# 005 — Wallet y QR dinámico

**Mundo:** Fan · **Pantalla del mockup:** «Wallet · QR» ·
**Depende de:** 001, 004 · **Bloquea a:** 006

La wallet es el centro de control del fan y el QR es el puente con la puerta. Es la
implementación del artículo **2** completo.

---

## Objetivo

Que el fan vea todas sus entradas, entienda el estado de cada una y pueda mostrar en
puerta una credencial que **no funcione fuera de su sesión autenticada**.

## No objetivos

- Transferir o regalar: Fase 2.
- Publicar en reventa: Fase 2. El estado `listed` existe en el enum y la wallet lo sabe
  mostrar, pero nada lo produce todavía.
- Donar entradas: no está confirmado, no se implementa.
- Álbum del evento pasado: Fase 3.
- Saldo o créditos: **D-28**.
- Wallet offline o pass de Apple/Google: contradice el Art. 2.3. No se hace.

## El QR

### Cómo se construye

TOTP con HMAC-SHA256, ventana de **30 segundos**.

```
slot   = floor(unix_seconds / 30)
mac    = hmac_sha256(secret_del_ticket, ticket_id || ':' || slot)
token  = base64url( ticket_id | slot | mac[0..15] )
```

- `secret` son 32 bytes aleatorios en `ticket_secrets`, tabla **sin ninguna política de
  RLS** (Art. 2.6). Solo la alcanza `service_role` desde una Edge Function.
- El truncado a 16 bytes deja 128 bits de MAC: de sobra, y mantiene el QR pequeño, que
  es lo que hace que se lea rápido con poca luz.
- El `slot` viaja en claro dentro del token. No es un secreto y permite al validador
  distinguir **«MAC inválida»** de **«MAC válida pero vieja»**, que son dos incidentes
  distintos con dos mensajes distintos.

### Quién puede pedirlo

La Edge Function `qr-token` lo emite solo si, todo a la vez:

1. hay sesión autenticada y `tickets.owner_id = uid`;
2. `tickets.status = 'active'`;
3. `now() >= tickets.qr_available_from`;
4. el evento no está `cancelled`.

Si falla cualquiera, devuelve el motivo, y la wallet lo muestra con su razón. No un
error genérico: el fan tiene que saber si es cuestión de esperar o de escribir a
soporte.

### Qué protege de verdad

Rotar cada 30 s hace **incómodo** compartir un pantallazo, pero no imposible: dentro de
la ventana, la imagen sirve. La protección real es doble:

1. **Un ticket entra una vez.** El primer escaneo lo marca `used`; el segundo dice «YA
   UTILIZADO» con la hora y la puerta del primero. Quien comparte su QR está regalando
   su propia entrada, no duplicándola.
2. **Un token de un slot viejo es una acusación.** Si la MAC es válida pero el slot está
   fuera de ±1, el token estuvo **almacenado**: solo puede venir de una captura. El
   validador responde «probable captura de pantalla» y lo registra con
   `reason = 'screenshot_suspected'`.

> `ponytail:` la ventana de replay es de 30 s por diseño. Cerrarla del todo exige un
> desafío del scanner al servidor por escaneo (QR con nonce del validador), lo que
> obliga al scanner a estar online por lectura y contradice **D-04**. Si el fraude
> medido lo justifica, ahí está el camino: nonce por escaneo, no ventana más corta.

## Historias

1. Abro la wallet y veo mi próxima entrada arriba, con el QR grande si está en ventana.
2. Veo la cuenta atrás y la barra de progreso del QR («se actualiza en 24 s») y entiendo
   que el código es vivo.
3. Debajo del QR leo siempre por qué: «Muestra este QR en puerta. Las capturas no
   funcionan.»
4. Veo mi código de ticket en monoespaciada, para poder dictarlo a soporte.
5. Veo mis otras entradas con su estado: «QR activo», «QR desde el 1 de julio», «QR
   inhabilitado».
6. Una entrada fuera de ventana me dice **desde cuándo** estará disponible el QR y por
   qué («14 días antes del evento»).
7. Veo mis entradas pasadas, separadas, con «Usada» y la hora de ingreso.
8. Desde cualquier entrada abro un caso de soporte y el caso ya sabe de qué ticket
   hablo (009).
9. Sin conexión, la wallet me dice que necesita conexión para mostrar el QR y que no
   sirve una captura. No finge funcionar.

## Criterios de aceptación

### Emisión del token

- **AC-01** `qr-token` con sesión de otro usuario sobre un ticket ajeno devuelve 403 y
  **no** revela si el ticket existe.
- **AC-02** Sin sesión, devuelve 401.
- **AC-03** Con `status` distinto de `active` (`listed`, `used`, `void`, `refunded`,
  `transferred`) devuelve 409 con el motivo — Art. 2.4.
- **AC-04** Con `now() < qr_available_from` devuelve 409 y **la fecha** desde la que
  estará disponible — Art. 2.5.
- **AC-05** Con el evento `cancelled` devuelve 409.
- **AC-06** Dos llamadas dentro del mismo slot devuelven el **mismo** token.
- **AC-07** Cruzando el borde del slot, el token **cambia**.
- **AC-08** La respuesta trae los segundos que faltan para el próximo slot, para que la
  UI no tenga que adivinar el reloj del servidor.
- **AC-09** La respuesta **nunca** incluye el `secret`, ni entero ni truncado.
- **AC-10** `ticket_secrets` no tiene ninguna política; un `select` con la publishable
  key devuelve 0 filas — Art. 2.6.
- **AC-11** El JWT del fan no sirve para leer `ticket_secrets` ni por PostgREST ni por
  RPC.

### Wallet

- **AC-12** Un fan lee solo los tickets donde es `owner_id`.
- **AC-13** `anon` no lee ni un ticket.
- **AC-14** El organizador **no** lee tickets individuales de su evento (**D-06**).
- **AC-15** Un fan no puede `update` ni `delete` un ticket. Todo cambio de estado va por
  RPC o Edge Function.
- **AC-16** La wallet ordena por `starts_at` ascendente entre las activas y descendente
  entre las pasadas.
- **AC-17** Un ticket `listed` muestra «QR inhabilitado» y **no** pide token — Art. 2.4.
- **AC-18** Un ticket `used` muestra la hora del check-in, tomada de `checkins`, no de un
  campo suelto.

### Presentación (Art. 2.3)

- **AC-19** El QR se dibuja en un `<canvas>` o SVG en línea. **No** hay `<img>` con data
  URI, ni enlace de descarga, ni botón de compartir sobre el QR.
- **AC-20** El texto «Las capturas no funcionan» está presente en cada ticket con QR
  visible. No es un tooltip ni un acordeón.
- **AC-21** La wallet no cachea el token en `localStorage` ni en `sessionStorage`. Vive
  en memoria y muere con la pestaña.
- **AC-22** El `code` del ticket va en JetBrains Mono y se puede seleccionar y copiar
  como texto — hay que poder dictarlo.

## Riesgos de confusión

- **«Ya tengo la foto del QR, listo».** Es el riesgo central del feature. Se ataca con
  tres cosas a la vez: la cuenta atrás visible que prueba que el código cambia, el texto
  fijo debajo, y un mensaje en puerta que nombra la captura en lugar de decir «error».
- **«QR desde el 1 de julio» se lee como error.** El copy explica la regla («14 días
  antes del evento»), no solo la fecha.
- **«QR inhabilitado» se lee como «me robaron la entrada».** Dice la causa: publicada en
  reventa, transferida o anulada, y ofrece soporte en la misma card.
- **La wallet se confunde con una billetera de dinero.** No hay saldo, ni importes, ni
  nada que se parezca a un balance (**D-28**).
