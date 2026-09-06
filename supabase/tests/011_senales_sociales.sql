-- 011 Señales sociales — pruebas de política
--
-- Corre entero dentro de begin … rollback: no deja rastro.
--   mcp__supabase__execute_sql  con el contenido de este archivo
--
-- Bloque de identificadores de esta suite: `b1000000-0000-4000-8000-…`,
-- RUC `20511000001`.
--
-- Lo que esta suite protege de verdad: `v_my_event_signals` es `security
-- definer`, así que la RLS de `tickets` NO se evalúa dentro. El `where` de la
-- vista es lo único que separa «cuántos amigos míos van» de «quién ha comprado
-- qué en toda la plataforma». AC-03, AC-05, AC-06 y AC-11 son esa frontera, y
-- las cuatro miran el MISMO número: si sube, la vista se abrió.

begin;

-- ── Semilla · cinco personas ────────────────────────────────────────────────
--   f1 = A  el que mira          f4 = N  amigo en modo ninja
--   f2 = G  amigo con entrada    f5 = X  desconocido con entrada (AC-03)
--   f3 = I  amiga con interés    f6 = O  organizador
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at)
values
 ('b1000000-0000-4000-8000-0000000000f1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','a011@t.local','x',now(),'{}','{"full_name":"Ana Mira"}',now(),now()),
 ('b1000000-0000-4000-8000-0000000000f2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','g011@t.local','x',now(),'{}','{"full_name":"Gonzalo Va"}',now(),now()),
 ('b1000000-0000-4000-8000-0000000000f3','00000000-0000-0000-0000-000000000000','authenticated','authenticated','i011@t.local','x',now(),'{}','{"full_name":"Ines Quiere"}',now(),now()),
 ('b1000000-0000-4000-8000-0000000000f4','00000000-0000-0000-0000-000000000000','authenticated','authenticated','n011@t.local','x',now(),'{}','{"full_name":"Nadia Ninja"}',now(),now()),
 ('b1000000-0000-4000-8000-0000000000f5','00000000-0000-0000-0000-000000000000','authenticated','authenticated','x011@t.local','x',now(),'{}','{"full_name":"Ximena Ajena"}',now(),now()),
 ('b1000000-0000-4000-8000-0000000000f6','00000000-0000-0000-0000-000000000000','authenticated','authenticated','o011@t.local','x',now(),'{}','{}',now(),now());

-- ── Utilidades ──────────────────────────────────────────────────────────────
create or replace function pg_temp.fails(p_sql text) returns boolean
language plpgsql as $$
begin execute p_sql; return false;
exception when others then return true; end $$;

create temp table res(ac text, pass boolean, detail text) on commit drop;
grant insert, select on res to authenticated, anon;

-- ── Amistades: A es amiga de G, I y N. NO de X. ─────────────────────────────
-- Se insertan directas y no por RPC: aquí se prueba la señal, no el alta de
-- amistad. Eso ya lo cubre 010. Las direcciones van mezcladas a propósito —
-- A pidió a G, I pidió a A— porque la simetría (D-39) es parte de lo probado.
insert into public.friend_edges (requester_id, addressee_id, status, responded_at) values
 ('b1000000-0000-4000-8000-0000000000f1','b1000000-0000-4000-8000-0000000000f2','accepted',now()),
 ('b1000000-0000-4000-8000-0000000000f3','b1000000-0000-4000-8000-0000000000f1','accepted',now()),
 ('b1000000-0000-4000-8000-0000000000f1','b1000000-0000-4000-8000-0000000000f4','accepted',now());

-- ── Dos eventos con inventario ──────────────────────────────────────────────
insert into public.venues (id,name,city,capacity)
values ('b1000000-0000-4000-8000-0000000000b1','Local Señales','Lima',5000);

insert into public.organizers (id, legal_name, trade_name, ruc, status, created_by)
values ('b1000000-0000-4000-8000-0000000000c1','Señales SAC','Señales','20511000001','approved',
        'b1000000-0000-4000-8000-0000000000f6');

insert into public.events (id, organizer_id, venue_id, title, slug, status, visibility,
                           starts_at, doors_at, capacity, nomination_mode) values
 ('b1000000-0000-4000-8000-0000000000e1','b1000000-0000-4000-8000-0000000000c1','b1000000-0000-4000-8000-0000000000b1',
  'Evento con amigos','ev-senales-11','published','public', now()+interval '30 days', now()+interval '30 days'-interval '2 hours',5000,'flexible'),
 -- AC-07 necesita un evento donde NADIE que yo conozca aparezca.
 ('b1000000-0000-4000-8000-0000000000e2','b1000000-0000-4000-8000-0000000000c1','b1000000-0000-4000-8000-0000000000b1',
  'Evento sin amigos','ev-senales-11-solo','published','public', now()+interval '30 days', now()+interval '30 days'-interval '2 hours',5000,'flexible');

insert into public.zones (id, event_id, name, kind, numbered, capacity) values
 ('b1000000-0000-4000-8000-0000000000a1','b1000000-0000-4000-8000-0000000000e1','General','standing',false,4000),
 ('b1000000-0000-4000-8000-0000000000a2','b1000000-0000-4000-8000-0000000000e2','General','standing',false,4000);

insert into public.price_phases (id, event_id, name, kind, starts_at, ends_at) values
 ('b1000000-0000-4000-8000-0000000000d1','b1000000-0000-4000-8000-0000000000e1','Única','regular',now()-interval '10 days',now()+interval '10 days'),
 ('b1000000-0000-4000-8000-0000000000d2','b1000000-0000-4000-8000-0000000000e2','Única','regular',now()-interval '10 days',now()+interval '10 days');

insert into public.price_tiers (id, event_id, zone_id, phase_id, price_cents, stock, sold) values
 ('b1000000-0000-4000-8000-0000000000c2','b1000000-0000-4000-8000-0000000000e1','b1000000-0000-4000-8000-0000000000a1','b1000000-0000-4000-8000-0000000000d1',5000,100,4),
 ('b1000000-0000-4000-8000-0000000000c3','b1000000-0000-4000-8000-0000000000e2','b1000000-0000-4000-8000-0000000000a2','b1000000-0000-4000-8000-0000000000d2',5000,100,1);

-- Cada quien compra la suya: el comprador tiene que ser el dueño del ticket
-- para que la señal signifique algo.
insert into public.orders (id, event_id, buyer_id, status, subtotal_cents, service_charge_cents, total_cents, paid_at) values
 ('b1000000-0000-4000-8000-00000000d001','b1000000-0000-4000-8000-0000000000e1','b1000000-0000-4000-8000-0000000000f2','paid',5000,300,5300,now()),
 ('b1000000-0000-4000-8000-00000000d002','b1000000-0000-4000-8000-0000000000e1','b1000000-0000-4000-8000-0000000000f4','paid',5000,300,5300,now()),
 ('b1000000-0000-4000-8000-00000000d003','b1000000-0000-4000-8000-0000000000e1','b1000000-0000-4000-8000-0000000000f5','paid',5000,300,5300,now()),
 ('b1000000-0000-4000-8000-00000000d004','b1000000-0000-4000-8000-0000000000e1','b1000000-0000-4000-8000-0000000000f1','paid',5000,300,5300,now()),
 ('b1000000-0000-4000-8000-00000000d005','b1000000-0000-4000-8000-0000000000e2','b1000000-0000-4000-8000-0000000000f5','paid',5000,300,5300,now());

insert into public.order_items (id, order_id, price_tier_id, unit_price_cents) values
 ('b1000000-0000-4000-8000-00000000e001','b1000000-0000-4000-8000-00000000d001','b1000000-0000-4000-8000-0000000000c2',5000),
 ('b1000000-0000-4000-8000-00000000e002','b1000000-0000-4000-8000-00000000d002','b1000000-0000-4000-8000-0000000000c2',5000),
 ('b1000000-0000-4000-8000-00000000e003','b1000000-0000-4000-8000-00000000d003','b1000000-0000-4000-8000-0000000000c2',5000),
 ('b1000000-0000-4000-8000-00000000e004','b1000000-0000-4000-8000-00000000d004','b1000000-0000-4000-8000-0000000000c2',5000),
 ('b1000000-0000-4000-8000-00000000e005','b1000000-0000-4000-8000-00000000d005','b1000000-0000-4000-8000-0000000000c3',5000);

insert into public.tickets (id, code, event_id, order_item_id, zone_id, owner_id, original_owner_id,
                            status, face_value_cents) values
 ('b1000000-0000-4000-8000-000000009001','FVT-011-0001','b1000000-0000-4000-8000-0000000000e1','b1000000-0000-4000-8000-00000000e001','b1000000-0000-4000-8000-0000000000a1','b1000000-0000-4000-8000-0000000000f2','b1000000-0000-4000-8000-0000000000f2','active',5000),
 ('b1000000-0000-4000-8000-000000009002','FVT-011-0002','b1000000-0000-4000-8000-0000000000e1','b1000000-0000-4000-8000-00000000e002','b1000000-0000-4000-8000-0000000000a1','b1000000-0000-4000-8000-0000000000f4','b1000000-0000-4000-8000-0000000000f4','active',5000),
 ('b1000000-0000-4000-8000-000000009003','FVT-011-0003','b1000000-0000-4000-8000-0000000000e1','b1000000-0000-4000-8000-00000000e003','b1000000-0000-4000-8000-0000000000a1','b1000000-0000-4000-8000-0000000000f5','b1000000-0000-4000-8000-0000000000f5','active',5000),
 ('b1000000-0000-4000-8000-000000009004','FVT-011-0004','b1000000-0000-4000-8000-0000000000e1','b1000000-0000-4000-8000-00000000e004','b1000000-0000-4000-8000-0000000000a1','b1000000-0000-4000-8000-0000000000f1','b1000000-0000-4000-8000-0000000000f1','active',5000),
 ('b1000000-0000-4000-8000-000000009005','FVT-011-0005','b1000000-0000-4000-8000-0000000000e2','b1000000-0000-4000-8000-00000000e005','b1000000-0000-4000-8000-0000000000a2','b1000000-0000-4000-8000-0000000000f5','b1000000-0000-4000-8000-0000000000f5','active',5000);

-- I marca interés desde su propia sesión: es su fila y su política.
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1000000-0000-4000-8000-0000000000f3","role":"authenticated"}';
insert into public.event_interests (user_id, event_id)
values ('b1000000-0000-4000-8000-0000000000f3','b1000000-0000-4000-8000-0000000000e1');

-- ═══════════════════════════════════════════════════════════════════════════
-- La señal, vista por A
-- ═══════════════════════════════════════════════════════════════════════════
set local request.jwt.claims = '{"sub":"b1000000-0000-4000-8000-0000000000f1","role":"authenticated"}';

-- AC-01 · G y N tienen entrada y los dos son amigos: 2. (N todavía no es ninja.)
insert into res select 'AC-01  un amigo con entrada suma a friends_going',
  (select friends_going from public.v_my_event_signals
    where event_id = 'b1000000-0000-4000-8000-0000000000e1') = 2,
  'G y N, antes de que N encienda el interruptor';

-- AC-02 · I no tiene entrada pero marcó interés
insert into res select 'AC-02  un amigo con interés suma a friends_interested',
  (select friends_interested from public.v_my_event_signals
    where event_id = 'b1000000-0000-4000-8000-0000000000e1') = 1,
  'solo I';

-- AC-03 · X tiene entrada del MISMO evento y no es amiga. Esta es la frontera:
-- sin el join con `visibles`, la vista definer la contaría.
insert into res select 'AC-03  un desconocido con entrada NO suma',
  (select friends_going from public.v_my_event_signals
    where event_id = 'b1000000-0000-4000-8000-0000000000e1') = 2,
  'si saliera 3, la vista estaría contando a toda la plataforma';

-- AC-06 · yo también tengo entrada de este evento, y no me cuento
insert into res select 'AC-06  mi propia entrada no me cuenta como amigo mío',
  (select friends_going from public.v_my_event_signals
    where event_id = 'b1000000-0000-4000-8000-0000000000e1') = 2,
  'la CTE `amigos` toma siempre el OTRO extremo de la arista';

-- AC-07 · el segundo evento solo tiene a X
insert into res select 'AC-07  un evento sin ningún amigo no aparece en la vista',
  not exists (select 1 from public.v_my_event_signals
               where event_id = 'b1000000-0000-4000-8000-0000000000e2'),
  'cero no es un valor que enseñar';

-- AC-08 · un ticket `used` sigue contando: ya entró, sigue yendo
reset role;
update public.tickets set status = 'used', used_at = now()
 where id = 'b1000000-0000-4000-8000-000000009001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1000000-0000-4000-8000-0000000000f1","role":"authenticated"}';

insert into res select 'AC-08  un ticket ya usado sigue contando como «va»',
  (select friends_going from public.v_my_event_signals
    where event_id = 'b1000000-0000-4000-8000-0000000000e1') = 2,
  'G ya entró; el número no cambia';

-- AC-08b · pero `listed` no: quien revende su entrada está intentando no ir
-- `used_at` se limpia a la vez: la constraint `tickets_used_has_time` ata el
-- estado y la hora en los dos sentidos, y saltársela aquí abortaba la suite
-- entera. Es la garantía haciendo su trabajo.
reset role;
update public.tickets set status = 'listed', used_at = null
 where id = 'b1000000-0000-4000-8000-000000009001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1000000-0000-4000-8000-0000000000f1","role":"authenticated"}';

insert into res select 'AC-08b un ticket en reventa (listed) deja de contar',
  (select friends_going from public.v_my_event_signals
    where event_id = 'b1000000-0000-4000-8000-0000000000e1') = 1,
  'anunciar «va» de quien está vendiendo su entrada es la señal al revés';

-- Se devuelve a `used` para el resto de la suite, con su hora.
reset role;
update public.tickets set status = 'used', used_at = now()
 where id = 'b1000000-0000-4000-8000-000000009001';

-- AC-10 · la vista no expone nada más que conteos
insert into res select 'AC-10  la vista solo expone event_id y dos conteos (D-40)',
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'v_my_event_signals') = 3
  and not exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'v_my_event_signals'
                     and column_name in ('zone_id','face_value_cents','order_id',
                                         'owner_id','code','friend_id','user_id')),
  'ni zona, ni precio, ni orden, ni quién';

-- ═══════════════════════════════════════════════════════════════════════════
-- Ninja y bloqueo · el filtro que 010 dejó escrito
-- ═══════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1000000-0000-4000-8000-0000000000f4","role":"authenticated"}';
update public.profiles set ninja_mode = true
 where id = 'b1000000-0000-4000-8000-0000000000f4';

set local request.jwt.claims = '{"sub":"b1000000-0000-4000-8000-0000000000f1","role":"authenticated"}';

-- AC-04 · misma consulta que AC-01, y por eso vale: baja de 2 a 1 sin tocar
-- nada más que el interruptor.
insert into res select 'AC-04  un amigo en modo ninja deja de sumar',
  (select friends_going from public.v_my_event_signals
    where event_id = 'b1000000-0000-4000-8000-0000000000e1') = 1,
  'de 2 a 1: solo G';

-- AC-05 · I bloquea a A
set local request.jwt.claims = '{"sub":"b1000000-0000-4000-8000-0000000000f3","role":"authenticated"}';
select public.block_user('b1000000-0000-4000-8000-0000000000f1');

set local request.jwt.claims = '{"sub":"b1000000-0000-4000-8000-0000000000f1","role":"authenticated"}';

insert into res select 'AC-05  un amigo que me bloqueó deja de sumar',
  coalesce((select friends_interested from public.v_my_event_signals
             where event_id = 'b1000000-0000-4000-8000-0000000000e1'), 0) = 0,
  'el bloqueo lo resuelve can_see_activity_of, no esta vista';

-- ═══════════════════════════════════════════════════════════════════════════
-- La superficie de escritura de event_interests
-- ═══════════════════════════════════════════════════════════════════════════

-- AC-12b · el camino feliz PRIMERO: sin él, AC-12 y AC-13 darían verde con la
-- tabla entera bloqueada.
insert into res select 'AC-12b A sí puede marcar su propio interés',
  not pg_temp.fails($q$insert into public.event_interests (user_id, event_id)
    values ('b1000000-0000-4000-8000-0000000000f1','b1000000-0000-4000-8000-0000000000e2')$q$),
  'la política de insert deja pasar lo propio';

-- AC-12 · la PK impide el duplicado
insert into res select 'AC-12  marcar interés dos veces no duplica',
  pg_temp.fails($q$insert into public.event_interests (user_id, event_id)
    values ('b1000000-0000-4000-8000-0000000000f1','b1000000-0000-4000-8000-0000000000e2')$q$),
  'lo impide la PK, no una comprobación en la aplicación';

-- AC-13 · a nombre de otro, no
insert into res select 'AC-13  nadie marca interés a nombre de otro',
  pg_temp.fails($q$insert into public.event_interests (user_id, event_id)
    values ('b1000000-0000-4000-8000-0000000000f2','b1000000-0000-4000-8000-0000000000e2')$q$),
  'así se fabricaría una señal social falsa';

-- AC-14 · quitar el interés
delete from public.event_interests
 where user_id = 'b1000000-0000-4000-8000-0000000000f1'
   and event_id = 'b1000000-0000-4000-8000-0000000000e2';

insert into res select 'AC-14  quitar el interés borra la fila',
  (select count(*) from public.event_interests
    where user_id = 'b1000000-0000-4000-8000-0000000000f1') = 0,
  'sin columna status: no se guarda a qué eventos dijiste que no';

-- AC-11 · X ve la vista vacía. Tiene DOS entradas y cero amigos.
set local request.jwt.claims = '{"sub":"b1000000-0000-4000-8000-0000000000f5","role":"authenticated"}';

insert into res select 'AC-11  un ajeno ve la vista VACÍA aunque definer apague la RLS',
  (select count(*) from public.v_my_event_signals) = 0,
  'el where es lo único que lo frena';

-- AC-15 · anon
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

insert into res select 'AC-15  anon no lee la vista de señales',
  pg_temp.fails($q$select count(*) from public.v_my_event_signals$q$),
  'el grant es solo para authenticated';

insert into res select 'AC-15b anon no lee event_interests',
  pg_temp.fails($q$select count(*) from public.event_interests$q$),
  'permission denied: la 0009 le quitó el select por defecto';

-- ── Resultado ───────────────────────────────────────────────────────────────
reset role;

select ac, case when pass then '✓' else '✗ FALLA' end as r, detail
from res order by ac;

select count(*) filter (where not pass or pass is null) as fallos,
       count(*) as total
from res;

rollback;
