-- ECOBAJATOURS · Cuentas de cliente y admin de usuarios
-- Aplicar una sola vez en un proyecto de Supabase nuevo (SQL Editor o migración).
--
-- Las reservas NO se guardan aquí: el formulario las envía al gestor de reservas
-- de ECOBAJATOURS (ver bookingEndpoint en js/ecoba-config.js). Supabase solo maneja
-- el registro e inicio de sesión (correo o Google) y el listado de usuarios.

-- ---------------------------------------------------------------- esquema privado
create schema if not exists private;
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------- admins
create table public.admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.admins where user_id = (select auth.uid()));
$$;
revoke all on function private.is_admin() from public, anon;
grant execute on function private.is_admin() to authenticated;

-- Cada usuario puede saber si él mismo es admin; los admins ven la lista.
create policy "admins: ver la propia fila o todas si es admin"
  on public.admins for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));

-- ---------------------------------------------------------------- perfiles
create table public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  full_name  text check (full_name is null or char_length(full_name) <= 80),
  email      text,
  phone      text check (phone is null or char_length(phone) <= 25),
  provider   text,                       -- 'email' o 'google'
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

create policy "profiles: el dueño o un admin pueden leer"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select private.is_admin()));

create policy "profiles: el dueño o un admin pueden editar"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()) or (select private.is_admin()))
  with check (id = (select auth.uid()) or (select private.is_admin()));

-- Solo se pueden cambiar el nombre y el teléfono; el correo y el id vienen de la cuenta.
revoke insert, update, delete on public.profiles from authenticated;
grant update (full_name, phone) on public.profiles to authenticated;

-- Crear el perfil automáticamente al registrarse (correo o Google).
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, email, phone, provider)
  values (
    new.id,
    left(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'), 80),
    new.email,
    left(nullif(new.raw_user_meta_data ->> 'phone', ''), 25),
    coalesce(new.raw_app_meta_data ->> 'provider', 'email')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- ---------------------------------------------------------------- listado para el admin
-- Une el perfil con datos de la cuenta (último acceso, correo confirmado).
-- Solo responde a administradores.
create or replace function public.admin_list_users()
returns table (
  id                 uuid,
  full_name          text,
  email              text,
  phone              text,
  provider           text,
  created_at         timestamptz,
  last_sign_in_at    timestamptz,
  email_confirmed_at timestamptz,
  is_admin           boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  return query
    select p.id, p.full_name, coalesce(p.email, u.email)::text, p.phone, p.provider,
           p.created_at, u.last_sign_in_at, u.email_confirmed_at,
           exists (select 1 from public.admins a where a.user_id = p.id)
    from public.profiles p
    join auth.users u on u.id = p.id
    order by p.created_at desc;
end;
$$;
revoke all on function public.admin_list_users() from public, anon;
grant execute on function public.admin_list_users() to authenticated;

-- ---------------------------------------------------------------- permisos
revoke all on public.admins, public.profiles from anon;

-- ---------------------------------------------------------------- cómo agregar un admin
-- La persona primero crea su cuenta en el sitio (correo o Google). Luego:
--   insert into public.admins (user_id)
--   select id from auth.users where email = 'correo@dominio.com';
