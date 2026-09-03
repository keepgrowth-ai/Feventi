/**
 * Art. 9.3: aquí solo va la publishable key. La `service_role` no aparece jamás
 * en el bundle — lo que necesita privilegio vive en una Edge Function.
 *
 * La publishable key es pública por diseño: identifica al proyecto y entra como
 * rol `anon` o `authenticated`. Lo que protege los datos es la RLS, no el
 * secreto de esta cadena.
 */
export const environment = {
  production: false,
  supabaseUrl: 'https://orirleaujhpewiowaanq.supabase.co',
  supabasePublishableKey: 'sb_publishable_K1B29OwvqXggI9JiKvAL9g_zd26MUP6',
} as const;
