-- Corrige 0013. Hallazgo del linter de rendimiento.
--
-- `for all` INCLUYE select. Así que venues tenía dos políticas permisivas de
-- lectura —venues_select (true) y venues_write_admin (auth_is_admin())— y
-- Postgres evaluaba las dos en cada consulta, llamando al helper para todo el
-- mundo cuando la primera ya devolvía true.
--
-- Es la misma trampa que 0011, escondida en un `for all`: la convención del
-- plan dice "una política por OPERACIÓN", y `for all` son cuatro operaciones.
-- Se separan las tres de escritura y la lectura queda sola.

drop policy venues_write_admin on public.venues;

create policy venues_insert_admin on public.venues
  for insert to authenticated
  with check (private.auth_is_admin());

create policy venues_update_admin on public.venues
  for update to authenticated
  using (private.auth_is_admin())
  with check (private.auth_is_admin());

create policy venues_delete_admin on public.venues
  for delete to authenticated
  using (private.auth_is_admin());
