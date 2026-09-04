// La pasarela de mentira. Solo para el entorno de pruebas.
//
// Un sandbox de verdad —Culqi, Stripe— da tarjetas que aprueban siempre y
// llaman a tu webhook al instante. Aquí no hay pasarela conectada, así que el
// checkout se quedaba en `awaiting_payment` esperando una confirmación que
// nunca llegaba: la cadena completa —comprar, emitir, mostrar el QR, validar en
// puerta— no se podía recorrer entera ni una vez.
//
// Esta función ocupa ese hueco. Hace lo que haría el webhook: llamar a
// `confirm_payment`, que emite los tickets en una transacción.
//
// ── LO QUE NO HACE, Y POR QUÉ IMPORTA ──────────────────────────────────────
//
// No cobra. No habla con ningún banco. No sustituye a `payment-webhook`, que
// sigue siendo el que atenderá a la pasarela real y verifica una firma HMAC.
//
// ── CÓMO SE APAGA SOLA ─────────────────────────────────────────────────────
//
// El riesgo evidente de una función así es que sobreviva al día en que se
// conecte el cobro real: entonces cualquiera con sesión se emitiría entradas
// gratis. Por eso no depende de que alguien se acuerde de borrarla.
//
// Antes de confirmar nada comprueba si en la base existe ALGÚN pago cuyo
// `provider` no sea de sandbox. En cuanto entre el primer cobro real, esta
// función empieza a responder 403 y deja de funcionar para siempre — sin que
// nadie tenga que hacer nada.
//
// Es una defensa imperfecta: alguien podría estrenar la pasarela real y, hasta
// el primer cobro, esto seguiría abierto. Cerrarla del todo exige un secreto de
// entorno que haya que poner a mano, y eso es lo correcto para producción. Para
// una demo, apagarse sola en el primer pago real es la protección que se paga
// con cero pasos de configuración — que es justo lo que se olvida.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { json, preflight } from '../_shared/cors.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;

/** Los `provider` que cuentan como entorno de pruebas. */
const SANDBOX = ['culqi_sandbox', 'sandbox_manual'];

Deno.serve(async (req: Request) => {
  // El preflight va primero: si no se contesta, el POST no llega a salir.
  const pre = preflight(req);
  if (pre) return pre;

  if (req.method !== 'POST') return json({ error: 'método no permitido' }, 405);

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader) return json({ error: 'no autenticado' }, 401);

  let orderId: string;
  try {
    ({ order_id: orderId } = await req.json());
  } catch {
    return json({ error: 'cuerpo ilegible' }, 400);
  }
  if (!orderId) return json({ error: 'falta order_id' }, 400);

  // Quién llama lo dice el JWT, no el cuerpo. Y la RLS de `orders` decide qué
  // órdenes ve: si esta consulta vuelve vacía, o no es suya o no existe — y en
  // los dos casos la respuesta es la misma, para no convertir esto en un oráculo
  // que permita enumerar órdenes ajenas.
  const asUser = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  const { data: orden } = await asUser
    .from('orders')
    .select('id, status, total_cents, code')
    .eq('id', orderId)
    .maybeSingle();

  if (!orden) return json({ error: 'no tienes acceso a ese pedido' }, 403);

  const asService = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  // El interruptor de seguridad descrito arriba.
  const { data: real } = await asService
    .from('payments')
    .select('provider')
    .not('provider', 'in', `(${SANDBOX.join(',')})`)
    .limit(1);

  if (real && real.length > 0) {
    return json(
      {
        error:
          'este proyecto ya tiene pagos reales: el pago simulado está desactivado. ' +
          'Usa la pasarela y su webhook.',
      },
      403,
    );
  }

  // `paid` no es un error: el webhook de una pasarela reintenta, y esta función
  // imita a un webhook. Se responde lo mismo que la primera vez.
  if (orden.status === 'paid') {
    return json({ ok: true, already: true, order_code: orden.code });
  }

  if (orden.status !== 'awaiting_payment' && orden.status !== 'reserved') {
    return json({ error: `este pedido está en ${orden.status} y no admite pago` }, 409);
  }

  // El `provider_ref` dice a las claras de dónde salió, y es único por orden: si
  // esto se llama dos veces, el índice de idempotencia de `payments` lo para en
  // seco y `confirm_payment` devuelve los tickets ya emitidos en vez de duplicar.
  const { data, error } = await asService.rpc('confirm_payment', {
    p_order_id: orderId,
    p_provider_ref: `sandbox_${orden.code}`,
    p_amount_cents: orden.total_cents,
    p_provider: 'sandbox_manual',
    p_raw: { simulado: true, en: new Date().toISOString() },
  });

  if (error) return json({ error: error.message }, 400);

  return json({ ok: true, tickets: data, order_code: orden.code });
});
