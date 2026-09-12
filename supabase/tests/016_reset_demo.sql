-- 0064 reset_demo — el guardarraíl de una función que BORRA
--
-- Corre entero dentro de begin … rollback: no deja rastro.
--   mcp__supabase__execute_sql  con el contenido de este archivo
--
-- Lo que esta suite protege no es que la función reinicie bien —eso se ve a
-- simple vista en la pantalla— sino que **no la pueda llamar nadie más**. Es
-- una función que borra órdenes, tickets y checkins: el día que alguien le
-- quite el `auth_is_admin()` por error, esto es lo único que lo dice.
--
-- Bloque de identificadores de esta suite: `b6400000-0000-4000-8000-…`,
-- RUC `20564000001`.

begin;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at)
values
 ('b6400000-0000-4000-8000-0000000000f1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','fan064@t.local','x',now(),'{}','{"full_name":"Fan Cualquiera"}',now(),now()),
 ('b6400000-0000-4000-8000-0000000000f2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','adm064@t.local','x',now(),'{}','{"full_name":"Admin Prueba"}',now(),now())
on conflict (id) do nothing;

insert into public.user_roles (user_id, role)
values ('b6400000-0000-4000-8000-0000000000f2','admin') on conflict do nothing;

-- El evento AJENO, con su compra pagada. Se siembra AQUÍ, antes de ponerse
-- ningún rol: `authenticated` no tiene insert en `organizers` ni en `orders`, y
-- sembrarlo desde una sesión de fan solo probaría que el revoke funciona. Es la
-- misma trampa del arnés que mordió en 012.
insert into public.venues (id,name,city,capacity)
values ('b6400000-0000-4000-8000-0000000000b1','Local Ajeno','Lima',900);
insert into public.organizers (id, legal_name, ruc, status, created_by)
values ('b6400000-0000-4000-8000-0000000000c1','Ajeno SAC','20564000001','approved','b6400000-0000-4000-8000-0000000000f2');
insert into public.events (id, organizer_id, venue_id, title, slug, status, visibility, starts_at, capacity, nomination_mode)
values ('b6400000-0000-4000-8000-0000000000e1','b6400000-0000-4000-8000-0000000000c1','b6400000-0000-4000-8000-0000000000b1',
        'Evento ajeno','ev-ajeno-64','published','public', now()+interval '20 days',900,'flexible');
insert into public.zones (id, event_id, name, kind, numbered, capacity)
values ('b6400000-0000-4000-8000-0000000000a1','b6400000-0000-4000-8000-0000000000e1','General','standing',false,900);
insert into public.price_phases (id, event_id, name, kind, starts_at, ends_at)
values ('b6400000-0000-4000-8000-0000000000d1','b6400000-0000-4000-8000-0000000000e1','Única','regular',now()-interval '1 day',now()+interval '10 days');
insert into public.price_tiers (id, event_id, zone_id, phase_id, price_cents, stock, sold)
values ('b6400000-0000-4000-8000-0000000000c2','b6400000-0000-4000-8000-0000000000e1','b6400000-0000-4000-8000-0000000000a1','b6400000-0000-4000-8000-0000000000d1',5000,100,1);
insert into public.orders (id, event_id, buyer_id, status, subtotal_cents, service_charge_cents, total_cents, paid_at)
values ('b6400000-0000-4000-8000-00000000d001','b6400000-0000-4000-8000-0000000000e1','b6400000-0000-4000-8000-0000000000f1','paid',5000,300,5300,now());
insert into public.order_items (id, order_id, price_tier_id, unit_price_cents)
values ('b6400000-0000-4000-8000-00000000e001','b6400000-0000-4000-8000-00000000d001','b6400000-0000-4000-8000-0000000000c2',5000);
insert into public.tickets (id, code, event_id, order_item_id, zone_id, owner_id, original_owner_id, status, face_value_cents)
values ('b6400000-0000-4000-8000-000000009001','FVT-064-AJENO','b6400000-0000-4000-8000-0000000000e1','b6400000-0000-4000-8000-00000000e001','b6400000-0000-4000-8000-0000000000a1','b6400000-0000-4000-8000-0000000000f1','b6400000-0000-4000-8000-0000000000f1','active',5000);


create or replace function pg_temp.fails(p_sql text) returns boolean
language plpgsql as $$
begin execute p_sql; return false;
exception when others then return true; end $$;

create or replace function pg_temp.err(p_sql text) returns text
language plpgsql as $$
begin execute p_sql; return 'NO FALLÓ';
exception when others then return sqlstate || ' ' || left(sqlerrm, 70); end $$;

create temp table res(ac text, pass boolean, detail text) on commit drop;
grant insert, select on res to authenticated, anon;

-- ═══════════════════════════════════════════════════════════════════════════
-- Cierre 1 · solo Admin
-- ═══════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"b6400000-0000-4000-8000-0000000000f1","role":"authenticated"}';

insert into res select 'AC-01  un fan cualquiera NO puede reiniciar',
  pg_temp.fails($q$select public.reset_demo()$q$),
  pg_temp.err($q$select public.reset_demo()$q$);

-- AC-02 · el camino feliz, que es lo que da sentido al de arriba. Comprobar
-- que algo falla no es comprobar por qué: sin esta mitad, AC-01 daría verde
-- aunque la función estuviera rota del todo.
set local request.jwt.claims = '{"sub":"b6400000-0000-4000-8000-0000000000f2","role":"authenticated"}';

insert into res select 'AC-02  un Admin SÍ puede',
  not pg_temp.fails($q$select public.reset_demo()$q$),
  'sin esta mitad, AC-01 no prueba nada';

insert into res select 'AC-02b el estado que devuelve es el del guion',
  (select (public.reset_demo() ->> 'puntos_de_camila')::int) = 150
  and (select (public.reset_demo() ->> 'entradas_de_camila')::int) = 2
  and (select (public.reset_demo() ->> 'solicitudes_pendientes')::int) = 1,
  '150 puntos, 2 entradas, 1 solicitud sin responder';

insert into res select 'AC-02c deja la ventana de puerta ABIERTA',
  (public.reset_demo() -> 'puerta_abierta')::boolean,
  'sin esto el escáner no funciona en la toma siguiente';

-- ═══════════════════════════════════════════════════════════════════════════
-- Cierre 2 · solo toca la utilería, no la base
-- ═══════════════════════════════════════════════════════════════════════════
-- El evento ajeno ya está sembrado arriba, antes de ponerse ningún rol: la
-- comprobación aquí es solo que siguió intacto.
select public.reset_demo();

reset role;
insert into res select 'AC-03  no toca eventos que no son la demo',
  exists (select 1 from public.orders  where id = 'b6400000-0000-4000-8000-00000000d001')
  and exists (select 1 from public.tickets where id = 'b6400000-0000-4000-8000-000000009001')
  and (select sold from public.price_tiers where id = 'b6400000-0000-4000-8000-0000000000c2') = 1,
  'la orden, el ticket y el contador del evento ajeno siguen intactos';

-- ═══════════════════════════════════════════════════════════════════════════
-- Cierre 3 · se apaga sola con el primer cobro real
-- ═══════════════════════════════════════════════════════════════════════════
-- Es el único de los tres que no depende de que nadie se acuerde de nada.
insert into public.payments (order_id, provider, provider_ref, status, amount_cents, currency)
values ('b6400000-0000-4000-8000-00000000d001','culqi','chg_real_0001','succeeded',5300,'PEN');

set local role authenticated;
set local request.jwt.claims = '{"sub":"b6400000-0000-4000-8000-0000000000f2","role":"authenticated"}';

insert into res select 'AC-04  con un pago REAL en la base, ni Admin puede',
  pg_temp.fails($q$select public.reset_demo()$q$),
  pg_temp.err($q$select public.reset_demo()$q$);

-- ═══════════════════════════════════════════════════════════════════════════
-- La superficie
-- ═══════════════════════════════════════════════════════════════════════════
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

insert into res select 'AC-05  anon no puede ni llamarla',
  pg_temp.fails($q$select public.reset_demo()$q$),
  'permission denied: el revoke de PUBLIC está puesto (lección de 0055)';

-- ── Resultado ───────────────────────────────────────────────────────────────
reset role;

select ac, case when pass then '✓' else '✗ FALLA' end as r, detail
from res order by ac;

select count(*) filter (where not pass or pass is null) as fallos,
       count(*) as total
from res;

rollback;
