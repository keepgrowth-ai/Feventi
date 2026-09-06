-- 012 · corrección de 0058 · Art. 12.4
--
-- Las dos políticas de 0058 provocaban:
--
--   ERROR: 42P17: infinite recursion detected in policy for relation "group_members"
--
-- La política de `group_members` consultaba `group_members` para saber si el
-- llamante era miembro, y esa consulta vuelve a evaluar la política. El linter
-- no lo ve: solo aparece al leer la tabla.
--
-- El proyecto ya tenía la salida escrita desde `0004`: un helper `security
-- definer` que devuelve un ARRAY. Se evalúa una vez por consulta y deja la
-- política en `group_id = any (...)`, que usa índice — un `exists`
-- correlacionado se evaluaría por fila, aparte de recursar.

create or replace function private.auth_group_ids()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $fn$
  select coalesce(array_agg(gm.group_id), '{}'::uuid[])
  from public.group_members gm
  where gm.user_id = (select auth.uid())
$fn$;

comment on function private.auth_group_ids() is
  'Grupos de compra del llamante. Definer para romper la recursion de la politica de group_members (0058).';

grant execute on function private.auth_group_ids() to authenticated;
revoke all on function private.auth_group_ids() from public, anon;

drop policy purchase_groups_select on public.purchase_groups;
drop policy group_members_select   on public.group_members;

-- El creador se comprueba directo: es una columna de la propia fila y no
-- necesita el helper. El OR va con el caso comun primero.
create policy purchase_groups_select on public.purchase_groups
  for select to authenticated
  using (
    creator_id = (select auth.uid())
    or id = any (private.auth_group_ids())
  );

create policy group_members_select on public.group_members
  for select to authenticated
  using (group_id = any (private.auth_group_ids()));
