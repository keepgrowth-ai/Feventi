-- Semilla del validador de puerta (006).
--
-- Para qué: abrir la pantalla real en `npm run dev` y correr
-- `supabase/tests/006_qr_validate.mjs`, que necesita tokens de VERDAD contra
-- entradas de VERDAD. Las pruebas SQL se siembran solas y no dejan rastro; esta
-- sí deja datos, a propósito.
--
-- Correr con: mcp__supabase__execute_sql
-- Ver en:     http://localhost:4200/puerta
--
-- ES REEJECUTABLE, y eso importa por dos motivos: cada pasada del .mjs CONSUME
-- entradas (para eso están), y la ventana de turno es relativa a `now()`, así
-- que un escenario sembrado ayer ya no sirve.
--
-- BORRA Y REHACE, en vez de actualizar. La primera versión intentaba recolocar
-- la fecha con `on conflict … do update` y chocó de frente con
-- `guard_sensitive_event_fields` (0036): «con entradas ya emitidas, la fecha la
-- cambia Feventi». El guard tiene razón —mover la fecha de un evento vendido es
-- una acción de Admin, no una de semilla— así que la salida no es esquivarlo,
-- es no pedirle nada: se tira el evento de demo entero y se vuelve a construir.
--
-- Sí, borra `checkins`. El Art. 8.1 dice que nadie los borra desde el cliente —y
-- nadie puede, está revocado para `authenticated` en todos los roles—. Esto corre
-- como `postgres` sobre un evento cuyo único propósito es ser reiniciado. El
-- filtro por `event_id` de abajo es lo que lo mantiene acotado, y no se toca.

-- ── Borrar lo anterior, en orden de dependencias ────────────────────────────
-- `ticket_secrets` cae en cascada con su ticket. `order_items` no se puede
-- borrar antes que los tickets: la FK es `on delete restrict`, y está bien que
-- lo sea — una entrada emitida no debe quedar huérfana de su línea de compra.
delete from public.checkins where event_id = 'd6000000-0000-4000-8000-000000000001';
delete from public.ticket_events
 where ticket_id in (select id from public.tickets where event_id = 'd6000000-0000-4000-8000-000000000001');
delete from public.tickets     where event_id = 'd6000000-0000-4000-8000-000000000001';
delete from public.order_items where order_id in (select id from public.orders where event_id = 'd6000000-0000-4000-8000-000000000001');
delete from public.orders      where event_id = 'd6000000-0000-4000-8000-000000000001';
delete from public.price_tiers where event_id = 'd6000000-0000-4000-8000-000000000001';
delete from public.price_phases where event_id = 'd6000000-0000-4000-8000-000000000001';
delete from public.event_staff where event_id = 'd6000000-0000-4000-8000-000000000001';
delete from public.zones       where event_id = 'd6000000-0000-4000-8000-000000000001';
delete from public.events      where id = 'd6000000-0000-4000-8000-000000000001';

-- ── El evento: en ventana de turno ──────────────────────────────────────────
-- Puertas abiertas hace media hora, empieza en una. Es lo que pone al staff
-- DENTRO de su turno (2 h antes de puertas, 4 h después del inicio).
--
-- Bloque de uuid propio (`d6…`) y no una continuación de `d0…`: la primera
-- versión reusó `…e101`, que ya era la zona General de «Noche de Stand Up». El
-- `on conflict do nothing` se la quedó en silencio y el fallo salió después, en
-- el trigger de aforo, hablando de una capacidad que no venía a cuento. De ahí
-- salió la migración 0045, que hace imposible ese cruce.

insert into public.events (id, organizer_id, venue_id, title, slug, status, visibility,
                           starts_at, doors_at, capacity, nomination_mode, qr_lead_days)
values ('d6000000-0000-4000-8000-000000000001',
        'd0000000-0000-4000-8000-00000000d003',
        'd0000000-0000-4000-8000-00000000d002',
        'Prueba de Puerta','prueba-de-puerta','published','public',
        now() + interval '1 hour', now() - interval '30 minutes', 500, 'flexible', 14)
;

insert into public.zones (id, event_id, name, kind, numbered, capacity) values
 ('d6000000-0000-4000-8000-000000000011','d6000000-0000-4000-8000-000000000001','General','standing',false,400),
 ('d6000000-0000-4000-8000-000000000012','d6000000-0000-4000-8000-000000000001','VIP','standing',false,100)
;

insert into public.price_phases (id, event_id, name, kind, starts_at, ends_at)
values ('d6000000-0000-4000-8000-000000000021','d6000000-0000-4000-8000-000000000001','Única','regular',
        now()-interval '30 days', now()+interval '30 days')
;

insert into public.price_tiers (id, event_id, zone_id, phase_id, price_cents, stock, sold) values
 ('d6000000-0000-4000-8000-000000000031','d6000000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000011','d6000000-0000-4000-8000-000000000021',6000,400,4),
 ('d6000000-0000-4000-8000-000000000032','d6000000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000012','d6000000-0000-4000-8000-000000000021',12000,100,1)
;

insert into public.orders (id, event_id, buyer_id, status, subtotal_cents, service_charge_cents, total_cents, paid_at)
values ('d6000000-0000-4000-8000-000000000041','d6000000-0000-4000-8000-000000000001',
        '50adfe5e-9ebc-4ff8-9054-445ee4fd2c25','paid',36000,2160,38160,now())
;

insert into public.order_items (id, order_id, price_tier_id, unit_price_cents) values
 ('d6000000-0000-4000-8000-000000000051','d6000000-0000-4000-8000-000000000041','d6000000-0000-4000-8000-000000000031',6000),
 ('d6000000-0000-4000-8000-000000000052','d6000000-0000-4000-8000-000000000041','d6000000-0000-4000-8000-000000000031',6000),
 ('d6000000-0000-4000-8000-000000000053','d6000000-0000-4000-8000-000000000041','d6000000-0000-4000-8000-000000000031',6000),
 ('d6000000-0000-4000-8000-000000000054','d6000000-0000-4000-8000-000000000041','d6000000-0000-4000-8000-000000000031',6000),
 ('d6000000-0000-4000-8000-000000000055','d6000000-0000-4000-8000-000000000041','d6000000-0000-4000-8000-000000000032',12000)
;

-- Cinco entradas, una por caso del .mjs. `qr_available_from` en el pasado: el
-- QR tiene que poder emitirse ya.
--
-- El DNI del titular se hashea con la función real (`private.hash_dni`, movida ahí
-- por 0010), no se inventa: el modo DNI
-- busca por ese hash y con un valor falso no encontraría nada.
insert into public.tickets (id, code, event_id, order_item_id, zone_id, owner_id, original_owner_id,
                           holder_name, holder_dni_hash, holder_dni_last4, status, face_value_cents,
                           qr_available_from) values
 ('d6000000-0000-4000-8000-000000000061','FVT-2026-PTA001','d6000000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000051','d6000000-0000-4000-8000-000000000011','50adfe5e-9ebc-4ff8-9054-445ee4fd2c25','50adfe5e-9ebc-4ff8-9054-445ee4fd2c25','Valeria Demo Rios',private.hash_dni('40123456'),'3456','active',6000,now()-interval '1 day'),
 ('d6000000-0000-4000-8000-000000000062','FVT-2026-PTA002','d6000000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000052','d6000000-0000-4000-8000-000000000011','50adfe5e-9ebc-4ff8-9054-445ee4fd2c25','50adfe5e-9ebc-4ff8-9054-445ee4fd2c25','Nicolas Rios',private.hash_dni('40123457'),'3457','active',6000,now()-interval '1 day'),
 -- Sin nominar: modo flexible → REVISAR MANUALMENTE.
 ('d6000000-0000-4000-8000-000000000063','FVT-2026-PTA003','d6000000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000053','d6000000-0000-4000-8000-000000000011','50adfe5e-9ebc-4ff8-9054-445ee4fd2c25','50adfe5e-9ebc-4ff8-9054-445ee4fd2c25',null,null,null,'active',6000,now()-interval '1 day'),
 -- Para el doble escaneo simultáneo (AC-09).
 ('d6000000-0000-4000-8000-000000000064','FVT-2026-PTA004','d6000000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000054','d6000000-0000-4000-8000-000000000011','50adfe5e-9ebc-4ff8-9054-445ee4fd2c25','50adfe5e-9ebc-4ff8-9054-445ee4fd2c25','Ana Doble',private.hash_dni('40123458'),'3458','active',6000,now()-interval '1 day'),
 -- VIP: en la Puerta A (atada a General) sale wrong_zone.
 ('d6000000-0000-4000-8000-000000000065','FVT-2026-PTA005','d6000000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000055','d6000000-0000-4000-8000-000000000012','50adfe5e-9ebc-4ff8-9054-445ee4fd2c25','50adfe5e-9ebc-4ff8-9054-445ee4fd2c25','Luis VIP',private.hash_dni('40123459'),'3459','active',12000,now()-interval '1 day')
;

-- Art. 2.6: 32 bytes por entrada, inalcanzables desde cualquier cliente.
insert into public.ticket_secrets (ticket_id, secret)
select id, extensions.gen_random_bytes(32) from public.tickets
 where event_id = 'd6000000-0000-4000-8000-000000000001'
;

-- ── El staff ────────────────────────────────────────────────────────────────
-- Rosa en Puerta A, atada a General: por eso el VIP le sale `wrong_zone` en vez
-- de pasar. Sin zona, la puerta admite cualquier entrada del evento.
insert into public.event_staff (id, event_id, profile_id, gate, zone_id)
values ('d6000000-0000-4000-8000-000000000071','d6000000-0000-4000-8000-000000000001',
        '33b6f220-9a6d-453a-b44c-d61b6328d281','Puerta A','d6000000-0000-4000-8000-000000000011')
;

-- Comprobación: 5 entradas activas, 1 asignación viva, evento en turno.
select
  (select count(*) from public.tickets where event_id = 'd6000000-0000-4000-8000-000000000001' and status = 'active') as entradas_activas,
  (select count(*) from public.event_staff where event_id = 'd6000000-0000-4000-8000-000000000001' and revoked_at is null) as staff,
  -- La ventana de turno, calculada igual que en `gate_checkin`. No se lee de
  -- `v_my_gate_events` porque esta semilla corre como `postgres`, sin JWT, y esa
  -- vista filtra por `auth.uid()`: saldría vacía y parecería un fallo.
  (select now() between coalesce(doors_at, starts_at) - interval '2 hours'
                   and starts_at + interval '4 hours'
     from public.events where id = 'd6000000-0000-4000-8000-000000000001') as en_turno,
  (select starts_at from public.events where id = 'd6000000-0000-4000-8000-000000000001') as empieza;
