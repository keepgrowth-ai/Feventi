-- 012 Compra grupal — pruebas de política
--
-- Corre entero dentro de begin … rollback: no deja rastro.
--   mcp__supabase__execute_sql  con el contenido de este archivo
--
-- Bloque de identificadores de esta suite: `b2000000-0000-4000-8000-…`,
-- RUC `20512000001`.
--
-- Dos cosas que costaron una corrida en rojo cada una y que valen para toda
-- suite futura:
--
--   1. **Medir desde quien acaba de salir da cero por RLS, no por el producto.**
--      AC-08 contaba los miembros restantes desde la sesión de quien se acababa
--      de ir del grupo — y esa persona ya no ve el grupo. El conteo se hace
--      desde quien se queda.
--
--   2. **Las órdenes se siembran como `postgres`.** `authenticated` no tiene
--      `insert` en `orders` (la reserva la hace `reserve_order`), así que
--      sembrarlas desde una sesión de fan solo probaría que el `revoke`
--      funciona, cosa que ya cubre 004.

begin;

-- ── Semilla · el creador y tres amigos ──────────────────────────────────────
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
 ('b2000000-0000-4000-8000-0000000000f1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','c012@t.local','x',now(),'{}','{"full_name":"Cesar Crea"}',now(),now()),
 ('b2000000-0000-4000-8000-0000000000f2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','a012@t.local','x',now(),'{}','{"full_name":"Amiga Dos"}',now(),now()),
 ('b2000000-0000-4000-8000-0000000000f3','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b012@t.local','x',now(),'{}','{"full_name":"Amigo Tres"}',now(),now()),
 ('b2000000-0000-4000-8000-0000000000f4','00000000-0000-0000-0000-000000000000','authenticated','authenticated','d012@t.local','x',now(),'{}','{"full_name":"Amiga Cuatro"}',now(),now()),
 ('b2000000-0000-4000-8000-0000000000f5','00000000-0000-0000-0000-000000000000','authenticated','authenticated','e012@t.local','x',now(),'{}','{"full_name":"Amigo Cinco"}',now(),now()),
 -- El extraño: amigo de nadie. Es quien prueba AC-03 y AC-17.
 ('b2000000-0000-4000-8000-0000000000f9','00000000-0000-0000-0000-000000000000','authenticated','authenticated','x012@t.local','x',now(),'{}','{"full_name":"Extrano"}',now(),now()),
 ('b2000000-0000-4000-8000-0000000000f6','00000000-0000-0000-0000-000000000000','authenticated','authenticated','o012@t.local','x',now(),'{}','{}',now(),now());

create or replace function pg_temp.fails(p_sql text) returns boolean
language plpgsql as $$ begin execute p_sql; return false; exception when others then return true; end $$;

create temp table res(ac text, pass boolean, detail text) on commit drop;
-- `\gset` es de psql y aquí no existe: el id del grupo viaja en esta tabla.
create temp table ctx(k text primary key, v uuid) on commit drop;
grant insert, select on res to authenticated, anon;
grant insert, select, update on ctx to authenticated, anon;

insert into public.friend_edges (requester_id, addressee_id, status, responded_at) values
 ('b2000000-0000-4000-8000-0000000000f1','b2000000-0000-4000-8000-0000000000f2','accepted',now()),
 ('b2000000-0000-4000-8000-0000000000f1','b2000000-0000-4000-8000-0000000000f3','accepted',now()),
 ('b2000000-0000-4000-8000-0000000000f1','b2000000-0000-4000-8000-0000000000f4','accepted',now()),
 ('b2000000-0000-4000-8000-0000000000f1','b2000000-0000-4000-8000-0000000000f5','accepted',now());

insert into public.venues (id,name,city,capacity) values ('b2000000-0000-4000-8000-0000000000b1','Local Grupos','Lima',5000);
insert into public.organizers (id, legal_name, ruc, status, created_by)
values ('b2000000-0000-4000-8000-0000000000c1','Grupos SAC','20512000001','approved','b2000000-0000-4000-8000-0000000000f6');
insert into public.events (id, organizer_id, venue_id, title, slug, status, visibility, starts_at, doors_at, capacity, nomination_mode) values
 ('b2000000-0000-4000-8000-0000000000e1','b2000000-0000-4000-8000-0000000000c1','b2000000-0000-4000-8000-0000000000b1','Evento grupo','ev-grupo-12','published','public', now()+interval '30 days', now()+interval '30 days'-interval '2 hours',5000,'flexible'),
 ('b2000000-0000-4000-8000-0000000000e2','b2000000-0000-4000-8000-0000000000c1','b2000000-0000-4000-8000-0000000000b1','Otro evento','ev-grupo-12b','published','public', now()+interval '40 days', now()+interval '40 days'-interval '2 hours',5000,'flexible');
insert into public.zones (id, event_id, name, kind, numbered, capacity) values
 ('b2000000-0000-4000-8000-0000000000a1','b2000000-0000-4000-8000-0000000000e1','General','standing',false,4000),
 ('b2000000-0000-4000-8000-0000000000a2','b2000000-0000-4000-8000-0000000000e2','General','standing',false,4000);
insert into public.price_phases (id, event_id, name, kind, starts_at, ends_at) values
 ('b2000000-0000-4000-8000-0000000000d1','b2000000-0000-4000-8000-0000000000e1','Única','regular',now()-interval '10 days',now()+interval '10 days'),
 ('b2000000-0000-4000-8000-0000000000d2','b2000000-0000-4000-8000-0000000000e2','Única','regular',now()-interval '10 days',now()+interval '10 days');
insert into public.price_tiers (id, event_id, zone_id, phase_id, price_cents, stock, sold) values
 ('b2000000-0000-4000-8000-0000000000c2','b2000000-0000-4000-8000-0000000000e1','b2000000-0000-4000-8000-0000000000a1','b2000000-0000-4000-8000-0000000000d1',5000,100,0),
 ('b2000000-0000-4000-8000-0000000000c3','b2000000-0000-4000-8000-0000000000e2','b2000000-0000-4000-8000-0000000000a2','b2000000-0000-4000-8000-0000000000d2',5000,100,0);

-- Tres órdenes: la buena (3 ítems, mismo evento), una de otro evento (AC-10) y
-- una con 2 ítems (AC-11). `reserved_until` no es opcional: la constraint
-- `orders_reserved_has_deadline` ata el estado con el plazo.
insert into public.orders (id, event_id, buyer_id, status, subtotal_cents, service_charge_cents, total_cents, reserved_until) values
 ('b2000000-0000-4000-8000-00000000d001','b2000000-0000-4000-8000-0000000000e1','b2000000-0000-4000-8000-0000000000f1','reserved',15000,900,15900, now()+interval '10 minutes'),
 ('b2000000-0000-4000-8000-00000000d002','b2000000-0000-4000-8000-0000000000e2','b2000000-0000-4000-8000-0000000000f1','reserved',15000,900,15900, now()+interval '10 minutes'),
 ('b2000000-0000-4000-8000-00000000d003','b2000000-0000-4000-8000-0000000000e1','b2000000-0000-4000-8000-0000000000f1','reserved',10000,600,10600, now()+interval '10 minutes');
-- Los `created_at` van escalonados: el reparto de slots ordena por ellos, y con
-- tres iguales el resultado dependería del desempate por id.
insert into public.order_items (id, order_id, price_tier_id, unit_price_cents, created_at) values
 ('b2000000-0000-4000-8000-00000000e001','b2000000-0000-4000-8000-00000000d001','b2000000-0000-4000-8000-0000000000c2',5000, now()),
 ('b2000000-0000-4000-8000-00000000e002','b2000000-0000-4000-8000-00000000d001','b2000000-0000-4000-8000-0000000000c2',5000, now()+interval '1 ms'),
 ('b2000000-0000-4000-8000-00000000e003','b2000000-0000-4000-8000-00000000d001','b2000000-0000-4000-8000-0000000000c2',5000, now()+interval '2 ms'),
 ('b2000000-0000-4000-8000-00000000e011','b2000000-0000-4000-8000-00000000d002','b2000000-0000-4000-8000-0000000000c3',5000, now()),
 ('b2000000-0000-4000-8000-00000000e012','b2000000-0000-4000-8000-00000000d002','b2000000-0000-4000-8000-0000000000c3',5000, now()),
 ('b2000000-0000-4000-8000-00000000e013','b2000000-0000-4000-8000-00000000d002','b2000000-0000-4000-8000-0000000000c3',5000, now()),
 ('b2000000-0000-4000-8000-00000000e021','b2000000-0000-4000-8000-00000000d003','b2000000-0000-4000-8000-0000000000c2',5000, now()),
 ('b2000000-0000-4000-8000-00000000e022','b2000000-0000-4000-8000-00000000d003','b2000000-0000-4000-8000-0000000000c2',5000, now());

-- ═══════════════════════════════════════════════════════════════════════════
-- Formar el grupo
-- ═══════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"b2000000-0000-4000-8000-0000000000f1","role":"authenticated"}';

insert into ctx select 'g', public.create_purchase_group('b2000000-0000-4000-8000-0000000000e1');

insert into res select 'AC-01  crear grupo mete al creador como slot 1',
  (select count(*) from public.group_members
    where group_id = (select v from ctx where k='g')
      and user_id = 'b2000000-0000-4000-8000-0000000000f1' and slot = 1) = 1,
  'creador y miembro son la misma persona';

select public.add_group_member((select v from ctx where k='g'), 'b2000000-0000-4000-8000-0000000000f2');

insert into res select 'AC-02  el creador añade a un amigo: entra como slot 2',
  (select slot from public.group_members
    where group_id = (select v from ctx where k='g')
      and user_id = 'b2000000-0000-4000-8000-0000000000f2') = 2,
  'el slot lo asigna la RPC bajo candado';

-- Sin esta comprobación, `add_group_member` acepta cualquier uuid: es la forma
-- de meter a alguien en una compra que no pidió, y de averiguar qué uuid
-- existen.
insert into res select 'AC-03  añadir a quien NO es amigo falla',
  pg_temp.fails(format($q$select public.add_group_member(%L,'b2000000-0000-4000-8000-0000000000f9')$q$,
    (select v from ctx where k='g'))),
  'la amistad no es un adorno aquí';

select public.add_group_member((select v from ctx where k='g'), 'b2000000-0000-4000-8000-0000000000f3');
select public.add_group_member((select v from ctx where k='g'), 'b2000000-0000-4000-8000-0000000000f4');

insert into res select 'AC-04  un quinto miembro falla (Art. 11)',
  pg_temp.fails(format($q$select public.add_group_member(%L,'b2000000-0000-4000-8000-0000000000f5')$q$,
    (select v from ctx where k='g')))
  and (select count(*) from public.group_members where group_id = (select v from ctx where k='g')) = 4,
  'hasta 4, y siguen siendo 4';

set local request.jwt.claims = '{"sub":"b2000000-0000-4000-8000-0000000000f2","role":"authenticated"}';

insert into res select 'AC-05  quien no es el creador no puede añadir',
  pg_temp.fails(format($q$select public.add_group_member(%L,'b2000000-0000-4000-8000-0000000000f5')$q$,
    (select v from ctx where k='g'))),
  'no_autorizado';

insert into res select 'AC-06  la misma persona no entra en dos grupos del mismo evento',
  pg_temp.fails($q$select public.create_purchase_group('b2000000-0000-4000-8000-0000000000e1')$q$),
  'group_members_one_group_per_event';

insert into ctx select 'g2', public.create_purchase_group('b2000000-0000-4000-8000-0000000000e2');

insert into res select 'AC-07  sí puede estar en grupos de eventos distintos',
  (select count(*) from public.group_members
    where user_id = 'b2000000-0000-4000-8000-0000000000f2') = 2,
  'el índice es por (user_id, event_id), no por usuario';

-- ═══════════════════════════════════════════════════════════════════════════
-- Visibilidad
-- ═══════════════════════════════════════════════════════════════════════════
set local request.jwt.claims = '{"sub":"b2000000-0000-4000-8000-0000000000f9","role":"authenticated"}';

insert into res select 'AC-17  nadie ve grupos ajenos',
  (select count(*) from public.purchase_groups) = 0
  and (select count(*) from public.group_members) = 0,
  'y sin recursión: el helper definer de 0059 rompe el ciclo';

set local request.jwt.claims = '{"sub":"b2000000-0000-4000-8000-0000000000f4","role":"authenticated"}';

insert into res select 'AC-17b un miembro SÍ ve su grupo',
  (select count(*) from public.group_members
    where group_id = (select v from ctx where k='g')) = 4,
  'la otra mitad del guardarraíl';

-- ═══════════════════════════════════════════════════════════════════════════
-- Salir
-- ═══════════════════════════════════════════════════════════════════════════
select public.leave_purchase_group((select v from ctx where k='g'));

-- El conteo se hace desde quien SE QUEDA: medirlo desde f4, que acaba de irse,
-- daría 0 por RLS y no por el producto. Costó una corrida en rojo.
set local request.jwt.claims = '{"sub":"b2000000-0000-4000-8000-0000000000f1","role":"authenticated"}';

insert into res select 'AC-08  un miembro puede salir mientras el grupo está open',
  (select count(*) from public.group_members where group_id = (select v from ctx where k='g')) = 3,
  'de 4 a 3, contado desde quien se queda';

set local request.jwt.claims = '{"sub":"b2000000-0000-4000-8000-0000000000f2","role":"authenticated"}';
select public.leave_purchase_group((select v from ctx where k='g2'));

reset role;
insert into res select 'AC-09  si sale el creador, el grupo queda cancelled y sin miembros',
  (select status from public.purchase_groups where id = (select v from ctx where k='g2'))::text = 'cancelled'
  and (select count(*) from public.group_members where group_id = (select v from ctx where k='g2')) = 0,
  'sin el creador no hay quien pague';

-- ═══════════════════════════════════════════════════════════════════════════
-- Bloquear: aquí se emparejan personas con ítems
-- ═══════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"b2000000-0000-4000-8000-0000000000f1","role":"authenticated"}';

insert into res select 'AC-10  bloquear con una orden de OTRO evento falla',
  pg_temp.fails(format($q$select public.lock_purchase_group(%L,'b2000000-0000-4000-8000-00000000d002')$q$,
    (select v from ctx where k='g'))),
  'si no, el creador engancha el grupo a una orden ajena';

insert into res select 'AC-11  bloquear con menos ítems que miembros falla',
  pg_temp.fails(format($q$select public.lock_purchase_group(%L,'b2000000-0000-4000-8000-00000000d003')$q$,
    (select v from ctx where k='g'))),
  'el todo-o-nada del Art. 11, en una comparación';

select public.lock_purchase_group((select v from ctx where k='g'), 'b2000000-0000-4000-8000-00000000d001');

insert into res select 'AC-12  bloquear pone locked, order_id y reparte los order_item_id',
  (select status from public.purchase_groups where id=(select v from ctx where k='g'))::text = 'locked'
  and (select order_id from public.purchase_groups where id=(select v from ctx where k='g'))
      = 'b2000000-0000-4000-8000-00000000d001'
  and (select count(*) from public.group_members
        where group_id=(select v from ctx where k='g') and order_item_id is not null) = 3
  and (select count(distinct order_item_id) from public.group_members
        where group_id=(select v from ctx where k='g')) = 3,
  'tres miembros, tres ítems distintos';

insert into res select 'AC-13  con el grupo locked, añadir o salir falla',
  pg_temp.fails(format($q$select public.add_group_member(%L,'b2000000-0000-4000-8000-0000000000f4')$q$,
    (select v from ctx where k='g')))
  and pg_temp.fails(format($q$select public.leave_purchase_group(%L)$q$,
    (select v from ctx where k='g'))),
  'salirse dejaría una entrada pagada sin dueño';

-- ═══════════════════════════════════════════════════════════════════════════
-- El pago · lo que decide si la función es real
-- ═══════════════════════════════════════════════════════════════════════════
-- Los tickets se emiten como lo hace `confirm_payment`: uno por order_item, con
-- `owner_id = comprador`. El trigger tiene que corregirlo ANTES de que la fila
-- exista. Se hace con un insert directo y no llamando a `confirm_payment`
-- porque lo que se prueba aquí es el trigger, no el pago — y el pago ya tiene
-- su propia suite en 004.
reset role;
insert into public.tickets (code, event_id, order_item_id, zone_id, owner_id, original_owner_id, status, face_value_cents)
select 'FVT-012-' || right(oi.id::text, 8), 'b2000000-0000-4000-8000-0000000000e1', oi.id,
       'b2000000-0000-4000-8000-0000000000a1',
       'b2000000-0000-4000-8000-0000000000f1', 'b2000000-0000-4000-8000-0000000000f1',
       'active', 5000
  from public.order_items oi where oi.order_id = 'b2000000-0000-4000-8000-00000000d001';

insert into res select 'AC-14  al pagar, cada ticket nace con SU miembro como dueño',
  (select count(*) from public.tickets t
     join public.group_members gm on gm.order_item_id = t.order_item_id
    where gm.group_id = (select v from ctx where k='g')
      and t.owner_id = gm.user_id
      and t.original_owner_id = gm.user_id) = 3,
  'se insertaron con owner = comprador y el trigger lo corrigió';

insert into res select 'AC-14b y los tres dueños son personas DISTINTAS',
  (select count(distinct owner_id) from public.tickets
    where order_item_id in (select order_item_id from public.group_members
                             where group_id = (select v from ctx where k='g'))) = 3,
  'sin esto la compra grupal sería decorativa';

update public.orders set status='paid', paid_at=now() where id='b2000000-0000-4000-8000-00000000d001';

insert into res select 'AC-15  orders.buyer_id sigue siendo quien pagó',
  (select buyer_id from public.orders where id='b2000000-0000-4000-8000-00000000d001')
    = 'b2000000-0000-4000-8000-0000000000f1',
  'la comisión y el dashboard del organizador no se enteran de nada';

insert into res select 'AC-20  el grupo pasa a completed cuando su orden se paga',
  (select status from public.purchase_groups where id=(select v from ctx where k='g'))::text = 'completed',
  'trigger sobre orders: confirm_payment inserta los tickets DESPUÉS del paid';

-- AC-16 · una compra normal, sin grupo por medio
insert into public.orders (id, event_id, buyer_id, status, subtotal_cents, service_charge_cents, total_cents, paid_at)
values ('b2000000-0000-4000-8000-00000000d009','b2000000-0000-4000-8000-0000000000e1','b2000000-0000-4000-8000-0000000000f2','paid',5000,300,5300,now());
insert into public.order_items (id, order_id, price_tier_id, unit_price_cents)
values ('b2000000-0000-4000-8000-00000000e099','b2000000-0000-4000-8000-00000000d009','b2000000-0000-4000-8000-0000000000c2',5000);
insert into public.tickets (id, code, event_id, order_item_id, zone_id, owner_id, original_owner_id, status, face_value_cents)
values ('b2000000-0000-4000-8000-000000009099','FVT-012-SOLO','b2000000-0000-4000-8000-0000000000e1','b2000000-0000-4000-8000-00000000e099','b2000000-0000-4000-8000-0000000000a1','b2000000-0000-4000-8000-0000000000f2','b2000000-0000-4000-8000-0000000000f2','active',5000);

insert into res select 'AC-16  un ticket sin miembro (compra normal) no cambia de dueño',
  (select owner_id from public.tickets where id='b2000000-0000-4000-8000-000000009099')
    = 'b2000000-0000-4000-8000-0000000000f2',
  'el trigger no toca lo que no es de un grupo';

-- ═══════════════════════════════════════════════════════════════════════════
-- Superficie de escritura
-- ═══════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"b2000000-0000-4000-8000-0000000000f1","role":"authenticated"}';

insert into res select 'AC-18a nadie inserta miembros a mano',
  pg_temp.fails(format($q$insert into public.group_members (group_id,user_id,event_id,slot)
    values (%L,'b2000000-0000-4000-8000-0000000000f9','b2000000-0000-4000-8000-0000000000e1',4)$q$,
    (select v from ctx where k='g'))),
  'el slot y el estado no los escribe el cliente';

insert into res select 'AC-18b ni cambia el estado del grupo',
  pg_temp.fails(format($q$update public.purchase_groups set status='completed' where id=%L$q$,
    (select v from ctx where k='g'))),
  'una transición de estado vive en la RPC';

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

insert into res select 'AC-19  anon no lee grupos',
  pg_temp.fails($q$select count(*) from public.purchase_groups$q$)
  and pg_temp.fails($q$select count(*) from public.group_members$q$),
  'permission denied: la 0009 le quitó el select por defecto';

-- ── Resultado ───────────────────────────────────────────────────────────────
reset role;

select ac, case when pass then '✓' else '✗ FALLA' end as r, detail
from res order by ac;

select count(*) filter (where not pass or pass is null) as fallos,
       count(*) as total
from res;

rollback;
