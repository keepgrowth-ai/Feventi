-- 007 · T-09 · Art. 4.3 (evidencia) y Art. 8.1 (append-only)

create table public.event_review_notes (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null references public.events (id) on delete cascade,
  actor_id      uuid references public.profiles (id),
  action        public.review_action not null,
  note          text,
  -- El checklist tal como estaba al decidir. Sin esto, "se aprobó con el plano
  -- pendiente" es indemostrable seis meses después.
  checklist_snapshot jsonb,
  status_before public.event_status,
  status_after  public.event_status,
  -- Nota interna de Feventi: el organizador no la ve. Igual que en 009.
  internal      boolean not null default false,
  created_at    timestamptz not null default now()
);

create index event_review_notes_event_idx on public.event_review_notes (event_id, created_at desc);

alter table public.event_review_notes enable row level security;

-- AC-13: el organizador lee las de sus eventos, sin las internas.
create policy event_review_notes_select on public.event_review_notes
  for select to authenticated
  using (
    (
      not internal
      and event_id in (
        select id from public.events
        where organizer_id = any (private.auth_organizer_ids())
      )
    )
    or private.auth_is_admin()
  );

-- AC-11: append-only. Ni update ni delete, para nadie fuera de service_role.
-- Tampoco insert directo: los asientos los escribe private.log_event_review(),
-- que es la única que garantiza que van completos.
revoke insert, update, delete on public.event_review_notes from authenticated, anon;

comment on table public.event_review_notes is
  'Append-only (Art. 8.1). Sin insert directo: solo private.log_event_review(). Corregir es un asiento nuevo, nunca un update.';
