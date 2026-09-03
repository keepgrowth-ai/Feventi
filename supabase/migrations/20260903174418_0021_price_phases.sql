-- 003 · T-05 · AC-06

create table public.price_phases (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events (id) on delete cascade,
  name       text not null,
  kind       public.phase_kind not null default 'presale',
  starts_at  timestamptz not null,
  ends_at    timestamptz not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint price_phases_window check (ends_at > starts_at),

  -- AC-06. Sin esto, dos fases solapadas dejan el precio INDETERMINADO: la
  -- consulta devuelve dos filas para el mismo cruce y el "precio desde" acaba
  -- dependiendo del plan de ejecución. Es el bug que aparece un viernes con el
  -- evento a la venta.
  --
  -- '[)' — el fin es exclusivo, así que una fase puede empezar exactamente
  -- cuando termina la anterior sin que cuente como solape.
  constraint price_phases_no_overlap exclude using gist (
    event_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  )
);

create index price_phases_event_idx on public.price_phases (event_id, starts_at);

create trigger price_phases_touch_updated_at
  before update on public.price_phases
  for each row execute function public.touch_updated_at();

alter table public.price_phases enable row level security;

create policy price_phases_select on public.price_phases
  for select to authenticated
  using (
    event_id in (select id from public.events
                  where organizer_id = any (private.auth_organizer_ids()))
    or private.auth_is_admin()
  );

create policy price_phases_insert on public.price_phases
  for insert to authenticated
  with check (
    event_id in (select id from public.events
                  where organizer_id = any (private.auth_organizer_ids()))
    or private.auth_is_admin()
  );

create policy price_phases_update on public.price_phases
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

create policy price_phases_delete on public.price_phases
  for delete to authenticated
  using (
    event_id in (select id from public.events
                  where organizer_id = any (private.auth_organizer_ids()))
    or private.auth_is_admin()
  );

grant insert, update, delete on public.price_phases to authenticated;

-- La fase activa se CALCULA, no se guarda: un estado guardado se desincroniza en
-- cuanto nadie lo mira. Art. 12.5 aplicado al inventario.
create or replace function public.active_phase_id(p_event_id uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select id from public.price_phases
   where event_id = p_event_id
     and now() >= starts_at and now() < ends_at
   limit 1
$$;

revoke all on function public.active_phase_id(uuid) from public;
grant execute on function public.active_phase_id(uuid) to authenticated, anon;

comment on constraint price_phases_no_overlap on public.price_phases is
  'AC-06: dos fases del mismo evento no pueden solaparse en el tiempo, o el precio queda indeterminado.';
