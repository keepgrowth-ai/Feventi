// 005 · qr-token — prueba contra el proyecto REAL, no contra un doble.
//
//   node supabase/tests/005_qr_token.mjs
//
// Por qué no va en SQL como las demás suites: el token se emite en una Edge
// Function, y lo que hay que verificar es su comportamiento HTTP — códigos de
// estado, qué revela cada rechazo, y que dos llamadas dentro del mismo slot den
// el mismo token. Eso no se puede comprobar desde dentro de Postgres.
//
// Necesita la semilla `supabase/seed/demo_kpop.sql` y su compra: un ticket con
// el QR disponible y otro `too_early`. Los dos estados hacen falta.
//
// Una trampa que costó un rato: el cuerpo de la respuesta trae su propio
// `status` (el del ticket, `active`). Con `{ status: r.status, ...j }` el spread
// pisaba el código HTTP y AC-04 fallaba con el mensaje correcto. Por eso el
// campo se llama `http`.
const K = 'sb_publishable_K1B29OwvqXggI9JiKvAL9g_zd26MUP6';
const B = 'https://orirleaujhpewiowaanq.supabase.co';

const res = [];
const check = (ac, pass, detail) => res.push({ ac, pass, detail });

const tok = await (
  await fetch(`${B}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: K, 'content-type': 'application/json' },
    body: JSON.stringify({
      email: 'feventi.e2e.compra@gmail.com',
      password: 'Feventi-e2e-2026!',
    }),
  })
).json();

const JWT = tok.access_token;
if (!JWT) {
  console.log('sin token:', JSON.stringify(tok).slice(0, 120));
  process.exit(1);
}
const H = { apikey: K, authorization: `Bearer ${JWT}`, 'content-type': 'application/json' };

// ── La wallet ───────────────────────────────────────────────────────────────
const wallet = await (
  await fetch(
    `${B}/rest/v1/v_my_tickets?select=id,code,event_title,zone_name,row_label,seat_number,qr_state,holder_name,qr_available_from&order=code`,
    { headers: H },
  )
).json();

console.log('=== wallet ===');
for (const t of wallet) {
  console.log(
    `  ${t.code}  ${t.qr_state.padEnd(10)} ${t.zone_name}` +
      (t.row_label ? ` ${t.row_label}-${t.seat_number}` : '') +
      (t.holder_name ? `  · ${t.holder_name}` : '  · sin nominar'),
  );
}
check('la wallet devuelve los tickets del fan', wallet.length >= 3, `${wallet.length} tickets`);
check(
  'todos con qr_state resuelto',
  wallet.every((t) => t.qr_state),
  [...new Set(wallet.map((t) => t.qr_state))].join(', '),
);

// El ticket cuyo QR YA está disponible. Los demás son `too_early` a propósito:
// el K-Pop Fest es en 60 días y el QR abre 14 antes, que es exactamente lo que
// el Art. 2.5 manda.
const conQr = wallet.find((t) => t.qr_state === 'available');
const temprano = wallet.find((t) => t.qr_state === 'too_early');
if (!conQr) {
  console.log('no hay ningún ticket con el QR disponible; corre la semilla');
  process.exit(1);
}
const id = conQr.id;
check(
  'la wallet distingue disponible de too_early',
  !!conQr && !!temprano,
  `${wallet.filter((t) => t.qr_state === 'available').length} disponibles, ` +
    `${wallet.filter((t) => t.qr_state === 'too_early').length} todavía no`,
);
// `http` y no `status`: el cuerpo trae su propio `status` (el del ticket), y con
// `{ status: r.status, ...j }` el spread lo pisaba. Un falso negativo que costó
// un rato: la función devolvía 409 correctamente y la prueba leía 'active'.
const qr = (body) =>
  fetch(`${B}/functions/v1/qr-token`, {
    method: 'POST',
    headers: H,
    body: JSON.stringify(body),
  }).then((r) => r.json().then((j) => ({ ...j, http: r.status })));

// ── El token ────────────────────────────────────────────────────────────────
//
// Antes de comparar, esperar a un slot FRESCO. Si quedan 2 s, la segunda llamada
// cruza el borde y AC-06 sale «no concluyente» — y una prueba que a veces no
// concluye no es una prueba.
let a = await qr({ ticket_id: id });
if (a.expires_in < 10) {
  await new Promise((r) => setTimeout(r, (a.expires_in + 1) * 1000));
  a = await qr({ ticket_id: id });
}
console.log('\n=== token ===');
console.log(`  ${a.token}`);
console.log(`  ${a.token?.length} caracteres · slot ${a.slot} · expira en ${a.expires_in}s`);

check('AC-08 el servidor dice cuántos segundos faltan', a.expires_in > 0 && a.expires_in <= 30, `${a.expires_in}s`);
check(
  'AC-09 la respuesta NO trae el secreto',
  !JSON.stringify(a).match(/secret/i),
  'ni entero ni truncado',
);
check('el token mide 51 caracteres (38 bytes en base64url)', a.token?.length === 51, `${a.token?.length}`);

// AC-06: mismo slot → mismo token
const b = await qr({ ticket_id: id });
check(
  'AC-06 dos llamadas en el mismo slot dan el MISMO token',
  a.slot === b.slot && a.token === b.token,
  `slot ${a.slot}, token idéntico`,
);

// AC-07: el token cambia al cruzar el borde
const espera = a.expires_in + 1;
console.log(`\n=== AC-07 · esperando ${espera}s al borde del slot ===`);
await new Promise((r) => setTimeout(r, espera * 1000));
const c = await qr({ ticket_id: id });
check(
  'AC-07 al cruzar el borde del slot, el token CAMBIA',
  c.slot === a.slot + 1 && c.token !== a.token,
  `slot ${a.slot} → ${c.slot}`,
);
check(
  'y el ticket_id embebido no cambia',
  c.token.slice(0, 22) === a.token.slice(0, 22),
  'los primeros 16 bytes son el uuid del ticket',
);

// ── Los rechazos ────────────────────────────────────────────────────────────
const ajeno = await qr({ ticket_id: '11111111-2222-4333-8444-555555555555' });
check('AC-01 un ticket ajeno da 403', ajeno.http === 403, ajeno.error);
check(
  'AC-01b …y NO revela si existe',
  !/existe|not found|no encontrad/i.test(ajeno.error ?? ''),
  'un 404 distinto de un 403 convierte la wallet en un oráculo',
);

// AC-04 · Art. 2.5: no basta con negarse, hay que decir DESDE CUÁNDO.
const pronto = await qr({ ticket_id: temprano.id });
check('AC-04 fuera de ventana da 409', pronto.http === 409, pronto.error);
check(
  'AC-04b …y dice desde cuándo estará disponible',
  !!pronto.available_from,
  pronto.available_from
    ? new Date(pronto.available_from).toLocaleDateString('es-PE')
    : 'sin fecha',
);
check('AC-04c y nombra el estado, no un error genérico', pronto.qr_state === 'too_early', pronto.qr_state);

const vacio = await qr({});
check('sin ticket_id da 400', vacio.http === 400, vacio.error);

const sinAuth = await fetch(`${B}/functions/v1/qr-token`, {
  method: 'POST',
  headers: { apikey: K, 'content-type': 'application/json' },
  body: JSON.stringify({ ticket_id: id }),
}).then((r) => r.status);
check('AC-02 sin sesión da 401', sinAuth === 401, `HTTP ${sinAuth}`);

// AC-10: ticket_secrets sigue inalcanzable
const secretos = await (
  await fetch(`${B}/rest/v1/ticket_secrets?select=secret`, { headers: H })
).json();
check('AC-10 ticket_secrets inalcanzable, ni para el dueño', secretos.code === '42501', secretos.message?.slice(0, 50));

// ── Resultado ───────────────────────────────────────────────────────────────
console.log('\n=== resultado ===');
for (const r of res) console.log(`  ${r.pass ? '✓' : '✗ FALLA'}  ${r.ac} — ${r.detail ?? ''}`);
const fallos = res.filter((r) => !r.pass).length;
console.log(`\n  ${res.length - fallos}/${res.length} en verde`);
process.exit(fallos ? 1 : 0);
