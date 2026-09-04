-- Corrige 0050. El staff no podía abrir un caso sobre una entrada de su propia
-- puerta:
--
--     42501: no puedes abrir un caso sobre ese pedido
--
-- La función resolvía el `order_id` DESDE el ticket —que es lo que pide AC-03—
-- y después lo revalidaba contra quien abre. Para el fan cuadraba, porque es el
-- comprador; para el staff no, porque el pedido es del asistente.
--
-- El error estaba en tratar igual dos cosas distintas:
--
--   · un `order_id` que manda el CLIENTE hay que autorizarlo, porque podría ser
--     el de cualquiera;
--   · un `order_id` que el SERVIDOR dedujo de un ticket ya autorizado, no: la
--     autorización ya ocurrió sobre el ticket.
--
-- Revalidarlo no añadía ninguna seguridad. Solo cerraba la historia 4 del spec
-- —la incidencia abierta desde el validador— que es justo el caso que 009
-- existe para cubrir.
--
-- Ahora se distinguen con una bandera local, y el caso del staff pasa sin
-- aflojar nada: un `order_id` que llegue por parámetro se sigue comprobando
-- igual de estricto, y hay una comprobación para cada rama.
--
-- De paso se añade el organizador al primer permiso: puede abrir un caso sobre
-- una entrada de su evento sin ser su dueño, que es la historia 5.

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
  -- true = el order_id lo dedujo el servidor del ticket, no lo mandó el cliente.
  v_order_derivado boolean := false;
  v_id     uuid;
  v_abierto text;
begin
  if v_uid is null then
    raise exception 'no autenticado' using errcode = '28000';
  end if;

  if p_ticket_id is not null then
    select * into v_ticket from public.tickets where id = p_ticket_id;

    -- AC-05: el mismo mensaje exista o no el ticket. Distinguirlos convertiría
    -- esto en un oráculo para saber si un código es real.
    if not found or (
      v_ticket.owner_id <> v_uid
      and not exists (
        select 1 from public.event_staff
         where event_id = v_ticket.event_id and profile_id = v_uid and revoked_at is null)
      and not exists (
        select 1 from public.events e
         where e.id = v_ticket.event_id
           and e.organizer_id = any (private.auth_organizer_ids()))
      and not private.auth_is_admin()
    ) then
      raise exception 'no puedes abrir un caso sobre esa entrada' using errcode = '42501';
    end if;

    -- AC-03: el contexto sale del ticket, no del cliente.
    v_event := v_ticket.event_id;
    select o.id into v_order_id
      from public.orders o
      join public.order_items oi on oi.order_id = o.id
     where oi.id = v_ticket.order_item_id;
    v_order_derivado := true;
  end if;

  -- Solo se autoriza el pedido que MANDÓ el cliente. El deducido ya viene
  -- respaldado por la autorización del ticket, y exigir además ser el comprador
  -- dejaría al staff sin poder reportar la entrada que tiene delante.
  if v_order_id is not null and not v_order_derivado then
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
-- una persona pueda leer y actuar.
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

comment on function public.open_support_case(public.support_kind, text, text, uuid, uuid, uuid, uuid) is
  'AC-03: el contexto lo rellena el servidor desde el ticket. Un order_id DEDUCIDO no se revalida contra quien abre —la autorizacion ya ocurrio sobre el ticket—; uno MANDADO por el cliente, si.';
