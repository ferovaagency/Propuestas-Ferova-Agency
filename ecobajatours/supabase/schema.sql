-- ECOBAJATOURS · Reservas, cuentas de cliente y portal de admin
-- Aplicar una sola vez en un proyecto de Supabase nuevo (SQL Editor o migración).
--
-- Horarios: pickup_at y return_pickup_at son hora local de Los Cabos
-- (America/Mazatlan) y se guardan sin zona horaria a propósito, para que la
-- hora que escribe el admin sea exactamente la que ve el cliente.

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
  full_name  text,
  email      text,
  phone      text,
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

-- El cliente solo puede cambiar su nombre y teléfono, no el correo ni el id.
revoke update on public.profiles from authenticated;
grant update (full_name, phone) on public.profiles to authenticated;

-- Crear el perfil automáticamente al registrarse (correo o Google).
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, email, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    new.email,
    nullif(new.raw_user_meta_data ->> 'phone', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- ---------------------------------------------------------------- reservas
create or replace function private.gen_booking_code()
returns text
language sql
volatile
set search_path = ''
as $$
  select 'EBT-' || upper(substr(md5(gen_random_uuid()::text), 1, 6));
$$;
grant execute on function private.gen_booking_code() to authenticated;

create table public.bookings (
  id                uuid primary key default gen_random_uuid(),
  code              text not null unique default private.gen_booking_code(),
  user_id           uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  arrival_flight    text not null check (char_length(arrival_flight) between 2 and 12),
  arrival_date      date not null,
  return_flight     text check (return_flight is null or char_length(return_flight) between 2 and 12),
  return_date       date,
  vehicle_type      text not null check (vehicle_type in ('sedan', 'suburban', 'van', 'shared')),
  passengers        int  not null check (passengers between 1 and 10),
  destination       text not null check (char_length(destination) between 2 and 120),
  estimated_mxn     numeric(10, 2),
  estimated_usd     numeric(10, 2),
  status            text not null default 'pending'
                      check (status in ('pending', 'confirmed', 'completed', 'cancelled')),
  pickup_at         timestamp,
  return_pickup_at  timestamp,
  customer_message  text,
  locale            text not null default 'es' check (locale in ('es', 'en')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (return_date is null or return_date >= arrival_date)
);
create index bookings_user_id_idx      on public.bookings (user_id);
create index bookings_arrival_date_idx on public.bookings (arrival_date);
create index bookings_status_idx       on public.bookings (status);
alter table public.bookings enable row level security;

create policy "bookings: el dueño o un admin pueden leer"
  on public.bookings for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));

create policy "bookings: el cliente crea reservas a su nombre"
  on public.bookings for insert to authenticated
  with check (user_id = (select auth.uid()) or (select private.is_admin()));

create policy "bookings: solo admins editan"
  on public.bookings for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy "bookings: solo admins borran"
  on public.bookings for delete to authenticated
  using ((select private.is_admin()));

-- Un cliente no puede fijarse estado, hora de recogida ni mensaje del equipo.
create or replace function private.bookings_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and not private.is_admin() then
    new.user_id          := auth.uid();
    new.code             := private.gen_booking_code();
    new.status           := 'pending';
    new.pickup_at        := null;
    new.return_pickup_at := null;
    new.customer_message := null;
    new.created_at       := now();
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger bookings_guard
  before insert or update on public.bookings
  for each row execute function private.bookings_guard();

-- ---------------------------------------------------------------- notas internas
-- Separadas de bookings para que el cliente nunca pueda leerlas.
create table public.booking_internal_notes (
  booking_id uuid primary key references public.bookings (id) on delete cascade,
  notes      text,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);
alter table public.booking_internal_notes enable row level security;

create policy "notas internas: solo admins"
  on public.booking_internal_notes for all to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

-- ---------------------------------------------------------------- permisos
revoke all on public.admins, public.profiles, public.bookings, public.booking_internal_notes from anon;

-- ---------------------------------------------------------------- cómo agregar un admin
-- La persona primero crea su cuenta en el sitio (correo o Google). Luego:
--   insert into public.admins (user_id)
--   select id from auth.users where email = 'correo@dominio.com';
