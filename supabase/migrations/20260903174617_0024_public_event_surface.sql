-- 003 · T-12 … T-14 · Art. 5
--
-- La ÚNICA superficie de `public` a la que anon tiene acceso.
--
-- Las vistas van con security_invoker = false: corren con los privilegios de su
-- dueño y por eso SALTAN la RLS de las tablas. Eso las hace útiles y peligrosas:
-- su `where` es la única protección que queda. Cambiarlo sin pensar abre el
-- inventario entero.
--
-- OJO: 0025 concede `execute` de total_with_charge a anon. Con
-- security_invoker = false, los privilegios de las TABLAS se comprueban contra
-- el dueño de la vista, pero el EXECUTE de una FUNCIÓN se comprueba contra quien
-- consulta — así que sin ese grant la vista revienta para anon.

-- ── El dinero se calcula UNA vez ────────────────────────────────────────────
-- AC-15: el desglose tiene que sumar exacto al total. La forma de garantizarlo
-- no es redondear con cuidado en dos sitios: es calcular el total y RESTAR.
-- Así `base + cargo = total` es una identidad aritmética, no una coincidencia.
--
-- Con una sola línea las dos formas coinciden (sumar un entero antes de
-- redondear no cambia el redondeo). Donde importa es en 004, con varias
-- entradas: 7 × S/ 9.25 al 6 % da 392 por línea y 389 sobre el subtotal — tres
-- céntimos de diferencia. Ver specs/003-detalle-evento/plan.md.
create or replace function private.total_with_charge(
  p_price_cents int, p_bps int, p_payer public.charge_payer
) returns int language sql immutable set search_path = '' as $$
  select case
    when p_payer = 'fan' then round(p_price_cents * (1 + p_bps / 10000.0))::int
    else p_price_cents
  end
$$;

-- ── Catálogo: listable por anon (lo consume 002) ────────────────────────────
create view public.v_event_public with (security_invoker = false) as
with tier as (
  select
    t.event_id,
    private.total_with_charge(t.price_cents, e.service_charge_bps, e.service_charge_payer)
      as total_cents,
    t.currency
  from public.price_tiers t
  join public.events       e on e.id = t.event_id
  join public.price_phases p on p.id = t.phase_id
  where now() >= p.starts_at and now() < p.ends_at        -- solo la fase activa
    and t.stock - t.reserved - t.sold > 0                  -- solo lo comprable
)
select
  e.id,
  e.slug,
  e.title,
  e.category,
  e.hero_image_url,
  e.starts_at,
  e.doors_at,
  e.timezone,
  e.capacity,
  e.max_per_user,
  e.resale_enabled,
  e.featured_at,
  v.name  as venue_name,
  v.city  as venue_city,
  o.trade_name as organizer_name,
  -- AC-08: el mínimo entre los tiers comprables de la fase activa, con el cargo
  -- ya incluido si lo paga el fan (AC-09).
  (select min(total_cents) from tier where tier.event_id = e.id) as from_price_cents,
  (select currency from tier where tier.event_id = e.id limit 1) as currency,
  -- AC-10 / AC-11: sin fase activa no hay precio comprable, y hay que decir
  -- cuándo abre la siguiente en lugar de mostrar un hueco.
  public.active_phase_id(e.id) is not null as sale_open,
  (select min(p.starts_at) from public.price_phases p
    where p.event_id = e.id and p.starts_at > now())        as next_phase_starts_at,
  coalesce((select sum(t.stock - t.reserved - t.sold)
              from public.price_tiers t
              join public.price_phases p on p.id = t.phase_id
             where t.event_id = e.id
               and now() >= p.starts_at and now() < p.ends_at), 0) as available_now
from public.events e
left join public.venues     v on v.id = e.venue_id
left join public.organizers o on o.id = e.organizer_id
-- AC-01, AC-04, AC-05: publicado, público, y que no haya pasado.
where e.status = 'published'
  and e.visibility = 'public'
  and (e.starts_at is null or e.starts_at > now());

comment on view public.v_event_public is
  'Catálogo público. security_invoker = false: salta la RLS, así que este WHERE es la única protección. No exponer review_checklist, payout_policy ni created_by (AC-07).';

-- ── Detalle: por SLUG, no listable ──────────────────────────────────────────
-- Va como función y no como vista a propósito. Un evento `unlisted` no aparece
-- en el catálogo pero SÍ se abre por su enlace (002, AC-02). Si estuviera en una
-- vista, anon la consultaría sin filtro y enumeraría todo lo no listado — que es
-- exactamente lo que "no listado" promete evitar. Pedir el slug es la diferencia
-- entre "no aparece" y "no existe para ti".
create or replace function public.get_public_event(p_slug text)
returns jsonb language sql stable security definer set search_path = '' as $$
  with ev as (
    select e.*, v.name as venue_name, v.city as venue_city, v.address as venue_address,
           o.trade_name as organizer_name
    from public.events e
    left join public.venues     v on v.id = e.venue_id
    left join public.organizers o on o.id = e.organizer_id
    where e.slug = p_slug
      and e.status = 'published'                    -- AC-12: ningún otro estado
      and e.visibility in ('public', 'unlisted')    -- AC-03: 'private' no
  )
  select case when ev.id is null then null else jsonb_build_object(
    'id', ev.id,
    'slug', ev.slug,
    'title', ev.title,
    'description', ev.description,
    'category', ev.category,
    'hero_image_url', ev.hero_image_url,
    'starts_at', ev.starts_at,
    'doors_at', ev.doors_at,
    'timezone', ev.timezone,
    'venue', jsonb_build_object('name', ev.venue_name, 'city', ev.venue_city,
                                'address', ev.venue_address),
    'organizer_name', ev.organizer_name,
    'max_per_user', ev.max_per_user,
    'resale_enabled', ev.resale_enabled,
    'max_resales', ev.max_resales,
    'service_charge_bps', ev.service_charge_bps,
    'service_charge_payer', ev.service_charge_payer,
    'qr_lead_days', ev.qr_lead_days,
    'nomination_mode', ev.nomination_mode,
    'sale_open', public.active_phase_id(ev.id) is not null,

    -- Línea de fases completa: la activa, las futuras con su fecha, las pasadas
    -- apagadas. No se ocultan (design-system §5).
    'phases', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', p.id, 'name', p.name, 'kind', p.kind,
               'starts_at', p.starts_at, 'ends_at', p.ends_at,
               'state', case when now() < p.starts_at then 'future'
                             when now() >= p.ends_at  then 'past'
                             else 'active' end,
               'tickets', (select coalesce(sum(t.stock - t.reserved - t.sold), 0)
                             from public.price_tiers t where t.phase_id = p.id)
             ) order by p.starts_at)
        from public.price_phases p where p.event_id = ev.id), '[]'::jsonb),

    -- Zonas, con sus segmentos anidados dentro (nunca como hermanos).
    'zones', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', z.id, 'name', z.name, 'kind', z.kind,
               'numbered', z.numbered, 'notes', z.notes,
               'tiers', (
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'tier_id', t.id,
                          'segment_id', t.segment_id,
                          'segment_label', s.label,
                          'row_from', s.row_from,
                          'row_to', s.row_to,
                          'phase_id', t.phase_id,
                          'phase_name', p.name,
                          'phase_active', (now() >= p.starts_at and now() < p.ends_at),
                          'base_cents', t.price_cents,
                          'total_cents', private.total_with_charge(
                                           t.price_cents, ev.service_charge_bps,
                                           ev.service_charge_payer),
                          -- AC-15: la diferencia, nunca un redondeo aparte.
                          'service_charge_cents', private.total_with_charge(
                                           t.price_cents, ev.service_charge_bps,
                                           ev.service_charge_payer) - t.price_cents,
                          'currency', t.currency,
                          'available', greatest(t.stock - t.reserved - t.sold, 0),
                          'stock', t.stock
                        ) order by s.sort_order nulls first, t.price_cents desc), '[]'::jsonb)
                 from public.price_tiers t
                 join public.price_phases p on p.id = t.phase_id
                 left join public.zone_segments s on s.id = t.segment_id
                 where t.zone_id = z.id
               )
             ) order by z.sort_order)
        from public.zones z where z.event_id = ev.id), '[]'::jsonb)
  ) end
  from ev
$$;

revoke all on function public.get_public_event(text) from public;
grant execute on function public.get_public_event(text) to anon, authenticated;
revoke all on function private.total_with_charge(int, int, public.charge_payer)
  from public, anon, authenticated;

-- ── Disponibilidad por tier: para el organizador, no para anon ──────────────
create view public.v_event_availability with (security_invoker = true) as
select
  t.id          as tier_id,
  t.event_id,
  t.zone_id,
  z.name        as zone_name,
  t.segment_id,
  s.label       as segment_label,
  t.phase_id,
  p.name        as phase_name,
  (now() >= p.starts_at and now() < p.ends_at) as phase_active,
  t.price_cents,
  t.currency,
  t.stock,
  t.reserved,
  t.sold,
  -- AC-10: nunca negativo. El check de la tabla lo garantiza, el greatest lo
  -- hace evidente al leer.
  greatest(t.stock - t.reserved - t.sold, 0) as available
from public.price_tiers t
join public.zones        z on z.id = t.zone_id
join public.price_phases p on p.id = t.phase_id
left join public.zone_segments s on s.id = t.segment_id;

comment on view public.v_event_availability is
  'security_invoker = true: la RLS del que consulta se aplica DENTRO de la vista, así que no la esquiva. Para organizador y Admin, no para anon.';

-- AC-13: anon lee las vistas públicas y nada más.
grant select on public.v_event_public       to anon, authenticated;
grant select on public.v_event_availability to authenticated;
