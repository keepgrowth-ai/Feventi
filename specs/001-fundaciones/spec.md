# 001 — Fundaciones: identidad, roles, tenencia y RLS base

**Mundo:** todos · **Pantalla del mockup:** ninguna · **Depende de:** nada ·
**Bloquea a:** todo lo demás

---

## Objetivo

Que exista una identidad con roles no falsificables y una convención de RLS que los
demás features solo tengan que aplicar. Sin esto, cada feature reinventa su control de
acceso y alguno lo hace mal.

Cierra los artículos **7** (datos personales), **9** (denegar por defecto) y la base del
**8** (auditoría).

## No objetivos

- Pantallas de perfil, privacidad o modo ninja: la columna existe, la UI es Fase 2.
- Verificación de identidad con proveedor externo: **D-10**, se sella a mano por Admin.
- Login social. Solo email + contraseña y magic link, lo que trae Supabase Auth.
- Centro de notificaciones: **D-11**.

## Actores

| Actor | Qué obtiene aquí |
|---|---|
| Visitante | puede registrarse; no lee nada de `public` salvo lo que un feature abra a `anon` |
| Fan | su `profile`, editable salvo los campos de identidad |
| Organizador | pertenencia a uno o más `organizers` |
| Admin | lectura y escritura sobre identidad y organizadores, con auditoría |

## Historias

1. **Registro.** Como visitante me registro con email y quedo con un `profile` y el rol
   `fan`, sin ningún paso manual.
2. **Perfil.** Como fan edito mi nombre, teléfono y avatar. **No** puedo tocar mi DNI
   hasheado, mi verificación ni mis roles.
3. **DNI.** Como fan declaro mi DNI una vez y el sistema lo guarda hasheado. Veo solo
   los últimos 4 dígitos. Nunca recibo el hash.
4. **Organizador.** Como fan solicito ser organizador; queda un `organizer` en `pending`
   y yo como `owner`. No puedo aprobarme.
5. **Equipo.** Como `owner` de un organizador invito a otro usuario como `admin` o
   `viewer`, y le puedo revocar el acceso sin borrar su rastro.
6. **Admin.** Como Admin veo cualquier perfil y cualquier organizador, apruebo o
   suspendo organizadores, y sello un DNI como verificado.
7. **Aislamiento.** Como organizador A no puedo leer ni una fila del organizador B.

## Criterios de aceptación

Verificables con SQL en `supabase/tests/001_fundaciones.sql`. Cada uno tiene su caso
permitido y su caso denegado.

### Identidad

- **AC-01** Insertar en `auth.users` crea exactamente una fila en `profiles` con el
  mismo `id` y el email copiado.
- **AC-02** Ese mismo insert crea `(user_id, 'fan')` en `user_roles`.
- **AC-03** Borrar el usuario de `auth.users` borra su `profile` en cascada.
- **AC-04** Un fan hace `select` de `profiles` y obtiene **una** fila: la suya.
- **AC-05** Un fan hace `update` de `full_name`, `phone`, `avatar_url`, `ninja_mode` en
  su fila y funciona.
- **AC-06** Un fan que intenta escribir en `profile_identity`, aunque sea su propia
  fila, **falla**.
- **AC-07** Un fan que intenta `update profiles set dni_verified_at = now()` **falla**
  por privilegio de columna, aunque sea su propia fila. `verify_dni` llamada por un fan
  también falla.
- **AC-08** `set_own_dni('76543210')` deja `dni_last4 = '3210'` en `profiles` y un
  `dni_hash` en `profile_identity` que **no** es el SHA-256 desnudo del DNI (lleva
  pepper). Un DNI que no sean 8 dígitos se rechaza. `hash_dni` no es invocable por el
  cliente.
- **AC-09** Dos usuarios distintos que declaran el mismo DNI obtienen el **mismo**
  `dni_hash` — el hash tiene que ser determinista para poder nominar y buscar en puerta.
  Dos DNIs distintos dan hashes distintos.
- **AC-10** Un fan que hace `select` sobre `profile_identity` **falla**: la tabla tiene
  RLS activa y ninguna política. Y `select *` sobre `profiles` **sí funciona** — no hay
  ninguna columna revocada que rompa la consulta por defecto de PostgREST.

### Roles

- **AC-11** Un fan que intenta `insert into user_roles values (uid, 'admin')` **falla**.
- **AC-12** Un fan que intenta `update user_roles` sobre su propia fila **falla**.
- **AC-13** `public.auth_is_admin()` devuelve `true` para un usuario con rol `admin` y
  `false` para un fan.
- **AC-14** Las funciones de resolución de rol son `security definer`, `stable` y
  tienen `search_path` fijado. Se verifica leyendo `pg_proc`.
- **AC-15** Ninguna política de RLS provoca recursión: un `select` sobre `user_roles`
  como fan termina y devuelve solo sus filas.

### Tenencia

- **AC-16** Un fan crea un `organizer`; queda en `status = 'pending'` y él como `owner`
  en `organizer_members`, en una sola llamada transaccional.
- **AC-17** Un fan que intenta crear un `organizer` con `status = 'approved'` termina
  con `pending`: el estado lo fija el servidor, no el payload.
- **AC-18** Un `owner` lee su organizador y sus miembros.
- **AC-19** El `owner` del organizador A hace `select` de `organizers` y **no ve** al
  organizador B.
- **AC-20** Un `viewer` que intenta `insert` en `organizer_members` **falla**.
- **AC-21** Revocar un miembro pone `revoked_at` y su fila **sigue existiendo**
  (Art. 8.2).
- **AC-22** Un miembro con `revoked_at` no null deja de tener acceso: `auth_organizer_ids()`
  ya no lo incluye.
- **AC-23** Un fan que intenta `update organizers set status = 'approved'` **falla**.
- **AC-24** Admin aprueba un organizador y quedan sellados `approved_at` y `approved_by`.
- **AC-25** No hay `delete` de `organizer_members` para ningún rol que no sea
  `service_role`.

### RLS base

- **AC-26** Toda tabla de `public` tiene `rowsecurity = true` en `pg_tables`. Es una
  comprobación global, no solo de las tablas de este feature: hereda cada feature nuevo.
- **AC-27** `mcp__supabase__get_advisors(security)` no reporta ningún hallazgo de nivel
  `ERROR`, ninguna función con `search_path` mutable, y ninguna función de trigger o
  helper interno expuesta como RPC. Los hallazgos aceptados se listan en
  `specs/advisor-baseline.md` con su razón.
- **AC-28** Como `anon`, `select` sobre `profiles`, `user_roles`, `organizers` y
  `organizer_members` **falla con 42501**. Se prefiere la denegación por privilegio a
  las «0 filas» de una RLS sin política: es más fuerte, más barata de evaluar y no
  depende de que nadie añada después una política permisiva. Lo que `anon` puede leer
  son las vistas públicas, concedidas una por una.
- **AC-29** Como `anon`, `truncate` sobre cualquier tabla de `public` **falla**.
  `TRUNCATE` no está sujeto a RLS, así que un `grant` olvidado ahí no lo tapa ninguna
  política.
- **AC-30** Una tabla nueva creada en `public` nace con `select` para `authenticated`,
  **nada** para `anon`, y sin `insert/update/delete/truncate` para ninguno.

## Riesgos de confusión

- **Un fan cree que su rol lo define lo que él manda.** Se corta en la raíz: el cliente
  no escribe en `user_roles` nunca (Art. 9.2).
- **Se cree que hashear el DNI ya lo protege.** No: un DNI peruano son 8 dígitos, 10⁸
  combinaciones. Un SHA-256 desnudo se rompe por fuerza bruta en segundos. Va con
  **pepper en Vault**, y el `select` de la columna está revocado al cliente.
- **Se cree que `security definer` es una puerta trasera.** Aquí es lo correcto: sin él,
  una política sobre `user_roles` que lea `user_roles` recursa. La contención es
  `search_path` fijo y que la función solo devuelva booleanos o ids del propio llamante.
