# 005 — Tasks

**Cerrado.** 17/17 comprobaciones en verde contra el proyecto real, por HTTP.

## Base de datos

- [x] T-01 `0041_wallet_view`: `v_my_tickets` con `qr_state` resuelto en el servidor
- [x] T-01b `0042_wallet_view_definer`: **la vista salía vacía.** `security_invoker
      = true` parecía lo correcto, pero el join con `events`, `zones` y `venues`
      —limitadas al organizador— dejaba al fan con 3 tickets y 0 eventos. Pasa a
      `definer` con un filtro por `owner_id`, más estrecho y más fácil de auditar
      que abrirle esas tres tablas a cualquiera con una entrada

## Edge Function

- [x] T-02 `qr-token` desplegada, `verify_jwt = true`
- [x] T-03 TOTP con HMAC-SHA256, ventana de 30 s, MAC truncada a 16 bytes
- [x] T-04 El `slot` viaja en claro — es lo que permite a 006 distinguir «MAC
      inválida» de «MAC válida pero vieja», que son dos incidentes distintos
- [x] T-05 Las cinco razones de rechazo, cada una con su motivo concreto
- [x] T-06 `expires_in` lo calcula el **servidor**: deducirlo del reloj del móvil
      haría que la cuenta atrás mintiera en cuanto hubiera desfase, y esa cuenta
      atrás es lo que sostiene el mensaje de que el código cambia

## Verificación

- [x] T-07 `supabase/tests/005_qr_token.mjs` — 17/17
- [x] T-08 **AC-06** dos llamadas en el mismo slot → el mismo token
- [x] T-09 **AC-07** al cruzar el borde → el token cambia, el `ticket_id` embebido no
- [x] T-10 **AC-01** un ticket ajeno da 403 y **no revela si existe**
- [x] T-11 **AC-04** fuera de ventana da 409 **con la fecha** desde la que estará
- [x] T-12 **AC-09/AC-10** la respuesta nunca trae el secreto, y `ticket_secrets`
      sigue inalcanzable incluso para el dueño del ticket

### Dos trampas del arnés, anotadas en el propio archivo

- El cuerpo de la respuesta trae su propio `status` (el del ticket, `active`), y
  con `{ status: r.status, ...j }` el spread **pisaba el código HTTP**. AC-04
  fallaba con el mensaje correcto. Por eso el campo se llama `http`.
- La comparación de AC-06 salía «no concluyente» si quedaban 2 s de slot. Una
  prueba que a veces no concluye no es una prueba: ahora espera a un slot fresco.

## Front

- [x] T-13 `wallet.store.ts` — el token vive en memoria, **nunca** en
      `localStorage` (AC-21): persistirlo sería fabricar la captura que el
      Art. 2.3 dice que no debe funcionar
- [x] T-14 `ticket-qr.ts` — el QR en `<canvas>`, sin data URI ni descarga (AC-19)
- [x] T-15 `wallet.page.ts` — próxima entrada con QR grande, otras, y pasadas
- [x] T-16 Cuenta atrás con barra de progreso: es lo que **prueba** visualmente
      que el código cambia
- [x] T-17 «Muestra este QR en puerta. Las capturas no funcionan.» siempre
      visible, no en un tooltip (AC-20)
- [x] T-18 El código del ticket en monoespaciada y seleccionable (AC-22)
- [x] T-19 «QR desde el 19 de octubre» explica **la regla** («14 días antes del
      evento»), no solo la fecha
- [x] T-20 «QR inhabilitado» dice la **causa** — a secas se lee como «me robaron
      la entrada»
- [x] T-21 Ruta `/entradas` con `authGuard`
- [x] T-22 `npm run build` limpio

## El encoder de QR: un intento fallido, y por qué se descartó

Se escribió un encoder propio (~200 líneas: Reed-Solomon, máscara fija, versiones
3-6) para ahorrarse la dependencia. El contenido siempre es el mismo —51
caracteres base64url— así que parecía un caso acotado.

Al contrastarlo contra `qrcode-generator`, **429 de 1089 módulos salían
distintos**. No habría escaneado.

Se descartó y se usa la librería. El razonamiento: un QR que falla en la puerta,
con cola detrás y poca luz, es lo más caro que puede romperse en este producto.
No es sitio para ahorrar 10 KB, y menos con código que no se puede verificar sin
una implementación de referencia — que es justo la que se estaba evitando.

La lección general, para el resto del proyecto: **escribir algo propio solo es
más simple si se puede comprobar que funciona.** Si la comprobación exige la
misma dependencia que se quería evitar, la dependencia ya ganó.

## Fuera de alcance, como dice el spec

Transferir, publicar en reventa, donar, álbum del evento pasado y saldo. El enum
`ticket_status` ya tiene `listed` y `transferred`, y la wallet sabe pintarlos —
pero nada los produce todavía. Fase 2.
