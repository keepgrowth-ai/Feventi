# 001 — Tasks

**Cerrado.** 43 comprobaciones en verde, `get_advisors(security)` sin `ERROR`,
verificado además de extremo a extremo contra la Auth API y PostgREST reales.

## Base de datos

- [x] T-01 ~~Branch de Supabase~~ → se aplicó al proyecto de desarrollo, que estaba
      vacío y recién creado. Las pruebas van dentro de `begin … rollback`, así que no
      dejan rastro y no hacía falta pagar una branch. Cuando haya datos de verdad, sí.
- [x] T-02 `0001_extensions_and_enums`
- [x] T-03 `0002_profiles`: tabla, índices, RLS, `grant update` de columna
- [x] T-04 `0002_profiles`: `handle_new_user()` + trigger — AC-01, AC-02
- [x] T-05 `0002_profiles`: `user_roles`, solo select propio — AC-11, AC-12
- [x] T-06 `0004_role_helpers`: los tres helpers `security definer stable search_path=''` — AC-13, AC-14
- [x] T-07 `0003_organizers`: tablas + RLS + sin delete — AC-18…AC-22, AC-25
- [x] T-08 `0005_organizer_rpcs`: `create_organizer` transaccional — AC-16, AC-17
- [x] T-09 `0005_organizer_rpcs`: `add`/`revoke_organizer_member` — AC-20, AC-21
- [x] T-10 `0005_organizer_rpcs`: `approve_organizer`, `set_organizer_status` — AC-23, AC-24
- [x] T-11 `0006_dni`: pepper en Vault, idempotente
- [x] T-12 `0006_dni`: `hash_dni` con HMAC + pepper, revocada al cliente — AC-08, AC-09
- [x] T-13 `0006_dni`: `set_own_dni`, `verify_dni` — AC-06, AC-07

### No estaba en el plan, salió de las pruebas

- [x] T-13b `0007`: revocar `select` de tabla antes de conceder por columna. El
      `revoke select (dni_hash)` de 0002 no hacía nada — lo destapó **AC-10**
- [x] T-13c `0008`: `profile_identity`, tabla aparte con RLS y cero políticas. El
      privilegio de columna rompía el `select *` de PostgREST y era reversible de un
      `grant`
- [x] T-13d `0009`: quitar `truncate` a `anon`/`authenticated` (**TRUNCATE no está
      sujeto a RLS**) e invertir los privilegios por defecto — AC-29, AC-30
- [x] T-13e `0010`: schema `private` para helpers y funciones de trigger; sacar
      `handle_new_user` de la superficie de RPC

## Verificación

- [x] T-14 `supabase/tests/001_fundaciones.sql`, un caso permitido y uno denegado por AC
- [x] T-15 43/43 en verde
- [x] T-16 `get_advisors(security)` sin `ERROR`; aceptados en `specs/advisor-baseline.md` — AC-27
- [x] T-17 `get_advisors(performance)` revisado: sin hallazgos sobre las tablas de 001
- [x] T-18 ~~Merge de branch~~ → no aplica, ver T-01
- [x] T-18b Migraciones espejadas en `supabase/migrations/`, 1:1 con
      `supabase_migrations.schema_migrations`. La base no es la única copia del schema
- [x] T-18c Extremo a extremo por la **Auth API real**: alta → `profile` con
      `full_name` + rol `fan` (el trigger sigue funcionando tras revocarle `execute`)
- [x] T-18d Extremo a extremo por **PostgREST**: `anon` denegado en las cuatro tablas;
      helpers y `handle_new_user` no resuelven como RPC; autenticado ve solo su fila,
      `select *` funciona, `PATCH dni_verified_at` denegado, `PATCH full_name` pasa,
      `set_own_dni` deja `last4`, `verify_dni` responde «solo Admin»

## Front

- [x] T-19 Angular en `apps/web`: standalone, zoneless, sin SSR — **CLI 22**, no 20
      (es la actual; mismo stack de standalone + signals + zoneless que se eligió)
- [x] T-20 Tailwind v4 + `@theme` con los tokens de `design-system.md` §1–3
- [x] T-21 Inter + JetBrains Mono con `display=swap` y stack de respaldo real
- [x] T-22 `environment.ts` con URL + **publishable key**
- [x] T-23 `supabase.client.ts`
- [x] T-24 `auth.store.ts`: signals `session`/`profile`/`roles`, computed `isAdmin`,
      `isOrganizer`, `isStaff`, `hasDni`
- [x] T-25 `auth.guard.ts`: `authGuard`, `roleGuard(...)`, `guestGuard`
- [x] T-26 Login: contraseña y magic link
- [x] T-27 Registro; el `profile` lo crea el trigger, el cliente no inserta nada
- [x] T-28 Los tres layouts: `fan`, `ops`, `gate` — Art. 10
- [x] T-29 `shared/ui`: `fv-chip` (texto siempre), `fv-metric` (denominador
      obligatorio), `fv-price-breakdown` (el cargo visible aunque sea cero), `money.ts`
      (formatea, no calcula)
- [x] T-30 `db.types.ts` generado desde el schema — Art. 12.3
- [x] T-31 `npm run build` limpio (471 kB inicial, 117 kB transferidos);
      `grep -r service_role dist/` sin resultados — Art. 9.3

## Cierre

- [x] T-32 001 marcado como listo en `roadmap.md` y `README.md`
- [x] T-33 Defaults en los que se apoya este feature: **D-10** (verificación de
      identidad manual, y el pepper necesita respaldo custodiado antes de producción),
      **D-11** (sin centro de notificaciones)

## Queda fuera, y es de quien tenga acceso al panel

- [ ] T-34 Activar **leaked password protection** en Authentication → Policies. No se
      puede tocar por MCP ni por SQL. Sin esto, Supabase Auth acepta contraseñas ya
      filtradas. Anotado en `specs/advisor-baseline.md`.
