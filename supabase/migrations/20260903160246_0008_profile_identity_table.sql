-- Corrige 0007. Art. 7.1.
--
-- 0007 dejó dni_hash inaccesible con un revoke de columna, y funciona, pero deja
-- una trampa: PostgREST emite `select *` cuando el cliente no pide columnas, así
-- que un GET normal a /profiles devuelve 42501. Alguien va a "arreglarlo"
-- volviendo a conceder select de tabla y reabrirá el agujero sin notarlo.
--
-- Se saca el hash a su propia tabla, con el mismo patrón que ticket_secrets
-- (Art. 2.6): RLS activa y CERO políticas. Inalcanzable por diseño, no por un
-- privilegio de columna que alguien pueda revertir de un grant.

create table public.profile_identity (
  user_id    uuid primary key references public.profiles (id) on delete cascade,
  dni_hash   text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index profile_identity_dni_hash_idx on public.profile_identity (dni_hash);

comment on table public.profile_identity is
  'HMAC del DNI, aislado. RLS activa y sin ninguna política: solo service_role y funciones security definer. Art. 7.1, mismo patrón que ticket_secrets.';

create trigger profile_identity_touch_updated_at
  before update on public.profile_identity
  for each row execute function public.touch_updated_at();

-- Mudanza de lo que ya existe
insert into public.profile_identity (user_id, dni_hash)
select id, dni_hash from public.profiles where dni_hash is not null
on conflict (user_id) do nothing;

drop index if exists public.profiles_dni_hash_idx;
alter table public.profiles drop column dni_hash;

-- RLS activa, sin políticas: nadie pasa.
alter table public.profile_identity enable row level security;
revoke all on public.profile_identity from authenticated, anon;

-- profiles vuelve a ser legible entero: ya no esconde nada.
grant select on public.profiles to authenticated;

-- set_own_dni ahora escribe en las dos tablas: el hash aislado y el last4 visible.
create or replace function public.set_own_dni(p_dni text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'no autenticado' using errcode = '28000';
  end if;

  insert into public.profile_identity (user_id, dni_hash)
  values (v_uid, public.hash_dni(p_dni))   -- hash_dni valida el formato
  on conflict (user_id) do update set dni_hash = excluded.dni_hash;

  update public.profiles set dni_last4 = right(p_dni, 4) where id = v_uid;
end $$;

create or replace function public.verify_dni(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.auth_is_admin() then
    raise exception 'solo Admin' using errcode = '42501';
  end if;

  update public.profiles
     set dni_verified_at = now()
   where id = p_user_id
     and exists (select 1 from public.profile_identity where user_id = p_user_id);

  if not found then
    raise exception 'perfil inexistente o sin DNI declarado' using errcode = '22023';
  end if;
end $$;
