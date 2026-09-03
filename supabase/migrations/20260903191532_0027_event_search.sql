-- 002 · AC-13, AC-15
--
-- `ilike '%kpop%'` sobre 10 000 eventos es un recorrido secuencial con una
-- comparación de cadenas por fila. Un GIN sobre tsvector es una búsqueda de
-- índice, y AC-13 pide menos de 200 ms en el p95.
--
-- El texto del venue se DENORMALIZA aquí porque una columna generada solo puede
-- leer su propia fila, y calcular el tsvector dentro de la vista sobre el join
-- no se puede indexar. Ver specs/002-catalogo-publico/plan.md.
--
-- OJO: 0028 reescribe event_search_text() para añadir unaccent y una variante
-- sin guiones. Con esta versión, buscar «kpop» NO encuentra «K-Pop Fest».

alter table public.events add column search_text tsvector;

-- Los pesos no son decorativos: A al título y D a la descripción hace que
-- buscar «festival» ponga primero un evento que se llama así, y no uno que lo
-- menciona de pasada en su texto largo.
create or replace function private.event_search_text(
  p_title text, p_category text, p_description text,
  p_venue_name text, p_venue_city text
) returns tsvector language sql immutable set search_path = '' as $$
  select setweight(to_tsvector('spanish', coalesce(p_title, '')),       'A')
      || setweight(to_tsvector('spanish', coalesce(p_category, '')),    'B')
      || setweight(to_tsvector('spanish', coalesce(p_venue_name, '')),  'B')
      || setweight(to_tsvector('spanish', coalesce(p_venue_city, '')),  'B')
      || setweight(to_tsvector('spanish', coalesce(p_description, '')), 'D')
$$;

-- ── Trigger 1: el evento cambia ─────────────────────────────────────────────
create or replace function private.events_set_search_text()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_name text; v_city text;
begin
  if new.venue_id is not null then
    select v.name, v.city into v_name, v_city
      from public.venues v where v.id = new.venue_id;
  end if;

  new.search_text := private.event_search_text(
    new.title, new.category, new.description, v_name, v_city);
  return new;
end $$;

create trigger events_search_text
  before insert or update of title, category, description, venue_id on public.events
  for each row execute function private.events_set_search_text();

-- ── Trigger 2: el venue se renombra ─────────────────────────────────────────
-- Un venue se renombra casi nunca. Pero cuando pasa, sin esto el catálogo deja
-- de encontrar sus eventos por el nombre nuevo Y por el viejo.
--
-- ponytail: recorre los eventos de ese venue. Con 50 es irrelevante; si alguna
-- vez hay un venue con miles, se pasa a una cola.
create or replace function private.venues_refresh_event_search()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.events e
     set search_text = private.event_search_text(
           e.title, e.category, e.description, new.name, new.city)
   where e.venue_id = new.id;
  return new;
end $$;

create trigger venues_refresh_event_search
  after update of name, city on public.venues
  for each row execute function private.venues_refresh_event_search();

-- Poblar lo que ya existe
update public.events e
   set search_text = private.event_search_text(
         e.title, e.category, e.description, v.name, v.city)
  from public.venues v
 where v.id = e.venue_id;

update public.events
   set search_text = private.event_search_text(title, category, description, null, null)
 where venue_id is null;

create index events_search_idx on public.events using gin (search_text);

revoke all on function private.event_search_text(text, text, text, text, text)
  from public, anon, authenticated;
revoke all on function private.events_set_search_text()      from public, anon, authenticated;
revoke all on function private.venues_refresh_event_search() from public, anon, authenticated;

-- ── Exponer en la vista pública ─────────────────────────────────────────────
-- Se recrea añadiendo search_text, para que PostgREST pueda filtrar con
-- ?search_text=fts(spanish).kpop. Se FILTRA, no se selecciona: un tsvector en
-- cada fila de la respuesta son kilobytes de ruido.
drop view public.v_event_public;

create view public.v_event_public with (security_invoker = false) as
with tier as (
  select
    t.event_id,
    private.total_with_charge(t.price_cents, e.service_charge_bps, e.service_charge_payer)
      as total_cents,
    t.currency
  from public.price_tiers t
  join public.events       e on e.id = t.event_id
  join public.price_phases p on p.id = t.phase_id
  where now() >= p.starts_at and now() < p.ends_at
    and t.stock - t.reserved - t.sold > 0
)
select
  e.id,
  e.slug,
  e.title,
  e.category,
  e.hero_image_url,
  e.starts_at,
  e.doors_at,
  e.timezone,
  e.capacity,
  e.max_per_user,
  e.resale_enabled,
  e.featured_at,
  e.search_text,                                   -- para filtrar, no para leer
  v.name  as venue_name,
  v.city  as venue_city,
  o.trade_name as organizer_name,
  (select min(total_cents) from tier where tier.event_id = e.id) as from_price_cents,
  (select currency from tier where tier.event_id = e.id limit 1) as currency,
  public.active_phase_id(e.id) is not null as sale_open,
  (select min(p.starts_at) from public.price_phases p
    where p.event_id = e.id and p.starts_at > now())        as next_phase_starts_at,
  coalesce((select sum(t.stock - t.reserved - t.sold)
              from public.price_tiers t
              join public.price_phases p on p.id = t.phase_id
             where t.event_id = e.id
               and now() >= p.starts_at and now() < p.ends_at), 0) as available_now
from public.events e
left join public.venues     v on v.id = e.venue_id
left join public.organizers o on o.id = e.organizer_id
where e.status = 'published'
  and e.visibility = 'public'
  and (e.starts_at is null or e.starts_at > now());

comment on view public.v_event_public is
  'Catálogo público. security_invoker = false: salta la RLS, así que este WHERE es la única protección. search_text está para filtrar con fts, no para seleccionar.';

grant select on public.v_event_public to anon, authenticated;
