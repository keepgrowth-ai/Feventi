-- 011 · corrección y mejora · acta §4, §6 · D-46
--
-- DOS COSAS.
--
-- ── 1. Un bug: la señal contaba ENTRADAS, no personas ──────────────────────
--
-- `count(*)` sobre la unión de tickets e intereses cuenta filas. Un amigo con
-- dos entradas del mismo evento salía como «2 amigos ya tienen entrada».
-- Comprobado con la semilla de la demo: Camila tiene 2 entradas de Zona Ritmo,
-- así que cualquier amigo suyo la vería contada dos veces.
--
-- Es el peor tipo de fallo para esta función: no rompe nada, solo miente un
-- poco, y el número miente hacia arriba — justo en la dirección que hace que
-- parezca que funciona mejor de lo que funciona. Se arregla con
-- `count(distinct friend_id)`.
--
-- ── 2. La señal ahora dice QUIÉN ───────────────────────────────────────────
--
-- El spec de 011 puso «nombres» entre los NO objetivos, apoyándose en que el
-- mockup enseña conteos y el mockup manda. Pero el mockup se dibujó ANTES del
-- acta, y el acta pide otra cosa —§4: «debe SENTIRSE como una red social»; §6:
-- «descubra que amigos o personas de su comunidad también irán»—. «2 amigos
-- quieren ir» es un dato. «Diego y Valeria quieren ir» es una razón para ir.
--
-- No contradice D-40, que dice que la señal revela EL HECHO y no el detalle de
-- la compra: un nombre no es la zona, ni el precio, ni cuántas entradas. Y no
-- revela a nadie nuevo — son amistades mutuas y aceptadas, cuyos nombres ya
-- salen en `/amigos` desde 010.
--
-- Queda como **D-46** en decisiones-pendientes, con su default: se muestran
-- hasta DOS nombres y el resto como «y N más». Dos porque tres ya no caben en
-- la tarjeta del catálogo, y porque «Diego, Valeria y Ana» se lee como una
-- lista y «Diego y Valeria» se lee como una frase.
--
-- El nombre es el de PILA. «Diego Salazar y Valeria Ríos ya tienen entrada» es
-- una notificación de banco; «Diego y Valeria» es cómo hablan las personas.

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
  -- Bloqueo y ninja, los dos, en una sola llamada. 011 no vuelve a decidir
  -- quién ve a quién: si hubiera dos sitios que lo deciden, uno se queda atrás.
  select a.friend_id
    from amigos a
   where private.can_see_activity_of(auth.uid(), a.friend_id)
),
actividad as (
  -- De los seis estados del enum entran DOS. `listed` queda fuera aunque la
  -- entrada siga siendo suya: quien la publicó en reventa está intentando no
  -- ir, y anunciar «va» de quien vende su entrada es la señal al revés.
  select distinct t.event_id, t.owner_id as friend_id, true as va
    from public.tickets t
   where t.status in ('active', 'used')
  union
  select distinct i.event_id, i.user_id, false
    from public.event_interests i
),
-- Una fila por PERSONA y evento. El `distinct` de arriba ya colapsa las dos
-- entradas de un mismo amigo; esto además evita contarlo dos veces si tiene
-- entrada Y marcó interés — en ese caso manda «va», que es más fuerte.
por_persona as (
  select ac.event_id, ac.friend_id, bool_or(ac.va) as va,
         split_part(trim(p.full_name), ' ', 1) as nombre
    from actividad ac
    join visibles v on v.friend_id = ac.friend_id
    join public.profiles p on p.id = ac.friend_id
   group by ac.event_id, ac.friend_id, p.full_name
)
select
  pp.event_id,
  count(*) filter (where pp.va)     ::int as friends_going,
  count(*) filter (where not pp.va) ::int as friends_interested,
  -- Hasta dos nombres. El resto lo cuenta el número de arriba.
  (array_agg(pp.nombre order by pp.nombre) filter (where pp.va))[1:2]     as going_names,
  (array_agg(pp.nombre order by pp.nombre) filter (where not pp.va))[1:2] as interested_names
from por_persona pp
group by pp.event_id;

grant select on public.v_my_event_signals to authenticated;

comment on view public.v_my_event_signals is
  'D-40/D-41/D-46. Una fila por PERSONA, no por entrada (el count(*) anterior contaba tickets). Emite conteos y hasta dos nombres de pila de amistades mutuas no-ninja; nunca zona, precio, cantidad ni id de orden. Definer, con el filtro por auth.uid() escrito en el where (AC-11). El ninja lo resuelve private.can_see_activity_of.';
