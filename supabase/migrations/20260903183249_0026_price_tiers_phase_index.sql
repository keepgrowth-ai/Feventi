-- 003 · hallazgo del linter de rendimiento, el único que valía actuar.
--
-- `get_public_event` cuenta entradas por fase (`where t.phase_id = p.id`) para
-- pintar la línea de fases, y el índice que había —(event_id, phase_id)— no
-- sirve cuando no se filtra por evento: `phase_id` no es la columna que lidera.
--
-- Los demás FK que reporta el linter sí están cubiertos por el prefijo de un
-- índice existente: (zone_id, segment_id) usa `price_tiers_zone_idx (zone_id)`,
-- y los dos `..._zone_is_seated_fk` usan el (zone_id, …) de su tabla. Postgres
-- puede usar un índice compuesto para una búsqueda por su primera columna.
-- El resto son columnas de auditoría y quedan aceptadas en advisor-baseline.md.

create index price_tiers_phase_idx on public.price_tiers (phase_id);
