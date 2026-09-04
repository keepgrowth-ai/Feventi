// Webhook de pago — la única pieza que llama a `confirm_payment`.
//
// Art. 9.3-9.4: lo que necesita privilegio vive aquí, no en el bundle de
// Angular. `confirm_payment` está revocada a `authenticated` a propósito
// (004/AC-29): un fan que la invoque falla, y hay una prueba que lo verifica.
//
// Art. 13: sandbox. Culqi de verdad exige cerrar antes las políticas de
// cancelación, reembolso, retenciones y liquidación — D-40 … D-49. El paso a
// producción es una decisión de negocio con documento firmado, no un despliegue.
//
// Desplegar:  supabase functions deploy payment-webhook --no-verify-jwt
//   `--no-verify-jwt` porque quien llama es la pasarela, no un usuario. La
//   autenticación es la FIRMA del cuerpo, no un JWT de Supabase.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { json, preflight } from '../_shared/cors.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
// Secreto compartido con la pasarela. Sin él, cualquiera que descubra la URL
// puede emitir tickets: la función corre con service_role.
const WEBHOOK_SECRET = Deno.env.get('FEVENTI_WEBHOOK_SECRET') ?? '';

interface PaymentEvent {
  /** Referencia del cargo en la pasarela. Es la clave de idempotencia. */
  readonly id: string;
  readonly status: 'succeeded' | 'failed';
  readonly order_id: string;
  readonly amount_cents: number;
  readonly provider?: string;
}

/**
 * Compara en tiempo constante.
 *
 * Con `===` la comparación corta en el primer byte distinto, y esa diferencia
 * de tiempo es medible: permite adivinar la firma byte a byte.
 */
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function hmacHex(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(body));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req: Request) => {
  // El preflight va primero: si no se contesta, el POST no llega a salir.
  const pre = preflight(req);
  if (pre) return pre;

  if (req.method !== 'POST') {
    return new Response('método no permitido', { status: 405 });
  }

  // El cuerpo se lee como TEXTO, no como JSON: la firma se calcula sobre los
  // bytes exactos que llegaron. Volver a serializar el objeto cambia el orden
  // de las claves y la firma deja de cuadrar.
  const raw = await req.text();

  if (!WEBHOOK_SECRET) {
    // Fallar cerrado. Sin secreto configurado, cualquiera que descubra la URL
    // emite tickets — y esta función corre con service_role.
    console.error('FEVENTI_WEBHOOK_SECRET no está configurado');
    return new Response('webhook no configurado', { status: 500 });
  }

  const firma = req.headers.get('x-feventi-signature') ?? '';
  const esperada = await hmacHex(WEBHOOK_SECRET, raw);
  if (!safeEqual(firma, esperada)) {
    return new Response('firma inválida', { status: 401 });
  }

  let evento: PaymentEvent;
  try {
    evento = JSON.parse(raw);
  } catch {
    return new Response('cuerpo ilegible', { status: 400 });
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false },
  });

  if (evento.status === 'failed') {
    // `failed` CONSERVA la reserva hasta reserved_until: un reintento con otra
    // tarjeta no debe perder los asientos.
    const { error } = await supabase.rpc('fail_payment', {
      p_order_id: evento.order_id,
      p_reason: 'rechazado por la pasarela',
    });
    if (error) console.error('fail_payment', error);
    return new Response(JSON.stringify({ ok: true }), {
      headers: { 'content-type': 'application/json' },
    });
  }

  // AC-21: idempotente por (provider, provider_ref). Un reintento del webhook
  // devuelve el conteo sin volver a emitir — y los webhooks REINTENTAN.
  const { data, error } = await supabase.rpc('confirm_payment', {
    p_order_id: evento.order_id,
    p_provider_ref: evento.id,
    p_amount_cents: evento.amount_cents,
    p_provider: evento.provider ?? 'culqi_sandbox',
    p_raw: evento as unknown as Record<string, unknown>,
  });

  if (error) {
    console.error('confirm_payment', error);
    // 400 y no 500: un 5xx hace que la pasarela reintente sin parar. Si el error
    // es de negocio —importe que no cuadra, orden en otro estado— reintentar no
    // lo arregla. La idempotencia cubre el caso en que sí valga la pena.
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { 'content-type': 'application/json' },
    });
  }

  return new Response(JSON.stringify({ ok: true, tickets: data }), {
    headers: { 'content-type': 'application/json' },
  });
});
