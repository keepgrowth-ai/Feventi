-- 009 · T-05 … T-10 · las RPC del soporte
--
-- OJO: `open_support_case` de esta migración tiene un bug — revalida contra
-- quien abre el `order_id` que ella misma dedujo del ticket, y eso deja al staff
-- sin poder reportar una entrada de su propia puerta. Corregido en `0051`. Las
-- migraciones son inmutables (Art. 12.4): esto queda como está.

-- ── Abrir un caso ───────────────────────────────────────────────────────────
--
-- AC-03: el cliente manda el OBJETO, no el contexto. `event_id` y `order_id`
-- salen del ticket, aquí dentro. Si el cliente los mandara, podría adjuntar el
-- evento de otro y ensuciar la cola de un organizador ajeno.
--
-- AC-04: quien abre tiene que tener relación con el objeto, y se comprueba
-- antes de escribir nada.
create or replace function public.open_support_case(
  p_kind       public.support_kind,
  p_subject    text,
  p_body       text,
  p_ticket_id  uuid default null,
  p_order_id   uuid default null,
  p_event_id   uuid default null,
  p_checkin_id uuid default null
) returns uuid
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_ticket public.tickets%rowtype;
  v_order  public.orders%rowtype;
  v_event  uuid := p_event_id;
  v_order_id uuid := p_order_id;
  v_id     uuid;
  v_abierto text;
begin
  if v_uid is null then
    raise exception 'no autenticado' using errcode = '28000';
  end if;

  if p_ticket_id is not null then
    select * into v_ticket from public.tickets where id = p_ticket_id;

    -- AC-05: el mismo mensaje exista o no. Distinguirlos convertiría esto en un
    -- oráculo para saber si un código de ticket es real.
    if not found or (
      v_ticket.owner_id <> v_uid
      and not exists (
        select 1 from public.event_staff
         where event_id = v_ticket.event_id and profile_id = v_uid and revoked_at is null)
      and not private.auth_is_admin()
    ) then
      raise exception 'no puedes abrir un caso sobre esa entrada' using errcode = '42501';
    end if;

    v_event := v_ticket.event_id;
    select o.id into v_order_id
      from public.orders o
      join public.order_items oi on oi.order_id = o.id
     where oi.id = v_ticket.order_item_id;
  end if;

  if v_order_id is not null then
    select * into v_order from public.orders where id = v_order_id;
    if not found or (v_order.buyer_id <> v_uid and not private.auth_is_admin()) then
      raise exception 'no puedes abrir un caso sobre ese pedido' using errcode = '42501';
    end if;
    v_event := coalesce(v_event, v_order.event_id);
  end if;

  if v_event is not null and p_ticket_id is null and v_order_id is null then
    if not exists (
      select 1 from public.events e
       where e.id = v_event
         and (e.organizer_id = any (private.auth_organizer_ids())
              or exists (select 1 from public.event_staff es
                          where es.event_id = e.id and es.profile_id = v_uid
                            and es.revoked_at is null))
    ) and not private.auth_is_admin() then
      raise exception 'no puedes abrir un caso sobre ese evento' using errcode = '42501';
    end if;
  end if;

  insert into public.support_cases (
    kind, opened_by, event_id, order_id, ticket_id, checkin_id, subject, body
  ) values (
    p_kind, v_uid, v_event, v_order_id, p_ticket_id, p_checkin_id,
    trim(p_subject), trim(p_body)
  ) returning id into v_id;

  return v_id;

-- AC-06 · D-12. El índice único es el árbitro; aquí solo se traduce a algo que
-- una persona pueda leer y actuar. «duplicate key value violates unique
-- constraint» no le dice a nadie que ya tiene un caso abierto.
exception when unique_violation then
  select code into v_abierto from public.support_cases
   where order_id = v_order_id
     and kind in ('refund', 'cancellation')
     and status not in ('resolved', 'closed')
   limit 1;
  raise exception
    'ya hay un caso de recuperacion abierto para este pedido (%). Responde ahi en vez de abrir otro: dos vias a la vez sobre el mismo pago se bloquean entre si.',
    coalesce(v_abierto, 'sin codigo')
    using errcode = '23505';
end $$;

revoke all on function public.open_support_case(public.support_kind, text, text, uuid, uuid, uuid, uuid) from public, anon;
grant execute on function public.open_support_case(public.support_kind, text, text, uuid, uuid, uuid, uuid) to authenticated;

-- ── Responder ───────────────────────────────────────────────────────────────
create or replace function public.post_support_message(
  p_case_id  uuid,
  p_body     text,
  p_internal boolean default false
) returns uuid
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_admin boolean := private.auth_is_admin();
  v_id    uuid;
begin
  if v_uid is null then
    raise exception 'no autenticado' using errcode = '28000';
  end if;

  -- AC-16: la nota interna es de Admin. Sin esto, cualquiera podría escribir una
  -- nota que el resto del hilo no ve.
  if p_internal and not v_admin then
    raise exception 'solo Feventi escribe notas internas' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.support_cases c
     where c.id = p_case_id
       and (c.opened_by = v_uid
            or c.ticket_id in (select id from public.tickets where owner_id = v_uid)
            or v_admin)
  ) then
    raise exception 'no tienes acceso a ese caso' using errcode = '42501';
  end if;

  -- Un caso cerrado no recibe mensajes: si no, el hilo sigue vivo sin que nadie
  -- lo mire. Reabrirlo es una acción de Admin.
  if exists (select 1 from public.support_cases where id = p_case_id and status = 'closed') then
    raise exception 'este caso esta cerrado. Abre uno nuevo y cita el codigo del anterior'
      using errcode = '22023';
  end if;

  insert into public.support_messages (case_id, author_id, body, internal)
  values (p_case_id, v_uid, trim(p_body), p_internal)
  returning id into v_id;

  -- Que el usuario responda saca el caso de «esperando al usuario»: si no, se
  -- queda ahí para siempre y nadie lo vuelve a mirar.
  update public.support_cases
     set status = 'open'
   where id = p_case_id and status = 'waiting_user' and not v_admin;

  return v_id;
end $$;

revoke all on function public.post_support_message(uuid, text, boolean) from public, anon;
grant execute on function public.post_support_message(uuid, text, boolean) to authenticated;

-- ── Gestionar (Admin) ───────────────────────────────────────────────────────
-- AC-15: estado, prioridad y asignación son de Admin. Una sola RPC en vez de
-- tres: son el mismo movimiento —«Feventi toca el caso»— y separarlas obligaría
-- a repetir la comprobación de rol tres veces, que es tres sitios donde
-- olvidarla.
create or replace function public.manage_support_case(
  p_case_id  uuid,
  p_status   public.support_status   default null,
  p_priority public.support_priority default null,
  p_assign   uuid                    default null,
  p_note     text                    default null
) returns void
language plpgsql volatile security definer set search_path = ''
as $$
declare v_uid uuid := (select auth.uid());
begin
  if not private.auth_is_admin() then
    raise exception 'solo Feventi gestiona casos' using errcode = '42501';
  end if;

  update public.support_cases
     set status      = coalesce(p_status, status),
         priority    = coalesce(p_priority, priority),
         assigned_to = coalesce(p_assign, assigned_to),
         -- AC-18: cerrar SELLA la hora, y no borra ni un mensaje.
         resolved_at = case
           when coalesce(p_status, status) in ('resolved', 'closed')
             then coalesce(resolved_at, now())
           else null
         end
   where id = p_case_id;

  if not found then
    raise exception 'caso inexistente' using errcode = '22023';
  end if;

  if p_note is not null and length(trim(p_note)) > 0 then
    insert into public.support_messages (case_id, author_id, body, internal)
    values (p_case_id, v_uid, trim(p_note), true);
  end if;
end $$;

revoke all on function public.manage_support_case(uuid, public.support_status, public.support_priority, uuid, text) from public, anon;
grant execute on function public.manage_support_case(uuid, public.support_status, public.support_priority, uuid, text) to authenticated;

-- ── Actuar sobre un ticket desde un caso (Art. 8.3) ─────────────────────────
--
-- AC-19: cada acción deja asiento con su actor, el caso en `meta` y, si corrige
-- uno anterior, su `corrects_id`. Corregir NO es editar el asiento viejo: es uno
-- nuevo que apunta al anterior, y el viejo se queda.
create or replace function public.admin_ticket_action(
  p_case_id   uuid,
  p_ticket_id uuid,
  p_action    public.ticket_event_action,
  p_note      text default null,
  p_corrects  uuid default null
) returns uuid
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_id  uuid;
begin
  if not private.auth_is_admin() then
    raise exception 'solo Feventi actua sobre una entrada' using errcode = '42501';
  end if;

  if not exists (select 1 from public.support_cases where id = p_case_id) then
    raise exception 'caso inexistente' using errcode = '22023';
  end if;

  -- `voided` y `refunded` son las únicas de Fase 1 que mueven el estado del
  -- ticket. Art. 8.2: se revoca sin borrar.
  if p_action = 'voided' then
    update public.tickets set status = 'void' where id = p_ticket_id;
  elsif p_action = 'refunded' then
    update public.tickets set status = 'refunded' where id = p_ticket_id;
  end if;

  insert into public.ticket_events (ticket_id, actor_id, action, meta, corrects_id)
  values (p_ticket_id, v_uid, p_action,
          jsonb_build_object('case_id', p_case_id, 'note', p_note),
          p_corrects)
  returning id into v_id;

  return v_id;
end $$;

revoke all on function public.admin_ticket_action(uuid, uuid, public.ticket_event_action, text, uuid) from public, anon;
grant execute on function public.admin_ticket_action(uuid, uuid, public.ticket_event_action, text, uuid) to authenticated;

-- ── La cola ─────────────────────────────────────────────────────────────────
--
-- AC-11: el organizador ve los casos de sus eventos SIN saber quién los abrió
-- (D-06). Por eso `opened_by` no está en la vista, y en su lugar va una etiqueta
-- que depende de quién consulta.
create view public.v_support_queue with (security_invoker = true) as
select
  c.id,
  c.code,
  c.kind,
  c.status,
  c.priority,
  c.subject,
  c.created_at,
  c.updated_at,
  c.resolved_at,
  c.event_id,
  c.ticket_id,
  c.order_id,
  c.checkin_id,
  c.assigned_to,
  e.title as event_title,
  t.code  as ticket_code,
  o.code  as order_code,
  case when c.opened_by = (select auth.uid()) then 'yo'
       when private.auth_is_admin() then coalesce(p.full_name, 'usuario')
       else 'un asistente'
  end as opened_by_label,
  (select count(*) from public.support_messages m
    where m.case_id = c.id and (not m.internal or private.auth_is_admin())) as messages
from public.support_cases c
left join public.events   e on e.id = c.event_id
left join public.tickets  t on t.id = c.ticket_id
left join public.orders   o on o.id = c.order_id
left join public.profiles p on p.id = c.opened_by;

grant select on public.v_support_queue to authenticated;

comment on view public.v_support_queue is
  'security_invoker = true: aqui SI se puede, y por eso no lleva excepcion en advisor-baseline. La RLS de support_cases ya deja ver exactamente los casos que tocan, y los joins son a filas que el que consulta o ve o le salen nulas.';
