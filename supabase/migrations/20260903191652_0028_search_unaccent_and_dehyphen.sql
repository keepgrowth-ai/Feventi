-- Corrige 0027. Lo destapó AC-15: buscar «kpop» NO encontraba «K-Pop Fest 2026».
--
-- Dos cosas que la gente escribe distinto de como está guardado:
--
-- 1) SIN TILDES. «musica» no encontraba «Música». En un catálogo peruano esto no
--    es un detalle: nadie escribe tildes en un buscador.
-- 2) SIN GUIONES. to_tsvector('spanish', 'K-Pop Fest') da los lexemas k-pop, k,
--    pop y fest — ninguno es «kpop». Y «kpop» es exactamente lo que se teclea.
--
-- El (1) se resuelve con una configuración de búsqueda que pasa por unaccent.
-- El (2) indexando además una variante sin guiones, para que los dos lexemas
-- existan y la consulta acierte se escriba como se escriba.
--
-- ponytail: lo que NO cubre es juntar palabras separadas por espacio —
-- «standup» no encuentra «Stand Up», aunque sí encuentra «Stand-Up». Cubrirlo
-- exigiría indexar el título entero concatenado, que en un título largo es un
-- lexema gigante e inútil. Si aparece en las búsquedas reales, la salida es un
-- índice trigram (pg_trgm) en paralelo, no más variantes concatenadas.

create extension if not exists unaccent with schema extensions;

-- Configuración propia: español + unaccent antes del stemmer.
create text search configuration public.spanish_unaccent (copy = spanish);
alter text search configuration public.spanish_unaccent
  alter mapping for hword, hword_part, word
  with extensions.unaccent, spanish_stem;

-- Se usa la firma to_tsvector(regconfig, text), que es IMMUTABLE. La de un solo
-- argumento es solo STABLE —depende de default_text_search_config— y no vale
-- para nada que se indexe.
create or replace function private.event_search_text(
  p_title text, p_category text, p_description text,
  p_venue_name text, p_venue_city text
) returns tsvector language sql immutable set search_path = '' as $$
  select
    -- Texto tal cual: conserva k-pop, k, pop
    setweight(to_tsvector('public.spanish_unaccent', coalesce(p_title, '')),       'A')
 || setweight(to_tsvector('public.spanish_unaccent', coalesce(p_category, '')),    'B')
 || setweight(to_tsvector('public.spanish_unaccent', coalesce(p_venue_name, '')),  'B')
 || setweight(to_tsvector('public.spanish_unaccent', coalesce(p_venue_city, '')),  'B')
 || setweight(to_tsvector('public.spanish_unaccent', coalesce(p_description, '')), 'D')
    -- Variante sin guiones: añade kpop. Solo para título, categoría y venue —
    -- en la descripción no aporta y engorda el índice.
 || setweight(to_tsvector('public.spanish_unaccent',
      translate(coalesce(p_title, ''), '-', '')),      'A')
 || setweight(to_tsvector('public.spanish_unaccent',
      translate(coalesce(p_category, ''), '-', '')),   'B')
 || setweight(to_tsvector('public.spanish_unaccent',
      translate(coalesce(p_venue_name, ''), '-', '')), 'B')
$$;

-- Repoblar con la definición nueva
update public.events e
   set search_text = private.event_search_text(
         e.title, e.category, e.description, v.name, v.city)
  from public.venues v
 where v.id = e.venue_id;

update public.events
   set search_text = private.event_search_text(title, category, description, null, null)
 where venue_id is null;

revoke all on function private.event_search_text(text, text, text, text, text)
  from public, anon, authenticated;

-- La consulta tiene que usar la MISMA configuración, o unaccent no se aplica al
-- término buscado y «musica» sigue sin encontrar «Música».
--
-- Se expone como función para que el cliente no tenga que conocer el nombre de
-- la configuración ni acordarse de quitar los guiones.
create or replace function public.search_events_tsquery(p_query text)
returns tsquery language sql immutable set search_path = '' as $$
  select websearch_to_tsquery('public.spanish_unaccent', coalesce(p_query, ''))
$$;

grant execute on function public.search_events_tsquery(text) to anon, authenticated;

comment on text search configuration public.spanish_unaccent is
  'Español con unaccent antes del stemmer. Hay que usarla en el índice Y en la consulta: si solo se usa en uno de los dos, «musica» no encuentra «Música».';
