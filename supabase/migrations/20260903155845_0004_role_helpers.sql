-- 001 Fundaciones · T-06
-- AC-13, AC-14, AC-15. Art. 9.2.
--
-- security definer no es una puerta trasera aquí: es lo que evita la recursión.
-- Una política sobre user_roles que hiciera join a user_roles se llamaría a sí
-- misma. La contención es search_path fijo y que la función solo devuelva
-- booleanos o ids del propio llamante.
--
-- Nota: 0010 mueve estas cuatro funciones al schema `private`, que PostgREST no
-- expone. Las políticas creadas aquí siguen valiendo porque las resuelven por
-- OID, y ALTER FUNCTION ... SET SCHEMA lo conserva.

create or replace function public.auth_has_role(p_role public.app_role)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = (select auth.uid()) and role = p_role
  )
$$;

create or replace function public.auth_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.auth_has_role('admin')
$$;

-- Devuelve array, no exists: se evalúa una vez por consulta y las políticas
-- quedan en `organizer_id = any(...)`, que usa índice. Un exists correlacionado
-- se evaluaría por fila.
create or replace function public.auth_organizer_ids()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(organizer_id), '{}'::uuid[])
  from public.organizer_members
  where user_id = (select auth.uid())
    and revoked_at is null   -- AC-22: revocado deja de contar, sin borrar la fila
$$;

comment on function public.auth_organizer_ids() is
  'Organizadores a los que pertenece el llamante, sin los revocados. Art. 8.2.';

revoke all on function public.auth_has_role(public.app_role) from public, anon;
revoke all on function public.auth_is_admin()                from public, anon;
revoke all on function public.auth_organizer_ids()           from public, anon;

grant execute on function public.auth_has_role(public.app_role) to authenticated;
grant execute on function public.auth_is_admin()                to authenticated;
grant execute on function public.auth_organizer_ids()           to authenticated;

-- ── Políticas que dependen de los helpers ───────────────────────────────────

-- Admin ve toda la identidad; el fan solo la suya (políticas de 0002).
create policy profiles_select_admin on public.profiles
  for select to authenticated
  using (public.auth_is_admin());

create policy user_roles_select_admin on public.user_roles
  for select to authenticated
  using (public.auth_is_admin());

-- AC-18, AC-19: el organizador A no ve ni una fila del organizador B.
create policy organizers_select_member on public.organizers
  for select to authenticated
  using (id = any (public.auth_organizer_ids()));

create policy organizers_select_admin on public.organizers
  for select to authenticated
  using (public.auth_is_admin());

create policy organizer_members_select_member on public.organizer_members
  for select to authenticated
  using (organizer_id = any (public.auth_organizer_ids()));

create policy organizer_members_select_admin on public.organizer_members
  for select to authenticated
  using (public.auth_is_admin());
