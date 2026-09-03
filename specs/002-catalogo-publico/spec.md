# 002 — Catálogo público

**Mundo:** Público · **Pantalla del mockup:** «Catálogo» ·
**Depende de:** 001, 007, 003 · **Bloquea a:** nada

---

## Objetivo

Convertir a alguien que no conoce el evento en alguien que abre el detalle. Es una
**proyección de solo lectura** de 003: aquí no se define nada, solo se muestra y se
filtra.

## No objetivos

- Home de marca: Fase 2. La raíz del sitio es el catálogo con el evento destacado
  arriba.
- Personalización, recomendaciones y señales sociales reales: Fase 3. En Fase 1 la card
  no pinta el bloque «3 amigos quieren ir».
- Búsqueda semántica o por similitud. Búsqueda por texto en título, venue y categoría.
- Mercado de reventa: Fase 2. El filtro existe en el diseño pero se pinta deshabilitado
  con «próximamente», o no se pinta.

## Historias

1. Entro sin cuenta y veo el evento destacado con su key visual, nombre, venue, fecha,
   estado de venta y precio desde.
2. Veo la lista de eventos publicados con card: imagen, badge de demanda, título,
   venue · ciudad, fecha, «desde S/ X» y la fase activa.
3. Filtro por fecha (rango), categoría, ciudad y precio.
4. Ordeno por fecha, por precio y por relevancia (**D-01**: relevancia = curaduría
   manual, sin algoritmo).
5. Busco por texto y encuentro por título, venue o categoría.
6. Veo señales de disponibilidad: «Disponible», «Pocas entradas», «Últimas VIP · 8
   lugares», «Alta demanda», «Agotado».
7. Abro un evento y llego al detalle (003).
8. Comparto un evento por enlace y el enlace trae vista previa correcta.
9. Un evento sin imagen sigue siendo legible: cae en uno de los seis gradientes por
   índice del design system.

## Criterios de aceptación

### Visibilidad

- **AC-01** `v_event_public` solo devuelve eventos con `status = 'published'` **y**
  `visibility = 'public'`.
- **AC-02** Un evento `unlisted` no sale en el catálogo pero **sí** se abre por su slug
  directo.
- **AC-03** Un evento `private` no sale ni se abre por slug para `anon`.
- **AC-04** Un evento `paused` o `cancelled` desaparece del catálogo en la consulta
  siguiente, sin caché intermedia que lo mantenga vivo.
- **AC-05** Un evento cuyo `starts_at` ya pasó no aparece en el listado por defecto.
- **AC-06** `anon` lee `v_event_public` y **no** lee `events` directamente — AC-18 de 007.
- **AC-07** La vista no expone `events.review_checklist`, `payout_policy`,
  `created_by` ni ningún campo de operación interna.

### Precio y disponibilidad

- **AC-08** El «precio desde» es el `price_cents` **mínimo** entre los tiers de la fase
  activa con `stock - reserved - sold > 0`.
- **AC-09** Con el cargo a cargo del fan, el «desde» ya lo incluye, y la card lleva la
  leyenda de que hay fases y condiciones (Art. 11).
- **AC-10** Sin fase activa, la card muestra la fase que abre y **no** un precio
  comprable.
- **AC-11** Sin ningún tier con disponibilidad, la card muestra «Agotado» y no ofrece
  comprar.
- **AC-12** El «precio desde» de la card coincide con el precio mínimo del detalle:
  ambos salen de la misma vista, no de dos consultas parecidas.

### Rendimiento

- **AC-13** El catálogo con 10 000 eventos publicados responde en menos de 200 ms en el
  percentil 95, con índice sobre `(status, visibility, starts_at)`.
- **AC-14** La lista pagina por cursor sobre `(starts_at, id)`, no por `offset`.
- **AC-15** La búsqueda de texto usa un índice GIN sobre un `tsvector` en español; no
  hace `ilike '%...%'` sobre la tabla completa.

### Presentación

- **AC-16** Una card sin `hero_image_url` recibe el gradiente `índice % 6` del design
  system y sigue siendo legible.
- **AC-17** La card es legible a 390 px de ancho sin scroll horizontal.
- **AC-18** El badge de demanda usa el trío semántico correcto y **siempre** lleva
  texto, nunca solo color.

## Riesgos de confusión

- **El «desde» se lee como total.** Ya declarado en 003; aquí la card lo repite con la
  leyenda de fases y cargos.
- **Se cree que el catálogo está vacío porque no hay eventos.** Vacío por filtro y vacío
  de verdad son dos estados con dos mensajes: «Ningún evento coincide con estos filtros
  — limpiar filtros» y «Todavía no hay eventos publicados».
- **Reventa y venta primaria mezcladas** (Art. 6.1). En Fase 1 no hay reventa en el
  catálogo, y cuando la haya va en su propia superficie, no intercalada entre las cards.
