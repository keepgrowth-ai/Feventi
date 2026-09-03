-- Corrige 0033/0037. Lo destapó la suite de pruebas al reservar dos veces en la
-- misma transacción:
--
--   ERROR: relation "_items" already exists
--
-- La función creaba una tabla temporal `on commit drop`, así que la segunda
-- llamada dentro de una transacción reventaba. Por PostgREST cada RPC es su
-- propia transacción y en producción no se habría visto — hasta el día en que
-- otra función llame a esta dos veces, o se haga una carga por lotes. Un bug
-- que solo aparece bajo un patrón de uso concreto es peor que uno visible.
--
-- Se quita la tabla temporal. En su lugar, una función que devuelve conjunto:
-- una sola definición, ocho usos limpios, y la función queda REENTRANTE. De
-- paso desaparece la creación de una tabla temporal por cada reserva, que a
-- volumen alto es churn de catálogo.

create or replace function private.order_items_of(p_items jsonb)
returns table (tier_id uuid, seat_id uuid)
language sql immutable set search_path = '' as $$
  select (i ->> 'tier_id')::uuid,
         nullif(i ->> 'seat_id', '')::uuid
    from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) i
$$;

revoke all on function private.order_items_of(jsonb) from public, anon, authenticated;

create or replace function public.reserve_order(
  p_event_id uuid,
  p_items    jsonb    -- [{"tier_id": "...", "seat_id": "..."|null}, ...] una entrada por elemento
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := (select auth.uid());
  v_order_id  uuid;
  v_ev        record;
  v_count     int;
  v_existing  int;
  v_subtotal  int;
  v_charge    int;
  v_total     int;
  v_tier      record;
begin
  if v_uid is null then
    raise exception 'no autenticado' using errcode = '28000';
  end if;

  v_count := jsonb_array_length(coalesce(p_items, '[]'::jsonb));
  if v_count = 0 then
    raise exception 'no hay entradas que reservar' using errcode = '22023';
  end if;

  -- ── 1. AC-01: solo `published` vende. Ni `paused`, ni `setup` (007/AC-20) ──
  select e.id, e.status, e.max_per_user, e.service_charge_bps,
         e.service_charge_payer, e.qr_lead_days, e.starts_at
    into v_ev
    from public.events e where e.id = p_event_id;

  if v_ev.id is null then
    raise exception 'evento inexistente' using errcode = '22023';
  end if;
  if v_ev.status <> 'published' then
    raise exception 'este evento no está a la venta (está en %)', v_ev.status
      using errcode = '22023';
  end if;

  -- ── 2. AC-02: todos los tiers son del evento y su fase está activa ────────
  if exists (
    select 1 from private.order_items_of(p_items) it
    left join public.price_tiers t on t.id = it.tier_id
    where t.id is null or t.event_id <> p_event_id
  ) then
    raise exception 'alguna entrada no pertenece a este evento' using errcode = '22023';
  end if;

  if exists (
    select 1 from private.order_items_of(p_items) it
    join public.price_tiers  t on t.id = it.tier_id
    join public.price_phases p on p.id = t.phase_id
    where not (now() >= p.starts_at and now() < p.ends_at)
  ) then
    raise exception 'la fase de venta de alguna entrada no está activa'
      using errcode = '22023';
  end if;

  -- ── 3. AC-08: límite por usuario (Art. 11) ────────────────────────────────
  -- Cuenta lo ya emitido MÁS las reservas vivas: si no, alguien abre cinco
  -- pestañas y se lleva el doble del límite.
  select coalesce((select count(*) from public.tickets
                    where event_id = p_event_id and owner_id = v_uid
                      and status not in ('void', 'refunded')), 0)
       + coalesce((select count(*) from public.order_items oi
                    join public.orders o on o.id = oi.order_id
                   where o.event_id = p_event_id and o.buyer_id = v_uid
                     and o.status in ('draft','reserved','awaiting_payment','failed','paid')), 0)
    into v_existing;

  if v_existing + v_count > v_ev.max_per_user then
    raise exception
      'el límite es % entradas por usuario para este evento, y ya tienes %',
      v_ev.max_per_user, v_existing using errcode = '22023';
  end if;

  -- ── 4. AC-05: bloquear los tiers, EN ORDEN ASCENDENTE DE ID ───────────────
  -- El orden no es un detalle: dos sesiones que pidan los mismos dos tiers en
  -- orden distinto se abrazan en un deadlock. Ordenar el lock siempre igual lo
  -- hace imposible.
  for v_tier in
    select t.id, t.stock, t.reserved, t.sold, t.price_cents, t.zone_id,
           (select count(*) from private.order_items_of(p_items) it where it.tier_id = t.id) as asked
      from public.price_tiers t
     where t.id in (select distinct tier_id from private.order_items_of(p_items))
     order by t.id            -- ← esto evita el deadlock
       for update
  loop
    -- ── 5. Disponibilidad, ya con la fila bloqueada ─────────────────────────
    if v_tier.stock - v_tier.reserved - v_tier.sold < v_tier.asked then
      raise exception
        'solo quedan % entradas de esa zona y se piden %',
        greatest(v_tier.stock - v_tier.reserved - v_tier.sold, 0), v_tier.asked
        using errcode = '23514';
    end if;
  end loop;

  -- ── 6. AC-07: asientos bloqueados ─────────────────────────────────────────
  -- Que el asiento pertenezca a la zona y al segmento del tier ya lo garantiza
  -- la FK compuesta de 003, así que aquí solo queda el bloqueo operativo.
  if exists (
    select 1 from private.order_items_of(p_items) it
    join public.seats s on s.id = it.seat_id
    where s.blocked
  ) then
    raise exception 'alguno de los asientos elegidos no está disponible'
      using errcode = '22023';
  end if;

  -- Una zona numerada exige asiento; una de pie no lo admite.
  if exists (
    select 1 from private.order_items_of(p_items) it
    join public.price_tiers t on t.id = it.tier_id
    join public.zones       z on z.id = t.zone_id
    where (z.kind = 'seated'   and it.seat_id is null)
       or (z.kind = 'standing' and it.seat_id is not null)
  ) then
    raise exception 'una zona numerada exige elegir asiento y una de pie no lo admite'
      using errcode = '22023';
  end if;

  -- El asiento tiene que ser de la zona del tier.
  if exists (
    select 1 from private.order_items_of(p_items) it
    join public.price_tiers t on t.id = it.tier_id
    join public.seats       s on s.id = it.seat_id
    where s.zone_id <> t.zone_id
  ) then
    raise exception 'el asiento no pertenece a la zona de esa entrada'
      using errcode = '22023';
  end if;

  -- ── 7. AC-09, AC-10: crear la orden con el precio y la política CONGELADOS ─
  insert into public.orders (
    event_id, buyer_id, status,
    service_charge_payer, service_charge_bps,
    reserved_until
  ) values (
    p_event_id, v_uid, 'reserved',
    v_ev.service_charge_payer, v_ev.service_charge_bps,
    now() + interval '15 minutes'
  ) returning id into v_order_id;

  -- El unique de order_items.seat_id es lo que rechaza al perdedor de la
  -- carrera por un asiento (AC-06): un error de constraint, no una consulta.
  begin
    insert into public.order_items (order_id, price_tier_id, seat_id, unit_price_cents)
    select v_order_id, it.tier_id, it.seat_id, t.price_cents
      from private.order_items_of(p_items) it
      join public.price_tiers t on t.id = it.tier_id;
  exception
    when unique_violation then
      raise exception
        'alguien acaba de tomar uno de esos asientos: elige otro'
        using errcode = '23505';
  end;

  -- ── 8. AC-03: subir `reserved` en la MISMA transacción ────────────────────
  -- No existe orden `reserved` sin su contrapartida en el tier. Y el check
  -- `reserved + sold <= stock` de 003 es la última red: si la aritmética de
  -- arriba se equivocara, esto revienta antes de comprometer nada.
  update public.price_tiers t
     set reserved = t.reserved + it.asked
    from (select tier_id, count(*) as asked from private.order_items_of(p_items) group by tier_id) it
   where t.id = it.tier_id;

  -- ── 9. AC-18: el dinero. El cargo se redondea UNA vez, sobre el SUBTOTAL ──
  -- Con 7 entradas de S/ 9.25 al 6 %, por línea sale 392 y sobre el subtotal
  -- 389: tres céntimos que no cierran en la conciliación.
  select coalesce(sum(unit_price_cents), 0) into v_subtotal
    from public.order_items where order_id = v_order_id;

  v_total  := private.total_with_charge(v_subtotal, v_ev.service_charge_bps,
                                        v_ev.service_charge_payer);
  v_charge := v_total - v_subtotal;   -- la diferencia, nunca un redondeo aparte

  update public.orders
     set subtotal_cents = v_subtotal,
         service_charge_cents = v_charge,
         total_cents = v_total
   where id = v_order_id;

  return v_order_id;
end $$;

revoke all on function public.reserve_order(uuid, jsonb) from public, anon;
grant execute on function public.reserve_order(uuid, jsonb) to authenticated;

comment on function public.reserve_order(uuid, jsonb) is
  'Reentrante: sin tabla temporal. AC-05 bloquea los tiers con for update EN ORDEN DE ID, o dos sesiones con los mismos dos tiers se abrazan en un deadlock.';
