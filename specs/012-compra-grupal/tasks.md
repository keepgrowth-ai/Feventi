# 012 — Tareas

## Migración

- [x] T-01 · `0058_purchase_groups.sql`: enum, `purchase_groups`, `group_members`
- [x] T-02 · Los tres árbitros en índices, no en comprobaciones:
      `group_members_slot_unique` (el «hasta 4» del Art. 11),
      `group_members_one_group_per_event`,
      y la **FK compuesta** `(group_id, event_id)` — la lección de `0045`.
- [x] T-03 · RLS + políticas de lectura en la misma migración
- [x] T-04 · `revoke insert, update, delete`: los estados van por RPC
- [x] T-05 · `create_purchase_group`, `add_group_member` (exige amistad),
      `leave_purchase_group`, `lock_purchase_group`
- [x] T-06 · Trigger `tickets_assign_group_owner` — **el ticket nace con su
      dueño**. Sin esto la feature sería decorativa.
- [x] T-07 · Trigger `orders_complete_group` sobre `orders`, no sobre `tickets`:
      `confirm_payment` inserta los tickets DESPUÉS de marcar la orden pagada.
- [x] T-08 · Grants + `revoke … from public, anon` en la misma migración
      (la lección de `0055`, ya aprendida)

### Corrección

- [x] T-08b · `0059_fix_group_policy_recursion` — `42P17: infinite recursion`.
      La política de `group_members` se consultaba a sí misma. Resuelto con
      `private.auth_group_ids()`, el patrón de array de `0004`. **El linter no
      lo ve**: solo aparece al leer la tabla.

## Verificación

- [x] T-09 · `supabase/tests/012_compra_grupal.sql` — **20 comprobaciones en
      verde**, AC-01…AC-20
- [x] T-10 · `get_advisors(security)` — 4 `WARN` nuevos, argumentados en
      `specs/advisor-baseline.md`

## Tipos

- [x] T-11 · `purchase_groups`, `group_members`, las 4 RPC y el enum

## UI

- [x] T-12 · `features/social/grupos.store.ts`
- [x] T-13 · `features/social/grupos.page.ts` — `/grupos`
- [x] T-14 · Botón «Comprar con amigos» en la ficha del evento.
      **No se mezcla con el flujo de compra individual**: crea el grupo y
      navega. Meter dos flujos en la misma pantalla es la forma más fácil de
      romper el que ya funciona.
- [x] T-15 · `PublicEventStore.getById` — el grupo guarda `event_id`, no el slug
- [x] T-16 · Ruta y enlace en la navegación
- [x] T-17 · `ng build` limpio (`grupos-page` 22,07 kB)
