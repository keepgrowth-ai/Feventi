-- Corrige 0044. `gate_find_by_dni` llamaba a `public.hash_dni`, que ya no
-- existe: 0010 movió los helpers al schema `private`.
--
-- Es EXACTAMENTE la trampa que la constitución (Art. 12) ya tenía anotada, y que
-- 0017 ya había pisado una vez: **plpgsql no valida el cuerpo al crear la
-- función.** Compiló sin quejarse y habría reventado la primera noche que
-- alguien usara el modo DNI en puerta — con el fan sin batería delante.
--
-- Peor: la prueba de 006 daba VERDE sobre esto. Comprobaba que un DNI mal
-- formado falla, y fallaba… pero por «function does not exist», no por el
-- formato. Una comprobación que solo verifica QUE algo falla, y no POR QUÉ, no
-- distingue un guardarraíl de una función rota. La prueba nueva pide el camino
-- FELIZ: un DNI válido tiene que DEVOLVER la entrada. Ese es el que no se puede
-- fingir.

create or replace function public.gate_find_by_dni(p_event_id uuid, p_dni text)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_hash text;
  v_out  jsonb;
begin
  -- Antes de hashear: sin esto sería un oráculo para confirmar si una persona
  -- concreta tiene entrada para un evento concreto.
  if not exists (
    select 1 from public.event_staff
     where event_id = p_event_id and profile_id = v_uid and revoked_at is null
  ) then
    raise exception 'no eres staff de este evento' using errcode = '42501';
  end if;

  -- private.hash_dni valida el formato y revienta con 22023 si no son 8 dígitos.
  v_hash := private.hash_dni(p_dni);

  select coalesce(jsonb_agg(x order by x ->> 'code'), '[]'::jsonb) into v_out
    from (
      select jsonb_build_object(
               'ticket_id',   t.id,
               'code',        t.code,
               'status',      t.status,
               'holder_name', t.holder_name,
               -- AC-20: los últimos cuatro y el nombre, que es lo que el staff
               -- coteja contra el carné. El hash no sale nunca.
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

comment on function public.gate_find_by_dni(uuid, text) is
  'Modo DNI (D-03). Devuelve nombre y ultimos 4, nunca el hash (AC-20). Comprueba event_staff ANTES de hashear: sin eso seria un oraculo para confirmar si alguien tiene entrada.';
