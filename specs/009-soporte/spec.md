# 009 — Soporte contextual

**Mundo:** Fan + Staff + Organizador (apertura) · Admin (resolución) ·
**Pantalla del mockup:** «Admin: solicitudes y soporte» (bloque de casos) ·
**Depende de:** 001, 004, 005, 006 · **Bloquea a:** nada

Último de Fase 1 porque necesita que existan las cosas de las que la gente se queja.

---

## Objetivo

Que nadie tenga que explicar su problema desde cero. Un caso nace **desde el objeto
afectado** —un ticket, una orden, un escaneo— y llega a Admin con ese contexto ya
adjunto.

## No objetivos

- Reembolsos y cancelaciones ejecutadas: Fase 2 y **D-40…D-42**. Aquí el caso se
  **registra y se clasifica**; el dinero no se mueve.
- Chat en vivo, teléfono, WhatsApp o base de conocimiento.
- SLA prometido al usuario: **D-45**. No se muestra un tiempo de respuesta que no se
  pueda cumplir.
- Excepciones de puerta ejecutadas por el staff: **D-05**. Se piden aquí, las ejecuta
  Admin.

## Tipos de caso

`support_kind` los separa de entrada, porque tratarlos igual es lo que produce el error
del Art. 5 más caro:

`payment` · `ticket` · `qr` · `resale` · `courtesy` · `group` · `refund` ·
`cancellation` · `ownership` · `other`

**Regla firme de la guía:** `refund` (el fan pide a Feventi), `cancellation` (el evento
no ocurre) y una disputa bancaria son tres procesos distintos, y **no se abren dos vías
de recuperación por el mismo pago** (**D-12**). La base lo impide: un `order_id` no
puede tener dos casos abiertos de recuperación a la vez.

## Historias

### Quien abre

1. Como fan, desde una entrada de mi wallet abro un caso y el caso ya trae el ticket, el
   evento y la orden. No tecleo ningún código.
2. Elijo el tipo de problema en lenguaje humano, no jerga de sistema.
3. Veo mis casos y su estado, y respondo cuando me piden información.
4. Como staff, desde un resultado del validador abro una incidencia y el caso trae el
   ticket, el escaneo y mi puerta.
5. Como organizador abro un caso sobre mi evento: solicitud observada, problema de
   ventas, staff, liquidación, o emergencia durante el evento.

### Admin

6. Veo la cola de casos abiertos con código, tipo, prioridad y contexto, y filtro por
   tipo, prioridad y estado.
7. Abro un caso y veo **todo** el contexto sin salir: el ticket con su historial de
   `ticket_events`, la orden con su pago, los `checkins` de ese ticket.
8. Respondo al usuario, o dejo una nota interna que él no ve.
9. Asigno el caso, cambio prioridad, escalo y lo resuelvo.
10. Sobre un ticket puedo anular, corregir titularidad o autorizar una excepción, y cada
    acción deja `ticket_events` (Art. 8.3).

## Criterios de aceptación

### Contexto obligatorio

- **AC-01** Un caso de tipo `ticket`, `qr` u `ownership` sin `ticket_id` **falla**.
- **AC-02** Un caso de tipo `payment` o `refund` sin `order_id` **falla**.
- **AC-03** Al abrir un caso con `ticket_id`, el `event_id` y el `order_id` se rellenan
  **en el servidor** desde el ticket. El cliente no los manda: podría mandar los de otro.
- **AC-04** `open_support_case` verifica que quien abre tiene relación con el objeto: es
  el `owner_id` del ticket, el `buyer_id` de la orden, staff del evento o miembro del
  organizador. Si no, **falla**.
- **AC-05** Un fan que abre un caso sobre un ticket ajeno **falla**, y el error no
  revela si el ticket existe.

### No duplicar vías de recuperación (D-12)

- **AC-06** Con un caso `refund` abierto para un `order_id`, abrir un `cancellation` o
  otro `refund` sobre el mismo pedido **falla** con un mensaje que apunta al caso
  existente. Índice único parcial, no validación de aplicación.
- **AC-07** Cerrado el primero, se puede abrir otro.
- **AC-08** Un caso `refund` **no** mueve dinero en Fase 1: no hay ninguna escritura en
  `payments` desde este feature.

### Visibilidad

- **AC-09** El fan lee sus casos: los que abrió, o los que apuntan a un ticket del que
  es `owner_id`.
- **AC-10** El fan **no** lee los `support_messages` con `internal = true`.
- **AC-11** El organizador lee los casos de sus eventos, **sin** los datos personales
  de quien los abrió (**D-06**) y sin las notas internas.
- **AC-12** El staff lee **solo** los casos que él abrió.
- **AC-13** Admin lee todo.
- **AC-14** `anon` no lee ni un caso.
- **AC-15** Solo Admin escribe `assigned_to`, `priority` y `status`. Un fan que lo
  intenta **falla**.
- **AC-16** Solo Admin escribe `support_messages` con `internal = true`.

### Auditoría (Art. 8)

- **AC-17** `support_messages` no admite `update` ni `delete` para `authenticated`. Lo
  que se escribió, se escribió.
- **AC-18** Cerrar un caso sella `resolved_at` y no borra ni un mensaje.
- **AC-19** Toda acción de Admin sobre un ticket desde un caso (anular, corregir
  titularidad, autorizar excepción) deja un `ticket_events` con `actor_id`, el
  `case_id` en `meta` y, si corrige un asiento previo, su `corrects_id` — Art. 8.3.
- **AC-20** Un `code` de caso legible y único (`#1042`), en monoespaciada en la UI: se
  dicta por teléfono.

### Presentación

- **AC-21** El botón de soporte está presente en la wallet, en cada ticket, en el
  checkout, en el resultado del validador y en el dashboard del organizador. Nunca
  obliga a buscar un menú.
- **AC-22** El formulario llega con el contexto **ya cargado y visible**: el fan ve de
  qué entrada está hablando antes de escribir.
- **AC-23** La cola de Admin muestra prioridad con el trío semántico y **texto**.
- **AC-24** No se muestra ningún tiempo de respuesta estimado (**D-45**).

## Riesgos de confusión

- **«Reembolso», «reclamo» y «disputa» usados como sinónimos.** Es el riesgo central
  (**D-12**). Se separan al abrir, con una frase que explica cada uno, y la base impide
  la doble vía.
- **El fan cree que abrir un caso cancela su compra.** El copy dice que la compra sigue
  como está mientras se revisa.
- **La nota interna se filtra.** Es un `boolean` en la fila, así que se protege con RLS
  y se verifica con **AC-10**, no confiando en que el front no la pinte.
- **El staff cree que un caso resuelve la puerta ahora.** No: la excepción la ejecuta
  Admin (**D-05**). La pantalla lo dice para que el staff no deje esperando a alguien en
  la cola.
