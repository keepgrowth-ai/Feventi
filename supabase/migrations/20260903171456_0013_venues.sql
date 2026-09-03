-- 007 · T-02
--
-- OJO: la política `venues_write_admin` que crea esta migración usa `for all`,
-- que INCLUYE select, y por eso se solapaba con `venues_select`. 0018 la separa.
-- Las migraciones son inmutables (Art. 12.4): esto queda como está.

create table public.venues (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  city       text not null,
  address    text,
  capacity   int check (capacity is null or capacity > 0),
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index venues_city_idx on public.venues (city);

create trigger venues_touch_updated_at
  before update on public.venues
  for each row execute function public.touch_updated_at();

alter table public.venues enable row level security;

-- Un venue es un dato compartido: dos organizadores pueden usar el Estadio
-- Nacional. Cualquier usuario autenticado lo lee; solo Admin lo edita, para que
-- nadie renombre el venue de otro ni le cambie el aforo.
create policy venues_select on public.venues
  for select to authenticated
  using (true);

create policy venues_write_admin on public.venues
  for all to authenticated
  using (private.auth_is_admin())
  with check (private.auth_is_admin());

-- 0009 dejó el default en solo-select; aquí se concede la escritura que la
-- política de Admin necesita poder ejercer.
grant insert, update, delete on public.venues to authenticated;

comment on table public.venues is
  'Dato compartido entre organizadores. Lectura para todo autenticado, escritura solo Admin: el aforo declarado de un venue es un control, no una preferencia del organizador.';
