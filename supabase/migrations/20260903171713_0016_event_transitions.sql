-- 007 · T-10 … T-13b
--
-- Una política de RLS puede decir "este usuario puede tocar esta fila". No puede
-- decir "de draft puedes ir a pending_review pero no a published". Eso es una
-- transición, y las transiciones van en RPC security definer.
--
-- Las siete comparten esqueleto: verificar quién, bloquear la fila, verificar el
-- estado de origen, mover, y dejar asiento. El `perform` de la bitácora está en
-- la plantilla justamente para que no se pueda olvidar (AC-10).
--
-- OJO: create_event de esta migración llama a una función que no existe.
-- Corregido en 0017 — ver la nota de allí sobre plpgsql y la validación tardía.

-- T-10: el asiento. Única vía de escritura a event_review_notes.
create or replace function private.log_event_review(
  p_event_id      uuid,
  p_action        public.review_action,
  p_note          text,
  p_status_before public.event_status,
  p_status_after  public.event_status,
  p_internal      boolean default false
) returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.event_review_notes (
    event_id, actor_id, action, note, checklist_snapshot,
    status_before, status_after, internal
  )
  select p_event_id, (select auth.uid()), p_action, nullif(btrim(p_note), ''),
         e.review_checklist, p_status_before, p_status_after, p_internal
  from public.events e where e.id = p_event_id;
end $$;

-- Bloquea la fila y devuelve el estado actual. Dos Admins revisando la misma
-- solicitud a la vez es un caso real, no teórico (T-13b).
create or replace function private.lock_event(p_event_id uuid)
returns public.event_status language plpgsql security definer set search_path = '' as $$
declare v_status public.event_status;
begin
  select status into v_status from public.events where id = p_event_id for update;
  if v_status is null then
    raise exception 'evento inexistente' using errcode = '22023';
  end if;
  return v_status;
end $$;

create or replace function private.require_organizer(p_event_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if private.auth_is_admin() then return; end if;
  if not exists (
    select 1 from public.events e
    join public.organizer_members m on m.organizer_id = e.organizer_id
    where e.id = p_event_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin')
      and m.revoked_at is null
  ) then
    raise exception 'sin permiso sobre este evento' using errcode = '42501';
  end if;
end $$;

create or replace function private.require_admin()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.auth_is_admin() then
    raise exception 'solo Admin' using errcode = '42501';
  end if;
end $$;

-- ── T-11 · AC-01, AC-02 ─────────────────────────────────────────────────────
create or replace function public.create_event(
  p_organizer_id uuid,
  p_title        text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_uid uuid := (select auth.uid());
begin
  if not (public.auth_owns_organizer_or_admin(p_organizer_id)) then
    raise exception 'sin permiso sobre este organizador' using errcode = '42501';
  end if;
  if not exists (select 1 from public.organizers
                  where id = p_organizer_id and status = 'approved') then
    raise exception 'el organizador debe estar aprobado antes de crear eventos'
      using errcode = '42501';
  end if;

  insert into public.events (organizer_id, title, status, created_by)
  values (p_organizer_id, nullif(btrim(p_title), ''),
          'draft',   -- AC-01: lo fija el servidor, nunca el payload
          v_uid)
  returning id into v_id;

  return v_id;
end $$;

-- ── T-11 · AC-03, AC-04 ─────────────────────────────────────────────────────
create or replace function public.submit_event(p_event_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_before public.event_status; v_missing text[];
begin
  perform private.require_organizer(p_event_id);
  v_before := private.lock_event(p_event_id);

  if v_before not in ('draft', 'changes_requested') then
    raise exception 'solo se envía a revisión desde draft o changes_requested (está en %)',
      v_before using errcode = '22023';
  end if;

  -- AC-03: si falta algo, decir QUÉ falta. Un "datos incompletos" obliga al
  -- organizador a adivinar y termina en un caso de soporte.
  select array_remove(array[
    case when coalesce(btrim(title), '')       = '' then 'título'      end,
    case when coalesce(btrim(description), '') = '' then 'descripción' end,
    case when coalesce(btrim(category), '')    = '' then 'categoría'   end,
    case when starts_at is null                     then 'fecha y hora' end,
    case when venue_id  is null                     then 'lugar'       end,
    case when capacity  is null                     then 'aforo'       end
  ], null) into v_missing
  from public.events where id = p_event_id;

  if array_length(v_missing, 1) > 0 then
    raise exception 'faltan datos obligatorios: %', array_to_string(v_missing, ', ')
      using errcode = '22023';
  end if;

  update public.events
     set status = 'pending_review', submitted_at = now()
   where id = p_event_id;

  perform private.log_event_review(p_event_id, 'submitted', null, v_before, 'pending_review');
end $$;

-- ── T-12 · AC-06, AC-08 ─────────────────────────────────────────────────────
-- approve pasa directo a 'setup': "aprobado" y "cargando inventario" son el
-- mismo momento para el organizador. Lo que sí es un paso aparte es publicar.
create or replace function public.approve_event(p_event_id uuid, p_note text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_before public.event_status;
begin
  perform private.require_admin();
  v_before := private.lock_event(p_event_id);

  if v_before <> 'pending_review' then
    raise exception 'solo se aprueba desde pending_review (está en %)', v_before
      using errcode = '22023';
  end if;

  update public.events set status = 'setup', approved_at = now() where id = p_event_id;
  perform private.log_event_review(p_event_id, 'approved', p_note, v_before, 'setup');
end $$;

create or replace function public.reject_event(p_event_id uuid, p_note text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_before public.event_status;
begin
  perform private.require_admin();
  if coalesce(btrim(p_note), '') = '' then
    raise exception 'rechazar exige un motivo' using errcode = '22023';
  end if;
  v_before := private.lock_event(p_event_id);

  if v_before <> 'pending_review' then
    raise exception 'solo se rechaza desde pending_review (está en %)', v_before
      using errcode = '22023';
  end if;

  update public.events set status = 'rejected' where id = p_event_id;
  perform private.log_event_review(p_event_id, 'rejected', p_note, v_before, 'rejected');
end $$;

-- AC-12: la observación es obligatoria. "Requiere info" sin decir cuál es una
-- solicitud parada para siempre.
create or replace function public.request_event_info(
  p_event_id uuid, p_note text, p_checklist jsonb default null
) returns void language plpgsql security definer set search_path = '' as $$
declare v_before public.event_status;
begin
  perform private.require_admin();
  if coalesce(btrim(p_note), '') = '' then
    raise exception 'pedir información exige una observación' using errcode = '22023';
  end if;
  v_before := private.lock_event(p_event_id);

  if v_before <> 'pending_review' then
    raise exception 'solo se pide info desde pending_review (está en %)', v_before
      using errcode = '22023';
  end if;

  -- El checklist se actualiza ANTES del asiento, para que el snapshot refleje
  -- lo que Admin acababa de marcar.
  if p_checklist is not null then
    update public.events set review_checklist = p_checklist where id = p_event_id;
  end if;

  update public.events set status = 'changes_requested' where id = p_event_id;
  perform private.log_event_review(p_event_id, 'info_requested', p_note,
                                   v_before, 'changes_requested');
end $$;

-- Marcar el checklist sin cambiar de estado.
create or replace function public.set_event_checklist(p_event_id uuid, p_checklist jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_admin();
  update public.events set review_checklist = p_checklist where id = p_event_id;
  if not found then
    raise exception 'evento inexistente' using errcode = '22023';
  end if;
end $$;

-- ── T-13 · AC-07 ────────────────────────────────────────────────────────────
-- La ejecuta el ORGANIZADOR: Feventi autoriza, el organizador decide cuándo
-- abre la venta. Y no se publica sin inventario, porque publicar un evento sin
-- nada que vender es una landing que rebota.
create or replace function public.publish_event(p_event_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_before public.event_status; v_slug text;
begin
  perform private.require_organizer(p_event_id);
  v_before := private.lock_event(p_event_id);

  if v_before <> 'setup' then
    raise exception 'solo se publica desde setup (está en %)', v_before
      using errcode = '22023';
  end if;

  -- 003 crea zones y price_tiers. Hasta entonces esta comprobación se salta,
  -- porque las tablas no existen; queda activada al aplicar 003.
  if to_regclass('public.price_tiers') is not null then
    if not exists (
      select 1 from public.price_tiers t
      where t.event_id = p_event_id and t.stock > 0
    ) then
      raise exception 'no se publica sin al menos una entrada con stock'
        using errcode = '22023';
    end if;
  end if;

  select slug into v_slug from public.events where id = p_event_id;
  if coalesce(btrim(v_slug), '') = '' then
    raise exception 'falta el slug público del evento' using errcode = '22023';
  end if;

  update public.events set status = 'published', published_at = now()
   where id = p_event_id;

  perform private.log_event_review(p_event_id, 'published', null, v_before, 'published');
end $$;

-- pause detiene la VENTA. Los tickets emitidos siguen válidos y su QR sigue
-- funcionando en puerta (AC-20, y 006/AC-15 lo verifica).
create or replace function public.pause_event(p_event_id uuid, p_note text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_before public.event_status;
begin
  perform private.require_admin();
  v_before := private.lock_event(p_event_id);

  if v_before <> 'published' then
    raise exception 'solo se pausa un evento publicado (está en %)', v_before
      using errcode = '22023';
  end if;

  update public.events set status = 'paused', paused_at = now() where id = p_event_id;
  perform private.log_event_review(p_event_id, 'paused', p_note, v_before, 'paused');
end $$;

create or replace function public.resume_event(p_event_id uuid, p_note text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_before public.event_status;
begin
  perform private.require_admin();
  v_before := private.lock_event(p_event_id);

  if v_before <> 'paused' then
    raise exception 'solo se reanuda un evento pausado (está en %)', v_before
      using errcode = '22023';
  end if;

  update public.events set status = 'published', paused_at = null where id = p_event_id;
  perform private.log_event_review(p_event_id, 'published', p_note, v_before, 'published');
end $$;

create or replace function public.cancel_event(p_event_id uuid, p_note text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_before public.event_status;
begin
  perform private.require_admin();
  if coalesce(btrim(p_note), '') = '' then
    raise exception 'cancelar exige un motivo' using errcode = '22023';
  end if;
  v_before := private.lock_event(p_event_id);

  if v_before in ('cancelled', 'finished') then
    raise exception 'el evento ya está en % y no se puede cancelar', v_before
      using errcode = '22023';
  end if;

  update public.events set status = 'cancelled', cancelled_at = now() where id = p_event_id;
  perform private.log_event_review(p_event_id, 'cancelled', p_note, v_before, 'cancelled');
end $$;

-- D-01: destacar es curaduría manual de Admin, no un algoritmo.
create or replace function public.set_event_featured(p_event_id uuid, p_featured boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_admin();
  update public.events
     set featured_at = case when p_featured then now() else null end
   where id = p_event_id;
end $$;

-- ── Privilegios ─────────────────────────────────────────────────────────────
revoke all on function private.log_event_review(uuid, public.review_action, text,
       public.event_status, public.event_status, boolean) from public, anon, authenticated;
revoke all on function private.lock_event(uuid)            from public, anon, authenticated;
revoke all on function private.require_organizer(uuid)     from public, anon, authenticated;
revoke all on function private.require_admin()             from public, anon, authenticated;

revoke all on function public.create_event(uuid, text)                    from public, anon;
revoke all on function public.submit_event(uuid)                          from public, anon;
revoke all on function public.approve_event(uuid, text)                   from public, anon;
revoke all on function public.reject_event(uuid, text)                    from public, anon;
revoke all on function public.request_event_info(uuid, text, jsonb)       from public, anon;
revoke all on function public.set_event_checklist(uuid, jsonb)            from public, anon;
revoke all on function public.publish_event(uuid)                         from public, anon;
revoke all on function public.pause_event(uuid, text)                     from public, anon;
revoke all on function public.resume_event(uuid, text)                    from public, anon;
revoke all on function public.cancel_event(uuid, text)                    from public, anon;
revoke all on function public.set_event_featured(uuid, boolean)           from public, anon;

grant execute on function public.create_event(uuid, text)                 to authenticated;
grant execute on function public.submit_event(uuid)                       to authenticated;
grant execute on function public.approve_event(uuid, text)                to authenticated;
grant execute on function public.reject_event(uuid, text)                 to authenticated;
grant execute on function public.request_event_info(uuid, text, jsonb)    to authenticated;
grant execute on function public.set_event_checklist(uuid, jsonb)         to authenticated;
grant execute on function public.publish_event(uuid)                      to authenticated;
grant execute on function public.pause_event(uuid, text)                  to authenticated;
grant execute on function public.resume_event(uuid, text)                 to authenticated;
grant execute on function public.cancel_event(uuid, text)                 to authenticated;
grant execute on function public.set_event_featured(uuid, boolean)        to authenticated;
