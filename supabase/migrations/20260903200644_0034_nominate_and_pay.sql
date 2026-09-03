-- 004 · T-15 … T-19 · Art. 2.1, 7.1

-- ── Nominación: el DNI se hashea en el SERVIDOR (AC-33) ─────────────────────
-- Si el cliente pudiera escribir attendee_dni_hash, copiaría el de otra persona
-- y se haría pasar por ella en puerta.
create or replace function public.set_item_attendee(
  p_item_id uuid,
  p_name    text,
  p_dni     text
) returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_status public.order_status;
begin
  select o.status into v_status
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
   where oi.id = p_item_id and o.buyer_id = v_uid;

  if v_status is null then
    raise exception 'esa entrada no es de una orden tuya' using errcode = '42501';
  end if;
  if v_status not in ('draft', 'reserved', 'failed') then
    raise exception 'la orden ya está en % y no admite cambios de nominación', v_status
      using errcode = '22023';
  end if;
  if coalesce(btrim(p_name), '') = '' then
    raise exception 'el nombre del asistente es obligatorio' using errcode = '22023';
  end if;

  update public.order_items
     set attendee_name      = btrim(p_name),
         attendee_dni_hash  = private.hash_dni(p_dni),   -- valida 8 dígitos
         attendee_dni_last4 = right(p_dni, 4),
         nominated_at       = now()
   where id = p_item_id;
end $$;

-- ── start_payment: AC-30, AC-31 ─────────────────────────────────────────────
create or replace function public.start_payment(p_order_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_o   record;
  v_mode public.nomination_mode;
  v_missing int;
begin
  select o.*, e.nomination_mode into v_o
    from public.orders o join public.events e on e.id = o.event_id
   where o.id = p_order_id and o.buyer_id = v_uid
     for update;

  if v_o.id is null then
    raise exception 'orden inexistente o no es tuya' using errcode = '42501';
  end if;
  if v_o.status not in ('reserved', 'failed') then
    raise exception 'no se puede pagar una orden en %', v_o.status using errcode = '22023';
  end if;
  if v_o.reserved_until < now() then
    raise exception 'la reserva venció; vuelve a elegir tus entradas' using errcode = '22023';
  end if;

  -- AC-30: sin DNI declarado no se paga. Es lo que permite nominar y validar
  -- en puerta (Art. 7.2).
  if not exists (select 1 from public.profile_identity where user_id = v_uid) then
    raise exception 'declara tu DNI antes de pagar' using errcode = '22023';
  end if;

  -- AC-31: en modo strict, sin nominar no se paga. En flexible sí, y el ticket
  -- sale sin holder_dni_hash — que es lo que hace que en puerta salga
  -- manual_review (006/AC-16).
  v_mode := v_o.nomination_mode;
  if v_mode = 'strict' then
    select count(*) into v_missing
      from public.order_items
     where order_id = p_order_id and nominated_at is null;
    if v_missing > 0 then
      raise exception
        'este evento exige nominar cada entrada: faltan % por nominar', v_missing
        using errcode = '22023';
    end if;
  end if;

  -- Bloquea el botón: mientras está aquí no se puede pagar dos veces.
  update public.orders set status = 'awaiting_payment' where id = p_order_id;
end $$;

create or replace function public.fail_payment(p_order_id uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid());
begin
  -- `failed` CONSERVA la reserva hasta reserved_until: un reintento con otra
  -- tarjeta no debe perder los asientos.
  update public.orders
     set status = 'failed', failed_at = now()
   where id = p_order_id
     and (buyer_id = v_uid or private.auth_is_admin())
     and status = 'awaiting_payment';

  if not found then
    raise exception 'la orden no está esperando pago' using errcode = '22023';
  end if;
end $$;

-- ── confirm_payment: la única vía de emisión, e idempotente ─────────────────
-- AC-19, AC-20, AC-21, AC-28, AC-29.
--
-- Los webhooks de pasarela REINTENTAN. Sin idempotencia, un reintento emite los
-- tickets otra vez — y eso se descubre en la puerta, con dos personas y el mismo
-- asiento.
create or replace function public.confirm_payment(
  p_order_id     uuid,
  p_provider_ref text,
  p_amount_cents int default null,
  p_provider     text default 'culqi_sandbox',
  p_raw          jsonb default null
) returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o        record;
  v_ev       record;
  v_issued   int;
  v_existing uuid;
begin
  -- AC-29: solo service_role. La llama el webhook, no el cliente.
  if current_user not in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'solo el servidor confirma pagos' using errcode = '42501';
  end if;
  if coalesce(btrim(p_provider_ref), '') = '' then
    raise exception 'falta la referencia del pago' using errcode = '22023';
  end if;

  select * into v_o from public.orders where id = p_order_id for update;
  if v_o.id is null then
    raise exception 'orden inexistente' using errcode = '22023';
  end if;

  -- AC-21: ¿es un reintento del mismo pago? Entonces no se hace NADA y se
  -- devuelve lo que ya hay. No es un error: es un webhook reintentando.
  select id into v_existing from public.payments
   where provider = p_provider and provider_ref = p_provider_ref;

  if v_existing is not null then
    if v_o.status = 'paid' then
      return (select count(*)::int from public.tickets t
               join public.order_items oi on oi.id = t.order_item_id
              where oi.order_id = p_order_id);
    end if;
    raise exception 'ese pago ya existe pero la orden está en %', v_o.status
      using errcode = '22023';
  end if;

  if v_o.status = 'paid' then
    raise exception 'la orden ya está pagada con otra referencia' using errcode = '22023';
  end if;
  if v_o.status not in ('awaiting_payment', 'reserved', 'failed') then
    raise exception 'no se puede confirmar el pago de una orden en %', v_o.status
      using errcode = '22023';
  end if;
  if p_amount_cents is not null and p_amount_cents <> v_o.total_cents then
    raise exception 'el importe pagado (%) no coincide con el total de la orden (%)',
      p_amount_cents, v_o.total_cents using errcode = '22023';
  end if;

  select e.starts_at, e.qr_lead_days into v_ev
    from public.events e where e.id = v_o.event_id;

  insert into public.payments (order_id, provider, provider_ref, status,
                               amount_cents, currency, raw, settled_at)
  values (p_order_id, p_provider, p_provider_ref, 'succeeded',
          coalesce(p_amount_cents, v_o.total_cents), v_o.currency, p_raw, now());

  update public.orders set status = 'paid', paid_at = now() where id = p_order_id;

  -- AC-20: un ticket por order_item, en la MISMA transacción que el `paid`.
  -- AC-28: si algo de aquí falla, se revierte todo — no queda orden pagada sin
  -- tickets ni tickets con la orden esperando pago.
  with nuevo as (
    insert into public.tickets (
      code, event_id, order_item_id, zone_id, seat_id,
      owner_id, original_owner_id,
      holder_name, holder_dni_hash, holder_dni_last4,
      status, face_value_cents, qr_available_from
    )
    select private.new_ticket_code(),
           v_o.event_id, oi.id, t.zone_id, oi.seat_id,
           v_o.buyer_id, v_o.buyer_id,
           oi.attendee_name, oi.attendee_dni_hash, oi.attendee_dni_last4,
           'active',
           oi.unit_price_cents,          -- AC-26: el techo de reventa (Art. 6.2)
           -- AC-25 · Art. 2.5
           v_ev.starts_at - make_interval(days => v_ev.qr_lead_days)
      from public.order_items oi
      join public.price_tiers t on t.id = oi.price_tier_id
     where oi.order_id = p_order_id
    returning id
  ),
  -- AC-24 · Art. 2.6: 32 bytes por ticket. La tabla no tiene ninguna política.
  secretos as (
    insert into public.ticket_secrets (ticket_id, secret)
    select id, extensions.gen_random_bytes(32) from nuevo
    returning ticket_id
  ),
  -- AC-27: cada emisión deja su asiento en la bitácora (Art. 8).
  bitacora as (
    insert into public.ticket_events (ticket_id, action, meta)
    select id, 'issued',
           jsonb_build_object('order_id', p_order_id, 'provider_ref', p_provider_ref)
      from nuevo
    returning id
  )
  select count(*)::int into v_issued from nuevo;

  -- AC-22: el cupo pasa de `reserved` a `sold`. La suma no cambia en esta
  -- transición: lo comprometido sigue comprometido, solo cambia de casilla.
  update public.price_tiers t
     set reserved = t.reserved - c.n,
         sold     = t.sold     + c.n
    from (select price_tier_id, count(*) as n from public.order_items
           where order_id = p_order_id group by price_tier_id) c
   where t.id = c.price_tier_id;

  return v_issued;
end $$;

revoke all on function public.set_item_attendee(uuid, text, text) from public, anon;
revoke all on function public.start_payment(uuid)                 from public, anon;
revoke all on function public.fail_payment(uuid, text)             from public, anon;
-- confirm_payment NO se concede a authenticated: es del webhook (AC-29).
revoke all on function public.confirm_payment(uuid, text, int, text, jsonb)
  from public, anon, authenticated;

grant execute on function public.set_item_attendee(uuid, text, text) to authenticated;
grant execute on function public.start_payment(uuid)                 to authenticated;
grant execute on function public.fail_payment(uuid, text)             to authenticated;

comment on function public.confirm_payment(uuid, text, int, text, jsonb) is
  'AC-21: idempotente por (provider, provider_ref). Un webhook reintentado devuelve el conteo sin volver a emitir. Solo service_role.';
