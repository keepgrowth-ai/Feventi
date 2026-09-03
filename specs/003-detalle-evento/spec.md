# 003 — Detalle de evento: zonas, segmentos, fases y precios

**Mundo:** Público (lectura) + Organizador (configuración) ·
**Pantalla del mockup:** «Evento» · **Depende de:** 001, 007 · **Bloquea a:** 002, 004, 008

La pantalla pública más importante para conversión. Se construye antes del catálogo
porque el catálogo es una **proyección** de esta: el «precio desde» del catálogo sale de
los `price_tiers` que se definen aquí.

---

## Objetivo

Que el organizador declare qué vende y a cuánto, en tres ejes —**zona** (dónde),
**segmento** (qué filas) y **fase** (cuándo)— y que el visitante lo entienda sin
sorpresas de precio.

Cierra el artículo **5** en su parte visible al fan (el cargo se muestra desde el primer
paso) y el **11** en «el precio de catálogo es *desde*».

## No objetivos

- Plano gráfico del venue: **D-09**, selección por fila y número desde una lista.
- Promociones y códigos de descuento más allá de mostrar el descuento bancario del
  mockup como dato del evento.
- Reventa: Fase 2. El detalle muestra el bloque solo si `resale_enabled`, y por ahora
  dice «próximamente».
- Álbum, señales sociales reales y «armar grupo»: Fase 3. El botón no se pinta.

## Modelo de precio

El precio vive en el cruce de los tres ejes, en `price_tiers`:

```
zona            segmento        fase             price_cents   stock
General de pie  —               Preventa 1        4000          800
Platea          Filas A–C       Preventa 1       18000            3
Platea          Filas D–H       Preventa 1       15000           12
Platea          Filas I–M       Preventa 1       12000           45
VIP             —               Preventa 2       30000          100
```

- **Zona sin numerar** (`kind = 'standing'`): sin segmentos, sin asientos, se compra por
  cantidad.
- **Zona numerada** (`kind = 'seated'`): puede tener segmentos con precio distinto por
  bloque de filas, y se compra eligiendo asiento.
- **Fase activa**: `now() between starts_at and ends_at`. Se **calcula**, no se guarda,
  porque un estado guardado se desincroniza en cuanto nadie mira.

Si dos fases se solapan en el tiempo para la misma zona, el precio es indeterminado. Se
prohíbe en la base (**AC-06**), no en la UI.

## Historias

### Visitante

1. Abro el evento y veo key visual, nombre, fecha y hora, venue, organizador y
   descripción.
2. Veo las reglas del evento: límite por usuario, si hay reventa oficial, y las
   condiciones.
3. Veo las zonas con su precio **total** ya incluido el cargo si lo paga el fan, y el
   desglose debajo («Base S/ 40.00 + cargo 6%»). Si lo absorbe el organizador, dice
   «cargo absorbido».
4. Veo el stock por zona en lenguaje humano: «800 disponibles», «Últimas 8», «Agotado en
   Preventa 1 — se libera stock en Preventa 2».
5. En una zona numerada con segmentos veo el desglose por bloque de filas con su precio
   y su disponibilidad.
6. Veo la **línea de fases** completa: la activa con lo que falta para que cierre, las
   futuras con la fecha en que abren, las pasadas apagadas.
7. Veo el bloque «Ticket protegido» que explica el Art. 2: QR dinámico en wallet
   autenticada, no se descarga; reventa oficial dentro de Feventi; titularidad
   controlada.
8. Un evento agotado no me deja comprar y me dice qué pasa después (**D-01**/**D-02** no
   lo resuelven todavía: sin lista de espera, se dice cuándo abre la siguiente fase si
   existe).

### Organizador

9. En `setup` creo zonas indicando nombre, tipo, aforo y si va numerada.
10. En una zona numerada genero asientos por rango de filas y cantidad por fila, y
    opcionalmente segmentos de precio por bloque de filas.
11. Creo fases con nombre, tipo y ventana de fechas.
12. Fijo el precio y el stock en el cruce zona/segmento × fase.
13. Bloqueo asientos por razón operativa (cabina, cortesías, visibilidad) sin borrarlos.
14. Con venta abierta no puedo cambiar precio ni stock hacia abajo por debajo de lo ya
    vendido (**D-08**).

## Criterios de aceptación

### Integridad del inventario

- **AC-01** `sum(price_tiers.stock)` por zona no puede superar `zones.capacity`;
  intentarlo falla.
- **AC-02** `price_tiers.price_cents > 0`. Un precio cero es una cortesía y va por su
  propio camino (Fase 2), no por un tier a 0.
- **AC-03** `unique (zone_id, segment_id, phase_id)`, tratando `segment_id` null como un
  valor: no puede haber dos precios para el mismo cruce.
- **AC-04** Un `segment_id` que no pertenece a `zone_id` falla por constraint, no por
  validación de aplicación.
- **AC-05** Una zona `standing` con segmentos o con asientos falla.
- **AC-06** Dos fases del mismo evento con ventanas solapadas fallan (constraint de
  exclusión sobre `tstzrange`).
- **AC-07** `reserved + sold <= stock` siempre. Bajar `stock` por debajo de
  `reserved + sold` falla.
- **AC-08** `seats` es único por `(zone_id, row_label, seat_number)`.
- **AC-09** La cantidad de `seats` de una zona numerada no puede superar su `capacity`.

### Lectura pública

- **AC-10** `v_event_availability` devuelve, por tier, `stock - reserved - sold`, y
  nunca un negativo.
- **AC-11** El detalle público de un evento `published` es legible por `anon`.
- **AC-12** El detalle de un evento `draft`, `pending_review`, `approved`, `setup` o
  `paused` devuelve **0 filas** a `anon`.
- **AC-13** `anon` no lee `zones`, `price_tiers`, `seats` ni `price_phases` en directo:
  solo a través de las vistas públicas.
- **AC-14** El precio que muestra la vista es el de la **fase activa**. Sin fase activa,
  el evento se marca «venta no abierta» y no muestra precio comprable.
- **AC-15** Con el cargo a cargo del fan, el total de la vista es
  `round(price_cents * (1 + service_charge_bps/10000))`, y el desglose suma exacto al
  total: sin diferencias de redondeo de un céntimo.

### Configuración

- **AC-16** Solo un miembro no revocado del organizador dueño escribe `zones`,
  `zone_segments`, `price_phases`, `price_tiers` y `seats`.
- **AC-17** El organizador A no ve ni escribe el inventario del organizador B.
- **AC-18** Con tickets emitidos, bajar `price_tiers.stock` por debajo de `sold` falla.
- **AC-19** Con tickets emitidos, cambiar `price_cents` de un tier con ventas **falla**
  para el organizador y queda solo para Admin, con asiento (**D-08**, AC-16 de 007).
- **AC-20** `delete` de una `zone` con tickets emitidos falla; se despublica, no se borra.

## Riesgos de confusión

- **El «desde» se lee como precio final.** Se corta mostrando el **total con cargo** en
  grande y el desglose debajo, en la misma card, desde el primer paso (Art. 5).
- **«Agotado» se lee como «agotado para siempre».** Si hay una fase futura con stock, el
  copy dice «Agotado en Preventa 1 — se libera stock en Preventa 2», que es lo que dice
  el mockup y es la diferencia entre perder al fan y que vuelva.
- **Los segmentos se confunden con zonas.** Van anidados dentro de la card de la zona,
  con el título «Platea — segmentos internos de precio», nunca como hermanos.
- **La fase se confunde con un descuento.** Es un precio por ventana de tiempo, no una
  promoción: el copy dice cuándo termina, no «ahorra X».
