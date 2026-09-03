-- 004 · T-02 … T-05 · Art. 5

create sequence public.order_code_seq;

create table public.orders (
  id          uuid primary key default gen_random_uuid(),
  code        text unique not null
                default 'FVT-' || to_char(now(), 'YYYY') || '-'
                        || lpad(nextval('public.order_code_seq')::text, 6, '0'),
  event_id    uuid not null references public.events (id) on delete restrict,
  buyer_id    uuid not null references public.profiles (id) on delete restrict,
  status      public.order_status not null default 'draft',

  -- Art. 5: cada concepto en su columna, con su nombre. Nada de un total ambiguo.
  subtotal_cents        int not null default 0 check (subtotal_cents >= 0),
  discount_cents        int not null default 0 check (discount_cents >= 0),
  service_charge_cents  int not null default 0 check (service_charge_cents >= 0),
  total_cents           int not null default 0 check (total_cents >= 0),
  currency              char(3) not null default 'PEN',

  -- Congelados al reservar (AC-09): un cambio de política a mitad del checkout
  -- no puede alterar lo que el fan ya vio.
  service_charge_payer public.charge_payer not null default 'fan',
  service_charge_bps   int not null default 600,

  promo_code    text,
  reserved_until timestamptz,

  created_at  timestamptz not null default now(),
  paid_at     timestamptz,
  failed_at   timestamptz,
  expired_at  timestamptz,

  -- El total no puede mentir ni por un error de programación.
  constraint orders_total_is_consistent
    check (total_cents = subtotal_cents - discount_cents + service_charge_cents),
  -- Una orden que retiene stock tiene que tener vencimiento.
  constraint orders_reserved_has_deadline
    check (status not in ('reserved', 'awaiting_payment', 'failed')
           or reserved_until is not null)
);

create index orders_buyer_idx  on public.orders (buyer_id, created_at desc);
create index orders_event_idx  on public.orders (event_id, status);
-- Lo consulta el job de expiración cada minuto: tiene que ir por índice.
create index orders_expiry_idx on public.orders (reserved_until)
  where status in ('reserved', 'awaiting_payment', 'failed');

-- ── order_items: una fila por ENTRADA, sin columna qty ──────────────────────
-- Cada entrada necesita su asiento, su nominación y su ticket. Con `qty` habría
-- que partir la fila al nominar o al emitir, y ese reparto —qué asiento va con
-- qué nombre— es donde se cuelan los bugs.
create table public.order_items (
  id            uuid primary key default gen_random_uuid(),
  order_id      uuid not null references public.orders (id) on delete cascade,
  price_tier_id uuid not null references public.price_tiers (id) on delete restrict,
  seat_id       uuid references public.seats (id) on delete restrict,

  -- Congelado al reservar (AC-09).
  unit_price_cents int not null check (unit_price_cents > 0),

  -- Art. 7.1: el DNI en claro no se persiste. Solo entra por RPC.
  attendee_name       text,
  attendee_dni_hash   text,
  attendee_dni_last4  char(4),
  nominated_at        timestamptz,

  created_at    timestamptz not null default now()
);

create index order_items_order_idx on public.order_items (order_id);
create index order_items_tier_idx  on public.order_items (price_tier_id);

-- AC-06. ESTE índice es lo que impide que dos personas se queden con el mismo
-- asiento. No una consulta de disponibilidad antes del insert: entre la consulta
-- y el insert caben las otras 19 sesiones.
--
-- Sin condición de estado, a propósito. Un índice parcial no puede mirar
-- orders.status, y la alternativa habitual —denormalizar el estado con un
-- trigger— no hace falta: al expirar, la orden BORRA sus order_items, y con eso
-- el asiento queda libre sin que ninguna condición sepa de estados.
create unique index order_items_seat_unique
  on public.order_items (seat_id) where seat_id is not null;

comment on index public.order_items_seat_unique is
  'AC-06: un asiento, una entrada. Al expirar una orden se borran sus items, y así el asiento se libera sin que el índice tenga que conocer estados.';

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.orders      enable row level security;
alter table public.order_items enable row level security;

-- AC-34, AC-35: el fan ve lo suyo. El organizador NO ve órdenes de su evento —
-- solo agregados por vista (D-06, Art. 7.5).
create policy orders_select on public.orders
  for select to authenticated
  using (
    buyer_id = (select auth.uid())
    or private.auth_is_admin()
  );

create policy order_items_select on public.order_items
  for select to authenticated
  using (
    order_id in (select id from public.orders where buyer_id = (select auth.uid()))
    or private.auth_is_admin()
  );

-- AC-37: el cliente no escribe nada aquí. Ni insert, ni update, ni delete.
-- Todo pasa por reserve_order / set_item_attendee / start_payment /
-- confirm_payment (Art. 9.4-9.5).
revoke insert, update, delete on public.orders      from authenticated, anon;
revoke insert, update, delete on public.order_items from authenticated, anon;

comment on table public.orders is
  'Al expirar se conserva la fila con sus totales y status=expired, para conciliación y soporte. Lo que se borra son los order_items, que sin la orden viva no valen nada.';
