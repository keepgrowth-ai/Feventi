-- 001 Fundaciones · AC-27. Hallazgos del linter de seguridad.
--
-- 1) handle_new_user() quedaba expuesta en /rest/v1/rpc/handle_new_user. Es una
--    función de trigger: llamarla directo falla porque no hay NEW, pero no tiene
--    ninguna razón para estar en la superficie de la API.
-- 2) Los helpers auth_* no son RPC: son piezas internas de las políticas. Van a
--    un schema que PostgREST no expone. Las políticas los siguen resolviendo por
--    OID, así que ALTER ... SET SCHEMA no las rompe.
--
-- Lo que SÍ se queda en public es la superficie real de RPC: create_organizer,
-- add/revoke_organizer_member, approve/set_organizer_status, set_own_dni,
-- verify_dni. Cada una comprueba autorización en su propio cuerpo.

create schema if not exists private;
revoke all on schema private from anon, authenticated;
grant usage on schema private to authenticated;

-- handle_new_user: solo el trigger. El privilegio de ejecución de una función de
-- trigger se comprueba al crear el trigger, no al dispararlo, así que revocarlo
-- no afecta al registro de usuarios (verificado con un alta real por la Auth API).
revoke all on function public.handle_new_user() from public, anon, authenticated;
alter function public.handle_new_user() set schema private;

alter function public.auth_has_role(public.app_role) set schema private;
alter function public.auth_is_admin()                set schema private;
alter function public.auth_organizer_ids()           set schema private;
alter function public.auth_owns_organizer(uuid)      set schema private;
alter function public.hash_dni(text)                 set schema private;

-- auth_is_admin llamaba a public.auth_has_role, que ya no está ahí.
-- create or replace conserva el OID, así que las políticas no se enteran.
create or replace function private.auth_is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select private.auth_has_role('admin')
$$;

-- set_own_dni llamaba a public.hash_dni
create or replace function public.set_own_dni(p_dni text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'no autenticado' using errcode = '28000';
  end if;

  insert into public.profile_identity (user_id, dni_hash)
  values (v_uid, private.hash_dni(p_dni))
  on conflict (user_id) do update set dni_hash = excluded.dni_hash;

  update public.profiles set dni_last4 = right(p_dni, 4) where id = v_uid;
end $$;

create or replace function public.verify_dni(p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.auth_is_admin() then
    raise exception 'solo Admin' using errcode = '42501';
  end if;
  update public.profiles set dni_verified_at = now()
   where id = p_user_id
     and exists (select 1 from public.profile_identity where user_id = p_user_id);
  if not found then
    raise exception 'perfil inexistente o sin DNI declarado' using errcode = '22023';
  end if;
end $$;

create or replace function public.add_organizer_member(
  p_organizer_id uuid, p_user_id uuid, p_role public.organizer_role default 'viewer'
) returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid());
begin
  if not (private.auth_owns_organizer(p_organizer_id) or private.auth_is_admin()) then
    raise exception 'sin permiso sobre este organizador' using errcode = '42501';
  end if;
  if p_role = 'owner' and not private.auth_is_admin() then
    raise exception 'solo Admin asigna owner' using errcode = '42501';
  end if;
  insert into public.organizer_members (organizer_id, user_id, role, invited_by)
  values (p_organizer_id, p_user_id, p_role, v_uid)
  on conflict (organizer_id, user_id)
    do update set role = excluded.role, revoked_at = null, invited_by = v_uid;
  insert into public.user_roles (user_id, role)
  values (p_user_id, 'organizer') on conflict do nothing;
end $$;

create or replace function public.revoke_organizer_member(
  p_organizer_id uuid, p_user_id uuid
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if not (private.auth_owns_organizer(p_organizer_id) or private.auth_is_admin()) then
    raise exception 'sin permiso sobre este organizador' using errcode = '42501';
  end if;
  update public.organizer_members set revoked_at = now()
   where organizer_id = p_organizer_id and user_id = p_user_id and revoked_at is null;
end $$;

create or replace function public.approve_organizer(p_organizer_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.auth_is_admin() then
    raise exception 'solo Admin' using errcode = '42501';
  end if;
  update public.organizers
     set status = 'approved', approved_at = now(), approved_by = (select auth.uid())
   where id = p_organizer_id and status = 'pending';
  if not found then
    raise exception 'organizador inexistente o no está en pending' using errcode = '22023';
  end if;
end $$;

create or replace function public.set_organizer_status(
  p_organizer_id uuid, p_status public.organizer_status
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.auth_is_admin() then
    raise exception 'solo Admin' using errcode = '42501';
  end if;
  update public.organizers set status = p_status where id = p_organizer_id;
end $$;

grant execute on function private.auth_has_role(public.app_role) to authenticated;
grant execute on function private.auth_is_admin()                to authenticated;
grant execute on function private.auth_organizer_ids()           to authenticated;
grant execute on function private.auth_owns_organizer(uuid)      to authenticated;
revoke all on function private.hash_dni(text) from public, anon, authenticated;

comment on schema private is
  'Piezas internas: helpers de RLS y funciones de trigger. PostgREST no expone este schema, así que nada de aquí es un endpoint. Las políticas resuelven por OID.';
