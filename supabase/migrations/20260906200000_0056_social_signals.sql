-- 011 · T-01 … T-04 · acta §5, §6 · D-40, D-41

-- ── event_interests ────────────────────────────────────────────────────────
-- «Ya tiene entrada» ya se deduce de `tickets`. «Quiere ir» no existia en
-- ninguna parte, y es la mitad de la señal del mockup.
--
-- Sin columna `status`: quitar el interes BORRA la fila. Un `interested = false`
-- guardaria para siempre a que eventos dijo alguien que no, que es justo lo que
-- nadie pidio almacenar.
create table public.event_interests (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  event_id   uuid not null references public.events (id)   on delete cascade,
  created_at timestamptz not null default now(),

  -- La PK ES el «una vez por persona y evento». Sin ella haria falta una
  -- comprobacion en la aplicacion, que dos peticiones a la vez se saltan.
  primary key (user_id, event_id)
);

-- El camino de lectura de la vista: «que amigos se interesaron por este evento».
create index event_interests_event_idx on public.event_interests (event_id);

alter table public.event_interests enable row level security;

-- AC-13. Solo el mio, en las tres operaciones. Marcar interes a nombre de otro
-- es exactamente como se fabricaria una señal social falsa.
create policy event_interests_select on public.event_interests
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy event_interests_insert on public.event_interests
  for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy event_interests_delete on public.event_interests
  for delete to authenticated
  using (user_id = (select auth.uid()));

revoke update on public.event_interests from authenticated, anon;

-- La leccion de 0053: la politica no sirve de nada sin el grant de tabla. La
-- 0009 invirtio los privilegios por defecto y la tabla nueva nace solo con
-- `select`; sin esto, Postgres devuelve 42501 ANTES de evaluar la politica.
grant select, insert, delete on public.event_interests to authenticated;

-- ── La señal ───────────────────────────────────────────────────────────────
-- Una fila por evento donde alguno de mis amigos VISIBLES va o quiere ir.
--
-- `security definer` por lo mismo que las vistas de 010: lee `tickets` y
-- `event_interests` de OTRA gente, que ninguna politica me deja ver. Eso es
-- justamente lo que hace de esto una revelacion deliberada y no un accidente.
--
-- ⚠️ Definer apaga la RLS de debajo. El filtro por auth.uid() esta escrito dos
-- veces en el `where` de `amigos` y es lo unico que separa esta vista del grafo
-- social entero. Cubierto por AC-11.
--
-- El ninja NO se comprueba aqui: se delega en `private.can_see_activity_of`,
-- que 010 dejo escrita. Si hubiera dos sitios que deciden quien ve a quien, uno
-- de los dos se quedaria atras — y el que se queda atras es el que filtra.
create view public.v_my_event_signals with (security_invoker = false) as
with amigos as (
  select case when e.requester_id = auth.uid()
              then e.addressee_id else e.requester_id end as friend_id
    from public.friend_edges e
   where e.status = 'accepted'
     and (e.requester_id = auth.uid() or e.addressee_id = auth.uid())
),
visibles as (
  -- Bloqueo y ninja, los dos, en una sola llamada.
  select a.friend_id
    from amigos a
   where private.can_see_activity_of(auth.uid(), a.friend_id)
),
actividad as (
  -- AC-08: `used` sigue contando. Ya entro: sigue yendo.
  -- AC-09: un ticket solo existe con el pago confirmado (Art. 3), asi que una
  -- orden a medias no aparece aqui sin necesidad de filtrarla.
  --
  -- De los seis estados del enum entran DOS. `listed` queda fuera a proposito
  -- aunque la entrada siga siendo suya: quien la publico en reventa esta
  -- intentando no ir, y anunciar «va» de alguien que esta vendiendo su entrada
  -- es la señal al reves. `transferred`, `void` y `refunded` son obvios.
  select t.event_id, t.owner_id as friend_id, true as va
    from public.tickets t
   where t.status in ('active', 'used')
  union all
  select i.event_id, i.user_id, false
    from public.event_interests i
)
select
  ac.event_id,
  count(*) filter (where ac.va)     ::int as friends_going,
  count(*) filter (where not ac.va) ::int as friends_interested
from actividad ac
join visibles v on v.friend_id = ac.friend_id
-- AC-07: un evento sin ningun amigo no sale. Cero no es un valor que enseñar —
-- «0 amigos van» es peor que no decir nada.
group by ac.event_id;

grant select on public.v_my_event_signals to authenticated;

comment on table public.event_interests is
  'D-40: la mitad «quiere ir» de la señal. Sin status: quitar el interes borra la fila.';
comment on view public.v_my_event_signals is
  'D-40/D-41. Emite SOLO conteos: nunca zona, precio, cantidad ni id de orden. Definer, con el filtro por auth.uid() escrito en el where (AC-11). El ninja lo resuelve private.can_see_activity_of, no esta vista.';
