-- Semilla de demo: el evento del mockup, con sus precios y disponibilidades.
--
-- Para qué: poder abrir la pantalla real en `npm run dev` y comparar contra
-- `docs/sources/mockups/`. No es una prueba — las pruebas viven en
-- `supabase/tests/` y no dejan rastro. Esto SÍ deja datos.
--
-- Correr con: mcp__supabase__execute_sql
-- Ver en:     http://localhost:4200/eventos/k-pop-fest-2026
-- Limpiar:    la última sección de este archivo, comentada.
--
-- Reproduce los números del mockup: General S/ 40 → S/ 42.40 con el cargo del
-- 6 %, Platea con sus tres segmentos a 180/150/120 y 3/12/45 disponibles, y VIP
-- agotado en Preventa 1 pero con stock en Preventa 2 — que es el caso del copy
-- «Agotado en Preventa 1 — se libera stock en Preventa 2».
--
-- El usuario se inserta a mano, así que sirve como dueño del organizador pero
-- NO para iniciar sesión: GoTrue es estricto con `auth.identities`. Para probar
-- las pantallas de organizador hace falta un alta por la Auth API.

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at)
values ('d0000000-0000-4000-8000-00000000d001','00000000-0000-0000-0000-000000000000',
        'authenticated','authenticated','demo003@test.local','x',now(),'{}','{}',now(),now())
on conflict (id) do nothing;

insert into public.venues (id, name, city, address, capacity)
values ('d0000000-0000-4000-8000-00000000d002','Estadio Nacional','Lima','Jose Diaz s/n',40000)
on conflict (id) do nothing;

insert into public.organizers (id, legal_name, trade_name, ruc, status, created_by)
values ('d0000000-0000-4000-8000-00000000d003','Andes Live SAC','Andes Live','20501234567',
        'approved','d0000000-0000-4000-8000-00000000d001')
on conflict (id) do nothing;

insert into public.organizer_members (organizer_id, user_id, role)
values ('d0000000-0000-4000-8000-00000000d003','d0000000-0000-4000-8000-00000000d001','owner')
on conflict do nothing;

insert into public.events (id, organizer_id, venue_id, title, description, category,
                           starts_at, doors_at, capacity, slug, status, visibility,
                           service_charge_bps, service_charge_payer, max_per_user,
                           qr_lead_days, nomination_mode)
values ('d0000000-0000-4000-8000-00000000d004','d0000000-0000-4000-8000-00000000d003',
        'd0000000-0000-4000-8000-00000000d002',
        'K-Pop Fest 2026',
        'Dos escenarios, doce artistas y una noche que no se repite.',
        'Festival',
        now() + interval '60 days', now() + interval '60 days' - interval '2 hours',
        1400,'k-pop-fest-2026','published','public',600,'fan',5,14,'flexible')
on conflict (id) do nothing;

-- Las tres zonas del mockup
insert into public.zones (id, event_id, name, kind, numbered, capacity, notes, sort_order) values
 ('d0000000-0000-4000-8000-00000000d101','d0000000-0000-4000-8000-00000000d004','General — de pie','standing',false,800,'Sin numeración',0),
 ('d0000000-0000-4000-8000-00000000d102','d0000000-0000-4000-8000-00000000d004','Platea — butacas','seated',true,200,'Numerada por fila y asiento',1),
 ('d0000000-0000-4000-8000-00000000d103','d0000000-0000-4000-8000-00000000d004','VIP','standing',false,100,'Acceso anticipado',2)
on conflict (id) do nothing;

insert into public.zone_segments (id, zone_id, label, row_from, row_to, sort_order) values
 ('d0000000-0000-4000-8000-00000000d201','d0000000-0000-4000-8000-00000000d102','Filas A–C','A','C',0),
 ('d0000000-0000-4000-8000-00000000d202','d0000000-0000-4000-8000-00000000d102','Filas D–H','D','H',1),
 ('d0000000-0000-4000-8000-00000000d203','d0000000-0000-4000-8000-00000000d102','Filas I–M','I','M',2)
on conflict (id) do nothing;

insert into public.price_phases (id, event_id, name, kind, starts_at, ends_at, sort_order) values
 ('d0000000-0000-4000-8000-00000000d301','d0000000-0000-4000-8000-00000000d004','Preventa 1','presale', now()-interval '5 days', now()+interval '3 days',0),
 ('d0000000-0000-4000-8000-00000000d302','d0000000-0000-4000-8000-00000000d004','Preventa 2','presale', now()+interval '3 days', now()+interval '20 days',1),
 ('d0000000-0000-4000-8000-00000000d303','d0000000-0000-4000-8000-00000000d004','Regular','regular',  now()+interval '20 days', now()+interval '58 days',2)
on conflict (id) do nothing;

-- `sold` se escribe aquí directo porque esto es semilla y corre como postgres.
-- Desde el cliente está revocado: lo mueve la confirmación de pago de 004.
insert into public.price_tiers (event_id, zone_id, segment_id, phase_id, price_cents, stock, sold) values
 ('d0000000-0000-4000-8000-00000000d004','d0000000-0000-4000-8000-00000000d101',null,                                   'd0000000-0000-4000-8000-00000000d301', 4000,800, 62),
 ('d0000000-0000-4000-8000-00000000d004','d0000000-0000-4000-8000-00000000d101',null,                                   'd0000000-0000-4000-8000-00000000d302', 5000,800,  0),
 ('d0000000-0000-4000-8000-00000000d004','d0000000-0000-4000-8000-00000000d102','d0000000-0000-4000-8000-00000000d201','d0000000-0000-4000-8000-00000000d301',18000, 20, 17),
 ('d0000000-0000-4000-8000-00000000d004','d0000000-0000-4000-8000-00000000d102','d0000000-0000-4000-8000-00000000d202','d0000000-0000-4000-8000-00000000d301',15000, 60, 48),
 ('d0000000-0000-4000-8000-00000000d004','d0000000-0000-4000-8000-00000000d102','d0000000-0000-4000-8000-00000000d203','d0000000-0000-4000-8000-00000000d301',12000,120, 75),
 -- VIP: agotado en Preventa 1, con stock en Preventa 2.
 ('d0000000-0000-4000-8000-00000000d004','d0000000-0000-4000-8000-00000000d103',null,                                   'd0000000-0000-4000-8000-00000000d301',30000,  8,  8),
 ('d0000000-0000-4000-8000-00000000d004','d0000000-0000-4000-8000-00000000d103',null,                                   'd0000000-0000-4000-8000-00000000d302',30000,100,  0)
on conflict do nothing;

-- Asientos de Platea, por segmento. 10 filas × 20 = 200, justo su aforo.
--
-- Hay que suplantar al dueño: `generate_seats` comprueba
-- `private.auth_organizer_ids()`, y como `postgres` sin JWT no hay organizador,
-- así que responde «sin permiso sobre esta zona». Es el comportamiento
-- correcto — la semilla se adapta, la función no.
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"d0000000-0000-4000-8000-00000000d001","role":"authenticated"}';
select public.generate_seats('d0000000-0000-4000-8000-00000000d102', array['A','B','C'], 20,
                             'd0000000-0000-4000-8000-00000000d201'),
       public.generate_seats('d0000000-0000-4000-8000-00000000d102', array['D','E','F'], 20,
                             'd0000000-0000-4000-8000-00000000d202'),
       public.generate_seats('d0000000-0000-4000-8000-00000000d102', array['G','H','I','J'], 20,
                             'd0000000-0000-4000-8000-00000000d203');
commit;

-- Comprobación: debe salir «desde S/ 42.40» y 798 disponibles.
select slug, from_price_cents, available_now, sale_open
from public.v_event_public where slug = 'k-pop-fest-2026';

-- ── Limpiar ─────────────────────────────────────────────────────────────────
-- delete from public.events where id = 'd0000000-0000-4000-8000-00000000d004';
-- delete from public.organizers where id = 'd0000000-0000-4000-8000-00000000d003';
-- delete from public.venues where id = 'd0000000-0000-4000-8000-00000000d002';
-- delete from auth.users where id = 'd0000000-0000-4000-8000-00000000d001';
