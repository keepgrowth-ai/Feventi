# 010 — Plan

Cómo se construye lo que `spec.md` describe. Una migración, dos pantallas.

---

## Migración `0052_social_graph.sql`

Todo en una sola migración porque las tablas, sus políticas y los helpers que las
leen son inseparables: partirla deja una ventana con RLS a medias, que es
exactamente lo que el CLAUDE.md prohíbe.

### Orden dentro del archivo

1. `friend_edge_status` (enum, dos valores).
2. `friend_edges` + constraints + índices.
3. `blocks`.
4. `alter table … enable row level security` **en la misma migración**.
5. Políticas.
6. `revoke insert, update on friend_edges` — solo las RPC escriben.
7. Helpers `private.*`.
8. RPC `request_friendship` y `respond_friendship`.
9. Vistas `v_my_friends` y `v_my_friend_requests`.
10. Grants.

### Decisiones de implementación

**El enum solo tiene `pending` y `accepted`.** «Rechazada» no es un estado: es la
ausencia de la fila. Guardar rechazos permitiría a A saber que B lo rechazó
—consultando por qué no puede volver a pedir— y crea un cementerio de filas que
nadie consulta. Rechazar **borra**.

**`least`/`greatest` en el índice único, no una columna calculada.** Postgres
indexa expresiones inmutables sin ayuda. Una columna `pair_key` generada sería
otro sitio donde equivocarse.

**Los helpers viven en `private`, no en `public`.** PostgREST no expone el esquema
`private`, así que `can_see_activity_of` no es llamable desde el cliente ni por
accidente. 011 la usará desde una vista `security invoker`, que es la única forma
correcta de que el filtro de ninja no se pueda saltar.

**`can_see_activity_of` es `stable`, no `volatile`.** Se va a llamar una vez por
evento y por amigo en 011. Con `volatile` el planner la ejecutaría por fila sin
poder cachear nada dentro de la consulta.

**Las dos RPC son `security definer` con `search_path = public, private, pg_temp`.**
`request_friendship` necesita leer `profiles` de otra persona para resolver el
correo, cosa que la RLS del llamante no permite — y ese es justamente el motivo de
que devuelva siempre el mismo mensaje.

### El mensaje único de `request_friendship`

```sql
-- Los cuatro casos de fallo devuelven ESTO, exactamente:
raise exception 'no_se_pudo_enviar' using errcode = 'P0001';
```

El front lo traduce a *«Si esa persona usa Feventi, le llegará tu solicitud»* y lo
muestra **también en el caso de éxito**. Si el mensaje de éxito fuera distinto, el
formulario seguiría siendo un oráculo de registro: bastaría con mirar cuál de los
dos textos sale.

### `respond_friendship`, la transición

```sql
select * into v_edge from public.friend_edges
 where id = p_edge_id for update;          -- primero el candado

if v_edge is null then raise exception 'no_existe'; end if;
if v_edge.addressee_id <> auth.uid() then raise exception 'no_autorizado'; end if;
if v_edge.status <> 'pending' then raise exception 'ya_respondida'; end if;
```

`for update` antes de comprobar el estado, no después (CLAUDE.md). Dos pestañas
aceptando a la vez es el caso que este candado resuelve, y AC-06 lo verifica por
HTTP, no en SQL: dos transacciones en la misma sesión psql se serializan solas y
el test pasaría en verde sin probar nada.

### Vistas

`v_my_friends` — `security invoker`, para que la RLS de `friend_edges` haga el
trabajo. Devuelve `friend_id`, `full_name`, `avatar_url`, `since`. **No devuelve
`ninja_mode`**: si el front supiera quién está en ninja, la función estaría rota
por diseño. El front no necesita saberlo; la base de datos sí.

`v_my_friend_requests` — solicitudes recibidas pendientes, con nombre y avatar de
quien pide.

Las dos excluyen a quien yo bloqueé y a quien me bloqueó.

---

## Tipos

`npm run gen:types` después de aplicar. No se toca `db.types.ts` a mano.

---

## Pantallas

### `SocialStore` (`features/social/social.store.ts`)

Mismo patrón que `WalletStore`: señales `loading` y `error`, métodos `async` que
devuelven datos y no los guardan. Sin caché — el grafo cambia por acción de otra
persona y una lista cacheada muestra amigos que ya no lo son.

Métodos: `friends()`, `requests()`, `request(email)`, `respond(edgeId, accept)`,
`unfriend(edgeId)`, `block(userId)`, `unblock(userId)`, `blocked()`,
`setNinja(on)`.

### `/amigos` (`features/social/amigos.page.ts`)

Tres bloques en el orden del spec. Mobile-first a 390 px, modo Fan (Art. 10).

El bloque de solicitudes solo se pinta si hay alguna: un «no tienes solicitudes»
permanente es ruido en la pantalla que más se va a ver vacía.

### `/perfil` (`features/social/perfil.page.ts`)

Datos de solo lectura, el interruptor de ninja y la lista de bloqueados.

El interruptor escribe `profiles.ninja_mode` directo —es una columna del propio
usuario y su política de update ya existe desde 001— y **relee** el valor de la
respuesta en vez de asumirlo. Si la escritura falló, el interruptor tiene que
volver, no quedarse mintiendo.

### Navegación

`fan.layout.ts` gana dos entradas cuando hay sesión: «Amigos» y «Perfil».

La de Amigos lleva un punto coral si hay solicitudes pendientes. Es lo más
parecido a una notificación que se puede hacer sin D-11, y no requiere nada nuevo:
el contador sale de `v_my_friend_requests`, que ya se consulta.

---

## Test `supabase/tests/010_grafo_social.sql`

Los 18 AC, con el patrón del README de tests. Tres usuarios sembrados dentro del
propio test (bloque `20600000x`, siguiendo la convención de RUC de las otras
suites para no chocar con la siembra de demo).

AC-06 —aceptar dos veces en paralelo— **no cabe en el .sql**: dos llamadas en la
misma sesión se serializan y el test pasaría por la razón equivocada. Va en
`010_concurrencia.mjs`, dos `fetch` con `Promise.all` contra la API real, igual
que `006_qr_validate.mjs`.
