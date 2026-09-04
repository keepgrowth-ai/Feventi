// 006 · qr-validate — la decisión de puerta.
//
// El reparto es deliberado: esta función sabe de criptografía y la base sabe de
// estado. Aquí se verifica el HMAC —porque el secreto solo es alcanzable con
// service_role— y se calcula la distancia de slots; todo lo demás —bloquear el
// ticket, marcarlo usado y anotar el checkin— lo hace `gate_checkin` en UNA
// transacción, porque si se hiciera aquí serían tres viajes y dos puertas
// escaneando a la vez producirían dos ACCESO PERMITIDO.
//
// verify_jwt = true: quien llama es el staff, con su sesión. Quién es lo dice el
// JWT, no el cuerpo de la petición — si el cuerpo pudiera decirlo, cualquiera
// firmaría checkins con el nombre de otro.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  SLOT_SECONDS,
  byteaToBytes,
  currentSlot,
  macMatches,
  parseToken,
} from '../_shared/qr.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'método no permitido' }, 405);

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader) return json({ error: 'no autenticado' }, 401);

  let body: { event_id?: string; token?: string; ticket_id?: string; mode?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'cuerpo ilegible' }, 400);
  }

  const eventId = body.event_id;
  const mode = body.mode === 'dni' ? 'dni' : 'qr';
  if (!eventId) return json({ error: 'falta event_id' }, 400);
  if (mode === 'qr' && !body.token) return json({ error: 'falta token' }, 400);
  if (mode === 'dni' && !body.ticket_id) return json({ error: 'falta ticket_id' }, 400);

  const asUser = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: auth } = await asUser.auth.getUser();
  const staffId = auth?.user?.id;
  if (!staffId) return json({ error: 'no autenticado' }, 401);

  const asService = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  let ticketId: string | null = null;
  let macOk = false;
  let slotDelta: number | null = null;

  if (mode === 'dni') {
    // D-03. La búsqueda por documento ya la hizo el staff con `gate_find_by_dni`,
    // que comprueba su asignación; aquí solo llega el ticket elegido. No hay MAC
    // que verificar: la identidad la comprobó una persona mirando un carné, y
    // por eso el resultado es siempre `manual_review`.
    ticketId = body.ticket_id!;
    macOk = true;
  } else {
    const parsed = parseToken(body.token!);
    if (parsed) {
      // El secreto solo se alcanza con service_role, y solo para esto.
      const { data: row } = await asService
        .from('ticket_secrets')
        .select('secret')
        .eq('ticket_id', parsed.ticketId)
        .maybeSingle();

      if (row?.secret && (await macMatches(parsed, byteaToBytes(row.secret)))) {
        macOk = true;
        ticketId = parsed.ticketId;
        // Positivo = el token viene del futuro (reloj adelantado); negativo = del
        // pasado. Fuera de ±1 solo puede ser una captura, y `gate_checkin` lo
        // marca `screenshot_suspected` en vez de «QR inválido».
        slotDelta = parsed.slot - currentSlot();
      }
      // MAC que no cuadra: `macOk` sigue false y el ticket_id NO se propaga. Un
      // token con un uuid real y una firma falsa no debe ensuciar la bitácora de
      // ese ticket con un intento que nunca fue suyo.
    }
  }

  const { data, error } = await asService.rpc('gate_checkin', {
    p_staff_id: staffId,
    p_event_id: eventId,
    p_ticket_id: ticketId,
    p_scanned_code: mode === 'qr' ? body.token : null, // AC-24: el token crudo
    p_mac_ok: macOk,
    p_slot_delta: slotDelta,
    p_mode: mode,
  });

  if (error) {
    // 42501 es «no eres staff» o «fuera de turno». Es un 403 de verdad, no un
    // fallo del servidor: la pantalla tiene que mandar al staff a «Mis eventos»,
    // no invitarle a reintentar.
    const forbidden = error.code === '42501' || /staff|turno/i.test(error.message ?? '');
    return json({ error: error.message ?? 'no se pudo validar' }, forbidden ? 403 : 400);
  }

  return json({ ...data, slot_seconds: SLOT_SECONDS });
});
