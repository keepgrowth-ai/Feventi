import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { environment } from '../../environments/environment';
import type { Database } from './db.types';

/**
 * Cliente único. `db.types.ts` está generado desde el schema (Art. 12.3):
 * `npm run gen:types`. Editarlo a mano es un error.
 */
export const supabase: SupabaseClient<Database> = createClient<Database>(
  environment.supabaseUrl,
  environment.supabasePublishableKey,
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  },
);
