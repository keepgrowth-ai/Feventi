# 007 — Solicitud de evento y aprobación

**Mundo:** Organizador + Admin · **Pantalla del mockup:** «Admin: solicitudes y soporte»
(bloque de solicitudes + checklist) · **Depende de:** 001 · **Bloquea a:** 002, 003, 008

Se construye **antes** del catálogo. Sin un evento aprobado y publicado no hay nada que
catalogar, y sembrar datos de prueba salteándose la aprobación instala exactamente el
hábito que el Art. 4 prohíbe.

---

## Objetivo

Que un evento recorra `draft → pending_review → approved → setup → published` sin que
nadie pueda acortar el camino, y que cada decisión deje evidencia.

Cierra el artículo **4** completo y el **8.1** para las decisiones de Admin.

## No objetivos

- Zonas, fases y precios: eso es 003. Aquí el evento llega a `setup` con la ficha, no
  con el inventario.
- Alta del organizador: es 001 (`create_organizer`).
- Notificaciones por email al organizador: **D-11**. El estado se ve entrando al panel.
- Reputación del organizador: **D-26**, la columna queda en null.

## Estados

```
draft ──submit──> pending_review ──approve──> approved ──setup_done──> published
  ^                   │    │                                             │
  │                   │    └──reject──> rejected                    pause │ cancel
  └──resubmit── changes_requested <──request_info──┘                      v
                                                                  paused / cancelled
                                                                          │
                                                                     finished
```

Reglas duras:

- `published` es **la única** condición que habilita venta. Se enforce en la función de
  reserva de 004, no en la UI.
- `pending_review` no vende nada (Art. 4.2).
- `paused` detiene la venta pero **los tickets ya emitidos siguen válidos** y su QR
  sigue funcionando en puerta.
- `cancelled` invalida los tickets; abre el proceso de reembolso, que es Fase 2.
- `finished` lo pone un job cuando pasa `starts_at`; no es una acción de nadie.

## Historias

### Organizador

1. Creo un evento y queda en `draft`, visible solo para mi organizador.
2. Completo la ficha: título, descripción, categoría, imagen, fecha, hora, venue,
   aforo y las reglas comerciales (límite por usuario, reventa sí/no, quién paga el
   cargo, días de anticipación del QR, modo de nominación).
3. Envío a revisión y el evento pasa a `pending_review`. **No se publica** (Art. 4.2) y
   yo dejo de poder editar los campos de la ficha.
4. Si Admin pide información, veo su observación textual y qué ítems del checklist
   faltan, puedo editar de nuevo y reenviar.
5. Aprobado, paso a `setup`, cargo zonas y precios (003) y **yo** decido publicar.
6. Con entradas ya vendidas, no puedo tocar zonas, precios, fecha, aforo ni venue
   (**D-08**). Sí descripción e imagen. Para el resto abro un caso de soporte.

### Admin

7. Veo la cola de solicitudes con código, evento, organizador, fecha y estado, y puedo
   filtrar por estado.
8. Abro una solicitud y trabajo un checklist de seis ítems: datos generales,
   organizador y RUC, venue y plano, fechas y funciones, zonas y fases de precio,
   cortesías y bolsas. Cada uno queda en `pending`, `ok` o `na`.
9. Apruebo, rechazo o pido información, siempre con una nota. Queda un
   `event_review_notes` con mi id, la hora, el estado antes y después y el checklist
   congelado en ese momento.
10. Puedo pausar o cancelar un evento publicado, y también deja asiento.
11. Veo el historial completo de decisiones de una solicitud, en orden.

## Criterios de aceptación

### Transiciones

- **AC-01** `create_event` deja el evento en `draft` aunque el payload traiga otro
  `status`.
- **AC-02** `create_event` genera un `code` correlativo `REQ-NNN`, único.
- **AC-03** `submit_event` exige que estén llenos título, descripción, categoría,
  `starts_at`, `venue_id` y `capacity`; si falta uno, falla con el nombre del campo.
- **AC-04** `submit_event` desde `draft` o `changes_requested` funciona; desde cualquier
  otro estado falla.
- **AC-05** Un organizador que intenta `update events set status = 'published'` **falla**:
  la columna no está en su `grant`.
- **AC-06** Solo Admin ejecuta `approve_event`, `reject_event`, `request_event_info`,
  `pause_event`, `cancel_event`. Un organizador que las llama **falla**.
- **AC-07** `publish_event` la ejecuta el **organizador**, solo desde `setup`, y solo si
  el evento tiene al menos una `zone` con un `price_tier` de stock > 0. Sin inventario
  no se publica.
- **AC-08** `approve_event` sobre un evento en `draft` **falla**: solo desde
  `pending_review`.
- **AC-09** Un evento en `pending_review` no admite `insert` en `orders` (lo comprueba
  004, se declara aquí).

### Evidencia (Art. 4.3)

- **AC-10** Cada una de las seis funciones de decisión escribe **exactamente un**
  `event_review_notes` con `actor_id`, `action`, `status_before`, `status_after` y
  `checklist_snapshot`.
- **AC-11** `event_review_notes` no admite `update` ni `delete` para ningún rol fuera de
  `service_role` — Art. 8.1.
- **AC-12** `request_event_info` sin nota **falla**: la observación es obligatoria.
- **AC-13** El organizador lee los `event_review_notes` de sus eventos, pero **no** los
  campos internos ni las notas de otros organizadores.

### Edición con venta abierta (D-08)

- **AC-14** Con al menos un ticket emitido, un `update` del organizador sobre
  `starts_at`, `venue_id`, `capacity`, `service_charge_bps` o `max_per_user` **falla**.
- **AC-15** En la misma situación, `update` de `description` y `hero_image_url`
  **funciona**.
- **AC-16** Admin sí puede cambiar los campos sensibles, y queda asiento en
  `event_review_notes` con `action = 'note'`.

### Aislamiento

- **AC-17** El organizador A no ve ni una fila de los eventos del organizador B, en
  ningún estado.
- **AC-18** Como `anon`, `select` sobre `events` devuelve **0 filas**. Lo público se lee
  por `v_event_public`, que solo expone `published` (002).
- **AC-19** Un evento `draft` o `pending_review` no aparece en `v_event_public`.
- **AC-20** Un evento `paused`: desaparece de `v_event_public`, y sus tickets siguen
  validando en puerta.

## Riesgos de confusión

- **«Enviar» se siente como «publicar».** El botón dice «Enviar a revisión» y la
  pantalla dice qué pasa después y cuánto suele tardar. Nunca «Publicar evento» en
  `draft`.
- **`approved` no es `published`.** Son dos cosas: Feventi autoriza, el organizador
  decide cuándo abre la venta. La UI las nombra distinto y muestra el paso que falta.
- **El checklist parece un formulario del organizador.** No lo es: es de Admin, y el
  organizador solo ve qué ítems están pendientes, no puede marcarlos.
- **`paused` se lee como «cancelado».** El copy tiene que decir «venta pausada — las
  entradas ya emitidas siguen siendo válidas», porque es la diferencia entre un fan
  tranquilo y un caso de soporte.
