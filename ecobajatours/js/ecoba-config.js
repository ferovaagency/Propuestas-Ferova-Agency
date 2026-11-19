// Conexión pública a Supabase para ECOBAJATOURS.
// La URL y la clave publicable (anon / sb_publishable_...) son públicas por diseño:
// la seguridad la dan las políticas RLS de supabase/schema.sql.
// Mientras estén vacías, el sitio muestra el formulario pero avisa que las
// cuentas todavía no están conectadas.
//
// bookingEndpoint: URL del gestor de reservas de ECOBAJATOURS. El formulario
// "Reserva tu traslado" le envía un POST con JSON (ver supabase/README.md).
// El endpoint debe aceptar peticiones desde el dominio del sitio (CORS).
window.ECOBA_CONFIG = {
  supabaseUrl: "",
  supabaseKey: "",
  bookingEndpoint: ""
};
