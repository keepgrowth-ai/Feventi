# 004 — Checkout y emisión de tickets

**Mundo:** Fan · **Pantalla del mockup:** «Checkout» ·
**Depende de:** 001, 003, 007 · **Bloquea a:** 005, 006, 008

El feature más delicado del sistema: aquí se toca dinero, se compite por stock y se
crea la credencial. Todo lo demás es lectura comparada con esto.

---

## Objetivo

Que el fan pase de «quiero esta zona» a «tengo el ticket en la wallet» sin que el
sistema pueda quedar en un estado intermedio inconsistente: nunca dos personas con el
mismo asiento, nunca un ticket sin pago, nunca un pago sin ticket.

Cierra los artículos **2.1** (no hay ticket sin pago confirmado), **5** (el cargo se
muestra desde el primer paso) y **7.1–7.2** (DNI para nominación).

## No objetivos

- Grupo de compra: Fase 2 (Art. 11). El stepper no muestra el paso de grupo.
- Reventa como origen de compra: Fase 2.
- Cortesías como origen: Fase 2 (Art. 3).
- Saldo o wallet monetaria: **D-28**. El «Saldo S/ 180» del mockup es decorativo y **no
  se implementa**; el único medio de pago es tarjeta.
- Recuperar una compra expirada: **D-02**. La reserva vence, se libera y el fan
  reempieza.
- Pasarela real: Art. 13. `culqi_sandbox`.

## Los cinco pasos

`Zona · Asientos · Datos · Pago · Wallet`, fijos. Si un paso no aplica —una zona de pie
no elige asiento— se marca **hecho**, no se oculta: el fan no debe sentir que el flujo
cambió debajo de él.

## Máquina de estados de la orden

```
draft ──reserve──> reserved ──start_payment──> awaiting_payment ──ok──> paid
                      │                              │
                      │ vence                        └──falla──> failed ──retry──> awaiting_payment
                      v
                   expired                                        paid ──> refunded (Fase 2)
```

- `reserved` **retiene stock** y tiene `reserved_until`. Por defecto **15 minutos**.
- `expired` libera el stock. Lo hace un job, no la siguiente visita del fan: el stock
  tiene que volver a estar disponible aunque nadie entre a la página.
- `paid` es la **única** transición que emite tickets, y los emite en la misma
  transacción que la marca. No hay ventana entre «pagué» y «tengo entrada».
- `failed` conserva la reserva hasta `reserved_until`, para que un reintento con otra
  tarjeta no pierda los asientos.

## Historias

1. Elijo una zona y una cantidad, o elijo asientos concretos por fila y número
   (**D-09**: lista, no plano).
2. Desde el **primer paso** veo precio base, cargo de servicio, descuento y total. El
   cargo aparece siempre: con `S/ 0.00` y la leyenda «absorbido por el organizador» si
   lo paga el organizador (Art. 5).
3. Al reservar veo cuánto tiempo tengo, con cuenta atrás, y qué pasa si se vence.
4. Declaro mis datos. El DNI se guarda hasheado y solo veo los últimos 4 dígitos
   (Art. 7.1).
5. Nomino a los acompañantes. Si dejo una entrada sin nominar, la pantalla me advierte
   con el texto del mockup: «se generará alerta en puerta (modo flexible)». En modo
   `strict` no me deja pagar sin nominar todo.
6. Pago con tarjeta en sandbox. Mientras se procesa no puedo pagar dos veces.
7. Confirmado el pago, mis tickets aparecen en la wallet con su código.
8. Si el pago falla, veo por qué, mis asientos siguen retenidos y puedo reintentar.
9. Si se vence la reserva, veo que se venció y que los asientos volvieron a la venta.
10. Antes del pago confirmado, **ninguna** pantalla me dice que tengo entrada válida
    (Art. 2.1). El copy del botón es «Pagar y emitir tickets» y debajo «Tus tickets se
    emiten solo tras pago confirmado y viven en tu wallet».

## Criterios de aceptación

### Reserva

- **AC-01** `reserve_order` sobre un evento que no está `published` **falla**, en
  cualquier otro estado, incluido `paused` — AC-09 de 007.
- **AC-02** `reserve_order` fuera de la ventana de la fase activa **falla**.
- **AC-03** `reserve_order` incrementa `price_tiers.reserved` en la misma transacción
  que crea la orden. No existe orden `reserved` sin su contrapartida en `reserved`.
- **AC-04** `reserve_order` que dejaría `reserved + sold > stock` **falla** y no deja
  rastro parcial.
- **AC-05** **Concurrencia:** 50 sesiones reservando a la vez el último cupo de un tier
  con `stock = 1` producen **exactamente 1** éxito y 49 fallos limpios. Se garantiza con
  `select ... for update` sobre la fila del tier, no con una comprobación previa.
- **AC-06** **Asientos:** 20 sesiones reservando el mismo asiento producen exactamente 1
  éxito. Garantizado por índice único parcial sobre `order_items.seat_id` en órdenes
  vivas, no por una consulta de disponibilidad.
- **AC-07** Un asiento con `blocked = true` no se puede reservar.
- **AC-08** Reservar más de `events.max_per_user` entradas, contando las ya compradas y
  las reservas vivas del mismo usuario para ese evento, **falla** (Art. 11).
- **AC-09** El `unit_price_cents` de cada `order_item` y el
  `orders.service_charge_payer` se **congelan** al reservar. Un cambio de fase o de
  política durante el checkout no altera lo que el fan ya vio.
- **AC-10** `reserved_until = now() + interval '15 minutes'`.

### Expiración

- **AC-11** Un job de `pg_cron` cada minuto pasa a `expired` las órdenes `reserved` o
  `failed` con `reserved_until < now()` y decrementa `reserved`.
- **AC-12** Tras expirar, la disponibilidad del tier vuelve exactamente al valor previo
  a la reserva.
- **AC-13** El job es idempotente: correrlo dos veces no descuenta `reserved` dos veces.
- **AC-14** El job **nunca** toca una orden `paid`, aunque tenga `reserved_until` en el
  pasado.

### Dinero (Art. 5)

- **AC-15** `total_cents = subtotal_cents - discount_cents + service_charge_cents`,
  verificado por constraint en la tabla, no solo en la función.
- **AC-16** Con `service_charge_payer = 'organizer'`, `service_charge_cents = 0` y
  `total_cents = subtotal - discount`.
- **AC-17** Todo importe es `integer` en céntimos. No hay `numeric` ni `float` en el
  camino del dinero.
- **AC-18** El desglose que muestra la UI suma **exacto** al total: el redondeo del
  cargo se hace una vez sobre el subtotal, no por línea.

### Emisión (Art. 2.1)

- **AC-19** `confirm_payment` es la **única** vía de creación de `tickets`.
  `authenticated` no tiene `insert` sobre `tickets`.
- **AC-20** `confirm_payment` emite exactamente un ticket por `order_item`, en la misma
  transacción en que pone `orders.status = 'paid'`.
- **AC-21** **Idempotencia:** llamar `confirm_payment` dos veces con el mismo
  `provider_ref` emite los tickets **una** vez. Los webhooks de pasarela reintentan; si
  esto falla, se emiten tickets duplicados.
- **AC-22** `confirm_payment` mueve el cupo de `reserved` a `sold`; la suma
  `reserved + sold` no cambia en esa transición.
- **AC-23** Cada ticket recibe un `code` único con formato `FVT-<año>-<6 caracteres>`,
  de un alfabeto sin `0/O` ni `1/I/L`: alguien va a dictarlo por teléfono a soporte.
- **AC-24** Cada ticket recibe su fila en `ticket_secrets` con 32 bytes de
  `gen_random_bytes`, y esa tabla **no tiene ninguna política de RLS** (Art. 2.6).
- **AC-25** `qr_available_from = events.starts_at - events.qr_lead_days` (Art. 2.5).
- **AC-26** `face_value_cents = order_items.unit_price_cents`: es el techo de reventa
  del Art. 6.2.
- **AC-27** Cada emisión deja un `ticket_events` con `action = 'issued'`.
- **AC-28** Si la emisión falla a mitad, la transacción entera se revierte: no queda
  orden `paid` sin tickets ni tickets con orden `awaiting_payment`.
- **AC-29** `confirm_payment` solo la puede llamar `service_role`. Un fan que la invoca
  **falla**.

### Nominación (Art. 7)

- **AC-30** `set_own_dni` se exige antes de pagar: sin `dni_hash` en el perfil,
  `start_payment` **falla**.
- **AC-31** Con `nomination_mode = 'strict'`, `start_payment` con algún `order_item`
  sin `nominated_at` **falla**.
- **AC-32** Con `nomination_mode = 'flexible'`, se permite, y el ticket emitido queda
  con `holder_dni_hash` null, que es lo que hace que en puerta salga
  `manual_review` (006).
- **AC-33** El DNI del acompañante entra por RPC y se hashea en el servidor. El cliente
  **no** puede escribir `attendee_dni_hash` — AC-06 de 001.

### Aislamiento

- **AC-34** Un fan lee solo sus propias `orders`, `order_items` y `payments`.
- **AC-35** El organizador **no** lee `orders` ni `order_items` de su evento: solo
  agregados por vista (**D-06**, Art. 7.5).
- **AC-36** `anon` no lee nada de `orders`, `order_items`, `payments` ni `tickets`.
- **AC-37** Un fan no puede `update` ni `delete` una orden `paid`.

## Riesgos de confusión

- **«Reservado» se lee como «comprado».** El paso muestra la cuenta atrás y dice
  literalmente que la entrada aún no está emitida (Art. 2.1). No aparece la palabra
  «entrada» en singular posesiva hasta `paid`.
- **El cargo aparece al final y se siente como trampa.** Va desde el primer paso,
  siempre visible, incluso en cero (Art. 5).
- **«Sin nominar» se lee como «da igual».** El copy dice la consecuencia concreta —
  alerta en puerta— no una advertencia genérica.
- **El fan cree que puede pagar dos veces por si acaso.** `awaiting_payment` bloquea el
  botón y la orden; el reintento solo se habilita tras `failed`.

## Verificación obligatoria

Este feature no se cierra sin **AC-05**, **AC-06**, **AC-13** y **AC-21** corriendo como
test de concurrencia real, con sesiones paralelas. Son los cuatro que, si fallan, se
descubren la noche del evento con gente en la puerta.
