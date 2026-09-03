-- Corrige 0002. AC-10 lo destapó.
--
-- En Postgres un GRANT de SELECT a nivel de tabla implica select sobre TODAS las
-- columnas, y un REVOKE de columna no lo puede recortar. Supabase concede
-- select de tabla a anon y authenticated por privilegios por defecto, así que el
-- `revoke select (dni_hash)` de 0002 no tuvo ningún efecto.
--
-- El orden correcto es: revocar el privilegio de tabla primero, después conceder
-- columna por columna. Lo mismo que ya se hizo bien con UPDATE en 0002.
--
-- Esto FUNCIONA, pero deja una trampa: PostgREST emite `select *` cuando el
-- cliente no pide columnas, así que un GET a /profiles devuelve 42501. 0008 lo
-- resuelve de raíz sacando el hash a su propia tabla.

revoke select on public.profiles from authenticated, anon;

-- Todo menos dni_hash. Art. 7.1: es el identificador con el que se valida en
-- puerta; que el fan lo lea es entregarle la pieza que necesita para suplantar.
grant select (
  id, full_name, email, phone,
  dni_last4, dni_verified_at,
  ninja_mode, avatar_url,
  created_at, updated_at
) on public.profiles to authenticated;

-- anon no lee identidad, ni una columna. AC-28.
