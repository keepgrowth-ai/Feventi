-- Reiniciar la demo, para poder grabarla muchas veces.
--
-- ── LO QUE HAY QUE ENTENDER ANTES DE TOCAR ESTO ────────────────────────────
--
-- Es una función que BORRA DATOS. Lo importante no es lo que hace, es lo que
-- tiene prohibido hacer. Tres cierres, y ninguno sustituye a los otros:
--
-- 1. **Solo Admin.** `private.auth_is_admin()` en la primera línea. Sin eso,
--    cualquiera con sesión reinicia la base de otro.
--
-- 2. **Solo toca la utilería de la demo, por id escrito a mano.** No hay un
--    `delete from orders where ...` genérico en ningún sitio. Si mañana alguien
--    quiere reiniciar otro evento, tiene que escribir su id aquí — y al
--    escribirlo se dará cuenta de lo que está haciendo.
--
-- 3. **Se apaga sola en cuanto haya un pago real.** Mismo mecanismo que
--    `sandbox-pay` (ver su cabecera): consulta `payments` por cualquier
--    `provider` que no sea de sandbox y, si encuentra uno, devuelve error para
--    siempre. Es la única de las tres que no depende de que nadie se acuerde de
--    nada.
--
-- ── QUÉ DEVUELVE AL ESTADO SEMBRADO ────────────────────────────────────────
--
-- Todo lo que una grabación ensucia:
--
--   · las entradas usadas vuelven a `active`, y los checkins se borran — sin
--     esto el segundo escaneo dice «YA UTILIZADO» desde el principio;
--   · los puntos de esos checkins se van con ellos, así que Camila vuelve a 150
--     y el «150 → 200» del paso 8 se puede volver a enseñar;
--   · las compras hechas durante la grabación desaparecen, con su contador de
--     vendidas. Sin esto Camila llega a su tope de 6 entradas por evento a la
--     tercera grabación y el paso 4 falla con un mensaje de límite;
--   · los grupos de compra creados en vivo;
--   · los intereses y el grafo de amistad vuelven a como estaban, incluida la
--     solicitud de Joaquín sin responder —que es lo que enciende el punto
--     coral— y el modo ninja de Nadia;
--   · y el evento se recoloca con las puertas recién abiertas, que es lo que
--     mantiene la ventana de puerta abierta y el evento en el catálogo a la vez.
--     (Ver la cabecera de `demo_presentacion.sql`: son dos condiciones que el
--     tiempo separa.)

create or replace function public.reset_demo()
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $fn$
declare
  -- La utilería, por id. Cambiar esto es cambiar QUÉ se borra: que cueste.
  c_evento   constant uuid := 'de000000-0000-4000-8000-00000000b001';  -- Zona Ritmo
  c_camila   constant uuid := 'dede0000-0000-4000-8000-000000000002';
  c_ops      constant uuid := 'dede0000-0000-4000-8000-000000000001';
  c_diego    constant uuid := 'deaa0000-0000-4000-8000-000000000001';
  c_valeria  constant uuid := 'deaa0000-0000-4000-8000-000000000002';
  c_nadia    constant uuid := 'deaa0000-0000-4000-8000-000000000003';
  c_joaquin  constant uuid := 'deaa0000-0000-4000-8000-000000000004';
  c_kpop     constant uuid := 'd0000000-0000-4000-8000-00000000d004';
  c_standup  constant uuid := 'd0000000-0000-4000-8000-00000000e004';

  -- Las órdenes que SÍ son de la siembra. Todo lo demás del evento es basura
  -- de grabación y se va.
  c_sembradas constant uuid[] := array[
    'de000000-0000-4000-8000-00000000f001'::uuid,  -- las 2 de Camila
    'deaa0000-0000-4000-8000-00000000f001'::uuid,  -- la de Diego
    'deaa0000-0000-4000-8000-00000000f002'::uuid   -- la de Nadia
  ];

  v_ordenes  int := 0;
  v_checkins int := 0;
  v_grupos   int := 0;
begin
  -- ── Cierre 1: solo Admin ────────────────────────────────────────────────
  if not private.auth_is_admin() then
    raise exception 'solo Admin puede reiniciar la demo' using errcode = '42501';
  end if;

  -- ── Cierre 3: se apaga sola con el primer cobro real ────────────────────
  if exists (
    select 1 from public.payments
     where provider not in ('culqi_sandbox', 'sandbox_manual')
  ) then
    raise exception
      'este proyecto ya tiene pagos reales: reiniciar la demo está desactivado para siempre'
      using errcode = '42501';
  end if;

  -- ── Los checkins y sus puntos ───────────────────────────────────────────
  -- Los puntos PRIMERO: `point_ledger.checkin_id` es `on delete set null`, así
  -- que borrar el checkin antes deja el asiento huérfano y ya no se sabe cuál
  -- quitar. Se aprendió reiniciando esto a mano.
  delete from public.point_ledger
   where checkin_id in (select id from public.checkins where event_id = c_evento);

  delete from public.checkins where event_id = c_evento;
  get diagnostics v_checkins = row_count;

  update public.tickets set status = 'active', used_at = null
   where event_id = c_evento and status = 'used';

  -- ── Las compras de la grabación ─────────────────────────────────────────
  with basura as (
    select o.id from public.orders o
     where o.event_id = c_evento
       and not (o.id = any (c_sembradas))
  ),
  tk as (
    select t.id from public.tickets t
     where t.order_item_id in (select oi.id from public.order_items oi
                                where oi.order_id in (select id from basura))
  ),
  d1 as (delete from public.point_ledger where checkin_id in
          (select c.id from public.checkins c where c.ticket_id in (select id from tk)) returning 1),
  d2 as (delete from public.checkins       where ticket_id in (select id from tk) returning 1),
  d3 as (delete from public.ticket_secrets where ticket_id in (select id from tk) returning 1),
  d4 as (delete from public.ticket_events  where ticket_id in (select id from tk) returning 1),
  d5 as (delete from public.tickets        where id in (select id from tk) returning 1),
  d6 as (delete from public.group_members  where order_item_id in
          (select oi.id from public.order_items oi where oi.order_id in (select id from basura)) returning 1),
  d7 as (delete from public.order_items    where order_id in (select id from basura) returning 1),
  d8 as (delete from public.payments       where order_id in (select id from basura) returning 1),
  d9 as (delete from public.orders         where id in (select id from basura) returning 1)
  select count(*) into v_ordenes from d9;

  -- El contador de vendidas vuelve a los números de la siembra, que están
  -- elegidos para que el catálogo cuente algo: el Campo llenándose y el VIP
  -- casi agotado. Un evento con todo a cero se lee como un producto sin uso.
  update public.price_tiers set sold = 2840 where id = 'de000000-0000-4000-8000-00000000e001';
  update public.price_tiers set sold =  361 where id = 'de000000-0000-4000-8000-00000000e002';
  update public.price_tiers set sold =    0 where id = 'de000000-0000-4000-8000-00000000e003';

  -- ── Los grupos de compra ────────────────────────────────────────────────
  delete from public.purchase_groups where event_id = c_evento;
  get diagnostics v_grupos = row_count;

  -- ── El grafo social ─────────────────────────────────────────────────────
  -- `friend_edges` no es append-only (el Art. 8 no lista las amistades entre lo
  -- auditado), así que borrar y rehacer es legítimo.
  delete from public.blocks
   where c_camila in (blocker_id, blocked_id);
  delete from public.friend_edges
   where c_camila in (requester_id, addressee_id);

  insert into public.friend_edges (requester_id, addressee_id, status, responded_at) values
   (c_camila,  c_diego,   'accepted', now() - interval '30 days'),
   (c_valeria, c_camila,  'accepted', now() - interval '12 days'),
   (c_camila,  c_nadia,   'accepted', now() - interval '5 days'),
   -- Sin responder: es lo que enciende el punto coral del menú.
   (c_joaquin, c_camila,  'pending',  null);

  update public.profiles set ninja_mode = (id = c_nadia)
   where id in (c_camila, c_diego, c_valeria, c_nadia, c_joaquin);

  -- ── Los intereses ───────────────────────────────────────────────────────
  delete from public.event_interests
   where user_id in (c_camila, c_diego, c_valeria, c_nadia);

  insert into public.event_interests (user_id, event_id, created_at) values
   (c_valeria, c_evento,  now() - interval '2 days'),
   (c_diego,   c_kpop,    now() - interval '4 days'),
   (c_valeria, c_kpop,    now() - interval '1 day'),
   -- Solo Nadia, y está en ninja: este evento NO debe mostrar señal. Es la
   -- comprobación silenciosa de que el filtro funciona en el catálogo.
   (c_nadia,   c_standup, now() - interval '3 days');

  -- ── Recolocar el evento ─────────────────────────────────────────────────
  -- Las fases de atrás hacia adelante: `price_phases_no_overlap` es una
  -- exclusion constraint y adelantar primero la Preventa la haría solaparse con
  -- la Última hora, que aún está en su sitio viejo.
  update public.events
     set starts_at = now() + interval '5 hours',
         doors_at  = now() - interval '1 hour'
   where id = c_evento;

  update public.price_phases
     set starts_at = now() + interval '3 hours', ends_at = now() + interval '30 days'
   where event_id = c_evento and sort_order = 1;

  update public.price_phases
     set starts_at = now() - interval '20 days', ends_at = now() + interval '3 hours'
   where event_id = c_evento and sort_order = 0;

  return jsonb_build_object(
    'ok', true,
    'checkins_borrados', v_checkins,
    'ordenes_borradas', v_ordenes,
    'grupos_borrados', v_grupos,
    'puntos_de_camila', (select coalesce(sum(points), 0) from public.point_ledger where user_id = c_camila),
    'entradas_de_camila', (select count(*) from public.tickets
                            where owner_id = c_camila and event_id = c_evento and status = 'active'),
    'solicitudes_pendientes', (select count(*) from public.friend_edges
                                where addressee_id = c_camila and status = 'pending'),
    'puerta_abierta', (select now() between doors_at - interval '2 hours'
                                        and starts_at + interval '4 hours'
                         from public.events where id = c_evento)
  );
end;
$fn$;

-- Solo `authenticated` puede llamarla, y dentro se comprueba que sea Admin. Y
-- el `revoke` va detrás del `grant` porque conceder NO quita el `execute` que
-- `PUBLIC` trae de fábrica — la lección de 0055.
grant execute on function public.reset_demo() to authenticated;
revoke execute on function public.reset_demo() from public, anon;

comment on function public.reset_demo() is
  'Devuelve la utileria de la demo a su estado sembrado, para poder grabarla muchas veces. Tres cierres: solo Admin, solo ids escritos a mano, y se apaga sola en cuanto exista un pago con provider no-sandbox (igual que sandbox-pay).';
