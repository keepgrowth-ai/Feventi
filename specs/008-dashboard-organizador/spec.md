# 008 — Dashboard del organizador

**Mundo:** Organizador · **Pantalla del mockup:** «Dashboard del evento» ·
**Depende de:** 001, 003, 004, 007 · **Bloquea a:** nada

---

## Objetivo

Que el organizador sepa **qué requiere acción** y qué es solo informativo, y que
entienda su dinero sin confundir venta bruta con dinero disponible.

Cierra el artículo **5** en su parte de operación y el **7.5** (solo agregados).

## No objetivos

- Datos individuales de asistentes: **D-06**, se deniega por defecto. Ni nombres, ni
  correos, ni DNIs, ni el listado de quién compró qué.
- Exportaciones: **D-07**. Se ve en pantalla, no se descarga.
- Liquidación con movimientos reales: Fase 2. Aquí se muestra el **neto estimado** y la
  política de tramos declarada en `events.payout_policy`, etiquetada como estimación.
- Promotores, cortesías y reventa como módulos: Fase 2. El dashboard muestra el
  contador de cortesías reclamadas solo cuando el módulo exista.
- Multi-evento: Fase 2. Este dashboard es **de un evento**, como el mockup.

## Bloques de la pantalla

1. **Cabecera** — evento, organizador, estado y fecha. Si el estado no es `published`,
   dice qué falta para publicar.
2. **Métricas** — entradas vendidas / aforo · venta bruta · **neto estimado** ·
   cortesías reclamadas. Cada una con su denominador o su comparación: un número sin
   denominador no se muestra.
3. **Ventas por fase** — barra por fase con importe y cantidad de entradas.
4. **Resumen financiero** — venta bruta → comisión Feventi (6 %) → devoluciones →
   **neto estimado a liquidar**, con la política de tramos debajo.
5. **Accesos** — validados, revisión manual, denegados, % de aforo, en vivo durante el
   evento.
6. **Alertas** — lo que requiere acción: solicitudes con info pendiente, incidencias
   abiertas, fases que cierran hoy, zonas agotadas.

## Historias

1. Abro mi evento y en cinco segundos sé cuántas entradas vendí, cuánto facturé y
   cuánto me queda estimado.
2. Veo mis ventas repartidas por fase y entiendo qué fase funcionó.
3. Leo el resumen financiero y **no puedo confundir** el bruto con lo que voy a recibir:
   cada línea está etiquetada y el total dice «neto **estimado** a liquidar».
4. Veo la política de liquidación (30/40/30) con el disparador de cada tramo, marcada
   como estimación, no como pago programado.
5. Durante el evento veo los accesos en vivo y detecto si una puerta está atascada.
6. Veo mis alertas y sé qué tengo que hacer hoy.
7. **No** veo datos personales de mis compradores, y la pantalla explica por qué
   (Art. 7.5).

## Criterios de aceptación

### Aislamiento (Art. 7.5, D-06)

- **AC-01** El organizador A no lee ni una fila de ningún evento, venta, ticket o
  check-in del organizador B.
- **AC-02** El organizador **no** lee `orders`, `order_items`, `payments`, `tickets` ni
  `profiles` de terceros. Nada individual, ni por PostgREST ni por RPC.
- **AC-03** Todo lo que el dashboard muestra sale de vistas agregadas:
  `v_event_sales`, `v_event_phase_sales`, `v_gate_stats`.
- **AC-04** Las vistas se declaran `security_invoker = true`, para que la RLS del
  organizador se aplique dentro de la vista y no la esquive.
- **AC-05** Ninguna vista del dashboard expone una columna con nombre, email, teléfono,
  `dni_hash` ni `dni_last4`.
- **AC-06** Una vista que agrupe por una dimensión con **menos de 5 filas** no expone el
  grupo: se agrega en «otros». Sin esto, «1 entrada vendida en la fila A» identifica a
  una persona.
- **AC-07** Un miembro `viewer` lee el dashboard; un miembro con `revoked_at` no lo lee.

### Dinero (Art. 5)

- **AC-08** `v_event_sales` devuelve, en columnas separadas y nombradas:
  `gross_cents`, `feventi_commission_cents`, `refunds_cents`, `net_estimated_cents`.
- **AC-09** `net_estimated_cents = gross - commission - refunds`, verificado con datos
  de prueba.
- **AC-10** La comisión sale de `events.service_charge_bps`, no de una constante en el
  código ni en el front.
- **AC-11** El bruto cuenta **solo** órdenes `paid`. Ni `reserved`, ni
  `awaiting_payment`.
- **AC-12** Las cortesías no suman al bruto, y se cuentan aparte.
- **AC-13** La etiqueta de la UI dice literalmente «neto **estimado**». La palabra
  «disponible» no aparece en esta pantalla.
- **AC-14** Los tramos se muestran con el rótulo «estimado» y su disparador. No llevan
  fecha de pago concreta hasta que exista Fase 2.
- **AC-15** Todo importe se formatea desde céntimos enteros, con dos decimales y `S/ `.
  El front no hace aritmética de dinero: recibe los céntimos y solo formatea.

### Métricas

- **AC-16** «Entradas vendidas» cuenta `tickets` con estado distinto de `void` y
  `refunded`, y va **siempre** con su denominador de aforo.
- **AC-17** `v_gate_stats` cuenta por `result` desde `checkins`, no de un contador
  incremental.
- **AC-18** El «% de aforo ocupado» es `allowed / capacity`, y se marca como ocupación
  de acceso, no de venta: son dos cosas distintas y confundirlas es un error caro.
- **AC-19** El dashboard de un evento sin ventas muestra ceros con su denominador, no
  espacios vacíos ni un esqueleto de carga permanente.
- **AC-20** Las vistas responden en menos de 300 ms con 50 000 tickets y 60 000
  check-ins, con índices sobre `(event_id, status)` y `(event_id, result)`.

## Riesgos de confusión

- **«Neto estimado» leído como «mi plata».** Es el riesgo principal (Art. 5). Etiqueta
  explícita, la palabra «disponible» prohibida en esta pantalla, y los tramos marcados
  como estimación.
- **«% de aforo» confundido con % vendido.** Son dos métricas: vendido sobre aforo, y
  validado sobre aforo. Van rotuladas distinto y en bloques distintos.
- **El organizador espera ver a sus compradores.** No los va a ver, y la pantalla lo
  dice en una línea con su razón (Art. 7.5), en vez de dejar un hueco que parezca un
  bug y termine en un caso de soporte.
- **La comisión parece un cargo nuevo.** Es la del Art. 5, la misma que el fan vio o que
  el organizador absorbió. La línea lo aclara según `service_charge_payer`.
