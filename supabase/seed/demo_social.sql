-- La capa social de la demo (010–013).
--
-- Se corre **después** de `demo_presentacion.sql`, y lo complementa: aquel deja
-- el eje comprar → QR → puerta; este deja lo que el acta del 4 de septiembre
-- pide enseñar — que Camila vea que sus amigos van.
--
-- TRES DECISIONES QUE SOSTIENEN EL RECORRIDO
--
-- 1. **Nadia está en modo ninja y TIENE entrada.** No es un detalle de relleno:
--    es lo que permite señalar la pantalla y decir «el contador dice 1, no 2,
--    porque Nadia se escondió». Un control de privacidad que no se puede
--    demostrar es un control que nadie cree.
--
-- 2. **Joaquín deja una solicitud sin responder.** Así el punto coral del menú
--    está encendido desde el primer momento y hay algo que pulsar en /amigos.
--    Una pantalla social vacía no se explica, se justifica.
--
-- 3. **Los puntos salen de asistencias reales.** No se insertan en el libro
--    mayor a mano: se siembra un evento pasado con sus check-ins y el trigger
--    de 013 hace el resto. Si se falsearan, la primera pregunta incómoda
--    —«¿de dónde salen?»— no tendría respuesta.
--
-- Correr con: mcp__supabase__execute_sql · Reejecutable.

-- ── Los tres amigos y quien deja la solicitud ───────────────────────────────
-- Mismo procedimiento que las dos cuentas de `demo_presentacion.sql`: alta a
-- mano en `auth.users` + `auth.identities`, con los campos de token en CADENA
-- VACÍA. Un NULL ahí revienta GoTrue con «Database error querying schema».
do $cuentas$
declare
  r record;
begin
  for r in
    select * from (values
      ('deaa0000-0000-4000-8000-000000000001'::uuid,'diego@feventi.demo',  'Diego Salazar'),
      ('deaa0000-0000-4000-8000-000000000002'::uuid,'valeria@feventi.demo','Valeria Ríos'),
      ('deaa0000-0000-4000-8000-000000000003'::uuid,'nadia@feventi.demo',  'Nadia Soto'),
      ('deaa0000-0000-4000-8000-000000000004'::uuid,'joaquin@feventi.demo','Joaquín Vera')
    ) as t(id, email, nombre)
  loop
    insert into auth.users (
      id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change, email_change_token_new,
      email_change_token_current, phone_change, phone_change_token, reauthentication_token
    ) values (
      r.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      r.email, extensions.crypt('Feventi2026!', extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('full_name', r.nombre, 'email_verified', true), now(), now(),
      '', '', '', '', '', '', '', ''
    ) on conflict (id) do nothing;

    insert into auth.identities (id, user_id, provider_id, provider, identity_data,
                                 last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), r.id, r.id::text, 'email',
            jsonb_build_object('sub', r.id::text, 'email', r.email, 'email_verified', true),
            now(), now(), now())
    on conflict do nothing;
  end loop;
end $cuentas$;

-- ── El grafo ────────────────────────────────────────────────────────────────
-- Se limpia primero para que el archivo sea reejecutable: `friend_edges` no es
-- append-only (el Art. 8 no lista las amistades entre lo auditado), así que
-- borrar aquí es legítimo y no rompe ninguna bitácora.
delete from public.friend_edges
 where 'dede0000-0000-4000-8000-000000000002' in (requester_id, addressee_id);

insert into public.friend_edges (requester_id, addressee_id, status, responded_at) values
 -- Las direcciones van mezcladas a propósito: la amistad es simétrica (D-39) y
 -- la pantalla tiene que dar igual quién pidió.
 ('dede0000-0000-4000-8000-000000000002','deaa0000-0000-4000-8000-000000000001','accepted', now() - interval '30 days'),
 ('deaa0000-0000-4000-8000-000000000002','dede0000-0000-4000-8000-000000000002','accepted', now() - interval '12 days'),
 ('dede0000-0000-4000-8000-000000000002','deaa0000-0000-4000-8000-000000000003','accepted', now() - interval '5 days'),
 -- La solicitud sin responder: enciende el punto coral del menú.
 ('deaa0000-0000-4000-8000-000000000004','dede0000-0000-4000-8000-000000000002','pending', null);

-- Nadia se esconde. Es el único dato de esta siembra que se ve por lo que NO
-- produce.
update public.profiles set ninja_mode = true
 where id = 'deaa0000-0000-4000-8000-000000000003';
update public.profiles set ninja_mode = false
 where id in ('dede0000-0000-4000-8000-000000000002',
              'deaa0000-0000-4000-8000-000000000001',
              'deaa0000-0000-4000-8000-000000000002');

-- ── Las entradas de los amigos al evento de la demo ─────────────────────────
-- Diego y Nadia compraron. Diego cuenta; Nadia no, por ninja. Ese 1 en vez de 2
-- es la demostración.
delete from public.tickets     where id in ('deaa0000-0000-4000-8000-00000000f201','deaa0000-0000-4000-8000-00000000f202');
delete from public.order_items where id in ('deaa0000-0000-4000-8000-00000000f101','deaa0000-0000-4000-8000-00000000f102');
delete from public.orders      where id in ('deaa0000-0000-4000-8000-00000000f001','deaa0000-0000-4000-8000-00000000f002');

insert into public.orders (id, event_id, buyer_id, status, subtotal_cents, service_charge_cents,
                           total_cents, service_charge_payer, service_charge_bps, paid_at) values
 ('deaa0000-0000-4000-8000-00000000f001','de000000-0000-4000-8000-00000000b001',
  'deaa0000-0000-4000-8000-000000000001','paid',8500,510,9010,'fan',600, now() - interval '6 days'),
 ('deaa0000-0000-4000-8000-00000000f002','de000000-0000-4000-8000-00000000b001',
  'deaa0000-0000-4000-8000-000000000003','paid',22000,1320,23320,'fan',600, now() - interval '3 days');

insert into public.order_items (id, order_id, price_tier_id, unit_price_cents, attendee_name, nominated_at) values
 ('deaa0000-0000-4000-8000-00000000f101','deaa0000-0000-4000-8000-00000000f001','de000000-0000-4000-8000-00000000e001',8500,'Diego Salazar', now() - interval '6 days'),
 ('deaa0000-0000-4000-8000-00000000f102','deaa0000-0000-4000-8000-00000000f002','de000000-0000-4000-8000-00000000e002',22000,'Nadia Soto', now() - interval '3 days');

insert into public.tickets (id, code, event_id, order_item_id, zone_id, owner_id, original_owner_id,
                           holder_name, status, face_value_cents, qr_available_from, issued_at) values
 ('deaa0000-0000-4000-8000-00000000f201','FVT-2026-DGO4X1','de000000-0000-4000-8000-00000000b001',
  'deaa0000-0000-4000-8000-00000000f101','de000000-0000-4000-8000-00000000c001',
  'deaa0000-0000-4000-8000-000000000001','deaa0000-0000-4000-8000-000000000001',
  'Diego Salazar','active',8500, now() - interval '6 days', now() - interval '6 days'),
 ('deaa0000-0000-4000-8000-00000000f202','FVT-2026-NDA9K3','de000000-0000-4000-8000-00000000b001',
  'deaa0000-0000-4000-8000-00000000f102','de000000-0000-4000-8000-00000000c002',
  'deaa0000-0000-4000-8000-000000000003','deaa0000-0000-4000-8000-000000000003',
  'Nadia Soto','active',22000, now() - interval '3 days', now() - interval '3 days');

insert into public.ticket_secrets (ticket_id, secret)
select id, extensions.gen_random_bytes(32) from public.tickets
 where id in ('deaa0000-0000-4000-8000-00000000f201','deaa0000-0000-4000-8000-00000000f202')
on conflict (ticket_id) do nothing;

-- ── Los intereses ───────────────────────────────────────────────────────────
-- «Quiere ir» es la otra mitad de la señal. Repartidos por varios eventos para
-- que el catálogo no enseñe una sola tarjeta con señal — con una sola, el
-- filtro «Con amigos asistiendo» no se ve hacer nada.
delete from public.event_interests
 where user_id in ('deaa0000-0000-4000-8000-000000000001',
                   'deaa0000-0000-4000-8000-000000000002',
                   'deaa0000-0000-4000-8000-000000000003');

insert into public.event_interests (user_id, event_id, created_at) values
 -- Zona Ritmo: Valeria quiere ir. Con Diego ya dentro, la ficha dirá
 -- «1 amigo quiere ir · 1 amigo ya tiene entrada» — el texto exacto del mockup.
 ('deaa0000-0000-4000-8000-000000000002','de000000-0000-4000-8000-00000000b001', now() - interval '2 days'),
 -- K-Pop Fest: dos amigos. La tarjeta del catálogo dirá «2 amigos quieren ir».
 ('deaa0000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-00000000d004', now() - interval '4 days'),
 ('deaa0000-0000-4000-8000-000000000002','d0000000-0000-4000-8000-00000000d004', now() - interval '1 day'),
 -- Stand Up: solo Nadia, que está en ninja. Este evento NO debe mostrar señal,
 -- y es la comprobación silenciosa de que el filtro funciona en el catálogo.
 ('deaa0000-0000-4000-8000-000000000003','d0000000-0000-4000-8000-00000000e004', now() - interval '3 days');

-- ── Un evento pasado, para que los puntos existan de verdad ─────────────────
--
-- Los puntos NO se insertan en `point_ledger`: se siembran los check-ins y el
-- trigger de 013 los otorga. Es la diferencia entre «la wallet muestra un
-- número» y «la wallet muestra lo que asististe».
delete from public.checkins      where event_id = 'deaa0000-0000-4000-8000-00000000b009';
delete from public.tickets       where event_id = 'deaa0000-0000-4000-8000-00000000b009';
delete from public.order_items   where order_id = 'deaa0000-0000-4000-8000-00000000f009';
delete from public.orders        where id       = 'deaa0000-0000-4000-8000-00000000f009';
delete from public.price_tiers   where event_id = 'deaa0000-0000-4000-8000-00000000b009';
delete from public.price_phases  where event_id = 'deaa0000-0000-4000-8000-00000000b009';
delete from public.zones         where event_id = 'deaa0000-0000-4000-8000-00000000b009';
delete from public.events        where id       = 'deaa0000-0000-4000-8000-00000000b009';

insert into public.events (id, organizer_id, venue_id, title, description, category,
                           starts_at, doors_at, capacity, slug, status, visibility,
                           service_charge_bps, service_charge_payer, max_per_user,
                           qr_lead_days, nomination_mode)
values ('deaa0000-0000-4000-8000-00000000b009','d0000000-0000-4000-8000-00000000d003',
        'de000000-0000-4000-8000-00000000a003',
        'Noche de Cumbia — Edición Invierno',
        'La edición pasada. Aquí es donde Camila y sus amigos ganaron sus primeros puntos.',
        'Concierto',
        now() - interval '45 days', now() - interval '45 days' - interval '2 hours', 3000,
        'noche-cumbia-invierno','published','unlisted',600,'fan',6,14,'flexible');

insert into public.zones (id, event_id, name, kind, numbered, capacity, sort_order)
values ('deaa0000-0000-4000-8000-00000000c009','deaa0000-0000-4000-8000-00000000b009','General','standing',false,3000,0);
insert into public.price_phases (id, event_id, name, kind, starts_at, ends_at, sort_order)
values ('deaa0000-0000-4000-8000-00000000d009','deaa0000-0000-4000-8000-00000000b009','Única','regular',
        now()-interval '90 days', now()-interval '45 days',0);
insert into public.price_tiers (id, event_id, zone_id, phase_id, price_cents, stock, sold)
values ('deaa0000-0000-4000-8000-00000000e009','deaa0000-0000-4000-8000-00000000b009',
        'deaa0000-0000-4000-8000-00000000c009','deaa0000-0000-4000-8000-00000000d009',6000,3000,1180);

insert into public.orders (id, event_id, buyer_id, status, subtotal_cents, service_charge_cents,
                           total_cents, service_charge_payer, service_charge_bps, paid_at)
values ('deaa0000-0000-4000-8000-00000000f009','deaa0000-0000-4000-8000-00000000b009',
        'dede0000-0000-4000-8000-000000000002','paid',18000,1080,19080,'fan',600, now()-interval '60 days');

insert into public.order_items (id, order_id, price_tier_id, unit_price_cents, attendee_name, nominated_at) values
 ('deaa0000-0000-4000-8000-00000000f191','deaa0000-0000-4000-8000-00000000f009','deaa0000-0000-4000-8000-00000000e009',6000,'Camila Torres', now()-interval '60 days'),
 ('deaa0000-0000-4000-8000-00000000f192','deaa0000-0000-4000-8000-00000000f009','deaa0000-0000-4000-8000-00000000e009',6000,'Camila Torres', now()-interval '60 days'),
 ('deaa0000-0000-4000-8000-00000000f193','deaa0000-0000-4000-8000-00000000f009','deaa0000-0000-4000-8000-00000000e009',6000,'Camila Torres', now()-interval '60 days');

insert into public.tickets (id, code, event_id, order_item_id, zone_id, owner_id, original_owner_id,
                           holder_name, status, face_value_cents, qr_available_from, issued_at, used_at)
select 'deaa0000-0000-4000-8000-0000000091' || lpad(n::text, 2, '0'),
       'FVT-2025-CMB' || lpad(n::text, 3, '0'),
       'deaa0000-0000-4000-8000-00000000b009',
       ('deaa0000-0000-4000-8000-00000000f19' || n)::uuid,
       'deaa0000-0000-4000-8000-00000000c009',
       'dede0000-0000-4000-8000-000000000002','dede0000-0000-4000-8000-000000000002',
       'Camila Torres','used',6000, now()-interval '60 days', now()-interval '60 days',
       now()-interval '45 days'
  from generate_series(1,3) as n;

-- Y los check-ins, que son los que otorgan los puntos. Uno por entrada, todos
-- `allowed`: 3 × 50 = 150.
insert into public.checkins (event_id, ticket_id, staff_id, gate, result, reason, created_at)
select 'deaa0000-0000-4000-8000-00000000b009', t.id,
       'dede0000-0000-4000-8000-000000000001', 'Puerta A', 'allowed', 'ok',
       now() - interval '45 days'
  from public.tickets t where t.event_id = 'deaa0000-0000-4000-8000-00000000b009';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Se mira desde la sesión de Camila: es lo que ella verá en pantalla, no lo que
-- hay en las tablas. Son dos cosas distintas y la que importa es la primera.
set local role authenticated;
set local request.jwt.claims = '{"sub":"dede0000-0000-4000-8000-000000000002","role":"authenticated"}';

select
  (select count(*) from public.v_my_friends)                            as amigos,
  (select count(*) from public.v_my_friend_requests)                    as solicitudes_pendientes,
  (select friends_going      from public.v_my_event_signals
    where event_id='de000000-0000-4000-8000-00000000b001')              as zona_ritmo_van,
  (select friends_interested from public.v_my_event_signals
    where event_id='de000000-0000-4000-8000-00000000b001')              as zona_ritmo_quieren,
  (select friends_interested from public.v_my_event_signals
    where event_id='d0000000-0000-4000-8000-00000000d004')              as kpop_quieren,
  (select count(*) from public.v_my_event_signals
    where event_id='d0000000-0000-4000-8000-00000000e004')              as standup_debe_ser_cero,
  (select total from public.v_my_points)                                as puntos;

reset role;
