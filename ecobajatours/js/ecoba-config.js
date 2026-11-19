// Conexión pública a Supabase para ECOBAJATOURS.
// La URL y la clave publicable (anon / sb_publishable_...) son públicas por diseño:
// la seguridad la dan las políticas RLS de supabase/schema.sql.
// Mientras estén vacías, el sitio muestra el formulario pero avisa que las
// reservas todavía no están conectadas.
window.ECOBA_CONFIG = {
  supabaseUrl: "",
  supabaseKey: ""
};
