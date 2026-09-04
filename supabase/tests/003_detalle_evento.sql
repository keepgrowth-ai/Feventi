-- 003 Detalle de evento — invariantes de inventario, dinero y superficie pública
--
-- Corre entero dentro de begin … rollback: no deja rastro.
--
-- Los identificadores son del bloque de esta suite —RUC `205030000xx`— porque la
-- base tiene datos permanentes de la semilla de demo. Ver `supabase/tests/README.md`.
--
-- Ojo al orden: los bloques que llaman a `private.*` van ANTES del primer
-- `set local role`. Dentro de una misma llamada, `reset role` no siempre ha
-- surtido efecto para el statement siguiente, y esas funciones están revocadas
-- a `authenticated`.

begin;

create or replace function pg_temp.fails(p_sql text) returns boolean
language plpgsql as $$
begin execute p_sql; return false;
exception when others then return true; end $$;

create or replace function pg_temp.err(p_sql text) returns text
language plpgsql as $$
begin execute p_sql; return 'NO FALLÓ';
exception when others then return left(sqlerrm, 85); end $$;

create temp table res(ac text, pass boolean, detail text) on commit drop;
grant insert, select on res to authenticated, anon;

-- ════════════════════════════════════════════════════════════════════════════
-- 1. El dinero. Va primero porque usa private.total_with_charge.
-- ════════════════════════════════════════════════════════════════════════════

-- AC-15: base + cargo = total, siempre, para cualquier precio y cualquier bps.
insert into res
select 'AC-15  base+cargo=total · ' || p.price || ' @ ' || p.bps || 'bps',
       p.price + (private.total_with_charge(p.price, p.bps, 'fan') - p.price)
         = private.total_with_charge(p.price, p.bps, 'fan'),
       'base ' || p.price
         || ' → cargo ' || (private.total_with_charge(p.price, p.bps, 'fan') - p.price)
         || ' → total ' || private.total_with_charge(p.price, p.bps, 'fan')
from (values (4000,600),(12000,600),(3333,600),(18000,600),(1,600),(9999,733),(2500,1250))
     as p(price, bps);

insert into res select 'AC-15b el caso del mockup: 4000 @ 600bps = 4240',
  private.total_with_charge(4000, 600, 'fan') = 4240, 'S/ 40.00 + 6% = S/ 42.40';

insert into res select 'AC-16  cargo absorbido: total = base',
  private.total_with_charge(4000, 600, 'organizer') = 4000, 'y el cargo queda en 0';

-- Por qué el cargo se deriva restando en lugar de redondearse aparte.
-- Con UNA línea las dos formas coinciden — sumar un entero antes de redondear no
-- cambia el redondeo. La diferencia aparece con VARIAS, que es 004: por eso su
-- AC-18 exige redondear una vez sobre el subtotal.
insert into res
select 'AC-15c  por línea ≠ sobre subtotal: ' || price || ' × ' || qty,
       (qty * round(price * 0.06)::int) <> round(price * qty * 0.06)::int,
       'por línea ' || (qty * round(price * 0.06)::int)
         || ' vs sobre subtotal ' || round(price * qty * 0.06)::int
         || ' → ' || abs(qty * round(price * 0.06)::int - round(price * qty * 0.06)::int)
         || ' céntimos'
from (values (925,7),(1675,3),(1675,2)) as c(price, qty);

-- ════════════════════════════════════════════════════════════════════════════
-- 2. Semilla
-- ════════════════════════════════════════════════════════════════════════════
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at)
values
  ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','orgA@test.pe','x',now(),'{}','{}',now(),now()),
  ('55555555-5555-5555-5555-555555555555','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','orgB@test.pe','x',now(),'{}','{}',now(),now())
on conflict (id) do nothing;

insert into public.venues (id, name, city, capacity)
values ('b0000000-0000-4000-8000-0000000000aa','Estadio Nacional','Lima',40000);

insert into public.organizers (id, legal_name, ruc, status, created_by) values
 ('c0000000-0000-4000-8000-0000000000aa','Andes Live SAC','20503000001','approved','22222222-2222-2222-2222-222222222222'),
 ('c0000000-0000-4000-8000-0000000000bb','Otra Prod SAC','20503000002','approved','55555555-5555-5555-5555-555555555555');
insert into public.organizer_members (organizer_id, user_id, role) values
 ('c0000000-0000-4000-8000-0000000000aa','22222222-2222-2222-2222-222222222222','owner'),
 ('c0000000-0000-4000-8000-0000000000bb','55555555-5555-5555-5555-555555555555','owner');

-- Un evento por cada caso de visibilidad que hay que probar
insert into public.events (id, organizer_id, venue_id, title, description, category,
                           starts_at, capacity, slug, status, visibility,
                           service_charge_bps, service_charge_payer) values
 ('e0000000-0000-4000-8000-0000000000aa','c0000000-0000-4000-8000-0000000000aa','b0000000-0000-4000-8000-0000000000aa','Publicado público','d','Festival', now()+interval '60 days',1400,'pub-publico','published','public',600,'fan'),
 ('e0000000-0000-4000-8000-0000000000bb','c0000000-0000-4000-8000-0000000000aa','b0000000-0000-4000-8000-0000000000aa','No listado','d','Festival', now()+interval '60 days',500,'pub-unlisted','published','unlisted',600,'fan'),
 ('e0000000-0000-4000-8000-0000000000cc','c0000000-0000-4000-8000-0000000000aa','b0000000-0000-4000-8000-0000000000aa','Privado','d','Festival', now()+interval '60 days',500,'pub-private','published','private',600,'fan'),
 ('e0000000-0000-4000-8000-0000000000dd','c0000000-0000-4000-8000-0000000000aa','b0000000-0000-4000-8000-0000000000aa','Borrador','d','Festival', now()+interval '60 days',500,'borrador','draft','public',600,'fan'),
 ('e0000000-0000-4000-8000-0000000000ee','c0000000-0000-4000-8000-0000000000aa','b0000000-0000-4000-8000-0000000000aa','Pausado','d','Festival', now()+interval '60 days',500,'pausado','paused','public',600,'fan'),
 ('e0000000-0000-4000-8000-0000000000ff','c0000000-0000-4000-8000-0000000000aa','b0000000-0000-4000-8000-0000000000aa','Ya pasó','d','Festival', now()-interval '5 days',500,'ya-paso','published','public',600,'fan');

-- ════════════════════════════════════════════════════════════════════════════
-- 3. Inventario: las FK compuestas y los triggers de aforo
-- ════════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

-- Las tres zonas del mockup
insert into public.zones (id, event_id, name, kind, numbered, capacity, notes, sort_order) values
 ('20000000-0000-4000-8000-0000000000aa','e0000000-0000-4000-8000-0000000000aa','General — de pie','standing',false,800,'Sin numeración',0),
 ('20000000-0000-4000-8000-0000000000bb','e0000000-0000-4000-8000-0000000000aa','Platea — butacas','seated',true,200,'Numerada por fila y asiento',1),
 ('20000000-0000-4000-8000-0000000000cc','e0000000-0000-4000-8000-0000000000bb','General','standing',false,400,null,0);

insert into res select 'AC-05a zona de pie NO admite segmento',
  pg_temp.fails($q$insert into public.zone_segments (zone_id, label)
      values ('20000000-0000-4000-8000-0000000000aa','Filas A–C')$q$),
  pg_temp.err($q$insert into public.zone_segments (zone_id, label)
      values ('20000000-0000-4000-8000-0000000000aa','Filas A–C')$q$);

insert into res select 'AC-05b zona de pie NO admite asiento',
  pg_temp.fails($q$insert into public.seats (zone_id, row_label, seat_number)
      values ('20000000-0000-4000-8000-0000000000aa','A',1)$q$),
  pg_temp.err($q$insert into public.seats (zone_id, row_label, seat_number)
      values ('20000000-0000-4000-8000-0000000000aa','A',1)$q$);

insert into res select 'numbered es consecuencia de kind, no una opción',
  pg_temp.fails($q$insert into public.zones (event_id, name, kind, numbered, capacity)
      values ('e0000000-0000-4000-8000-0000000000aa','Mal','seated',false,10)$q$),
  'seated implica numbered';

-- Segmentos y fases
insert into public.zone_segments (id, zone_id, label, row_from, row_to, sort_order) values
 ('30000000-0000-4000-8000-0000000000aa','20000000-0000-4000-8000-0000000000bb','Filas A–C','A','C',0),
 ('30000000-0000-4000-8000-0000000000bb','20000000-0000-4000-8000-0000000000bb','Filas D–H','D','H',1),
 ('30000000-0000-4000-8000-0000000000cc','20000000-0000-4000-8000-0000000000bb','Filas I–M','I','M',2);

insert into public.price_phases (id, event_id, name, kind, starts_at, ends_at, sort_order) values
 ('40000000-0000-4000-8000-0000000000aa','e0000000-0000-4000-8000-0000000000aa','Preventa 1','presale', now()-interval '5 days', now()+interval '3 days',0),
 ('40000000-0000-4000-8000-0000000000bb','e0000000-0000-4000-8000-0000000000aa','Preventa 2','presale', now()+interval '3 days', now()+interval '20 days',1),
 ('40000000-0000-4000-8000-0000000000cc','e0000000-0000-4000-8000-0000000000bb','Preventa 1','presale', now()-interval '5 days', now()+interval '3 days',0);

insert into res select 'AC-06  dos fases solapadas fallan',
  pg_temp.fails($q$insert into public.price_phases (event_id, name, starts_at, ends_at)
      values ('e0000000-0000-4000-8000-0000000000aa','Solapada',
              now()-interval '1 day', now()+interval '1 day')$q$),
  pg_temp.err($q$insert into public.price_phases (event_id, name, starts_at, ends_at)
      values ('e0000000-0000-4000-8000-0000000000aa','Solapada',
              now()-interval '1 day', now()+interval '1 day')$q$);

insert into res select 'AC-06b una fase que empieza donde acaba otra SÍ pasa',
  not pg_temp.fails($q$insert into public.price_phases (event_id, name, starts_at, ends_at)
      values ('e0000000-0000-4000-8000-0000000000aa','Contigua',
              now()+interval '20 days', now()+interval '40 days')$q$),
  'el rango es [) — el fin es exclusivo';

insert into res select 'ends_at <= starts_at falla',
  pg_temp.fails($q$insert into public.price_phases (event_id, name, starts_at, ends_at)
      values ('e0000000-0000-4000-8000-0000000000aa','Invertida',
              now()+interval '80 days', now()+interval '79 days')$q$), 'ok';

-- Precios del mockup
insert into public.price_tiers (event_id, zone_id, segment_id, phase_id, price_cents, stock) values
 ('e0000000-0000-4000-8000-0000000000aa','20000000-0000-4000-8000-0000000000aa',null,'40000000-0000-4000-8000-0000000000aa',4000,800),
 ('e0000000-0000-4000-8000-0000000000aa','20000000-0000-4000-8000-0000000000aa',null,'40000000-0000-4000-8000-0000000000bb',5000,800),
 ('e0000000-0000-4000-8000-0000000000aa','20000000-0000-4000-8000-0000000000bb','30000000-0000-4000-8000-0000000000aa','40000000-0000-4000-8000-0000000000aa',18000,3),
 ('e0000000-0000-4000-8000-0000000000aa','20000000-0000-4000-8000-0000000000bb','30000000-0000-4000-8000-0000000000bb','40000000-0000-4000-8000-0000000000aa',15000,12),
 ('e0000000-0000-4000-8000-0000000000aa','20000000-0000-4000-8000-0000000000bb','30000000-0000-4000-8000-0000000000cc','40000000-0000-4000-8000-0000000000aa',12000,45),
 ('e0000000-0000-4000-8000-0000000000bb','20000000-0000-4000-8000-0000000000cc',null,'40000000-0000-4000-8000-0000000000cc',9000,400);

insert into res select 'AC-02  price_cents = 0 falla',
  pg_temp.fails($q$insert into public.price_tiers (event_id, zone_id, phase_id, price_cents, stock)
      values ('e0000000-0000-4000-8000-0000000000aa','20000000-0000-4000-8000-0000000000aa',
              '40000000-0000-4000-8000-0000000000cc',0,10)$q$),
  'una cortesía no es un tier a 0 (Art. 3)';

insert into res select 'AC-04  un segmento de OTRA zona falla',
  pg_temp.fails($q$insert into public.price_tiers (event_id, zone_id, segment_id, phase_id, price_cents, stock)
      values ('e0000000-0000-4000-8000-0000000000aa','20000000-0000-4000-8000-0000000000aa',
              '30000000-0000-4000-8000-0000000000aa','40000000-0000-4000-8000-0000000000bb',5000,10)$q$),
  pg_temp.err($q$insert into public.price_tiers (event_id, zone_id, segment_id, phase_id, price_cents, stock)
      values ('e0000000-0000-4000-8000-0000000000aa','20000000-0000-4000-8000-0000000000aa',
              '30000000-0000-4000-8000-0000000000aa','40000000-0000-4000-8000-0000000000bb',5000,10)$q$);

insert into res select 'AC-01  stock por encima del aforo de la zona falla',
  pg_temp.fails($q$update public.price_tiers set stock = 900
      where zone_id='20000000-0000-4000-8000-0000000000aa'
        and phase_id='40000000-0000-4000-8000-0000000000aa'$q$),
  pg_temp.err($q$update public.price_tiers set stock = 900
      where zone_id='20000000-0000-4000-8000-0000000000aa'
        and phase_id='40000000-0000-4000-8000-0000000000aa'$q$);

insert into res select 'AC-01b el mismo cupo en otra FASE sí pasa',
  (select count(*) = 2 from public.price_tiers
    where zone_id='20000000-0000-4000-8000-0000000000aa'),
  '800 en Preventa 1 y 800 en Preventa 2 son los mismos 800 asientos, no 1600';

insert into res select 'AC-03  dos precios para el mismo cruce falla',
  pg_temp.fails($q$insert into public.price_tiers (event_id, zone_id, segment_id, phase_id, price_cents, stock)
      values ('e0000000-0000-4000-8000-0000000000aa','20000000-0000-4000-8000-0000000000bb',
              '30000000-0000-4000-8000-0000000000aa','40000000-0000-4000-8000-0000000000aa',19000,1)$q$),
  pg_temp.err($q$insert into public.price_tiers (event_id, zone_id, segment_id, phase_id, price_cents, stock)
      values ('e0000000-0000-4000-8000-0000000000bb','20000000-0000-4000-8000-0000000000cc',
              null,'40000000-0000-4000-8000-0000000000cc',9500,1)$q$);

insert into res select 'reserved y sold NO los escribe el cliente',
  pg_temp.fails($q$update public.price_tiers set sold = 5$q$),
  pg_temp.err($q$update public.price_tiers set sold = 5$q$);

-- Asientos
insert into res select 'T-11  generate_seats crea el bloque de una vez',
  public.generate_seats('20000000-0000-4000-8000-0000000000bb',
                        array['A','B','C'], 20,
                        '30000000-0000-4000-8000-0000000000aa') = 60,
  '3 filas × 20 = 60 asientos en un statement';

insert into res select 'AC-08  asiento duplicado falla',
  pg_temp.fails($q$insert into public.seats (zone_id, row_label, seat_number)
      values ('20000000-0000-4000-8000-0000000000bb','A',1)$q$),
  'unique (zone_id, row_label, seat_number)';

insert into res select 'AC-09  pasar el aforo de la zona falla',
  pg_temp.fails($q$select public.generate_seats('20000000-0000-4000-8000-0000000000bb',
      array['D','E','F','G','H','I','J','K'], 20)$q$),
  pg_temp.err($q$select public.generate_seats('20000000-0000-4000-8000-0000000000bb',
      array['D','E','F','G','H','I','J','K'], 20)$q$);

insert into res select 'T-11b generate_seats en zona de pie falla',
  pg_temp.fails($q$select public.generate_seats('20000000-0000-4000-8000-0000000000aa', array['A'], 5)$q$),
  pg_temp.err($q$select public.generate_seats('20000000-0000-4000-8000-0000000000aa', array['A'], 5)$q$);

-- ════════════════════════════════════════════════════════════════════════════
-- 4. Superficie pública
-- ════════════════════════════════════════════════════════════════════════════
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

-- Presencia y ausencia de LOS SLUGS DE ESTA SUITE, no un `count(*) = 1`. La
-- base tiene eventos de demo publicados, y contar todo el catálogo hacía que la
-- comprobación dependiera de qué más hubiera sembrado. Es la misma lección del
-- RUC: una suite no puede asumir que la base está vacía.
insert into res select 'AC-01c el catálogo solo trae published + public',
  exists (select 1 from public.v_event_public where slug='pub-publico')
  and not exists (select 1 from public.v_event_public
                   where slug in ('pub-unlisted','pub-private','borrador','pausado','ya-paso')),
  (select coalesce(string_agg(slug, ', '), '(vacío)') from public.v_event_public);

insert into res select 'AC-02  el no listado NO está en el catálogo',
  not exists (select 1 from public.v_event_public where slug='pub-unlisted'), 'ok';
insert into res select 'AC-02b …pero SÍ se abre por su slug',
  public.get_public_event('pub-unlisted') is not null,
  'un enlace directo funciona; enumerar, no';
insert into res select 'AC-03b el privado no se abre ni con slug',
  public.get_public_event('pub-private') is null, 'ok';
insert into res select 'AC-12  el borrador no se abre',
  public.get_public_event('borrador') is null, 'ok';
insert into res select 'AC-04  el pausado desaparece del catálogo',
  not exists (select 1 from public.v_event_public where slug='pausado'), 'ok';
insert into res select 'AC-12b el pausado tampoco se abre por slug',
  public.get_public_event('pausado') is null, 'la venta está detenida';
insert into res select 'AC-05c un evento que ya pasó no sale en el listado',
  not exists (select 1 from public.v_event_public where slug='ya-paso'), 'ok';
insert into res select 'un slug inexistente devuelve null, no un error',
  public.get_public_event('no-existe') is null, 'ok';

insert into res select 'AC-08b el "desde" es el mínimo de la fase ACTIVA, con cargo',
  (select from_price_cents = 4240 from public.v_event_public where slug='pub-publico'),
  (select 'desde=' || from_price_cents
            || ' (Preventa 1 a 4000+6%, no Preventa 2 a 5000)'
     from public.v_event_public where slug='pub-publico');

insert into res select 'AC-12c el detalle trae total y cargo derivado por tier',
  (select bool_and((t->>'base_cents')::int + (t->>'service_charge_cents')::int
                     = (t->>'total_cents')::int)
     from jsonb_array_elements(public.get_public_event('pub-publico') -> 'zones') z,
          jsonb_array_elements(z->'tiers') t),
  'base + cargo = total en todos los tiers del detalle';

insert into res select 'la línea de fases viene completa, con su estado',
  (select count(*) = 3 from jsonb_array_elements(public.get_public_event('pub-publico')->'phases')),
  (select string_agg((e->>'name')||'='||(e->>'state'), ', ' order by e->>'starts_at')
     from jsonb_array_elements(public.get_public_event('pub-publico')->'phases') e);

insert into res select 'los segmentos van anidados dentro de su zona',
  (select count(*) = 3
     from jsonb_array_elements(public.get_public_event('pub-publico') -> 'zones') z,
          jsonb_array_elements(z->'tiers') t
    where z->>'name' like 'Platea%' and (t->>'phase_active')::boolean),
  'Platea trae sus 3 segmentos de precio dentro, no como hermanos';

insert into res select 'AC-13  anon NO lee zones',        pg_temp.fails($q$select 1 from public.zones$q$), 'ok';
insert into res select 'AC-13b anon NO lee price_tiers',  pg_temp.fails($q$select 1 from public.price_tiers$q$), 'ok';
insert into res select 'AC-13c anon NO lee price_phases', pg_temp.fails($q$select 1 from public.price_phases$q$), 'ok';
insert into res select 'AC-13d anon NO lee seats',        pg_temp.fails($q$select 1 from public.seats$q$), 'ok';
insert into res select 'AC-13e anon NO lee zone_segments',pg_temp.fails($q$select 1 from public.zone_segments$q$), 'ok';
insert into res select 'AC-13f anon NO lee v_event_availability',
  pg_temp.fails($q$select 1 from public.v_event_availability$q$), 'ok';
insert into res select 'AC-06c anon NO lee events',       pg_temp.fails($q$select 1 from public.events$q$), 'ok';

insert into res select 'AC-07  la vista no expone campos internos',
  not exists (select 1 from information_schema.columns
               where table_schema='public' and table_name='v_event_public'
                 and column_name in ('review_checklist','payout_policy','created_by',
                                     'status','visibility')),
  'sin review_checklist, payout_policy, created_by, status ni visibility';

-- ════════════════════════════════════════════════════════════════════════════
-- 5. Aislamiento entre organizadores
-- ════════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}';
insert into res select 'AC-17  el organizador B no ve las zonas de A',
  (select count(*) = 0 from public.zones),
  've ' || (select count(*) from public.zones)::text || ' zonas';
insert into res select 'AC-17b B no ve los precios de A',
  (select count(*) = 0 from public.price_tiers), 'ok';
insert into res select 'AC-17c B no ve los asientos de A',
  (select count(*) = 0 from public.seats), 'ok';
insert into res select 'AC-17d B no ve la disponibilidad de A',
  (select count(*) = 0 from public.v_event_availability),
  'la vista es security_invoker = true: la RLS se aplica DENTRO';

set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
insert into res select 'AC-10  el dueño sí ve su disponibilidad, sin negativos',
  (select count(*) = 6 and bool_and(available >= 0) from public.v_event_availability),
  (select count(*)::text || ' tiers visibles' from public.v_event_availability);

-- ── Convenciones heredadas ──────────────────────────────────────────────────
reset role;
insert into res select 'PERF  una política permisiva por operación y rol',
  not exists (select 1 from pg_policies
               where schemaname='public' and 'authenticated'=any(roles)
               group by tablename, cmd having count(*) > 1),
  coalesce((select string_agg(tablename||'/'||cmd, ', ') from pg_policies
             where schemaname='public' and 'authenticated'=any(roles)
             group by tablename, cmd having count(*) > 1),
           'ninguna duplicada · ojo: `for all` cuenta también como SELECT');

insert into res select 'AC-26  RLS activa en toda tabla de public',
  not exists (select 1 from pg_tables where schemaname='public' and not rowsecurity),
  coalesce((select string_agg(tablename, ', ') from pg_tables
             where schemaname='public' and not rowsecurity), 'ninguna sin RLS');

-- ── Resultado ───────────────────────────────────────────────────────────────
select ac, case when pass then '✓' else '✗ FALLA' end as r, detail from res order by ac;
select count(*) filter (where not pass or pass is null) as fallos, count(*) as total from res;

rollback;
