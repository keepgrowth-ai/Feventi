# 013 — Puntos por asistencia en la wallet

**Mundo:** Fan · **Pantalla del mockup:** «Wallet» (L338) y «Validador» (L685) ·
**Depende de:** 005, 006 · **Bloquea a:** —

El acta §5 pide que *«la wallet muestre que asistir, comprar o participar puede
generar puntos, beneficios o valor acumulado»*, y §10 lo cierra: el usuario
*«vuelve después del evento por recuerdos, puntos o álbum»*.

El mockup ya lo tiene en los dos extremos del recorrido:

```
Wallet      1 240 puntos
Validador   Titular verificado con DNI · +50 puntos por check-in
```

---

## Objetivo

Que asistir de verdad a un evento sume puntos, y que el fan los vea en su wallet.

## No objetivos

- **Canjear.** D-44: los puntos se acumulan y se muestran; no compran nada, no
  se convierten en dinero, no vencen. Sin catálogo de premios.
- FanPass: **D-29**, Fase 3. El chip sigue apareciendo solo si existe la
  membresía.
- Puntos por comprar, por invitar o por participar: **D-45**. Ver abajo.
- Saldo monetario: **D-28**, y el «Saldo S/ 180» del mockup de checkout sigue
  siendo decorativo.
- Ranking, niveles o insignias: nadie los ha pedido.

---

## Por qué por asistir y no por comprar (D-45)

El mockup lo dice en la pantalla de puerta —«+50 puntos por check-in»— y hay una
razón de producto detrás:

**Comprar es reversible; entrar no.** Si los puntos se dieran al pagar, una
compra seguida de un reembolso los deja en la cuenta, y habría que escribir la
resta. Con el check-in no hay nada que restar: quien entró, entró, y esa fila es
append-only por el Art. 8.1.

Es también lo que hace que el número signifique algo: mide asistencia real, no
intención de compra.

---

## Modelo de datos

### `point_ledger`

Un libro mayor, no un contador. Nunca hay una columna `profiles.points` que
alguien pueda «ajustar»: el saldo se **calcula** sumando asientos.

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `user_id` | uuid → profiles | on delete cascade |
| `kind` | `point_reason` | por ahora solo `checkin` |
| `points` | integer not null | positivo; el enum decide el porqué |
| `event_id` | uuid → events | de dónde salió |
| `checkin_id` | uuid → checkins | el asiento que lo originó |
| `created_at` | timestamptz | |

**Append-only**, igual que `checkins`. Sin `update` ni `delete` para nadie: un
saldo que se puede editar deja de ser una bitácora.

```sql
-- El árbitro contra el doble abono. Un ticket que se escanea dos veces produce
-- un segundo `checkin` (con result = already_used), y sin este índice el
-- segundo también sumaría.
create unique index point_ledger_one_per_checkin
  on public.point_ledger (checkin_id) where checkin_id is not null;
```

### Cómo se otorgan

Un **trigger** sobre `checkins`, no una modificación de `gate_checkin`.

`gate_checkin` es la función más verificada del proyecto y la que decide si
alguien entra al evento. Meterle una escritura de puntos añade una forma de
fallar a la operación que **no puede fallar** en la puerta. Un trigger `after
insert` corre en la misma transacción —así que el punto y el ingreso son
atómicos— sin tocar una línea de la decisión.

Solo dispara con `result = 'allowed'`. `manual_review` no suma: si el modo DNI
acaba siendo un ingreso legítimo, lo confirma un humano, y esa corrección es
Fase 2.

### `v_my_points`

Una fila: `total`. El desglose se lee del propio `point_ledger`, que ya tiene
RLS por dueño.

---

## Pantallas

- **Wallet**: el total, arriba, como en el mockup. Si es cero no se pinta nada:
  «0 puntos» le dice al fan que la función existe y que él no la ha usado, que
  es la peor combinación.
- **Validador**: la pantalla de ACCESO PERMITIDO añade «+50 puntos» debajo del
  nombre, como en el mockup L685. Es la línea que convierte un control de acceso
  en un momento agradable, y es gratis: el dato ya viajó.

---

## Criterios de aceptación

| # | Criterio | Cómo se verifica |
|---|---|---|
| AC-01 | Un check-in `allowed` crea un asiento de 50 puntos | SQL |
| AC-02 | Un check-in `already_used` **no** crea asiento | SQL |
| AC-03 | Un check-in `denied` no crea asiento | SQL |
| AC-04 | Un check-in `manual_review` no crea asiento | SQL |
| AC-05 | El asiento se le abona al **dueño del ticket**, no al staff que escanea | SQL |
| AC-06 | Dos asientos sobre el mismo `checkin_id` fallan por el índice único | SQL |
| AC-07 | `v_my_points` suma solo lo mío | SQL |
| AC-08 | Nadie ve los asientos de otro | SQL |
| AC-09 | Nadie puede insertar, actualizar ni borrar asientos a mano (Art. 8.1) | SQL |
| AC-10 | `anon` no lee nada de esto | SQL |
| AC-11 | El punto y el check-in son atómicos: si el checkin revierte, el punto también | SQL |
| AC-12 | La wallet muestra el total, y nada si es cero | navegador |
| AC-13 | El validador muestra «+50 puntos» solo en ACCESO PERMITIDO | navegador |
