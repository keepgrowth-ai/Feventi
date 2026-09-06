-- 012 · Art. 11 · acta §5
--
-- La idea que hace esto pequeño: «todo o nada» YA EXISTE — es una orden con N
-- items, y `reserve_order` la hace en una transaccion. El grupo no es un
-- mecanismo de compra: es la capa que decide QUIEN entra y le entrega a la
-- compra que ya funciona una lista de personas.
--
-- No se toca `reserve_order` ni `confirm_payment`.

create type public.purchase_group_status as enum
  ('open', 'locked', 'completed', 'cancelled');

-- ── El grupo ───────────────────────────────────────────────────────────────
create table public.purchase_groups (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events (id)   on delete cascade,
  creator_id uuid not null references public.profiles (id) on delete cascade,
  status     public.purchase_group_status not null default 'open',
  order_id   uuid references public.orders (id) on delete set null,
  created_at timestamptz not null default now(),
  locked_at  timestamptz,

  -- Bloqueado y con orden van juntos, en los dos sentidos.
  constraint purchase_groups_locked_has_order
    check ((status in ('locked','completed')) = (order_id is not null)),

  -- Para la FK compuesta de group_members. Ver la leccion de 0045 abajo.
  constraint purchase_groups_id_event unique (id, event_id)
);

create index purchase_groups_creator_idx on public.purchase_groups (creator_id, created_at desc);
create index purchase_groups_order_idx   on public.purchase_groups (order_id) where order_id is not null;

-- ── Los miembros ───────────────────────────────────────────────────────────
create table public.group_members (
  group_id      uuid not null,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  -- Denormalizado para poder indexar «una persona, un grupo por evento».
  event_id      uuid not null references public.events (id) on delete cascade,
  -- El arbitro del «hasta 4» del Art. 11.
  slot          smallint not null check (slot between 1 and 4),
  -- Se rellena al bloquear: es lo que hace que el ticket nazca con su dueño.
  order_item_id uuid unique references public.order_items (id) on delete set null,
  joined_at     timestamptz not null default now(),

  primary key (group_id, user_id),

  -- Art. 11, hasta 4. La RPC asigna el slot bajo `for update`; si dos entraran
  -- a la vez y calcularan el mismo, este indice tumba a uno. Indice, no `if`.
  constraint group_members_slot_unique unique (group_id, slot),

  -- LECCION DE 0045: un event_id denormalizado junto a una FK simple no obliga
  -- a nada — nada impediria que el grupo fuera de otro evento. La FK COMPUESTA
  -- si lo obliga.
  constraint group_members_group_in_event
    foreign key (group_id, event_id) references public.purchase_groups (id, event_id)
    on delete cascade
);

-- Una persona, un grupo por evento. Cancelar un grupo borra sus miembros
-- (cascade), asi que el indice no bloquea un segundo intento.
create unique index group_members_one_group_per_event
  on public.group_members (user_id, event_id);

create index group_members_user_idx on public.group_members (user_id);

-- ── RLS ────────────────────────────────────────────────────────────────────
alter table public.purchase_groups enable row level security;
alter table public.group_members   enable row level security;

-- AC-17. Veo un grupo si soy miembro. El creador siempre lo es (slot 1).
create policy purchase_groups_select on public.purchase_groups
  for select to authenticated
  using (
    creator_id = (select auth.uid())
    or id in (select gm.group_id from public.group_members gm
               where gm.user_id = (select auth.uid()))
  );

create policy group_members_select on public.group_members
  for select to authenticated
  using (
    group_id in (select gm.group_id from public.group_members gm
                  where gm.user_id = (select auth.uid()))
  );

-- AC-18. Todo por RPC: los estados y el slot no los escribe el cliente.
revoke insert, update, delete on public.purchase_groups from authenticated, anon;
revoke insert, update, delete on public.group_members   from authenticated, anon;

-- ── Crear ──────────────────────────────────────────────────────────────────
create or replace function public.create_purchase_group(p_event_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, private, pg_temp
as $fn$
declare
  v_me uuid := auth.uid();
  v_id uuid;
begin
  if v_me is null then
    raise exception 'no_autenticado' using errcode = 'P0001';
  end if;

  if not exists (select 1 from public.events e
                  where e.id = p_event_id and e.status = 'published') then
    raise exception 'evento_no_disponible' using errcode = 'P0001';
  end if;

  insert into public.purchase_groups (event_id, creator_id)
  values (p_event_id, v_me)
  returning id into v_id;

  -- El creador es el slot 1. Si ya esta en otro grupo de este evento, el indice
  -- unico lo para aqui (AC-06) y la transaccion entera se revierte: no queda
  -- un grupo vacio de recuerdo.
  insert into public.group_members (group_id, user_id, event_id, slot)
  values (v_id, v_me, p_event_id, 1);

  return v_id;
end;
$fn$;

-- ── Añadir a un amigo ──────────────────────────────────────────────────────
create or replace function public.add_group_member(p_group_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $fn$
declare
  v_me   uuid := auth.uid();
  v_g    public.purchase_groups;
  v_slot smallint;
begin
  if v_me is null then
    raise exception 'no_autenticado' using errcode = 'P0001';
  end if;

  -- El candado PRIMERO: el conteo de slots que viene despues no vale nada sin el.
  select * into v_g from public.purchase_groups where id = p_group_id for update;

  if v_g.id is null then
    raise exception 'no_existe' using errcode = 'P0001';
  end if;
  if v_g.creator_id <> v_me then
    raise exception 'no_autorizado' using errcode = 'P0001';   -- AC-05
  end if;
  if v_g.status <> 'open' then
    raise exception 'grupo_bloqueado' using errcode = 'P0001'; -- AC-13
  end if;

  -- AC-03. Requerir amistad NO es un adorno: sin ella esta RPC acepta cualquier
  -- uuid, y se convierte en la forma de meter a alguien en una compra que no
  -- pidio — y de paso en un oraculo de que uuid existen.
  if not private.are_friends(v_me, p_user_id) then
    raise exception 'no_se_pudo_anadir' using errcode = 'P0001';
  end if;

  select coalesce(max(gm.slot), 0) + 1 into v_slot
    from public.group_members gm where gm.group_id = p_group_id;

  if v_slot > 4 then
    raise exception 'grupo_lleno' using errcode = 'P0001';     -- AC-04
  end if;

  insert into public.group_members (group_id, user_id, event_id, slot)
  values (p_group_id, p_user_id, v_g.event_id, v_slot);
end;
$fn$;

-- ── Salir ──────────────────────────────────────────────────────────────────
create or replace function public.leave_purchase_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $fn$
declare
  v_me uuid := auth.uid();
  v_g  public.purchase_groups;
begin
  if v_me is null then
    raise exception 'no_autenticado' using errcode = 'P0001';
  end if;

  select * into v_g from public.purchase_groups where id = p_group_id for update;

  if v_g.id is null then
    raise exception 'no_existe' using errcode = 'P0001';
  end if;
  if v_g.status <> 'open' then
    -- AC-13. Con la reserva hecha, salirse dejaria una entrada pagada sin dueño.
    raise exception 'grupo_bloqueado' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.group_members gm
                  where gm.group_id = p_group_id and gm.user_id = v_me) then
    raise exception 'no_eres_miembro' using errcode = 'P0001';
  end if;

  if v_g.creator_id = v_me then
    -- AC-09. El creador es quien paga: sin el no hay compra. El grupo se
    -- cancela entero y los miembros se van por cascade — no se queda un grupo
    -- huerfano que nadie puede usar ni borrar.
    update public.purchase_groups set status = 'cancelled' where id = p_group_id;
    delete from public.group_members where group_id = p_group_id;
  else
    delete from public.group_members
     where group_id = p_group_id and user_id = v_me;
  end if;
end;
$fn$;

-- ── Bloquear: aqui se emparejan personas con items ─────────────────────────
create or replace function public.lock_purchase_group(p_group_id uuid, p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $fn$
declare
  v_me      uuid := auth.uid();
  v_g       public.purchase_groups;
  v_o       public.orders;
  v_items   int;
  v_miembros int;
begin
  if v_me is null then
    raise exception 'no_autenticado' using errcode = 'P0001';
  end if;

  select * into v_g from public.purchase_groups where id = p_group_id for update;

  if v_g.id is null then
    raise exception 'no_existe' using errcode = 'P0001';
  end if;
  if v_g.creator_id <> v_me then
    raise exception 'no_autorizado' using errcode = 'P0001';
  end if;
  if v_g.status <> 'open' then
    raise exception 'grupo_bloqueado' using errcode = 'P0001';
  end if;

  select * into v_o from public.orders where id = p_order_id;

  -- La orden tiene que ser suya y del MISMO evento (AC-10). Sin esto, el
  -- creador podria enganchar el grupo a una orden ajena y regalarle sus
  -- entradas a sus amigos.
  if v_o.id is null or v_o.buyer_id <> v_me or v_o.event_id <> v_g.event_id then
    raise exception 'orden_no_valida' using errcode = 'P0001';
  end if;

  select count(*) into v_items    from public.order_items where order_id = p_order_id;
  select count(*) into v_miembros from public.group_members where group_id = p_group_id;

  -- AC-11. Exactamente tantos items como miembros: es el todo-o-nada del
  -- Art. 11 expresado en una comparacion. Con menos, alguien se queda fuera
  -- despues de haber dicho que si.
  if v_items <> v_miembros then
    raise exception 'items_no_cuadran' using errcode = 'P0001';
  end if;

  -- El emparejamiento. Por slot y por orden de creacion del item: dos
  -- secuencias estables, asi que el reparto es reproducible.
  with pares as (
    select gm.user_id,
           (select oi.id from public.order_items oi
             where oi.order_id = p_order_id
             order by oi.created_at, oi.id
             offset gm.slot - 1 limit 1) as item_id
      from public.group_members gm
     where gm.group_id = p_group_id
  )
  update public.group_members gm
     set order_item_id = p.item_id
    from pares p
   where gm.group_id = p_group_id and gm.user_id = p.user_id;

  update public.purchase_groups
     set status = 'locked', order_id = p_order_id, locked_at = now()
   where id = p_group_id;
end;
$fn$;

-- ── El ticket nace con su dueño ────────────────────────────────────────────
-- ESTE es el detalle que decide si la funcion es real o decorativa.
--
-- `confirm_payment` emite los tickets con `owner_id = comprador`. Sin esto, los
-- otros tres tendrian su nombre impreso pero la entrada NO estaria en su
-- wallet: no podrian enseñar su QR ni contarian como «va» en la señal de 011.
--
-- No se transfiere despues — se escribe ANTES de que la fila exista. Asi no hay
-- asiento de correccion ni ventana en la que la entrada sea de otro.
create or replace function private.assign_group_ticket_owner()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $fn$
declare
  v_member uuid;
begin
  select gm.user_id into v_member
    from public.group_members gm
   where gm.order_item_id = new.order_item_id;

  -- AC-16: sin miembro, la compra es normal y el trigger no toca nada.
  if v_member is not null then
    new.owner_id          := v_member;
    new.original_owner_id := v_member;
  end if;

  return new;
end;
$fn$;

create trigger tickets_assign_group_owner
  before insert on public.tickets
  for each row execute function private.assign_group_ticket_owner();

-- ── El grupo se completa al pagar ──────────────────────────────────────────
-- AC-20. Sobre `orders`, no sobre `tickets`: no depende de que los tickets ya
-- existan, y `confirm_payment` los inserta DESPUES de marcar la orden pagada.
create or replace function private.complete_group_on_paid()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $fn$
begin
  if new.status = 'paid' and old.status is distinct from 'paid' then
    update public.purchase_groups
       set status = 'completed'
     where order_id = new.id and status = 'locked';
  end if;
  return new;
end;
$fn$;

create trigger orders_complete_group
  after update on public.orders
  for each row execute function private.complete_group_on_paid();

-- ── Grants (la leccion de 0053: la politica no basta) ──────────────────────
grant execute on function public.create_purchase_group(uuid) to authenticated;
grant execute on function public.add_group_member(uuid, uuid) to authenticated;
grant execute on function public.leave_purchase_group(uuid) to authenticated;
grant execute on function public.lock_purchase_group(uuid, uuid) to authenticated;

-- Y la de 0055: conceder no quita el execute que PUBLIC trae de fabrica.
revoke execute on function public.create_purchase_group(uuid) from public, anon;
revoke execute on function public.add_group_member(uuid, uuid) from public, anon;
revoke execute on function public.leave_purchase_group(uuid) from public, anon;
revoke execute on function public.lock_purchase_group(uuid, uuid) from public, anon;

comment on table public.purchase_groups is
  'Art. 11: hasta 4, atado a evento, todo o nada. El grupo NO es un mecanismo de compra: decide quien entra y le entrega la lista a reserve_order.';
comment on constraint group_members_group_in_event on public.group_members is
  'Leccion de 0045: un event_id denormalizado con FK simple no obliga a nada.';
comment on function private.assign_group_ticket_owner() is
  'El ticket nace con su dueño en vez de transferirse despues. Sin esto la compra grupal seria decorativa: los amigos tendrian su nombre impreso y ninguna entrada en su wallet.';
