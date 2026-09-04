-- 006 Validador de puerta — la decisión, la autorización y la bitácora
--
-- Corre entero dentro de begin … rollback: no deja rastro.
--
-- LO QUE ESTE ARCHIVO NO PRUEBA:
--   · AC-09, el doble escaneo SIMULTÁNEO. Necesita dos conexiones de verdad y
--     va en `006_qr_validate.mjs`, con peticiones HTTP en paralelo. Es la que,
--     si falla, se descubre con dos personas dentro y una entrada vendida.
--   · AC-11 y AC-12 aquí se prueban por el parámetro (`p_slot_delta`,
--     `p_mac_ok`); que ese parámetro se calcule bien a partir de un token real
--     lo prueba el .mjs, que es quien tiene el HMAC.
--   · AC-27 … AC-33, que son de pantalla.
--
-- TRAMPA DEL ARNÉS heredada de 004: `fails()` y `err()` ejecutan el statement
-- CADA UNA. Para una comprobación con efectos —y `gate_checkin` los tiene
-- todos— se usa solo `fails()` y el detalle se escribe a mano.

begin;

create temp table res(ac text, pass boolean, detail text) on commit drop;
grant insert, select on res to authenticated, anon;

create or replace function pg_temp.fails(p_sql text) returns boolean
language plpgsql as $$
begin execute p_sql; return false;
exception when others then return true; end $$;

create or replace function pg_temp.err(p_sql text) returns text
language plpgsql as $$
begin execute p_sql; return 'NO FALLÓ';
exception when others then return left(sqlerrm, 95); end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- Semilla: dos eventos en ventana de turno (uno flexible, uno estricto), un
-- tercero al que este staff NO está asignado, y sus entradas.
-- ════════════════════════════════════════════════════════════════════════════
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at) values
 ('a6000000-0000-4000-8000-0000000000f1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','staff1@t.local','x',now(),'{}','{"full_name":"Rosa Puerta"}',now(),now()),
 ('a6000000-0000-4000-8000-0000000000f2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','staff2@t.local','x',now(),'{}','{"full_name":"Luis Puerta"}',now(),now()),
 ('a6000000-0000-4000-8000-0000000000f3','00000000-0000-0000-0000-000000000000','authenticated','authenticated','fan6@t.local','x',now(),'{}','{"full_name":"Ana Fan"}',now(),now()),
 ('a6000000-0000-4000-8000-0000000000f4','00000000-0000-0000-0000-000000000000','authenticated','authenticated','org6@t.local','x',now(),'{}','{}',now(),now());

insert into public.venues (id,name,city,capacity)
values ('a6000000-0000-4000-8000-0000000000b1','Coliseo','Lima',5000);

insert into public.organizers (id, legal_name, trade_name, ruc, status, created_by)
values ('a6000000-0000-4000-8000-0000000000c1','Puerta SAC','Puerta','20506000001','approved',
        'a6000000-0000-4000-8000-0000000000f4');
insert into public.organizer_members (organizer_id, user_id, role)
values ('a6000000-0000-4000-8000-0000000000c1','a6000000-0000-4000-8000-0000000000f4','owner');

-- En ventana: puertas abrieron hace media hora, empieza en una.
insert into public.events (id, organizer_id, venue_id, title, slug, status, visibility,
                           starts_at, doors_at, capacity, nomination_mode) values
 ('a6000000-0000-4000-8000-0000000000e1','a6000000-0000-4000-8000-0000000000c1','a6000000-0000-4000-8000-0000000000b1',
  'Evento flexible','ev-flex-6','published','public', now()+interval '1 hour', now()-interval '30 minutes',5000,'flexible'),
 ('a6000000-0000-4000-8000-0000000000e2','a6000000-0000-4000-8000-0000000000c1','a6000000-0000-4000-8000-0000000000b1',
  'Evento estricto','ev-strict-6','published','public', now()+interval '1 hour', now()-interval '30 minutes',5000,'strict'),
 ('a6000000-0000-4000-8000-0000000000e3','a6000000-0000-4000-8000-0000000000c1','a6000000-0000-4000-8000-0000000000b1',
  'Evento ajeno','ev-ajeno-6','published','public', now()+interval '1 hour', now()-interval '30 minutes',5000,'flexible'),
 -- Fuera de ventana: empieza dentro de tres días.
 ('a6000000-0000-4000-8000-0000000000e4','a6000000-0000-4000-8000-0000000000c1','a6000000-0000-4000-8000-0000000000b1',
  'Evento lejano','ev-lejos-6','published','public', now()+interval '3 days', now()+interval '3 days'-interval '2 hours',5000,'flexible');

insert into public.zones (id, event_id, name, kind, numbered, capacity) values
 ('a6000000-0000-4000-8000-0000000000a1','a6000000-0000-4000-8000-0000000000e1','General','standing',false,4000),
 ('a6000000-0000-4000-8000-0000000000a2','a6000000-0000-4000-8000-0000000000e1','VIP','standing',false,200),
 ('a6000000-0000-4000-8000-0000000000a3','a6000000-0000-4000-8000-0000000000e2','General','standing',false,4000),
 ('a6000000-0000-4000-8000-0000000000a4','a6000000-0000-4000-8000-0000000000e3','General','standing',false,4000);

insert into public.price_phases (id, event_id, name, kind, starts_at, ends_at) values
 ('a6000000-0000-4000-8000-0000000000d1','a6000000-0000-4000-8000-0000000000e1','Única','regular',now()-interval '10 days',now()+interval '10 days'),
 ('a6000000-0000-4000-8000-0000000000d2','a6000000-0000-4000-8000-0000000000e2','Única','regular',now()-interval '10 days',now()+interval '10 days'),
 ('a6000000-0000-4000-8000-0000000000d3','a6000000-0000-4000-8000-0000000000e3','Única','regular',now()-interval '10 days',now()+interval '10 days');

insert into public.price_tiers (id, event_id, zone_id, phase_id, price_cents, stock, sold) values
 ('a6000000-0000-4000-8000-0000000000c2','a6000000-0000-4000-8000-0000000000e1','a6000000-0000-4000-8000-0000000000a1','a6000000-0000-4000-8000-0000000000d1',5000,100,8),
 ('a6000000-0000-4000-8000-0000000000c3','a6000000-0000-4000-8000-0000000000e1','a6000000-0000-4000-8000-0000000000a2','a6000000-0000-4000-8000-0000000000d1',9000,100,1),
 ('a6000000-0000-4000-8000-0000000000c4','a6000000-0000-4000-8000-0000000000e2','a6000000-0000-4000-8000-0000000000a3','a6000000-0000-4000-8000-0000000000d2',5000,100,1),
 ('a6000000-0000-4000-8000-0000000000c5','a6000000-0000-4000-8000-0000000000e3','a6000000-0000-4000-8000-0000000000a4','a6000000-0000-4000-8000-0000000000d3',5000,100,1);

insert into public.orders (id, event_id, buyer_id, status, subtotal_cents, service_charge_cents, total_cents, paid_at) values
 ('a6000000-0000-4000-8000-0000000000d4','a6000000-0000-4000-8000-0000000000e1','a6000000-0000-4000-8000-0000000000f3','paid',50000,3000,53000,now()),
 ('a6000000-0000-4000-8000-0000000000d5','a6000000-0000-4000-8000-0000000000e2','a6000000-0000-4000-8000-0000000000f3','paid', 5000, 300, 5300,now()),
 ('a6000000-0000-4000-8000-0000000000d6','a6000000-0000-4000-8000-0000000000e3','a6000000-0000-4000-8000-0000000000f3','paid', 5000, 300, 5300,now());

-- Una entrada por caso. El sufijo dice cuál.
insert into public.order_items (id, order_id, price_tier_id, unit_price_cents) values
 ('a6000000-0000-4000-8000-000000000e11','a6000000-0000-4000-8000-0000000000d4','a6000000-0000-4000-8000-0000000000c2',5000), -- nominada, GA
 ('a6000000-0000-4000-8000-000000000e12','a6000000-0000-4000-8000-0000000000d4','a6000000-0000-4000-8000-0000000000c2',5000), -- sin nominar, GA
 ('a6000000-0000-4000-8000-000000000e13','a6000000-0000-4000-8000-0000000000d4','a6000000-0000-4000-8000-0000000000c3',9000), -- nominada, VIP
 ('a6000000-0000-4000-8000-000000000e14','a6000000-0000-4000-8000-0000000000d4','a6000000-0000-4000-8000-0000000000c2',5000), -- listed
 ('a6000000-0000-4000-8000-000000000e15','a6000000-0000-4000-8000-0000000000d4','a6000000-0000-4000-8000-0000000000c2',5000), -- void
 ('a6000000-0000-4000-8000-000000000e16','a6000000-0000-4000-8000-0000000000d4','a6000000-0000-4000-8000-0000000000c2',5000), -- para paused/cancelled
 ('a6000000-0000-4000-8000-000000000e17','a6000000-0000-4000-8000-0000000000d4','a6000000-0000-4000-8000-0000000000c2',5000), -- para cancelled
 ('a6000000-0000-4000-8000-000000000e18','a6000000-0000-4000-8000-0000000000d5','a6000000-0000-4000-8000-0000000000c4',5000), -- estricto, sin nominar
 ('a6000000-0000-4000-8000-000000000e19','a6000000-0000-4000-8000-0000000000d6','a6000000-0000-4000-8000-0000000000c5',5000), -- de otro evento
 ('a6000000-0000-4000-8000-000000000e1a','a6000000-0000-4000-8000-0000000000d4','a6000000-0000-4000-8000-0000000000c2',5000); -- para el evento pausado

insert into public.tickets (id, code, event_id, order_item_id, zone_id, owner_id, original_owner_id,
                           holder_name, holder_dni_hash, holder_dni_last4, status, face_value_cents,
                           qr_available_from) values
 ('a6000000-0000-4000-8000-000000000f11','FVT-T-000001','a6000000-0000-4000-8000-0000000000e1','a6000000-0000-4000-8000-000000000e11','a6000000-0000-4000-8000-0000000000a1','a6000000-0000-4000-8000-0000000000f3','a6000000-0000-4000-8000-0000000000f3','Ana Fan','hashana','5678','active',5000,now()-interval '1 day'),
 ('a6000000-0000-4000-8000-000000000f12','FVT-T-000002','a6000000-0000-4000-8000-0000000000e1','a6000000-0000-4000-8000-000000000e12','a6000000-0000-4000-8000-0000000000a1','a6000000-0000-4000-8000-0000000000f3','a6000000-0000-4000-8000-0000000000f3',null,null,null,'active',5000,now()-interval '1 day'),
 ('a6000000-0000-4000-8000-000000000f13','FVT-T-000003','a6000000-0000-4000-8000-0000000000e1','a6000000-0000-4000-8000-000000000e13','a6000000-0000-4000-8000-0000000000a2','a6000000-0000-4000-8000-0000000000f3','a6000000-0000-4000-8000-0000000000f3','Ana Fan','hashana','5678','active',9000,now()-interval '1 day'),
 ('a6000000-0000-4000-8000-000000000f14','FVT-T-000004','a6000000-0000-4000-8000-0000000000e1','a6000000-0000-4000-8000-000000000e14','a6000000-0000-4000-8000-0000000000a1','a6000000-0000-4000-8000-0000000000f3','a6000000-0000-4000-8000-0000000000f3','Ana Fan','hashana','5678','listed',5000,now()-interval '1 day'),
 ('a6000000-0000-4000-8000-000000000f15','FVT-T-000005','a6000000-0000-4000-8000-0000000000e1','a6000000-0000-4000-8000-000000000e15','a6000000-0000-4000-8000-0000000000a1','a6000000-0000-4000-8000-0000000000f3','a6000000-0000-4000-8000-0000000000f3','Ana Fan','hashana','5678','void',5000,now()-interval '1 day'),
 ('a6000000-0000-4000-8000-000000000f16','FVT-T-000006','a6000000-0000-4000-8000-0000000000e1','a6000000-0000-4000-8000-000000000e16','a6000000-0000-4000-8000-0000000000a1','a6000000-0000-4000-8000-0000000000f3','a6000000-0000-4000-8000-0000000000f3','Ana Fan','hashana','5678','active',5000,now()-interval '1 day'),
 ('a6000000-0000-4000-8000-000000000f17','FVT-T-000007','a6000000-0000-4000-8000-0000000000e1','a6000000-0000-4000-8000-000000000e17','a6000000-0000-4000-8000-0000000000a1','a6000000-0000-4000-8000-0000000000f3','a6000000-0000-4000-8000-0000000000f3','Ana Fan','hashana','5678','active',5000,now()-interval '1 day'),
 ('a6000000-0000-4000-8000-000000000f18','FVT-T-000008','a6000000-0000-4000-8000-0000000000e2','a6000000-0000-4000-8000-000000000e18','a6000000-0000-4000-8000-0000000000a3','a6000000-0000-4000-8000-0000000000f3','a6000000-0000-4000-8000-0000000000f3',null,null,null,'active',5000,now()-interval '1 day'),
 ('a6000000-0000-4000-8000-000000000f19','FVT-T-000009','a6000000-0000-4000-8000-0000000000e3','a6000000-0000-4000-8000-000000000e19','a6000000-0000-4000-8000-0000000000a4','a6000000-0000-4000-8000-0000000000f3','a6000000-0000-4000-8000-0000000000f3','Ana Fan','hashana','5678','active',5000,now()-interval '1 day'),
 ('a6000000-0000-4000-8000-000000000f1a','FVT-T-000010','a6000000-0000-4000-8000-0000000000e1','a6000000-0000-4000-8000-000000000e1a','a6000000-0000-4000-8000-0000000000a1','a6000000-0000-4000-8000-0000000000f3','a6000000-0000-4000-8000-0000000000f3','Ana Fan','hashana','5678','active',5000,now()-interval '1 day');

-- El staff. Rosa en Puerta A, atada a General: por eso un VIP le sale wrong_zone.
-- Luis en Puerta B, sin zona: le entra cualquiera.
insert into public.event_staff (id, event_id, profile_id, gate, zone_id) values
 ('a6000000-0000-4000-8000-0000000000ab','a6000000-0000-4000-8000-0000000000e1','a6000000-0000-4000-8000-0000000000f1','Puerta A','a6000000-0000-4000-8000-0000000000a1'),
 ('a6000000-0000-4000-8000-0000000000ac','a6000000-0000-4000-8000-0000000000e2','a6000000-0000-4000-8000-0000000000f1','Puerta A',null),
 ('a6000000-0000-4000-8000-0000000000ad','a6000000-0000-4000-8000-0000000000e1','a6000000-0000-4000-8000-0000000000f2','Puerta B',null),
 ('a6000000-0000-4000-8000-0000000000ae','a6000000-0000-4000-8000-0000000000e4','a6000000-0000-4000-8000-0000000000f1','Puerta A',null);

-- ════════════════════════════════════════════════════════════════════════════
-- Los cuatro resultados
-- ════════════════════════════════════════════════════════════════════════════
--
-- Se llama a `gate_checkin` directamente porque este archivo prueba la DECISIÓN.
-- Quién puede llamarla se prueba más abajo (AC-01, AC-05).

-- AC-08 · el camino feliz, y la consecuencia en la misma transacción
with r as (
  select public.gate_checkin(
    'a6000000-0000-4000-8000-0000000000f1','a6000000-0000-4000-8000-0000000000e1',
    'a6000000-0000-4000-8000-000000000f11','TOKEN-K01',true,0,'qr') as j
)
insert into res select 'AC-08 entrada válida y nominada da ACCESO PERMITIDO',
  (j->>'result') = 'allowed' and (j->>'reason') = 'ok',
  (j->>'result') || ' · ' || (j #>> '{ticket,holder_name}') from r;

insert into res select 'AC-08b …y el ticket queda used en la MISMA transacción',
  status = 'used' and used_at is not null, status::text || ', ' || to_char(used_at,'HH24:MI:SS')
  from public.tickets where id = 'a6000000-0000-4000-8000-000000000f11';

-- AC-25
insert into res select 'AC-25 el allowed deja asiento en ticket_events',
  count(*) = 1, coalesce(max(meta->>'gate'),'—')
  from public.ticket_events
 where ticket_id = 'a6000000-0000-4000-8000-000000000f11' and action = 'used';

-- AC-24
insert into res select 'AC-24 el checkin guarda el token CRUDO, para peritaje',
  scanned_code = 'TOKEN-K01', coalesce(scanned_code,'(nulo)')
  from public.checkins where ticket_id = 'a6000000-0000-4000-8000-000000000f11';

-- AC-10 · el segundo escaneo
with r as (
  select public.gate_checkin(
    'a6000000-0000-4000-8000-0000000000f1','a6000000-0000-4000-8000-0000000000e1',
    'a6000000-0000-4000-8000-000000000f11','TOKEN-K01-BIS',true,0,'qr') as j
)
insert into res select 'AC-10 el segundo escaneo da YA UTILIZADO con hora y puerta del primero',
  (j->>'result') = 'already_used' and (j->>'first_gate') = 'Puerta A' and (j->>'first_at') is not null,
  (j->>'result') || ' · entró por ' || coalesce(j->>'first_gate','—') from r;

-- AC-16 · sin nominar, modo flexible
with r as (
  select public.gate_checkin(
    'a6000000-0000-4000-8000-0000000000f1','a6000000-0000-4000-8000-0000000000e1',
    'a6000000-0000-4000-8000-000000000f12','TOKEN-K02',true,1,'qr') as j
)
insert into res select 'AC-16 sin nominar en modo flexible da REVISAR MANUALMENTE',
  (j->>'result') = 'manual_review' and (j->>'reason') = 'not_nominated',
  (j->>'result') || ' / ' || (j->>'reason') from r;

insert into res select 'AC-16b …y consume la entrada: quien pasa la revisión, entra una vez',
  status = 'used', status::text
  from public.tickets where id = 'a6000000-0000-4000-8000-000000000f12';

-- AC-17 · lo mismo en modo estricto
with r as (
  select public.gate_checkin(
    'a6000000-0000-4000-8000-0000000000f1','a6000000-0000-4000-8000-0000000000e2',
    'a6000000-0000-4000-8000-000000000f18','TOKEN-K08',true,0,'qr') as j
)
insert into res select 'AC-17 sin nominar en modo estricto da ACCESO DENEGADO',
  (j->>'result') = 'denied' and (j->>'reason') = 'not_nominated',
  (j->>'result') || ' / ' || (j->>'reason') from r;

insert into res select 'AC-17b …y NO consume la entrada: no entró',
  status = 'active', status::text
  from public.tickets where id = 'a6000000-0000-4000-8000-000000000f18';

-- AC-18 · zona que no es la de esta puerta
with r as (
  select public.gate_checkin(
    'a6000000-0000-4000-8000-0000000000f1','a6000000-0000-4000-8000-0000000000e1',
    'a6000000-0000-4000-8000-000000000f13','TOKEN-K03',true,0,'qr') as j
)
insert into res select 'AC-18 un VIP en la puerta de General da REVISAR, nunca DENEGADO',
  (j->>'result') = 'manual_review' and (j->>'reason') = 'wrong_zone',
  (j->>'result') || ' / ' || (j->>'reason') from r;

-- La consecuencia que importa: si no consumiera, la persona se quedaría fuera
-- al ir a su puerta de verdad.
insert into res select 'AC-18b …y NO consume: tiene que poder entrar por su puerta',
  status = 'active', status::text
  from public.tickets where id = 'a6000000-0000-4000-8000-000000000f13';

-- AC-13 · los estados que inhabilitan
with r as (
  select public.gate_checkin(
    'a6000000-0000-4000-8000-0000000000f1','a6000000-0000-4000-8000-0000000000e1',
    'a6000000-0000-4000-8000-000000000f14','TOKEN-K04',true,0,'qr') as j
)
insert into res select 'AC-13 una entrada en reventa da el motivo CONCRETO, no «inválida»',
  (j->>'result') = 'denied' and (j->>'reason') = 'ticket_listed', (j->>'reason') from r;

with r as (
  select public.gate_checkin(
    'a6000000-0000-4000-8000-0000000000f1','a6000000-0000-4000-8000-0000000000e1',
    'a6000000-0000-4000-8000-000000000f15','TOKEN-K05',true,0,'qr') as j
)
insert into res select 'AC-13b una entrada anulada, igual',
  (j->>'result') = 'denied' and (j->>'reason') = 'ticket_void', (j->>'reason') from r;

-- AC-11 · Art. 2.3 — la señal antifraude
with r as (
  select public.gate_checkin(
    'a6000000-0000-4000-8000-0000000000f1','a6000000-0000-4000-8000-0000000000e1',
    'a6000000-0000-4000-8000-000000000f16','TOKEN-VIEJO',true,-9,'qr') as j
)
insert into res select 'AC-11 MAC válida con slot viejo: captura de pantalla, no «QR inválido»',
  (j->>'result') = 'denied' and (j->>'reason') = 'screenshot_suspected', (j->>'reason') from r;

-- Y la que da sentido a la anterior: ±1 SÍ pasa. Sin esto, «tolerancia ±1» es
-- una afirmación sin comprobar.
with r as (
  select public.gate_checkin(
    'a6000000-0000-4000-8000-0000000000f1','a6000000-0000-4000-8000-0000000000e1',
    'a6000000-0000-4000-8000-000000000f16','TOKEN-BORDE',true,-1,'qr') as j
)
insert into res select 'AC-11b un slot de diferencia SÍ pasa: es el reloj del móvil, no un fraude',
  (j->>'result') = 'allowed', (j->>'result') from r;

-- AC-12 · MAC que no cuadra
with r as (
  select public.gate_checkin(
    'a6000000-0000-4000-8000-0000000000f1','a6000000-0000-4000-8000-0000000000e1',
    null,'BASURA',false,null,'qr') as j
)
insert into res select 'AC-12 un código ilegible da ACCESO DENEGADO por qr_unreadable',
  (j->>'result') = 'denied' and (j->>'reason') = 'qr_unreadable', (j->>'reason') from r;

insert into res select 'AC-21 …y deja checkin igual, sin ticket: un QR inválido es información',
  count(*) = 1, count(*)::text || ' fila'
  from public.checkins
 where scanned_code = 'BASURA' and ticket_id is null;

-- AC-02 · ticket de otro evento
with r as (
  select public.gate_checkin(
    'a6000000-0000-4000-8000-0000000000f1','a6000000-0000-4000-8000-0000000000e1',
    'a6000000-0000-4000-8000-000000000f19','TOKEN-AJENO',true,0,'qr') as j
)
insert into res select 'AC-02 un ticket de otro evento da DENEGADO por wrong_event',
  (j->>'result') = 'denied' and (j->>'reason') = 'wrong_event', (j->>'reason') from r;

insert into res select 'AC-02b …y queda registrado en el evento del staff',
  count(*) = 1, count(*)::text || ' fila'
  from public.checkins
 where scanned_code = 'TOKEN-AJENO' and event_id = 'a6000000-0000-4000-8000-0000000000e1';

-- AC-19 · modo DNI (D-03)
with r as (
  select public.gate_checkin(
    'a6000000-0000-4000-8000-0000000000f1','a6000000-0000-4000-8000-0000000000e1',
    'a6000000-0000-4000-8000-000000000f17','',true,null,'dni') as j
)
insert into res select 'AC-19 el modo DNI siempre es REVISAR MANUALMENTE',
  (j->>'result') = 'manual_review' and (j->>'reason') = 'dni_mode', (j->>'reason') from r;

-- AC-20 · lo que el staff necesita cotejar, y nada más
with r as (
  select public.gate_checkin(
    'a6000000-0000-4000-8000-0000000000f1','a6000000-0000-4000-8000-0000000000e1',
    'a6000000-0000-4000-8000-000000000f14','TOKEN-DNI-CHECK',true,0,'qr') as j
)
insert into res select 'AC-20 la respuesta trae nombre y últimos 4, NUNCA el hash del DNI',
  (j #>> '{ticket,dni_last4}') = '5678'
  and j::text not like '%hashana%',
  'dni_last4 = ' || coalesce(j #>> '{ticket,dni_last4}','—') from r;

-- AC-15 y AC-14 · el estado del evento. En este orden: pausar no cierra la
-- puerta, cancelar sí.
--
-- Con entrada PROPIA (…f1a) y no reutilizando f16. La primera vez que se corrió
-- esta suite, AC-15 falló con `already_used`: f16 ya lo había consumido AC-11b.
-- Es la trampa que 004 ya había anotado —una comprobación con efectos contamina
-- a la siguiente— y volvió a morder aquí. Falló la prueba, no el producto.
update public.events set status = 'paused', paused_at = now()
 where id = 'a6000000-0000-4000-8000-0000000000e1';

with r as (
  select public.gate_checkin(
    'a6000000-0000-4000-8000-0000000000f1','a6000000-0000-4000-8000-0000000000e1',
    'a6000000-0000-4000-8000-000000000f1a','TOKEN-PAUSED',true,0,'qr') as j
)
insert into res select 'AC-15 evento pausado: ENTRA. Pausar detiene la venta, no el acceso',
  (j->>'result') = 'allowed', (j->>'result') from r;

update public.events set status = 'cancelled', cancelled_at = now()
 where id = 'a6000000-0000-4000-8000-0000000000e1';

with r as (
  select public.gate_checkin(
    'a6000000-0000-4000-8000-0000000000f1','a6000000-0000-4000-8000-0000000000e1',
    'a6000000-0000-4000-8000-000000000f17','TOKEN-CANCEL',true,0,'qr') as j
)
insert into res select 'AC-14 evento cancelado: DENEGADO',
  (j->>'result') = 'denied' and (j->>'reason') = 'event_cancelled', (j->>'reason') from r;

update public.events set status = 'published', cancelled_at = null, paused_at = null
 where id = 'a6000000-0000-4000-8000-0000000000e1';

-- ════════════════════════════════════════════════════════════════════════════
-- Autorización
-- ════════════════════════════════════════════════════════════════════════════

-- AC-03 · fuera de la ventana de turno
insert into res select 'AC-03 fuera de la ventana de turno, no se valida',
  pg_temp.fails($$select public.gate_checkin(
    'a6000000-0000-4000-8000-0000000000f1','a6000000-0000-4000-8000-0000000000e4',
    'a6000000-0000-4000-8000-000000000f11','X',true,0,'qr')$$),
  '2 h antes de puertas y 4 h después del inicio';

-- Un staff que no está asignado a ESE evento
insert into res select 'AC-01 sin asignación viva no hay validación posible',
  pg_temp.fails($$select public.gate_checkin(
    'a6000000-0000-4000-8000-0000000000f2','a6000000-0000-4000-8000-0000000000e2',
    'a6000000-0000-4000-8000-000000000f18','X',true,0,'qr')$$),
  'Luis no es staff del evento estricto';

-- AC-04 · revocar corta el acceso y NO borra nada
create temp table antes as
  select count(*) as n from public.checkins where staff_id = 'a6000000-0000-4000-8000-0000000000f1';

update public.event_staff set revoked_at = now()
 where id = 'a6000000-0000-4000-8000-0000000000ab';

insert into res select 'AC-04 revocar corta el acceso en la llamada siguiente',
  pg_temp.fails($$select public.gate_checkin(
    'a6000000-0000-4000-8000-0000000000f1','a6000000-0000-4000-8000-0000000000e1',
    'a6000000-0000-4000-8000-000000000f16','X',true,0,'qr')$$),
  'Art. 8.2';

insert into res select 'AC-04b …y no borra ni uno de sus checkins',
  (select n from antes) = (select count(*) from public.checkins where staff_id = 'a6000000-0000-4000-8000-0000000000f1'),
  (select n from antes)::text || ' antes y después';

update public.event_staff set revoked_at = null
 where id = 'a6000000-0000-4000-8000-0000000000ab';

-- ════════════════════════════════════════════════════════════════════════════
-- Lo que el staff ve, y lo que no
-- ════════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-0000000000f1","role":"authenticated"}';

-- AC-05 · un fan —o cualquiera con sesión— no puede llamar a la decisión
insert into res select 'AC-05 gate_checkin no es llamable con una sesión normal',
  pg_temp.fails($$select public.gate_checkin(
    'a6000000-0000-4000-8000-0000000000f1','a6000000-0000-4000-8000-0000000000e1',
    'a6000000-0000-4000-8000-000000000f16','X',true,0,'qr')$$),
  'solo service_role, desde qr-validate';

-- AC-06 · solo sus eventos
insert into res select 'AC-06 el staff ve SOLO sus eventos asignados',
  count(*) = 3 and bool_and(title <> 'Evento ajeno'),
  string_agg(title || ' · ' || gate, ' | ' order by title)
  from public.v_my_gate_events;

insert into res select 'AC-06b …y la vista ya dice si está en turno o no',
  count(*) filter (where shift_active) = 2 and count(*) filter (where not shift_active) = 1,
  string_agg(title || '=' || shift_active::text, ', ' order by title)
  from public.v_my_gate_events;

-- AC-07 · nada de dinero, nada de terceros
insert into res select 'AC-07 el staff no lee orders',
  (select count(*) from public.orders) = 0, 'cero filas visibles';
insert into res select 'AC-07b el staff no lee tickets ajenos',
  (select count(*) from public.tickets) = 0, 'cero filas visibles';

-- AC-23 · su turno y su puerta
insert into res select 'AC-23 el staff lee los checkins de SU puerta',
  count(*) > 0 and bool_and(gate = 'Puerta A'), count(*)::text || ' en Puerta A'
  from public.checkins;

-- AC-22 · Art. 8.1
insert into res select 'AC-22 el staff no puede INSERTAR en checkins',
  pg_temp.fails($$insert into public.checkins (event_id, staff_id, gate, result, reason)
    values ('a6000000-0000-4000-8000-0000000000e1','a6000000-0000-4000-8000-0000000000f1','Puerta A','allowed','ok')$$),
  'append-only, y el append lo hace service_role';
insert into res select 'AC-22b …ni ACTUALIZAR',
  pg_temp.fails($$update public.checkins set result = 'allowed'$$), 'Art. 8.1';
insert into res select 'AC-22c …ni BORRAR. Corregir es un asiento nuevo',
  pg_temp.fails($$delete from public.checkins$$), 'Art. 8.3';

-- AC-26 · el contador sale de la bitácora
insert into res select 'AC-26 el contador del turno agrega checkins, no lleva un contador aparte',
  scans = allowed + manual_review + already_used + denied and tickets_total > 0,
  scans::text || ' escaneos: ' || allowed || ' ok, ' || manual_review || ' revisión, '
    || already_used || ' repetidos, ' || denied || ' denegados'
  from public.v_gate_stats where gate = 'Puerta A' and event_id = 'a6000000-0000-4000-8000-0000000000e1';

insert into res select 'AC-26b …y separa las capturas, que es lo que se mira al día siguiente',
  screenshots = 1, screenshots::text || ' captura'
  from public.v_gate_stats where gate = 'Puerta A' and event_id = 'a6000000-0000-4000-8000-0000000000e1';

-- Modo DNI: la búsqueda es del staff, no del servicio.
insert into res select 'el modo DNI rechaza un documento mal formado antes de buscar',
  pg_temp.fails($$select public.gate_find_by_dni('a6000000-0000-4000-8000-0000000000e1','1234')$$),
  'ocho dígitos o nada';

reset role;

-- Un fan que intenta buscar por DNI en un evento donde no es staff: ese sería
-- un oráculo para confirmar si alguien tiene entrada.
set local role authenticated;
set local request.jwt.claims = '{"sub":"a6000000-0000-4000-8000-0000000000f3","role":"authenticated"}';
insert into res select 'un fan no puede buscar por DNI: sería un oráculo sobre quién va',
  pg_temp.fails($$select public.gate_find_by_dni('a6000000-0000-4000-8000-0000000000e1','12345678')$$),
  '42501';
reset role;

-- ════════════════════════════════════════════════════════════════════════════
select case when pass then '✓' else '✗ FALLA' end as ok, ac, detail from res order by ctid;
select count(*) filter (where pass) || '/' || count(*) || ' en verde' as resultado from res;

rollback;
