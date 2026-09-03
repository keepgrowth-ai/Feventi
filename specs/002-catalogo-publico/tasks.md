# 002 — Tasks

**Cerrado.** 25 comprobaciones en verde. Rendimiento sin `WARN`. Seguridad con un
`ERROR` **argumentado** — ver la nota abajo.

El feature más corto de Fase 1, y a propósito: el catálogo es una proyección de
003. Una sola migración; si hubieran hecho falta más, sería señal de que 003 dejó
algo sin cerrar.

## Base de datos

- [x] T-01 `0027_event_search`: `events.search_text tsvector` + índice GIN — AC-13, AC-15
- [x] T-02 `0027_event_search`: trigger en `events` (título, descripción, categoría, venue)
- [x] T-03 `0027_event_search`: trigger en `venues` — al renombrar un venue, refresca
      el texto de sus eventos. Si no, el catálogo deja de encontrarlos por el nombre
      nuevo **y** por el viejo
- [x] T-04 `0027_event_search`: `search_text` expuesto en `v_event_public` para poder
      filtrar con `wfts`. Se filtra, **no** se selecciona
- [x] T-05 `0028_search_unaccent_and_dehyphen`: configuración `spanish_unaccent` y
      variante sin guiones

### Lo que salió de las pruebas

- [x] T-05b Buscar **«kpop» no encontraba «K-Pop Fest 2026»**. El tokenizador da
      `k-pop`, `k`, `pop` — ninguno es `kpop`, y `kpop` es exactamente lo que se
      teclea. Se indexa además una variante sin guiones
- [x] T-05c **Sin tildes tampoco encontraba.** «musica» no daba «Música». En un
      catálogo peruano eso no es un detalle: nadie escribe tildes en un buscador. Se
      resuelve con `unaccent` **en el índice y en la consulta** — solo en uno de los
      dos no sirve de nada
- [x] T-05d `search_events_tsquery()` expuesta, para que el cliente no tenga que
      conocer el nombre de la configuración

## Verificación

- [x] T-06 `supabase/tests/002_catalogo_publico.sql`
- [x] T-07 25/25 en verde
- [x] T-08 13 términos de búsqueda reales: con y sin guion, con y sin tilde, por
      nombre del venue, por ciudad, por palabra de la descripción, y uno que no existe
- [x] T-09 **AC-14 con `starts_at` empatado**: el keyset `(starts_at, id)` devuelve
      los 4; el atajo `.gt('starts_at')` devuelve una segunda página **vacía** y pierde
      2 de 4. Las dos cosas están probadas, para que nadie «simplifique» el cursor
- [x] T-10 **AC-12**: el «desde» de la card sale de la misma vista que el mínimo del
      detalle, y la prueba lo compara en lugar de confiar
- [x] T-11 `get_advisors(security)`: 1 `ERROR` argumentado en `advisor-baseline.md`
- [x] T-12 `get_advisors(performance)` sin `WARN`
- [x] T-13 Migraciones espejadas, 1:1 con lo aplicado
- [x] T-14 Verificado por HTTP como `anon`: `wfts(spanish_unaccent)` funciona, el
      `tsvector` no viaja en la respuesta, y los filtros de categoría y ciudad también

## Front

- [x] T-15 `public-event.store.ts`: `listCatalog()` con filtros, orden y cursor keyset
- [x] T-16 `listFacets()`: las opciones de los filtros salen de lo publicado, no de
      una lista fija que se queda vieja
- [x] T-17 `demandBadge()`: la señal de la card, **siempre con texto**
- [x] T-18 `publico/catalogo.page.ts` en `FanLayout`, sin sesión
- [x] T-19 Destacado arriba, y solo sin filtros: con filtros, estorba
- [x] T-20 El «desde» con la leyenda «precio de la fase actual, puede variar por zona
      y fase». Que se lea como total es el riesgo nº 1 de esta pantalla
- [x] T-21 **Dos** estados vacíos, que dicen cosas opuestas: «ningún evento coincide
      con estos filtros» y «todavía no hay eventos publicados»
- [x] T-22 Seis gradientes por índice para las cards sin imagen
- [x] T-23 La raíz **es** el catálogo. Muere `home.page.ts`, que era provisional
- [x] T-24 `npm run build` limpio

## Cierre

- [x] T-25 002 marcado en `roadmap.md` y `README.md`
- [x] T-26 Defaults: **D-01** (relevancia = `featured_at` manual, sin algoritmo)

## La regla del advisor cambió aquí

Decía «cero `ERROR`». `v_event_public` es `security definer` a propósito: es lo que
permite que `anon` lea el catálogo **sin** tener acceso a `events`, `price_tiers`,
`price_phases`, `zones` ni `venues`. La alternativa —`security_invoker = true` más
políticas de `anon` en esas cinco tablas— le daría a `anon` acceso directo por
PostgREST con los filtros que quiera, y repartiría la regla de visibilidad en cinco
sitios. Más superficie y más difícil de auditar.

Así que la regla pasa a ser **«ningún hallazgo sin decisión escrita»**. Una regla que
obliga a elegir entre el linter y la seguridad real está mal escrita.

## Fuera de alcance, y por qué

- **Home de marca**: la raíz es el catálogo. Una home aparte, antes de tener eventos
  que mostrar, es una pantalla que se diseña dos veces.
- **Recomendaciones y señales sociales**: Fase 3. La card no pinta «3 amigos quieren
  ir», porque hoy mentiría.
- **Filtro de reventa**: Fase 2. Y no se pinta deshabilitado — un control que no hace
  nada es peor que su ausencia.
- **Juntar palabras separadas en la búsqueda**: «standup» no encuentra «Stand Up»
  (sí encuentra «Stand-Up»). Cubrirlo exigiría indexar el título entero concatenado.
  Si aparece en las búsquedas reales, la salida es `pg_trgm`, no más variantes.
