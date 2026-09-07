# 011 — Señales sociales

**Mundo:** Público + Fan · **Pantalla del mockup:** «Catálogo» (L92) y «Evento» (L153) ·
**Depende de:** 010, 003, 002 · **Bloquea a:** —

El efecto wow del acta §6: *«una persona entra a Feventi, ve un evento que le
interesa y descubre que amigos o personas de su comunidad también irán»*.

El mockup lo tiene dibujado desde el principio, literal:

```
2 amigos quieren ir · 1 amigo ya tiene entrada
Solo ves señales de quienes no están en modo ninja.
```

---

## Objetivo

Que en la ficha de un evento y en la tarjeta del catálogo aparezca **cuántos
amigos van y cuántos quieren ir**, y que el fan pueda declarar su propio interés.

## No objetivos

- ~~**Nombres.**~~ **Corregido: la señal SÍ dice quiénes** (D-46, migración
  `0062`). Este no-objetivo se escribió apoyándose en que el mockup enseña
  conteos, y el mockup manda. Pero el mockup se dibujó antes del acta, y el acta
  pide que la app *se sienta* como una red social (§4, §6). Se muestran hasta
  **dos nombres de pila** y el resto como «y N más».
- Comunidades y señales de gente que no es amiga: **D-42**, Fase 3.
- Recomendaciones o ranking por actividad social: sin grafo poblado no hay señal
  que rankear, y un algoritmo mal calibrado es una fuga de datos con apariencia
  de función.
- Notificar «tu amigo va a ir»: **D-11**, no hay centro de notificaciones.
- Cambiar `v_event_public`. El catálogo lo lee `anon`, que por definición no
  tiene amigos.

---

## Lo que una señal revela, y lo que no (D-40)

Hoy nadie puede leer la compra de otro: es una regla del motor, no del código.
**«1 amigo ya tiene entrada» es una excepción deliberada a esa regla**, así que
se define por lo que NO dice:

| dice | nunca dice |
|---|---|
| que va, o que quiere ir | la zona |
| el número de amigos | el precio pagado |
| | cuántas entradas compró |
| | el número de orden o de ticket |
| **quiénes**, hasta dos nombres de pila (D-46) | el apellido |

Y tres condiciones que no se negocian:

1. Solo cuenta gente con **amistad mutua aceptada** (D-39). Nunca «seguidores».
2. Quien tiene `ninja_mode` **no entra en ningún conteo** (Art. 7.3, D-43).
3. El filtro se aplica en la base de datos vía `private.can_see_activity_of`, la
   misma función que 010 dejó escrita. **011 no vuelve a decidir quién ve a
   quién**: si hubiera dos sitios que lo deciden, uno de los dos se quedaría
   atrás.

### El riesgo aceptado (D-41)

Con **un solo amigo**, «1 amigo ya tiene entrada» lo identifica sin ambigüedad.
No se pone un umbral mínimo porque el mockup muestra exactamente ese caso.

Se acepta porque la amistad es mutua, consentida y revocable, y porque la tabla
de arriba limita lo revelado al hecho. Queda escrito para que la próxima persona
sepa que fue una decisión.

---

## Modelo de datos

### `event_interests`

Lo único que falta. «Ya tiene entrada» ya se puede deducir de `tickets`;
«quiere ir» no existía en ninguna parte.

| col | tipo | nota |
|---|---|---|
| `user_id` | uuid → profiles | on delete cascade |
| `event_id` | uuid → events | on delete cascade |
| `created_at` | timestamptz not null default now() | |
| | PK `(user_id, event_id)` | la PK **es** el «una vez por persona» |

Sin columna `status`: quitar el interés borra la fila. Un `interested = false`
guardaría para siempre a qué eventos dijo alguien que no, que es justo lo que
nadie pidió almacenar.

### `v_my_event_signals`

Una fila por evento donde **alguno de mis amigos visibles** va o quiere ir.

| col | nota |
|---|---|
| `event_id` | |
| `friends_going` | amigos con ticket `active` |
| `friends_interested` | amigos con fila en `event_interests` |

Un evento sin señal **no sale**. Cero no es un valor que enseñar: «0 amigos van»
es peor que no decir nada.

`security definer` por lo mismo que las vistas de 010 —lee `tickets` y
`profiles` ajenos— con el filtro por `auth.uid()` escrito en el `where`.

---

## Cómo llega a la pantalla

**El catálogo no cambia.** `v_event_public` sigue siendo lo que lee `anon`. La
pantalla pide `v_my_event_signals` **aparte**, en una sola consulta sin filtro, y
las cruza en el cliente por `event_id`.

Tres razones:

1. `anon` no tiene amigos: meter la señal en la vista pública obliga a un
   `left join` que siempre da null para la mitad del tráfico.
2. La señal es un adorno; el catálogo tiene que pintarse aunque falle.
3. El filtro «Con amigos asistiendo» del mockup se resuelve sobre la lista ya
   cargada, sin ida y vuelta.

---

## Criterios de aceptación

| # | Criterio | Cómo se verifica |
|---|---|---|
| AC-01 | Un amigo con ticket activo suma 1 a `friends_going` | SQL |
| AC-02 | Un amigo con interés suma 1 a `friends_interested` | SQL |
| AC-03 | Un **no amigo** con ticket no suma nada | SQL |
| AC-04 | Un amigo con `ninja_mode` no suma en ninguna de las dos | SQL |
| AC-05 | Un amigo que me bloqueó no suma | SQL |
| AC-06 | Mi propia entrada no me cuenta como amigo mío | SQL |
| AC-07 | Un evento sin ningún amigo **no aparece** en la vista | SQL |
| AC-08 | Un ticket `used` sigue contando como «va» — ya entró | SQL |
| AC-09 | Un ticket de una orden no pagada no cuenta (no existe el ticket) | SQL |
| AC-10 | La vista no expone `zone_id`, `face_value_cents` ni `order_id` (D-40) | inspección de columnas |
| AC-11 | Un tercero ajeno ve la vista **vacía**, aunque definer apague la RLS | SQL |
| AC-12 | Marcar interés dos veces no duplica ni falla | SQL |
| AC-13 | Nadie puede insertar interés a nombre de otro | SQL |
| AC-14 | Quitar el interés borra la fila y baja el conteo | SQL |
| AC-15 | `anon` no lee `event_interests` ni la vista | SQL |
| AC-16 | `get_advisors(security)` sin hallazgos sin decisión | MCP |
| AC-17 | La ficha del evento muestra la señal con el texto del mockup | navegador |
| AC-18 | El catálogo pinta las tarjetas aunque la consulta de señales falle | navegador |
| AC-19 | El filtro «Con amigos asistiendo» deja solo los eventos con señal | navegador |
| AC-20 | El aviso de ninja aparece junto a la señal, como en el mockup | navegador |
