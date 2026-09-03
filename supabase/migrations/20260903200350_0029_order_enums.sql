-- 004 · T-01

create type public.order_status as enum (
  'draft',              -- creada, sin stock retenido
  'reserved',           -- RETIENE stock, con reserved_until
  'awaiting_payment',   -- pago en curso; el botón se bloquea
  'paid',               -- la ÚNICA transición que emite tickets (Art. 2.1)
  'failed',             -- conserva la reserva hasta reserved_until, para reintentar
  'expired',            -- liberada por el job; sus order_items se borran
  'refunded',           -- Fase 2: nada lo produce todavía
  'cancelled'
);

create type public.payment_status as enum (
  'pending', 'succeeded', 'failed', 'refunded', 'disputed'
);

create type public.ticket_status as enum (
  'active',       -- válido; QR disponible dentro de ventana
  'listed',       -- en reventa: QR inhabilitado (Art. 2.4)
  'transferred',  -- cedido: esta fila ya no entra
  'used',         -- consumido en puerta
  'void',         -- anulado por Admin
  'refunded'
);

create type public.ticket_event_action as enum (
  'issued', 'nominated', 'listed', 'unlisted', 'transferred',
  'used', 'voided', 'refunded', 'corrected'
);

comment on type public.order_status is
  'Solo paid emite tickets, y en la misma transacción (Art. 2.1). failed conserva la reserva; expired la libera y borra sus items.';
