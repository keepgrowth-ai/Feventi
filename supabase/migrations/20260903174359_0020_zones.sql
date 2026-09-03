-- 003 · T-02 … T-04

create table public.zones (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events (id) on delete cascade,
  name       text not null,
  kind       public.zone_kind not null,
  numbered   boolean not null default false,
  capacity   int not null check (capacity > 0),
  notes      text,
  sort_order int  not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- 'numbered' es una consecuencia de 'kind', no una opción independiente.
  constraint zones_numbered_matches_kind check (numbered = (kind = 'seated')),

  -- Permite la FK compuesta de zone_segments y seats: convierte "la zona tiene
  -- que ser numerada" en algo que garantiza el motor. Ver plan.md.
  constraint zones_id_kind_key unique (id, kind)
);

create index zones_event_idx on public.zones (event_id, sort_order);

create trigger zones_touch_updated_at
  before update on public.zones
  for each row execute function public.touch_updated_at();

-- ── Segmentos: bloques de filas con precio distinto dentro de una zona ──────
create table public.zone_segments (
  id         uuid primary key default gen_random_uuid(),
  zone_id    uuid not null references public.zones (id) on delete cascade,
  -- Redundante a propósito: la FK compuesta de abajo hace imposible que un
  -- segmento cuelgue de una zona de pie (AC-05). Un check no puede mirar otra
  -- tabla y un trigger se puede desactivar; una FK, no.
  zone_kind  public.zone_kind not null default 'seated'
               check (zone_kind = 'seated'),
  label      text not null,
  row_from   text,
  row_to     text,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),

  constraint zone_segments_zone_is_seated_fk
    foreign key (zone_id, zone_kind) references public.zones (id, kind)
    on delete cascade,

  -- Permite la FK compuesta de price_tiers: el segmento pertenece a SU zona (AC-04).
  constraint zone_segments_zone_id_id_key unique (zone_id, id)
);

create index zone_segments_zone_idx on public.zone_segments (zone_id, sort_order);

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.zones         enable row level security;
alter table public.zone_segments enable row level security;

-- AC-16, AC-17. Convención: una política por operación, casos con OR, caso
-- común primero. anon NO lee esto: lo público sale de las vistas de 0024.
create policy zones_select on public.zones
  for select to authenticated
  using (
    event_id in (select id from public.events
                  where organizer_id = any (private.auth_organizer_ids()))
    or private.auth_is_admin()
  );

create policy zones_insert on public.zones
  for insert to authenticated
  with check (
    event_id in (select id from public.events
                  where organizer_id = any (private.auth_organizer_ids()))
    or private.auth_is_admin()
  );

create policy zones_update on public.zones
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

-- AC-20: una zona con tickets emitidos no se borra. El guard va con 004, que es
-- quien crea `tickets`; mientras tanto el delete queda solo para el dueño.
create policy zones_delete on public.zones
  for delete to authenticated
  using (
    event_id in (select id from public.events
                  where organizer_id = any (private.auth_organizer_ids()))
    or private.auth_is_admin()
  );

create policy zone_segments_select on public.zone_segments
  for select to authenticated
  using (
    zone_id in (select z.id from public.zones z
                join public.events e on e.id = z.event_id
                where e.organizer_id = any (private.auth_organizer_ids()))
    or private.auth_is_admin()
  );

create policy zone_segments_insert on public.zone_segments
  for insert to authenticated
  with check (
    zone_id in (select z.id from public.zones z
                join public.events e on e.id = z.event_id
                where e.organizer_id = any (private.auth_organizer_ids()))
    or private.auth_is_admin()
  );

create policy zone_segments_update on public.zone_segments
  for update to authenticated
  using (
    zone_id in (select z.id from public.zones z
                join public.events e on e.id = z.event_id
                where e.organizer_id = any (private.auth_organizer_ids()))
    or private.auth_is_admin()
  )
  with check (
    zone_id in (select z.id from public.zones z
                join public.events e on e.id = z.event_id
                where e.organizer_id = any (private.auth_organizer_ids()))
    or private.auth_is_admin()
  );

create policy zone_segments_delete on public.zone_segments
  for delete to authenticated
  using (
    zone_id in (select z.id from public.zones z
                join public.events e on e.id = z.event_id
                where e.organizer_id = any (private.auth_organizer_ids()))
    or private.auth_is_admin()
  );

-- 0009 dejó el default en solo-select. Se concede lo que las políticas necesitan.
grant insert, update, delete on public.zones         to authenticated;
grant insert, update, delete on public.zone_segments to authenticated;

comment on column public.zone_segments.zone_kind is
  'Siempre ''seated''. Existe para que la FK compuesta con zones(id, kind) impida que un segmento cuelgue de una zona de pie. Ver specs/003-detalle-evento/plan.md.';
