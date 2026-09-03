# 004 — Tasks

**Backend cerrado.** 50 comprobaciones en verde, más las cuatro de concurrencia
con peticiones HTTP simultáneas de verdad. Rendimiento sin `WARN`.

Cierra además los dos guards que 007 y 003 dejaron abiertos por dependencia.

## Base de datos

- [x] T-01 `0029_order_enums`: `order_status`, `payment_status`, `ticket_status`, `ticket_event_action`
- [x] T-02 `0030_orders`: `orders` con el `check` que obliga a que el total cuadre — AC-15
- [x] T-03 `0030_orders`: `order_items`, **una fila por entrada, sin `qty`**
- [x] T-04 `0030_orders`: `unique (seat_id)` — el índice que decide la carrera por un asiento — AC-06
- [x] T-05 `0030_orders`: RLS; el cliente no escribe nada, todo por RPC — AC-34, AC-35, AC-37
- [x] T-06 `0031_payments`: tabla + `unique (provider, provider_ref)`, la clave de idempotencia — AC-21
- [x] T-07 `0032_tickets`: `tickets` con `face_value_cents` y `qr_available_from` — AC-25, AC-26
- [x] T-08 `0032_tickets`: `ticket_secrets`, RLS activa y **cero políticas** — AC-24 · Art. 2.6
- [x] T-09 `0032_tickets`: `ticket_events` append-only — AC-27 · Art. 8
- [x] T-10 `0032_tickets`: `new_ticket_code()` sin `0/O` ni `1/I/L` — AC-23
- [x] T-11 `0033_reserve_order`: la reserva, con `for update` en orden de id — AC-01 … AC-10
- [x] T-12 `0033`: límite por usuario contando emitidas **y** reservas vivas — AC-08
- [x] T-13 `0033`: precio y política **congelados** al reservar — AC-09
- [x] T-14 `0033`: el cargo redondeado **una vez sobre el subtotal** — AC-18
- [x] T-15 `0034`: `set_item_attendee`, el DNI se hashea en el servidor — AC-33
- [x] T-16 `0034`: `start_payment` exige DNI propio y, en `strict`, nominación — AC-30, AC-31
- [x] T-17 `0034`: `fail_payment` conserva la reserva para reintentar
- [x] T-18 `0034`: `confirm_payment` idempotente, solo `service_role` — AC-19 … AC-22, AC-28, AC-29
- [x] T-19 `0034`: emisión y secreto en la **misma transacción** que el `paid` — AC-28
- [x] T-20 `0035`: `expire_orders()` idempotente, que no toca `paid` — AC-11 … AC-14
- [x] T-21 `0035`: `pg_cron` cada minuto
- [x] T-22 `0036`: guard de **007/T-14** — con tickets, los campos sensibles los cambia Feventi
- [x] T-23 `0036`: guard de **003/T-15** — con ventas no se cambia el precio, ni se baja el stock, ni se borra la zona

### Lo que salió de las pruebas

- [x] T-23b `0037`: traducir el error del índice único del asiento. El perdedor
      de la carrera recibía `duplicate key value violates unique constraint`, y
      eso no se le muestra a un fan. Ahora dice **«alguien acaba de tomar uno de
      esos asientos: elige otro»**
- [x] T-23c `0038`: índice en `tickets (zone_id)` — lo usan el dashboard de 008 y
      el guard de 003/AC-20
- [x] T-23d `0039`: **`reserve_order` no era reentrante.** Creaba una tabla
      temporal `on commit drop`, así que llamarla dos veces en la misma
      transacción reventaba con `relation "_items" already exists`. Por PostgREST
      cada RPC es su propia transacción, así que en producción no se habría visto
      — hasta el día en que otra función la llamara dos veces. Sustituida por una
      función que devuelve conjunto

## Verificación

- [x] T-24 `supabase/tests/004_checkout_emision.sql`
- [x] T-25 50/50 en verde
- [x] T-26 **AC-05** · 50 peticiones HTTP simultáneas por un tier con `stock = 1`
      → **1 éxito, 49 rechazos**, todos con el mismo mensaje limpio. Ningún
      deadlock: el lock va en orden de id. Y ni una orden huérfana — `reserved`
      quedó en 1/1 exacto
- [x] T-27 **AC-06** · 20 peticiones simultáneas por el mismo asiento
      → **1 éxito, 19 rechazos** con el mensaje legible
- [x] T-28 **AC-13** · `expire_orders()` dos veces → la segunda devuelve 0 y
      `reserved` no se descuenta dos veces
- [x] T-29 **AC-21** · `confirm_payment` con el mismo `provider_ref` dos veces
      → 7 tickets, no 14
- [x] T-30 `get_advisors(performance)` sin `WARN`
- [x] T-31 Migraciones espejadas, 1:1 con lo aplicado
- [ ] T-32 `npm run gen:types` y las pantallas de checkout

## Front — pendiente

- [ ] T-33 `checkout.store.ts`: reservar, nominar, pagar
- [ ] T-34 `checkout.page.ts` con el stepper de cinco pasos fijos
- [ ] T-35 El desglose desde el **primer** paso, con el cargo visible aunque sea cero
- [ ] T-36 Cuenta atrás de la reserva, y qué pasa si vence
- [ ] T-37 Nominación, con la advertencia literal del mockup en modo flexible
- [ ] T-38 El copy del Art. 2.1: «tus tickets se emiten solo tras pago confirmado»
- [ ] T-39 Selector de asiento por fila y número (**D-09**: sin plano gráfico)
- [ ] T-40 Edge Function del webhook de pago, que es quien llama a `confirm_payment`
- [ ] T-41 `npm run build` limpio

## Notas

**La pasarela no está conectada** (Art. 13). `confirm_payment` existe y es
idempotente, pero la llama `service_role`: hasta que haya una Edge Function con
el webhook de Culqi, el pago se confirma a mano. Y el paso a producción es una
decisión de negocio con documento firmado, no un despliegue.

**El rate limit de correos se liberó** durante esta sesión, así que las cuatro
pruebas de concurrencia se hicieron por HTTP contra PostgREST — el camino real
del cliente, no solo el motor. En plan free son 2 correos/hora: si hay que
repetirlas, conviene desactivar la confirmación de correo en
Authentication → Sign In / Providers → Email.
