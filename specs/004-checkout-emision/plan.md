# 004 — Plan

El único feature donde se toca dinero, se compite por stock y se crea la
credencial. Todo lo demás del proyecto es lectura comparado con esto.

## Migraciones

| # | nombre | contenido |
|---|---|---|
| 0029 | `order_enums` | `order_status`, `payment_status`, `ticket_status`, `ticket_event_action` |
| 0030 | `orders` | `orders`, `order_items` con el índice que impide dos personas en un asiento |
| 0031 | `payments` | `payments`, con la clave de idempotencia |
| 0032 | `tickets` | `tickets`, `ticket_secrets` (RLS sin políticas), `ticket_events` |
| 0033 | `reserve_order` | la reserva: la función crítica |
| 0034 | `nominate_and_pay` | `set_item_attendee`, `start_payment`, `confirm_payment` |
| 0035 | `expire_orders` | el job de expiración y su `pg_cron` |
| 0036 | `deferred_guards` | los guards de 007/T-14 y 003/T-15, que esperaban `tickets` |

## Una fila por entrada, sin columna `qty`

`order_items` no tiene cantidad. Comprar tres entradas de General son **tres
filas** con el mismo `price_tier_id`.

Cuesta filas y ahorra todo lo demás: cada entrada necesita su asiento, su
nominación y su ticket. Con `qty` habría que partir la fila en el momento de
nominar o de emitir, y ese reparto —qué asiento va con qué nombre— es
precisamente donde se cuelan los bugs. Una fila desde el principio hace que
`order_item → ticket` sea uno a uno y que la emisión no tenga nada que decidir.

## El asiento: un índice, no una comprobación

**AC-06** pide que 20 sesiones peleando por el mismo asiento produzcan
exactamente un éxito. La forma de conseguirlo **no** es consultar
disponibilidad antes de insertar: entre la consulta y el insert caben las otras
19.

```sql
create unique index order_items_seat_unique
  on public.order_items (seat_id) where seat_id is not null;
```

Sin condición de estado, y eso es deliberado. Un índice parcial no puede mirar
`orders.status`, así que la alternativa habitual es denormalizar el estado en
`order_items` con un trigger que lo mantenga. Aquí no hace falta: **al expirar,
la orden borra sus `order_items`**, y con eso el asiento queda libre sin que
ninguna condición tenga que saber de estados.

Lo que **no** se borra es la orden: su fila queda con sus totales y su
`status = 'expired'`, para que la conciliación y el soporte vean qué pasó. Se
borran los ítems, que sin la orden viva no valen nada.

`failed` **sí** conserva sus ítems hasta `reserved_until`: un reintento con otra
tarjeta no debe perder los asientos.

## La reserva, paso a paso

Es la función que decide quién se queda con el último cupo.

```sql
reserve_order(p_event_id uuid, p_items jsonb) returns uuid
-- p_items: [{"tier_id": "...", "seat_id": "..." | null}, ...]  una entrada por elemento
```

Dentro, en una transacción:

1. **Evento `published`.** Ningún otro estado vende, ni `paused` (007/AC-20).
2. **Fase activa** para cada tier. Fuera de ventana no se reserva.
3. **Límite por usuario**: entradas ya emitidas + reservas vivas de este usuario
   para este evento, contra `events.max_per_user`.
4. **Bloquear los tiers con `for update`, en orden ascendente de id.** El orden
   no es un detalle: dos sesiones que pidan los mismos dos tiers en orden
   distinto se abrazan en un deadlock. Ordenar el lock siempre igual lo hace
   imposible.
5. **Disponibilidad** por tier: `stock - reserved - sold >= cuántas se piden`.
6. **Asientos**: que no estén `blocked`, y que pertenezcan a la zona y al
   segmento del tier. Lo segundo ya lo garantiza la FK compuesta de 003, así que
   aquí solo se comprueba el bloqueo.
7. **Crear la orden y sus ítems.** El `unique` del asiento es lo que rechaza al
   perdedor de la carrera, con un error de constraint y no con una consulta.
8. **Subir `reserved`** en la misma transacción. No existe orden `reserved` sin
   su contrapartida en el tier.
9. **Calcular el dinero.**

El cliente **no** tiene `insert` en `orders` ni en `order_items`: solo esta
función. Una política puede decir «sí o no»; no puede decir «sí, y además sube
el contador del tier y congela el precio».

## El dinero: redondear una vez, y sobre el subtotal

**AC-18.** Es la lección de 003, y aquí es donde muerde:

```
subtotal   = sum(unit_price_cents)          -- precio base, congelado al reservar
descuento  = 0                              -- fuera de alcance en Fase 1
cargo      = total_con_cargo(subtotal) - subtotal
total      = subtotal - descuento + cargo
```

El cargo se calcula **una vez sobre el subtotal**, no por línea. Con 7 entradas
de S/ 9.25 al 6 %, por línea sale 392 y sobre el subtotal 389: **tres céntimos**
que no cierran en la conciliación. La función `private.total_with_charge()` ya
existe de 003 justo para que aquí no haya dónde equivocarse.

`unit_price_cents` y `service_charge_payer` se **congelan al reservar**
(**AC-09**): un cambio de fase o de política a mitad del checkout no puede
alterar lo que el fan ya vio.

Y un `check` en la tabla, para que el total no pueda mentir ni por error de
programación:

```sql
constraint orders_total_is_consistent
  check (total_cents = subtotal_cents - discount_cents + service_charge_cents)
```

## La emisión: idempotente o duplica tickets

Los webhooks de pasarela **reintentan**. Si `confirm_payment` no es idempotente,
un reintento emite el ticket dos veces — y eso se descubre en la puerta.

La clave es el índice:

```sql
create unique index payments_provider_ref_unique
  on public.payments (provider, provider_ref) where provider_ref is not null;
```

Y la función:

1. `select ... for update` sobre la orden.
2. Si ya existe un `payment` con ese `provider` + `provider_ref` **y** la orden
   está `paid` → **no hace nada** y devuelve. No es un error: es un reintento.
3. Si no: crea el `payment`, pone la orden en `paid`, emite un ticket por
   `order_item`, y mueve el cupo de `reserved` a `sold`.

Todo en la **misma transacción**. **AC-28**: no puede quedar una orden `paid` sin
tickets ni tickets con la orden en `awaiting_payment`.

`confirm_payment` es solo para `service_role` — la llama el webhook, no el
cliente. Un fan que la invoque tiene que fallar (**AC-29**).

## El código del ticket

`FVT-2026-A3B7K9`. Seis caracteres de un alfabeto **sin `0/O` ni `1/I/L`**,
porque alguien va a dictarlo por teléfono a soporte a las once de la noche.

Aleatorio con reintento sobre el `unique`, no secuencial. Un código secuencial
se puede enumerar, y aunque el código **no** es la credencial (Art. 2: eso es el
QR), sí permite sondear soporte. Con 30⁶ ≈ 729 millones de combinaciones y unos
miles de tickets, la colisión es tan rara que tres intentos sobran.

## Expiración: un job, no la siguiente visita

**AC-11.** La reserva vence a los **15 minutos**, y el stock tiene que volver a
estar disponible **aunque nadie entre a la página**. Liberar «cuando alguien
consulta» significa que el último cupo de un evento agotado no vuelve nunca.

`pg_cron` cada minuto:

```sql
select cron.schedule('feventi-expire-orders', '* * * * *',
                     $$select public.expire_orders()$$);
```

`expire_orders()` es **idempotente** (**AC-13**): baja `reserved` solo por las
órdenes que está pasando a `expired` en esa misma pasada, con la orden bloqueada.
Correrlo dos veces no descuenta dos veces.

Y **nunca** toca una orden `paid`, aunque su `reserved_until` esté en el pasado
(**AC-14**). Una orden pagada no tiene reserva que liberar: tiene tickets.

## Nominación y DNI

El DNI del acompañante entra por RPC y se hashea en el servidor con el pepper de
001 (**AC-33**). El cliente **no** puede escribir `attendee_dni_hash`: si
pudiera, copiaría el de otra persona.

`start_payment` exige (**AC-30**, **AC-31**):

- que el comprador tenga su propio DNI declarado;
- si el evento es `nomination_mode = 'strict'`, que **todos** los ítems estén
  nominados.

En `flexible` se permite pagar sin nominar, y el ticket sale con
`holder_dni_hash` nulo — que es exactamente lo que hace que en puerta salga
`manual_review` (006/AC-16).

## Los guards que esperaban a `tickets`

Dos features dejaron una tarea abierta por dependencia, y ahora se puede cerrar:

- **007/T-14** — con entradas emitidas, el organizador no cambia fecha, lugar,
  aforo ni reglas comerciales (**D-08**).
- **003/T-15** — con ventas, no se cambia el precio de un tier (003/AC-19).

Van en `0036`, después de que `tickets` exista.

## Verificación: cuatro pruebas que no son opcionales

Este feature no se cierra sin estas cuatro **en paralelo de verdad**, porque si
fallan se descubren la noche del evento con gente en la puerta:

| AC | qué |
|---|---|
| **AC-05** | 50 sesiones por el último cupo de un tier con `stock = 1` → **1** éxito, 49 fallos limpios |
| **AC-06** | 20 sesiones por el mismo asiento → **1** éxito |
| **AC-13** | `expire_orders()` dos veces seguidas no descuenta `reserved` dos veces |
| **AC-21** | `confirm_payment` con el mismo `provider_ref` dos veces emite los tickets **una** vez |

El arnés: dos o más llamadas a `execute_sql` en el mismo mensaje, cada una en su
conexión. Es el método que ya contuvo la carrera de 007 con dos Admins.

> `ponytail:` con confirmación de correo activa y el rate limit del plan free
> (2/hora) no se pueden crear 50 sesiones HTTP reales, así que la concurrencia se
> prueba con conexiones SQL paralelas. Es el mismo motor y el mismo lock; lo que
> no cubre es la capa de PostgREST. Cuando se pueda desactivar la confirmación,
> conviene repetir **AC-05** por HTTP.

## Fuera de alcance, y por qué

- **Grupo de compra** (Art. 11) — Fase 2. El stepper no muestra ese paso.
- **Reventa y cortesía como origen** — Fase 2.
- **Saldo o wallet monetaria** — **D-28**. El «Saldo S/ 180» del mockup es
  decorativo y no se implementa. El único medio de pago es tarjeta.
- **Recuperar una compra expirada** — **D-02**. Vence, se libera, se reempieza.
- **Reembolsos** — el enum tiene `refunded`, pero nada lo produce todavía.
- **Pasarela real** — Art. 13. `culqi_sandbox`, y el paso a producción es una
  decisión de negocio con documento firmado, no un despliegue.
