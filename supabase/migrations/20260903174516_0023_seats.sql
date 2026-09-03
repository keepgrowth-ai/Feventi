-- 003 · T-10, T-11
--
-- Solo para zonas numeradas. La disponibilidad NO se guarda aquí: se deriva de
-- los order_items vivos (004). Un booleano `available` en esta tabla se
-- desincroniza la primera vez que una reserva expira sin que nadie lo actualice.
--
-- `blocked` es otra cosa: es una decisión operativa del organizador —cabina de
-- sonido, visibilidad mala, butaca rota—, no un reflejo de la venta.

create table public.seats (
  id          uuid primary key default gen_random_uuid(),
  zone_id     uuid not null references public.zones (id) on delete cascade,
  -- Igual que en zone_segments: la FK compuesta hace imposible un asiento en
  -- una zona de pie (AC-05).
  zone_kind   public.zone_kind not null default 'seated'
                check (zone_kind = 'seated'),
  segment_id  uuid,
  row_label   text not null,
  seat_number int  not null check (seat_number > 0),
  blocked     boolean not null default false,
  block_reason text,
  created_at  timestamptz not null default now(),

  constraint seats_zone_is_seated_fk
    foreign key (zone_id, zone_kind) references public.zones (id, kind)
    on delete cascade,

  -- AC-04 aplicado a asientos: el segmento pertenece a su zona.
  constraint seats_segment_in_zone_fk
    foreign key (zone_id, segment_id) references public.zone_segments (zone_id, id)
    on delete set null (segment_id),

  -- AC-08
  constraint seats_unique_in_zone unique (zone_id, row_label, seat_number)
);

create index seats_zone_idx    on public.seats (zone_id, row_label, seat_number);
create index seats_segment_idx on public.seats (segment_id) where segment_id is not null;

-- ── AC-09: los asientos no superan el aforo de su zona ──────────────────────
create or replace function private.check_zone_seats()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_capacity int; v_count int; v_zone text;
begin
  select z.capacity, z.name into v_capacity, v_zone
    from public.zones z where z.id = new.zone_id;

  select count(*) into v_count
    from public.seats where zone_id = new.zone_id and id <> new.id;

  if v_count + 1 > v_capacity then
    raise exception 'la zona % ya tiene % asientos y su aforo es %',
      v_zone, v_count, v_capacity using errcode = '23514';
  end if;

  return new;
end $$;

create trigger seats_check_zone_capacity
  before insert or update of zone_id on public.seats
  for each row execute function private.check_zone_seats();

revoke all on function private.check_zone_seats() from public, anon, authenticated;

-- ── Generar asientos por rango: la carga a mano no es viable ────────────────
-- 45 filas × 20 asientos son 900 inserts. Con un solo statement el trigger de
-- aforo se evalúa 900 veces igual, pero el viaje de red es uno.
create or replace function public.generate_seats(
  p_zone_id    uuid,
  p_rows       text[],
  p_per_row    int,
  p_segment_id uuid default null
) returns int language plpgsql security definer set search_path = '' as $$
declare v_inserted int; v_kind public.zone_kind;
begin
  if not exists (
    select 1 from public.zones z
    join public.events e on e.id = z.event_id
    where z.id = p_zone_id
      and (e.organizer_id = any (private.auth_organizer_ids())
           or private.auth_is_admin())
  ) then
    raise exception 'sin permiso sobre esta zona' using errcode = '42501';
  end if;

  select kind into v_kind from public.zones where id = p_zone_id;
  if v_kind <> 'seated' then
    raise exception 'solo una zona numerada tiene asientos' using errcode = '22023';
  end if;
  if p_per_row < 1 then
    raise exception 'la cantidad por fila tiene que ser al menos 1' using errcode = '22023';
  end if;

  insert into public.seats (zone_id, segment_id, row_label, seat_number)
  select p_zone_id, p_segment_id, r, n
    from unnest(p_rows) as r,
         generate_series(1, p_per_row) as n
  on conflict (zone_id, row_label, seat_number) do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end $$;

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.seats enable row level security;

create policy seats_select on public.seats
  for select to authenticated
  using (
    zone_id in (select z.id from public.zones z
                join public.events e on e.id = z.event_id
                where e.organizer_id = any (private.auth_organizer_ids()))
    or private.auth_is_admin()
  );

create policy seats_insert on public.seats
  for insert to authenticated
  with check (
    zone_id in (select z.id from public.zones z
                join public.events e on e.id = z.event_id
                where e.organizer_id = any (private.auth_organizer_ids()))
    or private.auth_is_admin()
  );

create policy seats_update on public.seats
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

create policy seats_delete on public.seats
  for delete to authenticated
  using (
    zone_id in (select z.id from public.zones z
                join public.events e on e.id = z.event_id
                where e.organizer_id = any (private.auth_organizer_ids()))
    or private.auth_is_admin()
  );

grant insert, update, delete on public.seats to authenticated;

revoke all on function public.generate_seats(uuid, text[], int, uuid) from public, anon;
grant execute on function public.generate_seats(uuid, text[], int, uuid) to authenticated;

comment on table public.seats is
  'La disponibilidad no vive aquí: se deriva de order_items vivos (004). `blocked` es decisión operativa del organizador, no reflejo de la venta.';
