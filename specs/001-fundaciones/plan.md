# 001 — Plan

**Estado: aplicado.** 43 comprobaciones en verde, `get_advisors(security)` sin ERROR.

## Migraciones

| # | nombre | contenido |
|---|---|---|
| 0001 | `extensions_and_enums` | `pgcrypto` en `extensions`, `supabase_vault`; enums `app_role`, `organizer_status`, `organizer_role` |
| 0002 | `profiles` | `profiles` + `user_roles`, trigger desde `auth.users`, `touch_updated_at`, RLS, privilegios de columna |
| 0003 | `organizers` | `organizers`, `organizer_members`, RLS |
| 0004 | `role_helpers` | `auth_has_role`, `auth_is_admin`, `auth_organizer_ids` + las políticas que dependen de ellos |
| 0005 | `organizer_rpcs` | `create_organizer`, `add`/`revoke_organizer_member`, `approve_organizer`, `set_organizer_status` |
| 0006 | `dni` | pepper en Vault, `hash_dni`, `set_own_dni`, `verify_dni` |
| 0007 | `fix_profiles_column_select` | corrige 0002: revocar `select` de tabla antes de conceder por columna |
| 0008 | `profile_identity_table` | saca el hash del DNI a su propia tabla sin políticas |
| 0009 | `harden_default_privileges` | quita `truncate` a `anon`/`authenticated` e invierte los privilegios por defecto |
| 0010 | `private_schema_for_helpers` | schema `private` para helpers y funciones de trigger |

Migraciones inmutables (Art. 12.4): 0007–0010 corrigen a las anteriores en lugar de
editarlas. Se aplican con `mcp__supabase__apply_migration`, que las deja también en el
historial del proyecto.

### Lo que se aprendió aplicándolas

**El orden importa más de lo que parece.** `auth_organizer_ids()` es `language sql`, y
Postgres valida el cuerpo de una función SQL al crearla. Con el orden del plan original
(helpers antes que `organizers`) la migración falla con
`relation "public.organizer_members" does not exist`. Las tablas van primero.

**Un `revoke` de columna no recorta un `grant` de tabla.** En Postgres, `grant select`
a nivel de tabla implica select sobre todas las columnas, y `revoke select (col)` no lo
puede deshacer. Supabase concede select de tabla a `anon` y `authenticated` por
privilegios por defecto, así que el `revoke select (dni_hash)` de 0002 no hizo nada.
Lo destapó **AC-10**, que es exactamente para lo que estaba escrito. El orden correcto
es revocar la tabla y después conceder columna por columna — que es lo que 0002 ya
hacía bien con `update` y mal con `select`.

**Y aun así, el privilegio de columna era la solución equivocada.** Con `select` sobre
`dni_hash` revocado, un `GET /profiles` sin lista de columnas devuelve 42501, porque
PostgREST emite `select *`. El siguiente que se topara con eso lo «arreglaría» con un
`grant select on profiles`, reabriendo el agujero en silencio. 0008 saca el hash a
`profile_identity`, con RLS activa y **cero políticas** — el patrón de
`ticket_secrets`. Inalcanzable por diseño, no por un privilegio reversible.

**`TRUNCATE` no está sujeto a RLS.** Los privilegios por defecto de Supabase conceden
`ALL` sobre las tablas de `public` a `anon`, y `ALL` incluye `TRUNCATE`. Se comprobó:
`set role anon; truncate public.organizers` **pasa**. PostgREST nunca emite `TRUNCATE`,
así que no es una puerta abierta hoy, pero es una mina esperando la primera RPC
`security invoker` con SQL dinámico. 0009 lo cierra y de paso invierte el default a lo
que pide el Art. 9.1: la tabla nueva nace sin nada para el cliente.

**Los helpers no son endpoints.** Estando en `public`, `auth_is_admin()` y compañía
quedan publicadas en `/rest/v1/rpc/`. No son peligrosas — cada una responde sobre el
propio llamante — pero no tienen razón de estar ahí. 0010 las mueve a `private`, que
PostgREST no expone. Las políticas siguen funcionando porque las resuelven por OID, y
`alter function ... set schema` conserva el OID. Lo mismo con `handle_new_user()`, que
estaba publicada como RPC: el privilegio de ejecución de una función de trigger se
comprueba al **crear** el trigger, no al dispararlo, así que revocarlo no rompe el
registro (verificado creando un usuario después).

## Convención de RLS

Cinco reglas, y todos los features las heredan:

1. **`enable row level security` en la misma migración que crea la tabla.** Nunca en
   una posterior: entre las dos hay una ventana abierta.
2. **UNA política por operación y por rol, no una por caso.** Con `to authenticated` o
   `to anon` explícito — sin `to public`, que obliga a evaluar la política también para
   `anon`. Los casos se combinan con `OR` **dentro** de la misma política, y el caso
   común va primero para que el cortocircuito ahorre la llamada al helper:

   ```sql
   -- bien: una evaluación
   using (id = (select auth.uid()) or private.auth_is_admin())

   -- mal: dos políticas permisivas, Postgres evalúa las dos en cada consulta
   -- y auth_is_admin() se ejecuta también para los fans
   ```
3. **`(select auth.uid())`, no `auth.uid()`.** Envuelto en subconsulta, el planner lo
   evalúa una vez como InitPlan en lugar de una vez por fila.
4. **El rol se resuelve con un helper `security definer`**, jamás con un join a
   `user_roles` dentro de la política: ese join sí recursa.
5. **Escritura con reglas de negocio: RPC `security definer`, no política.** Una
   política puede decir «sí o no»; no puede decir «sí, pero el `status` lo pongo yo».

## Decisiones de diseño

### El DNI va con HMAC y pepper, no con hash desnudo

El DNI se necesita **determinista**: la nominación compara asistente contra titular, y
el modo DNI del validador (**D-03**) busca por documento. Eso descarta bcrypt por fila.

Y un hash determinista sin secreto no protege nada: 8 dígitos son 10⁸ candidatos, un
diccionario completo se genera en segundos.

Solución: `hmac(dni, pepper, 'sha256')` con el pepper en `vault.secrets`. Determinista,
y sin el pepper no hay fuerza bruta posible. El pepper se crea una vez y **no rota**
sin un plan de re-hasheo, porque no se puede re-derivar sin el DNI original.

```sql
create or replace function private.hash_dni(p_dni text)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_pepper text;
begin
  if p_dni is null or p_dni !~ '^[0-9]{8}$' then
    raise exception 'DNI inválido: se esperan 8 dígitos';
  end if;
  select decrypted_secret into strict v_pepper
    from vault.decrypted_secrets where name = 'dni_pepper';
  return encode(extensions.hmac(p_dni, v_pepper, 'sha256'), 'hex');
end $$;
revoke all on function private.hash_dni(text) from public, anon, authenticated;
```

`hash_dni` queda revocada al cliente **y** fuera del schema expuesto: si pudiera
llamarla, tendría un oráculo para confirmar el DNI de cualquier persona. Solo la usan
`set_own_dni` y las funciones de nominación y de puerta, todas `security definer`.

### El cliente nunca escribe los campos de identidad

Para lo que **sí** vive en `profiles`, privilegio de columna — más barato y más difícil
de olvidar que un trigger:

```sql
revoke insert, update, delete on public.profiles from authenticated, anon;
grant  update (full_name, phone, avatar_url, ninja_mode) on public.profiles to authenticated;
```

`dni_verified_at` queda fuera del `grant`, así que **AC-07** se cumple por privilegio y
no por confianza. Y el hash no está en esta tabla: si el cliente pudiera escribirlo,
copiaría el de otra persona y se haría pasar por ella en puerta. Entra solo por
`set_own_dni(text)`, que hashea en el servidor y escribe en `profile_identity`.

### `auth_organizer_ids` devuelve un array, no un `exists`

```sql
create or replace function private.auth_organizer_ids()
returns uuid[] language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(organizer_id), '{}')
  from public.organizer_members
  where user_id = (select auth.uid()) and revoked_at is null
$$;
```

Un array se evalúa una vez por consulta y las políticas quedan en
`organizer_id = any(public.auth_organizer_ids())`, que usa índice. Un `exists`
correlacionado se evalúa por fila.

### Crear un organizador es una RPC, no un insert

Porque son dos filas que tienen que ir juntas y porque el `status` no lo elige el
cliente (**AC-17**):

```sql
create or replace function public.create_organizer(
  p_legal_name text, p_trade_name text, p_ruc text,
  p_contact_email text, p_contact_phone text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'no autenticado'; end if;

  insert into public.organizers (legal_name, trade_name, ruc,
                                 contact_email, contact_phone, status, created_by)
  values (p_legal_name, p_trade_name, p_ruc,
          p_contact_email, p_contact_phone, 'pending', v_uid)   -- estado fijado aquí
  returning id into v_id;

  insert into public.organizer_members (organizer_id, user_id, role)
  values (v_id, v_uid, 'owner');

  insert into public.user_roles (user_id, role)
  values (v_uid, 'organizer') on conflict do nothing;

  return v_id;
end $$;
```

`organizers` no recibe `insert` directo de `authenticated`: solo esta función.

### Aprobar es de Admin y deja sello

`approve_organizer(uuid)` verifica `auth_is_admin()`, pasa a `approved` y escribe
`approved_at` / `approved_by`. Un `update` directo de `status` está fuera del `grant`
de columna, así que **AC-23** se cumple por privilegio, no por confianza.

### Revocar, no borrar

`organizer_members` y `event_staff` no tienen `delete` para nadie fuera de
`service_role` (Art. 8.2). Revocar es `update ... set revoked_at = now()`, y el helper
filtra por `revoked_at is null`. El historial queda.

## Estructura del front que deja este feature

Angular 20, standalone, signals, zoneless. Solo el esqueleto: este feature no dibuja
ninguna pantalla del mockup.

```
apps/web/src/
  styles.css                    tokens de design-system.md como @theme de Tailwind v4
  app/
    core/
      supabase.client.ts        createClient con la publishable key
      auth.store.ts             signals: session, profile, roles; computed isAdmin/isOrganizer
      auth.guard.ts             canActivate: authGuard, roleGuard('admin'|'organizer'|'staff')
      db.types.ts               GENERADO — no editar a mano (Art. 12.3)
    shared/ui/                  chip de estado, card, métrica, desglose de precio
    layouts/
      fan.layout.ts             modo Fan
      ops.layout.ts             modo Operación
      gate.layout.ts            modo Puerta
    routes.ts
```

`auth.store.ts` guarda los roles que llegan de `user_roles`, y sirven **solo para
navegación**: qué pestañas se pintan. La autorización real es la RLS. Un rol falseado en
el cliente abre un menú vacío, no un dato.

## Verificación

`supabase/tests/001_fundaciones.sql` — 43 comprobaciones, todas en verde. Se corre con
`mcp__supabase__execute_sql`. El archivo entero va dentro de un `begin … rollback`, así
que no deja rastro y se puede correr contra el proyecto de desarrollo sin branch.

Suplantación con el patrón estándar de Supabase:

```sql
set local role authenticated;
set local request.jwt.claims = '{"sub":"<uuid>","role":"authenticated"}';
```

Dos trampas del arnés, por si un AC parece fallar sin motivo:

- **`SET LOCAL ROLE` dentro de una función plpgsql no sirve** para lo que queremos: hay
  que cambiar de rol en el nivel del statement. Por eso el arnés son funciones
  `fails()` / `err()` que devuelven un booleano, y no funciones que escriben en una
  tabla de resultados.
- **Dentro de un mismo `SELECT`, todas las subconsultas ven el mismo snapshot.** Llamar
  a `approve_organizer()` y comprobar `status = 'approved'` en el mismo `select` lee el
  estado *anterior* y el AC parece fallar. Van en statements separados.

Además, una tabla temporal usada desde el rol `authenticated` necesita su
`grant insert, select`.

## Riesgos

| riesgo | mitigación |
|---|---|
| Pepper perdido: todos los `dni_hash` quedan inservibles y no se pueden re-derivar | queda en Vault del proyecto; antes de producción, respaldo custodiado fuera de Supabase. Anotado en **D-10** |
| Recursión de RLS en `user_roles` | helpers `security definer`, verificado por **AC-15** |
| El trigger de `auth.users` falla y el registro se rompe entero | el trigger solo inserta dos filas sin validación; sin `raise` propio |
| Alguien añade una tabla y se olvida la RLS | `get_advisors(security)` en el «terminado» de cada feature (roadmap) |
