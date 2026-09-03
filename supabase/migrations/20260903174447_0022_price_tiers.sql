-- 003 · T-06 … T-09
-- El precio real: una fila por (zona | segmento) × fase.

create table public.price_tiers (
  id          uuid primary key default gen_random_uuid(),
  -- Denormalizado a propósito: la RLS y los índices lo consultan en cada
  -- lectura del catálogo, y llegar al evento por zones sería un join extra.
  event_id    uuid not null references public.events (id) on delete cascade,
  zone_id     uuid not null references public.zones (id) on delete cascade,
  segment_id  uuid,
  phase_id    uuid not null references public.price_phases (id) on delete cascade,

  price_cents int not null check (price_cents > 0),   -- AC-02
  currency    char(3) not null default 'PEN',

  stock       int not null check (stock >= 0),
  reserved    int not null default 0 check (reserved >= 0),
  sold        int not null default 0 check (sold >= 0),

  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  -- AC-07 y AC-18: es la misma fila, así que un check basta y no se puede
  -- desactivar. Es la invariante que sostiene toda la reserva de 004.
  constraint price_tiers_stock_covers_commitments
    check (reserved + sold <= stock),

  -- AC-04: el segmento pertenece a SU zona. FK compuesta, no trigger.
  -- Con segment_id nulo, MATCH SIMPLE no evalúa la FK — que es lo que quiere
  -- una zona de pie.
  constraint price_tiers_segment_in_zone_fk
    foreign key (zone_id, segment_id) references public.zone_segments (zone_id, id)
    on delete cascade
);

-- AC-03: un solo precio por cruce. `segment_id` nulo se trata como un valor,
-- porque un unique normal deja pasar infinitos nulos.
create unique index price_tiers_cross_key
  on public.price_tiers (zone_id, coalesce(segment_id, '00000000-0000-0000-0000-000000000000'::uuid), phase_id);

create index price_tiers_event_idx on public.price_tiers (event_id, phase_id);
create index price_tiers_zone_idx  on public.price_tiers (zone_id);

create trigger price_tiers_touch_updated_at
  before update on public.price_tiers
  for each row execute function public.touch_updated_at();

-- ── AC-01: sum(stock) por zona no supera el aforo de la zona ────────────────
-- Cruza filas, así que no cabe en un check. Va aquí, junto al dato, y no en la
-- aplicación: el organizador no es el único que escribe esta tabla.
create or replace function private.check_zone_stock()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_capacity int; v_sum int; v_zone text;
begin
  select z.capacity, z.name into v_capacity, v_zone
    from public.zones z where z.id = new.zone_id;

  -- Se suma por FASE, no por zona entera: el mismo cupo se revende en cada
  -- fase, no se acumula. 800 en Preventa 1 y 800 en Regular son los mismos 800
  -- asientos ofrecidos dos veces, no 1600.
  select coalesce(sum(stock), 0) into v_sum
    from public.price_tiers
   where zone_id = new.zone_id and phase_id = new.phase_id
     and id <> new.id;

  if v_sum + new.stock > v_capacity then
    raise exception
      'el stock de la zona % en esta fase (%) supera su aforo (%)',
      v_zone, v_sum + new.stock, v_capacity
      using errcode = '23514';
  end if;

  return new;
end $$;

create trigger price_tiers_check_zone_stock
  before insert or update of stock, zone_id, phase_id on public.price_tiers
  for each row execute function private.check_zone_stock();

revoke all on function private.check_zone_stock() from public, anon, authenticated;

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.price_tiers enable row level security;

create policy price_tiers_select on public.price_tiers
  for select to authenticated
  using (
    event_id in (select id from public.events
                  where organizer_id = any (private.auth_organizer_ids()))
    or private.auth_is_admin()
  );

create policy price_tiers_insert on public.price_tiers
  for insert to authenticated
  with check (
    event_id in (select id from public.events
                  where organizer_id = any (private.auth_organizer_ids()))
    or private.auth_is_admin()
  );

create policy price_tiers_update on public.price_tiers
  for update to authenticated
  using (
    event_id in (select id from public.events
                  where organizer_id = any (private.auth_organizer_ids()))
    or private.auth_is_admin()
  )
  with check (
    event_id in (select id from public.events
                  where organizer_id = any (private.auth_organizer_ids()))
    or private.auth_is_admin()
  );

create policy price_tiers_delete on public.price_tiers
  for delete to authenticated
  using (
    event_id in (select id from public.events
                  where organizer_id = any (private.auth_organizer_ids()))
    or private.auth_is_admin()
  );

grant insert, update, delete on public.price_tiers to authenticated;

-- `reserved` y `sold` NO los toca el cliente: los mueve la reserva y la
-- confirmación de pago de 004, en funciones transaccionales (Art. 9.4).
revoke update (reserved, sold) on public.price_tiers from authenticated;

comment on constraint price_tiers_stock_covers_commitments on public.price_tiers is
  'La invariante que sostiene la reserva de 004: nunca se compromete más de lo que hay.';
