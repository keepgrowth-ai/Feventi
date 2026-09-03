-- 004 · hallazgo del linter, el único que valía actuar.
--
-- El dashboard de 008 muestra «ventas por zona», y el guard de 003/AC-20 —una
-- zona con tickets emitidos no se borra— consulta `tickets` por `zone_id`. Sin
-- índice, las dos cosas recorren la tabla.
--
-- Los demás FK que reporta son columnas de auditoría (`original_owner_id`,
-- `actor_id`, `corrects_id`, `*.created_by`) o están cubiertos por el prefijo de
-- un índice compuesto. Aceptados en advisor-baseline.md.

create index tickets_zone_idx on public.tickets (zone_id);
