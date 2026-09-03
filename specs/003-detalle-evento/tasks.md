# 003 — Tasks

**Cerrado, salvo T-15.** 56 comprobaciones en verde. Advisors: seguridad sin
`ERROR`, rendimiento sin `WARN`. Verificado además por HTTP como `anon`, contra
los números exactos del mockup.

T-15 queda pendiente **por dependencia**: el guard que impide cambiar el precio
de un tier con ventas consulta `tickets`, que crea 004. Se aplica ahí, junto al
T-14 de 007.

## Base de datos

- [x] T-01 `0019_inventory_enums`: `btree_gist`; enums `zone_kind`, `phase_kind`
- [x] T-02 `0020_zones`: `zones` con `unique (id, kind)` y `check (numbered = (kind = 'seated'))`
- [x] T-03 `0020_zones`: `zone_segments` con FK compuesta contra `zones (id, kind)` — AC-05
- [x] T-04 `0020_zones`: RLS de las dos tablas, una política por operación — AC-16, AC-17
- [x] T-05 `0021_price_phases`: tabla + `exclude using gist` contra solapamiento — AC-06
- [x] T-05b `0021_price_phases`: `active_phase_id()` — la fase activa se calcula, no se guarda
- [x] T-06 `0022_price_tiers`: tabla con `check (reserved + sold <= stock)` — AC-07, AC-18
- [x] T-07 `0022_price_tiers`: `unique` del cruce con `coalesce(segment_id, …)` — AC-03
- [x] T-08 `0022_price_tiers`: FK compuesta `(zone_id, segment_id)` — AC-04
- [x] T-09 `0022_price_tiers`: trigger de aforo por zona **y fase** — AC-01
- [x] T-09b `0022_price_tiers`: `revoke update (reserved, sold)` — los mueve 004
- [x] T-10 `0023_seats`: tabla, FK compuesta, trigger de aforo — AC-05, AC-08, AC-09
- [x] T-11 `0023_seats`: `generate_seats(zona, filas[], por_fila, segmento)` — D-09
- [x] T-12 `0024_public_event_surface`: `private.total_with_charge()`, el cálculo del dinero en un solo sitio — AC-15
- [x] T-13 `0024_public_event_surface`: `v_event_public`, listable por `anon` — AC-01, AC-07, AC-08
- [x] T-14 `0024_public_event_surface`: `get_public_event(slug)` y `v_event_availability` — AC-02, AC-03, AC-10, AC-12
- [ ] T-15 Guard de AC-19: no cambiar `price_cents` de un tier con ventas. **Depende de `tickets`, que crea 004**

### No estaba en el plan, salió de las pruebas

- [x] T-14b `0025`: conceder `execute` de `total_with_charge` a `anon`. Con
      `security_invoker = false` los privilegios de las **tablas** se comprueban
      contra el dueño de la vista, pero el `EXECUTE` de una **función** se
      comprueba contra quien consulta — la vista reventaba para `anon`
- [x] T-14c `0026`: índice en `price_tiers (phase_id)`. `get_public_event` cuenta
      entradas por fase y `(event_id, phase_id)` no sirve sin filtrar por evento

## Verificación

- [x] T-16 `supabase/tests/003_detalle_evento.sql`, un caso permitido y uno denegado por AC
- [x] T-17 56/56 en verde
- [x] T-18 `get_advisors(security)` sin `ERROR`
- [x] T-19 `get_advisors(performance)` sin `WARN`
- [x] T-20 Migraciones espejadas en `supabase/migrations/`, 1:1 con lo aplicado
- [x] T-21 `npm run gen:types` — tablas, vistas y enums de 003
- [x] T-22 Extremo a extremo por HTTP como `anon`: catálogo y detalle. Los números
      salen idénticos al mockup — General S/ 42.40, Platea 180/150/120 con 3/12/45
      disponibles, VIP agotado — y `base + cargo = total` en los cinco tiers
- [x] T-23 `supabase/seed/demo_kpop.sql`: el evento del mockup, para ver la pantalla real

## Front

- [x] T-24 `eventos/inventory.store.ts`: zonas, segmentos, fases, precios y asientos
- [x] T-25 `publico/public-event.store.ts`: la superficie pública tipada, con `stockLabel()`
- [x] T-26 `publico/evento.page.ts`: el detalle, en `FanLayout`, sin sesión
- [x] T-27 Total **con cargo** en grande y desglose debajo, en la misma card — Art. 5
- [x] T-28 Segmentos **anidados** dentro de la card de su zona, nunca como hermanos
- [x] T-29 Stock en lenguaje humano, incluido «Agotado en Preventa 1 — se libera stock en Preventa 2»
- [x] T-30 Línea de fases completa: la activa con lo que falta, las futuras con su fecha
- [x] T-31 Bloque «Ticket protegido» con el Art. 2, antes de comprar
- [x] T-32 Sin imagen, la card cae en uno de los seis gradientes y sigue legible
- [x] T-33 `organizador/zonas.page.ts`: zonas, segmentos, fases, precios y generación de asientos
- [x] T-34 Rutas: `/eventos/:slug` público y `/organizador/eventos/:id/zonas`
- [x] T-35 `npm run build` limpio

## Cierre

- [x] T-36 003 marcado en `roadmap.md` y `README.md`
- [x] T-37 Defaults en los que se apoya: **D-09** (sin plano gráfico, filas y números
      en lista), **D-01** (`featured_at` manual)

## Lo que 003 le deja hecho a los siguientes

- **002** consume `v_event_public` tal cual: el catálogo ya trae «precio desde» con
  cargo, señal de disponibilidad y cuándo abre la siguiente fase.
- **004** hereda `price_tiers` con la invariante `reserved + sold <= stock` puesta
  como `check`, y `private.total_with_charge()` para no redondear el cargo en dos
  sitios. Su **AC-18** —redondear una vez sobre el subtotal— es la razón de que la
  función exista.
- **007** ya podía llamar a `publish_event`, que exige un `price_tier` con stock:
  esa comprobación estaba escrita con `to_regclass` esperando esta migración, y
  ahora está activa.
