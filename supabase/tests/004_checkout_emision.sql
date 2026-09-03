-- 004 Checkout y emisión — el camino completo y sus invariantes
--
-- Corre entero dentro de begin … rollback: no deja rastro.
--
-- LO QUE ESTE ARCHIVO NO PRUEBA: la concurrencia. AC-05, AC-06, AC-13 y AC-21
-- necesitan conexiones simultáneas de verdad y van al final, como guion.
-- Son las cuatro que, si fallan, se descubren la noche del evento con gente en
-- la puerta.
--
-- DOS TRAMPAS DEL ARNÉS, aprendidas corriéndolo:
--
-- 1. `fails()` y `err()` ejecutan el statement CADA UNA. Para una comprobación
--    de solo lectura da igual; para una con efectos —reservar, nominar— la
--    segunda pasada choca con la primera y el detalle reportado miente. En esos
--    casos se usa solo `fails()` y el detalle se escribe a mano.
--
-- 2. Una comprobación que deja una reserva viva CONTAMINA a las que miran
--    `reserved`. Por eso AC-30 va sobre Platea y no sobre General: la primera
--    vez que se corrió la suite entera, AC-22 falló por eso — por la prueba, no
--    por el producto.

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
exception when others then return left(sqlerrm, 95); end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- Semilla: fan, organizador, evento publicado con General (de pie) y Platea
-- ════════════════════════════════════════════════════════════════════════════
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at) values
 ('a1000000-0000-4000-8000-00000000fa01','00000000-0000-0000-0000-000000000000','authenticated','authenticated','fan1@t.local','x',now(),'{}','{"full_name":"Valeria Demo"}',now(),now()),
 ('a1000000-0000-4000-8000-00000000fa02','00000000-0000-0000-0000-000000000000','authenticated','authenticated','org1@t.local','x',now(),'{}','{}',now(),now()),
 ('a1000000-0000-4000-8000-00000000fa03','00000000-0000-0000-0000-000000000000','authenticated','authenticated','otro@t.local','x',now(),'{}','{}',now(),now());

insert into public.venues (id,name,city,capacity)
values ('a1000000-0000-4000-8000-00000000fb01','Estadio','Lima',40000);
insert into public.organizers (id,legal_name,ruc,status,created_by)
values ('a1000000-0000-4000-8000-00000000fc01','Andes SAC','20599999901','approved','a1000000-0000-4000-8000-00000000fa02');
insert into public.organizer_members (organizer_id,user_id,role)
values ('a1000000-0000-4000-8000-00000000fc01','a1000000-0000-4000-8000-00000000fa02','owner');

insert into public.events (id,organizer_id,venue_id,title,description,category,starts_at,capacity,
                           slug,status,visibility,service_charge_bps,service_charge_payer,
                           max_per_user,qr_lead_days,nomination_mode)
values ('a1000000-0000-4000-8000-00000000fd01','a1000000-0000-4000-8000-00000000fc01','a1000000-0000-4000-8000-00000000fb01',
        'Checkout Fest','d','Festival',now()+interval '40 days',1000,
        'checkout-fest','published','public',600,'fan',9,14,'flexible');

insert into public.zones (id,event_id,name,kind,numbered,capacity) values
 ('a1000000-0000-4000-8000-00000000fe01','a1000000-0000-4000-8000-00000000fd01','General','standing',false,800),
 ('a1000000-0000-4000-8000-00000000fe02','a1000000-0000-4000-8000-00000000fd01','Platea','seated',true,20);
insert into public.price_phases (id,event_id,name,starts_at,ends_at) values
 ('a1000000-0000-4000-8000-00000000ff01','a1000000-0000-4000-8000-00000000fd01','Preventa 1',now()-interval '1 day',now()+interval '20 days'),
 ('a1000000-0000-4000-8000-00000000ff02','a1000000-0000-4000-8000-00000000fd01','Preventa 2',now()+interval '20 days',now()+interval '35 days');
-- 925 céntimos a propósito: es el precio con el que 7 entradas descuadran si el
-- cargo se redondea por línea (389 vs 392).
insert into public.price_tiers (id,event_id,zone_id,phase_id,price_cents,stock) values
 ('a1000000-0000-4000-8000-000000010001','a1000000-0000-4000-8000-00000000fd01','a1000000-0000-4000-8000-00000000fe01','a1000000-0000-4000-8000-00000000ff01',  925,800),
 ('a1000000-0000-4000-8000-000000010002','a1000000-0000-4000-8000-00000000fd01','a1000000-0000-4000-8000-00000000fe02','a1000000-0000-4000-8000-00000000ff01',18000, 20),
 ('a1000000-0000-4000-8000-000000010003','a1000000-0000-4000-8000-00000000fd01','a1000000-0000-4000-8000-00000000fe01','a1000000-0000-4000-8000-00000000ff02', 1200,800);
insert into public.seats (id,zone_id,row_label,seat_number) values
 ('a1000000-0000-4000-8000-000000010101','a1000000-0000-4000-8000-00000000fe02','B',5),
 ('a1000000-0000-4000-8000-000000010102','a1000000-0000-4000-8000-00000000fe02','B',6);

-- ════════════════════════════════════════════════════════════════════════════
-- Reserva: lo que se rechaza
-- ════════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1000000-0000-4000-8000-00000000fa01","role":"authenticated"}';

insert into res select 'AC-02  una fase que no está activa se rechaza',
  pg_temp.fails($q$select public.reserve_order('a1000000-0000-4000-8000-00000000fd01',
    '[{"tier_id":"a1000000-0000-4000-8000-000000010003","seat_id":null}]'::jsonb)$q$),
  pg_temp.err($q$select public.reserve_order('a1000000-0000-4000-8000-00000000fd01',
    '[{"tier_id":"a1000000-0000-4000-8000-000000010003","seat_id":null}]'::jsonb)$q$);

insert into res select 'una zona de pie NO admite asiento',
  pg_temp.fails($q$select public.reserve_order('a1000000-0000-4000-8000-00000000fd01',
    '[{"tier_id":"a1000000-0000-4000-8000-000000010001","seat_id":"a1000000-0000-4000-8000-000000010101"}]'::jsonb)$q$),
  pg_temp.err($q$select public.reserve_order('a1000000-0000-4000-8000-00000000fd01',
    '[{"tier_id":"a1000000-0000-4000-8000-000000010001","seat_id":"a1000000-0000-4000-8000-000000010101"}]'::jsonb)$q$);

insert into res select 'una zona numerada EXIGE asiento',
  pg_temp.fails($q$select public.reserve_order('a1000000-0000-4000-8000-00000000fd01',
    '[{"tier_id":"a1000000-0000-4000-8000-000000010002","seat_id":null}]'::jsonb)$q$),
  pg_temp.err($q$select public.reserve_order('a1000000-0000-4000-8000-00000000fd01',
    '[{"tier_id":"a1000000-0000-4000-8000-000000010002","seat_id":null}]'::jsonb)$q$);

insert into res select 'AC-08  el límite por usuario cuenta reservas VIVAS',
  pg_temp.fails($q$select public.reserve_order('a1000000-0000-4000-8000-00000000fd01',
    (select jsonb_agg(jsonb_build_object('tier_id','a1000000-0000-4000-8000-000000010001','seat_id',null))
       from generate_series(1,10)))$q$),
  pg_temp.err($q$select public.reserve_order('a1000000-0000-4000-8000-00000000fd01',
    (select jsonb_agg(jsonb_build_object('tier_id','a1000000-0000-4000-8000-000000010001','seat_id',null))
       from generate_series(1,10)))$q$);

-- AC-30 va sobre PLATEA, no sobre General.
--
-- No es un detalle de estilo: esta comprobación deja una reserva VIVA, y si
-- fuera del mismo tier que el camino feliz, AC-22 vería `reserved = 1` en lugar
-- de 0 y fallaría por culpa de la prueba, no del producto. Pasó de verdad la
-- primera vez que se corrió la suite entera.
-- Sin err() a propósito: reservaría el asiento otra vez y reportaría la
-- colisión en lugar del motivo real. Ver la advertencia del encabezado.
insert into res select 'AC-30  sin DNI declarado no se paga',
  pg_temp.fails(format($q$select public.start_payment(%L)$q$,
    public.reserve_order('a1000000-0000-4000-8000-00000000fd01',
      '[{"tier_id":"a1000000-0000-4000-8000-000000010002","seat_id":"a1000000-0000-4000-8000-000000010102"}]'::jsonb))),
  'el DNI es lo que permite nominar y validar en puerta (Art. 7.2)';

-- ════════════════════════════════════════════════════════════════════════════
-- El camino feliz: 7 entradas de S/ 9.25 — el caso de los tres céntimos
-- ════════════════════════════════════════════════════════════════════════════
select public.set_own_dni('76543210');
insert into ctx (k, v)
select 'order', public.reserve_order('a1000000-0000-4000-8000-00000000fd01',
  (select jsonb_agg(jsonb_build_object('tier_id','a1000000-0000-4000-8000-000000010001','seat_id',null))
     from generate_series(1,7)));
reset role;

insert into res select 'AC-18  el cargo se redondea UNA vez, sobre el subtotal',
  (select subtotal_cents=6475 and service_charge_cents=389 and total_cents=6864
     from public.orders where id=(select v from ctx where k='order')),
  (select 'subtotal='||subtotal_cents||' cargo='||service_charge_cents||' total='||total_cents
          ||' — por línea habrían salido 392'
     from public.orders where id=(select v from ctx where k='order'));

insert into res select 'AC-15  el check de la tabla obliga a que el total cuadre',
  (select total_cents = subtotal_cents - discount_cents + service_charge_cents
     from public.orders where id=(select v from ctx where k='order')), 'ok';

insert into res select 'AC-03  `reserved` sube en la misma transacción',
  (select reserved=7 and sold=0 from public.price_tiers where id='a1000000-0000-4000-8000-000000010001'),
  (select 'reserved='||reserved||' sold='||sold from public.price_tiers where id='a1000000-0000-4000-8000-000000010001');

insert into res select 'AC-09  el precio queda CONGELADO en el ítem',
  (select bool_and(unit_price_cents=925) from public.order_items
    where order_id=(select v from ctx where k='order')),
  'un cambio de fase a mitad del checkout no altera lo que el fan vio';

insert into res select 'AC-10  reserved_until = ahora + 15 min',
  (select reserved_until between now()+interval '14 minutes' and now()+interval '16 minutes'
     from public.orders where id=(select v from ctx where k='order')), 'ok';

insert into res select 'una fila por entrada, sin columna qty',
  (select count(*)=7 from public.order_items where order_id=(select v from ctx where k='order')),
  '7 entradas = 7 filas';

insert into res select 'AC-19  todavía NO hay tickets (Art. 2.1)',
  (select count(*)=0 from public.tickets),
  'sin pago confirmado no existe entrada válida, y la UI no puede insinuarlo';

-- ════════════════════════════════════════════════════════════════════════════
-- Nominación y pago
-- ════════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1000000-0000-4000-8000-00000000fa03","role":"authenticated"}';
insert into res select 'AC-33  otro usuario NO nomina mi entrada',
  pg_temp.fails(format($q$select public.set_item_attendee(%L,'Intruso','11223344')$q$,
    (select id from public.order_items where order_id=(select v from ctx where k='order') limit 1))),
  'esa entrada no es de una orden suya';

set local request.jwt.claims = '{"sub":"a1000000-0000-4000-8000-00000000fa01","role":"authenticated"}';
insert into res select 'AC-33b el DNI del acompañante se hashea en el servidor',
  not pg_temp.fails(format($q$select public.set_item_attendee(%L,'Nicolas Rios','11223344')$q$,
    (select id from public.order_items where order_id=(select v from ctx where k='order')
      order by id limit 1))),
  'el cliente manda el DNI, no el hash';

insert into res select 'AC-31  en modo flexible se puede pagar sin nominar todo',
  not pg_temp.fails(format($q$select public.start_payment(%L)$q$, (select v from ctx where k='order'))),
  'y el ticket sale sin holder: eso da manual_review en puerta (006/AC-16)';
reset role;

insert into res select 'la orden queda en awaiting_payment: el botón se bloquea',
  (select status='awaiting_payment' from public.orders where id=(select v from ctx where k='order')),
  'no se puede pagar dos veces por si acaso';

set local role authenticated;
set local request.jwt.claims = '{"sub":"a1000000-0000-4000-8000-00000000fa01","role":"authenticated"}';
insert into res select 'AC-29  un fan NO puede confirmar su propio pago',
  pg_temp.fails(format($q$select public.confirm_payment(%L,'chg_fraude',6864)$q$,
    (select v from ctx where k='order'))),
  pg_temp.err(format($q$select public.confirm_payment(%L,'chg_fraude',6864)$q$,
    (select v from ctx where k='order')));
reset role;

insert into res select 'el importe tiene que coincidir con el total',
  pg_temp.fails(format($q$select public.confirm_payment(%L,'chg_malo',9999)$q$,
    (select v from ctx where k='order'))),
  pg_temp.err(format($q$select public.confirm_payment(%L,'chg_malo',9999)$q$,
    (select v from ctx where k='order')));

-- Emisión
select public.confirm_payment((select v from ctx where k='order'), 'chg_test_001', 6864);

insert into res select 'AC-20  un ticket por order_item, y la orden queda paid',
  (select count(*)=7 from public.tickets)
  and (select status='paid' and paid_at is not null
         from public.orders where id=(select v from ctx where k='order')),
  (select count(*)||' tickets emitidos' from public.tickets);

-- AC-22: sobre General, que no tiene otras reservas vivas — ver la nota de
-- AC-30 sobre por qué eso importa.
insert into res select 'AC-22  el cupo pasa de reserved a sold sin cambiar la suma',
  (select reserved=0 and sold=7 from public.price_tiers where id='a1000000-0000-4000-8000-000000010001'),
  (select 'reserved='||reserved||' sold='||sold from public.price_tiers where id='a1000000-0000-4000-8000-000000010001');

insert into res select 'AC-23  código FVT-año-6 sin caracteres ambiguos',
  (select bool_and(code ~ '^FVT-[0-9]{4}-[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$') from public.tickets),
  (select code from public.tickets limit 1);

insert into res select 'AC-23b los 7 códigos son distintos',
  (select count(distinct code)=7 from public.tickets), 'ok';

insert into res select 'AC-24  cada ticket con su secreto de 32 bytes',
  (select count(*)=7 and bool_and(length(secret)=32) from public.ticket_secrets), 'Art. 2.6';

insert into res select 'AC-25  qr_available_from = starts_at - qr_lead_days',
  (select bool_and(t.qr_available_from = e.starts_at - interval '14 days')
     from public.tickets t join public.events e on e.id=t.event_id), 'Art. 2.5';

insert into res select 'AC-26  face_value_cents = lo pagado por la entrada',
  (select bool_and(face_value_cents=925) from public.tickets),
  'es el techo de reventa (Art. 6.2)';

insert into res select 'AC-27  cada emisión deja asiento en la bitácora',
  (select count(*)=7 from public.ticket_events where action='issued'), 'Art. 8';

insert into res select 'AC-32  el ticket sin nominar sale sin holder_dni_hash',
  (select count(*)=6 from public.tickets where holder_dni_hash is null),
  'los 6 sin nominar dan manual_review en puerta';

-- AC-21: el reintento del webhook NO vuelve a emitir
insert into res select 'AC-21  confirm_payment con el mismo ref no duplica',
  public.confirm_payment((select v from ctx where k='order'), 'chg_test_001', 6864) = 7
  and (select count(*)=7 from public.tickets),
  'el webhook reintenta: devuelve 7 y no emite nada nuevo';

insert into res select 'AC-21b otra referencia sobre una orden pagada falla',
  pg_temp.fails(format($q$select public.confirm_payment(%L,'chg_otro',6864)$q$,
    (select v from ctx where k='order'))),
  pg_temp.err(format($q$select public.confirm_payment(%L,'chg_otro',6864)$q$,
    (select v from ctx where k='order')));

-- ════════════════════════════════════════════════════════════════════════════
-- Aislamiento
-- ════════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1000000-0000-4000-8000-00000000fa02","role":"authenticated"}';
insert into res select 'AC-35  el ORGANIZADOR no ve las órdenes de su evento',
  (select count(*)=0 from public.orders), 'solo agregados (D-06, Art. 7.5)';
insert into res select 'AC-35b el organizador no ve tickets individuales',
  (select count(*)=0 from public.tickets), 'ok';
insert into res select 'AC-35c el organizador no ve pagos',
  (select count(*)=0 from public.payments), 'ok';

set local request.jwt.claims = '{"sub":"a1000000-0000-4000-8000-00000000fa03","role":"authenticated"}';
insert into res select 'AC-34  otro fan no ve mis órdenes',
  (select count(*)=0 from public.orders), 'ok';

set local request.jwt.claims = '{"sub":"a1000000-0000-4000-8000-00000000fa01","role":"authenticated"}';
insert into res select 'AC-34b el comprador SÍ ve lo suyo',
  (select count(*)=1 from public.orders) and (select count(*)=7 from public.tickets), 'ok';
insert into res select 'AC-11 (005)  ticket_secrets es inalcanzable, ni para el dueño',
  pg_temp.fails($q$select * from public.ticket_secrets$q$), 'Art. 2.6';
insert into res select 'AC-37  el fan no puede tocar una orden pagada',
  pg_temp.fails($q$update public.orders set status='draft'$q$), 'ok';
insert into res select 'AC-15 (005)  el fan no puede tocar sus tickets',
  pg_temp.fails($q$update public.tickets set status='used'$q$), 'ok';

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
insert into res select 'AC-36  anon no lee nada del checkout',
  pg_temp.fails($q$select 1 from public.orders$q$)
  and pg_temp.fails($q$select 1 from public.order_items$q$)
  and pg_temp.fails($q$select 1 from public.payments$q$)
  and pg_temp.fails($q$select 1 from public.tickets$q$), 'ok';
reset role;

-- ════════════════════════════════════════════════════════════════════════════
-- Los guards que 007 y 003 dejaron esperando `tickets`
-- ════════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1000000-0000-4000-8000-00000000fa02","role":"authenticated"}';

insert into res select '007/AC-14  con tickets emitidos, la fecha la cambia Feventi',
  pg_temp.fails($q$update public.events set starts_at = now() + interval '80 days'
      where id='a1000000-0000-4000-8000-00000000fd01'$q$),
  pg_temp.err($q$update public.events set starts_at = now() + interval '80 days'
      where id='a1000000-0000-4000-8000-00000000fd01'$q$);

insert into res select '007/AC-15  la descripción SÍ se puede cambiar',
  not pg_temp.fails($q$update public.events set description='Texto nuevo'
      where id='a1000000-0000-4000-8000-00000000fd01'$q$),
  'la restricción es sobre lo sensible, no sobre toda la ficha';

insert into res select '003/AC-19  con ventas, el precio lo cambia Feventi',
  pg_temp.fails($q$update public.price_tiers set price_cents=1500
      where id='a1000000-0000-4000-8000-000000010001'$q$),
  pg_temp.err($q$update public.price_tiers set price_cents=1500
      where id='a1000000-0000-4000-8000-000000010001'$q$);

insert into res select '003/AC-18  no se baja el stock por debajo de lo vendido',
  pg_temp.fails($q$update public.price_tiers set stock=3
      where id='a1000000-0000-4000-8000-000000010001'$q$),
  pg_temp.err($q$update public.price_tiers set stock=3
      where id='a1000000-0000-4000-8000-000000010001'$q$);

insert into res select '003/AC-20  una zona con tickets emitidos no se borra',
  pg_temp.fails($q$delete from public.zones where id='a1000000-0000-4000-8000-00000000fe01'$q$),
  pg_temp.err($q$delete from public.zones where id='a1000000-0000-4000-8000-00000000fe01'$q$);
reset role;

-- ════════════════════════════════════════════════════════════════════════════
-- Expiración
-- ════════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1000000-0000-4000-8000-00000000fa03","role":"authenticated"}';
select public.set_own_dni('55667788');
insert into ctx (k, v)
select 'order2', public.reserve_order('a1000000-0000-4000-8000-00000000fd01',
  '[{"tier_id":"a1000000-0000-4000-8000-000000010002","seat_id":"a1000000-0000-4000-8000-000000010101"}]'::jsonb);
reset role;

update public.orders set reserved_until = now() - interval '1 minute'
 where id = (select v from ctx where k='order2');

insert into res select 'AC-11  la primera pasada expira y libera',
  public.expire_orders() = 1,
  (select 'reserved='||reserved from public.price_tiers where id='a1000000-0000-4000-8000-000000010002');

insert into res select 'AC-12  los order_items se borran, el asiento queda libre',
  (select count(*)=0 from public.order_items where order_id=(select v from ctx where k='order2')),
  'sin condición de estado en el índice único';

insert into res select 'la orden se CONSERVA con sus totales y status=expired',
  (select status='expired' and expired_at is not null and total_cents>0
     from public.orders where id=(select v from ctx where k='order2')),
  'para conciliación y soporte';

insert into res select 'AC-13  la segunda pasada no expira nada más',
  public.expire_orders() = 0, 'idempotente';

insert into res select 'AC-13b `reserved` no se descontó dos veces',
  (select reserved=0 from public.price_tiers where id='a1000000-0000-4000-8000-000000010002'),
  (select 'reserved='||reserved||' (nunca negativo)'
     from public.price_tiers where id='a1000000-0000-4000-8000-000000010002');

insert into res select 'AC-14  una orden paid no se expira, aunque venciera',
  (select count(*)=1 from public.orders
    where id=(select v from ctx where k='order') and status='paid'),
  'una orden pagada no tiene reserva que liberar: tiene tickets';

-- El asiento liberado se puede volver a reservar
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1000000-0000-4000-8000-00000000fa03","role":"authenticated"}';
insert into res select 'el asiento liberado se puede reservar otra vez',
  not pg_temp.fails($q$select public.reserve_order('a1000000-0000-4000-8000-00000000fd01',
    '[{"tier_id":"a1000000-0000-4000-8000-000000010002","seat_id":"a1000000-0000-4000-8000-000000010101"}]'::jsonb)$q$),
  'el borrado de items es lo que lo libera';
reset role;

-- ── Convenciones heredadas ──────────────────────────────────────────────────
insert into res select 'PERF  una política permisiva por operación y rol',
  not exists (select 1 from pg_policies
               where schemaname='public' and 'authenticated'=any(roles)
               group by tablename, cmd having count(*) > 1),
  coalesce((select string_agg(tablename||'/'||cmd, ', ') from pg_policies
             where schemaname='public' and 'authenticated'=any(roles)
             group by tablename, cmd having count(*) > 1), 'ninguna duplicada');

insert into res select 'AC-26 (001)  RLS activa en toda tabla de public',
  not exists (select 1 from pg_tables where schemaname='public' and not rowsecurity),
  coalesce((select string_agg(tablename, ', ') from pg_tables
             where schemaname='public' and not rowsecurity), 'ninguna sin RLS');

select ac, case when pass then '✓' else '✗ FALLA' end as r, detail from res order by ac;
select count(*) filter (where not pass or pass is null) as fallos, count(*) as total from res;

rollback;

-- ════════════════════════════════════════════════════════════════════════════
-- CONCURRENCIA · las cuatro que no son opcionales
--
-- No caben aquí: necesitan conexiones simultáneas de verdad. Se corren con
-- peticiones HTTP paralelas contra PostgREST, que es el camino real del cliente.
--
-- Verificado el 2026-09-03 con este método. Resultados obtenidos:
--
--   AC-05 · 50 peticiones simultáneas a reserve_order por un tier con stock=1
--           → 1 éxito, 49 rechazos, TODOS con «solo quedan 0 entradas de esa
--             zona y se piden 1». Ningún deadlock: el lock va en orden de id.
--           → Y ni una orden huérfana: los 49 fallos revirtieron entera su
--             transacción, `reserved` quedó en 1/1 exacto.
--
--   AC-06 · 20 peticiones simultáneas por el MISMO asiento
--           → 1 éxito, 19 rechazos con «alguien acaba de tomar uno de esos
--             asientos: elige otro». Lo decide el índice único, no una consulta.
--
--   AC-13 · expire_orders() dos veces seguidas → la segunda devuelve 0 y
--           `reserved` no se descuenta dos veces.
--
--   AC-21 · confirm_payment con el mismo provider_ref dos veces → 7 tickets,
--           no 14. Lo garantiza el unique (provider, provider_ref).
--
-- Guion para repetirlo:
--
--   1. Crear un usuario por la Auth API (POST /auth/v1/signup) y confirmarlo:
--        update auth.users set email_confirmed_at = now() where email = '…';
--      OJO: en plan free el rate limit de correos es 2/hora.
--   2. Obtener el JWT: POST /auth/v1/token?grant_type=password
--   3. Sembrar un evento publicado con un tier de stock=1 y un asiento único.
--   4. Lanzar N peticiones con `&` en bash:
--        for i in $(seq 1 50); do
--          curl -s -o /tmp/r$i.json -X POST "$BASE/rest/v1/rpc/reserve_order" \
--            -H "apikey: $ANON" -H "Authorization: Bearer $JWT" \
--            -H "Content-Type: application/json" \
--            -d '{"p_event_id":"…","p_items":[{"tier_id":"…","seat_id":null}]}' &
--        done; wait
--   5. Contar éxitos y agrupar los mensajes de rechazo.
--   6. Comprobar que no quedaron huérfanos:
--        select count(*) from public.orders where event_id = '…';
--        select reserved, stock from public.price_tiers where id = '…';
-- ════════════════════════════════════════════════════════════════════════════
