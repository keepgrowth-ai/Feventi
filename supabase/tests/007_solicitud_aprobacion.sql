-- 007 Solicitud de evento y aprobación — pruebas de política y de transición
--
-- Corre entero dentro de begin … rollback: no deja rastro.
--   mcp__supabase__execute_sql con el contenido de este archivo
--
-- La prueba de concurrencia (T-16) NO está aquí: necesita dos conexiones y va
-- aparte, al final de este archivo como comentario con las instrucciones.

begin;

-- ── Semilla ─────────────────────────────────────────────────────────────────
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at)
values
  ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','fan@test.pe','x',now(),'{}','{"full_name":"Valeria"}',now(),now()),
  ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','orgA@test.pe','x',now(),'{}','{"full_name":"Andes Live"}',now(),now()),
  ('33333333-3333-3333-3333-333333333333','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','admin@test.pe','x',now(),'{}','{"full_name":"Admin"}',now(),now()),
  ('55555555-5555-5555-5555-555555555555','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','orgB@test.pe','x',now(),'{}','{"full_name":"Otra Prod"}',now(),now())
on conflict (id) do nothing;

insert into public.user_roles (user_id, role)
values ('33333333-3333-3333-3333-333333333333','admin') on conflict do nothing;

create or replace function pg_temp.fails(p_sql text) returns boolean
language plpgsql as $$
begin execute p_sql; return false;
exception when others then return true; end $$;

create or replace function pg_temp.err(p_sql text) returns text
language plpgsql as $$
begin execute p_sql; return 'NO FALLÓ';
exception when others then return left(sqlerrm, 75); end $$;

create temp table res(ac text, pass boolean, detail text) on commit drop;
grant insert, select on res to authenticated, anon;

insert into public.venues (name, city, capacity) values ('Estadio Nacional','Lima',40000);

-- Dos organizadores aprobados, para probar aislamiento
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select public.create_organizer('Andes Live SAC','Andes Live','20501234567',null,null);
set local request.jwt.claims = '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}';
select public.create_organizer('Otra Produccion SAC','Otra Prod','20509999999',null,null);
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
select public.approve_organizer(id) from public.organizers order by created_at;

-- ── create_event ────────────────────────────────────────────────────────────
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select public.create_event(
  (select id from public.organizers where ruc='20501234567'), 'K-Pop Fest 2026');

insert into res select 'AC-01  create_event nace en draft',
  (select status = 'draft' from public.events limit 1),
  (select 'status=' || status::text from public.events limit 1);

insert into res select 'AC-02  code correlativo REQ-NNN',
  (select code ~ '^REQ-[0-9]{3}$' from public.events limit 1),
  (select code from public.events limit 1);

-- ── submit: exige campos, y DICE cuáles ─────────────────────────────────────
insert into res select 'AC-03  submit incompleto nombra lo que falta',
  pg_temp.fails($q$select public.submit_event((select id from public.events limit 1))$q$),
  pg_temp.err($q$select public.submit_event((select id from public.events limit 1))$q$);

update public.events set
  description='Festival de K-pop', category='Festival',
  starts_at='2026-08-28 20:00-05', doors_at='2026-08-28 18:00-05',
  venue_id=(select id from public.venues limit 1), capacity=1400,
  slug='k-pop-fest-2026';

insert into res select 'AC-04  submit desde draft funciona',
  not pg_temp.fails($q$select public.submit_event((select id from public.events limit 1))$q$),
  'ok';

insert into res select 'AC-04b submit dos veces falla, y dice el estado actual',
  pg_temp.fails($q$select public.submit_event((select id from public.events limit 1))$q$),
  pg_temp.err($q$select public.submit_event((select id from public.events limit 1))$q$);

-- ── AC-05: el organizador no escribe el estado ──────────────────────────────
insert into res select 'AC-05  organizador NO escribe status',
  pg_temp.fails($q$update public.events set status='published'$q$),
  pg_temp.err($q$update public.events set status='published'$q$);

insert into res select 'AC-05b organizador NO escribe review_checklist',
  pg_temp.fails($q$update public.events set review_checklist='{}'::jsonb$q$),
  pg_temp.err($q$update public.events set review_checklist='{}'::jsonb$q$);

-- ── AC-06 / AC-07: quién decide qué ─────────────────────────────────────────
insert into res select 'AC-06  organizador NO aprueba su propio evento',
  pg_temp.fails($q$select public.approve_event((select id from public.events limit 1))$q$),
  pg_temp.err($q$select public.approve_event((select id from public.events limit 1))$q$);

insert into res select 'AC-07  no se publica desde pending_review',
  pg_temp.fails($q$select public.publish_event((select id from public.events limit 1))$q$),
  pg_temp.err($q$select public.publish_event((select id from public.events limit 1))$q$);

-- ── AC-12: pedir info exige observación ─────────────────────────────────────
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
insert into res select 'AC-12  pedir info sin nota falla',
  pg_temp.fails($q$select public.request_event_info((select id from public.events limit 1), '  ')$q$),
  pg_temp.err($q$select public.request_event_info((select id from public.events limit 1), '  ')$q$);

-- Recorrido completo: info_requested → submit → approve
select public.request_event_info((select id from public.events limit 1),
  'Falta plano del venue y detalle de zonas.',
  '{"datos_generales":"ok","organizador_ruc":"ok","venue_plano":"pending",
    "fechas_funciones":"ok","zonas_fases":"pending","cortesias_bolsas":"na"}'::jsonb);
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select public.submit_event((select id from public.events limit 1));
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
select public.approve_event((select id from public.events limit 1), 'Aprobado con observaciones');

insert into res select 'AC-08  aprobar dos veces falla',
  pg_temp.fails($q$select public.approve_event((select id from public.events limit 1))$q$),
  pg_temp.err($q$select public.approve_event((select id from public.events limit 1))$q$);
reset role;

-- ── AC-10: cada transición deja exactamente un asiento ──────────────────────
insert into res select 'AC-10  una transición = un asiento',
  (select count(*) = 4 from public.event_review_notes),
  (select string_agg(action::text, ' → ' order by created_at) from public.event_review_notes);

insert into res select 'AC-10b el asiento guarda estado antes y después',
  (select bool_and(status_before is not null and status_after is not null)
     from public.event_review_notes),
  (select string_agg(status_before::text || '>' || status_after::text, ', ' order by created_at)
     from public.event_review_notes);

insert into res select 'AC-10c checklist congelado en el momento de decidir',
  (select checklist_snapshot ->> 'venue_plano' = 'pending'
     from public.event_review_notes where action = 'info_requested'),
  'sin snapshot, "se aprobó con el plano pendiente" es indemostrable';

-- ── AC-11: append-only ──────────────────────────────────────────────────────
set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
insert into res select 'AC-11  sin UPDATE en event_review_notes',
  pg_temp.fails($q$update public.event_review_notes set note='alterado'$q$),
  pg_temp.err($q$update public.event_review_notes set note='alterado'$q$);
insert into res select 'AC-11b sin DELETE en event_review_notes',
  pg_temp.fails($q$delete from public.event_review_notes$q$), 'Art. 8.1';
insert into res select 'AC-11c sin INSERT directo (solo log_event_review)',
  pg_temp.fails($q$insert into public.event_review_notes (event_id, action)
      values ((select id from public.events limit 1),'approved')$q$),
  'el asiento se escribe completo o no se escribe';

-- ── AC-13: el organizador lee su historial ──────────────────────────────────
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
insert into res select 'AC-13  organizador lee su historial de decisiones',
  (select count(*) = 4 from public.event_review_notes),
  've ' || (select count(*) from public.event_review_notes)::text || ' asientos';

-- ── AC-07: publicar es del organizador ──────────────────────────────────────
insert into res select 'AC-07b organizador publica desde setup',
  not pg_temp.fails($q$select public.publish_event((select id from public.events limit 1))$q$),
  'Feventi autoriza, el organizador decide cuándo abre la venta';
reset role;
insert into res select 'AC-07c published_at sellado',
  (select status = 'published' and published_at is not null from public.events limit 1),
  (select 'status=' || status::text from public.events limit 1);

-- ── AC-17 / AC-18: aislamiento ──────────────────────────────────────────────
set local role authenticated;
set local request.jwt.claims = '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}';
insert into res select 'AC-17  organizador B no ve el evento de A',
  (select count(*) = 0 from public.events),
  've ' || (select count(*) from public.events)::text || ' eventos';
insert into res select 'AC-17b organizador B no ve la bitácora de A',
  (select count(*) = 0 from public.event_review_notes), 'ok';

set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
insert into res select 'AC-17c un fan no ve ningún evento',
  (select count(*) = 0 from public.events), 'lo público sale de v_event_public (002)';

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
insert into res select 'AC-18  anon no lee events',
  pg_temp.fails($q$select count(*) from public.events$q$),
  pg_temp.err($q$select count(*) from public.events$q$);
insert into res select 'AC-18b anon no lee event_review_notes',
  pg_temp.fails($q$select count(*) from public.event_review_notes$q$), 'ok';
insert into res select 'AC-18c anon no lee venues',
  pg_temp.fails($q$select count(*) from public.venues$q$), 'ok';

-- ── AC-20: pausar detiene la venta, no el acceso ────────────────────────────
set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
insert into res select 'AC-20  Admin pausa un evento publicado',
  not pg_temp.fails($q$select public.pause_event((select id from public.events limit 1),'Revisión de aforo')$q$),
  'los tickets emitidos siguen válidos — lo verifica 006/AC-15';
insert into res select 'AC-20b reanudar vuelve a published',
  not pg_temp.fails($q$select public.resume_event((select id from public.events limit 1))$q$), 'ok';
insert into res select 'AC-06b cancelar sin motivo falla',
  pg_temp.fails($q$select public.cancel_event((select id from public.events limit 1),'')$q$),
  pg_temp.err($q$select public.cancel_event((select id from public.events limit 1),'')$q$);

-- ── Forma del checklist ─────────────────────────────────────────────────────
insert into res select 'T-05  checklist con valor inválido falla',
  pg_temp.fails($q$select public.set_event_checklist(
      (select id from public.events limit 1), '{"datos_generales":"quizas"}'::jsonb)$q$),
  pg_temp.err($q$select public.set_event_checklist(
      (select id from public.events limit 1), '{"datos_generales":"quizas"}'::jsonb)$q$);

-- ── Convención de rendimiento (heredada de 001) ─────────────────────────────
reset role;
insert into res select 'PERF  una sola política permisiva por operación y rol',
  not exists (
    select 1 from pg_policies
     where schemaname = 'public' and 'authenticated' = any (roles)
     group by tablename, cmd having count(*) > 1),
  coalesce((select string_agg(tablename || '/' || cmd, ', ') from pg_policies
             where schemaname = 'public' and 'authenticated' = any (roles)
             group by tablename, cmd having count(*) > 1),
           'ninguna duplicada · ojo: `for all` cuenta como SELECT también');

insert into res select 'AC-26  RLS activa en toda tabla de public',
  not exists (select 1 from pg_tables where schemaname = 'public' and not rowsecurity),
  coalesce((select string_agg(tablename, ', ') from pg_tables
             where schemaname = 'public' and not rowsecurity), 'ninguna sin RLS');

-- ── Resultado ───────────────────────────────────────────────────────────────
select ac, case when pass then '✓' else '✗ FALLA' end as r, detail from res order by ac;
select count(*) filter (where not pass or pass is null) as fallos, count(*) as total from res;

rollback;

-- ════════════════════════════════════════════════════════════════════════════
-- T-16 · Concurrencia: dos Admins aprobando la misma solicitud
--
-- No cabe en este archivo porque necesita DOS conexiones. Se corre lanzando
-- estos dos bloques EN PARALELO (dos llamadas a execute_sql en el mismo
-- mensaje), con un evento en pending_review ya confirmado en la base.
--
-- Resultado esperado: A aprueba; B se BLOQUEA en el lock de A, y al liberarse
-- re-lee el estado, encuentra 'setup' y falla con
--   «solo se aprueba desde pending_review (está en setup)».
-- Al final debe quedar UN asiento, no dos.
--
-- Verificado el 2026-09-03 con este método.
--
-- ── Conexión A ──
--   begin;
--     update public.events set status='pending_review', approved_at=null where id=:ev;
--     delete from public.event_review_notes where event_id=:ev;
--     set local role authenticated;
--     set local request.jwt.claims='{"sub":"<uuid admin>","role":"authenticated"}';
--     select public.approve_event(:ev, 'Admin A');
--     select pg_sleep(6);   -- retiene el lock
--   commit;
--
-- ── Conexión B ──
--   begin;
--     select pg_sleep(2);   -- entra mientras A tiene el lock
--     set local role authenticated;
--     set local request.jwt.claims='{"sub":"<uuid admin>","role":"authenticated"}';
--     select public.approve_event(:ev, 'Admin B');
--   commit;
--
-- ── Comprobación ──
--   select status, (select count(*) from public.event_review_notes where event_id=:ev)
--   from public.events where id=:ev;   -- esperado: setup, 1
-- ════════════════════════════════════════════════════════════════════════════
