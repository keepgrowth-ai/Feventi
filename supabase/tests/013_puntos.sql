-- 013 Puntos por asistencia — pruebas de política
--
-- Corre entero dentro de begin … rollback: no deja rastro.
--   mcp__supabase__execute_sql  con el contenido de este archivo
--
-- Bloque de identificadores de esta suite: `b3000000-0000-4000-8000-…`,
-- RUC `20513000001`.
--
-- Los cuatro checkins los escanea el MISMO staff a propósito: así AC-05 puede
-- comprobar que el punto NO se le abona a quien escanea. Confundir al dueño del
-- ticket con el del turno premiaría al portero por trabajar.

begin;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at)
values
 ('b3000000-0000-4000-8000-0000000000f1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','fan013@t.local','x',now(),'{}','{"full_name":"Fan Puntos"}',now(),now()),
 ('b3000000-0000-4000-8000-0000000000f2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','staff013@t.local','x',now(),'{}','{"full_name":"Staff Puntos"}',now(),now()),
 ('b3000000-0000-4000-8000-0000000000f3','00000000-0000-0000-0000-000000000000','authenticated','authenticated','otro013@t.local','x',now(),'{}','{"full_name":"Otro Fan"}',now(),now()),
 ('b3000000-0000-4000-8000-0000000000f6','00000000-0000-0000-0000-000000000000','authenticated','authenticated','org013@t.local','x',now(),'{}','{}',now(),now());

create or replace function pg_temp.fails(p_sql text) returns boolean
language plpgsql as $$
begin execute p_sql; return false;
exception when others then return true; end $$;

create temp table res(ac text, pass boolean, detail text) on commit drop;
grant insert, select on res to authenticated, anon;

-- ── Un evento con cuatro entradas: tres del fan y una de otro ───────────────
insert into public.venues (id,name,city,capacity)
values ('b3000000-0000-4000-8000-0000000000b1','Local Puntos','Lima',5000);
insert into public.organizers (id, legal_name, ruc, status, created_by)
values ('b3000000-0000-4000-8000-0000000000c1','Puntos SAC','20513000001','approved','b3000000-0000-4000-8000-0000000000f6');
insert into public.events (id, organizer_id, venue_id, title, slug, status, visibility,
                           starts_at, doors_at, capacity, nomination_mode)
values ('b3000000-0000-4000-8000-0000000000e1','b3000000-0000-4000-8000-0000000000c1','b3000000-0000-4000-8000-0000000000b1',
        'Evento puntos','ev-puntos-13','published','public', now()+interval '1 hour', now()-interval '30 minutes',5000,'flexible');
insert into public.zones (id, event_id, name, kind, numbered, capacity)
values ('b3000000-0000-4000-8000-0000000000a1','b3000000-0000-4000-8000-0000000000e1','General','standing',false,4000);
insert into public.price_phases (id, event_id, name, kind, starts_at, ends_at)
values ('b3000000-0000-4000-8000-0000000000d1','b3000000-0000-4000-8000-0000000000e1','Única','regular',now()-interval '10 days',now()+interval '10 days');
insert into public.price_tiers (id, event_id, zone_id, phase_id, price_cents, stock, sold)
values ('b3000000-0000-4000-8000-0000000000c2','b3000000-0000-4000-8000-0000000000e1','b3000000-0000-4000-8000-0000000000a1','b3000000-0000-4000-8000-0000000000d1',5000,100,4);
insert into public.orders (id, event_id, buyer_id, status, subtotal_cents, service_charge_cents, total_cents, paid_at)
values ('b3000000-0000-4000-8000-00000000d001','b3000000-0000-4000-8000-0000000000e1','b3000000-0000-4000-8000-0000000000f1','paid',20000,1200,21200,now());
insert into public.order_items (id, order_id, price_tier_id, unit_price_cents) values
 ('b3000000-0000-4000-8000-00000000e001','b3000000-0000-4000-8000-00000000d001','b3000000-0000-4000-8000-0000000000c2',5000),
 ('b3000000-0000-4000-8000-00000000e002','b3000000-0000-4000-8000-00000000d001','b3000000-0000-4000-8000-0000000000c2',5000),
 ('b3000000-0000-4000-8000-00000000e003','b3000000-0000-4000-8000-00000000d001','b3000000-0000-4000-8000-0000000000c2',5000),
 ('b3000000-0000-4000-8000-00000000e004','b3000000-0000-4000-8000-00000000d001','b3000000-0000-4000-8000-0000000000c2',5000);
insert into public.tickets (id, code, event_id, order_item_id, zone_id, owner_id, original_owner_id, status, face_value_cents) values
 ('b3000000-0000-4000-8000-000000009001','FVT-013-0001','b3000000-0000-4000-8000-0000000000e1','b3000000-0000-4000-8000-00000000e001','b3000000-0000-4000-8000-0000000000a1','b3000000-0000-4000-8000-0000000000f1','b3000000-0000-4000-8000-0000000000f1','active',5000),
 ('b3000000-0000-4000-8000-000000009002','FVT-013-0002','b3000000-0000-4000-8000-0000000000e1','b3000000-0000-4000-8000-00000000e002','b3000000-0000-4000-8000-0000000000a1','b3000000-0000-4000-8000-0000000000f1','b3000000-0000-4000-8000-0000000000f1','active',5000),
 ('b3000000-0000-4000-8000-000000009003','FVT-013-0003','b3000000-0000-4000-8000-0000000000e1','b3000000-0000-4000-8000-00000000e003','b3000000-0000-4000-8000-0000000000a1','b3000000-0000-4000-8000-0000000000f1','b3000000-0000-4000-8000-0000000000f1','active',5000),
 ('b3000000-0000-4000-8000-000000009004','FVT-013-0004','b3000000-0000-4000-8000-0000000000e1','b3000000-0000-4000-8000-00000000e004','b3000000-0000-4000-8000-0000000000a1','b3000000-0000-4000-8000-0000000000f3','b3000000-0000-4000-8000-0000000000f3','active',5000);

-- Un checkin por resultado. Los cuatro los escanea f2.
insert into public.checkins (id, event_id, ticket_id, staff_id, gate, result, reason) values
 ('b3000000-0000-4000-8000-00000000a001','b3000000-0000-4000-8000-0000000000e1','b3000000-0000-4000-8000-000000009001','b3000000-0000-4000-8000-0000000000f2','P1','allowed','ok'),
 ('b3000000-0000-4000-8000-00000000a002','b3000000-0000-4000-8000-0000000000e1','b3000000-0000-4000-8000-000000009001','b3000000-0000-4000-8000-0000000000f2','P1','already_used','already_used'),
 ('b3000000-0000-4000-8000-00000000a003','b3000000-0000-4000-8000-0000000000e1','b3000000-0000-4000-8000-000000009002','b3000000-0000-4000-8000-0000000000f2','P1','denied','wrong_zone'),
 ('b3000000-0000-4000-8000-00000000a004','b3000000-0000-4000-8000-0000000000e1','b3000000-0000-4000-8000-000000009003','b3000000-0000-4000-8000-0000000000f2','P1','manual_review','dni_mode');

-- ═══════════════════════════════════════════════════════════════════════════
-- Quién suma y quién no
-- ═══════════════════════════════════════════════════════════════════════════
insert into res select 'AC-01  un checkin allowed crea un asiento de 50 puntos',
  (select count(*) from public.point_ledger where checkin_id='b3000000-0000-4000-8000-00000000a001') = 1
  and (select points from public.point_ledger where checkin_id='b3000000-0000-4000-8000-00000000a001') = 50,
  'el trigger corre en la misma transacción que el ingreso (AC-11)';

insert into res select 'AC-02  un checkin already_used NO crea asiento',
  not exists (select 1 from public.point_ledger where checkin_id='b3000000-0000-4000-8000-00000000a002'),
  'escanear dos veces no paga dos veces';

insert into res select 'AC-03  un checkin denied no crea asiento',
  not exists (select 1 from public.point_ledger where checkin_id='b3000000-0000-4000-8000-00000000a003'),
  'ok';

insert into res select 'AC-04  un checkin manual_review no crea asiento',
  not exists (select 1 from public.point_ledger where checkin_id='b3000000-0000-4000-8000-00000000a004'),
  'lo confirma un humano; esa corrección es Fase 2';

insert into res select 'AC-05  el punto va al DUEÑO del ticket, no al staff que escanea',
  (select user_id from public.point_ledger where checkin_id='b3000000-0000-4000-8000-00000000a001')
    = 'b3000000-0000-4000-8000-0000000000f1'
  and not exists (select 1 from public.point_ledger where user_id='b3000000-0000-4000-8000-0000000000f2'),
  'confundirlos premiaría al portero por trabajar';

insert into res select 'AC-06  dos asientos sobre el mismo checkin fallan por el índice',
  pg_temp.fails($q$insert into public.point_ledger (user_id, kind, points, checkin_id)
    values ('b3000000-0000-4000-8000-0000000000f1','checkin',50,'b3000000-0000-4000-8000-00000000a001')$q$),
  'point_ledger_one_per_checkin';

-- ═══════════════════════════════════════════════════════════════════════════
-- El saldo y la superficie
-- ═══════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"b3000000-0000-4000-8000-0000000000f1","role":"authenticated"}';

insert into res select 'AC-07  v_my_points suma solo lo mío',
  (select total from public.v_my_points) = 50,
  'un solo ingreso permitido';

insert into res select 'AC-08  no veo los asientos de otro',
  (select count(*) from public.point_ledger
    where user_id <> 'b3000000-0000-4000-8000-0000000000f1') = 0,
  'RLS por dueño';

-- Sin esta mitad, AC-08 daría verde con la tabla vacía para todo el mundo.
insert into res select 'AC-08b y sí veo los míos (camino feliz)',
  (select count(*) from public.point_ledger) = 1,
  'la otra mitad del guardarraíl';

insert into res select 'AC-09a nadie inserta asientos a mano (Art. 8.1)',
  pg_temp.fails($q$insert into public.point_ledger (user_id, kind, points)
    values ('b3000000-0000-4000-8000-0000000000f1','checkin',9999)$q$),
  'ni el dueño escribe su propio saldo';

insert into res select 'AC-09b ni los actualiza',
  pg_temp.fails($q$update public.point_ledger set points = 9999
    where user_id = 'b3000000-0000-4000-8000-0000000000f1'$q$),
  'append-only';

insert into res select 'AC-09c ni los borra',
  pg_temp.fails($q$delete from public.point_ledger
    where user_id = 'b3000000-0000-4000-8000-0000000000f1'$q$),
  'append-only';

set local request.jwt.claims = '{"sub":"b3000000-0000-4000-8000-0000000000f3","role":"authenticated"}';

insert into res select 'AC-07b el que no entró tiene cero, no null',
  (select total from public.v_my_points) = 0,
  'coalesce: la wallet no pinta NaN';

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

insert into res select 'AC-10  anon no lee el libro mayor',
  pg_temp.fails($q$select count(*) from public.point_ledger$q$),
  'permission denied';

insert into res select 'AC-10b anon no lee el saldo',
  pg_temp.fails($q$select total from public.v_my_points$q$),
  'el grant es solo para authenticated';

-- ── Resultado ───────────────────────────────────────────────────────────────
reset role;

select ac, case when pass then '✓' else '✗ FALLA' end as r, detail
from res order by ac;

select count(*) filter (where not pass or pass is null) as fallos,
       count(*) as total
from res;

rollback;
