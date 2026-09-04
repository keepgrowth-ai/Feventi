-- Cierra un hueco que destapó la semilla de 006, no una prueba.
--
-- `price_tiers` y `tickets` llevan `event_id` denormalizado JUNTO a `zone_id`
-- (y `phase_id`). Las dos FK eran simples, así que nada obligaba a que la zona
-- perteneciera al evento de la fila: un tier del evento A podía apuntar a una
-- zona del evento B y el motor lo aceptaba.
--
-- Cómo salió: escribiendo la semilla del validador se reusó por error un uuid de
-- zona de otro evento. El insert NO falló por lo que debía — falló más adelante,
-- en el trigger de aforo, con un mensaje sobre capacidad que no tenía nada que
-- ver:
--
--     el stock de la zona General en esta fase (400) supera su aforo (300)
--
-- 300 era el aforo de la zona de OTRO evento. Un error así cuesta media hora
-- buscando en el sitio equivocado, y en producción habría dejado un precio del
-- evento A visible en el catálogo del evento B.
--
-- La solución es la que este esquema ya usa en zones/zone_segments/seats: FK
-- COMPUESTA. No es un trigger que se pueda desactivar ni un check que no puede
-- mirar otra tabla; es el motor.
--
-- Comprobado antes de aplicar: 0 filas incumplían las tres.

alter table public.zones
  add constraint zones_event_id_id_key unique (event_id, id);
alter table public.price_phases
  add constraint price_phases_event_id_id_key unique (event_id, id);

alter table public.price_tiers
  add constraint price_tiers_zone_in_event_fk
  foreign key (event_id, zone_id) references public.zones (event_id, id)
  on delete cascade;

alter table public.price_tiers
  add constraint price_tiers_phase_in_event_fk
  foreign key (event_id, phase_id) references public.price_phases (event_id, id)
  on delete cascade;

alter table public.tickets
  add constraint tickets_zone_in_event_fk
  foreign key (event_id, zone_id) references public.zones (event_id, id);

comment on constraint price_tiers_zone_in_event_fk on public.price_tiers is
  'La zona pertenece al evento de la fila. Sin esto, un uuid equivocado colaba un precio de un evento en el catalogo de otro, y el error aparecia en el trigger de aforo con un mensaje que no tenia nada que ver.';
