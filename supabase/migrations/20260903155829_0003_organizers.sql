-- 001 Fundaciones · T-07
-- Multi-tenencia. Un usuario puede pertenecer a varios organizadores.
--
-- Va ANTES de los helpers de rol a propósito: auth_organizer_ids() es
-- `language sql` y Postgres valida su cuerpo al crearla, así que necesita que
-- organizer_members ya exista.

create table public.organizers (
  id            uuid primary key default gen_random_uuid(),
  legal_name    text not null,
  trade_name    text,
  ruc           text unique,
  status        public.organizer_status not null default 'pending',
  contact_email text,
  contact_phone text,
  -- D-26: sin fórmula todavía. La columna existe y queda en null.
  reputation    int,
  created_by    uuid references public.profiles (id),
  -- Art. 4.3: evidencia de la aprobación.
  approved_at   timestamptz,
  approved_by   uuid references public.profiles (id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index organizers_created_by_idx on public.organizers (created_by);
create index organizers_status_idx     on public.organizers (status);

create trigger organizers_touch_updated_at
  before update on public.organizers
  for each row execute function public.touch_updated_at();

create table public.organizer_members (
  organizer_id uuid not null references public.organizers (id) on delete cascade,
  user_id      uuid not null references public.profiles (id)   on delete cascade,
  role         public.organizer_role not null default 'viewer',
  invited_by   uuid references public.profiles (id),
  -- Art. 8.2: se revoca, no se borra. El historial de acciones sobrevive.
  revoked_at   timestamptz,
  created_at   timestamptz not null default now(),
  primary key (organizer_id, user_id)
);

create index organizer_members_user_idx
  on public.organizer_members (user_id) where revoked_at is null;

comment on column public.organizer_members.revoked_at is
  'Art. 8.2: retirar acceso no borra historial. No hay DELETE para authenticated.';

alter table public.organizers        enable row level security;
alter table public.organizer_members enable row level security;

-- El cliente no inserta ni actualiza en directo: todo pasa por las RPC de 0005,
-- porque el status lo fija el servidor (AC-17) y crear un organizador son dos
-- filas que van juntas (AC-16).
revoke insert, update, delete on public.organizers        from authenticated, anon;
revoke insert, update, delete on public.organizer_members from authenticated, anon;
