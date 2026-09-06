-- La demo de la presentación.
--
-- Prepara un recorrido que una sola persona pueda conducir sin improvisar:
-- comprar, pagar, ver el QR vivo, validarlo en puerta, y ver la venta reflejada
-- en el dashboard del organizador.
--
-- DOS DECISIONES QUE SOSTIENEN TODO LO DEMÁS
--
-- 1. **Un solo evento para toda la historia.** El que se compra es el mismo que
--    se valida en puerta y el mismo del dashboard. Con eventos distintos el
--    recorrido se entiende igual, pero deja de ser una historia y pasa a ser una
--    lista de funciones.
--
-- 2. **La ventana de turno se recoloca sola.** Es el riesgo silencioso de esta
--    demo: el validador solo abre entre 2 h antes de puertas y 4 h después del
--    inicio, así que un evento sembrado hoy deja de escanearse mañana — y quien
--    presente lo descubriría delante de su público. Lo resuelve un trabajo de
--    `pg_cron` al final de este archivo.
--
-- Correr con: mcp__supabase__execute_sql · Reejecutable.

-- ── Venues ──────────────────────────────────────────────────────────────────
insert into public.venues (id, name, city, address, capacity) values
 ('de000000-0000-4000-8000-00000000a001','Arena Lima','Lima','Av. Javier Prado Este 4200, Surco',15000),
 ('de000000-0000-4000-8000-00000000a002','Gran Teatro Nacional','Lima','Av. Javier Prado Este 2225, San Borja',1400),
 ('de000000-0000-4000-8000-00000000a003','Parque de la Exposicion','Lima','Av. 28 de Julio, Cercado',8000)
on conflict (id) do nothing;

-- ── Las dos cuentas de la demo ──────────────────────────────────────────────
--
-- Creadas a mano y no por `signup` porque el envio de correos del plan gratuito
-- se agota en tres o cuatro altas por hora, y eso bloquea justo cuando hay prisa.
-- Se replica lo que hace GoTrue en un alta confirmada:
--
--   · fila en `auth.users` con la contrasena en bcrypt;
--   · su fila en `auth.identities` — sin ella el login falla;
--   · y los campos de token en CADENA VACIA, no NULL. GoTrue los lee como texto
--     y un NULL le revienta la consulta con «Database error querying schema»,
--     un mensaje que no apunta a nada.
--
-- OPERACIONES lleva los tres roles de gestion a proposito: asi la demo se
-- conduce desde UNA sesion en el portatil, cambiando de pestana y no de usuario.
-- Cada cierre de sesion en vivo es un sitio donde la presentacion puede encallar.
--
-- CAMILA es solo fan, y tiene que serlo: si viera el panel de organizador, la
-- demo no podria ensenar que un comprador no accede a la gestion.
do $cuentas$
declare
  v_ops uuid := 'dede0000-0000-4000-8000-000000000001';
  v_fan uuid := 'dede0000-0000-4000-8000-000000000002';
begin
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new,
    email_change_token_current, phone_change, phone_change_token, reauthentication_token
  ) values
    (v_ops, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'operaciones@feventi.demo', extensions.crypt('Feventi2026!', extensions.gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb,
     '{"full_name":"Equipo Feventi","email_verified":true}'::jsonb, now(), now(),
     '', '', '', '', '', '', '', ''),
    (v_fan, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'camila@feventi.demo', extensions.crypt('Feventi2026!', extensions.gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb,
     '{"full_name":"Camila Torres","email_verified":true}'::jsonb, now(), now(),
     '', '', '', '', '', '', '', '')
  on conflict (id) do nothing;

  insert into auth.identities (id, user_id, provider_id, provider, identity_data,
                               last_sign_in_at, created_at, updated_at)
  values
    (gen_random_uuid(), v_ops, v_ops::text, 'email',
     jsonb_build_object('sub', v_ops::text, 'email', 'operaciones@feventi.demo', 'email_verified', true),
     now(), now(), now()),
    (gen_random_uuid(), v_fan, v_fan::text, 'email',
     jsonb_build_object('sub', v_fan::text, 'email', 'camila@feventi.demo', 'email_verified', true),
     now(), now(), now())
  on conflict do nothing;
end $cuentas$;

insert into public.user_roles (user_id, role)
values ('dede0000-0000-4000-8000-000000000001', 'admin') on conflict do nothing;

insert into public.organizer_members (organizer_id, user_id, role)
values ('d0000000-0000-4000-8000-00000000d003','dede0000-0000-4000-8000-000000000001','owner')
on conflict do nothing;

-- ── Sacar del catalogo lo que se ve como dato de prueba ─────────────────────
-- «Prueba de Puerta» era lo PRIMERO que aparecia, por ser el evento mas proximo.
-- Se deja accesible por enlace para las suites, fuera del listado publico.
update public.events set visibility = 'unlisted'
 where id = 'd6000000-0000-4000-8000-000000000001';

-- Y los nombres tecleados al azar mientras se probaba a mano, que salian en la
-- wallet y en el veredicto del validador.
update public.tickets set holder_name = 'Camila Torres'   where holder_name in ('sdffsfds','asdadas');
update public.tickets set holder_name = 'Diego Salazar'   where holder_name in ('nbbjnjknjk','asdasdasdasdasdasasd');
update public.tickets set holder_name = 'Rivera Mendoza'  where holder_name = 'Rivera';
update public.tickets set holder_name = 'Inocencio Palma' where holder_name = 'Inocencio';
update public.tickets set holder_name = 'Ana Quispe'      where holder_name = 'Ana Doble';
update public.tickets set holder_name = 'Luis Carrillo'   where holder_name = 'Luis VIP';
update public.tickets set holder_name = 'Valeria Rios'    where holder_name = 'Valeria Demo Rios';

-- ── Limpiar el evento de la demo, para poder reejecutar ─────────────────────
delete from public.checkins      where event_id = 'de000000-0000-4000-8000-00000000b001';
delete from public.ticket_events where ticket_id in (select id from public.tickets where event_id='de000000-0000-4000-8000-00000000b001');
delete from public.tickets       where event_id = 'de000000-0000-4000-8000-00000000b001';
delete from public.order_items   where order_id in (select id from public.orders where event_id='de000000-0000-4000-8000-00000000b001');
delete from public.payments      where order_id in (select id from public.orders where event_id='de000000-0000-4000-8000-00000000b001');
delete from public.orders        where event_id = 'de000000-0000-4000-8000-00000000b001';
delete from public.price_tiers   where event_id = 'de000000-0000-4000-8000-00000000b001';
delete from public.price_phases  where event_id = 'de000000-0000-4000-8000-00000000b001';
delete from public.event_staff   where event_id = 'de000000-0000-4000-8000-00000000b001';
delete from public.zones         where event_id = 'de000000-0000-4000-8000-00000000b001';
delete from public.events        where id       = 'de000000-0000-4000-8000-00000000b001';

-- ── El evento de la demo ────────────────────────────────────────────────────
--
-- Puertas hace una hora y empieza dentro de cinco: eso deja la ventana de turno
-- abierta durante nueve horas, y a la vez la venta sigue abierta. Es la única
-- forma de que comprar y validar ocurran en el mismo evento y en la misma sesión.
insert into public.events (id, organizer_id, venue_id, title, description, category,
                           starts_at, doors_at, capacity, slug, status, visibility,
                           service_charge_bps, service_charge_payer, max_per_user,
                           qr_lead_days, nomination_mode)
values ('de000000-0000-4000-8000-00000000b001','d0000000-0000-4000-8000-00000000d003',
        'de000000-0000-4000-8000-00000000a001',
        'Zona Ritmo — Festival de Verano',
        'Ocho artistas, dos escenarios y una noche que abre la temporada. Cumbia, salsa y electrónica en la Arena Lima.',
        'Festival',
        now() + interval '5 hours', now() - interval '1 hour', 6000,
        'zona-ritmo-verano','published','public',600,'fan',6,14,'flexible');

insert into public.zones (id, event_id, name, kind, numbered, capacity, notes, sort_order) values
 ('de000000-0000-4000-8000-00000000c001','de000000-0000-4000-8000-00000000b001','Campo — de pie','standing',false,4000,'Acceso general',0),
 ('de000000-0000-4000-8000-00000000c002','de000000-0000-4000-8000-00000000b001','Palco VIP','standing',false,400,'Barra libre y acceso anticipado',1);

insert into public.price_phases (id, event_id, name, kind, starts_at, ends_at, sort_order) values
 ('de000000-0000-4000-8000-00000000d001','de000000-0000-4000-8000-00000000b001','Preventa','presale',now()-interval '20 days',now()+interval '3 hours',0),
 ('de000000-0000-4000-8000-00000000d002','de000000-0000-4000-8000-00000000b001','Última hora','regular',now()+interval '3 hours',now()+interval '30 days',1);

-- `sold` con números que cuentan algo: el Campo va llenándose y el VIP casi
-- agotado. Un catálogo con todo a cero se lee como un producto sin usuarios.
insert into public.price_tiers (id, event_id, zone_id, phase_id, price_cents, stock, sold) values
 ('de000000-0000-4000-8000-00000000e001','de000000-0000-4000-8000-00000000b001','de000000-0000-4000-8000-00000000c001','de000000-0000-4000-8000-00000000d001', 8500,4000,2840),
 ('de000000-0000-4000-8000-00000000e002','de000000-0000-4000-8000-00000000b001','de000000-0000-4000-8000-00000000c002','de000000-0000-4000-8000-00000000d001',22000, 400, 361),
 ('de000000-0000-4000-8000-00000000e003','de000000-0000-4000-8000-00000000b001','de000000-0000-4000-8000-00000000c001','de000000-0000-4000-8000-00000000d002',11000,4000,   0);

-- ── El staff de puerta ──────────────────────────────────────────────────────
-- Sin zona: así ninguna entrada sale como «zona equivocada» durante la demo.
insert into public.event_staff (id, event_id, profile_id, gate)
select gen_random_uuid(), 'de000000-0000-4000-8000-00000000b001', u.id, 'Puerta A'
  from auth.users u
 where u.email in ('operaciones@feventi.demo','anthony.g.rivera.i@gmail.com');

-- ── La compra que Camila ya tiene hecha ─────────────────────────────────────
--
-- Dos entradas pagadas y nominadas, para que la wallet tenga QR desde el primer
-- momento. El recorrido en vivo compra OTRAS: si la primera pantalla que se
-- enseña estuviera vacía, habría que comprar antes de poder contar nada.
insert into public.orders (id, event_id, buyer_id, status, subtotal_cents, service_charge_cents,
                           total_cents, service_charge_payer, service_charge_bps, paid_at)
values ('de000000-0000-4000-8000-00000000f001','de000000-0000-4000-8000-00000000b001',
        'dede0000-0000-4000-8000-000000000002','paid',17000,1020,18020,'fan',600,now()-interval '2 days');

insert into public.order_items (id, order_id, price_tier_id, unit_price_cents, attendee_name, attendee_dni_last4, nominated_at) values
 ('de000000-0000-4000-8000-00000000f101','de000000-0000-4000-8000-00000000f001','de000000-0000-4000-8000-00000000e001',8500,'Camila Torres','8412',now()-interval '2 days'),
 ('de000000-0000-4000-8000-00000000f102','de000000-0000-4000-8000-00000000f001','de000000-0000-4000-8000-00000000e001',8500,'Diego Salazar','5177',now()-interval '2 days');

insert into public.tickets (id, code, event_id, order_item_id, zone_id, owner_id, original_owner_id,
                           holder_name, holder_dni_hash, holder_dni_last4, status, face_value_cents,
                           qr_available_from, issued_at) values
 ('de000000-0000-4000-8000-00000000f201','FVT-2026-RTM4K2','de000000-0000-4000-8000-00000000b001','de000000-0000-4000-8000-00000000f101','de000000-0000-4000-8000-00000000c001','dede0000-0000-4000-8000-000000000002','dede0000-0000-4000-8000-000000000002','Camila Torres',private.hash_dni('70418412'),'8412','active',8500,now()-interval '2 days',now()-interval '2 days'),
 ('de000000-0000-4000-8000-00000000f202','FVT-2026-RTM7H9','de000000-0000-4000-8000-00000000b001','de000000-0000-4000-8000-00000000f102','de000000-0000-4000-8000-00000000c001','dede0000-0000-4000-8000-000000000002','dede0000-0000-4000-8000-000000000002','Diego Salazar',private.hash_dni('72305177'),'5177','active',8500,now()-interval '2 days',now()-interval '2 days');

insert into public.ticket_secrets (ticket_id, secret)
select id, extensions.gen_random_bytes(32) from public.tickets
 where event_id = 'de000000-0000-4000-8000-00000000b001'
on conflict (ticket_id) do nothing;

-- El DNI de Camila, ya declarado: sin esto el checkout en vivo pide teclear ocho
-- dígitos antes de poder pagar, y ese es un sitio donde una demo se atasca.
insert into public.profile_identity (user_id, dni_hash)
values ('dede0000-0000-4000-8000-000000000002', private.hash_dni('70418412'))
on conflict (user_id) do nothing;
update public.profiles set dni_last4 = '8412', dni_verified_at = now()
 where id = 'dede0000-0000-4000-8000-000000000002';

-- ── Que la ventana de turno no caduque ──────────────────────────────────────
--
-- Cada día a las 05:00 UTC (medianoche en Lima) la demo vuelve a colocarse con
-- las puertas recién abiertas. Sin esto funciona hoy y falla mañana, que es
-- exactamente la clase de fallo que aparece en el peor momento.
--
-- DOS COSAS QUE ESTE TRABAJO HACÍA MAL Y COSTARON UNA DEMO ROTA
--
-- 1. **Corría sin sesión.** `guard_sensitive_event_fields` bloquea mover la
--    fecha de un evento con entradas emitidas (Art. 4.4) — y su primera línea
--    dice «Admin sí puede». Sin JWT, `auth_is_admin()` daba falso y el update
--    moría con 42501 todas las noches, en silencio. El evento se quedó atrás y
--    la ventana de puerta llevaba un día cerrada.
--
-- 2. **Movía el evento pero no sus FASES.** La Preventa caducaba y el Palco VIP
--    se quedaba sin ningún tier a la venta. El catálogo seguía viéndose bien
--    —por eso no se notaba— pero comprar en VIP era imposible y el precio bueno
--    había desaparecido.
--
-- Y el orden importa: `price_phases_no_overlap` es una exclusion constraint, así
-- que la fase tardía se adelanta PRIMERO. Al revés, la Preventa se solaparía con
-- la Última hora, que todavía está en su sitio viejo.
select cron.unschedule('demo-recolocar-evento')
 where exists (select 1 from cron.job where jobname='demo-recolocar-evento');

select cron.schedule(
  'demo-recolocar-evento',
  '0 5 * * *',
  $job$
    do $$
    begin
      perform set_config('request.jwt.claims',
        '{"sub":"dede0000-0000-4000-8000-000000000001","role":"authenticated"}', true);

      update public.events
         set starts_at = now() + interval '5 hours',
             doors_at  = now() - interval '1 hour'
       where id = 'de000000-0000-4000-8000-00000000b001';

      update public.price_phases
         set starts_at = now() + interval '3 hours',
             ends_at   = now() + interval '30 days'
       where event_id = 'de000000-0000-4000-8000-00000000b001' and sort_order = 1;

      update public.price_phases
         set starts_at = now() - interval '20 days',
             ends_at   = now() + interval '3 hours'
       where event_id = 'de000000-0000-4000-8000-00000000b001' and sort_order = 0;

      perform set_config('request.jwt.claims', '', true);

      -- Devuelve las entradas usadas en la demo anterior a su estado inicial,
      -- para que la puerta vuelva a decir ACCESO PERMITIDO. Los checkins se
      -- borran con los triggers puestos: `point_ledger.checkin_id` tiene un
      -- `on delete set null` que tiene que propagarse (013).
      delete from public.checkins where event_id = 'de000000-0000-4000-8000-00000000b001';

      update public.tickets set status = 'active', used_at = null
       where event_id = 'de000000-0000-4000-8000-00000000b001' and status = 'used';
    end
    $$;
  $job$
);

-- ── Comprobación ────────────────────────────────────────────────────────────
select
  (select count(*) from public.events where status='published' and visibility='public') as eventos_en_catalogo,
  (select now() between doors_at - interval '2 hours' and starts_at + interval '4 hours'
     from public.events where id='de000000-0000-4000-8000-00000000b001') as puerta_abierta,
  (select count(*) from public.tickets where event_id='de000000-0000-4000-8000-00000000b001' and status='active') as entradas_de_camila,
  (select count(*) from public.event_staff where event_id='de000000-0000-4000-8000-00000000b001') as staff,
  (select count(*) from cron.job where jobname='demo-recolocar-evento') as cron_activo,
  -- Que las DOS zonas tengan tier a la venta: el fallo silencioso era que el
  -- Palco VIP se quedaba sin ninguno y nadie lo miraba.
  (select count(*) from public.price_tiers t
     join public.price_phases p on p.id = t.phase_id
    where t.event_id = 'de000000-0000-4000-8000-00000000b001'
      and now() between p.starts_at and p.ends_at)                as tiers_a_la_venta;
