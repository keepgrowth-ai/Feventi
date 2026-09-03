-- 007 · T-03 … T-08
--
-- UNA tabla cubre solicitud y evento. "Solicitudes" es esta tabla filtrada por
-- status. Dos tablas obligarían a duplicar cada columna y a mantener una copia
-- que se desincroniza. Ver plan.md.

create sequence public.event_code_seq;

create table public.events (
  id            uuid primary key default gen_random_uuid(),
  -- AC-02: legible, para dictar por teléfono a soporte. Con secuencia hay
  -- huecos si una transacción falla, y da igual; lo que no puede es repetirse.
  code          text unique not null
                  default 'REQ-' || lpad(nextval('public.event_code_seq')::text, 3, '0'),
  organizer_id  uuid not null references public.organizers (id) on delete restrict,
  venue_id      uuid references public.venues (id) on delete restrict,
  slug          text unique,

  title          text,
  description    text,
  category       text,
  hero_image_url text,

  starts_at     timestamptz,
  doors_at      timestamptz,
  timezone      text not null default 'America/Lima',

  status        public.event_status     not null default 'draft',
  visibility    public.event_visibility not null default 'public',
  capacity      int check (capacity is null or capacity > 0),

  -- Reglas comerciales. Art. 5 y 11; valores por defecto del mockup.
  max_per_user          int     not null default 5    check (max_per_user > 0),
  resale_enabled        boolean not null default true,
  max_resales           int     not null default 2    check (max_resales >= 0),
  resale_commission_bps int     not null default 1000 check (resale_commission_bps between 0 and 10000),
  service_charge_bps    int     not null default 600  check (service_charge_bps between 0 and 10000),
  service_charge_payer  public.charge_payer    not null default 'fan',
  qr_lead_days          int     not null default 14   check (qr_lead_days >= 0),
  nomination_mode       public.nomination_mode not null default 'flexible',

  -- Fase 2 lo convierte en payouts/payout_tranches con movimientos reales.
  -- Aquí es la política declarada, que el dashboard muestra como estimación.
  payout_policy jsonb not null default
    '[{"pct":30,"trigger":"cierre de preventa"},
      {"pct":40,"trigger":"48 h post-evento"},
      {"pct":30,"trigger":"cierre de incidencias"}]'::jsonb,

  review_checklist jsonb not null default
    '{"datos_generales":"pending","organizador_ruc":"pending","venue_plano":"pending",
      "fechas_funciones":"pending","zonas_fases":"pending","cortesias_bolsas":"pending"}'::jsonb,

  -- D-01: sin algoritmo de destacados. Lo pone Admin a mano.
  featured_at   timestamptz,

  submitted_at  timestamptz,
  approved_at   timestamptz,
  published_at  timestamptz,
  paused_at     timestamptz,
  cancelled_at  timestamptz,

  created_by    uuid references public.profiles (id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- T-05: seis claves fijas, tres valores. Un jsonb libre se vuelve vertedero.
  --
  -- El `?&` no es redundante: un CHECK se cumple cuando la expresión da NULL, y
  -- `->>` de una clave ausente da NULL, así que sin él un checklist incompleto
  -- pasaría. Presencia con `?&`, valores con los `in`.
  -- Sin subconsulta: CHECK no las admite (0A000).
  constraint events_checklist_shape check (
    review_checklist ?& array['datos_generales','organizador_ruc','venue_plano',
                              'fechas_funciones','zonas_fases','cortesias_bolsas']
    and review_checklist ->> 'datos_generales'  in ('ok','pending','na')
    and review_checklist ->> 'organizador_ruc'  in ('ok','pending','na')
    and review_checklist ->> 'venue_plano'      in ('ok','pending','na')
    and review_checklist ->> 'fechas_funciones' in ('ok','pending','na')
    and review_checklist ->> 'zonas_fases'      in ('ok','pending','na')
    and review_checklist ->> 'cortesias_bolsas' in ('ok','pending','na')
  ),
  -- Las puertas no abren después de que el evento empieza.
  constraint events_doors_before_start check (
    doors_at is null or starts_at is null or doors_at <= starts_at
  )
);

-- T-06
create index events_organizer_status_idx on public.events (organizer_id, status);
-- El de abajo lo necesita el catálogo de 002.
create index events_public_idx on public.events (status, visibility, starts_at)
  where status = 'published';
create index events_venue_idx on public.events (venue_id);

create trigger events_touch_updated_at
  before update on public.events
  for each row execute function public.touch_updated_at();

alter table public.events enable row level security;

-- T-07 · AC-17, AC-18. Convención de 001: una política, casos con OR, caso
-- común primero. anon NO lee events: lo público sale de v_event_public (002).
create policy events_select on public.events
  for select to authenticated
  using (
    organizer_id = any (private.auth_organizer_ids())
    or private.auth_is_admin()
  );

create policy events_update_member on public.events
  for update to authenticated
  using (
    organizer_id = any (private.auth_organizer_ids())
    or private.auth_is_admin()
  )
  with check (
    organizer_id = any (private.auth_organizer_ids())
    or private.auth_is_admin()
  );

-- T-08 · AC-05: el organizador edita la ficha, nunca el estado.
-- status, code, organizer_id, review_checklist y los sellos de tiempo quedan
-- FUERA del grant: solo se mueven por las RPC de 0016.
revoke insert, update, delete on public.events from authenticated, anon;
grant update (
  title, description, category, hero_image_url, slug,
  starts_at, doors_at, timezone, venue_id, capacity,
  max_per_user, resale_enabled, max_resales, resale_commission_bps,
  service_charge_bps, service_charge_payer, qr_lead_days, nomination_mode
) on public.events to authenticated;

comment on column public.events.status is
  'Solo published habilita venta (Art. 4). Fuera del grant del organizador: se mueve únicamente por las RPC de transición.';
comment on column public.events.review_checklist is
  'Del Admin, no del organizador. Él lo lee para saber qué le falta; escribirlo está fuera de su grant.';
