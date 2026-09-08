-- 011 · la señal social enseña caras
--
-- La vista ya devolvía nombres (D-46). Faltaba la foto, que es lo que convierte
-- «Diego y Valeria quieren ir» en algo que se entiende antes de leerlo.
--
-- Sigue sin revelar nada nuevo: `avatar_url` de una amistad mutua ya sale en
-- `/amigos` desde 010, y D-40 se cumple igual — ni zona, ni precio, ni cantidad,
-- ni identificadores. Una cara y un nombre de pila de alguien que aceptó ser tu
-- amigo, y nada más.
--
-- Los dos arrays van EN EL MISMO ORDEN que los de nombres. Es lo que permite al
-- componente emparejar cara con nombre sin una segunda consulta, y la razón de
-- que los dos `array_agg` ordenen por lo mismo.
drop view public.v_my_event_signals;

create view public.v_my_event_signals with (security_invoker = false) as
with amigos as (
  select case when e.requester_id = auth.uid()
              then e.addressee_id else e.requester_id end as friend_id
    from public.friend_edges e
   where e.status = 'accepted'
     and (e.requester_id = auth.uid() or e.addressee_id = auth.uid())
),
visibles as (
  select a.friend_id
    from amigos a
   where private.can_see_activity_of(auth.uid(), a.friend_id)
),
actividad as (
  select distinct t.event_id, t.owner_id as friend_id, true as va
    from public.tickets t
   where t.status in ('active', 'used')
  union
  select distinct i.event_id, i.user_id, false
    from public.event_interests i
),
por_persona as (
  select ac.event_id, ac.friend_id, bool_or(ac.va) as va,
         split_part(trim(p.full_name), ' ', 1) as nombre,
         p.avatar_url
    from actividad ac
    join visibles v on v.friend_id = ac.friend_id
    join public.profiles p on p.id = ac.friend_id
   group by ac.event_id, ac.friend_id, p.full_name, p.avatar_url
)
select
  pp.event_id,
  count(*) filter (where pp.va)     ::int as friends_going,
  count(*) filter (where not pp.va) ::int as friends_interested,
  (array_agg(pp.nombre     order by pp.nombre) filter (where pp.va))[1:2]     as going_names,
  (array_agg(pp.avatar_url order by pp.nombre) filter (where pp.va))[1:2]     as going_avatars,
  (array_agg(pp.nombre     order by pp.nombre) filter (where not pp.va))[1:2] as interested_names,
  (array_agg(pp.avatar_url order by pp.nombre) filter (where not pp.va))[1:2] as interested_avatars
from por_persona pp
group by pp.event_id;

grant select on public.v_my_event_signals to authenticated;

comment on view public.v_my_event_signals is
  'D-40/D-41/D-46. Una fila por PERSONA, no por entrada. Emite conteos, hasta dos nombres de pila y sus avatares, de amistades mutuas no-ninja; nunca zona, precio, cantidad ni id de orden. Los arrays de nombre y avatar van en el mismo orden. Definer, con el filtro por auth.uid() escrito en el where (AC-11).';
