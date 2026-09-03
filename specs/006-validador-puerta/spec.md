# 006 — Validador de puerta

**Mundo:** Staff · **Pantalla del mockup:** «Validador de puerta» ·
**Depende de:** 001, 004, 005 · **Bloquea a:** nada

La pantalla que se usa bajo presión, con una mano, con poca luz, con cola detrás. Es la
única del sistema donde un segundo de duda cuesta dinero real.

---

## Objetivo

Que el staff sepa en menos de un segundo si esta persona entra, y que cada decisión
quede registrada para siempre.

Cierra los artículos **8.1–8.2** (append-only, revocar sin borrar) y **10** (modo
Puerta).

## No objetivos

- Operación sin internet: **D-04**. No se soporta, y la pantalla lo dice en vez de
  fingir. Es la opción honesta hasta tener protocolo.
- Excepciones autorizadas desde la app: **D-05**. Van por soporte y las ejecuta Admin.
- Lector de DNI por hardware, NFC o biometría.
- Que el staff vea datos del evento más allá de su puerta y su turno.

## Los cuatro resultados

Exactamente los cuatro del mockup. No hay un quinto, y ninguno se puede confundir con
otro:

| resultado | cuándo | qué dice la pantalla |
|---|---|---|
| `allowed` | MAC válida, slot en ventana, ticket `active`, zona correcta, titular verificado | **ACCESO PERMITIDO** · zona, fila, código, «titular verificado con DNI» |
| `manual_review` | ticket válido pero sin nominar, o zona distinta a la puerta, o entrada por modo DNI | **REVISAR MANUALMENTE** · qué falta y qué pedir al asistente |
| `already_used` | ticket `used` | **YA UTILIZADO** · hora y puerta del primer ingreso, «escalar a supervisor» |
| `denied` | MAC inválida, slot viejo, ticket `void`/`listed`/`refunded`/`transferred`, evento cancelado | **ACCESO DENEGADO** · la causa **y la acción**: «solicita abrir la wallet en la app» |

`already_used` y `denied` comparten paleta pero **no** mensaje: el primero es un
diagnóstico para el supervisor, el segundo es una instrucción para el staff. El staff
necesita saber qué hacer, no qué pasó.

## Historias

1. Abro «Mis eventos» y veo **solo** los eventos donde estoy asignado, con puerta,
   fecha, horario y estado. La puerta y la fecha van grandes: operar el evento
   equivocado es el error más caro de la noche.
2. Abro el scanner y veo la cámara, el evento activo, mi puerta, el reloj y el estado de
   conexión.
3. Escaneo un QR y el veredicto tapa la pantalla, con color, icono y texto.
4. Con `ACCESO PERMITIDO` sigo escaneando sin tocar nada más: el veredicto se va solo a
   los 2 segundos.
5. Con cualquier otro resultado, el veredicto **espera** que yo lo cierre. No se va solo.
6. Uso el modo DNI cuando el fan no tiene batería o pantalla (**D-03**): busco por
   documento, veo qué entradas tiene y valido a mano. Queda como `manual_review`.
7. Veo el historial de mi turno: hora, resultado, puerta y referencia. **No puedo borrar
   nada** (Art. 8.1).
8. Reporto una incidencia desde el resultado que la disparó, y el caso ya sabe de qué
   ticket y qué escaneo hablo (009).
9. Veo el contador del turno: validados, revisión manual, denegados, % de aforo.
10. Si pierdo conexión, la pantalla me lo dice y **bloquea el escaneo**. No acumula
    lecturas para enviarlas luego: un ticket validado que resulta inválido es peor que
    una cola.

## Criterios de aceptación

### Autorización del staff

- **AC-01** `event_staff` con `revoked_at` null y turno vigente es la **única** vía de
  acceso al validador de un evento.
- **AC-02** Un staff asignado al evento A que valida un ticket del evento B recibe
  `denied` con `reason = 'wrong_event'`, y **queda registrado**.
- **AC-03** Fuera de su ventana de turno, `qr-validate` falla. El margen es de 2 h antes
  de `doors_at` y 4 h después de `starts_at`.
- **AC-04** Revocar a un miembro del staff le corta el acceso en la llamada siguiente y
  **no borra** ni uno de sus `checkins` — Art. 8.2.
- **AC-05** Un fan que llama `qr-validate` **falla**: no es staff del evento.
- **AC-06** El staff lee **solo** sus eventos asignados de `events`, y solo los campos
  que necesita: título, fecha, `doors_at`, venue y su puerta.
- **AC-07** El staff **no** lee `orders`, `payments`, `profiles` de terceros ni ningún
  importe.

### Validación

- **AC-08** MAC válida y slot dentro de ±1 sobre un ticket `active` → `allowed`, y el
  ticket pasa a `used` en la **misma transacción** que crea el `checkin`.
- **AC-09** **Doble escaneo simultáneo del mismo ticket:** dos llamadas en paralelo
  producen **un** `allowed` y **un** `already_used`. Garantizado con `select ... for
  update` sobre la fila del ticket. Es el caso real de dos puertas leyendo a la vez.
- **AC-10** Segundo escaneo posterior → `already_used`, con la hora y la puerta del
  primero tomadas de `checkins`.
- **AC-11** MAC válida con slot fuera de ±1 → `denied` con
  `reason = 'screenshot_suspected'` — Art. 2.3, y es la señal antifraude más valiosa de
  la noche.
- **AC-12** MAC inválida o token ilegible → `denied` con `reason = 'qr_unreadable'`.
- **AC-13** Ticket `listed`, `transferred`, `void` o `refunded` → `denied` con el motivo
  concreto — Art. 2.4.
- **AC-14** Evento `cancelled` → `denied` con `reason = 'event_cancelled'`.
- **AC-15** Evento `paused` → **`allowed`**. Pausar detiene la venta, no el acceso de
  quien ya compró — AC-20 de 007.
- **AC-16** Ticket sin `holder_dni_hash` y evento en modo `flexible` → `manual_review`
  con `reason = 'not_nominated'`.
- **AC-17** Lo mismo en modo `strict` → `denied` con `reason = 'not_nominated'`.
- **AC-18** Ticket de una zona que no corresponde a la puerta del staff →
  `manual_review` con `reason = 'wrong_zone'`. Nunca `denied`: puede ser un error de
  señalización del venue, y el staff está mejor situado que el sistema para resolverlo.
- **AC-19** Modo DNI: el staff busca por DNI, el servidor compara contra `hash_dni` del
  documento tecleado, y el resultado es siempre `manual_review` con
  `reason = 'dni_mode'` (**D-03**).
- **AC-20** `qr-validate` **nunca** devuelve el DNI ni el hash. Devuelve `dni_last4` y
  el nombre del titular, que es lo que el staff necesita cotejar.

### Bitácora (Art. 8)

- **AC-21** **Todo** escaneo deja un `checkin`, incluidos los `denied` y los ilegibles.
  Un QR inválido es información, no ruido.
- **AC-22** `checkins` no admite `update` ni `delete` para `authenticated`, en ningún
  rol. Ni staff, ni organizador, ni Admin. Solo `service_role`.
- **AC-23** El staff lee **solo** los `checkins` de su propio turno y su propia puerta.
- **AC-24** Cada `checkin` guarda `scanned_code` con el token crudo, para peritaje
  posterior.
- **AC-25** Cada `allowed` deja además un `ticket_events` con `action = 'used'`.
- **AC-26** El contador del turno sale de `v_gate_stats`, agregando `checkins`; no de un
  contador incremental que se pueda desincronizar.

### Modo Puerta (Art. 10)

- **AC-27** El veredicto ocupa el ancho completo, con el texto a 34 px o más.
- **AC-28** Cada resultado lleva **color, icono y texto**. Nunca solo color.
- **AC-29** El botón de escanear mide al menos 56 px de alto.
- **AC-30** Ningún texto de esta pantalla baja de 16 px.
- **AC-31** Sin conexión, el botón de escanear se deshabilita y aparece el aviso. No hay
  cola de lecturas pendientes (**D-04**).
- **AC-32** El veredicto `allowed` se cierra solo a los 2 s; los otros tres requieren
  toque explícito.
- **AC-33** La pantalla funciona en vertical, a 390 px, con una sola mano: los controles
  van en la mitad inferior.

## Riesgos de confusión

- **Operar el evento o la puerta equivocada.** El header repite evento, fecha y puerta
  siempre visibles, y cambiar de evento exige volver a «Mis eventos».
- **`YA UTILIZADO` se lee como fraude.** Casi nunca lo es: suele ser un doble escaneo o
  un grupo que compartió una pantalla. El mensaje da la hora y la puerta del primer
  ingreso y dice «escalar a supervisor», no «entrada falsa».
- **`REVISAR MANUALMENTE` se lee como «no entra».** Es lo contrario: entra, con una
  comprobación. El copy dice qué pedir.
- **El staff cree que puede corregir un error borrando.** No puede (Art. 8.1). La
  corrección es un caso de soporte, y la pantalla lo ofrece ahí mismo.
