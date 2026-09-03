-- 007 · T-01

-- Art. 4: solo 'published' habilita venta. Se enforce en la función de reserva
-- de 004, no en la UI.
create type public.event_status as enum (
  'draft',              -- borrador del organizador, invisible
  'pending_review',     -- enviado a Admin; NO vende (Art. 4.2)
  'changes_requested',  -- Admin pidió info
  'rejected',
  'approved',           -- aprobado pero sin inventario todavía
  'setup',              -- cargando zonas, fases y precios
  'published',          -- ÚNICA condición que habilita venta
  'paused',             -- venta detenida; los tickets emitidos siguen válidos
  'cancelled',
  'finished'
);

create type public.event_visibility as enum ('public', 'unlisted', 'private');

-- Art. 5: el cargo de servicio lo paga el fan o lo absorbe el organizador,
-- y se muestra desde el primer paso en los dos casos.
create type public.charge_payer as enum ('fan', 'organizer');

-- Art. 11: strict = sin nominar no entra; flexible = entra a revisión manual
-- y genera alerta en puerta.
create type public.nomination_mode as enum ('strict', 'flexible');

-- Art. 4.3 y 8: toda decisión de Admin deja asiento con su tipo.
create type public.review_action as enum (
  'submitted', 'info_requested', 'approved', 'rejected',
  'published', 'paused', 'cancelled', 'note'
);

comment on type public.event_status is
  'Una sola tabla cubre solicitud y evento: la pantalla "Solicitudes" es events filtrada por status. Ver specs/007-solicitud-aprobacion/plan.md.';
