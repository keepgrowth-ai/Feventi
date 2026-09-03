-- 001 Fundaciones · T-08, T-09, T-10
-- Escritura con reglas de negocio: RPC security definer, no política.
-- Una política puede decir "sí o no"; no puede decir "sí, pero el status lo pongo yo".
--
-- Nota: 0010 reescribe estos cuerpos para que llamen a private.auth_* en lugar
-- de public.auth_*.

-- AC-16, AC-17
create or replace function public.create_organizer(
  p_legal_name    text,
  p_trade_name    text default null,
  p_ruc           text default null,
  p_contact_email text default null,
  p_contact_phone text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id  uuid;
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'no autenticado' using errcode = '28000';
  end if;
  if coalesce(btrim(p_legal_name), '') = '' then
    raise exception 'legal_name es obligatorio' using errcode = '22023';
  end if;

  insert into public.organizers (
    legal_name, trade_name, ruc, contact_email, contact_phone, status, created_by
  ) values (
    btrim(p_legal_name), nullif(btrim(p_trade_name), ''), nullif(btrim(p_ruc), ''),
    nullif(btrim(p_contact_email), ''), nullif(btrim(p_contact_phone), ''),
    'pending',  -- AC-17: lo fija el servidor, nunca el payload
    v_uid
  ) returning id into v_id;

  insert into public.organizer_members (organizer_id, user_id, role, invited_by)
  values (v_id, v_uid, 'owner', v_uid);

  insert into public.user_roles (user_id, role)
  values (v_uid, 'organizer') on conflict do nothing;

  return v_id;
end $$;

-- ¿El llamante manda en este organizador?
create or replace function public.auth_owns_organizer(p_organizer_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.organizer_members
    where organizer_id = p_organizer_id
      and user_id = (select auth.uid())
      and role in ('owner', 'admin')
      and revoked_at is null
  )
$$;

-- AC-20
create or replace function public.add_organizer_member(
  p_organizer_id uuid,
  p_user_id      uuid,
  p_role         public.organizer_role default 'viewer'
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_uid uuid := (select auth.uid());
begin
  if not (public.auth_owns_organizer(p_organizer_id) or public.auth_is_admin()) then
    raise exception 'sin permiso sobre este organizador' using errcode = '42501';
  end if;
  if p_role = 'owner' and not public.auth_is_admin() then
    raise exception 'solo Admin asigna owner' using errcode = '42501';
  end if;

  insert into public.organizer_members (organizer_id, user_id, role, invited_by)
  values (p_organizer_id, p_user_id, p_role, v_uid)
  on conflict (organizer_id, user_id)
    do update set role = excluded.role, revoked_at = null, invited_by = v_uid;

  insert into public.user_roles (user_id, role)
  values (p_user_id, 'organizer') on conflict do nothing;
end $$;

-- AC-21: revocar es un update, no un delete. Art. 8.2.
create or replace function public.revoke_organizer_member(
  p_organizer_id uuid,
  p_user_id      uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (public.auth_owns_organizer(p_organizer_id) or public.auth_is_admin()) then
    raise exception 'sin permiso sobre este organizador' using errcode = '42501';
  end if;

  update public.organizer_members
     set revoked_at = now()
   where organizer_id = p_organizer_id
     and user_id = p_user_id
     and revoked_at is null;
end $$;

-- AC-23, AC-24
create or replace function public.approve_organizer(p_organizer_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.auth_is_admin() then
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
  p_organizer_id uuid,
  p_status       public.organizer_status
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.auth_is_admin() then
    raise exception 'solo Admin' using errcode = '42501';
  end if;
  update public.organizers set status = p_status where id = p_organizer_id;
end $$;

revoke all on function public.create_organizer(text, text, text, text, text)          from public, anon;
revoke all on function public.auth_owns_organizer(uuid)                               from public, anon;
revoke all on function public.add_organizer_member(uuid, uuid, public.organizer_role)  from public, anon;
revoke all on function public.revoke_organizer_member(uuid, uuid)                      from public, anon;
revoke all on function public.approve_organizer(uuid)                                  from public, anon;
revoke all on function public.set_organizer_status(uuid, public.organizer_status)       from public, anon;

grant execute on function public.create_organizer(text, text, text, text, text)         to authenticated;
grant execute on function public.auth_owns_organizer(uuid)                              to authenticated;
grant execute on function public.add_organizer_member(uuid, uuid, public.organizer_role) to authenticated;
grant execute on function public.revoke_organizer_member(uuid, uuid)                     to authenticated;
grant execute on function public.approve_organizer(uuid)                                 to authenticated;
grant execute on function public.set_organizer_status(uuid, public.organizer_status)      to authenticated;

-- El organizador edita su propia ficha de contacto, nunca su status (AC-23).
create policy organizers_update_member on public.organizers
  for update to authenticated
  using (id = any (public.auth_organizer_ids()) and public.auth_owns_organizer(id))
  with check (id = any (public.auth_organizer_ids()));

grant update (legal_name, trade_name, ruc, contact_email, contact_phone)
  on public.organizers to authenticated;
