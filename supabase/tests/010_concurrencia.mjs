// Fase 1.5 — la mitad que solo se puede probar por HTTP.
//
// Dos cosas que un `.sql` no puede decir la verdad sobre:
//
//   1. **AC-06 de 010: aceptar la misma solicitud dos veces a la vez.** Dos
//      llamadas dentro de la misma transacción psql se serializan solas, así
//      que el test pasaría en verde sin haber probado el candado. Hacen falta
//      dos peticiones de verdad, en paralelo, contra la API real.
//
//   2. **Que las pantallas nuevas puedan leer lo que necesitan** con un JWT de
//      verdad, pasando por PostgREST y sus grants. Un `set local role` en SQL
//      no comprueba el `grant select` de la vista ni el `revoke execute` de la
//      RPC, que es donde han fallado tres de las cinco correcciones de esta
//      fase (0053, 0055, y el propio 0054 por otra vía).
//
// Correr con:  node supabase/tests/010_concurrencia.mjs
// Requiere:    supabase/seed/demo_presentacion.sql y demo_social.sql aplicados.

const K = 'sb_publishable_K1B29OwvqXggI9JiKvAL9g_zd26MUP6';
const B = 'https://orirleaujhpewiowaanq.supabase.co';

const CAMILA = 'camila@feventi.demo';
const DIEGO = 'diego@feventi.demo';
const JOAQUIN = 'joaquin@feventi.demo';
const CLAVE = 'Feventi2026!';

const ZONA_RITMO = 'de000000-0000-4000-8000-00000000b001';

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
  if (!r.access_token) throw new Error(`login ${email}: ${JSON.stringify(r)}`);
  return r.access_token;
}

const h = (jwt) => ({ apikey: K, authorization: `Bearer ${jwt}`, 'content-type': 'application/json' });

async function rest(jwt, path) {
  const r = await fetch(`${B}/rest/v1/${path}`, { headers: h(jwt) });
  // El cuerpo puede traer su propio `status`; el código HTTP se guarda aparte.
  return { http: r.status, body: await r.json().catch(() => null) };
}

async function rpc(jwt, fn, args) {
  const r = await fetch(`${B}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: h(jwt),
    body: JSON.stringify(args),
  });
  return { http: r.status, body: await r.json().catch(() => null) };
}

const jwtCamila = await login(CAMILA, CLAVE);
const jwtDiego = await login(DIEGO, CLAVE);
const jwtJoaquin = await login(JOAQUIN, CLAVE);

// ── Lo que leen las pantallas ──────────────────────────────────────────────
const amigos = await rest(jwtCamila, 'v_my_friends?select=*');
check(
  'HTTP-01 /amigos lee v_my_friends con un JWT real',
  amigos.http === 200 && Array.isArray(amigos.body) && amigos.body.length === 3,
  `http ${amigos.http} · ${amigos.body?.length} amigos`,
);

check(
  'HTTP-02 v_my_friends NO expone ninja_mode',
  amigos.body?.every((a) => !('ninja_mode' in a)),
  'si el front supiera quién se esconde, la función estaría rota por diseño',
);

const solicitudes = await rest(jwtCamila, 'v_my_friend_requests?select=*');
check(
  'HTTP-03 el punto coral tiene de dónde salir',
  solicitudes.http === 200 && solicitudes.body?.length === 1,
  `${solicitudes.body?.length} solicitud pendiente`,
);

const senales = await rest(jwtCamila, `v_my_event_signals?event_id=eq.${ZONA_RITMO}`);
const s = senales.body?.[0];
check(
  'HTTP-04 la señal del evento: 1 va, 1 quiere ir',
  senales.http === 200 && s?.friends_going === 1 && s?.friends_interested === 1,
  `van ${s?.friends_going} · quieren ${s?.friends_interested}`,
);

check(
  'HTTP-05 la señal NO trae zona, precio ni quién (D-40)',
  s && Object.keys(s).length === 3 && 'event_id' in s,
  `columnas: ${s ? Object.keys(s).join(', ') : '—'}`,
);

// Nadia tiene entrada de este evento y está en ninja. Si el conteo fuera 2, el
// interruptor de privacidad no estaría haciendo nada.
check(
  'HTTP-06 el amigo en modo ninja NO aparece en el conteo',
  s?.friends_going === 1,
  'Diego y Nadia tienen entrada; solo cuenta Diego',
);

const puntos = await rest(jwtCamila, 'v_my_points?select=total');
check(
  'HTTP-07 la wallet lee el saldo de puntos',
  puntos.http === 200 && puntos.body?.[0]?.total === 150,
  `${puntos.body?.[0]?.total} puntos, de tres asistencias reales`,
);

const ledgerAjeno = await rest(jwtDiego, 'point_ledger?select=*');
check(
  'HTTP-08 nadie ve el libro mayor de otro',
  ledgerAjeno.http === 200 && ledgerAjeno.body?.length === 0,
  'Diego no ha asistido a nada: cero filas, no error',
);

// ── AC-06 · el candado, con dos peticiones de verdad ───────────────────────
//
// Joaquín ya tiene una solicitud pendiente hacia Camila (la de la semilla).
// Camila la acepta DOS VECES A LA VEZ: una tiene que ganar y la otra fallar.
const pendiente = solicitudes.body?.[0]?.edge_id;

if (!pendiente) {
  check('AC-06  aceptar dos veces en paralelo deja una sola arista', false,
    'no había solicitud pendiente que aceptar — recorre demo_social.sql');
} else {
  const [a, b] = await Promise.all([
    rpc(jwtCamila, 'respond_friendship', { edge_id: pendiente, accept: true }),
    rpc(jwtCamila, 'respond_friendship', { edge_id: pendiente, accept: true }),
  ]);

  const oks = [a, b].filter((r) => r.http < 300).length;
  const fallos = [a, b].filter((r) => r.http >= 400).length;

  check(
    'AC-06  aceptar dos veces EN PARALELO: exactamente una gana',
    oks === 1 && fallos === 1,
    `${oks} ok · ${fallos} rechazada · ${JSON.stringify([a.http, b.http])}`,
  );

  const ahora = await rest(jwtCamila, 'v_my_friends?select=friend_id');
  check(
    'AC-06b y queda UNA sola amistad nueva, no dos',
    ahora.body?.length === 4,
    `${ahora.body?.length} amigos (eran 3)`,
  );

  // Se deshace para que el archivo sea reejecutable: la solicitud vuelve a
  // quedar pendiente y el punto coral sigue encendido para la demo.
  await fetch(`${B}/rest/v1/friend_edges?id=eq.${pendiente}`, {
    method: 'DELETE',
    headers: h(jwtCamila),
  });
  await rpc(jwtJoaquin, 'request_friendship', { target_email: CAMILA });

  const restaurado = await rest(jwtCamila, 'v_my_friend_requests?select=edge_id');
  check(
    'AC-06c la semilla queda como estaba (reejecutable)',
    restaurado.body?.length === 1,
    'la solicitud de Joaquín vuelve a estar pendiente',
  );
}

// ── La superficie que NO debe existir ──────────────────────────────────────
const anon = await fetch(`${B}/rest/v1/v_my_event_signals?select=*`, {
  headers: { apikey: K, 'content-type': 'application/json' },
});
check(
  'HTTP-09 anon no lee las señales sociales',
  anon.status >= 400,
  `http ${anon.status} — el grant es solo para authenticated`,
);

const anonRpc = await fetch(`${B}/rest/v1/rpc/request_friendship`, {
  method: 'POST',
  headers: { apikey: K, 'content-type': 'application/json' },
  body: JSON.stringify({ target_email: CAMILA }),
});
check(
  'HTTP-10 anon no puede llamar a request_friendship (0055)',
  anonRpc.status >= 400,
  `http ${anonRpc.status} — conceder execute no quita el de PUBLIC`,
);

// ── El oráculo que no debe serlo ───────────────────────────────────────────
const inexistente = await rpc(jwtDiego, 'request_friendship', {
  target_email: 'no-existe-nadie-asi@feventi.demo',
});
const yaAmigos = await rpc(jwtDiego, 'request_friendship', { target_email: CAMILA });
check(
  'HTTP-11 el correo inexistente y «ya sois amigos» dan el MISMO error',
  JSON.stringify(inexistente.body) === JSON.stringify(yaAmigos.body),
  `«${inexistente.body?.message}»`,
);

// ── Resultado ──────────────────────────────────────────────────────────────
const fallos = res.filter((r) => !r.pass).length;
for (const r of res) {
  console.log(`${r.pass ? '✓' : '✗ FALLA'}  ${r.ac}`);
  console.log(`         ${r.detail}`);
}
console.log(`\n${res.length - fallos}/${res.length} en verde`);
process.exit(fallos ? 1 : 0);
