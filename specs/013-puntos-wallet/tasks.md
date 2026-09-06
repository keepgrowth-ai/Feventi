# 013 — Tareas

## Migración

- [x] T-01 · `0057_points.sql`: enum `point_reason`, tabla `point_ledger`
- [x] T-02 · Índice único `point_ledger_one_per_checkin` (el árbitro del doble abono)
- [x] T-03 · RLS + política de select por dueño; `revoke insert, update, delete`
- [x] T-04 · Trigger `award_points_on_checkin` sobre `checkins`, solo `allowed`
- [x] T-05 · Vista `v_my_points` + grants

## Verificación

- [x] T-06 · `supabase/tests/013_puntos.sql` — AC-01…AC-11
- [x] T-07 · `get_advisors(security)`

## Tipos

- [x] T-08 · `point_ledger`, `v_my_points` y el enum en `db.types.ts`

## UI

- [x] T-09 · Total de puntos en la cabecera de la wallet (mockup L338)
- [x] T-10 · «+50 puntos» en el veredicto ACCESO PERMITIDO (mockup L685)
- [x] T-11 · `ng build` limpio
