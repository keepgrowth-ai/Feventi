-- 009 Soporte contextual — el contexto, la doble vía y las notas internas
--
-- Corre entero dentro de begin … rollback: no deja rastro.
--
-- TRAMPA DEL ARNÉS, encontrada aquí y que vale para toda la suite:
--
--   insert into res select ...,
--     (select corrects_id from public.ticket_events
--       where id = public.admin_ticket_action(...)) = ...
--
-- Eso NO funciona. La función escribe una fila en `ticket_events` y la consulta
-- que la envuelve ya fijó su snapshot sobre esa misma tabla: la fila recién
-- insertada no es visible para el `where` que la busca. Devuelve nulo y la
-- comprobación falla — por la prueba, no por el producto.
--
-- La forma correcta es la de abajo: llamar a la función en un statement, guardar
-- el id, y comprobar en el siguiente. Vale para cualquier función que escriba en
-- la tabla que la propia consulta lee.

begin;

create temp table res(ac text, pass boolean, detail text) on commit drop;
create temp table ctx(k text primary key, v uuid) on commit drop;
grant insert, select on res to authenticated, anon;
grant insert, select on ctx to authenticated, anon;

create or replace function pg_temp.fails(p_sql text) returns boolean
language plpgsql as $$
begin execute p_sql; return false;
exception when others then return true; end $$;

create or replace function pg_temp.err(p_sql text) returns text
language plpgsql as $$
begin execute p_sql; return 'NO FALLÓ';
exception when others then return left(sqlerrm, 110); end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- Semilla: un fan con dos entradas —una suya y una de otro—, staff, organizador
-- y Admin. Los cinco papeles que abren o leen casos.
-- ════════════════════════════════════════════════════════════════════════════
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
 ('a9000000-0000-4000-8000-0000000000f1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','fan9@t.local','x',now(),'{}','{"full_name":"Ana Fan"}',now(),now()),
 ('a9000000-0000-4000-8000-0000000000f2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','otro9@t.local','x',now(),'{}','{"full_name":"Otro Fan"}',now(),now()),
 ('a9000000-0000-4000-8000-0000000000f3','00000000-0000-0000-0000-000000000000','authenticated','authenticated','org9@t.local','x',now(),'{}','{}',now(),now()),
 ('a9000000-0000-4000-8000-0000000000f4','00000000-0000-0000-0000-000000000000','authenticated','authenticated','staff9@t.local','x',now(),'{}','{}',now(),now()),
 ('a9000000-0000-4000-8000-0000000000f5','00000000-0000-0000-0000-000000000000','authenticated','authenticated','admin9@t.local','x',now(),'{}','{}',now(),now());

insert into public.user_roles (user_id, role) values ('a9000000-0000-4000-8000-0000000000f5','admin');

insert into public.venues (id,name,city,capacity) values ('a9000000-0000-4000-8000-0000000000b1','Coliseo','Lima',5000);
insert into public.organizers (id, legal_name, trade_name, ruc, status, created_by)
values ('a9000000-0000-4000-8000-0000000000c1','N SAC','N','20599999999','approved','a9000000-0000-4000-8000-0000000000f3');
insert into public.organizer_members (organizer_id, user_id, role)
values ('a9000000-0000-4000-8000-0000000000c1','a9000000-0000-4000-8000-0000000000f3','owner');

insert into public.events (id, organizer_id, venue_id, title, slug, status, visibility, starts_at, doors_at, capacity)
values ('a9000000-0000-4000-8000-0000000000e1','a9000000-0000-4000-8000-0000000000c1','a9000000-0000-4000-8000-0000000000b1','Evento 9','ev9','published','public',now()+interval '5 days',now()+interval '5 days'-interval '2 hours',500);

insert into public.zones (id, event_id, name, kind, numbered, capacity)
values ('a9000000-0000-4000-8000-0000000000a1','a9000000-0000-4000-8000-0000000000e1','General','standing',false,500);
insert into public.price_phases (id, event_id, name, kind, starts_at, ends_at)
values ('a9000000-0000-4000-8000-0000000000d1','a9000000-0000-4000-8000-0000000000e1','Unica','regular',now()-interval '5 days',now()+interval '4 days');
insert into public.price_tiers (id, event_id, zone_id, phase_id, price_cents, stock, sold)
values ('a9000000-0000-4000-8000-0000000000c2','a9000000-0000-4000-8000-0000000000e1','a9000000-0000-4000-8000-0000000000a1','a9000000-0000-4000-8000-0000000000d1',10000,500,2);

-- Las dos entradas salen de la MISMA orden, comprada por el fan 1. Es lo que
-- hace interesante el caso del staff: el ticket es del fan 2, pero el pedido
-- pertenece al fan 1.
insert into public.orders (id, event_id, buyer_id, status, subtotal_cents, service_charge_cents, total_cents, paid_at)
values ('a9000000-0000-4000-8000-0000000000d2','a9000000-0000-4000-8000-0000000000e1','a9000000-0000-4000-8000-0000000000f1','paid',20000,1200,21200,now());

insert into public.order_items (id, order_id, price_tier_id, unit_price_cents) values
 ('a9000000-0000-4000-8000-0000000000d3','a9000000-0000-4000-8000-0000000000d2','a9000000-0000-4000-8000-0000000000c2',10000),
 ('a9000000-0000-4000-8000-0000000000d4','a9000000-0000-4000-8000-0000000000d2','a9000000-0000-4000-8000-0000000000c2',10000);

insert into public.tickets (id, code, event_id, order_item_id, zone_id, owner_id, original_owner_id, status, face_value_cents) values
 ('a9000000-0000-4000-8000-0000000000e5','FVT-9-000001','a9000000-0000-4000-8000-0000000000e1','a9000000-0000-4000-8000-0000000000d3','a9000000-0000-4000-8000-0000000000a1','a9000000-0000-4000-8000-0000000000f1','a9000000-0000-4000-8000-0000000000f1','active',10000),
 ('a9000000-0000-4000-8000-0000000000e6','FVT-9-000002','a9000000-0000-4000-8000-0000000000e1','a9000000-0000-4000-8000-0000000000d4','a9000000-0000-4000-8000-0000000000a1','a9000000-0000-4000-8000-0000000000f2','a9000000-0000-4000-8000-0000000000f2','active',10000);

insert into public.event_staff (id, event_id, profile_id, gate)
values ('a9000000-0000-4000-8000-0000000000e7','a9000000-0000-4000-8000-0000000000e1','a9000000-0000-4000-8000-0000000000f4','Puerta A');

-- ════════════════════════════════════════════════════════════════════════════
-- El fan abre un caso desde su entrada
-- ════════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"a9000000-0000-4000-8000-0000000000f1","role":"authenticated"}';

insert into ctx select 'caso1', public.open_support_case(
  'ticket','No me carga el QR','Abro la app y el QR se queda girando desde ayer.',
  'a9000000-0000-4000-8000-0000000000e5');

-- AC-03: el cliente mandó SOLO el ticket. Si mandara el evento y la orden,
-- podría adjuntar los de otro y ensuciar la cola de un organizador ajeno.
insert into res select 'AC-03 el servidor rellena evento y orden desde el ticket',
  event_id = 'a9000000-0000-4000-8000-0000000000e1' and order_id = 'a9000000-0000-4000-8000-0000000000d2',
  'el cliente solo mandó el ticket_id'
  from public.support_cases where id = (select v from ctx where k='caso1');

insert into res select 'AC-20 el caso trae un código legible y único',
  code ~ '^#\d+$', code from public.support_cases where id = (select v from ctx where k='caso1');

insert into res select 'AC-01 un caso de tipo qr SIN ticket falla',
  pg_temp.fails($x$select public.open_support_case('qr','Sin contexto','texto suficientemente largo')$x$),
  'lo impide el CHECK, no la aplicación';

insert into res select 'AC-02 un caso de tipo refund SIN orden falla',
  pg_temp.fails($x$select public.open_support_case('refund','Sin contexto','texto suficientemente largo')$x$), 'ídem';

insert into res select 'AC-05 un caso sobre un ticket AJENO falla',
  pg_temp.fails($x$select public.open_support_case('ticket','Ajeno','texto suficientemente largo','a9000000-0000-4000-8000-0000000000e6')$x$),
  'el ticket es del otro fan';

-- Lo que de verdad importa de AC-05: los dos mensajes tienen que ser IGUALES.
-- Si difirieran, la función sería un oráculo para saber si un código es real.
insert into res select 'AC-05b y el mensaje NO revela si el ticket existe',
  pg_temp.err($x$select public.open_support_case('ticket','X','texto suficientemente largo','11111111-2222-4333-8444-555555555555')$x$)
  = pg_temp.err($x$select public.open_support_case('ticket','X','texto suficientemente largo','a9000000-0000-4000-8000-0000000000e6')$x$),
  'mismo mensaje exista o no';

-- ── D-12 · no se abren dos vías de recuperación sobre el mismo pago ─────────
insert into ctx select 'refund', public.open_support_case(
  'refund','Quiero el reembolso','No voy a poder asistir y pido la devolución.',
  null,'a9000000-0000-4000-8000-0000000000d2');

insert into res select 'AC-06 con un refund abierto, otro sobre el mismo pedido falla',
  pg_temp.fails($x$select public.open_support_case('cancellation','Otra vía','texto suficientemente largo',null,'a9000000-0000-4000-8000-0000000000d2')$x$),
  'índice único parcial, no un if: dos peticiones a la vez pasarían las dos';

-- «duplicate key value violates unique constraint» no le dice a nadie que ya
-- tiene un caso abierto. El mensaje trae el código para poder ir a él.
insert into res select 'AC-06b y el mensaje apunta al caso que ya existe',
  pg_temp.err($x$select public.open_support_case('refund','Otro','texto suficientemente largo',null,'a9000000-0000-4000-8000-0000000000d2')$x$) like '%#%',
  left(pg_temp.err($x$select public.open_support_case('refund','Otro','texto suficientemente largo',null,'a9000000-0000-4000-8000-0000000000d2')$x$), 78);

insert into res select 'AC-15 el fan no puede tocar estado ni prioridad',
  pg_temp.fails($x$update public.support_cases set priority = 'urgent'$x$), 'sin grant de update';

insert into res select 'AC-16 el fan no puede escribir una nota interna',
  pg_temp.fails($x$select public.post_support_message((select v from ctx where k='caso1'),'nota mía',true)$x$),
  'solo Feventi';

insert into res select 'AC-17 el fan no puede insertar mensajes a mano',
  pg_temp.fails($x$insert into public.support_messages (case_id, body) values ((select v from ctx where k='caso1'),'a mano')$x$),
  'append-only, y el append va por RPC';

select public.post_support_message((select v from ctx where k='caso1'), 'Adjunto que ya reinstalé la app.');
reset role;

-- ════════════════════════════════════════════════════════════════════════════
-- Admin gestiona y actúa
-- ════════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"a9000000-0000-4000-8000-0000000000f5","role":"authenticated"}';

insert into res select 'AC-13 Admin ve todos los casos',
  (select count(*) from public.v_support_queue) = 2, (select count(*)::text from public.v_support_queue) || ' casos';

select public.manage_support_case((select v from ctx where k='caso1'), 'in_progress'::public.support_status,
                                  'high'::public.support_priority, 'a9000000-0000-4000-8000-0000000000f5',
                                  'Reproducido: el ticket no tenía secreto emitido.');

insert into res select 'AC-15b Admin sí mueve estado, prioridad y asignación',
  status = 'in_progress' and priority = 'high' and assigned_to = 'a9000000-0000-4000-8000-0000000000f5',
  status::text || ' / ' || priority::text
  from public.support_cases where id = (select v from ctx where k='caso1');

insert into res select 'AC-16b la nota de Admin queda como interna',
  count(*) = 1, count(*)::text || ' nota'
  from public.support_messages where case_id = (select v from ctx where k='caso1') and internal;

-- Cada acción en su propio statement: ver la trampa del arnés arriba.
insert into ctx select 'accion', public.admin_ticket_action(
  (select v from ctx where k='caso1'),'a9000000-0000-4000-8000-0000000000e5','voided','Reemitida por incidencia');

insert into res select 'AC-19 la acción de Admin deja asiento con actor y case_id',
  actor_id = 'a9000000-0000-4000-8000-0000000000f5' and (meta->>'case_id')::uuid = (select v from ctx where k='caso1'),
  action::text || ' con case_id en meta'
  from public.ticket_events where id = (select v from ctx where k='accion');

insert into res select 'AC-19b y el ticket cambia de estado',
  status = 'void', status::text from public.tickets where id = 'a9000000-0000-4000-8000-0000000000e5';

insert into ctx select 'correccion', public.admin_ticket_action(
  (select v from ctx where k='caso1'),'a9000000-0000-4000-8000-0000000000e5','corrected','Me equivoqué de entrada',
  (select v from ctx where k='accion'));

-- Art. 8.3: corregir NO es editar el asiento viejo. Es uno nuevo que lo apunta,
-- y el viejo sigue ahí — por eso se comprueban los dos.
insert into res select 'AC-19c corregir es un asiento NUEVO que apunta al anterior',
  (select corrects_id from public.ticket_events where id = (select v from ctx where k='correccion'))
    = (select v from ctx where k='accion'),
  'Art. 8.3';

insert into res select 'AC-19d y el asiento corregido sigue existiendo',
  (select count(*) from public.ticket_events where ticket_id = 'a9000000-0000-4000-8000-0000000000e5') = 2,
  'dos asientos, ninguno borrado';

select public.manage_support_case((select v from ctx where k='caso1'), 'resolved'::public.support_status);

insert into res select 'AC-18 cerrar sella resolved_at',
  resolved_at is not null, to_char(resolved_at,'HH24:MI:SS')
  from public.support_cases where id = (select v from ctx where k='caso1');

insert into res select 'AC-18b y no borra ni un mensaje',
  count(*) = 2, count(*)::text || ' mensajes'
  from public.support_messages where case_id = (select v from ctx where k='caso1');

select public.manage_support_case((select v from ctx where k='refund'), 'closed'::public.support_status);
reset role;

-- ════════════════════════════════════════════════════════════════════════════
-- De vuelta al fan
-- ════════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"a9000000-0000-4000-8000-0000000000f1","role":"authenticated"}';

insert into res select 'AC-07 cerrado el primero, se puede abrir otro',
  not pg_temp.fails($x$select public.open_support_case('cancellation','El evento se cae','El organizador anunció que no se hace.',null,'a9000000-0000-4000-8000-0000000000d2')$x$),
  'el índice es parcial: solo cuenta lo abierto';

insert into res select 'AC-09 el fan ve sus casos',
  (select count(*) from public.v_support_queue) = 3, (select count(*)::text from public.v_support_queue) || ' casos';

-- No se confía en que el front no la pinte: es RLS.
insert into res select 'AC-10 el fan NO ve la nota interna',
  (select count(*) from public.support_messages where internal) = 0, 'cero internas';

insert into res select 'AC-08 abrir un refund no mueve ni un céntimo',
  (select count(*) from public.payments) = 0 and
  (select total_cents from public.orders where id = 'a9000000-0000-4000-8000-0000000000d2') = 21200,
  'la orden sigue en 212.00';
reset role;

-- ════════════════════════════════════════════════════════════════════════════
-- Los demás papeles
-- ════════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"a9000000-0000-4000-8000-0000000000f2","role":"authenticated"}';
insert into res select 'un fan ajeno no ve los casos de otro',
  (select count(*) from public.v_support_queue) = 0, 'cero';
insert into res select 'AC-04 un pedido MANDADO por el cliente sí se autoriza: el de otro falla',
  pg_temp.fails($x$select public.open_support_case('payment','X','texto suficientemente largo',null,'a9000000-0000-4000-8000-0000000000d2')$x$),
  'el pedido es del otro fan';
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a9000000-0000-4000-8000-0000000000f3","role":"authenticated"}';
insert into res select 'AC-11 el organizador ve los casos de su evento',
  (select count(*) from public.v_support_queue) = 3, (select count(*)::text from public.v_support_queue) || ' casos';
insert into res select 'AC-11b pero NO sabe quién los abrió (D-06)',
  (select bool_and(opened_by_label = 'un asistente') from public.v_support_queue), 'sin nombre del comprador';
insert into res select 'AC-11c ni ve las notas internas',
  (select count(*) from public.support_messages where internal) = 0, 'cero';
reset role;

-- El caso del staff: el ticket es de otro fan y el pedido es de un tercero. Es
-- la historia 4 del spec, y la que destapó el bug corregido en 0051.
set local role authenticated;
set local request.jwt.claims = '{"sub":"a9000000-0000-4000-8000-0000000000f4","role":"authenticated"}';
insert into ctx select 'staff', public.open_support_case(
  'qr','QR rechazado en puerta','Una asistente muestra un QR y sale denegado por captura. Pide excepción.',
  'a9000000-0000-4000-8000-0000000000e6');
insert into res select 'AC-04b el staff abre un caso sobre un ticket de SU evento, aunque el pedido no sea suyo',
  (select count(*) from public.support_cases where opened_by = 'a9000000-0000-4000-8000-0000000000f4') = 1, 'uno';
insert into res select 'AC-12 y solo ve el que él abrió',
  (select count(*) from public.v_support_queue) = 1, (select count(*)::text from public.v_support_queue);
reset role;

-- AC-14: `anon` ni siquiera llega a evaluar la política. 0009 le quitó el
-- `select` por defecto, así que falla antes con «permission denied» — que es
-- mejor que devolver cero filas.
insert into res select 'AC-14 anon ni siquiera puede CONSULTAR la tabla',
  pg_temp.fails($x$set local role anon; select count(*) from public.support_cases$x$),
  'permission denied, no «cero filas»';

-- ════════════════════════════════════════════════════════════════════════════
select case when pass then '✓' else '✗ FALLA' end as ok, ac, detail from res order by ctid;
select count(*) filter (where pass) || '/' || count(*) || ' en verde' as resultado from res;

rollback;
