# 010 — Grafo social: amistad, bloqueo y modo ninja efectivo

**Mundo:** Fan · **Pantalla del mockup:** «Perfil» (parcial) ·
**Depende de:** 001 · **Bloquea a:** 011, 012

Primer feature de Fase 1.5. Es a la capa social lo que 001 fue a todo lo demás: no
enseña casi nada y sin él no se puede enseñar nada.

El acta del 4 de septiembre pide que Feventi se sienta como una red social de
eventos. Una red social empieza por saber **quién es amigo de quién** y, antes de la
primera señal, por saber **quién no quiere que se sepa**.

---

## Objetivo

Que un fan pueda tener amigos en Feventi, y que el sistema sepa —**en la base de
datos, no en la interfaz**— a quién puede mostrarle actividad de quién.

## No objetivos

- Mostrar señales sociales en eventos: eso es **011**. Aquí no se muestra ninguna.
- Comprar en grupo: **012**.
- Comunidades, muros, publicaciones, hashtags: **D-42**, Fase 3.
- Importar contactos del teléfono, Google o Instagram: **D-38**. Se busca por correo
  exacto o por código de usuario, y nada más.
- Notificar la solicitud por correo o push: **D-11**, no existe centro de
  notificaciones. La solicitud se ve al entrar a `/amigos`.
- Sugerencias de amistad («personas que quizá conozcas»): sin grafo poblado no hay
  qué sugerir, y una sugerencia mal calculada es una fuga de datos disfrazada de
  función.

---

## Por qué el modo ninja va **antes** que la primera señal

`profiles.ninja_mode` existe desde 001 y hoy no hace nada, porque no hay actividad
social que ocultar. La tentación es construir 011 y añadir el filtro después.

No. Una señal social que se filtra una vez **ya no se puede retirar**: quien la vio,
la vio. El orden 010 → 011 no es prolijidad, es la única secuencia en la que el
error caro es imposible.

---

## Modelo de datos

### `friend_edges`

Una sola tabla para solicitud y amistad, porque son el mismo hecho en dos momentos.

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `requester_id` | uuid not null → profiles | quien pidió |
| `addressee_id` | uuid not null → profiles | quien recibe |
| `status` | `friend_edge_status` not null default `pending` | `pending` · `accepted` |
| `created_at` | timestamptz not null default now() | |
| `responded_at` | timestamptz | null mientras `pending` |

```sql
alter table public.friend_edges
  add constraint friend_edges_no_self check (requester_id <> addressee_id);

-- Una sola relación entre dos personas, en el sentido que sea. Este índice es el
-- árbitro: si A pide a B y B pide a A a la vez, la segunda falla. Mismo patrón
-- que support_cases_one_recovery_per_order (009).
create unique index friend_edges_one_per_pair
  on public.friend_edges (least(requester_id, addressee_id),
                          greatest(requester_id, addressee_id));
```

La amistad **es simétrica** (D-39) pero la fila **es direccional**, y las dos cosas
son ciertas a la vez: importa quién pidió (para saber quién puede aceptar) y deja de
importar después (para responder «somos amigos»). Guardar dos filas simétricas y
mantenerlas sincronizadas es exactamente el bug que este índice hace imposible.

### `blocks`

Tabla aparte, y esto no es sobre-diseño:

| col | tipo | nota |
|---|---|---|
| `blocker_id` | uuid not null → profiles | |
| `blocked_id` | uuid not null → profiles | |
| `created_at` | timestamptz not null default now() | |
| | PK `(blocker_id, blocked_id)` | |

Tres razones por las que no es un `status` más de `friend_edges`:

1. Bloquear **sobrevive** a dejar de ser amigos. Si fuera un estado de la arista, dar
   de baja la amistad borraría el bloqueo.
2. Bloquear es **direccional de verdad**: A bloquea a B sin que B lo sepa ni pueda
   deshacerlo. La amistad no.
3. Con un solo enum, «desbloquear» y «dejar de ser amigos» acaban siendo la misma
   operación. Son dos cosas distintas con dos consecuencias distintas.

`blocks` **no es visible para el bloqueado**: solo su dueño lee sus filas. Un bloqueo
que se puede detectar no protege de nada.

---

## Las reglas, en la base de datos

### `private.are_friends(a uuid, b uuid) → boolean`

`security definer`, `stable`, `search_path` fijo (Art. 9.2). Cierto solo si existe
una arista `accepted` entre los dos, en cualquier sentido, **y no existe bloqueo en
ninguna dirección**.

### `private.can_see_activity_of(viewer uuid, subject uuid) → boolean`

La única función que 011 tiene permitido llamar. Cierta si, todo a la vez:

1. `are_friends(viewer, subject)`;
2. `subject` **no** tiene `ninja_mode = true`.

El modo ninja se evalúa **sobre el sujeto, no sobre el observador** (D-43): esconderse
no es cegarse. Quien activa ninja deja de emitir señales y sigue viendo las de sus
amigos. Es asimétrico a propósito — castigar la privacidad con menos producto es la
forma más segura de que nadie la use.

> El modo ninja **no** afecta a puerta, antifraude, auditoría ni soporte (Art. 7.3).
> No es invisibilidad: es no aparecer en el conteo de un amigo.

### RPC `request_friendship(target_email text) → uuid`

`security definer`. Busca por correo **exacto** (D-38: sin búsqueda parcial, que es un
directorio de usuarios disfrazado de buscador). Falla, con motivo distinguible
internamente, si:

- el objetivo es uno mismo;
- ya existe arista entre ambos;
- cualquiera de los dos bloqueó al otro;
- no hay nadie con ese correo.

**Hacia afuera, los cuatro casos devuelven el mismo mensaje.** Distinguirlos
convierte el formulario en un oráculo de «¿está esta persona registrada en Feventi?»,
que es una fuga de datos personales con formulario bonito.

### RPC `respond_friendship(edge_id uuid, accept boolean)`

`security definer`. Una transición de estado va en una RPC, no en una política.
Bloquea la fila con `select … for update`, comprueba que `auth.uid() = addressee_id`
y que el estado de origen es `pending`, y solo entonces pasa a `accepted` o borra la
fila.

Aceptar dos veces desde dos pestañas tiene que dar un resultado, no dos.

### RLS

| tabla | select | insert | update | delete |
|---|---|---|---|---|
| `friend_edges` | soy `requester` o `addressee` | ninguna (solo la RPC) | ninguna (solo la RPC) | soy cualquiera de los dos — dejar de ser amigos borra de verdad |
| `blocks` | soy `blocker` | soy `blocker` | ninguna | soy `blocker` |

Una política por operación y rol, con `(select auth.uid())` envuelto.

`friend_edges` **no es append-only**: el Art. 8 enumera lo que se audita —checkins,
decisiones de Admin, titularidad, dinero— y una amistad no está ahí. Que «dejar de
ser amigos» borre la fila es el comportamiento correcto en materia de datos
personales, no una laxitud.

---

## Pantallas

### `/amigos` — mundo Fan (Art. 10)

Tres bloques, en este orden:

1. **Solicitudes recibidas** — arriba porque es lo accionable. Cada una con Aceptar y
   Rechazar. Si no hay, el bloque no aparece.
2. **Mis amigos** — nombre, avatar y un menú con «Dejar de ser amigos» y «Bloquear».
3. **Añadir** — un campo de correo y un botón. Un solo mensaje de resultado
   («Si esa persona usa Feventi, le llegará tu solicitud»), sea cual sea el caso, por
   lo dicho arriba sobre el oráculo.

Vacío es el estado normal al principio y tiene que explicarse: *«Todavía no tienes
amigos en Feventi. Cuando los tengas, verás a cuáles de tus eventos van.»*

### `/perfil` — mínimo

Esta feature crea la ruta con lo justo:

- nombre, correo, DNI enmascarado (`dni_last4`);
- **el interruptor de modo ninja**, con la frase de D-43 debajo:
  *«Nadie ve a qué eventos vas. Tú sigues viendo a tus amigos.»*
- lista de personas bloqueadas, con desbloquear.

Sin edición de perfil, sin avatar subido, sin preferencias de notificación (D-11).

---

## Criterios de aceptación

| # | Criterio | Cómo se verifica |
|---|---|---|
| AC-01 | A pide amistad a B por correo exacto: se crea una arista `pending` | RPC + select |
| AC-02 | A pide amistad a un correo inexistente: el mensaje es **idéntico** al de «ya existe relación» | dos llamadas, comparar carácter a carácter |
| AC-03 | A pide amistad a A: falla | RPC |
| AC-04 | A pide a B mientras B pide a A: la segunda falla por `friend_edges_one_per_pair` | dos inserciones |
| AC-05 | Solo B puede aceptar la solicitud A→B; si A la acepta, falla | RPC como cada uno |
| AC-06 | Aceptar dos veces en paralelo deja una sola arista `accepted` | dos llamadas concurrentes por HTTP |
| AC-07 | C, ajeno a la relación, no ve la arista A↔B | select como C → 0 filas |
| AC-08 | `are_friends(A,B)` = `are_friends(B,A)` | select |
| AC-09 | A bloquea a B: `are_friends` pasa a falso sin borrar la arista | select antes y después |
| AC-10 | B no puede saber que A lo bloqueó: `blocks` devuelve 0 filas para B | select como B |
| AC-11 | A bloquea a B y luego deja de ser su amigo: el bloqueo **sigue** | delete de la arista, luego select en `blocks` |
| AC-12 | B con `ninja_mode = true`: `can_see_activity_of(A,B)` es falso | select |
| AC-13 | B con `ninja_mode = true`: `can_see_activity_of(B,A)` sigue siendo **cierto** (D-43) | select |
| AC-14 | `ninja_mode` no afecta a `gate_checkin` ni a `gate_find_by_dni` (Art. 7.3) | correr el test de 006 con el fan en ninja |
| AC-15 | Ningún cliente puede hacer `update` directo de `friend_edges.status` | update como `authenticated` → 0 filas |
| AC-16 | `get_advisors(security)` sin hallazgos nuevos | MCP |
| AC-17 | `/amigos` y `/perfil` legibles a 390 px | navegador |
| AC-18 | El interruptor de ninja persiste tras recargar | navegador |

## Riesgo conocido, anotado a propósito

Con **un solo amigo**, cualquier señal futura de 011 lo identifica sin ambigüedad
(D-41). No se mitiga con un umbral porque el mockup muestra explícitamente «1 amigo
ya tiene entrada», y el mockup manda.

Se acepta porque la amistad es mutua, consentida y revocable, y porque D-40 limita lo
revelado al hecho de ir, nunca a la zona ni al precio. Queda escrito aquí para que la
próxima persona sepa que fue una decisión y no un descuido.
