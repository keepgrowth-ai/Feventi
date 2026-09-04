-- 009 · T-01 … T-04 · Art. 8

-- ── Los tipos, separados de entrada ─────────────────────────────────────────
-- No es taxonomía por gusto: tratar igual un reembolso y una cancelación es lo
-- que produce el error del Art. 5 más caro. Ver D-12 y el comentario de abajo.
create type public.support_kind as enum (
  'payment', 'ticket', 'qr', 'resale', 'courtesy', 'group',
  'refund', 'cancellation', 'ownership', 'other'
);

create type public.support_status as enum (
  'open', 'waiting_user', 'in_progress', 'escalated', 'resolved', 'closed'
);

create type public.support_priority as enum ('low', 'normal', 'high', 'urgent');

comment on type public.support_kind is
  'D-12: refund (el fan pide a Feventi), cancellation (el evento no ocurre) y una disputa bancaria son TRES procesos distintos. Separarlos de entrada es lo que permite impedir dos vias de recuperacion sobre el mismo pago.';

-- Legible y dictable por teléfono (AC-20). Empieza en 1000 para que el primer
-- caso no sea «#1»: un código de una cifra parece un dato de prueba.
create sequence public.support_case_seq start 1000;

create table public.support_cases (
  id         uuid primary key default gen_random_uuid(),
  code       text unique not null default '#' || nextval('public.support_case_seq')::text,

  kind       public.support_kind     not null,
  status     public.support_status   not null default 'open',
  priority   public.support_priority not null default 'normal',

  opened_by   uuid not null references public.profiles (id) on delete restrict,
  assigned_to uuid references public.profiles (id) on delete set null,

  -- El contexto. Lo rellena `open_support_case` desde el objeto, no el cliente.
  event_id   uuid references public.events (id)   on delete restrict,
  order_id   uuid references public.orders (id)   on delete restrict,
  ticket_id  uuid references public.tickets (id)  on delete restrict,
  checkin_id uuid references public.checkins (id) on delete restrict,

  subject    text not null check (length(trim(subject)) between 3 and 140),
  body       text not null check (length(trim(body)) between 10 and 4000),

  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  resolved_at timestamptz,

  -- AC-01 y AC-02, en la tabla y no en la aplicación: un caso de QR sin ticket
  -- es un caso que Admin no puede resolver sin escribir al usuario a preguntar.
  constraint support_cases_ticket_kinds_need_ticket
    check (kind not in ('ticket', 'qr', 'ownership') or ticket_id is not null),
  constraint support_cases_money_kinds_need_order
    check (kind not in ('payment', 'refund') or order_id is not null),
  -- Resuelto y con hora van juntos, en los dos sentidos.
  constraint support_cases_resolved_has_time
    check ((status in ('resolved', 'closed')) = (resolved_at is not null))
);

create index support_cases_opened_idx   on public.support_cases (opened_by, created_at desc);
-- La cola de Admin: parcial, porque lo cerrado no se mira a diario.
create index support_cases_queue_idx    on public.support_cases (status, priority, created_at)
  where status not in ('resolved', 'closed');
create index support_cases_event_idx    on public.support_cases (event_id, created_at desc);
create index support_cases_ticket_idx   on public.support_cases (ticket_id) where ticket_id is not null;
create index support_cases_assigned_idx on public.support_cases (assigned_to) where assigned_to is not null;

-- AC-06 · D-12. Índice único PARCIAL, no una validación en la RPC: dos
-- peticiones simultáneas pasarían las dos por un `if not exists`. Y parcial
-- porque cerrado el primero se puede abrir otro (AC-07) — que es exactamente lo
-- que la cláusula `where` permite.
create unique index support_cases_one_recovery_per_order
  on public.support_cases (order_id)
  where kind in ('refund', 'cancellation') and status not in ('resolved', 'closed');

create trigger support_cases_touch_updated_at
  before update on public.support_cases
  for each row execute function public.touch_updated_at();

-- ── El hilo ─────────────────────────────────────────────────────────────────
create table public.support_messages (
  id         uuid primary key default gen_random_uuid(),
  case_id    uuid not null references public.support_cases (id) on delete cascade,
  author_id  uuid references public.profiles (id) on delete set null,
  body       text not null check (length(trim(body)) between 1 and 4000),
  -- AC-10 y AC-16: la nota interna es una COLUMNA protegida por RLS. No se
  -- confía en que el front no la pinte — eso no es una protección, es una
  -- esperanza.
  internal   boolean not null default false,
  created_at timestamptz not null default now()
);

create index support_messages_case_idx on public.support_messages (case_id, created_at);

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.support_cases    enable row level security;
alter table public.support_messages enable row level security;

-- AC-09, AC-11, AC-12, AC-13, AC-14. Convención: una política, casos con OR,
-- caso común primero.
--
-- El staff cae en el primer OR y solo en ese: ve lo que él abrió (AC-12). No hay
-- una rama para «staff del evento» a propósito — un caso de puerta puede citar
-- datos del asistente, y el turno siguiente no tiene por qué leerlos.
create policy support_cases_select on public.support_cases
  for select to authenticated
  using (
    opened_by = (select auth.uid())
    or ticket_id in (select id from public.tickets where owner_id = (select auth.uid()))
    or event_id in (
      select id from public.events where organizer_id = any (private.auth_organizer_ids())
    )
    or private.auth_is_admin()
  );

-- AC-15: el cliente no escribe estado, prioridad ni asignación. Todo se mueve
-- por RPC, que comprueban quién llama.
revoke insert, update, delete on public.support_cases from authenticated, anon;

create policy support_messages_select on public.support_messages
  for select to authenticated
  using (
    (
      not internal
      and case_id in (
        select id from public.support_cases
         where opened_by = (select auth.uid())
            or ticket_id in (select id from public.tickets where owner_id = (select auth.uid()))
            or event_id in (
              select id from public.events where organizer_id = any (private.auth_organizer_ids())
            )
      )
    )
    or private.auth_is_admin()
  );

-- AC-17 · Art. 8.1: lo que se escribió, se escribió.
revoke insert, update, delete on public.support_messages from authenticated, anon;

comment on table public.support_cases is
  'Un caso nace DESDE el objeto afectado. event_id y order_id los rellena el servidor desde el ticket (AC-03): el cliente podria mandar los de otro.';
comment on table public.support_messages is
  'Append-only (Art. 8.1). internal = true solo lo escribe Admin y solo Admin lo lee (AC-10, AC-16).';
comment on index public.support_cases_one_recovery_per_order is
  'D-12: no se abren dos vias de recuperacion sobre el mismo pago. Indice, no validacion: dos peticiones a la vez pasarian las dos por un if.';
