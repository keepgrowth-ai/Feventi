-- 010 · segunda corrección de 0052
--
-- Las tres RPC nuevas quedaron ejecutables por `anon` y por `PUBLIC`:
--
--   block_user          =X/postgres | anon=X | authenticated=X | service_role=X
--   create_event                      postgres=X | authenticated=X | service_role=X
--
-- El `grant execute … to authenticated` de 0052 AÑADE; no quita el `execute`
-- que `PUBLIC` trae de fábrica. Las RPC de 001/004/007/009 sí lo revocan, y por
-- eso su ACL no tiene la entrada vacía `=X/postgres`.
--
-- Las tres empiezan por `if auth.uid() is null then raise`, así que una llamada
-- anónima ya fallaba. Pero eso es la comprobación de dentro, no el permiso: lo
-- que decide quién puede llamar es el `execute`, y publicar en `/rest/v1/rpc/`
-- una función de escritura para un rol que no debería tocarla es superficie
-- regalada. La comprobación de dentro es la segunda línea, no la primera.

revoke execute on function public.request_friendship(text)         from public, anon;
revoke execute on function public.respond_friendship(uuid, boolean) from public, anon;
revoke execute on function public.block_user(uuid)                  from public, anon;
