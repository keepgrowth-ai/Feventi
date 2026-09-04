-- 008 · T-01 … T-05 · Art. 5 y 7.5
--
-- Todo lo que el organizador ve del dinero y de la puerta sale de estas vistas.
-- Ninguna deja llegar a una fila individual: es la diferencia entre «vendiste
-- 340 entradas» y «Ana Fernández compró la butaca C-12», y la segunda no es del
-- organizador (D-06, Art. 7.5).
--
-- ── AC-04 CONTRA AC-02, y por qué gana AC-02 ───────────────────────────────
--
-- El spec pide `security_invoker = true` «para que la RLS del organizador se
-- aplique dentro de la vista y no la esquive» (AC-04). Con invoker estas vistas
-- salen EN CERO: agregan `orders`, `order_items`, `payments` y `tickets`, y la
-- RLS de esas cuatro tablas deja al organizador sin una sola fila — es la misma
-- trampa que dejó vacía la wallet en 0042.
--
-- Para que invoker funcionara habría que dar al organizador políticas de lectura
-- sobre esas tablas. Y eso es exactamente lo que **AC-02 prohíbe**: «el
-- organizador no lee orders, order_items, payments ni tickets. Nada individual,
-- ni por PostgREST ni por RPC». Los dos criterios no pueden cumplirse a la vez.
--
-- Gana AC-02, porque es la regla de privacidad (Art. 7.5) y AC-04 solo era el
-- medio que se supuso para llegar a ella. Las vistas van `definer` con un filtro
-- explícito por organizador, que es MÁS estrecho que cuatro políticas nuevas y
-- cabe en una línea auditable. Anotado en `advisor-baseline.md`.

-- ── La comisión de una orden ────────────────────────────────────────────────
-- En su propia función porque la calculan la vista de ventas y, en Fase 2, la
-- liquidación. Dos copias de esta fórmula es dos números distintos en dos
-- pantallas, y el organizador reclamando con razón.
create or replace function private.order_commission_cents(o public.orders)
returns int language sql immutable set search_path = '' as $$
  select case
    when o.service_charge_payer = 'fan' then o.service_charge_cents
    -- El organizador absorbe: la orden guarda 0 porque el fan no lo pagó, así
    -- que se recalcula desde el subtotal con el bps CONGELADO en la orden.
    else round(o.subtotal_cents * o.service_charge_bps / 10000.0)::int
  end
$$;

revoke all on function private.order_commission_cents(public.orders) from public, anon, authenticated;

-- ── Ventas del evento ───────────────────────────────────────────────────────
--
-- Art. 5: cada concepto en su columna, con su nombre. Nada de un total ambiguo
-- que después alguien lee como «mi plata».
--
-- LO DELICADO ES QUÉ ES «BRUTO», y depende de quién paga el cargo:
--
--   payer = 'fan'        el fan paga  subtotal + cargo.  Feventi se queda el
--                        cargo; el organizador recibe el subtotal.
--   payer = 'organizer'  el fan paga  subtotal.          Feventi cobra el cargo
--                        AL ORGANIZADOR, que recibe subtotal - cargo.
--
-- Si «bruto» fuera el subtotal en los dos casos, restar la comisión cobraría dos
-- veces al organizador que ya la trasladó al fan. Por eso bruto es **lo que se
-- cobró al fan** (`orders.total_cents`), y entonces
--
--     neto = bruto - comisión - devoluciones
--
-- se cumple literalmente en los dos casos (AC-09). Comprobado en la suite con un
-- evento de cada tipo, que es la única forma de saber que no se cobra dos veces.
--
-- El otro detalle: cuando el organizador absorbe el cargo, el
-- `service_charge_cents` de la orden vale CERO — la orden guarda lo que pagó el
-- fan, y el fan no lo pagó. Ahí la comisión se recalcula desde `subtotal_cents`
-- con el `service_charge_bps` **congelado en la orden** (AC-10), nunca desde el
-- evento: cambiar la política mañana no puede reescribir lo ya vendido.
create view public.v_event_sales with (security_invoker = false) as
select
  e.id                                   as event_id,
  e.capacity,
  e.service_charge_bps,
  e.service_charge_payer,
  e.payout_policy,
  -- AC-16: nunca sin denominador. El denominador es `capacity`, aquí al lado.
  (select count(*) from public.tickets t
    where t.event_id = e.id and t.status not in ('void', 'refunded')) as tickets_sold,
  coalesce(sum(o.total_cents), 0)::bigint as gross_cents,
  coalesce(sum(private.order_commission_cents(o.*)), 0)::bigint as feventi_commission_cents,
  -- Devoluciones: lo que la pasarela devolvió, esté la orden como esté. Hoy no
  -- hay nada que las produzca (Fase 2), pero la columna existe y la aritmética
  -- cuadra desde el primer día en vez de añadirse con prisa.
  coalesce(r.refunds, 0)::bigint          as refunds_cents,
  (coalesce(sum(o.total_cents), 0)
   - coalesce(sum(private.order_commission_cents(o.*)), 0)
   - coalesce(r.refunds, 0))::bigint      as net_estimated_cents
from public.events e
-- AC-11: solo lo COBRADO. Ni reservado, ni en curso.
--
-- `paid_at is not null` y no `status = 'paid'` a secas: en Fase 2 una orden
-- reembolsada pasará a `refunded` y su dinero SÍ se cobró. Dejarla fuera la
-- haría desaparecer del bruto Y aparecer en devoluciones, restando dos veces.
left join public.orders o
  on o.event_id = e.id and o.paid_at is not null and o.status in ('paid', 'refunded')
left join lateral (
  select sum(p.amount_cents) as refunds
    from public.payments p
    join public.orders o2 on o2.id = p.order_id
   where o2.event_id = e.id and p.status = 'refunded'
) r on true
-- ESTE filtro es la única protección: la vista salta la RLS. No se toca sin
-- pensar, igual que el de `v_my_tickets`.
where e.organizer_id = any (private.auth_organizer_ids())
   or private.auth_is_admin()
group by e.id, r.refunds;

grant select on public.v_event_sales to authenticated;

comment on view public.v_event_sales is
  'Art. 5. bruto = lo cobrado al fan, para que neto = bruto - comision - devoluciones valga tanto con el cargo pagado por el fan como absorbido por el organizador. La comision usa el bps CONGELADO en la orden.';

-- ── Ventas por fase ─────────────────────────────────────────────────────────
--
-- AC-06: una fase con 1 a 4 entradas vendidas no se expone sola, se suma a
-- «Otras fases». El umbral es de privacidad, no de estética: con dos entradas en
-- una fase de un evento pequeño, quien conozca a los compradores los identifica.
--
-- El coste es real y conviene decirlo en vez de descubrirlo: un evento recién
-- abierto puede tener TODAS sus fases por debajo del umbral y mostrar una sola
-- barra. Es preferible a un umbral variable según el tamaño del evento, que es
-- una regla que nadie recuerda al mirar la pantalla.
create view public.v_event_phase_sales with (security_invoker = false) as
with visible as (
  select e.id as event_id
    from public.events e
   where e.organizer_id = any (private.auth_organizer_ids())
      or private.auth_is_admin()
),
por_fase as (
  select
    p.event_id,
    p.id                                          as phase_id,
    p.name,
    p.kind,
    p.starts_at,
    p.ends_at,
    p.sort_order,
    -- `filter` y no solo el join: un LEFT JOIN a `orders` que no casa NO borra
    -- la fila de `order_items`, así que sin esto contaría también las reservas
    -- sin pagar. Es el error que hincha las ventas de una fase recién abierta.
    count(oi.id) filter (where o.id is not null)  as tickets,
    coalesce(sum(oi.unit_price_cents) filter (where o.id is not null), 0)::bigint as gross_cents
  from public.price_phases p
  join visible v on v.event_id = p.event_id
  left join public.price_tiers pt on pt.phase_id = p.id
  left join public.order_items oi on oi.price_tier_id = pt.id
  left join public.orders o
    on o.id = oi.order_id and o.paid_at is not null and o.status in ('paid', 'refunded')
  -- `oi` sin orden pagada no cuenta, pero la fase sigue apareciendo con 0.
  group by p.event_id, p.id, p.name, p.kind, p.starts_at, p.ends_at, p.sort_order
)
select event_id, phase_id, name, kind, starts_at, ends_at, sort_order, tickets, gross_cents
  from por_fase
 where tickets = 0 or tickets >= 5
union all
select event_id, null::uuid, 'Otras fases', null::public.phase_kind,
       null::timestamptz, null::timestamptz, 999, sum(tickets), sum(gross_cents)
  from por_fase
 where tickets between 1 and 4
 group by event_id;

grant select on public.v_event_phase_sales to authenticated;

comment on view public.v_event_phase_sales is
  'AC-06: una fase con 1 a 4 entradas se agrega en «Otras fases». Con tan pocas, quien conozca a los compradores los identifica.';

-- ── Accesos: la misma vista de 006, ahora también para el organizador ───────
--
-- 006 la creó filtrada a `event_staff`. El organizador no es staff de su propio
-- evento —y no debe serlo— pero sí necesita los accesos en vivo (008, bloque 5).
--
-- Se amplía el filtro en vez de crear una vista paralela: dos vistas que cuentan
-- lo mismo se desincronizan el día que alguien corrija una.
--
-- Sigue siendo `definer`, y aquí la razón es la más fuerte de todas: `checkins`
-- guarda `scanned_code`, el token CRUDO de cada escaneo. Abrir esa tabla al
-- organizador para que pueda contar cuatro números sería regalarle la credencial
-- de cada asistente.
create or replace view public.v_gate_stats with (security_invoker = false) as
select
  c.event_id,
  c.gate,
  count(*)                                                  as scans,
  count(*) filter (where c.result = 'allowed')              as allowed,
  count(*) filter (where c.result = 'manual_review')        as manual_review,
  count(*) filter (where c.result = 'already_used')         as already_used,
  count(*) filter (where c.result = 'denied')               as denied,
  count(*) filter (where c.reason = 'screenshot_suspected') as screenshots,
  (select count(*) from public.tickets t
    where t.event_id = c.event_id and t.status <> 'void')   as tickets_total,
  (select count(*) from public.tickets t
    where t.event_id = c.event_id and t.status = 'used')    as tickets_used
from public.checkins c
where exists (
  -- El staff, en su puerta.
  select 1 from public.event_staff es
   where es.event_id   = c.event_id
     and es.gate       = c.gate
     and es.profile_id = (select auth.uid())
     and es.revoked_at is null
)
   or exists (
  -- El organizador del evento, en todas sus puertas.
  select 1 from public.events e
   where e.id = c.event_id
     and (e.organizer_id = any (private.auth_organizer_ids()) or private.auth_is_admin())
)
group by c.event_id, c.gate;

grant select on public.v_gate_stats to authenticated;

comment on view public.v_gate_stats is
  'AC-26 de 006 y bloque 5 de 008. definer a proposito: checkins guarda scanned_code, el token crudo de cada escaneo. Abrir la tabla al organizador para contar cuatro numeros seria regalar la credencial de cada asistente.';

-- ── Índice (AC-20) ──────────────────────────────────────────────────────────
-- `tickets (event_id, status)` y `orders (event_id, status)` ya existen.
create index checkins_event_result_idx on public.checkins (event_id, result);
