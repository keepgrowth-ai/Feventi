# 006 — Plan

La única pantalla donde un segundo de duda cuesta dinero real. Todo lo de aquí
sale de esa frase.

## El reparto: quién decide qué

```
  scanner (Angular)          qr-validate (Deno)            gate_checkin (Postgres)
  ─────────────────          ──────────────────            ───────────────────────
  lee el QR con la cámara →  verifica el HMAC          →   bloquea el ticket
  pinta el veredicto      ←  calcula el slot_delta         decide los 4 resultados
                             (nada más)                    marca `used`
                                                           escribe el checkin
                                                           ──── una transacción ───
```

**Nada decide en el cliente.** El front manda un código y pinta lo que le
devuelven. Si algún día alguien «agiliza» resolviendo en el navegador —«si el
ticket ya salió `used`, no llames»—, el resultado es dos personas dentro con una
entrada.

**Nada de estado decide en la Edge Function.** La función sabe de criptografía:
tiene el secreto y puede comprobar la firma. Punto. Bloquear el ticket, marcarlo
usado y anotar el asiento **tiene** que ser atómico, y en la función serían tres
viajes con ventanas entre ellos.

`gate_checkin` recibe `p_mac_ok` y `p_slot_delta` ya calculados, y por eso es
**solo de `service_role`**: si `authenticated` pudiera llamarla, cualquiera con
sesión marcaría entradas como usadas pasando `p_mac_ok = true`.

## Migraciones

| # | nombre | contenido |
|---|---|---|
| 0043 | `gate_staff_and_checkins` | enums, `event_staff`, `checkins`, RLS |
| 0044 | `gate_decision` | `v_my_gate_events`, `v_gate_stats`, `gate_find_by_dni`, `gate_checkin` |
| 0045 | `cross_event_composite_fks` | FK compuestas: la zona pertenece al evento |
| 0046 | `fix_gate_find_by_dni_helper` | corrige un `public.hash_dni` que ya no existía |

Las dos últimas no estaban planificadas. La 0045 salió escribiendo la semilla y
la 0046 salió porque una prueba daba verde por el motivo equivocado; las dos
están contadas en `tasks.md`.

## El staff es un rol POR EVENTO

`event_staff (event_id, profile_id, gate, zone_id, revoked_at)`.

No es `profiles.role`. La misma persona es staff del festival del sábado y no lo
es del concierto del domingo; un rol global obligaría a acotarlo en cada consulta
y la primera que se olvidara sería un agujero.

**`gate` es texto, no una tabla.** «Puerta A», «Acceso VIP» son etiquetas del
venue, cambian por evento y no tienen atributos propios. Una tabla `gates` sería
una tabla de una columna.

**`zone_id` nulo = la puerta atiende todas las zonas.** Con valor, un ticket de
otra zona sale `manual_review`/`wrong_zone` — nunca denegado.

### El turno se deriva, no se guarda

De `doors_at − 2 h` a `starts_at + 4 h`. Guardarlo por asignación obligaría a
rehacer todas las filas cada vez que el evento mueve la hora, y la primera vez
que alguien lo olvidara el staff se quedaría fuera de su propia puerta.

## Los cuatro resultados, y el orden en que se deciden

```
  ¿la firma cuadra?           no → DENEGADO  qr_unreadable
  ¿el ticket es de este evento? no → DENEGADO  wrong_event      (y se registra)
  ¿el evento está cancelado?   sí → DENEGADO  event_cancelled
  ¿el slot está en ±1?         no → DENEGADO  screenshot_suspected
  ¿el ticket ya se usó?        sí → YA UTILIZADO
  ¿el ticket está activo?      no → DENEGADO  ticket_listed | void | …
  ¿sin nominar y modo strict?  sí → DENEGADO  not_nominated
  modo DNI                        → REVISAR   dni_mode
  ¿sin nominar (flexible)?     sí → REVISAR   not_nominated
  ¿zona distinta a la puerta?  sí → REVISAR   wrong_zone
                                  → PERMITIDO
```

El orden importa: lo que deniega va antes que lo que revisa, y dentro de lo que
deniega, primero lo que dice que el código no vale.

`paused` **no** aparece en la cascada, y es a propósito (AC-15): pausar detiene
la venta, no el acceso de quien ya compró.

### Qué consume la entrada, y qué no

Esto no estaba escrito en el spec y hubo que decidirlo:

| resultado | ¿marca `used`? | por qué |
|---|---|---|
| `allowed` | **sí** | obvio |
| `manual_review` / `not_nominated` | **sí** | la persona entra; la revisión es de identidad, no de validez. Si no consumiera, el mismo QR admitiría a un segundo |
| `manual_review` / `dni_mode` | **sí** | igual: el staff eligió un ticket concreto y esa persona entra |
| `manual_review` / `wrong_zone` | **no** | puede ser señalización del venue. Si va a la puerta correcta tiene que poder entrar; consumir aquí la dejaría fuera |
| `already_used` y todo `denied` | **no** | no entró |

Las dos comprobaciones que lo fijan (AC-16b, AC-18b) están en la suite,
precisamente porque es la clase de decisión que alguien «simplifica» después.

## `already_used` no es una acusación

Casi nunca es fraude: es un doble escaneo, o un grupo que compartió una pantalla.
El veredicto trae la hora y la puerta del **primer** ingreso, sacadas de
`checkins`, y dice «escala a supervisor». No «entrada falsa».

## La bitácora registra TODO, incluidos los ilegibles

Un QR que no es de Feventi deja fila con `ticket_id` nulo. No es ruido: es lo que
permite saber al día siguiente que en la Puerta C hubo veinte capturas de
pantalla, y `v_gate_stats` las separa en su propia columna.

Lo que **no** deja fila: una llamada de alguien que no es staff, o fuera de
turno. Esas revientan antes, con 42501. No son escaneos dudosos — son llamadas
que no deberían existir.

> Un token con la firma mal **no** propaga su `ticket_id` al checkin, aunque el
> uuid que traiga sea real. Ensuciar la bitácora de un ticket con un intento que
> nunca fue suyo convertiría el peritaje en un problema.

## Append-only de verdad (Art. 8.1)

`checkins` no admite `insert`, `update` ni `delete` para `authenticated`. **En
ningún rol**: ni staff, ni organizador, ni Admin. El único que escribe es
`service_role`, desde la Edge Function.

Corregir un error de puerta no es editar la fila: es un caso de soporte, y la
pantalla lo dice donde el staff podría buscar el botón de borrar.

## Las vistas, y por qué son `definer`

`v_my_gate_events` y `v_gate_stats` van con `security_invoker = false`, igual que
`v_my_tickets` (0042). La alternativa es abrir `events`, `venues` y `zones` a
cualquiera que sea staff de algún evento, con la fila **entera** — incluidos los
campos comerciales que el Art. 7.5 no le corresponde ver. El filtro por
`profile_id = auth.uid()` cabe en una línea y se audita de un vistazo; tres
políticas nuevas, no. Queda anotado en `advisor-baseline.md`.

## Modo DNI (D-03)

`gate_find_by_dni(event_id, dni)` la llama el staff **directamente** —es
`security definer` y comprueba `event_staff` en su cuerpo— y devuelve nombre,
últimos cuatro y ubicación. Nunca el hash.

La comprobación de staff va **antes** de hashear a propósito: si no, cualquiera
con sesión tendría un oráculo para confirmar si una persona concreta va a un
evento concreto.

Validar sigue yendo por `qr-validate` con `mode: 'dni'`, para que el checkin lo
escriba el mismo sitio que los demás.

## Modo Puerta (Art. 10)

- veredicto a **ancho completo**, título a 34 px;
- **color + icono + texto**, siempre los tres;
- `ACCESO PERMITIDO` se va solo a los 2 s; los otros tres **esperan un toque**.
  Es asimétrico a propósito: lo que va bien no debe frenar la cola, y lo que va
  mal no debe desaparecer antes de leerse;
- botón de escanear de 56 px, en la mitad inferior — donde llega el pulgar;
- nada por debajo de 16 px (lo fuerza `.fv-gate` en `styles.css`);
- **sin conexión, el escáner se bloquea.** No hay cola de lecturas pendientes
  (D-04): un ticket dado por bueno que luego resulta inválido es peor que una
  cola.

El header repite evento, fecha y puerta siempre, y cambiar de evento obliga a
volver a «Mis eventos». Operar la puerta equivocada es el error más caro de la
noche y no se descubre hasta que alguien reclama.

### La cámara

`jsqr`, no `BarcodeDetector`. Lo nativo sería la primera opción, pero esa API no
está en todos los navegadores con los que el staff llega con su propio teléfono,
y mantener dos caminos significa que uno de los dos solo se prueba el día del
evento. Un camino, probado.

El bucle lee 10 veces por segundo sobre un fotograma reducido a 480 px: a
resolución completa y 60 fps calienta el teléfono y no encuentra el QR antes —
lo que ayuda es que la cámara enfoque. Y hay un freno de 3 s por código: sin él,
un QR en el encuadre dispararía diez validaciones y nueve dirían «YA UTILIZADO».

> `ponytail:` sin linterna. Si la puerta está a oscuras se añade con
> `applyConstraints({ advanced: [{ torch: true }] })`, que es un botón y cuatro
> líneas. No se adelanta porque no todos los dispositivos lo soportan y habría
> que diseñar el caso de que no esté.

## Ruta y guard

`/puerta` con `authGuard`, **no** con `roleGuard('staff')`. Ser staff no es un
rol global; quien no esté asignado a nada ve «Mis eventos» vacío con el texto que
explica por qué, y `qr-validate` le da 403 aunque llegue a la pantalla — que es
donde de verdad se decide (Art. 9.2).

## Verificación

Dos archivos, porque son dos cosas distintas:

- **`supabase/tests/006_validador_puerta.sql`** — la decisión, la autorización y
  la bitácora, llamando a `gate_checkin` con los parámetros ya calculados. Corre
  en `begin … rollback`.
- **`supabase/tests/006_qr_validate.mjs`** — que un token **real** emitido por
  `qr-token` se verifica bien, y **AC-09**: dos peticiones HTTP en paralelo sobre
  el mismo ticket. Es la comprobación que, si falla, se descubre con dos personas
  dentro y una entrada vendida. Necesita `supabase/seed/demo_puerta.sql`.
