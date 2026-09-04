-- 008 Dashboard del organizador — el dinero y el aislamiento
--
-- Corre entero dentro de begin … rollback: no deja rastro.
--
-- LO QUE DE VERDAD SE PRUEBA AQUÍ son dos cosas que se rompen en silencio:
--
--   1. **Que no se cobre dos veces la comisión.** El cargo puede pagarlo el fan
--      o absorberlo el organizador, y en cada caso «bruto» significa una cosa
--      distinta. Por eso hay DOS eventos sembrados, uno de cada tipo: con uno
--      solo, la fórmula parece correcta y está mal para la mitad de los casos.
--   2. **Que el organizador no llegue a una fila individual** (Art. 7.5, D-06).
--      Se comprueba contra las cuatro tablas por separado, no «confiando» en
--      que la vista agrega.
--
-- AC-20 (tiempos con 50 000 tickets) no está: necesita un volumen que esta
-- suite no siembra. Los índices que pide existen — `tickets (event_id, status)`,
-- `orders (event_id, status)` y `checkins (event_id, result)`, este último
-- añadido en 0047.

begin;

create temp table res(ac text, pass boolean, detail text) on commit drop;
grant insert, select on res to authenticated, anon;

-- ════════════════════════════════════════════════════════════════════════════
-- Semilla: dos organizadores, cuatro eventos, y un cargo de cada tipo
-- ════════════════════════════════════════════════════════════════════════════
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
 ('a8000000-0000-4000-8000-0000000000f1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','orgA@t.local','x',now(),'{}','{}',now(),now()),
 ('a8000000-0000-4000-8000-0000000000f2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','orgB@t.local','x',now(),'{}','{}',now(),now()),
 ('a8000000-0000-4000-8000-0000000000f3','00000000-0000-0000-0000-000000000000','authenticated','authenticated','viewerA@t.local','x',now(),'{}','{}',now(),now()),
 ('a8000000-0000-4000-8000-0000000000f4','00000000-0000-0000-0000-000000000000','authenticated','authenticated','exA@t.local','x',now(),'{}','{}',now(),now()),
 ('a8000000-0000-4000-8000-0000000000f5','00000000-0000-0000-0000-000000000000','authenticated','authenticated','fan8@t.local','x',now(),'{}','{"full_name":"Ana Fan"}',now(),now());

insert into public.venues (id,name,city,capacity) values ('a8000000-0000-4000-8000-0000000000b1','Coliseo','Lima',5000);

insert into public.organizers (id, legal_name, trade_name, ruc, status, created_by) values
 ('a8000000-0000-4000-8000-0000000000c1','A SAC','A','20508000001','approved','a8000000-0000-4000-8000-0000000000f1'),
 ('a8000000-0000-4000-8000-0000000000c2','B SAC','B','20508000002','approved','a8000000-0000-4000-8000-0000000000f2');

-- Un viewer vivo y uno revocado, para AC-07.
insert into public.organizer_members (organizer_id, user_id, role, revoked_at) values
 ('a8000000-0000-4000-8000-0000000000c1','a8000000-0000-4000-8000-0000000000f1','owner',null),
 ('a8000000-0000-4000-8000-0000000000c1','a8000000-0000-4000-8000-0000000000f3','viewer',null),
 ('a8000000-0000-4000-8000-0000000000c1','a8000000-0000-4000-8000-0000000000f4','viewer',now()),
 ('a8000000-0000-4000-8000-0000000000c2','a8000000-0000-4000-8000-0000000000f2','owner',null);

insert into public.events (id, organizer_id, venue_id, title, slug, status, visibility,
                           starts_at, doors_at, capacity, service_charge_bps, service_charge_payer) values
 ('a8000000-0000-4000-8000-0000000000e1','a8000000-0000-4000-8000-0000000000c1','a8000000-0000-4000-8000-0000000000b1','Evento cargo al fan','ev8-fan','published','public',now()+interval '10 days',now()+interval '10 days'-interval '2 hours',100,600,'fan'),
 ('a8000000-0000-4000-8000-0000000000e2','a8000000-0000-4000-8000-0000000000c1','a8000000-0000-4000-8000-0000000000b1','Evento cargo absorbido','ev8-org','published','public',now()+interval '10 days',now()+interval '10 days'-interval '2 hours',50,600,'organizer'),
 ('a8000000-0000-4000-8000-0000000000e3','a8000000-0000-4000-8000-0000000000c2','a8000000-0000-4000-8000-0000000000b1','Evento de B','ev8-b','published','public',now()+interval '10 days',now()+interval '10 days'-interval '2 hours',100,600,'fan'),
 ('a8000000-0000-4000-8000-0000000000e4','a8000000-0000-4000-8000-0000000000c1','a8000000-0000-4000-8000-0000000000b1','Evento sin ventas','ev8-cero','published','public',now()+interval '10 days',now()+interval '10 days'-interval '2 hours',200,600,'fan');

insert into public.zones (id, event_id, name, kind, numbered, capacity) values
 ('a8000000-0000-4000-8000-0000000000a1','a8000000-0000-4000-8000-0000000000e1','General','standing',false,100),
 ('a8000000-0000-4000-8000-0000000000a2','a8000000-0000-4000-8000-0000000000e2','General','standing',false,50),
 ('a8000000-0000-4000-8000-0000000000a3','a8000000-0000-4000-8000-0000000000e3','General','standing',false,100),
 ('a8000000-0000-4000-8000-0000000000a4','a8000000-0000-4000-8000-0000000000e4','General','standing',false,200);

insert into public.price_phases (id, event_id, name, kind, starts_at, ends_at, sort_order) values
 ('a8000000-0000-4000-8000-0000000000d1','a8000000-0000-4000-8000-0000000000e1','Preventa','presale',now()-interval '20 days',now()-interval '10 days',0),
 ('a8000000-0000-4000-8000-0000000000d2','a8000000-0000-4000-8000-0000000000e1','Regular','regular',now()-interval '10 days',now()+interval '9 days',1),
 ('a8000000-0000-4000-8000-0000000000d3','a8000000-0000-4000-8000-0000000000e2','Unica','regular',now()-interval '10 days',now()+interval '9 days',0),
 ('a8000000-0000-4000-8000-0000000000d4','a8000000-0000-4000-8000-0000000000e3','Unica','regular',now()-interval '10 days',now()+interval '9 days',0);

insert into public.price_tiers (id, event_id, zone_id, phase_id, price_cents, stock, sold) values
 ('a8000000-0000-4000-8000-0000000000c3','a8000000-0000-4000-8000-0000000000e1','a8000000-0000-4000-8000-0000000000a1','a8000000-0000-4000-8000-0000000000d1',10000,100,6),
 ('a8000000-0000-4000-8000-0000000000c4','a8000000-0000-4000-8000-0000000000e1','a8000000-0000-4000-8000-0000000000a1','a8000000-0000-4000-8000-0000000000d2',10000,100,2),
 ('a8000000-0000-4000-8000-0000000000c5','a8000000-0000-4000-8000-0000000000e2','a8000000-0000-4000-8000-0000000000a2','a8000000-0000-4000-8000-0000000000d3',20000,50,5),
 ('a8000000-0000-4000-8000-0000000000c6','a8000000-0000-4000-8000-0000000000e3','a8000000-0000-4000-8000-0000000000a3','a8000000-0000-4000-8000-0000000000d4',10000,100,3);

-- Los números están elegidos para que el resultado se pueda comprobar a mano:
--
--   e1 · Preventa   6 × S/ 100.00 = 600.00  + 6 % = 636.00
--   e1 · Regular    2 × S/ 100.00 = 200.00  + 6 % = 212.00   ← menos de 5 (AC-06)
--   e1 total        bruto 848.00 · comisión 48.00 · neto 800.00
--
--   e2              5 × S/ 200.00 = 1000.00, cargo ABSORBIDO
--                   bruto 1000.00 · comisión 60.00 · neto 940.00
insert into public.orders (id, event_id, buyer_id, status, subtotal_cents, service_charge_cents, total_cents,
                           service_charge_payer, service_charge_bps, paid_at, reserved_until) values
 ('a8000000-0000-4000-8000-0000000000d5','a8000000-0000-4000-8000-0000000000e1','a8000000-0000-4000-8000-0000000000f5','paid',60000,3600,63600,'fan',600,now(),null),
 ('a8000000-0000-4000-8000-0000000000d6','a8000000-0000-4000-8000-0000000000e1','a8000000-0000-4000-8000-0000000000f5','paid',20000,1200,21200,'fan',600,now(),null),
 ('a8000000-0000-4000-8000-0000000000d7','a8000000-0000-4000-8000-0000000000e2','a8000000-0000-4000-8000-0000000000f5','paid',100000,0,100000,'organizer',600,now(),null),
 ('a8000000-0000-4000-8000-0000000000d8','a8000000-0000-4000-8000-0000000000e3','a8000000-0000-4000-8000-0000000000f5','paid',30000,1800,31800,'fan',600,now(),null),
 -- AC-11: reservada y sin pagar. No debe sumar ni un céntimo.
 ('a8000000-0000-4000-8000-0000000000d9','a8000000-0000-4000-8000-0000000000e1','a8000000-0000-4000-8000-0000000000f5','reserved',30000,1800,31800,'fan',600,null,now()+interval '10 minutes');

insert into public.order_items (id, order_id, price_tier_id, unit_price_cents)
select ('a8000000-0000-4000-8000-00000000' || lpad((100+n)::text,4,'0'))::uuid,
       'a8000000-0000-4000-8000-0000000000d5','a8000000-0000-4000-8000-0000000000c3',10000 from generate_series(1,6) n;
insert into public.order_items (id, order_id, price_tier_id, unit_price_cents)
select ('a8000000-0000-4000-8000-00000000' || lpad((200+n)::text,4,'0'))::uuid,
       'a8000000-0000-4000-8000-0000000000d6','a8000000-0000-4000-8000-0000000000c4',10000 from generate_series(1,2) n;
insert into public.order_items (id, order_id, price_tier_id, unit_price_cents)
select ('a8000000-0000-4000-8000-00000000' || lpad((300+n)::text,4,'0'))::uuid,
       'a8000000-0000-4000-8000-0000000000d7','a8000000-0000-4000-8000-0000000000c5',20000 from generate_series(1,5) n;
insert into public.order_items (id, order_id, price_tier_id, unit_price_cents)
select ('a8000000-0000-4000-8000-00000000' || lpad((400+n)::text,4,'0'))::uuid,
       'a8000000-0000-4000-8000-0000000000d8','a8000000-0000-4000-8000-0000000000c6',10000 from generate_series(1,3) n;
insert into public.order_items (id, order_id, price_tier_id, unit_price_cents)
select ('a8000000-0000-4000-8000-00000000' || lpad((500+n)::text,4,'0'))::uuid,
       'a8000000-0000-4000-8000-0000000000d9','a8000000-0000-4000-8000-0000000000c3',10000 from generate_series(1,3) n;

-- Tickets solo de las órdenes pagadas.
insert into public.tickets (id, code, event_id, order_item_id, zone_id, owner_id, original_owner_id, status, face_value_cents)
select ('a8000000-0000-4000-8000-00000001' || lpad((100+n)::text,4,'0'))::uuid,
       'FVT-8-' || lpad(n::text,6,'0'),'a8000000-0000-4000-8000-0000000000e1',
       ('a8000000-0000-4000-8000-00000000' || lpad((100+n)::text,4,'0'))::uuid,
       'a8000000-0000-4000-8000-0000000000a1','a8000000-0000-4000-8000-0000000000f5','a8000000-0000-4000-8000-0000000000f5',
       'active',10000 from generate_series(1,6) n;
insert into public.tickets (id, code, event_id, order_item_id, zone_id, owner_id, original_owner_id, status, face_value_cents)
select ('a8000000-0000-4000-8000-00000002' || lpad((200+n)::text,4,'0'))::uuid,
       'FVT-8-' || lpad((100+n)::text,6,'0'),'a8000000-0000-4000-8000-0000000000e1',
       ('a8000000-0000-4000-8000-00000000' || lpad((200+n)::text,4,'0'))::uuid,
       'a8000000-0000-4000-8000-0000000000a1','a8000000-0000-4000-8000-0000000000f5','a8000000-0000-4000-8000-0000000000f5',
       'active',10000 from generate_series(1,2) n;

-- La puerta: 4 permitidos, 1 revisión, 2 denegados. 8 vendidas y 4 validadas —
-- dos números distintos a propósito, que es lo que prueba AC-18.
insert into public.event_staff (id, event_id, profile_id, gate)
values ('a8000000-0000-4000-8000-0000000000ab','a8000000-0000-4000-8000-0000000000e1','a8000000-0000-4000-8000-0000000000f5','Puerta A');
insert into public.checkins (event_id, staff_id, gate, result, reason)
select 'a8000000-0000-4000-8000-0000000000e1','a8000000-0000-4000-8000-0000000000f5','Puerta A','allowed','ok' from generate_series(1,4);
insert into public.checkins (event_id, staff_id, gate, result, reason) values
 ('a8000000-0000-4000-8000-0000000000e1','a8000000-0000-4000-8000-0000000000f5','Puerta A','manual_review','not_nominated'),
 ('a8000000-0000-4000-8000-0000000000e1','a8000000-0000-4000-8000-0000000000f5','Puerta A','denied','qr_unreadable'),
 ('a8000000-0000-4000-8000-0000000000e1','a8000000-0000-4000-8000-0000000000f5','Puerta A','denied','screenshot_suspected');
update public.tickets set status = 'used', used_at = now()
 where id in (select id from public.tickets where event_id = 'a8000000-0000-4000-8000-0000000000e1' limit 4);

-- ════════════════════════════════════════════════════════════════════════════
-- El dinero (Art. 5)
-- ════════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"a8000000-0000-4000-8000-0000000000f1","role":"authenticated"}';

insert into res select 'AC-08 cada concepto en su columna y con su nombre',
  gross_cents = 84800 and feventi_commission_cents = 4800 and refunds_cents = 0,
  'bruto ' || (gross_cents/100.0)::numeric(10,2) || ' · comision ' || (feventi_commission_cents/100.0)::numeric(10,2)
  from public.v_event_sales where event_id = 'a8000000-0000-4000-8000-0000000000e1';

insert into res select 'AC-09 neto = bruto - comision - devoluciones (cargo al fan)',
  net_estimated_cents = gross_cents - feventi_commission_cents - refunds_cents and net_estimated_cents = 80000,
  'neto ' || (net_estimated_cents/100.0)::numeric(10,2)
  from public.v_event_sales where event_id = 'a8000000-0000-4000-8000-0000000000e1';

-- LA COMPROBACIÓN QUE JUSTIFICA TODO EL DISEÑO. Si «bruto» fuera el subtotal en
-- los dos casos, aquí saldría 940.00 en el evento del fan también — cobrándole
-- la comisión a un organizador que ya la trasladó.
insert into res select 'AC-09b y tambien cuando el organizador ABSORBE el cargo',
  gross_cents = 100000 and feventi_commission_cents = 6000 and net_estimated_cents = 94000,
  'bruto 1000.00 - comision ' || (feventi_commission_cents/100.0)::numeric(10,2) || ' = neto ' || (net_estimated_cents/100.0)::numeric(10,2)
  from public.v_event_sales where event_id = 'a8000000-0000-4000-8000-0000000000e2';

insert into res select 'AC-11 una orden reservada NO suma al bruto',
  gross_cents = 84800, 'las 3 entradas reservadas (318.00) quedan fuera'
  from public.v_event_sales where event_id = 'a8000000-0000-4000-8000-0000000000e1';

insert into res select 'AC-16 entradas vendidas, con su denominador de aforo',
  tickets_sold = 8 and capacity = 100, tickets_sold || ' de ' || capacity
  from public.v_event_sales where event_id = 'a8000000-0000-4000-8000-0000000000e1';

insert into res select 'AC-19 un evento sin ventas da CEROS, no vacio',
  gross_cents = 0 and net_estimated_cents = 0 and tickets_sold = 0 and capacity = 200, '0 de 200'
  from public.v_event_sales where event_id = 'a8000000-0000-4000-8000-0000000000e4';

-- ════════════════════════════════════════════════════════════════════════════
-- El aislamiento (Art. 7.5, D-06)
-- ════════════════════════════════════════════════════════════════════════════
insert into res select 'AC-01 el organizador A no ve NADA del evento de B',
  (select count(*) from public.v_event_sales where event_id = 'a8000000-0000-4000-8000-0000000000e3') = 0, 'cero filas de B';
insert into res select 'AC-01b y solo ve sus tres eventos',
  (select count(*) from public.v_event_sales) = 3, (select count(*)::text from public.v_event_sales) || ' eventos';

-- Tabla por tabla, no «confiando» en que la vista agrega.
insert into res select 'AC-02 no lee ni una orden', (select count(*) from public.orders) = 0, 'cero';
insert into res select 'AC-02b ni un ticket', (select count(*) from public.tickets) = 0, 'cero';
insert into res select 'AC-02c ni un pago', (select count(*) from public.payments) = 0, 'cero';
insert into res select 'AC-02d ni el perfil del comprador',
  (select count(*) from public.profiles where id = 'a8000000-0000-4000-8000-0000000000f5') = 0, 'cero';

-- Contra el catálogo del sistema, no contra una lista escrita a mano: así una
-- columna nueva con nombre delator falla la prueba sola.
insert into res select 'AC-05 ninguna columna del dashboard es un dato personal',
  count(*) = 0, coalesce(string_agg(table_name || '.' || column_name, ', '), 'ninguna')
  from information_schema.columns
 where table_schema = 'public'
   and table_name in ('v_event_sales','v_event_phase_sales','v_gate_stats')
   and column_name ~* 'email|phone|dni|holder|buyer|owner';

insert into res select 'AC-06 una fase con menos de 5 entradas se agrega en «Otras fases»',
  bool_or(name = 'Otras fases' and tickets = 2) and bool_or(name = 'Preventa' and tickets = 6)
  and not bool_or(name = 'Regular'),
  string_agg(name || '=' || tickets, ', ' order by sort_order)
  from public.v_event_phase_sales where event_id = 'a8000000-0000-4000-8000-0000000000e1';

-- Esconder el grupo no puede perder el importe: el total por fase tiene que
-- seguir cuadrando con el subtotal del evento.
insert into res select 'AC-06b y el importe de la fase escondida no se pierde',
  sum(gross_cents) = 80000, (sum(gross_cents)/100.0)::numeric(10,2)::text
  from public.v_event_phase_sales where event_id = 'a8000000-0000-4000-8000-0000000000e1';

insert into res select 'AC-17 los accesos se cuentan desde checkins, por resultado',
  scans = 7 and allowed = 4 and manual_review = 1 and denied = 2,
  scans || ' escaneos: ' || allowed || '/' || manual_review || '/' || denied
  from public.v_gate_stats where event_id = 'a8000000-0000-4000-8000-0000000000e1';

insert into res select 'AC-18 aforo de ACCESO distinto de aforo de VENTA',
  (select allowed from public.v_gate_stats where event_id = 'a8000000-0000-4000-8000-0000000000e1') = 4
  and (select tickets_sold from public.v_event_sales where event_id = 'a8000000-0000-4000-8000-0000000000e1') = 8,
  '4 validados vs 8 vendidas: no son la misma metrica';

reset role;

-- ── AC-07 · quién del equipo lee ────────────────────────────────────────────
set local role authenticated;
set local request.jwt.claims = '{"sub":"a8000000-0000-4000-8000-0000000000f3","role":"authenticated"}';
insert into res select 'AC-07 un miembro viewer lee el dashboard',
  (select count(*) from public.v_event_sales) = 3, 'tres eventos';
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a8000000-0000-4000-8000-0000000000f4","role":"authenticated"}';
insert into res select 'AC-07b un miembro revocado no lee nada',
  (select count(*) from public.v_event_sales) = 0, 'cero';
reset role;

-- ── El otro lado del aislamiento ────────────────────────────────────────────
set local role authenticated;
set local request.jwt.claims = '{"sub":"a8000000-0000-4000-8000-0000000000f2","role":"authenticated"}';
insert into res select 'AC-01c el organizador B solo ve lo suyo',
  (select count(*) from public.v_event_sales) = 1
  and (select gross_cents from public.v_event_sales) = 31800, 'un evento, 318.00';
insert into res select 'AC-01d y tampoco los accesos de la puerta de A',
  (select count(*) from public.v_gate_stats) = 0, 'cero';
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a8000000-0000-4000-8000-0000000000f5","role":"authenticated"}';
insert into res select 'un fan no ve el dashboard de nadie',
  (select count(*) from public.v_event_sales) = 0
  and (select count(*) from public.v_event_phase_sales) = 0, 'cero y cero';
reset role;

-- ════════════════════════════════════════════════════════════════════════════
select case when pass then '✓' else '✗ FALLA' end as ok, ac, detail from res order by ctid;
select count(*) filter (where pass) || '/' || count(*) || ' en verde' as resultado from res;

rollback;
