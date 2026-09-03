# Línea base del linter de seguridad

`mcp__supabase__get_advisors(security)` corre al cerrar cada feature (roadmap,
«definición de terminado» §2). Este archivo dice qué hallazgos están **aceptados y por
qué**, para que la comprobación sea un diff y no una lectura completa cada vez.

**Regla:** cero hallazgos de nivel `ERROR`. Un `WARN` o `INFO` solo cuenta como
aceptado si está en la tabla de abajo. Uno que no esté es un hallazgo nuevo y hay que
resolverlo o justificarlo aquí en el mismo commit.

Última corrida: **001 Fundaciones** · seguridad 0 `ERROR` · rendimiento 0 `WARN`.

## Aceptados — rendimiento

| nivel | hallazgo | por qué se acepta |
|---|---|---|
| INFO | `unindexed_foreign_keys` en `organizer_members.invited_by` y `organizers.approved_by` | **YAGNI.** Son columnas de auditoría: nadie consulta «qué organizadores aprobó tal Admin». Un índice ahí solo aceleraría el chequeo de FK al borrar un `profile`, sobre tablas que van a tener cientos de filas, no millones. Se indexa el día que exista una pantalla que filtre por ellas. |
| INFO | `unused_index` en `organizers_status_idx` | Está sin usar porque **no hay datos**. La cola de solicitudes de Admin (007) filtra por `status` y es su caso de uso. Se revisa cuando 007 esté en producción; si sigue sin usarse, se borra. |

## Aceptados — seguridad

| nivel | hallazgo | por qué se acepta |
|---|---|---|
| INFO | `rls_enabled_no_policy` en `public.profile_identity` | **Es el diseño**, Art. 2.6 y 7.1. RLS activa y cero políticas es la forma de decir «nadie pasa». Solo `service_role` y las funciones `security definer` de nominación y puerta. Añadirle una política sería el bug. |
| WARN | `authenticated_security_definer_function_executable` en `create_organizer`, `add_organizer_member`, `revoke_organizer_member`, `approve_organizer`, `set_organizer_status`, `set_own_dni`, `verify_dni` | **Es la superficie de RPC de 001**, y `security definer` es justo lo que las hace útiles: existen para hacer lo que una política no puede (fijar el `status` en el servidor, escribir dos filas juntas, hashear con un pepper que el llamante no ve). Cada una comprueba autorización en su propio cuerpo, y esa comprobación está cubierta por AC-17, AC-20, AC-23, AC-24 y AC-07b. |
| WARN | `auth_leaked_password_protection` | **Bloqueado por plan, no por olvido.** El chequeo contra HaveIBeenPwned es **Pro o superior**, y la organización `Keepgrowth AI` está en **free**: el interruptor no existe todavía. Mitigación disponible en free, en Authentication → Sign In / Providers → Email: subir *minimum password length* a 12 y exigir minúsculas + mayúsculas + dígitos. No es equivalente —una contraseña filtrada puede ser larga y variada— así que el chequeo real queda como requisito de producción junto al Art. 13. Ver **D-50**. |

## Resueltos, para que no vuelvan

| hallazgo | cómo se resolvió |
|---|---|
| `rls_disabled_in_public` en `public._probe_defaults` | tabla de prueba de los privilegios por defecto, ya borrada. Recordatorio: una tabla de sonda se borra en el mismo statement que la crea. |
| `anon_security_definer_function_executable` en `handle_new_user()` | movida a `private` y `revoke execute` (migración `0010`). Era una función de trigger publicada como `/rest/v1/rpc/handle_new_user`. |
| Los helpers `auth_*` expuestos como RPC | movidos a `private` (migración `0010`). Las políticas los resuelven por OID, así que `alter function ... set schema` no las rompe. |
| `multiple_permissive_policies` en las cuatro tablas | consolidadas a **una política de SELECT por tabla** con `OR` (migración `0011`). Había dos permisivas por tabla —dueño y Admin— y Postgres evaluaba las dos en cada consulta, ejecutando `auth_is_admin()` también para los fans, que son el tráfico. |

## Lo que el linter no ve

Encontrado a mano, y por eso vale anotarlo:

- **`TRUNCATE` concedido a `anon`.** Los privilegios por defecto de Supabase dan `ALL`
  sobre las tablas de `public`, y `ALL` incluye `TRUNCATE`, que **no está sujeto a
  RLS**. Cerrado en `0009` y cubierto por **AC-29**. El linter no lo reporta.
- **`revoke select (col)` que no hace nada** porque existe un `grant select` de tabla.
  Silencioso: no da error ni aviso, simplemente no protege. Cubierto por **AC-10**.
