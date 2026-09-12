# Las pruebas

Ocho suites SQL y dos por HTTP. Cada una corre entera dentro de
`begin … rollback`: **no dejan rastro**.

```
001_fundaciones.sql            auth, perfiles, roles, tenencia, RLS base
002_catalogo_publico.sql       la superficie de anon
003_detalle_evento.sql         inventario, dinero y visibilidad
004_checkout_emision.sql       reserva, nominación, pago y emisión
005_qr_token.mjs               el QR rotativo, por HTTP
006_validador_puerta.sql       la decisión de puerta y la bitácora
006_qr_validate.mjs            el token real y el doble escaneo, por HTTP
007_solicitud_aprobacion.sql   el flujo de aprobación
008_dashboard_organizador.sql  el dinero agregado y el aislamiento
009_soporte.sql                el contexto, la doble vía y las notas internas
```

## Cómo se corren

Las `.sql` con `mcp__supabase__execute_sql`, pegando el archivo entero. Las
`.mjs` con `node supabase/tests/00N_*.mjs`, y **006 necesita antes**
`supabase/seed/demo_puerta.sql`.

## Reglas del arnés, aprendidas a base de falsos negativos

Cada una costó una corrida en rojo que no era del producto.

**Bloque de identificadores por suite.** La base tiene datos permanentes —la
semilla de demo— así que una suite no puede asumir que está vacía. Cada una usa
su propio bloque:

| suite | prefijo uuid | RUC |
|---|---|---|
| 001 | `11111111…` / `10000000…` | `20501000001` |
| 002 | — | `20502000001` |
| 003 | `e0000000…`, `20000000…` | `20503000001`, `20503000002` |
| 004 | `a1000000…` | `20504000001` |
| 006 | `a6000000…` | `20506000001` |
| 007 | — | `20507000001`, `20507000002` |
| 008 | `a8000000…` | `20508000001`, `20508000002` |
| 009 | `a9000000…` | `20509000001` |
| 010 | `b0000000…` | — |
| 011 | `b1000000-0000-4000-8000-…` | `20511000001` |
| 012 | `b2000000-0000-4000-8000-…` | `20512000001` |
| 013 | `b3000000-0000-4000-8000-…` | `20513000001` |
| 016 | `b6400000-0000-4000-8000-…` | `20564000001` |

Lo destapó 003 al chocar con el RUC de «Andes Live SAC», que puso
`demo_kpop.sql`. Una suite que solo pasa contra una base recién creada no sirve
para comprobar la base que hay.

**`fails()` y `err()` ejecutan el statement CADA UNA.** Para una comprobación de
solo lectura da igual; para una con efectos —reservar, nominar, validar— la
segunda pasada choca con la primera y el detalle reportado miente. En esos casos
se usa solo `fails()` y el detalle se escribe a mano. *(004, 006)*

**Una comprobación con efectos contamina a la siguiente.** Cada caso que consume
una entrada necesita su propia entrada. Ha mordido dos veces: AC-22 de 004 y
AC-15 de 006. *(004, 006)*

**No llames a una función dentro del `where` de la tabla que ella escribe.** La
consulta ya fijó su snapshot, así que la fila nueva no es visible y el resultado
sale nulo. Llamar en un statement, guardar el id, comprobar en el siguiente.
*(009)*

**Comprobar QUE algo falla no es comprobar POR QUÉ.** `gate_find_by_dni` llamaba
a una función inexistente y la suite daba verde: esperaba un fallo y lo hubo, por
el motivo equivocado. Toda comprobación de un guardarraíl necesita al lado la del
camino feliz. *(006)*

**`perform` es de plpgsql, no de SQL.** En un `.sql` que se ejecuta directo, una
función que devuelve `void` se llama con `select`. *(009)*

**El cuerpo de una respuesta HTTP puede pisar su código.** `{ status: r.status,
...j }` deja que un `status` del JSON sobrescriba el de la respuesta. Se guarda
como `http`. *(005, 006)*

**`anon` da «permission denied», no «cero filas».** La migración `0009` le quitó
el `select` por defecto, así que ni llega a evaluar la política. La comprobación
pide el fallo, que es lo que de verdad ocurre. *(009)*

## Lo que salió al re-correrlas todas contra el schema actual

Se hizo al cerrar Fase 1, y valió la pena: **dos suites llevaban rotas sin que
nadie lo supiera**, porque una suite que no se vuelve a correr no dice la verdad
sobre el código de hoy.

### 007 llevaba rota desde 003

`publish_event` gana una guarda al aplicar 003 —«no se publica sin al menos una
entrada con stock»— que hasta entonces se saltaba sola:

```sql
if to_regclass('public.price_tiers') is not null then …
```

007 se escribió antes y nunca sembró inventario. AC-07b fallaba y arrastraba a
AC-07c, AC-20 y AC-20b: **cuatro comprobaciones en rojo, y el producto correcto**.

Ahora siembra zona, fase y tier antes de publicar, y de paso comprueba la guarda
misma (AC-07d), que no la verificaba nadie.

> Una migración que toca una función deja obsoletas las pruebas de esa función,
> aunque estén en otra feature. El orden del roadmap no protege de esto: 003 va
> después de 007.

### Las suites asumían una base vacía

Tres chocaban con la semilla de demo —RUC repetido, slug `k-pop-fest-2026`
duplicado, `approve_organizer` sobre todos los organizadores— y varias contaban
`count(*)` sobre tablas que ahora tienen datos permanentes.

Los conteos que corren tras `reset role` son los peligrosos: sin RLS que los
acote, `count(*) from tickets` cuenta también los de otro evento.

### Y la contaminación mordió dos veces más

AC-30 de 004 deja viva una reserva de Platea. AC-13b la contaba como si no
existiera (`reserved = 0`) y AC-34b esperaba una sola orden. Las dos pasaban
**solo si se corrían aisladas** — la peor clase de prueba: verde en el
escritorio, roja en la suite entera.


## Lo que salió al construir la capa social (010–013)

Cinco correcciones, y **cuatro de las cinco las destapó una comprobación de
camino feliz**, no un guardarraíl. Vale la pena decirlo así de claro: los
guardarraíles estaban todos en verde mientras el producto no funcionaba.

**Un `grant` de tabla y una política de RLS son dos permisos distintos.** Las
políticas de `delete` de `friend_edges` no servían para nada: la migración
`0009` invirtió los privilegios por defecto, así que la tabla nueva nace solo
con `select` y Postgres devuelve `42501` **antes** de evaluar la política. Lo
vio AC-15c —«sí puede borrar lo suyo»— mientras AC-15a y AC-15b, los dos
«no puede», seguían pasando. Desde el lado del guardarraíl, un `revoke` de más
se ve exactamente igual que uno bien puesto. *(010, `0053`)*

**Una vista `security_invoker` no puede leer lo que su llamante no puede.**
`v_my_friends` salía vacía: hace join con `profiles`, y la política de
`profiles` es solo para su dueño. Es el mismo fallo que 0041 → 0042 con la
wallet, dos features después. *(010, `0054`)*

**Y al pasarla a `definer`, el `where` pasa a ser la única protección.** Cada
vista definer de esta fase lleva su propia comprobación de que un tercero la ve
VACÍA —010/AC-07d, 011/AC-11—, porque un `where` mal editado convierte «mis
amigos» en «el grafo social de la plataforma».

**Un `grant execute … to authenticated` no quita el `execute` de `PUBLIC`.**
Las tres RPC de 010 nacieron publicadas en `/rest/v1/rpc/` para `anon`. Se ve
en la ACL: las de Fase 1 llevan `postgres=X | authenticated=X | service_role=X`;
las nuevas llevaban además la entrada vacía `=X/postgres`. *(010, `0055`)*

**Una política que consulta su propia tabla recursa.** `group_members` se
preguntaba a sí misma si el llamante era miembro: `42P17: infinite recursion`.
El proyecto ya tenía la salida escrita desde `0004` —un helper definer que
devuelve un array—, solo había que usarla. **El linter no lo ve**: solo aparece
al leer la tabla. *(012, `0059`)*

### Y dos trampas del arnés, nuevas

**Medir desde quien acaba de salir da cero por RLS, no por el producto.** 012
contaba los miembros restantes de un grupo desde la sesión de quien se acababa
de ir — y esa persona ya no ve el grupo. El conteo se hace desde quien se queda.

**`\gset` es de psql y aquí no existe.** Para pasar un id de un statement al
siguiente se usa una tabla temporal, no una variable del cliente.

## Lo que encontró la primera persona que lo usó de verdad

**El QR se queda congelado cuando la pestaña pierde el foco.** Chrome frena los
`setInterval` de una pestaña en segundo plano a uno por minuto; un portátil
bloqueado los para del todo. La cuenta atrás de la wallet restaba uno por tick,
así que creía que quedaban 28 segundos cuando habían pasado tres minutos — y
enseñaba un QR caducado como si estuviera fresco.

En puerta eso sale como **`denied` / `screenshot_suspected`, `slot_delta = -6`**.
El validador tenía razón: un código de hace tres minutos ES sospechoso. El fallo
estaba en la wallet.

Es exactamente el caso de una demostración —abres el QR en el portátil, coges el
móvil para escanear— y ninguna prueba lo veía, porque **el tiempo del navegador
no se puede simular desde SQL ni desde `curl`**. La bitácora de `checkins` sí lo
guardaba: tres escaneos donde debería haber dos, y el primero denegado.

> Una cuenta atrás que resta ticks está midiendo cuántas veces se ejecutó el
> temporizador, no cuánto tiempo pasó. Son la misma cosa solo mientras el
> navegador coopera. Se calcula contra el reloj.

## Lo que ninguna de estas suites puede encontrar

Se descubrió abriendo la aplicación en un navegador, después de que las 229
comprobaciones estuvieran en verde y el despliegue funcionara.

**Las Edge Functions no tenían CORS.** Ninguna de las tres respondía al
`OPTIONS` de preflight: devolvían 405 y cero cabeceras. Desde el navegador, eso
significa que **la petición no llega a salir** — el POST muere antes de
existir.

Los síntomas no se parecían entre sí: «el QR no carga» y «el botón de pagar no
hace nada». Misma causa.

Y lo importante para estas suites:

> **Verificar por HTTP no es verificar desde el navegador.** `curl` no hace
> preflight y no tiene política de mismo origen. Las funciones respondían 200 a
> todo lo que les pedí desde la terminal — incluidas las 17 comprobaciones de
> `005_qr_token.mjs` y las 25 de `006_qr_validate.mjs`, todas en verde, todas
> ciegas a esto.

Una comprobación que lo habría detectado es de una línea:

```bash
curl -sS -o /dev/null -X OPTIONS "$B/functions/v1/qr-token"   -H "Origin: https://cualquier-cosa"   -H "Access-Control-Request-Method: POST" -w "%{http_code}"   # tiene que dar 204, no 405
```

Está añadida a los dos `.mjs`. Pero la lección de fondo no es esa comprobación:
es que **una capa entera del sistema —el navegador— no estaba cubierta por
ninguna prueba**, y se cubrió sola el día que alguien abrió la app.
