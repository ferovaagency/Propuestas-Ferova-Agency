# Reservas con cuenta · ECOBAJATOURS

Cómo conectar la propuesta 1 (`propuesta-1-sitio-completo.html` / `tarifas.html`) y el
portal de admin (`admin.html`) a Supabase.

## Qué hace

- **Reserva tu traslado / Reserve your ride**: formulario con vuelo de llegada, vuelo de
  regreso (opcional), fechas, destino, tipo de transporte y número de personas. Al enviarlo
  se crea la cuenta del cliente (correo y contraseña, o Google) y se guarda la reserva.
- **Mi cuenta** (`#/es/account`): el cliente ve el estado de cada reserva, su código
  `EBT-XXXXXX`, la hora de recogida y el mensaje del equipo.
- **admin.html**: el equipo ve las reservas, las confirma, asigna la hora de recogida,
  deja un mensaje al cliente y notas internas, ve los usuarios registrados y exporta CSV.

## Pasos para activarlo

1. **Crear el proyecto de Supabase** (plan gratis) llamado `ECOBAJATOURS`.
2. **Aplicar el esquema**: pegar [`schema.sql`](schema.sql) en *SQL Editor* y ejecutarlo.
3. **Conectar el sitio**: en *Project Settings → API* copiar la URL del proyecto y la clave
   publicable (`sb_publishable_...` o `anon`) en [`../js/ecoba-config.js`](../js/ecoba-config.js).
   Son públicas por diseño; la seguridad está en las políticas RLS del esquema.
4. **URLs de autenticación** (*Authentication → URL Configuration*):
   - *Site URL*: el dominio final, por ejemplo `https://ecobajatours.vercel.app/propuesta-1-sitio-completo.html`.
   - *Redirect URLs*: agregar las páginas que inician sesión:
     `https://<dominio>/propuesta-1-sitio-completo.html`, `https://<dominio>/tarifas.html`,
     `https://<dominio>/admin.html` (y `http://localhost:5173/**` para pruebas).
5. **Google** (*Authentication → Providers → Google*):
   1. En Google Cloud Console → *APIs & Services → Credentials* crear un
      *OAuth client ID* de tipo *Web application*.
   2. En *Authorized redirect URIs* poner la URL de callback que muestra Supabase
      (`https://<ref>.supabase.co/auth/v1/callback`).
   3. Pegar el *Client ID* y el *Client secret* en Supabase y activar el proveedor.
6. **Confirmación de correo**: por defecto Supabase pide confirmar el correo. La reserva queda
   guardada en el navegador y se registra sola cuando el cliente confirma desde ese mismo
   navegador. Si se prefiere que la reserva se guarde al instante, desactivar
   *Authentication → Providers → Email → Confirm email*. El servidor de correo gratuito de
   Supabase envía pocos correos por hora; para producción conviene configurar SMTP propio.
7. **Primer admin**: la persona crea su cuenta en el sitio y luego se ejecuta:

   ```sql
   insert into public.admins (user_id)
   select id from auth.users where email = 'correo@dominio.com';
   ```

## Notas

- Las horas de recogida se guardan como hora local de Los Cabos, tal cual las escribe el admin.
- Un cliente no puede cambiar el estado, la hora de recogida ni el mensaje de su reserva:
  lo impide el trigger `bookings_guard` aunque alguien llame a la API directamente.
- Las notas internas viven en otra tabla (`booking_internal_notes`) que solo leen los admins.
- `admin.html` no aparece enlazado en el sitio público y tiene `noindex`.
