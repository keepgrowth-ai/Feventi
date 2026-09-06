-- 013 · corrección de 0057 · Art. 12.4
--
--   WARN  function_search_path_mutable  private.checkin_points
--
-- Se me pasó el `set search_path`. La función es `immutable` y devuelve un
-- literal, así que no hay nada que secuestrar hoy — pero la regla del proyecto
-- no es «cuando importe»: es que toda función de `private` lo lleve, porque el
-- día que alguien le añada una consulta dentro nadie va a volver a mirar la
-- cabecera.
create or replace function private.checkin_points()
returns integer
language sql
immutable
set search_path = ''
as $fn$ select 50 $fn$;
