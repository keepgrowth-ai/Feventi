// 005 · qr-token — emite el QR rotativo de un ticket. Art. 2.
//
// El secreto del ticket vive en `ticket_secrets`: RLS activa, CERO políticas.
// Ni anon, ni authenticated, ni el propietario pueden leerlo. Solo esta
// función, que corre con service_role. Es lo único que hace que un QR no se
// pueda fabricar desde fuera (Art. 2.6).
//
// verify_jwt = true: hace falta sesión, y el token se emite SOLO al dueño.
//
// El algoritmo está en ../_shared/qr.ts, compartido con qr-validate.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { json, preflight } from '../_shared/cors.ts';
import { SLOT_SECONDS, buildToken, byteaToBytes, currentSlot } from '../_shared/qr.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;

Deno.serve(async (req: Request) => {
  // El preflight va primero: si no se contesta, el POST no llega a salir.
  const pre = preflight(req);
  if (pre) return pre;

  if (req.method !== 'POST') return json({ error: 'método no permitido' }, 405);

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader) return json({ error: 'no autenticado' }, 401);

  let ticketId: string;
  try {
    ({ ticket_id: ticketId } = await req.json());
  } catch {
    return json({ error: 'cuerpo ilegible' }, 400);
  }
  if (!ticketId) return json({ error: 'falta ticket_id' }, 400);

  // Cliente CON el JWT del fan: la RLS decide qué tickets ve. Así la comprobación
  // de propiedad no depende de que esta función la recuerde.
  const asUser = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  const { data: ticket, error } = await asUser
    .from('v_my_tickets')
    .select('id, status, qr_state, qr_available_from, event_status, event_title, code')
    .eq('id', ticketId)
    .maybeSingle();

  if (error) return json({ error: 'no autenticado' }, 401);

  // AC-01: sin decir si el ticket existe. Un 404 distinto de un 403 convierte la
  // wallet en un oráculo para enumerar tickets ajenos.
  if (!ticket) return json({ error: 'no tienes acceso a esa entrada' }, 403);

  // AC-03, AC-04, AC-05: el motivo concreto, no un error genérico. El fan tiene
  // que saber si es cuestión de esperar o de escribir a soporte.
  if (ticket.qr_state !== 'available') {
    const motivo: Record<string, string> = {
      spent: 'Esta entrada ya se usó en puerta.',
      too_early: 'El QR todavía no está disponible.',
      disabled: 'El QR de esta entrada está inhabilitado.',
    };
    return json(
      {
        error: motivo[ticket.qr_state] ?? 'El QR no está disponible.',
        qr_state: ticket.qr_state,
        status: ticket.status,
        // Art. 2.5: decir DESDE CUÁNDO, no solo que no se puede.
        available_from: ticket.qr_available_from,
      },
      409,
    );
  }

  // Solo aquí se sube a service_role, y solo para leer el secreto.
  const asService = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const { data: row } = await asService
    .from('ticket_secrets')
    .select('secret')
    .eq('ticket_id', ticketId)
    .maybeSingle();

  if (!row?.secret) return json({ error: 'entrada sin credencial emitida' }, 409);

  const nowSec = Math.floor(Date.now() / 1000);
  const slot = currentSlot();
  const token = await buildToken(ticketId, slot, byteaToBytes(row.secret));

  // AC-08: los segundos que faltan los calcula el SERVIDOR. Si los dedujera el
  // cliente de su propio reloj, la cuenta atrás mentiría en cuanto hubiera
  // desfase — y esa cuenta atrás es lo que sostiene el mensaje de que el código
  // cambia.
  return json({
    token,
    slot,
    slot_seconds: SLOT_SECONDS,
    expires_in: SLOT_SECONDS - (nowSec % SLOT_SECONDS),
    // AC-09: el secreto NUNCA sale de aquí, ni entero ni truncado.
  });
});
