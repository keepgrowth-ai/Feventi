# 010 — Tareas

## Migración

- [x] T-01 · `0052_social_graph.sql`: enum `friend_edge_status`, `friend_edges`, `blocks`
- [x] T-02 · Constraints: `no_self`, `accepted_has_time`, índice único `friend_edges_one_per_pair`
- [x] T-03 · RLS activada en la misma migración + políticas de las dos tablas
- [x] T-04 · `revoke insert, update on friend_edges from authenticated, anon`
- [x] T-05 · `private.are_friends`, `private.can_see_activity_of`
- [x] T-06 · RPC `request_friendship` con mensaje único
- [x] T-07 · RPC `respond_friendship` con `select … for update`
- [x] T-08 · RPC `block_user`.
      **Desbloquear y dejar de ser amigos NO llevan RPC**: son borrados que la
      política ya autoriza, y una RPC que solo envuelve un `delete` es una capa
      sin regla dentro.
- [x] T-09 · Vistas `v_my_friends`, `v_my_friend_requests` + grants

### Correcciones (migraciones inmutables, Art. 12.4)

- [x] T-09b · `0053_grant_social_writes` — las políticas de `delete` no servían
      de nada: la `0009` invirtió los privilegios por defecto y faltaba el
      `grant` de tabla. Postgres devolvía `42501` **antes** de evaluar la
      política. Lo destapó AC-15c.
- [x] T-09c · `0054_social_views_definer` — las vistas salían VACÍAS. Igual que
      0041 → 0042: el join con `profiles`, que solo lee su dueño. Lo destapó
      AC-07c. Al pasar a definer se apaga la RLS de dentro, así que el filtro
      por `auth.uid()` va escrito en el `where` y tiene su propia comprobación
      (AC-07d).
- [x] T-09d · `0055_revoke_social_rpcs_from_anon` — un `grant execute … to
      authenticated` no quita el `execute` que `PUBLIC` trae de fábrica. Las
      tres RPC quedaron publicadas en `/rest/v1/rpc/` para `anon`.

## Verificación

- [x] T-10 · `supabase/tests/010_grafo_social.sql` — **30 comprobaciones, 30 en
      verde.** AC-01…AC-05c, AC-07…AC-08, AC-09…AC-11b, AC-12a…AC-14, AC-15a…AC-15e
- [ ] T-11 · `supabase/tests/010_concurrencia.mjs` — AC-06 por HTTP.
      **Depende de la siembra**: necesita dos cuentas reales con contraseña para
      abrir dos sesiones. Se escribe y corre junto al camino feliz de Playwright.
- [x] T-12 · `get_advisors(security)` — sin hallazgos sin decisión.
      Dos `ERROR` nuevos (las vistas definer) y tres `WARN` nuevos (las RPC),
      argumentados en `specs/advisor-baseline.md`.

## Tipos

- [x] T-13 · `db.types.ts` con `friend_edges`, `blocks`, las dos vistas, las tres
      RPC y el enum.
      **Nota:** `npm run gen:types` no corre en este entorno —el CLI pide
      `SUPABASE_ACCESS_TOKEN`— así que las formas se copiaron literalmente de la
      salida del generador vía MCP, sin inventar ninguna. El resto del archivo
      no se tocó: la salida del generador del MCP tiene otro formato y adoptarla
      entera rompía `support.store.ts` y `events.store.ts` por un cambio de
      nulabilidad ajeno a esta feature.

## UI

- [x] T-14 · `features/social/social.store.ts`
- [x] T-15 · `features/social/amigos.page.ts` — `/amigos`
- [x] T-16 · `features/social/perfil.page.ts` — `/perfil`
- [x] T-17 · Rutas en `app.routes.ts` con `authGuard`
- [x] T-18 · Enlaces en `fan.layout.ts` + punto coral de solicitudes pendientes
- [x] T-19 · `ng build` limpio (`amigos-page` 19,44 kB)
- [ ] T-20 · Revisión a 390 px (AC-17) y persistencia del interruptor (AC-18) —
      va con el paso de navegador del final.
