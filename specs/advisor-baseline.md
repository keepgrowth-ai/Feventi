# Línea base del linter de seguridad

`mcp__supabase__get_advisors(security)` corre al cerrar cada feature (roadmap,
«definición de terminado» §2). Este archivo dice qué hallazgos están **aceptados y por
qué**, para que la comprobación sea un diff y no una lectura completa cada vez.

**Regla:** ningún hallazgo sin decisión escrita. Cualquier nivel —`ERROR` incluido—
solo cuenta como aceptado si está en una tabla de abajo con su razón. Uno que no esté
es un hallazgo nuevo y hay que resolverlo o justificarlo aquí en el mismo commit.

> La regla decía «cero `ERROR`» hasta 002. Se cambió al topar con un caso donde el
> `ERROR` **es** el diseño correcto (ver «Excepciones argumentadas»). Una regla que
> obliga a elegir entre el linter y la seguridad real está mal escrita: lo que importa
> es que ningún hallazgo quede sin mirar, no que la lista salga vacía.

Última corrida: **Fase 1.5 completa (010–013)** · seguridad 9 `ERROR`
argumentados · 1 `WARN` nuevo resuelto (`0060`).

> 009 no añade ningún `ERROR`: `v_support_queue` va con `security_invoker = true`
> y funciona. Es la diferencia con las otras seis — la RLS de `support_cases` ya
> deja ver exactamente los casos que tocan, así que la vista no necesita saltarla.
> Cuando invoker basta, se usa invoker.

## Excepciones argumentadas

| nivel | hallazgo | por qué se mantiene |
|---|---|---|
| **ERROR** | `security_definer_view` en `public.v_event_public` | **Es el diseño, y la alternativa es peor.** La vista corre con los privilegios de su dueño y por eso salta la RLS: es lo que permite que `anon` lea el catálogo **sin** tener acceso a `events`, `price_tiers`, `price_phases`, `zones` ni `venues`. La otra opción es `security_invoker = true` más políticas de `anon` en esas cinco tablas — y entonces `anon` las consulta **directamente** por PostgREST, con los filtros y joins que quiera, y la regla de visibilidad queda repartida en cinco sitios en lugar de uno. Eso es más superficie y más difícil de auditar, y contradice **002/AC-13**. Lo que sí exige esta decisión es que el `where` de la vista sea intocable sin pensar: está cubierto por siete comprobaciones de 003 (una por estado y visibilidad) más las de 002, y la migración lo dice en un comentario. |

| **ERROR** | `security_definer_view` en `public.v_my_tickets` | **Misma razón, filtro más estrecho.** La wallet hace join con `events`, `zones` y `venues`, que están limitadas al organizador: con `security_invoker = true` el fan veía sus tickets y **cero** eventos, así que la vista salía vacía. La alternativa era dar a `authenticated` políticas de lectura sobre esas tres tablas para los eventos donde tenga un ticket — cuatro políticas más, y la fila entera del evento abierta a cualquiera con una entrada. El filtro de la vista es `t.owner_id = auth.uid()`: una línea, trivial de auditar, y más estrecha que la de `v_event_public`. Cubierto por las comprobaciones de 005. |

| **ERROR** | `security_definer_view` en `public.v_my_gate_events` y `public.v_gate_stats` | **La tercera vez que aparece el mismo patrón, y por la misma razón.** El staff de puerta necesita el título del evento, el venue y el nombre de su zona; esas tres tablas están limitadas al organizador, así que con `security_invoker = true` las vistas salen vacías. La alternativa es dar a `authenticated` políticas de lectura sobre `events`, `venues` y `zones` para los eventos donde tenga una asignación — y entonces cualquiera que sea staff de un evento lee la fila **entera**, campos comerciales incluidos, que es justo lo que el Art. 7.5 no le corresponde. El filtro es `es.profile_id = auth.uid() and es.revoked_at is null`: dos condiciones en una línea, y revocar corta el acceso en la consulta siguiente. Cubierto por 006/AC-04, AC-06 y AC-07. |

| **ERROR** | `security_definer_view` en `public.v_event_sales` y `public.v_event_phase_sales` | **Aquí el spec pedía lo contrario, y se documentó por qué no.** 008/AC-04 dice `security_invoker = true`; con invoker las dos vistas salen EN CERO, porque agregan `orders`, `order_items`, `payments` y `tickets` y la RLS de esas cuatro no deja al organizador ni una fila. Para que invoker funcionara habría que darle políticas de lectura sobre ellas — que es **exactamente lo que 008/AC-02 prohíbe**. Los dos criterios no pueden cumplirse a la vez: gana AC-02, porque es la regla de privacidad (Art. 7.5) y AC-04 solo era el medio que se supuso para llegar a ella. El filtro es `e.organizer_id = any (private.auth_organizer_ids())`, y está verificado en las dos direcciones por 008/AC-01 … AC-01d y AC-02 … AC-02d.

| **ERROR** | `security_definer_view` en `public.v_my_friends` y `public.v_my_friend_requests` | **La quinta vez que aparece el patrón, y esta vez el dato revelado es de otra persona.** Las dos vistas hacen join con `profiles`, cuya política es solo para su dueño (0007): con `security_invoker = true` salían VACÍAS — 010/AC-07c lo destapó. La alternativa era añadir a `profiles` una rama «o si somos amigos», y eso abre la fila **entera**: teléfono, `dni_last4`, `dni_verified_at` y `ninja_mode`. Que un amigo pueda leer `ninja_mode` rompe la función entera: el front sabría quién se esconde. La vista emite **dos columnas** —`full_name` y `avatar_url`— de gente con una arista `accepted`, y nada más. Lo que esta decisión exige a cambio está escrito en `0054`: como definer apaga la RLS de `friend_edges`, el filtro `(e.requester_id = auth.uid() or e.addressee_id = auth.uid())` es la **única** cosa que separa la lista de amigos del grafo social completo de la plataforma. Por eso tiene comprobación propia, 010/AC-07d, además de AC-07c, AC-10c y AC-10d. |

| **ERROR** | `security_definer_view` en `public.v_my_event_signals` | **La sexta, y la que más revela: datos de compra de otra persona.** «1 amigo ya tiene entrada» es, técnicamente, una excepción deliberada a la regla de que nadie lee la compra de otro. La vista lee `tickets` y `event_interests` ajenos, y ninguna política me deja verlos — que es justo lo que la hace una revelación **deliberada** y no un accidente. Se limita por lo que emite: **tres columnas, dos de ellas conteos** (D-40). Nunca zona, precio, cantidad, id de orden ni quién. El filtro por `auth.uid()` está escrito dos veces en el `where` de la CTE `amigos`, y el ninja **no se comprueba aquí**: se delega en `private.can_see_activity_of`, para que no haya dos sitios decidiendo quién ve a quién. Cubierto por 011/AC-03, AC-04, AC-05, AC-06, AC-10 y AC-11 — las cuatro primeras miran el MISMO número, así que si la vista se abre, sube. |

## Aceptados — rendimiento

| nivel | hallazgo | por qué se acepta |
|---|---|---|
| INFO | `unindexed_foreign_keys` en columnas de auditoría (`*.created_by`, `organizers.approved_by`, `organizer_members.invited_by`, `event_review_notes.actor_id`, `ticket_events.actor_id`, `ticket_events.corrects_id`, `tickets.original_owner_id`) | **YAGNI.** Son columnas de auditoría: nadie consulta «qué organizadores aprobó tal Admin». Un índice ahí solo aceleraría el chequeo de FK al borrar un `profile`, sobre tablas que van a tener cientos de filas, no millones. Se indexa el día que exista una pantalla que filtre por ellas. |
| INFO | `unindexed_foreign_keys` en las FK compuestas de `0045` (`price_tiers (event_id, zone_id)`, `price_tiers (event_id, phase_id)`, `tickets (event_id, zone_id)`) | **Se paga solo al borrar una zona o una fase**, que es una operación de configuración, no de tráfico. Y no van a ciegas: `price_tiers_event_idx` y `tickets_event_idx` empiezan por `event_id`, así que el chequeo se acota al evento antes de mirar filas. Un índice exacto por cada FK compuesta serían tres índices más que se escriben en cada venta para acelerar un borrado que casi no ocurre. |
| INFO | `unindexed_foreign_keys` en `checkins.event_staff_id` y `event_staff.created_by` / `revoked_by` / `zone_id` | Mismo criterio que las columnas de auditoría de arriba: nadie consulta «qué escaneos hizo tal asignación». `checkins` ya tiene tres índices por los caminos que sí se usan —evento+puerta, ticket y staff—, y añadir un cuarto encarece el `insert` de cada escaneo, que es justo lo que tiene que ir rápido en la puerta. |
| INFO | `unindexed_foreign_keys` en `price_tiers (zone_id, segment_id)`, `seats (zone_id, …)` y `zone_segments (zone_id, …)` | **Ya están cubiertos.** Postgres usa un índice compuesto para una búsqueda por su primera columna, y existe un índice que empieza por `zone_id` en las tres tablas. El linter no comprueba prefijos. El que **sí** faltaba —`price_tiers (phase_id)`— se añadió en `0026`. |
| INFO | `unused_index` en `events_search_idx`, `tickets_holder_dni_idx` y `checkins_event_result_idx` | Los tres tienen su consumidor escrito y probado: el buscador de 002, el modo DNI de 006 y el dashboard de 008. Salen «sin usar» porque el volumen de datos es tan pequeño que el planner prefiere un seq scan — no porque nadie los consulte. Se revisan con tráfico real. |
| INFO | `unused_index` en `organizers_status_idx`, `venues_city_idx`, `events_public_idx`, `seats_segment_idx`, `zone_segments_zone_idx` | Están sin usar porque **no hay datos**. Cada uno tiene su caso: `organizers_status` y `venues_city` los usan las pantallas de 007, `events_public_idx` es el índice parcial del catálogo de 002 y `seats_segment_idx` lo usará el selector de asientos de 004. Se revisan con tráfico real; el que siga sin usarse, se borra. |

## Aceptados — seguridad

| nivel | hallazgo | por qué se acepta |
|---|---|---|
| INFO | `rls_enabled_no_policy` en `public.profile_identity` | **Es el diseño**, Art. 2.6 y 7.1. RLS activa y cero políticas es la forma de decir «nadie pasa». Solo `service_role` y las funciones `security definer` de nominación y puerta. Añadirle una política sería el bug. |
| WARN | `authenticated_security_definer_function_executable` en las RPC de `public`: las 7 de 001 (`create_organizer`, `add`/`revoke_organizer_member`, `approve_organizer`, `set_organizer_status`, `set_own_dni`, `verify_dni`) y las 11 de 007 (`create_event`, `submit_event`, `approve`/`reject`/`request_event_info`, `set_event_checklist`, `publish`/`pause`/`resume`/`cancel_event`, `set_event_featured`) | **Es la superficie de RPC del producto**, y `security definer` es justo lo que las hace útiles: existen para hacer lo que una política no puede (fijar el `status` en el servidor, escribir dos filas juntas, hashear con un pepper que el llamante no ve). Cada una comprueba autorización en su propio cuerpo, y esa comprobación está cubierta por pruebas: 001/AC-17, AC-20, AC-23, AC-24, AC-07b y 007/AC-05, AC-06, AC-07, AC-12. |
| WARN | `anon_security_definer_function_executable` en `get_public_event` y `active_phase_id` | **Son la superficie pública de 003, y `anon` las necesita.** `get_public_event(slug)` es `security definer` a propósito: exige el slug, y por eso un evento `unlisted` se abre por su enlace **sin** poder enumerarse — algo que una vista listable no puede lograr. `active_phase_id` devuelve el id de la fase activa de un evento, que es información pública del catálogo. Ninguna de las dos lee nada que no esté ya en la pantalla. |
| WARN | `authenticated_security_definer_function_executable` en las RPC de 004 (`reserve_order`, `set_item_attendee`, `start_payment`, `fail_payment`) | **Es la superficie del checkout.** `reserve_order` existe precisamente para hacer lo que una política no puede: bloquear los tiers en orden, congelar el precio, subir el contador y calcular el cargo, todo en una transacción. `confirm_payment` **no** está en esta lista porque está revocada a `authenticated`: es del webhook (AC-29), y una prueba lo verifica. |
| WARN | `authenticated_security_definer_function_executable` en las RPC de 009 (`open_support_case`, `post_support_message`, `manage_support_case`, `admin_ticket_action`) | **Es la superficie del soporte**, y las cuatro comprueban autorización en su cuerpo, verificado por 009: `open_support_case` exige relación con el objeto (AC-04, AC-05) y rellena el contexto en el servidor (AC-03); `post_support_message` bloquea la nota interna a quien no es Admin (AC-16); las otras dos empiezan por `auth_is_admin()` (AC-15, AC-19). `security definer` es justo lo que las hace útiles: escriben en tablas donde el cliente no tiene `insert` —`support_cases` y `support_messages` son append-only— y hacen dos escrituras juntas. |
| WARN | `authenticated_security_definer_function_executable` en `gate_find_by_dni` | **Es la superficie del modo DNI** (D-03), y `security definer` es lo que la hace posible: hashea con un pepper que el llamante no ve, sobre columnas que el staff no puede leer. Comprueba `event_staff` **antes** de hashear — ese orden es la comprobación, no un detalle: al revés sería un oráculo para confirmar si una persona concreta va a un evento concreto. Verificado por 006 en las dos direcciones: el staff encuentra la entrada, el fan recibe 42501. `gate_checkin` **no** está en esta lista porque está revocada a `authenticated`: es solo de `service_role`, y una comprobación lo verifica. |
| WARN | `authenticated_security_definer_function_executable` en `generate_seats` | Escribe cientos de asientos en un statement y comprueba `auth_organizer_ids()` en su cuerpo — verificado por 003/T-11b, que confirma el rechazo sobre una zona ajena y sobre una zona de pie. |
| WARN | `authenticated_security_definer_function_executable` en las RPC de 010 (`request_friendship`, `respond_friendship`, `block_user`) | **Es la superficie del grafo social**, y las tres comprueban autorización en su cuerpo: `request_friendship` resuelve un correo que el llamante no puede leer y devuelve **el mismo error en los cuatro casos de fallo** (AC-02), `respond_friendship` exige ser el destinatario y bloquea la fila antes de mirar el estado (AC-05a, AC-05c), `block_user` es idempotente y no deja bloquearse a uno mismo. `security definer` es lo que las hace posibles: las tres escriben en tablas donde `authenticated` no tiene `insert` ni `update` (AC-15a, AC-15b). |
| WARN | `authenticated_security_definer_function_executable` en las RPC de 012 (`create_purchase_group`, `add_group_member`, `leave_purchase_group`, `lock_purchase_group`) | **Es la superficie de la compra grupal**, y las cuatro toman `select … for update` sobre el grupo **antes** de mirar su estado: dos personas decidiendo a la vez es un caso real (012/AC-04, AC-13). `add_group_member` exige además `private.are_friends` — sin eso acepta cualquier uuid y se convierte en la forma de meter a alguien en una compra que no pidió, verificado por AC-03. `lock_purchase_group` comprueba que la orden sea del llamante, del mismo evento y con tantos ítems como miembros (AC-10, AC-11): es el todo-o-nada del Art. 11 escrito como una comparación. Las cuatro escriben en tablas donde `authenticated` no tiene `insert` ni `update` (AC-18). |
| WARN | `auth_leaked_password_protection` | **Bloqueado por plan, no por olvido.** El chequeo contra HaveIBeenPwned es **Pro o superior**, y la organización `Keepgrowth AI` está en **free**: el interruptor no existe todavía. Mitigación disponible en free, en Authentication → Sign In / Providers → Email: subir *minimum password length* a 12 y exigir minúsculas + mayúsculas + dígitos. No es equivalente —una contraseña filtrada puede ser larga y variada— así que el chequeo real queda como requisito de producción junto al Art. 13. Ver **D-50**. |

## Resueltos, para que no vuelvan

| hallazgo | cómo se resolvió |
|---|---|
| `rls_disabled_in_public` en `public._probe_defaults` | tabla de prueba de los privilegios por defecto, ya borrada. Recordatorio: una tabla de sonda se borra en el mismo statement que la crea. |
| `anon_security_definer_function_executable` en `handle_new_user()` | movida a `private` y `revoke execute` (migración `0010`). Era una función de trigger publicada como `/rest/v1/rpc/handle_new_user`. |
| Los helpers `auth_*` expuestos como RPC | movidos a `private` (migración `0010`). Las políticas los resuelven por OID, así que `alter function ... set schema` no las rompe. |
| `multiple_permissive_policies` en las cuatro tablas de 001 | consolidadas a **una política de SELECT por tabla** con `OR` (migración `0011`). Había dos permisivas por tabla —dueño y Admin— y Postgres evaluaba las dos en cada consulta, ejecutando `auth_is_admin()` también para los fans, que son el tráfico. |
| `function_search_path_mutable` en `private.checkin_points` | `set search_path = ''` en `0060`. La función es `immutable` y devuelve un literal, así que no había nada que secuestrar — pero la regla no es «cuando importe»: el día que alguien le meta una consulta dentro, nadie vuelve a mirar la cabecera. |
| `anon_security_definer_function_executable` en las RPC de 010 | `revoke execute … from public, anon` en `0055`. Ver la lección de abajo: conceder no quita lo que `PUBLIC` trae de fábrica. Las RPC de 012 ya nacieron con su `revoke` en la misma migración. |
| `infinite recursion detected in policy for relation "group_members"` | La política de `group_members` consultaba `group_members`. Resuelto en `0059` con `private.auth_group_ids()`, el mismo patrón de array que `auth_organizer_ids` desde `0004`. **El linter no lo ve**: solo aparece al leer la tabla. |
| `multiple_permissive_policies` en `venues` | la política de escritura era `for all`, y **`for all` incluye SELECT**, así que se solapaba con la de lectura. Separada en insert/update/delete (migración `0018`). La convención dice «una política por OPERACIÓN», y `for all` son cuatro. |

## Lo que el linter no ve

Encontrado a mano, y por eso vale anotarlo:

- **`TRUNCATE` concedido a `anon`.** Los privilegios por defecto de Supabase dan `ALL`
  sobre las tablas de `public`, y `ALL` incluye `TRUNCATE`, que **no está sujeto a
  RLS**. Cerrado en `0009` y cubierto por **AC-29**. El linter no lo reporta.
- **`revoke select (col)` que no hace nada** porque existe un `grant select` de tabla.
  Silencioso: no da error ni aviso, simplemente no protege. Cubierto por **001/AC-10**.
- **Una función que crea una tabla temporal no es reentrante.** `reserve_order` lo era
  hasta `0039`: llamarla dos veces en la misma transacción reventaba con
  `relation "_items" already exists`. Por PostgREST cada RPC es su propia transacción,
  así que el linter no lo ve y producción no lo habría visto — hasta el día en que otra
  función la llamara dos veces. Lo destapó la suite al reservar dos veces.
- **Una FK simple junto a una columna denormalizada no obliga a nada.** `price_tiers`
  y `tickets` llevan `event_id` **y** `zone_id`; nada impedía que la zona fuera de otro
  evento. Cerrado en `0045` con FK compuestas. Lo destapó una semilla que reusó un uuid,
  y el síntoma fue un error de aforo que hablaba de la capacidad de otro evento.
- **Una comprobación que verifica QUE algo falla, y no POR QUÉ, no prueba nada.**
  `gate_find_by_dni` llamaba a una función inexistente y la suite daba verde: la
  comprobación esperaba un fallo y lo hubo, por el motivo equivocado. Cerrado en `0046`,
  y la comprobación nueva pide el camino feliz. El linter no ve esto y las pruebas
  tampoco, salvo que se escriban pidiendo el éxito.
- **`security definer` en una vista NO cubre el `EXECUTE` de las funciones que llama.**
  Cubre las tablas; el permiso de las funciones se comprueba contra el rol que consulta.
  Costó un `42501` en `0025` (`total_with_charge` para `anon`) y **otra vez** en `0047`
  (`order_commission_cents` para `authenticated`). Dos veces la misma lección: definer no
  es un pase general.
- **Un mensaje de constraint no es un mensaje de producto.** El perdedor de la carrera
  por un asiento recibía `duplicate key value violates unique constraint`. La garantía
  era correcta y el texto inservible. Corregido en `0037`; el linter no opina de copy.
- **Una columna sensible en una tabla NUEVA vuelve a estar expuesta**, aunque la misma
  clase de dato ya se hubiera cerrado en otra. 001 escondió `profiles.dni_hash`; 004
  creó `order_items.attendee_dni_hash` y `tickets.holder_dni_hash` legibles. El linter
  no sabe qué columnas son sensibles, así que esto solo lo encuentra una prueba de
  extremo a extremo o una revisión. Cerrado en `0040`, con su propia comprobación en la
  suite para que un `grant select` posterior no lo reabra en silencio.
- **Una vista `security_invoker = false` salta la RLS**, así que su `where` es la única
  protección que queda. El linter no dice nada sobre lo que filtra. `v_event_public` es
  la única así, y sus condiciones están cubiertas por siete comprobaciones de 003, una
  por estado y visibilidad.
- **Un `grant execute … to authenticated` no quita el `execute` de `PUBLIC`.** Las tres
  RPC de 010 nacieron ejecutables por `anon` porque solo se concedió, no se revocó. Se
  ve en la ACL: las de Fase 1 llevan `postgres=X | authenticated=X | service_role=X`;
  las nuevas llevaban además la entrada vacía `=X/postgres`. Cerrado en `0055`. Las
  tres ya rechazaban a un anónimo en su cuerpo, pero eso es la segunda línea: la
  primera es no publicar la función en `/rest/v1/rpc/` para un rol que no la necesita.
- **Un `grant` de tabla y una política de RLS son dos permisos distintos, y hacen falta
  los dos.** Las políticas `delete` de `friend_edges` y `blocks` no servían para nada
  hasta `0053`: la migración `0009` invirtió los privilegios por defecto, así que la
  tabla nueva nace solo con `select` y Postgres devuelve `42501` **antes** de llegar a
  evaluar la política. Lo destapó 010/AC-15c — la mitad «camino feliz» de la
  comprobación de superficie. AC-15a y AC-15b, los guardarraíles, estaban en verde:
  desde ese lado, un `revoke` de más se ve exactamente igual que uno bien puesto.
- **En esa misma vista, el `EXECUTE` de una función se comprueba contra quien
  consulta**, no contra el dueño — al contrario que los privilegios de tabla. Se
  descubrió con un 42501 en tiempo de ejecución, no con el linter (`0025`).
