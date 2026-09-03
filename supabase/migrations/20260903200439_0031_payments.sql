-- 004 · T-06 · Art. 13

create table public.payments (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null references public.orders (id) on delete restrict,
  -- Art. 13: sandbox hasta que existan las políticas de cancelación, reembolso,
  -- retenciones y liquidación por escrito. El paso a producción es una decisión
  -- de negocio, no un despliegue.
  provider     text not null default 'culqi_sandbox',
  provider_ref text,
  status       public.payment_status not null default 'pending',
  amount_cents int not null check (amount_cents > 0),
  currency     char(3) not null default 'PEN',
  -- La respuesta cruda de la pasarela, para conciliar cuando algo no cuadre.
  raw          jsonb,
  created_at   timestamptz not null default now(),
  settled_at   timestamptz
);

create index payments_order_idx on public.payments (order_id, created_at desc);

-- AC-21. ESTA es la clave de idempotencia, y no es opcional: los webhooks de
-- pasarela REINTENTAN. Sin este índice, un reintento emite los tickets otra vez
-- — y eso se descubre en la puerta, con dos personas y el mismo asiento.
create unique index payments_provider_ref_unique
  on public.payments (provider, provider_ref) where provider_ref is not null;

alter table public.payments enable row level security;

-- AC-34: el fan ve los pagos de sus órdenes. El organizador, ninguno.
create policy payments_select on public.payments
  for select to authenticated
  using (
    order_id in (select id from public.orders where buyer_id = (select auth.uid()))
    or private.auth_is_admin()
  );

-- El cliente no escribe pagos. Los escribe confirm_payment, que es de
-- service_role porque la llama el webhook (AC-29).
revoke insert, update, delete on public.payments from authenticated, anon;

comment on index public.payments_provider_ref_unique is
  'AC-21: la idempotencia de la emisión. Un webhook reintentado no puede emitir tickets dos veces.';
