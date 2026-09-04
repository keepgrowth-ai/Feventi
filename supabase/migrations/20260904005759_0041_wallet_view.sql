-- 005 · T-01 · Art. 2
--
-- La wallet en una sola consulta, con la regla del QR ya resuelta del lado del
-- servidor.
--
-- OJO: esta versión sale VACÍA. Va con `security_invoker = true`, pero la vista
-- hace join con events, zones y venues, que están limitadas al organizador — así
-- que el fan ve sus tickets y 0 eventos, y el join no devuelve nada. Corregido
-- en 0042.

create view public.v_my_tickets with (security_invoker = true) as
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
left join public.seats s on s.id = t.seat_id;

comment on view public.v_my_tickets is
  'La wallet. `qr_state` es la regla del Art. 2 resuelta en un solo sitio.';

grant select on public.v_my_tickets to authenticated;
