/**
 * El entorno de producción. Lo sustituye `fileReplacements` al construir con
 * `--configuration production`.
 *
 * SIGUE APUNTANDO AL MISMO PROYECTO DE SUPABASE que desarrollo, y eso es
 * deliberado mientras el producto esté en sandbox (Art. 13): hay un solo
 * proyecto, con datos de demo dentro. El día que se abra la venta real, esto
 * apunta a un proyecto NUEVO y vacío — no se «limpia» el de desarrollo, porque
 * un `delete` a mano sobre datos mezclados es la forma más fácil de borrar algo
 * que no tocaba.
 *
 * La `publishable key` va en el bundle a propósito: es pública por diseño,
 * identifica al proyecto y entra como rol `anon` o `authenticated`. Lo que
 * protege los datos es la RLS. La `service_role` NO aparece aquí ni en ningún
 * archivo del front (Art. 9.3) — lo que necesita privilegio vive en una Edge
 * Function.
 */
export const environment = {
  production: true,
  supabaseUrl: 'https://orirleaujhpewiowaanq.supabase.co',
  supabasePublishableKey: 'sb_publishable_K1B29OwvqXggI9JiKvAL9g_zd26MUP6',
} as const;
