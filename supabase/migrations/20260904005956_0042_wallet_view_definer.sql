-- Corrige 0041. La wallet salía VACÍA.
--
-- `security_invoker = true` parecía lo correcto —la RLS de `tickets` se aplica
-- dentro— pero la vista hace join con `events`, `zones` y `venues`, y esas están
-- limitadas al organizador. El fan ve sus 3 tickets y 0 eventos, así que el join
-- no devuelve ninguna fila. Comprobado:
--
--   tickets_visibles 3 · eventos_visibles 0 · zonas_visibles 0 · wallet 0
--
-- Dos salidas:
--
--   a) Dar a `authenticated` políticas de lectura sobre events, zones y venues
--      para los eventos donde tenga un ticket. Serían tres o cuatro políticas
--      más, y le abrirían la fila ENTERA del evento —incluidos los campos de
--      operación— a cualquiera con una entrada.
--
--   b) Vista `security definer` con un filtro por dueño.
--
-- Se elige (b). El filtro es `t.owner_id = auth.uid()`: más estrecho que el de
-- `v_event_public`, y trivial de auditar — una línea, no cuatro políticas
-- repartidas. El coste es el mismo `ERROR` del linter, ya argumentado en
-- advisor-baseline.md para las vistas públicas.
--
-- `auth.uid()` funciona igual en una vista definer: lee el claim del JWT de la
-- petición, no depende del rol con el que se ejecute la vista.

drop view public.v_my_tickets;

create view public.v_my_tickets with (security_invoker = false) as
select
  t.id, t.code, t.status, t.face_value_cents, t.resale_count,
  t.qr_available_from, t.issued_at, t.used_at,
  t.holder_name, t.holder_dni_last4, t.owner_id,
  e.id as event_id, e.slug as event_slug, e.title as event_title,
  e.starts_at, e.doors_at, e.timezone, e.status as event_status,
  e.qr_lead_days, e.resale_enabled, e.max_resales,
  v.name as venue_name, v.city as venue_city,
  z.name as zone_name, z.kind as zone_kind,
  s.row_label, s.seat_number,
  (e.starts_at is not null and e.starts_at < now()) as is_past,
  case
    when t.status = 'used'                              then 'spent'
    when t.status <> 'active'                           then 'disabled'
    when e.status = 'cancelled'                         then 'disabled'
    when t.qr_available_from is not null
         and now() < t.qr_available_from                then 'too_early'
    else 'available'
  end as qr_state,
  case when t.status <> 'active' then t.status::text end as disabled_reason
from public.tickets t
join public.events e on e.id = t.event_id
left join public.venues v on v.id = e.venue_id
join public.zones z on z.id = t.zone_id
left join public.seats s on s.id = t.seat_id
-- ESTE filtro es la única protección que queda, porque la vista salta la RLS.
-- Tocarlo sin pensar abre la wallet de todo el mundo.
where t.owner_id = (select auth.uid());

comment on view public.v_my_tickets is
  'La wallet. security_invoker = false porque hace join con events/zones/venues, que están limitadas al organizador — con invoker la wallet salía vacía. El WHERE por owner_id es la única protección: no se toca sin pensar.';

grant select on public.v_my_tickets to authenticated;
