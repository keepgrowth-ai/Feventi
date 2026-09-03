# 002 — Plan

Es el feature más corto de Fase 1, y a propósito: **el catálogo es una proyección
de 003**, no una entidad nueva. Todo el precio, la disponibilidad y la visibilidad
ya están resueltos en `v_event_public`. Aquí solo se añade lo que un listado
necesita y un detalle no: **buscar, filtrar, ordenar y paginar**.

## Migraciones

| # | nombre | contenido |
|---|---|---|
| 0027 | `event_search` | `events.search_text tsvector` mantenido por trigger, índice GIN, y expuesto en `v_event_public` |

Una sola. Si hiciera falta más, sería señal de que 003 dejó algo sin cerrar.

## La búsqueda: un `tsvector` indexado, no un `ilike`

**AC-15** lo pide explícito, y la razón es medible: `ilike '%kpop%'` sobre 10 000
eventos es un recorrido secuencial de la tabla entera con una comparación de
cadenas por fila. Un GIN sobre `tsvector` es una búsqueda de índice.

El problema es **qué** indexar. El spec pide encontrar por título, venue y
categoría, y el venue vive en otra tabla. Tres caminos:

1. **Columna generada** sobre las columnas propias del evento. Indexable y sin
   trigger, pero no alcanza el nombre del venue: una expresión generada solo puede
   leer su propia fila.
2. **`to_tsvector(...)` dentro de la vista**, sobre el join. Alcanza el venue pero
   **no se puede indexar**: a 10 000 eventos vuelve a ser un recorrido completo, y
   **AC-13** pide menos de 200 ms.
3. **Denormalizar el texto del venue** en `events` y mantenerlo con un trigger.
   Indexable y completo.

Se elige la 3. Cuesta dos triggers pequeños, y son dos porque el texto se
desactualiza por dos caminos distintos:

```sql
alter table public.events add column search_text tsvector;

create or replace function private.events_refresh_search(p_event_id uuid)
returns void language sql security definer set search_path = '' as $$
  update public.events e
     set search_text =
           setweight(to_tsvector('spanish', coalesce(e.title, '')),       'A') ||
           setweight(to_tsvector('spanish', coalesce(e.category, '')),    'B') ||
           setweight(to_tsvector('spanish', coalesce(v.name, '')),        'B') ||
           setweight(to_tsvector('spanish', coalesce(v.city, '')),        'B') ||
           setweight(to_tsvector('spanish', coalesce(e.description, '')), 'D')
    from public.venues v
   where e.id = p_event_id and (v.id = e.venue_id or e.venue_id is null);
$$;
```

Los pesos no son decorativos: `A` al título y `D` a la descripción hace que buscar
«festival» ponga primero un evento que se llama así, y no uno que lo menciona de
pasada en su texto largo.

- **Trigger en `events`** — al cambiar `title`, `description`, `category` o
  `venue_id`.
- **Trigger en `venues`** — al renombrar un venue, se refresca el texto de sus
  eventos. Un venue se renombra casi nunca, pero cuando pasa, el catálogo dejaría
  de encontrarlos por su nombre viejo *y* por el nuevo.

> `ponytail:` el trigger de `venues` recorre los eventos de ese venue. Con un venue
> de 50 eventos es irrelevante. Si alguna vez hay uno con miles, se pasa a una cola.

La columna se expone en `v_event_public` para que PostgREST pueda filtrar con
`?search_text=fts(spanish).kpop`. **Se filtra, no se selecciona**: un `tsvector`
en cada fila de la respuesta son kilobytes de ruido.

## Paginación por cursor, no por `offset`

**AC-14.** `offset 10000` obliga a Postgres a leer y descartar 10 000 filas. Un
cursor sobre `(starts_at, id)` va directo a su sitio por índice.

El par importa: `starts_at` no es único —dos eventos pueden empezar a la misma
hora— así que el cursor lleva los dos campos y la condición es un keyset de verdad:

```
starts_at > :cursor_at
  or (starts_at = :cursor_at and id > :cursor_id)
```

Con PostgREST eso es un `.or(...)`. Ordenar solo por `starts_at` y paginar con
`.gt()` parece más simple y **salta eventos** en cuanto hay un empate.

## Qué NO se añade

- **Home de marca.** La raíz es el catálogo con el destacado arriba. Una home
  aparte antes de tener eventos que mostrar es una pantalla que se diseña dos veces.
- **Recomendaciones y señales sociales.** Fase 3. La card no pinta «3 amigos
  quieren ir», porque hoy mentiría.
- **Relevancia algorítmica.** **D-01**: destacado es `featured_at`, que pone Admin
  a mano. «Ordenar por relevancia» = destacados primero, después por fecha.
- **Filtro de reventa.** Fase 2. No se pinta deshabilitado: un control que no hace
  nada es peor que su ausencia.

## Front

```
features/publico/
  catalogo.page.ts     el listado, con filtros y cursor
```

`public-event.store.ts` ya existe de 003 con `listCatalog()`; se le añaden los
parámetros de filtro y el cursor.

Del mockup y del spec:

- **precio «desde» con el cargo ya incluido**, y la leyenda de que hay fases y
  condiciones. Que el «desde» se lea como precio final es el riesgo número uno de
  esta pantalla;
- **badge de demanda con texto**, nunca solo color;
- **seis gradientes por índice** para las cards sin imagen;
- **dos estados vacíos distintos**: «ningún evento coincide con estos filtros —
  limpiar filtros» y «todavía no hay eventos publicados». Confundirlos deja al
  visitante creyendo que Feventi está vacío.

## Verificación

`supabase/tests/002_catalogo_publico.sql`:

- **AC-15** la búsqueda encuentra por título, categoría y **nombre del venue**, y
  el plan usa el índice GIN — se comprueba con `explain`, no de oído.
- **AC-12** el «precio desde» de la card coincide con el mínimo del detalle: las
  dos cifras salen de la misma vista, y la prueba lo verifica en lugar de confiar.
- **AC-14** el cursor no salta ni repite con `starts_at` empatado.
- Los del venue renombrado: el evento se sigue encontrando por el nombre nuevo.
