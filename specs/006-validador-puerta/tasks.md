# 006 — Tareas

**Estado: listo.** 40 comprobaciones en SQL + 25 por HTTP, todas en verde.
Build limpio, `service_role` ausente del bundle, advisors sin hallazgos nuevos
fuera de los dos `ERROR` ya argumentados que esta feature añade.

## Backend

| # | qué | dónde |
|---|---|---|
| T-01 | enums `checkin_result` y `checkin_reason` | `0043` |
| T-02 | `event_staff` con revocación (Art. 8.2) | `0043` |
| T-03 | `checkins`, append-only | `0043` |
| T-04 | RLS de las dos | `0043` |
| T-05 | `v_my_gate_events` — AC-06 | `0044` |
| T-06 | `v_gate_stats` — AC-26 | `0044` |
| T-07 | `gate_find_by_dni` — D-03 | `0044`, corregida en `0046` |
| T-08 | `gate_checkin` — la decisión, en una transacción | `0044` |
| T-09 | `_shared/qr.ts` — el algoritmo, en UN sitio | Edge |
| T-10 | `qr-validate` desplegada, `verify_jwt = true` | Edge |
| T-11 | `qr-token` redesplegada contra el módulo compartido | Edge |

## Front

| # | qué | dónde |
|---|---|---|
| T-12 | `gate.store.ts` — llamadas y copy de los cuatro resultados | `features/puerta/` |
| T-13 | `mis-eventos.page.ts` — puerta y fecha grandes | `features/puerta/` |
| T-14 | `scanner.page.ts` — veredicto, DNI, historial, contador | `features/puerta/` |
| T-15 | `qr-scanner.ts` — cámara con `jsqr` | `shared/ui/` |
| T-16 | ruta `/puerta` con `GateLayout` y `authGuard` | `app.routes.ts` |
| T-17 | tipos de las dos tablas, las dos vistas y los dos enums | `db.types.ts` |

## Lo que salió mal, y qué se aprendió

### Una prueba que daba verde por el motivo equivocado

`gate_find_by_dni` llamaba a `public.hash_dni`. Esa función vive en `private`
desde la migración `0010`. **plpgsql no valida el cuerpo al crear la función**, así
que compiló sin una queja y habría reventado la primera noche que alguien usara
el modo DNI en puerta, con el fan sin batería delante.

Es la trampa que la constitución ya tenía anotada y que `0017` ya había pisado
una vez. Lo llamativo no es eso: es que **la suite lo tapó**. La comprobación
decía «un DNI mal formado tiene que fallar», y fallaba — pero por
`function does not exist`, no por el formato.

> Una comprobación que solo verifica **que** algo falla, y no **por qué**, no
> distingue un guardarraíl de una función rota.

La comprobación nueva pide el camino **feliz**: un DNI válido tiene que
**devolver** la entrada. Ese es el que no se puede fingir. Y por eso, en el
`.mjs`, la búsqueda por DNI comprueba el código exacto del ticket encontrado.

### Un uuid de otro evento, y un error que hablaba de otra cosa

Escribiendo la semilla se reusó `…e101`, que ya era la zona General de «Noche de
Stand Up». El `on conflict do nothing` se la quedó en silencio, y el fallo salió
tres statements más tarde:

```
el stock de la zona General en esta fase (400) supera su aforo (300)
```

300 era el aforo de la zona **del otro evento**. El insert no falló por lo que
debía.

La causa: `price_tiers` y `tickets` llevan `event_id` denormalizado **junto a**
`zone_id`, y las FK eran simples — nada obligaba a que la zona fuera del evento
de la fila. En producción eso deja un precio del evento A visible en el catálogo
del evento B.

Cerrado en `0045` con FK **compuestas**, que es lo que este esquema ya usa en
`zones`/`zone_segments`/`seats`. No un trigger, que se puede desactivar, ni un
check, que no puede mirar otra tabla: el motor.

> Un `on conflict do nothing` sobre una clave que crees tuya es un `if` silencioso.
> Cuando el uuid es a mano, el bloque de ids es parte del diseño.

### La semilla no era reejecutable, y el guard tenía razón

La primera versión recolocaba la ventana de turno con `on conflict … do update
set starts_at = …`. Chocó de frente con `guard_sensitive_event_fields`:

```
con entradas ya emitidas, la fecha, el lugar, el aforo y las reglas comerciales
los cambia Feventi: abre un caso de soporte
```

El guard tiene razón: mover la fecha de un evento vendido es una acción de Admin.
La salida no era esquivarlo —había la tentación de fabricar un Admin solo para la
semilla— sino **no pedirle nada**: la semilla borra el evento de demo entero y lo
vuelve a construir. Sale más corta y no toca ninguna regla.

### Otra vez la contaminación entre comprobaciones

AC-15 («evento pausado: ENTRA») falló con `already_used`. La entrada que usaba ya
la había consumido AC-11b tres comprobaciones antes.

Es exactamente la trampa que `004` había anotado —una comprobación con efectos
contamina a la siguiente— y volvió a morder. Ahora AC-15 tiene entrada propia.
Falló la prueba, no el producto, pero cuarenta comprobaciones con una en rojo son
cuarenta comprobaciones en las que ya no se confía.

### AC-21 pedía más de lo que debía

La primera versión exigía «al menos 3 escaneos denegados» y salieron 2. Contaba
como escaneos el intento del fan y el del evento ajeno — que dan 403 y **no**
deben dejar fila: no llegaron a la puerta.

Corregido a lo que la regla dice de verdad: los dos códigos ilegibles dejan fila,
y ninguno se pierde.

## Lo que queda fuera, y por qué

- **Sin linterna en el escáner.** Cuatro líneas el día que se vea que hace falta.
- **Sin modo offline** (D-04). La pantalla lo dice en vez de fingir.
- **Sin excepciones autorizadas desde la app** (D-05). Van por soporte.
- **`v_gate_stats` no filtra por turno**, solo por evento y puerta. Con un evento
  al día da igual; el día que un venue haga dos funciones seguidas habrá que
  meter la ventana en la vista.
- **El presupuesto de bundle inicial subió de 500 a 550 kB.** El total es 501,86
  kB (122 kB transferidos) y `jsqr` va en el chunk perezoso del escáner, no en el
  inicial. Optimizar 1,86 kB sobre un umbral redondo no compra nada.
