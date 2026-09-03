-- Corrige 0016. create_event llamaba a public.auth_owns_organizer_or_admin(),
-- que no existe.
--
-- plpgsql NO valida los identificadores del cuerpo al crear la función: compila
-- sin quejarse y falla la primera vez que se ejecuta. Es lo contrario de
-- `language sql`, que sí valida al crear — y es por lo que 0004 sí reventó a
-- tiempo con organizer_members. Conclusión práctica: una RPC en plpgsql no está
-- verificada hasta que una prueba la llama.

create or replace function private.require_organizer_of(p_organizer_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if private.auth_is_admin() then return; end if;
  if not private.auth_owns_organizer(p_organizer_id) then
    raise exception 'sin permiso sobre este organizador' using errcode = '42501';
  end if;
end $$;

create or replace function public.create_event(
  p_organizer_id uuid,
  p_title        text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_uid uuid := (select auth.uid());
begin
  perform private.require_organizer_of(p_organizer_id);

  -- Art. 4: un organizador sin aprobar no crea eventos. La cadena de
  -- aprobación empieza en el organizador, no en el evento.
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

revoke all on function private.require_organizer_of(uuid) from public, anon, authenticated;
