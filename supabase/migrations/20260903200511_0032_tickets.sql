-- 004 · T-07 … T-10 · Art. 2

create table public.tickets (
  id            uuid primary key default gen_random_uuid(),
  -- AC-23: alfabeto sin 0/O ni 1/I/L. Alguien va a dictar esto por teléfono a
  -- soporte a las once de la noche.
  code          text unique not null,
  event_id      uuid not null references public.events (id) on delete restrict,
  -- Uno a uno con el ítem: por eso order_items no tiene `qty`.
  order_item_id uuid unique not null references public.order_items (id) on delete restrict,
  zone_id       uuid not null references public.zones (id) on delete restrict,
  seat_id       uuid references public.seats (id) on delete restrict,

  owner_id          uuid not null references public.profiles (id) on delete restrict,
  original_owner_id uuid not null references public.profiles (id) on delete restrict,

  -- Art. 7.1: hasheado, y solo entra por RPC.
  holder_name       text,
  holder_dni_hash   text,
  holder_dni_last4  char(4),

  status        public.ticket_status not null default 'active',
  -- Art. 6.2: el techo de reventa es lo que se pagó por él.
  face_value_cents int not null check (face_value_cents > 0),
  resale_count  int not null default 0 check (resale_count >= 0),
  -- Art. 2.5: starts_at - qr_lead_days. Fuera de esa ventana la wallet muestra
  -- el ticket pero no el QR, y dice desde cuándo.
  qr_available_from timestamptz,

  issued_at     timestamptz not null default now(),
  used_at       timestamptz,

  -- Solo 'used' tiene hora de uso, y 'used' la exige.
  constraint tickets_used_has_time
    check ((status = 'used') = (used_at is not null))
);

create index tickets_owner_idx on public.tickets (owner_id, issued_at desc);
create index tickets_event_idx on public.tickets (event_id, status);
create index tickets_seat_idx  on public.tickets (seat_id) where seat_id is not null;
-- Modo DNI del validador (D-03): el staff busca por documento.
create index tickets_holder_dni_idx on public.tickets (event_id, holder_dni_hash)
  where holder_dni_hash is not null;

-- ── Art. 2.6: el secreto del QR nunca sale de la base ───────────────────────
-- Tabla aparte con RLS activa y CERO políticas, igual que profile_identity. No
-- es legible por anon, ni por authenticated, ni por el propietario del ticket.
-- Solo service_role, desde la Edge Function que emite y valida el QR (005, 006).
create table public.ticket_secrets (
  ticket_id  uuid primary key references public.tickets (id) on delete cascade,
  secret     bytea not null,
  rotated_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.ticket_secrets enable row level security;
revoke all on public.ticket_secrets from authenticated, anon;

comment on table public.ticket_secrets is
  'Art. 2.6. RLS activa y sin ninguna política: inalcanzable por diseño. 32 bytes por ticket, base del HMAC del QR rotativo de 005.';

-- ── Art. 8: append-only ─────────────────────────────────────────────────────
create table public.ticket_events (
  id          uuid primary key default gen_random_uuid(),
  ticket_id   uuid not null references public.tickets (id) on delete cascade,
  actor_id    uuid references public.profiles (id),   -- null = el sistema
  action      public.ticket_event_action not null,
  meta        jsonb,
  -- Art. 8.3: corregir es un asiento NUEVO que referencia al anterior.
  corrects_id uuid references public.ticket_events (id),
  created_at  timestamptz not null default now()
);

create index ticket_events_ticket_idx on public.ticket_events (ticket_id, created_at);

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.tickets       enable row level security;
alter table public.ticket_events enable row level security;

-- AC-12 de 005: el fan lee los tickets donde es owner. El organizador NO lee
-- tickets individuales de su evento (D-06, Art. 7.5) — solo agregados.
-- El staff tampoco: valida por Edge Function, que corre con service_role.
create policy tickets_select on public.tickets
  for select to authenticated
  using (
    owner_id = (select auth.uid())
    or private.auth_is_admin()
  );

create policy ticket_events_select on public.ticket_events
  for select to authenticated
  using (
    ticket_id in (select id from public.tickets where owner_id = (select auth.uid()))
    or private.auth_is_admin()
  );

-- AC-19: confirm_payment es la ÚNICA vía de creación de tickets.
-- AC-15 de 005: el fan no puede update ni delete. Todo cambio de estado va por
-- RPC o Edge Function.
revoke insert, update, delete on public.tickets       from authenticated, anon;
-- Art. 8.1: append-only. Ni update ni delete para nadie fuera de service_role.
revoke insert, update, delete on public.ticket_events from authenticated, anon;

-- ── El código del ticket ────────────────────────────────────────────────────
-- Aleatorio con reintento, no secuencial. Un código secuencial se puede
-- enumerar; y aunque el código NO es la credencial (Art. 2: eso es el QR), sí
-- permite sondear soporte. Con 30^6 ≈ 729 millones y unos miles de tickets, la
-- colisión es tan rara que tres intentos sobran.
create or replace function private.new_ticket_code()
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  -- Sin 0/O ni 1/I/L: se dicta por teléfono.
  v_alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  v_code text;
  v_try  int := 0;
begin
  loop
    v_try := v_try + 1;
    v_code := 'FVT-' || to_char(now(), 'YYYY') || '-' || (
      select string_agg(substr(v_alphabet,
               1 + floor(random() * length(v_alphabet))::int, 1), '')
        from generate_series(1, 6)
    );
    if not exists (select 1 from public.tickets where code = v_code) then
      return v_code;
    end if;
    if v_try >= 5 then
      raise exception 'no se pudo generar un código de ticket único' using errcode = '55000';
    end if;
  end loop;
end $$;

revoke all on function private.new_ticket_code() from public, anon, authenticated;
