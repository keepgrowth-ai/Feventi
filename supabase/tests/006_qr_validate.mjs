// 006 Validador de puerta — la mitad que solo se puede probar por HTTP.
//
// `006_validador_puerta.sql` prueba la DECISIÓN llamando a `gate_checkin` con
// los parámetros ya calculados. Esto prueba lo otro: que un token REAL emitido
// por `qr-token` se verifica bien en `qr-validate`, y sobre todo **AC-09**, el
// doble escaneo simultáneo, que necesita dos peticiones de verdad en paralelo.
// Es la comprobación que, si falla, se descubre con dos personas dentro y una
// sola entrada vendida.
//
// Antes de correr: aplicar `supabase/seed/demo_puerta.sql`. Cada pasada CONSUME
// entradas; la semilla es reejecutable justamente para eso.
//
// TRAMPA DEL ARNÉS heredada de 005: el cuerpo de la respuesta trae su propio
// `result`/`reason`, así que el código HTTP se guarda como `http` y nunca por
// spread — `{ status: r.status, ...j }` deja que el cuerpo pise el código.

const K = 'sb_publishable_K1B29OwvqXggI9JiKvAL9g_zd26MUP6';
const B = 'https://orirleaujhpewiowaanq.supabase.co';

const EVENTO = 'd6000000-0000-4000-8000-000000000001';
const T = {
  ok: 'd6000000-0000-4000-8000-000000000061',
  dni: 'd6000000-0000-4000-8000-000000000062',
  sinNominar: 'd6000000-0000-4000-8000-000000000063',
  doble: 'd6000000-0000-4000-8000-000000000064',
  vip: 'd6000000-0000-4000-8000-000000000065',
};

const res = [];
const check = (ac, pass, detail) => res.push({ ac, pass, detail });

async function login(email, password) {
  const r = await (
    await fetch(`${B}/auth/v1/token?grant_type=password`, {
      method: 'POST',
      headers: { apikey: K, 'content-type': 'application/json' },
      body: JSON.stringify({ email, password }),
    })
  ).json();
  if (!r.access_token) {
    console.log(`sin sesión para ${email}:`, JSON.stringify(r).slice(0, 160));
    process.exit(1);
  }
  return { apikey: K, authorization: `Bearer ${r.access_token}`, 'content-type': 'application/json' };
}

const FAN = await login('feventi.e2e.compra@gmail.com', 'Feventi-e2e-2026!');
const STAFF = await login('feventi.e2e.puerta@gmail.com', 'Feventi-e2e-2026!');

const post = (fn, headers, body) =>
  fetch(`${B}/functions/v1/${fn}`, { method: 'POST', headers, body: JSON.stringify(body) })
    .then((r) => r.json().then((j) => ({ ...j, http: r.status })));

/** El QR que vería el fan en su wallet, para este ticket, ahora mismo. */
const tokenDe = async (ticketId) => (await post('qr-token', FAN, { ticket_id: ticketId })).token;
const validar = (body) => post('qr-validate', STAFF, { event_id: EVENTO, ...body });

// ── Lo que el staff ve al abrir la app ──────────────────────────────────────
const misEventos = await (
  await fetch(
    `${B}/rest/v1/v_my_gate_events?select=event_id,title,gate,zone_name,venue_name,shift_active,starts_at`,
    { headers: STAFF },
  )
).json();

console.log('=== mis eventos ===');
for (const e of misEventos) {
  console.log(`  ${e.title} · ${e.gate}${e.zone_name ? ` (${e.zone_name})` : ''} · en turno: ${e.shift_active}`);
}

check('AC-06 el staff ve su evento, con su puerta', misEventos.length >= 1 && !!misEventos[0].gate,
  `${misEventos.length} evento(s)`);
check('AC-03 y la vista dice que está EN turno', misEventos.some((e) => e.shift_active),
  'la semilla coloca puertas hace 30 min');

// El staff NO ve dinero (AC-07).
const ordenes = await (await fetch(`${B}/rest/v1/orders?select=id,total_cents`, { headers: STAFF })).json();
check('AC-07 el staff no lee ninguna orden', Array.isArray(ordenes) && ordenes.length === 0,
  `${Array.isArray(ordenes) ? ordenes.length : '?'} filas`);

// ── El camino feliz, con un token de verdad ─────────────────────────────────
const tk = await tokenDe(T.ok);
const a = await validar({ token: tk });

console.log('\n=== escaneo ===');
console.log(`  ${a.result} · ${a.reason} · ${a.ticket?.code} · ${a.ticket?.holder_name}`);

check('AC-08 un token real y vigente da ACCESO PERMITIDO', a.result === 'allowed' && a.reason === 'ok',
  `${a.result} / ${a.reason}`);
check('AC-08b y la respuesta trae lo que el staff tiene que leer en voz alta',
  !!a.ticket?.code && !!a.ticket?.zone_name, `${a.ticket?.zone_name} · ${a.ticket?.code}`);
check('AC-20 nombre y últimos 4 del DNI, NUNCA el hash',
  a.ticket?.dni_last4 === '3456' && !JSON.stringify(a).match(/hash/i),
  `••••${a.ticket?.dni_last4}`);

// AC-10: el mismo token otra vez.
const b = await validar({ token: tk });
check('AC-10 el mismo QR otra vez da YA UTILIZADO, con hora y puerta del primero',
  b.result === 'already_used' && b.first_gate === 'Puerta A' && !!b.first_at,
  `entró por ${b.first_gate} a las ${b.first_at ? new Date(b.first_at).toLocaleTimeString('es-PE') : '?'}`);

// ── AC-09 · dos puertas leyendo a la vez ────────────────────────────────────
//
// Lo que de verdad protege el `select … for update`. Sin él, las dos lecturas
// ven `active` y las dos dejan entrar: una entrada vendida, dos personas dentro.
const tkDoble = await tokenDe(T.doble);
const [p1, p2] = await Promise.all([validar({ token: tkDoble }), validar({ token: tkDoble })]);
const resultados = [p1.result, p2.result].sort();

console.log(`\n=== AC-09 · dos escaneos en paralelo ===\n  ${p1.result} + ${p2.result}`);

check('AC-09 dos escaneos SIMULTÁNEOS dan un allowed y un already_used',
  resultados[0] === 'allowed' && resultados[1] === 'already_used', resultados.join(' + '));

// ── Los otros dos resultados ────────────────────────────────────────────────
const sinNom = await validar({ token: await tokenDe(T.sinNominar) });
check('AC-16 sin nominar, en modo flexible: REVISAR MANUALMENTE',
  sinNom.result === 'manual_review' && sinNom.reason === 'not_nominated',
  `${sinNom.result} / ${sinNom.reason}`);

const vip = await validar({ token: await tokenDe(T.vip) });
check('AC-18 un VIP en la puerta de General: REVISAR, no DENEGADO',
  vip.result === 'manual_review' && vip.reason === 'wrong_zone', `${vip.result} / ${vip.reason}`);

// ── Un código que no es de Feventi ──────────────────────────────────────────
//
// Se corrompe la FIRMA, no el uuid: el token sigue teniendo la forma correcta y
// apunta a un ticket real. Es el caso interesante — un token inventado con
// estructura válida—, no una cadena de basura cualquiera.
const falso = tk.slice(0, 40) + (tk[40] === 'A' ? 'B' : 'A') + tk.slice(41);
const mal = await validar({ token: falso });
check('AC-12 una firma que no cuadra da DENEGADO por qr_unreadable',
  mal.result === 'denied' && mal.reason === 'qr_unreadable', `${mal.result} / ${mal.reason}`);
check('AC-12b …y NO dice de qué ticket era el uuid que traía',
  !JSON.stringify(mal).includes(T.ok), 'sin filtrar el ticket que suplantaba');

const basura = await validar({ token: 'no-soy-un-token' });
check('AC-12c un código que ni siquiera tiene la forma, igual', basura.result === 'denied',
  `${basura.result} / ${basura.reason}`);

// ── Modo DNI (D-03) ─────────────────────────────────────────────────────────
const encontradas = await (
  await fetch(`${B}/rest/v1/rpc/gate_find_by_dni`, {
    method: 'POST',
    headers: STAFF,
    body: JSON.stringify({ p_event_id: EVENTO, p_dni: '40123457' }),
  })
).json();

check('AC-19 el staff encuentra la entrada por documento',
  Array.isArray(encontradas) && encontradas.length === 1 && encontradas[0].code === 'FVT-2026-PTA002',
  Array.isArray(encontradas) ? `${encontradas.length}: ${encontradas[0]?.holder_name}` : JSON.stringify(encontradas).slice(0, 80));
check('AC-20b la búsqueda por DNI tampoco devuelve el hash',
  !JSON.stringify(encontradas).match(/hash/i) && encontradas[0]?.dni_last4 === '3457',
  `••••${encontradas[0]?.dni_last4}`);

const porDni = await validar({ mode: 'dni', ticket_id: T.dni });
check('AC-19b validar por DNI siempre es REVISAR MANUALMENTE',
  porDni.result === 'manual_review' && porDni.reason === 'dni_mode', `${porDni.result} / ${porDni.reason}`);

// El fan no puede buscar por documento: sería un oráculo sobre quién va.
const fanBusca = await fetch(`${B}/rest/v1/rpc/gate_find_by_dni`, {
  method: 'POST',
  headers: FAN,
  body: JSON.stringify({ p_event_id: EVENTO, p_dni: '40123457' }),
});
check('un fan no puede buscar por DNI', fanBusca.status >= 400, `HTTP ${fanBusca.status}`);

// ── Quién puede validar ─────────────────────────────────────────────────────
const fanValida = await post('qr-validate', FAN, { event_id: EVENTO, token: tk });
check('AC-05 un fan que llama a qr-validate recibe 403', fanValida.http === 403,
  `HTTP ${fanValida.http} · ${fanValida.error}`);

const sinSesion = await fetch(`${B}/functions/v1/qr-validate`, {
  method: 'POST',
  headers: { apikey: K, 'content-type': 'application/json' },
  body: JSON.stringify({ event_id: EVENTO, token: tk }),
}).then((r) => r.status);
check('sin sesión, 401', sinSesion === 401, `HTTP ${sinSesion}`);

// Un evento donde este staff no está asignado (el K-Pop Fest de la otra semilla).
const otroEvento = await post('qr-validate', STAFF, {
  event_id: 'd0000000-0000-4000-8000-00000000d004',
  token: tk,
});
check('AC-01 en un evento donde no es staff, 403', otroEvento.http === 403, `HTTP ${otroEvento.http}`);

// ── La bitácora ─────────────────────────────────────────────────────────────
const bitacora = await (
  await fetch(`${B}/rest/v1/checkins?select=result,reason,scanned_code,gate&order=created_at.desc`, {
    headers: STAFF,
  })
).json();

console.log('\n=== bitácora del turno ===');
for (const c of bitacora.slice(0, 12)) {
  console.log(`  ${String(c.result).padEnd(14)} ${String(c.reason).padEnd(22)} ${c.gate}`);
}

// Los dos códigos ilegibles de arriba, y ninguno se perdió. El umbral es 2 y no
// más: un fan llamando a `qr-validate` o un evento ajeno dan 403 y NO son
// escaneos —no llegan a la puerta—, así que no deben dejar fila. La primera
// versión pedía 3 contándolos, y falló con razón.
const ilegibles = bitacora.filter((c) => c.reason === 'qr_unreadable');
check('AC-21 los códigos ilegibles dejan fila igual: un QR inválido es información',
  ilegibles.length === 2 && ilegibles.every((c) => c.result === 'denied'),
  `${ilegibles.length} ilegibles de ${bitacora.length} escaneos`);
check('AC-24 y guarda el token crudo',
  bitacora.some((c) => c.scanned_code === tk), 'peritaje posible meses después');
check('AC-23 solo los de su puerta', bitacora.every((c) => c.gate === 'Puerta A'), 'Puerta A');

const borrar = await fetch(`${B}/rest/v1/checkins?gate=eq.Puerta%20A`, { method: 'DELETE', headers: STAFF });
check('AC-22 el staff no puede borrar la bitácora', borrar.status >= 400, `HTTP ${borrar.status}`);

const stats = await (
  await fetch(`${B}/rest/v1/v_gate_stats?select=*`, { headers: STAFF })
).json();
const s = stats[0] ?? {};
console.log(
  `\n=== contador ===\n  ${s.scans} escaneos · ${s.allowed} permitidos · ${s.manual_review} revisión · ` +
    `${s.already_used} repetidos · ${s.denied} denegados · aforo ${s.tickets_used}/${s.tickets_total}`,
);
check('AC-26 el contador cuadra con la bitácora',
  s.scans === s.allowed + s.manual_review + s.already_used + s.denied,
  `${s.scans} = ${s.allowed}+${s.manual_review}+${s.already_used}+${s.denied}`);

// ── Resultado ───────────────────────────────────────────────────────────────
console.log('\n=== resultado ===');
for (const r of res) console.log(`  ${r.pass ? '✓' : '✗ FALLA'}  ${r.ac} — ${r.detail ?? ''}`);
const fallos = res.filter((r) => !r.pass).length;
console.log(`\n  ${res.length - fallos}/${res.length} en verde`);
process.exit(fallos ? 1 : 0);
