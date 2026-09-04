-- 006 · T-05 … T-08 · la decisión de puerta, en una transacción

-- ── Lo que el staff ve de sus eventos ───────────────────────────────────────
-- AC-06: solo sus eventos asignados, y solo los campos que necesita.
--
-- Vista `security definer` por el mismo motivo que `v_my_tickets` (0042): la
-- alternativa es abrir `events`, `venues` y `zones` a cualquiera que sea staff
-- de algún evento, con la fila ENTERA — incluidos los campos comerciales que el
-- Art. 7.5 no le corresponde ver. El filtro `es.profile_id = auth.uid()` es más
-- estrecho que tres políticas nuevas, y cabe en una línea que se puede auditar.
create view public.v_my_gate_events with (security_invoker = false) as
select
  e.id            as event_id,
  e.title,
  e.starts_at,
  e.doors_at,
  e.timezone,
  e.status        as event_status,
  e.nomination_mode,
  v.name          as venue_name,
  v.city          as venue_city,
  v.address       as venue_address,
  es.id           as assignment_id,
  es.gate,
  es.zone_id,
  z.name          as zone_name,
  -- AC-03: el turno no se guarda por persona, se deriva del evento. Dos horas
  -- antes de puertas y cuatro después del inicio. Guardarlo por fila obligaría
  -- a rehacer todas las asignaciones cada vez que el evento mueve la hora.
  coalesce(e.doors_at, e.starts_at) - interval '2 hours' as shift_from,
  e.starts_at + interval '4 hours'                       as shift_to,
  (e.starts_at is not null
   and now() >= coalesce(e.doors_at, e.starts_at) - interval '2 hours'
   and now() <= e.starts_at + interval '4 hours')        as shift_active
from public.event_staff es
join public.events e on e.id = es.event_id
left join public.venues v on v.id = e.venue_id
left join public.zones  z on z.id = es.zone_id
-- Este filtro es la única protección: la vista salta la RLS.
where es.profile_id = (select auth.uid())
  and es.revoked_at is null;

grant select on public.v_my_gate_events to authenticated;

comment on view public.v_my_gate_events is
  'AC-06. security_invoker = false por lo mismo que v_my_tickets: con invoker saldria vacia, porque events/venues/zones estan limitadas al organizador. El WHERE por profile_id es la unica proteccion.';

-- ── El contador del turno ───────────────────────────────────────────────────
-- AC-26: agregando `checkins`, no un contador incremental. Un contador se
-- desincroniza la primera vez que una petición se pierde a medias; una suma
-- sobre la bitácora no puede.
create view public.v_gate_stats with (security_invoker = false) as
select
  c.event_id,
  c.gate,
  count(*)                                                as scans,
  count(*) filter (where c.result = 'allowed')            as allowed,
  count(*) filter (where c.result = 'manual_review')      as manual_review,
  count(*) filter (where c.result = 'already_used')       as already_used,
  count(*) filter (where c.result = 'denied')             as denied,
  count(*) filter (where c.reason = 'screenshot_suspected') as screenshots,
  -- El aforo es del EVENTO, no de la puerta: lo que el staff quiere saber es
  -- cuánta gente hay dentro, y esa gente entró por todas las puertas.
  (select count(*) from public.tickets t
    where t.event_id = c.event_id and t.status <> 'void')  as tickets_total,
  (select count(*) from public.tickets t
    where t.event_id = c.event_id and t.status = 'used')   as tickets_used
from public.checkins c
where exists (
  select 1 from public.event_staff es
   where es.event_id   = c.event_id
     and es.gate       = c.gate
     and es.profile_id = (select auth.uid())
     and es.revoked_at is null
)
group by c.event_id, c.gate;

grant select on public.v_gate_stats to authenticated;

-- ── Modo DNI (D-03) ─────────────────────────────────────────────────────────
-- El fan sin batería o con la pantalla rota. El staff teclea el documento, el
-- servidor hashea y busca. AC-20: devuelve nombre y últimos cuatro dígitos —
-- lo que hay que cotejar contra el carné— y NUNCA el hash.
create or replace function public.gate_find_by_dni(p_event_id uuid, p_dni text)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_hash text;
  v_out  jsonb;
begin
  if not exists (
    select 1 from public.event_staff
     where event_id = p_event_id and profile_id = v_uid and revoked_at is null
  ) then
    raise exception 'no eres staff de este evento' using errcode = '42501';
  end if;

  -- hash_dni valida el formato y revienta con 22023 si no son ocho dígitos.
  v_hash := public.hash_dni(p_dni);

  select coalesce(jsonb_agg(x order by x ->> 'code'), '[]'::jsonb) into v_out
    from (
      select jsonb_build_object(
               'ticket_id',   t.id,
               'code',        t.code,
               'status',      t.status,
               'holder_name', t.holder_name,
               'dni_last4',   t.holder_dni_last4,
               'zone_name',   z.name,
               'row_label',   s.row_label,
               'seat_number', s.seat_number
             ) as x
        from public.tickets t
        join public.zones z on z.id = t.zone_id
        left join public.seats s on s.id = t.seat_id
       where t.event_id = p_event_id
         and t.holder_dni_hash = v_hash
    ) q;

  return v_out;
end $$;

revoke all on function public.gate_find_by_dni(uuid, text) from public, anon;
grant execute on function public.gate_find_by_dni(uuid, text) to authenticated;

-- ── La decisión ─────────────────────────────────────────────────────────────
-- La llama `qr-validate` con service_role, después de verificar el HMAC. El
-- reparto es: la Edge Function sabe de criptografía, la base sabe de estado. La
-- parte que TIENE que ser atómica —bloquear el ticket, marcarlo usado y anotar
-- el checkin— vive aquí, en una transacción, porque en la Edge Function serían
-- tres viajes y dos puertas escaneando a la vez producirían dos `allowed`.
create or replace function public.gate_checkin(
  p_staff_id     uuid,
  p_event_id     uuid,
  p_ticket_id    uuid,
  p_scanned_code text    default null,
  p_mac_ok       boolean default false,
  p_slot_delta   int     default null,
  p_mode         text    default 'qr'
) returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_staff   public.event_staff%rowtype;
  v_event   public.events%rowtype;
  v_ticket  public.tickets%rowtype;
  v_result  public.checkin_result;
  v_reason  public.checkin_reason;
  v_consume boolean := false;
  v_first_at   timestamptz;
  v_first_gate text;
  v_checkin_id uuid;
begin
  -- AC-01 y AC-05: `event_staff` vivo es la ÚNICA vía. Un fan que llame aquí
  -- —si pudiera— muere en esta línea.
  select * into v_staff
    from public.event_staff
   where event_id = p_event_id and profile_id = p_staff_id and revoked_at is null;
  if not found then
    raise exception 'no eres staff de este evento' using errcode = '42501';
  end if;

  select * into v_event from public.events where id = p_event_id;

  -- AC-03. Fuera del turno no se valida y no se registra: no es un escaneo
  -- dudoso, es una llamada que no debería existir.
  if v_event.starts_at is null
     or now() < coalesce(v_event.doors_at, v_event.starts_at) - interval '2 hours'
     or now() > v_event.starts_at + interval '4 hours' then
    raise exception 'fuera de la ventana de turno' using errcode = '42501';
  end if;

  -- AC-09. El `for update` es lo único que separa «un allowed y un
  -- already_used» de «dos allowed». Dos puertas leyendo el mismo QR a la vez es
  -- el caso real, no el hipotético.
  if p_ticket_id is not null then
    select * into v_ticket from public.tickets where id = p_ticket_id for update;
  end if;

  -- La cascada. El orden importa: lo que deniega va antes que lo que revisa, y
  -- dentro de lo que deniega, primero lo que dice que el código no vale.
  if not coalesce(p_mac_ok, false) or v_ticket.id is null then
    -- AC-12
    v_result := 'denied'; v_reason := 'qr_unreadable';
  elsif v_ticket.event_id <> p_event_id then
    -- AC-02: queda registrado igual, en el evento del staff.
    v_result := 'denied'; v_reason := 'wrong_event';
  elsif v_event.status = 'cancelled' then
    -- AC-14. AC-15: `paused` NO cae aquí — pausar detiene la venta, no el
    -- acceso de quien ya compró.
    v_result := 'denied'; v_reason := 'event_cancelled';
  elsif p_mode = 'qr' and abs(coalesce(p_slot_delta, 99)) > 1 then
    -- AC-11 · Art. 2.3. MAC válida y slot viejo solo puede venir de una captura.
    v_result := 'denied'; v_reason := 'screenshot_suspected';
  elsif v_ticket.status = 'used' then
    -- AC-10
    v_result := 'already_used'; v_reason := 'already_used';
  elsif v_ticket.status <> 'active' then
    -- AC-13 · Art. 2.4: el motivo concreto, no «inválida».
    v_result := 'denied';
    v_reason := ('ticket_' || v_ticket.status::text)::public.checkin_reason;
  elsif v_ticket.holder_dni_hash is null and v_event.nomination_mode = 'strict' then
    -- AC-17
    v_result := 'denied'; v_reason := 'not_nominated';
  elsif p_mode = 'dni' then
    -- AC-19 · D-03
    v_result := 'manual_review'; v_reason := 'dni_mode'; v_consume := true;
  elsif v_ticket.holder_dni_hash is null then
    -- AC-16
    v_result := 'manual_review'; v_reason := 'not_nominated'; v_consume := true;
  elsif v_staff.zone_id is not null and v_ticket.zone_id <> v_staff.zone_id then
    -- AC-18. NO consume: puede ser señalización del venue, y si la persona va a
    -- la puerta correcta tiene que poder entrar. Consumir aquí la dejaría fuera.
    v_result := 'manual_review'; v_reason := 'wrong_zone';
  else
    v_result := 'allowed'; v_reason := 'ok'; v_consume := true;
  end if;

  -- Para `already_used`, la hora y la puerta del PRIMER ingreso. El mensaje de
  -- puerta es «entró a las 20:14 por Puerta A», no «entrada falsa»: casi nunca
  -- lo es.
  if v_result = 'already_used' then
    select c.created_at, c.gate into v_first_at, v_first_gate
      from public.checkins c
     where c.ticket_id = v_ticket.id
       and c.result in ('allowed', 'manual_review')
     order by c.created_at
     limit 1;
  end if;

  -- AC-08: el cambio de estado y el asiento, en la MISMA transacción.
  if v_consume then
    update public.tickets
       set status = 'used', used_at = now()
     where id = v_ticket.id;

    -- AC-25
    insert into public.ticket_events (ticket_id, actor_id, action, meta)
    values (v_ticket.id, p_staff_id, 'used',
            jsonb_build_object('gate', v_staff.gate,
                               'result', v_result, 'reason', v_reason));
  end if;

  -- AC-21: TODO escaneo, incluidos los denegados y los ilegibles.
  insert into public.checkins (
    event_id, ticket_id, staff_id, event_staff_id, gate,
    result, reason, scanned_code, slot_delta, meta
  ) values (
    p_event_id, v_ticket.id, p_staff_id, v_staff.id, v_staff.gate,
    v_result, v_reason, p_scanned_code, p_slot_delta,
    case when v_first_at is not null
         then jsonb_build_object('first_at', v_first_at, 'first_gate', v_first_gate) end
  ) returning id into v_checkin_id;

  return jsonb_build_object(
    'checkin_id', v_checkin_id,
    'result',     v_result,
    'reason',     v_reason,
    'gate',       v_staff.gate,
    -- AC-20: nombre y últimos cuatro. El hash no sale de la base, y el DNI
    -- completo no existe en ninguna columna.
    'ticket', case when v_ticket.id is null then null else jsonb_build_object(
      'id',          v_ticket.id,
      'code',        v_ticket.code,
      'status',      v_ticket.status,
      'holder_name', v_ticket.holder_name,
      'dni_last4',   v_ticket.holder_dni_last4,
      'nominated',   v_ticket.holder_dni_hash is not null,
      'zone_name',   (select z.name from public.zones z where z.id = v_ticket.zone_id),
      'row_label',   (select s.row_label   from public.seats s where s.id = v_ticket.seat_id),
      'seat_number', (select s.seat_number from public.seats s where s.id = v_ticket.seat_id)
    ) end,
    'first_at',   v_first_at,
    'first_gate', v_first_gate
  );
end $$;

-- Solo service_role, desde la Edge Function. Si `authenticated` pudiera
-- llamarla, cualquiera con sesión podría marcar tickets como usados pasando un
-- p_mac_ok = true.
revoke all on function public.gate_checkin(uuid, uuid, uuid, text, boolean, int, text)
  from public, anon, authenticated;
grant execute on function public.gate_checkin(uuid, uuid, uuid, text, boolean, int, text)
  to service_role;

comment on function public.gate_checkin(uuid, uuid, uuid, text, boolean, int, text) is
  'La decision de puerta, en una transaccion. p_mac_ok viene de qr-validate, que es quien tiene el secreto: por eso esta funcion es solo de service_role.';
