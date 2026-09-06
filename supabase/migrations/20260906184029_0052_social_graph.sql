-- 010 · T-01 … T-09 · Art. 7.3, Art. 9

-- ── El estado de una arista ────────────────────────────────────────────────
-- Solo dos valores. «Rechazada» NO es un estado: es la ausencia de la fila.
-- Guardar rechazos deja a A saber que B lo rechazo (consultando por que no puede
-- volver a pedir) y crea un cementerio que nadie consulta. Rechazar borra.
create type public.friend_edge_status as enum ('pending', 'accepted');

-- ── friend_edges ───────────────────────────────────────────────────────────
-- Una sola tabla para solicitud y amistad: son el mismo hecho en dos momentos.
create table public.friend_edges (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles (id) on delete cascade,
  addressee_id uuid not null references public.profiles (id) on delete cascade,
  status       public.friend_edge_status not null default 'pending',
  created_at   timestamptz not null default now(),
  responded_at timestamptz,

  constraint friend_edges_no_self check (requester_id <> addressee_id),
  -- Pendiente y sin hora van juntos, en los dos sentidos.
  constraint friend_edges_accepted_has_time
    check ((status = 'accepted') = (responded_at is not null))
);

-- AC-04. El arbitro: si A pide a B y B pide a A a la vez, la segunda falla.
-- Indice, no validacion en la RPC — dos peticiones simultaneas pasarian las dos
-- por un `if not exists`. Mismo patron que support_cases_one_recovery_per_order.
create unique index friend_edges_one_per_pair
  on public.friend_edges (least(requester_id, addressee_id),
                          greatest(requester_id, addressee_id));

-- Las dos direcciones de lectura: «mis amigos» y «quien me pidio».
create index friend_edges_requester_idx on public.friend_edges (requester_id, status);
create index friend_edges_addressee_idx on public.friend_edges (addressee_id, status);

-- ── blocks ─────────────────────────────────────────────────────────────────
-- Tabla aparte y no un status mas, por tres razones:
--   1. Bloquear SOBREVIVE a dejar de ser amigos. Como estado de la arista, dar
--      de baja la amistad borraria el bloqueo.
--   2. Bloquear es direccional de verdad: A bloquea a B sin que B lo sepa.
--   3. Con un solo enum, «desbloquear» y «dejar de ser amigos» acaban siendo la
--      misma operacion. Son dos cosas con dos consecuencias distintas.
create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),

  primary key (blocker_id, blocked_id),
  constraint blocks_no_self check (blocker_id <> blocked_id)
);

-- AC-09: `are_friends` consulta por blocked_id para saber si me bloquearon.
create index blocks_blocked_idx on public.blocks (blocked_id);

-- ── RLS · en la MISMA migracion que crea las tablas ────────────────────────
alter table public.friend_edges enable row level security;
alter table public.blocks       enable row level security;

-- AC-07. Una politica por operacion, casos con OR, caso comun primero.
create policy friend_edges_select on public.friend_edges
  for select to authenticated
  using (
    requester_id = (select auth.uid())
    or addressee_id = (select auth.uid())
  );

-- Dejar de ser amigos borra de verdad. friend_edges NO es append-only: el Art. 8
-- enumera lo que se audita —checkins, decisiones de Admin, titularidad, dinero—
-- y una amistad no esta ahi. Borrar es lo correcto en materia de datos
-- personales, no una laxitud.
create policy friend_edges_delete on public.friend_edges
  for delete to authenticated
  using (
    requester_id = (select auth.uid())
    or addressee_id = (select auth.uid())
  );

-- AC-15: el cliente no escribe estado ni crea aristas. Todo por RPC.
revoke insert, update on public.friend_edges from authenticated, anon;

-- AC-10. Un bloqueo que se puede detectar no protege de nada: solo su dueño lo
-- lee. Por eso NO hay rama `blocked_id = auth.uid()` en el select.
create policy blocks_select on public.blocks
  for select to authenticated
  using (blocker_id = (select auth.uid()));

create policy blocks_insert on public.blocks
  for insert to authenticated
  with check (blocker_id = (select auth.uid()));

create policy blocks_delete on public.blocks
  for delete to authenticated
  using (blocker_id = (select auth.uid()));

revoke update on public.blocks from authenticated, anon;

-- ── Los helpers ────────────────────────────────────────────────────────────
-- Viven en `private` a proposito: PostgREST no expone ese esquema, asi que
-- can_see_activity_of no es llamable desde el cliente ni por accidente. 011 la
-- usara desde una vista `security invoker`, la unica forma correcta de que el
-- filtro de ninja no se pueda saltar.

create or replace function private.are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.friend_edges e
     where e.status = 'accepted'
       and ((e.requester_id = a and e.addressee_id = b)
         or (e.requester_id = b and e.addressee_id = a))
  )
  -- AC-09: un bloqueo en cualquier direccion rompe la amistad a efectos de
  -- visibilidad, sin borrar la arista.
  and not exists (
    select 1 from public.blocks bl
     where (bl.blocker_id = a and bl.blocked_id = b)
        or (bl.blocker_id = b and bl.blocked_id = a)
  );
$$;

-- La UNICA funcion que 011 tiene permitido llamar.
--
-- El modo ninja se evalua sobre el SUJETO, no sobre el observador (D-43):
-- esconderse no es cegarse. Quien activa ninja deja de emitir señales y sigue
-- viendo las de sus amigos. Asimetrico a proposito — castigar la privacidad con
-- menos producto es la forma mas segura de que nadie la active.
--
-- `stable` y no `volatile`: 011 la llama una vez por evento y por amigo.
create or replace function private.can_see_activity_of(viewer uuid, subject uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select private.are_friends(viewer, subject)
     and not coalesce((select p.ninja_mode from public.profiles p where p.id = subject), false);
$$;

comment on function private.can_see_activity_of(uuid, uuid) is
  'Art. 7.3 + D-43. Ninja se evalua sobre el sujeto: deja de emitir señales, sigue viendo. NO afecta a puerta, antifraude, auditoria ni soporte.';

-- ── RPC: pedir amistad ─────────────────────────────────────────────────────
-- AC-01, AC-02, AC-03.
--
-- Los CUATRO casos de fallo devuelven el mismo mensaje, y el front muestra ese
-- mismo texto tambien en el exito. Si el exito dijera otra cosa, el formulario
-- seguiria siendo un oraculo de «¿esta esta persona registrada en Feventi?»:
-- bastaria con mirar cual de los dos textos sale.
create or replace function public.request_friendship(target_email text)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_me     uuid := auth.uid();
  v_target uuid;
begin
  if v_me is null then
    raise exception 'no_autenticado' using errcode = 'P0001';
  end if;

  -- Correo EXACTO, normalizado. Sin `like`: una busqueda parcial es un
  -- directorio de usuarios disfrazado de buscador (D-38).
  select p.id into v_target
    from public.profiles p
   where lower(p.email) = lower(trim(target_email))
   limit 1;

  if v_target is null
     or v_target = v_me
     or exists (select 1 from public.blocks bl
                 where (bl.blocker_id = v_me and bl.blocked_id = v_target)
                    or (bl.blocker_id = v_target and bl.blocked_id = v_me))
  then
    raise exception 'no_se_pudo_enviar' using errcode = 'P0001';
  end if;

  -- El indice unico decide el empate; esto solo evita el error feo en el caso
  -- secuencial. AC-04 verifica que el indice hace su trabajo en el concurrente.
  begin
    insert into public.friend_edges (requester_id, addressee_id)
    values (v_me, v_target);
  exception when unique_violation then
    raise exception 'no_se_pudo_enviar' using errcode = 'P0001';
  end;
end;
$$;

-- ── RPC: responder ─────────────────────────────────────────────────────────
-- AC-05, AC-06. Una transicion de estado va en una RPC, no en una politica.
create or replace function public.respond_friendship(edge_id uuid, accept boolean)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_me   uuid := auth.uid();
  v_edge public.friend_edges;
begin
  if v_me is null then
    raise exception 'no_autenticado' using errcode = 'P0001';
  end if;

  -- El candado PRIMERO, antes de comprobar el estado. Dos pestañas aceptando a
  -- la vez es el caso real que esto resuelve.
  select * into v_edge from public.friend_edges
   where id = edge_id
   for update;

  if v_edge.id is null then
    raise exception 'no_existe' using errcode = 'P0001';
  end if;
  if v_edge.addressee_id <> v_me then
    raise exception 'no_autorizado' using errcode = 'P0001';
  end if;
  if v_edge.status <> 'pending' then
    raise exception 'ya_respondida' using errcode = 'P0001';
  end if;

  if accept then
    update public.friend_edges
       set status = 'accepted', responded_at = now()
     where id = edge_id;
  else
    -- Rechazar borra. Ver el comentario del enum.
    delete from public.friend_edges where id = edge_id;
  end if;
end;
$$;

-- ── RPC: bloquear ──────────────────────────────────────────────────────────
-- AC-11: bloquear NO borra la arista. Son dos hechos independientes y el
-- bloqueo tiene que sobrevivir a que la amistad se deshaga.
create or replace function public.block_user(target_id uuid)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'no_autenticado' using errcode = 'P0001';
  end if;
  if target_id = v_me then
    raise exception 'no_se_pudo_bloquear' using errcode = 'P0001';
  end if;

  insert into public.blocks (blocker_id, blocked_id)
  values (v_me, target_id)
  on conflict do nothing;
end;
$$;

-- ── Vistas ─────────────────────────────────────────────────────────────────
-- `security invoker`: la RLS de friend_edges hace el trabajo. No devuelven
-- ninja_mode — si el front supiera quien esta en ninja, la funcion estaria rota
-- por diseño. El front no necesita saberlo; la base de datos si.

create or replace view public.v_my_friends
with (security_invoker = true) as
select
  e.id                                            as edge_id,
  case when e.requester_id = auth.uid()
       then e.addressee_id else e.requester_id end as friend_id,
  p.full_name,
  p.avatar_url,
  e.responded_at                                  as since
from public.friend_edges e
join public.profiles p
  on p.id = case when e.requester_id = auth.uid()
                 then e.addressee_id else e.requester_id end
where e.status = 'accepted'
  and not exists (
    select 1 from public.blocks bl
     where (bl.blocker_id = auth.uid() and bl.blocked_id = p.id)
        or (bl.blocker_id = p.id and bl.blocked_id = auth.uid())
  );

create or replace view public.v_my_friend_requests
with (security_invoker = true) as
select
  e.id           as edge_id,
  e.requester_id,
  p.full_name,
  p.avatar_url,
  e.created_at
from public.friend_edges e
join public.profiles p on p.id = e.requester_id
where e.status = 'pending'
  and e.addressee_id = auth.uid()
  and not exists (
    select 1 from public.blocks bl
     where (bl.blocker_id = auth.uid() and bl.blocked_id = p.id)
        or (bl.blocker_id = p.id and bl.blocked_id = auth.uid())
  );

-- Los privilegios por defecto estan invertidos (0009): hay que conceder.
grant select on public.v_my_friends         to authenticated;
grant select on public.v_my_friend_requests to authenticated;

grant execute on function public.request_friendship(text)      to authenticated;
grant execute on function public.respond_friendship(uuid, boolean) to authenticated;
grant execute on function public.block_user(uuid)              to authenticated;

comment on table public.friend_edges is
  'D-39: la amistad es simetrica pero la fila es direccional. El indice one_per_pair impide la doble arista. Rechazar borra; no hay estado rejected.';
comment on table public.blocks is
  'AC-10: solo su dueño lee sus filas. Un bloqueo detectable no protege de nada.';
comment on index public.friend_edges_one_per_pair is
  'AC-04: A pide a B y B pide a A a la vez -> la segunda falla. Indice, no if.';
