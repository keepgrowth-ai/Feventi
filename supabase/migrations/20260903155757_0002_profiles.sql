-- 001 Fundaciones · T-03, T-04
-- profiles: espejo 1:1 de auth.users. Art. 7 (datos personales), Art. 9 (denegar por defecto).
--
-- OJO: la columna dni_hash que crea esta migración se elimina en 0008, que la
-- muda a public.profile_identity. Y el `revoke select (dni_hash)` de abajo NO
-- surte efecto — ver 0007. Las migraciones son inmutables (Art. 12.4): esto se
-- queda como está y se corrige más adelante.

create table public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  full_name       text,
  email           text,
  phone           text,
  -- Art. 7.1: el DNI en claro no se persiste. Solo HMAC con pepper + últimos 4.
  dni_hash        text,
  dni_last4       char(4),
  dni_verified_at timestamptz,
  -- Art. 7.3: oculta actividad social, no controles internos.
  ninja_mode      boolean     not null default false,
  avatar_url      text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index profiles_email_idx    on public.profiles (email);
create index profiles_dni_hash_idx on public.profiles (dni_hash) where dni_hash is not null;

comment on column public.profiles.dni_hash is
  'HMAC-SHA256(dni, pepper de Vault). Determinista para poder nominar y buscar en puerta; con pepper para que 10^8 DNIs no sean fuerza bruta. Revocado al cliente.';

-- updated_at por trigger: es el único campo que no debe depender de que el cliente lo mande.
create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ── user_roles (T-05) ────────────────────────────────────────────────────────
create table public.user_roles (
  user_id    uuid        not null references public.profiles (id) on delete cascade,
  role       public.app_role not null,
  created_at timestamptz not null default now(),
  primary key (user_id, role)
);

-- ── AC-01, AC-02: el registro crea profile + rol fan sin ningún paso manual ──
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, new.raw_user_meta_data ->> 'full_name')
  on conflict (id) do nothing;

  insert into public.user_roles (user_id, role)
  values (new.id, 'fan')
  on conflict do nothing;

  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── RLS: en la misma migración que crea la tabla (plan.md, regla 1) ──────────
alter table public.profiles   enable row level security;
alter table public.user_roles enable row level security;

-- AC-04, AC-28: el fan ve una fila, la suya; anon ve cero.
create policy profiles_select_own on public.profiles
  for select to authenticated
  using (id = (select auth.uid()));

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- AC-11, AC-12: solo lectura de las propias filas. Sin insert/update/delete.
create policy user_roles_select_own on public.user_roles
  for select to authenticated
  using (user_id = (select auth.uid()));

-- ── Privilegios de columna: más barato y más difícil de olvidar que un trigger ─
-- AC-06, AC-07: el cliente no escribe identidad ni verificación.
revoke insert, update, delete on public.profiles from authenticated, anon;
grant  update (full_name, phone, avatar_url, ninja_mode) on public.profiles to authenticated;

-- AC-10: si el fan pudiera leer el hash, tendría el identificador con el que se
-- valida en puerta. Si pudiera escribirlo, copiaría el de otra persona.
-- ⚠ Este revoke NO funciona: un grant de SELECT a nivel de tabla implica select
--   sobre todas las columnas y un revoke de columna no lo recorta. Corregido en
--   0007 y resuelto de raíz en 0008.
revoke select (dni_hash) on public.profiles from authenticated, anon;

revoke insert, update, delete on public.user_roles from authenticated, anon;
