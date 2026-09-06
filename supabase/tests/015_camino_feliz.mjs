// El camino feliz entero, por HTTP, con los triggers de Fase 1.5 en medio.
//
// POR QUÉ ESTE ARCHIVO EXISTE
//
// 012 y 013 metieron dos triggers en el camino más caliente del producto:
//
//   · `tickets_assign_group_owner`  — BEFORE INSERT en `tickets`. Corre en cada
//     emisión, sea de grupo o no.
//   · `checkins_award_points`       — AFTER INSERT en `checkins`. Corre DENTRO
//     de la decisión de puerta: si lanzara, **la puerta falla**.
//
// Las suites `.sql` prueban los dos por separado, pero ninguna los atraviesa en
// la cadena real: reservar → pagar → emitir → pedir el QR → validarlo. Eso solo
// se ve pasando por PostgREST y por las dos Edge Functions, con un JWT de
// verdad. Es la lección de «007 llevaba rota desde 003», aplicada a tiempo.
//
// CONSUME una entrada de Zona Ritmo por pasada, y **no se limpia solo**: los
// tickets no se borran por la API, que es lo correcto. Antes de una demo, o
// tras varias pasadas, hay que devolver la cuenta a su estado sembrado — el
// propio script lo recuerda al terminar.
//
// Este archivo destapó dos cosas que ninguna suite `.sql` podía ver:
//
//   · el trabajo de pg_cron llevaba fallando cada noche, y la Preventa había
//     caducado dejando el Palco VIP sin tier a la venta;
//   · `reserve_order` contaba cada entrada pagada DOS veces contra el límite
//     por usuario, así que el tope real era la mitad del configurado (`0061`).
//
// Las dos aparecen solo comprando de verdad, dos veces, contra una base que
// conserva la primera compra.
//
// Correr con:  node supabase/tests/015_camino_feliz.mjs

const K = 'sb_publishable_K1B29OwvqXggI9JiKvAL9g_zd26MUP6';
const B = 'https://orirleaujhpewiowaanq.supabase.co';

const CAMILA = 'camila@feventi.demo';
const OPS = 'operaciones@feventi.demo';
const CLAVE = 'Feventi2026!';

const EVENTO = 'de000000-0000-4000-8000-00000000b001';
const TIER_CAMPO = 'de000000-0000-4000-8000-00000000e001';

const res = [];
const check = (ac, pass, detail) => res.push({ ac, pass, detail });

async function login(email) {
  const r = await (
    await fetch(`${B}/auth/v1/token?grant_type=password`, {
      method: 'POST',
      headers: { apikey: K, 'content-type': 'application/json' },
      body: JSON.stringify({ email, password: CLAVE }),
    })
  ).json();
  if (!r.access_token) throw new Error(`login ${email}: ${JSON.stringify(r)}`);
  return r.access_token;
}

const h = (jwt) => ({ apikey: K, authorization: `Bearer ${jwt}`, 'content-type': 'application/json' });

async function rest(jwt, path) {
  const r = await fetch(`${B}/rest/v1/${path}`, { headers: h(jwt) });
  return { http: r.status, body: await r.json().catch(() => null) };
}
async function rpc(jwt, fn, args) {
  const r = await fetch(`${B}/rest/v1/rpc/${fn}`, {
    method: 'POST', headers: h(jwt), body: JSON.stringify(args),
  });
  return { http: r.status, body: await r.json().catch(() => null) };
}
async function fn(jwt, name, body) {
  const r = await fetch(`${B}/functions/v1/${name}`, {
    method: 'POST', headers: h(jwt), body: JSON.stringify(body),
  });
  // El cuerpo trae su propio `result`; el código HTTP se guarda aparte y NUNCA
  // por spread — es la trampa heredada de 005.
  return { http: r.status, body: await r.json().catch(() => null) };
}

const jwt = await login(CAMILA);
const jwtOps = await login(OPS);

// ── 0 · El preflight, que fue el bug que ninguna suite vio ─────────────────
for (const f of ['qr-token', 'qr-validate', 'sandbox-pay']) {
  const r = await fetch(`${B}/functions/v1/${f}`, {
    method: 'OPTIONS',
    headers: {
      Origin: 'https://feventi-ur5fufx5da-uc.a.run.app',
      'Access-Control-Request-Method': 'POST',
    },
  });
  check(`CORS  ${f} contesta al preflight`, r.status === 204 || r.status === 200,
    `http ${r.status} — sin esto, el POST no llega a salir del navegador`);
}

// ── 1 · Reservar ───────────────────────────────────────────────────────────
const puntosAntes = (await rest(jwt, 'v_my_points?select=total')).body?.[0]?.total ?? 0;

const reserva = await rpc(jwt, 'reserve_order', {
  p_event_id: EVENTO,
  p_items: [{ tier_id: TIER_CAMPO, seat_id: null }],
});
const orderId = reserva.body;
check('E2E-01 reservar devuelve una orden', reserva.http < 300 && typeof orderId === 'string',
  `http ${reserva.http} · ${String(orderId).slice(0, 8)}…`);

// ── 2 · Nominar ────────────────────────────────────────────────────────────
const items = await rest(jwt, `order_items?order_id=eq.${orderId}&select=id`);
const itemId = items.body?.[0]?.id;
const nom = await rpc(jwt, 'set_item_attendee', {
  p_item_id: itemId, p_name: 'Camila Torres', p_dni: '70418412',
});
check('E2E-02 nominar la entrada', nom.http < 300, `http ${nom.http}`);

// ── 3 · Pagar (la pasarela de mentira hace de webhook) ─────────────────────
const pago = await fn(jwt, 'sandbox-pay', { order_id: orderId });
check('E2E-03 el pago simulado confirma la orden', pago.http < 300 && pago.body?.ok === true,
  `http ${pago.http} · ${JSON.stringify(pago.body).slice(0, 90)}`);

// ── 4 · El ticket existe y es SUYO ─────────────────────────────────────────
// Aquí pasó `tickets_assign_group_owner`. Sin grupo detrás, no debe haber
// tocado nada: el dueño tiene que ser quien compró (012/AC-16, en vivo).
const wallet = await rest(jwt, `v_my_tickets?event_id=eq.${EVENTO}&select=id,code,qr_state,holder_name&order=issued_at.desc`);
const ticket = wallet.body?.[0];
check('E2E-04 la entrada aparece en la wallet, a nombre de quien compró',
  wallet.http === 200 && ticket?.holder_name === 'Camila Torres' && ticket?.qr_state === 'available',
  `${ticket?.code} · ${ticket?.qr_state} — el trigger de grupo no tocó una compra individual`);

// ── 5 · El QR ──────────────────────────────────────────────────────────────
const tok = await fn(jwt, 'qr-token', { ticket_id: ticket?.id });
check('E2E-05 el QR se emite y expira en menos de 30 s',
  tok.http === 200 && typeof tok.body?.token === 'string' && tok.body.expires_in <= 30,
  `slot ${tok.body?.slot} · quedan ${tok.body?.expires_in} s`);

// ── 6 · La puerta · aquí corre el trigger de puntos ────────────────────────
// `event_id` es obligatorio: el validador no deduce el evento del token, lo
// exige. Así un QR de otro evento se rechaza por `wrong_event` en vez de
// colarse en la puerta equivocada.
const val = await fn(jwtOps, 'qr-validate', {
  token: tok.body?.token, gate: 'Puerta A', event_id: EVENTO,
});
check('E2E-06 la puerta permite el acceso',
  val.http === 200 && val.body?.result === 'allowed',
  `${val.body?.result} · ${val.body?.reason}`);

// ── 7 · Y el segundo escaneo, que es el momento de la demo ─────────────────
const val2 = await fn(jwtOps, 'qr-validate', {
  token: tok.body?.token, gate: 'Puerta A', event_id: EVENTO,
});
check('E2E-07 el mismo QR, otra vez: YA UTILIZADO',
  val2.body?.result === 'already_used',
  `${val2.body?.result} · una entrada entra una vez`);

// ── 8 · Los puntos, que es lo que este archivo vino a comprobar ────────────
const puntosDespues = (await rest(jwt, 'v_my_points?select=total')).body?.[0]?.total ?? 0;
check('E2E-08 el check-in permitido sumó 50 puntos',
  puntosDespues === puntosAntes + 50,
  `${puntosAntes} → ${puntosDespues}`);

check('E2E-09 el segundo escaneo NO sumó otros 50',
  puntosDespues === puntosAntes + 50,
  'escanear dos veces no paga dos veces (013/AC-02)');

// ── 9 · Y la señal social sigue en pie después de todo ─────────────────────
const senal = await rest(jwt, `v_my_event_signals?event_id=eq.${EVENTO}`);
check('E2E-10 la señal social no se rompió por el camino',
  senal.http === 200 && senal.body?.[0]?.friends_going === 1,
  `van ${senal.body?.[0]?.friends_going} · quieren ${senal.body?.[0]?.friends_interested}`);

// ── Resultado ──────────────────────────────────────────────────────────────
const fallos = res.filter((r) => !r.pass).length;
for (const r of res) {
  console.log(`${r.pass ? '✓' : '✗ FALLA'}  ${r.ac}`);
  console.log(`         ${r.detail}`);
}
console.log(`\n${res.length - fallos}/${res.length} en verde`);
process.exit(fallos ? 1 : 0);
