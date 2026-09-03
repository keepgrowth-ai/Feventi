# 003 — Plan

## Migraciones

| # | nombre | contenido |
|---|---|---|
| 0019 | `inventory_enums` | `btree_gist`; enums `zone_kind`, `phase_kind` |
| 0020 | `zones` | `zones`, `zone_segments`, RLS |
| 0021 | `price_phases` | tabla + restricción de exclusión contra solapamiento |
| 0022 | `price_tiers` | el precio, con sus invariantes |
| 0023 | `seats` | asientos de zona numerada |
| 0024 | `public_event_views` | la superficie que `anon` puede leer |

## Lo que se enforce en la base, y con qué

La regla: **una restricción declarativa antes que un trigger, y un trigger antes que
código de aplicación**. Un `check` no se puede desactivar ni olvidar; un trigger sí,
pero al menos vive junto al dato.

| invariante | AC | cómo |
|---|---|---|
| `reserved + sold <= stock` | AC-07 | `check` de fila. Es la misma fila, así que no hace falta nada más |
| `price_cents > 0` | AC-02 | `check` |
| un solo precio por cruce | AC-03 | `unique (zone_id, segment_id, phase_id)` con índice sobre `coalesce(segment_id, …)` |
| el segmento pertenece a la zona | AC-04 | **FK compuesta** `(zone_id, segment_id) → zone_segments (zone_id, id)` |
| una zona de pie no tiene segmentos ni asientos | AC-05 | **FK compuesta** contra `zones (id, kind)` con una columna fijada a `'seated'` |
| las fases no se solapan | AC-06 | `exclude using gist` sobre `tstzrange` |
| `sum(stock) <= zones.capacity` | AC-01 | trigger: cruza filas, no cabe en un `check` |
| `count(seats) <= zones.capacity` | AC-09 | trigger, por lo mismo |
| no bajar `stock` por debajo de `sold` | AC-18 | `check` de fila, gratis |
| no cambiar precio con ventas | AC-19 | trigger, y **depende de `tickets`** → va con 004, como el T-14 de 007 |

### La FK compuesta, dos veces

Es el truco que evita dos triggers. `check` no puede mirar otra tabla, así que la
pertenencia se declara con la clave:

```sql
-- 1) El segmento pertenece a SU zona (AC-04)
alter table public.zone_segments add constraint zone_segments_zone_id_id_key
  unique (zone_id, id);

alter table public.price_tiers add constraint price_tiers_segment_in_zone_fk
  foreign key (zone_id, segment_id) references public.zone_segments (zone_id, id);
```

Con `segment_id` nulo la FK compuesta **no se evalúa** (regla MATCH SIMPLE de SQL),
que es justo lo que queremos: una zona de pie manda `segment_id = null` y pasa.

```sql
-- 2) Solo una zona 'seated' puede tener segmentos (AC-05)
alter table public.zones add constraint zones_id_kind_key unique (id, kind);

create table public.zone_segments (
  ...
  zone_id   uuid not null,
  -- Redundante a propósito: la FK compuesta de abajo convierte "la zona tiene que
  -- ser numerada" en algo que el motor garantiza siempre, incluso en una carga
  -- masiva. Un trigger se puede desactivar; una FK, no.
  zone_kind public.zone_kind not null default 'seated' check (zone_kind = 'seated'),
  foreign key (zone_id, zone_kind) references public.zones (id, kind)
);
```

Lo mismo en `seats`. Cuesta una columna que solo puede valer una cosa, y a cambio
quita dos triggers y hace imposible el estado inválido.

### El solapamiento de fases

```sql
create extension if not exists btree_gist with schema extensions;

alter table public.price_phases add constraint price_phases_no_overlap
  exclude using gist (
    event_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  );
```

`btree_gist` hace falta para poder meter un `uuid` con `=` en un índice GiST. Sin
esta restricción, dos fases solapadas dejan el precio **indeterminado**: la consulta
devolvería dos filas para el mismo cruce y el «precio desde» dependería del orden del
plan de ejecución. Es el tipo de bug que aparece un viernes con el evento a la venta.

## Las vistas públicas: dos superficies, no una

`anon` no lee `events` (007, AC-18). Lo público sale de aquí, y estas vistas son
**la única cosa de todo el schema a la que `anon` tiene `select`**.

Las vistas se crean con `security_invoker = false` — corren con los privilegios de su
dueño y por eso **saltan la RLS de las tablas**. Eso las hace útiles y peligrosas a la
vez: su `where` es la única protección que queda, así que tiene que ser hermético.

Y van **dos**, no una, por el Art. de visibilidad:

- **`v_event_public`** — el catálogo. `status = 'published' and visibility = 'public'`.
  Se puede listar entera.
- **`get_public_event(slug)`** — el detalle. Acepta `published` y también `unlisted`,
  porque un evento no listado **sí** se abre por su enlace directo (002, AC-02).

Si `unlisted` estuviera en la vista, `anon` la consultaría sin filtro y enumeraría todo
lo no listado — que es exactamente lo que «no listado» promete evitar. Pedir el slug
es la diferencia entre «no aparece en el catálogo» y «no existe para ti».

## El dinero se calcula una vez, y el desglose se deriva

**AC-15** pide que el desglose sume exacto al total. La forma de garantizarlo no es
redondear con cuidado en dos sitios, es **calcular el total y restar**:

```sql
-- en la vista
price_cents                                                as base_cents,
case when e.service_charge_payer = 'fan'
     then round(t.price_cents * (1 + e.service_charge_bps / 10000.0))::int
     else t.price_cents
end                                                        as total_cents,
-- el cargo NO se redondea por su cuenta: es la diferencia
case when e.service_charge_payer = 'fan'
     then round(t.price_cents * (1 + e.service_charge_bps / 10000.0))::int - t.price_cents
     else 0
end                                                        as service_charge_cents
```

Así `base + cargo = total` es una identidad aritmética, no una coincidencia de
redondeo.

**Con una sola línea da igual, y conviene saberlo.** `round(x·1.06) − x` y
`round(x·0.06)` son idénticos para cualquier `x` entero: sumar un entero antes de
redondear no cambia el redondeo. Aquí, en 003, cada tier es una línea suelta, así que
las dos formas coinciden — y una prueba que "demuestre" lo contrario está mal escrita.

**Donde importa es en 004**, cuando la orden tiene varias entradas y el cargo se
calcula una vez sobre el subtotal en lugar de una vez por línea. Medido:

| precio | cantidad | subtotal | cargo por línea | cargo sobre subtotal | diferencia |
|---|---|---|---|---|---|
| S/ 9.25 | 7 | S/ 64.75 | 392 | 389 | **3 céntimos** |
| S/ 16.75 | 3 | S/ 50.25 | 303 | 302 | 1 céntimo |
| S/ 16.75 | 2 | S/ 33.50 | 202 | 201 | 1 céntimo |
| S/ 40.00 | 2 | S/ 80.00 | 480 | 480 | — |

Tres céntimos son un caso de soporte y una conciliación que no cierra. Por eso la
regla de 004 (**AC-18**) es: el cargo se redondea **una vez sobre el subtotal**, y las
líneas del desglose se derivan de ahí. Definir el cálculo en una sola función desde
003 es lo que hace que 004 no tenga dónde equivocarse.

El front no repite ninguna de estas cuentas: recibe los enteros y los formatea
(Art. 5, y `money.ts` ya está escrito así).

## La disponibilidad es derivada, siempre

`seats` **no** tiene columna de estado. La disponibilidad de un asiento sale de los
`order_items` vivos, y la de un tier de `stock - reserved - sold`. Una sola fuente de
verdad: un booleano `available` en `seats` se desincroniza la primera vez que una
reserva expira sin que nadie lo actualice.

`seats.blocked` es otra cosa: es una decisión operativa del organizador (cabina de
sonido, visibilidad mala, butaca rota), no un reflejo de la venta.

## Front

```
features/
  organizador/
    zonas.page.ts        zonas, segmentos, fases y precios de un evento
  publico/
    evento.page.ts       el detalle público, por slug
```

`zonas.page.ts` es la pantalla que desbloquea `publish_event`: hasta que exista un
`price_tier` con stock, 007 no deja publicar.

`evento.page.ts` va en `FanLayout` y es **la primera pantalla del proyecto que se ve
sin sesión**. Del mockup:

- total con cargo en grande, desglose debajo, en la misma card;
- stock en lenguaje humano: «800 disponibles», «Últimas 8», y sobre todo
  «Agotado en Preventa 1 — se libera stock en Preventa 2», que es la diferencia entre
  perder al fan y que vuelva;
- segmentos **anidados** dentro de la card de su zona, nunca como hermanos;
- línea de fases completa: la activa con lo que falta, las futuras con su fecha;
- el bloque «Ticket protegido» que explica el Art. 2 antes de que el fan compre.

## Verificación

`supabase/tests/003_detalle_evento.sql`. Los que de verdad importan:

- **AC-01/AC-09** el trigger de aforo, por arriba y por debajo del límite.
- **AC-04/AC-05** las dos FK compuestas: un segmento de otra zona y una zona de pie
  con segmento tienen que fallar **por constraint**, no por validación de aplicación.
- **AC-06** dos fases solapadas fallan.
- **AC-12/AC-13** `anon` ve el evento publicado y **no** ve el `draft`, ni las tablas
  de inventario en directo.
- **AC-15** el desglose suma exacto, probado con varios precios y bps — no solo con
  el 40.00 del mockup.

## Riesgos

| riesgo | mitigación |
|---|---|
| Las vistas saltan la RLS y su `where` es la única protección | `security_invoker = false` documentado en la migración; AC-12 lo prueba con un evento en cada estado |
| `unlisted` enumerable | detalle por función con slug, no por vista listable |
| AC-19 depende de `tickets` | va con 004, igual que el T-14 de 007 |
| El trigger de aforo se salta en carga masiva | es `after ... for each row`; para una carga grande, `set constraints` no lo desactiva, pero un `alter table disable trigger` sí. Anotado |
