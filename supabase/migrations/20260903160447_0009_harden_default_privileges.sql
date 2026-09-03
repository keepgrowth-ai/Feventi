-- 001 Fundaciones · Art. 9.1, denegar por defecto.
--
-- Supabase concede ALL sobre las tablas de public a anon y authenticated por
-- privilegios por defecto. ALL incluye TRUNCATE, y TRUNCATE **no está sujeto a
-- RLS**: se comprobó que `set role anon; truncate public.organizers` pasa.
--
-- PostgREST nunca emite TRUNCATE, así que no es una puerta abierta hoy. Pero es
-- una mina esperando la primera RPC `security invoker` con SQL dinámico, y
-- cerrarla cuesta seis líneas.
--
-- Aprovechando, se invierte el default a lo que pide el Art. 9: nada por
-- defecto, y cada feature concede explícitamente lo que su tabla necesita.

-- Lo ya creado
revoke truncate, trigger, references on all tables in schema public from anon, authenticated;
revoke select on public.organizers, public.organizer_members, public.user_roles from anon;

-- Lo que venga. Los privilegios por defecto de Supabase están definidos para el
-- rol postgres, así que hay que recortarlos ahí.
alter default privileges for role postgres in schema public
  revoke truncate, trigger, references on tables from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke insert, update, delete on tables from anon, authenticated;

-- anon no lee ninguna tabla nueva. Su única superficie son las vistas públicas,
-- que se conceden una por una (data-model.md §7).
alter default privileges for role postgres in schema public
  revoke select on tables from anon;

comment on schema public is
  'Denegar por defecto (Art. 9.1): las tablas nuevas nacen sin insert/update/delete para el cliente y sin nada para anon. Cada feature concede lo suyo de forma explícita.';
