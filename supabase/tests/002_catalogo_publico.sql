-- 002 Catálogo público — búsqueda, filtros, orden y cursor
--
-- Corre entero dentro de begin … rollback: no deja rastro.
--
-- El catálogo es una proyección de 003, así que casi todo lo que importa ya está
-- probado allí (visibilidad, precio, disponibilidad). Aquí se prueba lo que un
-- LISTADO añade y un detalle no necesita.

begin;

create or replace function pg_temp.fails(p_sql text) returns boolean
language plpgsql as $$
begin execute p_sql; return false;
exception when others then return true; end $$;

create temp table res(ac text, pass boolean, detail text) on commit drop;
grant insert, select on res to authenticated, anon;

-- ════════════════════════════════════════════════════════════════════════════
-- Semilla: un evento con acentos y guiones, y cuatro con la MISMA fecha
-- ════════════════════════════════════════════════════════════════════════════
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at)
values ('f0000000-0000-4000-8000-0000000000f1','00000000-0000-0000-0000-000000000000',
        'authenticated','authenticated','cat@test.local','x',now(),'{}','{}',now(),now())
on conflict (id) do nothing;

insert into public.venues (id, name, city, capacity) values
 ('f0000000-0000-4000-8000-0000000000f2','Estadio Nacional','Lima',40000),
 ('f0000000-0000-4000-8000-0000000000f4','Teatro Municipal','Arequipa',1200);

insert into public.organizers (id, legal_name, ruc, status, created_by)
values ('f0000000-0000-4000-8000-0000000000f3','Catalogo SAC','20512345678','approved',
        'f0000000-0000-4000-8000-0000000000f1');
insert into public.organizer_members (organizer_id, user_id, role)
values ('f0000000-0000-4000-8000-0000000000f3','f0000000-0000-4000-8000-0000000000f1','owner');

-- Con guion y con tilde: los dos casos que la gente teclea distinto
insert into public.events (organizer_id, venue_id, title, description, category,
                           starts_at, capacity, slug, status, visibility,
                           service_charge_bps, service_charge_payer) values
 ('f0000000-0000-4000-8000-0000000000f3','f0000000-0000-4000-8000-0000000000f2',
  'K-Pop Fest 2026','Doce artistas en dos escenarios.','Festival',
  now()+interval '60 days',1400,'cat-kpop','published','public',600,'fan'),
 ('f0000000-0000-4000-8000-0000000000f3','f0000000-0000-4000-8000-0000000000f4',
  'Música Criolla en Vivo','Una noche de jarana.','Concierto',
  now()+interval '70 days',900,'cat-criolla','published','public',600,'fan');

-- Cuatro al MISMO instante: el caso que rompe el cursor si se hace mal
insert into public.events (organizer_id, venue_id, title, description, category,
                           starts_at, capacity, slug, status, visibility,
                           service_charge_bps, service_charge_payer)
select 'f0000000-0000-4000-8000-0000000000f3','f0000000-0000-4000-8000-0000000000f2',
       'Empate ' || i, 'd','Prueba',
       date_trunc('hour', now()) + interval '90 days',
       500, 'cat-empate-' || i, 'published','public',600,'fan'
from generate_series(1,4) i;

-- Inventario para todos, así entran en el catálogo
insert into public.zones (event_id, name, kind, numbered, capacity)
select id,'General','standing',false,500 from public.events where slug like 'cat-%';
insert into public.price_phases (event_id, name, starts_at, ends_at)
select id,'Preventa 1', now()-interval '1 day', now()+interval '30 days'
  from public.events where slug like 'cat-%';
insert into public.price_tiers (event_id, zone_id, phase_id, price_cents, stock)
select e.id, z.id, p.id,
       case when e.slug = 'cat-kpop' then 4000 else 2500 end, 500
  from public.events e
  join public.zones z        on z.event_id = e.id
  join public.price_phases p on p.event_id = e.id
 where e.slug like 'cat-%';

-- ════════════════════════════════════════════════════════════════════════════
-- AC-15 · Búsqueda: como se escribe, no como está guardado
-- ════════════════════════════════════════════════════════════════════════════
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

insert into res
select 'AC-15  busca «' || q || '»' ||
       case when debe then ' → encuentra' else ' → nada (correcto)' end,
       exists (select 1 from public.v_event_public
                where slug like 'cat-%'
                  and search_text @@ public.search_events_tsquery(q)) = debe,
       coalesce((select string_agg(title, ', ') from public.v_event_public
                  where slug like 'cat-%'
                    and search_text @@ public.search_events_tsquery(q)), '(nada)')
from (values
  ('kpop',             true),   -- SIN guion: el caso que falló en 0027
  ('k-pop',            true),   -- con guion
  ('K-POP',            true),   -- mayúsculas
  ('pop',              true),   -- una parte del compuesto
  ('festival',         true),   -- por categoría
  ('estadio nacional', true),   -- por NOMBRE DEL VENUE (denormalizado)
  ('arequipa',         true),   -- por ciudad
  ('musica',           true),   -- SIN tilde encuentra «Música»
  ('música',           true),   -- con tilde
  ('criolla',          true),
  ('artista',          true),   -- stemming: dice «artistas»
  ('escenarios',       true),   -- de la descripción, peso D
  ('reggaeton',        false)   -- no existe
) as t(q, debe);

-- ════════════════════════════════════════════════════════════════════════════
-- AC-12 · El «desde» de la card = el mínimo del detalle
-- ════════════════════════════════════════════════════════════════════════════
-- Las dos cifras salen de la misma vista. La prueba lo verifica en lugar de
-- confiar: si algún día alguien las calcula por separado, esto se pone rojo.
insert into res
select 'AC-12  el desde de la card = mínimo del detalle',
       (select c.from_price_cents = (
          select min((t->>'total_cents')::int)
            from jsonb_array_elements(public.get_public_event(c.slug) -> 'zones') z,
                 jsonb_array_elements(z->'tiers') t
           where (t->>'phase_active')::boolean and (t->>'available')::int > 0)
        from public.v_event_public c where c.slug = 'cat-kpop'),
       (select 'card=' || from_price_cents || ' (4000 + 6% = 4240)'
          from public.v_event_public where slug = 'cat-kpop');

insert into res select 'AC-09  el desde ya incluye el cargo del fan',
  (select from_price_cents = 4240 from public.v_event_public where slug='cat-kpop'), 'ok';

-- ════════════════════════════════════════════════════════════════════════════
-- AC-14 · Cursor: el empate en starts_at es el caso que importa
-- ════════════════════════════════════════════════════════════════════════════
with p1 as (
  select id, slug, starts_at from public.v_event_public
   where slug like 'cat-empate-%' order by starts_at, id limit 2
), cur as (select starts_at as at, id from p1 order by starts_at desc, id desc limit 1)
, p2 as (
  select v.id, v.slug, v.starts_at from public.v_event_public v, cur
   where v.slug like 'cat-empate-%'
     and (v.starts_at > cur.at or (v.starts_at = cur.at and v.id > cur.id))
   order by v.starts_at, v.id limit 2
)
insert into res
select 'AC-14  keyset (starts_at, id): ni salta ni repite',
       (select count(distinct slug) = 4 from (select slug from p1 union all select slug from p2) u),
       (select string_agg(slug, ' → ' order by pg, rn) from (
          select slug, 1 pg, row_number() over (order by starts_at, id) rn from p1
          union all
          select slug, 2, row_number() over (order by starts_at, id) from p2) u);

-- El atajo que parece equivalente y no lo es. Se prueba para que nadie lo
-- "simplifique" más adelante.
with p1 as (
  select slug, starts_at from public.v_event_public
   where slug like 'cat-empate-%' order by starts_at, id limit 2
), cur as (select starts_at as at from p1 order by starts_at desc limit 1)
, p2 as (
  select v.slug from public.v_event_public v, cur
   where v.slug like 'cat-empate-%' and v.starts_at > cur.at
   order by v.starts_at, v.id limit 2
)
insert into res
select 'AC-14b el atajo `.gt(starts_at)` pierde los empatados',
       (select count(*) = 0 from p2),
       'segunda página vacía: se pierden 2 de los 4';

-- ════════════════════════════════════════════════════════════════════════════
-- Filtros y orden
-- ════════════════════════════════════════════════════════════════════════════
insert into res select 'filtro por categoría',
  (select count(*) = 1 from public.v_event_public
    where slug like 'cat-%' and category = 'Concierto'), 'ok';

insert into res select 'filtro por ciudad',
  (select count(*) = 1 from public.v_event_public
    where slug like 'cat-%' and venue_city = 'Arequipa'), 'ok';

insert into res select 'filtro por rango de fechas',
  (select count(*) = 1 from public.v_event_public
    where slug like 'cat-%'
      and starts_at between now()+interval '55 days' and now()+interval '65 days'), 'ok';

insert into res select 'orden por precio: el más barato primero',
  (select from_price_cents from public.v_event_public
    where slug like 'cat-%' order by from_price_cents nulls last limit 1) = 2650,
  (select string_agg(from_price_cents::text, ' ≤ ' order by from_price_cents)
     from public.v_event_public where slug like 'cat-%');

-- ════════════════════════════════════════════════════════════════════════════
-- AC-07 · La vista no expone lo interno, y search_text no se selecciona
-- ════════════════════════════════════════════════════════════════════════════
insert into res select 'AC-07  la vista no expone campos internos',
  not exists (select 1 from information_schema.columns
               where table_schema='public' and table_name='v_event_public'
                 and column_name in ('review_checklist','payout_policy','created_by',
                                     'status','visibility','description')),
  'ni el estado, ni la visibilidad, ni la descripción larga';

insert into res select 'search_text está en la vista, para filtrar',
  exists (select 1 from information_schema.columns
           where table_schema='public' and table_name='v_event_public'
             and column_name = 'search_text'),
  'el cliente pide columnas explícitas, así que no viaja en la respuesta';

reset role;
insert into res select 'AC-13  el índice GIN existe',
  exists (select 1 from pg_indexes where schemaname='public'
           and indexname='events_search_idx' and indexdef ilike '%gin%'),
  'sin él, buscar es un recorrido secuencial de la tabla';

-- El texto del venue se refresca al renombrarlo (trigger 2 de 0027)
update public.venues set name = 'Estadio Monumental'
 where id = 'f0000000-0000-4000-8000-0000000000f2';
insert into res select 'el venue renombrado se encuentra por su nombre NUEVO',
  exists (select 1 from public.events
           where slug = 'cat-kpop'
             and search_text @@ public.search_events_tsquery('monumental')),
  'y deja de encontrarse por el viejo, que es lo correcto';

select ac, case when pass then '✓' else '✗ FALLA' end as r, detail from res order by ac;
select count(*) filter (where not pass or pass is null) as fallos, count(*) as total from res;

rollback;
