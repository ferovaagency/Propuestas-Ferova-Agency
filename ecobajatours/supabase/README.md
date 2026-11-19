# Cuentas de cliente y admin de usuarios · ECOBAJATOURS

Qué incluye la propuesta 1 (`propuesta-1-sitio-completo.html` / `tarifas.html`) y
`admin.html`, y cómo conectarlos.

## Qué hace

- **Reserva tu traslado / Reserve your ride**: formulario con vuelo de llegada, vuelo de
  regreso (opcional), fechas, destino, tipo de transporte, número de personas y WhatsApp.
  Al enviarlo se crea o se inicia la cuenta del cliente (correo y contraseña, o Google) y la
  reserva se **envía al gestor de reservas de ECOBAJATOURS**. El sitio no guarda reservas.
- **Mi cuenta** (`#/es/account`): inicio de sesión, registro y los datos de contacto del
  cliente (nombre y teléfono editables).
- **admin.html**: usuarios registrados, con búsqueda, filtro por tipo de acceso, detalle,
  edición de nombre y teléfono, y exportación a CSV.

## Envío al gestor de reservas

`bookingEndpoint` en [`../js/ecoba-config.js`](../js/ecoba-config.js) es la URL del gestor.
El formulario hace un `POST` con `Content-Type: application/json`:

```json
{
  "request_id": "6f1c2a4e-…",
  "submitted_at": "2026-11-19T17:08:41.740Z",
  "source": "ecobajatours-web",
  "locale": "es",
  "customer": { "user_id": "…", "name": "Nombre Apellido", "email": "cliente@dominio.com", "phone": "+52 624 000 0000" },
  "trip": {
    "arrival_flight": "AM 1234", "arrival_date": "2026-12-10",
    "return_flight": "AM 1235", "return_date": "2026-12-17",
    "destination": "ZONA CENTRO SAN JOSE DEL CABO",
    "vehicle_type": "suburban", "passengers": 5
  },
  "estimate": { "mxn": 1450, "usd": 90 }
}
```

- `vehicle_type`: `sedan`, `suburban`, `van` o `shared`. Fechas en `YYYY-MM-DD`.
- `return_flight` y `return_date` pueden venir en `null`. `estimate` es la tarifa de
  referencia de octubre de 2026 (`null` si la ruta es "a consultar").
- `request_id` es único por envío: sirve para ignorar duplicados.
- Cualquier respuesta 2xx se toma como recibida. El endpoint debe permitir CORS desde el
  dominio del sitio. Si su gestor no acepta peticiones desde el navegador o pide una clave
  secreta, se pone una función intermedia (Vercel o Supabase Edge Function) que reciba este
  JSON y lo reenvíe; la clave no debe ir en el sitio.
- Mientras `bookingEndpoint` esté vacío, la cuenta se crea igual y el cliente ve un aviso con
  el WhatsApp de ECOBAJATOURS.

## Pasos para activar las cuentas

1. **Crear el proyecto de Supabase** (plan gratis) llamado `ECOBAJATOURS`.
2. **Aplicar el esquema**: pegar [`schema.sql`](schema.sql) en *SQL Editor* y ejecutarlo.
3. **Conectar el sitio**: en *Project Settings → API* copiar la URL del proyecto y la clave
   publicable (`sb_publishable_...` o `anon`) en `js/ecoba-config.js`. Son públicas por
   diseño; la seguridad está en las políticas RLS del esquema.
4. **URLs de autenticación** (*Authentication → URL Configuration*):
   - *Site URL*: el dominio final.
   - *Redirect URLs*: `https://<dominio>/propuesta-1-sitio-completo.html`,
     `https://<dominio>/tarifas.html`, `https://<dominio>/admin.html`
     (y `http://localhost:5173/**` para pruebas).
5. **Google** (*Authentication → Providers → Google*):
   1. En Google Cloud Console → *APIs & Services → Credentials* crear un
      *OAuth client ID* de tipo *Web application*.
   2. En *Authorized redirect URIs* poner la URL de callback que muestra Supabase
      (`https://<ref>.supabase.co/auth/v1/callback`).
   3. Pegar el *Client ID* y el *Client secret* en Supabase y activar el proveedor.
6. **Confirmación de correo**: por defecto Supabase pide confirmar el correo. La reserva
   queda guardada en el navegador y se envía sola cuando el cliente confirma desde ese mismo
   navegador (solo si entra con el mismo correo con el que llenó el formulario). Para que se
   envíe al instante, desactivar *Authentication → Providers → Email → Confirm email*. El
   correo gratuito de Supabase envía pocos mensajes por hora; para producción conviene SMTP propio.
7. **Primer admin**: la persona crea su cuenta en el sitio y luego se ejecuta:

   ```sql
   insert into public.admins (user_id)
   select id from auth.users where email = 'correo@dominio.com';
   ```

## Notas

- Eliminar una cuenta o restablecer su acceso se hace en Supabase → Authentication → Users.
- `admin.html` no aparece enlazado en el sitio público y tiene `noindex`.
