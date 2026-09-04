# 005 — Plan

La wallet es el centro de control del fan y el QR es el puente con la puerta.
Es el artículo **2** completo, implementado.

## Migraciones

| # | nombre | contenido |
|---|---|---|
| 0041 | `wallet_view` | `v_my_tickets`: el ticket con su evento, zona y asiento, y el estado del QR ya resuelto |

Una sola. El schema de los tickets ya está en 004; aquí falta la **lectura**.

## Edge Functions

| nombre | quién la llama | qué hace |
|---|---|---|
| `qr-token` | la wallet del fan | emite el token del slot actual |
| `qr-validate` | el validador de 006 | verifica un token y marca el ticket usado |

`qr-validate` se escribe aquí porque es la otra mitad del mismo algoritmo:
separarlas sería dejar el HMAC definido en dos sitios. 006 la consume.

## El QR: TOTP con HMAC-SHA256

```
slot   = floor(unix_seconds / 30)
mac    = hmac_sha256(secreto_del_ticket, ticket_id || ':' || slot)
token  = base64url( ticket_id | slot | mac[0..15] )
```

Tres decisiones y su porqué:

**El secreto vive en `ticket_secrets`**, tabla con RLS activa y cero políticas
(Art. 2.6). Ni `anon`, ni `authenticated`, ni el propietario. Solo esta función,
que corre con `service_role`. Ya está creada en 004 con 32 bytes por ticket.

**El MAC se trunca a 16 bytes.** 128 bits es de sobra contra falsificación, y
mantiene el QR pequeño — que es lo que hace que se lea rápido con poca luz y una
mano temblando. Un QR más denso es un QR que no escanea a la primera.

**El `slot` viaja en claro dentro del token.** No es un secreto, y permite al
validador distinguir dos incidentes que parecen el mismo y no lo son:

- **MAC inválida** → el código no es de Feventi, o está corrupto.
- **MAC válida pero slot fuera de ±1** → el token estuvo **almacenado**. Solo
  puede venir de una captura de pantalla.

Sin el slot en claro, los dos casos darían «QR inválido» y se perdería la señal
antifraude más valiosa de la noche.

## Qué protege de verdad, y qué no

Rotar cada 30 s hace **incómodo** compartir un pantallazo. No lo hace imposible:
dentro de la ventana, la imagen sirve. Conviene decirlo claro en lugar de
pretender lo contrario.

La protección real es doble:

1. **Un ticket entra una vez.** El primer escaneo lo marca `used`; el segundo
   dice «YA UTILIZADO» con la hora y la puerta del primero. Quien comparte su QR
   está regalando su propia entrada, no duplicándola.
2. **Un token de un slot viejo es una acusación.** Si la MAC es válida pero el
   slot está fuera de ±1, ese token estuvo guardado. El validador responde
   «probable captura de pantalla» y lo registra con
   `reason = 'screenshot_suspected'`.

> `ponytail:` la ventana de replay es de 30 s por diseño. Cerrarla del todo exige
> un desafío del scanner al servidor por escaneo —QR con nonce del validador—, lo
> que obliga al scanner a estar online por lectura y contradice **D-04**. Si el
> fraude medido lo justifica, ese es el camino: nonce por escaneo, no ventana más
> corta. Acortarla solo empeora la experiencia sin cerrar nada.

## Por qué ±1 slot y no exacto

El reloj del móvil del fan y el del servidor no coinciden. Con tolerancia cero,
un desfase de dos segundos en el borde del slot rechaza a alguien con una entrada
legítima, en la puerta, con cola detrás.

±1 slot da una ventana de hasta 90 s y elimina ese falso rechazo. El coste es que
la ventana de replay pasa de 30 a 90 s — y como el replay ya está contenido por
el uso único, el intercambio es claramente favorable.

## Las cinco razones por las que NO se emite un token

`qr-token` responde el motivo, no un error genérico. El fan tiene que saber si
es cuestión de esperar o de escribir a soporte:

| situación | respuesta |
|---|---|
| sin sesión | 401 |
| el ticket no es suyo | 403, **sin decir si existe** |
| `status` distinto de `active` | 409 con el motivo concreto (Art. 2.4) |
| `now() < qr_available_from` | 409 **con la fecha** desde la que estará (Art. 2.5) |
| evento `cancelled` | 409 |

Un 403 que distinga «no es tuyo» de «no existe» convierte la wallet en un oráculo
para enumerar tickets ajenos.

## La vista de la wallet

`v_my_tickets` resuelve del lado del servidor lo que la pantalla necesita, para
que el front no reimplemente reglas:

- datos del evento, zona y asiento en una sola fila;
- **`qr_state`**: `available`, `too_early`, `disabled` o `spent`, ya calculado.

Ese `qr_state` es la regla del Art. 2 en un solo sitio. Si el front lo dedujera
de `status` + `qr_available_from`, esa lógica viviría en dos lenguajes.

`security_invoker = true`: la RLS del que consulta se aplica **dentro** de la
vista, así que no la esquiva — al contrario que `v_event_public`, que sí lo hace
a propósito y por eso lleva su excepción argumentada.

## Front

```
features/wallet/
  wallet.store.ts     lista de tickets + petición del token
  wallet.page.ts      la wallet
  ticket-qr.ts        el QR dibujado, con su cuenta atrás
```

Del mockup y del spec, lo que no se negocia:

- el QR en **canvas**, no en `<img>`. Sin data URI, sin enlace de descarga, sin
  botón de compartir sobre el QR (**AC-19**);
- la **cuenta atrás con barra de progreso** — es lo que prueba visualmente que el
  código cambia, y sostiene el mensaje de abajo;
- **«Muestra este QR en puerta. Las capturas no funcionan.»** siempre visible en
  cada ticket con QR. No un tooltip, no un acordeón (**AC-20**);
- el token **nunca** en `localStorage` ni `sessionStorage`: vive en memoria y
  muere con la pestaña (**AC-21**);
- el código del ticket en **monoespaciada y seleccionable** — hay que poder
  dictarlo a soporte (**AC-22**);
- «QR desde el 1 de julio» explica **la regla** («14 días antes del evento»), no
  solo la fecha.

### El QR se dibuja con `qrcode-generator`

Primero se intentó un encoder propio: el contenido siempre es el mismo —51
caracteres base64url— así que parecía un caso lo bastante acotado como para no
pagar una dependencia. Salieron ~200 líneas: Reed-Solomon sobre GF(256), máscara
fija, versiones 3 a 6.

**No funcionaba.** Contrastado contra `qrcode-generator`, 429 de 1089 módulos
salían distintos. No habría escaneado.

Se descartó. El razonamiento para no seguir depurándolo: un QR que falla en la
puerta, con cola detrás y poca luz, es lo más caro que puede romperse en este
producto. Ahí no se ahorran 10 KB.

Y la lección que vale para el resto del proyecto: **escribir algo propio solo es
más simple si se puede comprobar que funciona.** Aquí la única forma de
comprobarlo era compararlo contra una implementación de referencia — es decir,
contra la misma dependencia que se quería evitar. En cuanto la comprobación
necesita la dependencia, la dependencia ya ganó.

## Verificación

`supabase/tests/005_wallet_qr.sql` para la vista y la RLS, y pruebas por HTTP
contra la Edge Function para el token:

- **AC-01/AC-02** un ticket ajeno da 403 y no revela si existe;
- **AC-03** cada estado no-`active` da su motivo;
- **AC-04** fuera de ventana da la fecha;
- **AC-06/AC-07** dos llamadas en el mismo slot dan el **mismo** token; cruzando
  el borde, cambia;
- **AC-09/AC-10** la respuesta nunca trae el secreto, y `ticket_secrets` sigue
  inalcanzable;
- y la que de verdad importa: un token de un slot viejo se distingue de uno
  inválido.
