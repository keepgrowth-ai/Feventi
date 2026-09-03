-- 001 Fundaciones · hallazgo del linter de rendimiento.
--
-- 0002 y 0004 dejaron dos políticas permisivas de SELECT por tabla: una para el
-- dueño y otra para Admin. Postgres tiene que evaluar LAS DOS en cada consulta
-- de cada fila, y `auth_is_admin()` se ejecuta también para los fans, que son
-- el 99 % del tráfico.
--
-- Una sola política con OR hace lo mismo con una evaluación. Y el orden importa:
-- la condición del caso común va PRIMERO, para que el cortocircuito del OR se
-- ahorre la llamada al helper en el camino caliente.
--
-- Se corrige ahora y no más adelante porque esta es la convención que van a
-- copiar los features 002-009: mejor que copien la buena.

drop policy profiles_select_own   on public.profiles;
drop policy profiles_select_admin on public.profiles;

create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())     -- caso común primero: corta antes de llamar al helper
    or private.auth_is_admin()
  );

drop policy user_roles_select_own   on public.user_roles;
drop policy user_roles_select_admin on public.user_roles;

create policy user_roles_select on public.user_roles
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or private.auth_is_admin()
  );

drop policy organizers_select_member on public.organizers;
drop policy organizers_select_admin  on public.organizers;

create policy organizers_select on public.organizers
  for select to authenticated
  using (
    id = any (private.auth_organizer_ids())
    or private.auth_is_admin()
  );

drop policy organizer_members_select_member on public.organizer_members;
drop policy organizer_members_select_admin  on public.organizer_members;

create policy organizer_members_select on public.organizer_members
  for select to authenticated
  using (
    organizer_id = any (private.auth_organizer_ids())
    or private.auth_is_admin()
  );
