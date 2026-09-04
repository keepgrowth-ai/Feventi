-- 006 · T-01 … T-04 · Art. 8 y 10
--
-- Dos tablas y sus enums. El staff de puerta es un rol que vive POR EVENTO, no
-- en el perfil: la misma persona puede ser staff del festival del sábado y no
-- serlo del concierto del domingo. Meterlo en `profiles.role` obligaría a
-- inventar un rol global que después hay que acotar en cada consulta.

-- ── Enums ───────────────────────────────────────────────────────────────────
-- Exactamente los cuatro resultados del mockup. No hay un quinto, y el enum lo
-- garantiza: si algún día alguien quiere "pendiente", tiene que tocar el tipo y
-- pasar por aquí.
create type public.checkin_result as enum (
  'allowed',        -- entra
  'manual_review',  -- entra, con una comprobación humana
  'already_used',   -- diagnóstico para el supervisor
  'denied'          -- no entra
);

-- El motivo es un enum y no texto libre porque la pantalla traduce cada uno a
-- una instrucción distinta, y porque el peritaje posterior se hace agrupando
-- por esto. Texto libre convierte la bitácora en prosa.
create type public.checkin_reason as enum (
  'ok',
  -- manual_review
  'not_nominated', 'wrong_zone', 'dni_mode',
  -- already_used
  'already_used',
  -- denied
  'qr_unreadable', 'screenshot_suspected', 'wrong_event', 'event_cancelled',
  'ticket_listed', 'ticket_transferred', 'ticket_void', 'ticket_refunded'
);

comment on type public.checkin_reason is
  'screenshot_suspected es MAC valida con slot fuera de la ventana: el token estuvo almacenado (Art. 2.3). Tiene motivo propio, distinto de qr_unreadable, porque es la senal antifraude mas valiosa de la noche.';

-- ── El staff de un evento ───────────────────────────────────────────────────
create table public.event_staff (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events (id)   on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete restrict,

  -- La puerta es texto y no una tabla: es una etiqueta del venue ("Puerta A",
  -- "Acceso VIP"), cambia por evento y no tiene atributos propios. Una tabla
  -- `gates` seria una tabla de una columna.
  gate       text not null check (length(trim(gate)) between 1 and 40),

  -- null = la puerta atiende TODAS las zonas. Con valor, un ticket de otra zona
  -- sale como manual_review/wrong_zone (AC-18) — nunca denegado: puede ser
  -- senalizacion del venue, y el staff esta mejor situado que el sistema.
  zone_id    uuid references public.zones (id) on delete set null,

  -- Art. 8.2: revocar, no borrar. La fila se queda y sus checkins tambien.
  revoked_at timestamptz,
  revoked_by uuid references public.profiles (id),

  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id)
);

-- Una asignacion viva por persona y evento. Parcial, para que revocar y volver
-- a asignar funcione sin borrar el historial.
create unique index event_staff_active_unique
  on public.event_staff (event_id, profile_id) where revoked_at is null;

create index event_staff_profile_idx on public.event_staff (profile_id) where revoked_at is null;
create index event_staff_event_idx   on public.event_staff (event_id, gate);

-- ── La bitácora de puerta ───────────────────────────────────────────────────
-- Art. 8.1: append-only. AC-21: TODO escaneo deja fila, incluidos los denegados
-- y los ilegibles. Un QR invalido es informacion, no ruido: es lo que permite
-- saber, al dia siguiente, que en la Puerta C hubo veinte capturas de pantalla.
create table public.checkins (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events (id) on delete restrict,
  -- null cuando el token no se pudo leer: no hay ticket al que apuntar, pero el
  -- intento se registra igual.
  ticket_id  uuid references public.tickets (id) on delete restrict,

  staff_id       uuid not null references public.profiles (id)    on delete restrict,
  event_staff_id uuid          references public.event_staff (id) on delete restrict,
  gate           text not null,

  result public.checkin_result not null,
  reason public.checkin_reason not null,

  -- AC-24: el token CRUDO, para peritaje. Es lo que permite demostrar meses
  -- despues que el codigo presentado era de un slot de las 21:03.
  scanned_code text,
  -- slot presentado menos slot del servidor. 0 = al dia; ±1 = tolerancia de
  -- reloj; mas = captura. Guardarlo evita recalcularlo desde el token.
  slot_delta   int,
  meta         jsonb,

  created_at timestamptz not null default now()
);

create index checkins_event_gate_idx on public.checkins (event_id, gate, created_at desc);
create index checkins_ticket_idx     on public.checkins (ticket_id, created_at) where ticket_id is not null;
create index checkins_staff_idx      on public.checkins (staff_id, created_at desc);

-- El primer ingreso de un ticket, que es lo que already_used tiene que citar
-- ("entro a las 20:14 por Puerta A"). Parcial: solo los que consumieron.
create index checkins_first_entry_idx
  on public.checkins (ticket_id, created_at)
  where result in ('allowed', 'manual_review');

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.event_staff enable row level security;
alter table public.checkins    enable row level security;

-- El staff ve su propia asignacion; el organizador, las de sus eventos.
create policy event_staff_select on public.event_staff
  for select to authenticated
  using (
    profile_id = (select auth.uid())
    or event_id in (
      select id from public.events
       where organizer_id = any (private.auth_organizer_ids())
    )
    or private.auth_is_admin()
  );

-- El organizador asigna y revoca su propio staff. La revocacion es un UPDATE de
-- revoked_at; borrar no esta permitido (Art. 8.2) y por eso no hay grant de
-- delete mas abajo.
create policy event_staff_insert on public.event_staff
  for insert to authenticated
  with check (
    event_id in (
      select id from public.events
       where organizer_id = any (private.auth_organizer_ids())
    )
    or private.auth_is_admin()
  );

create policy event_staff_update on public.event_staff
  for update to authenticated
  using (
    event_id in (
      select id from public.events
       where organizer_id = any (private.auth_organizer_ids())
    )
    or private.auth_is_admin()
  )
  with check (
    event_id in (
      select id from public.events
       where organizer_id = any (private.auth_organizer_ids())
    )
    or private.auth_is_admin()
  );

revoke insert, update, delete on public.event_staff from authenticated, anon;
grant insert (event_id, profile_id, gate, zone_id) on public.event_staff to authenticated;
-- Solo se puede mover revoked_at/revoked_by (y corregir puerta o zona). Cambiar
-- el evento o la persona de una asignacion ya usada reescribiria el pasado de
-- la bitacora.
grant update (revoked_at, revoked_by, gate, zone_id) on public.event_staff to authenticated;

-- AC-23: el staff lee los checkins de SU puerta en SU evento. Ve los de sus
-- companeros del mismo turno a proposito: en un relevo hay que poder contestar
-- "este ya entro?" sin llamar al que estaba antes.
--
-- AC-04: revocar corta esta lectura en la llamada siguiente, y no borra ni una
-- fila.
create policy checkins_select on public.checkins
  for select to authenticated
  using (
    exists (
      select 1 from public.event_staff es
       where es.event_id   = checkins.event_id
         and es.gate       = checkins.gate
         and es.profile_id = (select auth.uid())
         and es.revoked_at is null
    )
    or private.auth_is_admin()
  );

-- AC-22: Art. 8.1 sin excepciones. Ni el staff, ni el organizador, ni Admin.
-- Solo service_role, desde la Edge Function. Corregir un error de puerta es un
-- asiento nuevo, no una edicion del anterior.
revoke insert, update, delete on public.checkins from authenticated, anon;

comment on table public.checkins is
  'Append-only (Art. 8.1). Ni update ni delete para authenticated en ningun rol. Registra TODO escaneo, incluidos los ilegibles: un QR invalido es informacion.';
comment on table public.event_staff is
  'El staff de puerta es un rol POR EVENTO. Revocar (revoked_at) corta el acceso en la llamada siguiente y no borra ningun checkin — Art. 8.2.';
