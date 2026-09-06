# 011 — Tareas

## Migración

- [x] T-01 · `0056_event_interests.sql`: tabla, PK compuesta, RLS + políticas
- [x] T-02 · `grant select, insert, delete on event_interests to authenticated`
      (la `0009` invirtió los defaults: sin esto la política no llega a evaluarse
      — la lección de `0053`)
- [x] T-03 · Vista `v_my_event_signals` definer, con el filtro por `auth.uid()`
      escrito en el `where` y el ninja resuelto por `private.can_see_activity_of`
- [x] T-04 · `grant select` de la vista a `authenticated` únicamente

## Verificación

- [x] T-05 · `supabase/tests/011_senales_sociales.sql` — AC-01…AC-15
- [x] T-06 · `get_advisors(security)` y anotar el `ERROR` de la vista definer

## Tipos

- [x] T-07 · `event_interests` y `v_my_event_signals` en `db.types.ts`

## UI

- [x] T-08 · `social.store.ts`: `signals()`, `setInterest(eventId, on)`
- [x] T-09 · Componente `fv-social-signal` compartido — el mismo texto en la
      tarjeta y en la ficha, para que no se escriban dos copias que divergen
- [x] T-10 · Señal + botón «Me interesa» en la ficha del evento
- [x] T-11 · Señal en la tarjeta del catálogo + filtro «Con amigos asistiendo»
- [x] T-12 · `ng build` limpio
