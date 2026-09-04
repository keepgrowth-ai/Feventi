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
