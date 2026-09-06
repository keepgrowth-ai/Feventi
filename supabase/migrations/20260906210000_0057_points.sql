-- 013 · T-01 … T-05 · acta §5, §10 · D-44, D-45 · Art. 8.1

create type public.point_reason as enum ('checkin');

-- ── El libro mayor ─────────────────────────────────────────────────────────
-- Un LIBRO, no un contador. No existe `profiles.points` que alguien pueda
-- «ajustar»: el saldo se calcula sumando asientos. Un saldo editable deja de
-- ser una bitacora y pasa a ser una opinion.
create table public.point_ledger (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  kind       public.point_reason not null,
  points     integer not null check (points > 0),
  event_id   uuid references public.events (id)   on delete set null,
  checkin_id uuid references public.checkins (id) on delete set null,
  created_at timestamptz not null default now()
);

create index point_ledger_user_idx on public.point_ledger (user_id, created_at desc);

-- El arbitro contra el doble abono. Un ticket escaneado dos veces produce un
-- SEGUNDO checkin —con result = already_used— y aunque el trigger ya lo filtra,
-- este indice es el que lo garantiza si alguien cambia la condicion del trigger.
create unique index point_ledger_one_per_checkin
  on public.point_ledger (checkin_id) where checkin_id is not null;

alter table public.point_ledger enable row level security;

-- AC-08. Solo lo mio.
create policy point_ledger_select on public.point_ledger
  for select to authenticated
  using (user_id = (select auth.uid()));

-- AC-09 · Art. 8.1: append-only. Ni el dueño escribe su propio saldo. Lo
-- escribe el trigger, que corre como el dueño de la funcion.
revoke insert, update, delete on public.point_ledger from authenticated, anon;

-- ── Cuantos puntos vale entrar ─────────────────────────────────────────────
-- 50, como dice el mockup L685. En su propia constante para que cambiarlo sea
-- una migracion y no una busqueda por el codigo.
create or replace function private.checkin_points()
returns integer language sql immutable
as $fn$ select 50 $fn$;

-- ── El trigger ─────────────────────────────────────────────────────────────
-- Un TRIGGER, no una modificacion de `gate_checkin`.
--
-- `gate_checkin` es la funcion mas verificada del proyecto y la que decide si
-- alguien entra al evento. Meterle una escritura de puntos le añade una forma
-- de fallar a la operacion que NO PUEDE fallar en la puerta. Un `after insert`
-- corre en la misma transaccion —asi que el punto y el ingreso son atomicos
-- (AC-11)— sin tocar una linea de la decision.
--
-- El punto se le abona al DUEÑO DEL TICKET (AC-05), no a `checkins.staff_id`,
-- que es quien escanea. Confundirlos premiaria al portero por trabajar.
create or replace function private.award_points_on_checkin()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $fn$
declare
  v_owner uuid;
begin
  -- AC-02, AC-03, AC-04: solo un ingreso permitido suma. `manual_review` no:
  -- si el modo DNI acaba siendo legitimo lo confirma un humano, y esa
  -- correccion es Fase 2.
  if new.result <> 'allowed' or new.ticket_id is null then
    return new;
  end if;

  select t.owner_id into v_owner
    from public.tickets t where t.id = new.ticket_id;

  if v_owner is null then
    return new;
  end if;

  insert into public.point_ledger (user_id, kind, points, event_id, checkin_id)
  values (v_owner, 'checkin', private.checkin_points(), new.event_id, new.id)
  -- El indice unico ya lo impide; esto evita que un doble abono tumbe el
  -- ingreso. En la puerta, la entrada manda sobre el punto.
  on conflict do nothing;

  return new;
end;
$fn$;

create trigger checkins_award_points
  after insert on public.checkins
  for each row execute function private.award_points_on_checkin();

-- ── El saldo ───────────────────────────────────────────────────────────────
-- `security_invoker`: la RLS de point_ledger ya acota a lo mio, asi que invoker
-- basta. Cuando invoker basta, se usa invoker.
create or replace view public.v_my_points
with (security_invoker = true) as
select coalesce(sum(pl.points), 0)::int as total
  from public.point_ledger pl;

grant select on public.v_my_points to authenticated;

comment on table public.point_ledger is
  'Art. 8.1 append-only. D-45: se otorga por asistencia real (checkin allowed), no por comprar — comprar es reversible y entrar no. D-44: no se canjean por nada.';
comment on index public.point_ledger_one_per_checkin is
  'Un ticket escaneado dos veces produce dos checkins. Solo el primero abona.';
