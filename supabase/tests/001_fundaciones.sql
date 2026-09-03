-- 001 Fundaciones — pruebas de política
--
-- Corre entero dentro de una transacción que termina en rollback: no deja rastro.
--   mcp__supabase__execute_sql  con el contenido de este archivo
--
-- Cada AC tiene su caso permitido y su caso denegado. Un ✗ es un bug, no un
-- ajuste de la prueba.
--
-- Requiere la semilla de abajo. Los uuid son fijos a propósito para que un fallo
-- se pueda reproducir tal cual.

begin;

-- ── Semilla ─────────────────────────────────────────────────────────────────
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at)
values
  ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','fan@test.pe','x',now(),'{"provider":"email"}',
   '{"full_name":"Valeria Demo"}',now(),now()),
  ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','org@test.pe','x',now(),'{"provider":"email"}',
   '{"full_name":"Andes Live"}',now(),now()),
  ('33333333-3333-3333-3333-333333333333','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','admin@test.pe','x',now(),'{"provider":"email"}',
   '{"full_name":"Admin Feventi"}',now(),now())
on conflict (id) do nothing;

insert into public.user_roles (user_id, role)
values ('33333333-3333-3333-3333-333333333333','admin') on conflict do nothing;

-- ── Utilidades ──────────────────────────────────────────────────────────────
create or replace function pg_temp.fails(p_sql text) returns boolean
language plpgsql as $$
begin execute p_sql; return false;
exception when others then return true; end $$;

create or replace function pg_temp.err(p_sql text) returns text
language plpgsql as $$
begin execute p_sql; return 'NO FALLÓ';
exception when others then return sqlstate || ' ' || left(sqlerrm, 55); end $$;

create temp table res(ac text, pass boolean, detail text) on commit drop;
grant insert, select on res to authenticated, anon;

-- ── Identidad ───────────────────────────────────────────────────────────────
-- AC-01, AC-02: el trigger hace todo el trabajo del registro
insert into res select 'AC-01  registro crea profile',
  (select count(*) from public.profiles
    where id = '11111111-1111-1111-1111-111111111111') = 1
  and (select email from public.profiles
        where id = '11111111-1111-1111-1111-111111111111') = 'fan@test.pe',
  'email copiado de auth.users';

insert into res select 'AC-02  registro asigna rol fan',
  exists (select 1 from public.user_roles
           where user_id = '11111111-1111-1111-1111-111111111111' and role = 'fan'),
  'ok';

-- AC-03: cascada
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at)
values ('99999999-9999-9999-9999-999999999999','00000000-0000-0000-0000-000000000000',
        'authenticated','authenticated','tmp@test.pe','x',now(),'{}','{}',now(),now())
on conflict (id) do nothing;
delete from auth.users where id = '99999999-9999-9999-9999-999999999999';

insert into res select 'AC-03  borrar usuario borra profile en cascada',
  not exists (select 1 from public.profiles
               where id = '99999999-9999-9999-9999-999999999999'), 'ok';

-- AC-14: los helpers de rol están bien declarados
insert into res select 'AC-14  helpers security definer + stable + search_path',
  (select count(*) = 4 from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname in ('auth_has_role','auth_is_admin','auth_organizer_ids','auth_owns_organizer')
      and p.prosecdef and p.provolatile = 's'
      and array_to_string(p.proconfig, ',') like 'search_path=%'),
  'los 4 helpers, en el schema private que PostgREST no expone';

-- AC-26: RLS en toda tabla de public
insert into res select 'AC-26  RLS activa en toda tabla de public',
  not exists (select 1 from pg_tables
               where schemaname = 'public' and not rowsecurity),
  coalesce((select string_agg(tablename, ', ') from pg_tables
             where schemaname = 'public' and not rowsecurity), 'ninguna sin RLS');

-- Una sola política de SELECT por tabla y rol. Dos permisivas se evalúan las
-- DOS en cada consulta, y el helper de Admin se ejecutaría también para los
-- fans, que son el tráfico. Los casos se unen con OR dentro de una política.
insert into res select 'PERF   una sola política SELECT por tabla',
  not exists (
    select 1 from pg_policies
     where schemaname = 'public' and cmd = 'SELECT' and 'authenticated' = any (roles)
     group by tablename having count(*) > 1),
  coalesce((select string_agg(tablename || ' (' || count(*) || ')', ', ')
              from pg_policies
             where schemaname = 'public' and cmd = 'SELECT'
               and 'authenticated' = any (roles)
             group by tablename having count(*) > 1),
           'ninguna tabla con políticas duplicadas');

-- ── Como fan ────────────────────────────────────────────────────────────────
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

insert into res select 'AC-04  el fan ve una fila de profiles, la suya',
  (select count(*) from public.profiles) = 1
  and (select id from public.profiles) = '11111111-1111-1111-1111-111111111111',
  'visibles: ' || (select count(*) from public.profiles)::text;

insert into res select 'AC-05  el fan edita sus campos permitidos',
  not pg_temp.fails($q$update public.profiles
        set full_name = 'Valeria Demo Ríos', phone = '+51999888777', ninja_mode = true
      where id = '11111111-1111-1111-1111-111111111111'$q$), 'ok';

insert into res select 'AC-06  el fan NO escribe en profile_identity',
  pg_temp.fails($q$insert into public.profile_identity (user_id, dni_hash)
        values ('11111111-1111-1111-1111-111111111111','robado')$q$),
  pg_temp.err($q$insert into public.profile_identity (user_id, dni_hash)
        values ('11111111-1111-1111-1111-111111111111','robado')$q$);

insert into res select 'AC-07  el fan NO sella su verificación',
  pg_temp.fails($q$update public.profiles set dni_verified_at = now()
      where id = '11111111-1111-1111-1111-111111111111'$q$),
  pg_temp.err($q$update public.profiles set dni_verified_at = now()
      where id = '11111111-1111-1111-1111-111111111111'$q$);

insert into res select 'AC-07b verify_dni rechaza a un fan',
  pg_temp.fails($q$select public.verify_dni('11111111-1111-1111-1111-111111111111')$q$),
  pg_temp.err($q$select public.verify_dni('11111111-1111-1111-1111-111111111111')$q$);

insert into res select 'AC-08d hash_dni no es invocable por el cliente',
  pg_temp.fails($q$select private.hash_dni('76543210')$q$),
  pg_temp.err($q$select private.hash_dni('76543210')$q$);

insert into res select 'AC-08e DNI mal formado se rechaza',
  pg_temp.fails($q$select public.set_own_dni('123')$q$),
  pg_temp.err($q$select public.set_own_dni('123')$q$);

insert into res select 'AC-10  profile_identity es inalcanzable (Art. 2.6)',
  pg_temp.fails($q$select * from public.profile_identity$q$),
  pg_temp.err($q$select * from public.profile_identity$q$);

insert into res select 'AC-10b select * en profiles funciona',
  not pg_temp.fails($q$select * from public.profiles$q$),
  'sin columna oculta que rompa el select de PostgREST';

insert into res select 'AC-11  el fan NO se hace admin',
  pg_temp.fails($q$insert into public.user_roles (user_id, role)
        values ('11111111-1111-1111-1111-111111111111','admin')$q$),
  pg_temp.err($q$insert into public.user_roles (user_id, role)
        values ('11111111-1111-1111-1111-111111111111','admin')$q$);

insert into res select 'AC-12  el fan NO actualiza su rol',
  pg_temp.fails($q$update public.user_roles set role = 'admin'
      where user_id = '11111111-1111-1111-1111-111111111111'$q$),
  pg_temp.err($q$update public.user_roles set role = 'admin'
      where user_id = '11111111-1111-1111-1111-111111111111'$q$);

insert into res select 'AC-13  auth_is_admin() false para fan',
  private.auth_is_admin() = false, 'auth_is_admin=' || private.auth_is_admin()::text;

insert into res select 'AC-15  sin recursión en user_roles',
  (select count(*) from public.user_roles) = 1,
  'filas visibles: ' || (select count(*) from public.user_roles)::text;

insert into res select 'AC-23  el fan NO cambia el status de un organizador',
  pg_temp.fails($q$update public.organizers set status = 'approved'$q$),
  pg_temp.err($q$update public.organizers set status = 'approved'$q$);

insert into res select 'AC-25  sin DELETE en organizer_members (Art. 8.2)',
  pg_temp.fails($q$delete from public.organizer_members$q$),
  pg_temp.err($q$delete from public.organizer_members$q$);

-- ── DNI: determinista y con pepper ──────────────────────────────────────────
select public.set_own_dni('76543210');
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select public.set_own_dni('76543210');
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
select public.set_own_dni('11223344');
reset role;

insert into res select 'AC-08  hash ≠ sha256 desnudo (lleva pepper)',
  (select dni_hash <> encode(extensions.digest('76543210','sha256'),'hex')
     from public.profile_identity where user_id = '11111111-1111-1111-1111-111111111111'),
  'sin pepper, 10^8 DNIs se rompen en segundos';

insert into res select 'AC-08c last4 visible en profiles',
  (select dni_last4 = '3210' from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'),
  'last4 = ' || (select coalesce(dni_last4,'∅') from public.profiles
                  where id = '11111111-1111-1111-1111-111111111111');

insert into res select 'AC-09  mismo DNI → mismo hash (nominación y modo DNI)',
  (select count(distinct dni_hash) = 1 from public.profile_identity
    where user_id in ('11111111-1111-1111-1111-111111111111',
                      '22222222-2222-2222-2222-222222222222')), 'ok';

insert into res select 'AC-09b DNI distinto → hash distinto',
  (select count(distinct dni_hash) = 2 from public.profile_identity), 'ok';

-- ── Tenencia ────────────────────────────────────────────────────────────────
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select public.create_organizer('Andes Live SAC','Andes Live','20501234567','ops@andes.pe',null);

insert into res select 'AC-16  organizador nace en pending, con owner',
  (select o.status = 'pending' and m.role = 'owner'
     from public.organizers o join public.organizer_members m on m.organizer_id = o.id
    where m.user_id = '22222222-2222-2222-2222-222222222222'),
  (select 'status=' || o.status::text || ' role=' || m.role::text
     from public.organizers o join public.organizer_members m on m.organizer_id = o.id
    where m.user_id = '22222222-2222-2222-2222-222222222222');

insert into res select 'AC-16b rol organizer añadido a user_roles',
  exists (select 1 from public.user_roles
           where user_id = '22222222-2222-2222-2222-222222222222' and role = 'organizer'), 'ok';

insert into res select 'AC-17  insert directo en organizers bloqueado',
  pg_temp.fails($q$insert into public.organizers (legal_name, status)
        values ('Trampa','approved')$q$),
  pg_temp.err($q$insert into public.organizers (legal_name, status)
        values ('Trampa','approved')$q$);

insert into res select 'AC-18  el owner lee su organizador',
  (select count(*) from public.organizers) = 1,
  'visibles: ' || (select count(*) from public.organizers)::text;

insert into res select 'AC-22a el owner aparece en auth_organizer_ids',
  array_length(private.auth_organizer_ids(), 1) = 1, 'ok';

select public.add_organizer_member(
  (select id from public.organizers limit 1),
  '11111111-1111-1111-1111-111111111111','viewer');

set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
insert into res select 'AC-20b el viewer añadido ve el organizador',
  (select count(*) from public.organizers) = 1, 'ok';

insert into res select 'AC-24a el fan NO aprueba organizadores',
  pg_temp.fails($q$select public.approve_organizer(
      (select id from public.organizers order by created_at limit 1))$q$),
  pg_temp.err($q$select public.approve_organizer(
      (select id from public.organizers order by created_at limit 1))$q$);

-- AC-21, AC-22: revocar corta el acceso sin borrar la fila
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select public.revoke_organizer_member(
  (select id from public.organizers limit 1),'11111111-1111-1111-1111-111111111111');
reset role;

insert into res select 'AC-21  revocar NO borra la fila (Art. 8.2)',
  (select revoked_at is not null from public.organizer_members
    where user_id = '11111111-1111-1111-1111-111111111111'),
  'la fila sigue, con revoked_at sellado';

set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
insert into res select 'AC-22  el revocado sale de auth_organizer_ids',
  coalesce(array_length(private.auth_organizer_ids(), 1), 0) = 0, 'ok';
insert into res select 'AC-22b el revocado deja de ver el organizador',
  (select count(*) from public.organizers) = 0,
  've ' || (select count(*) from public.organizers)::text;

-- AC-19: aislamiento entre organizadores
insert into res select 'AC-19  aislamiento entre organizadores',
  (select count(*) from public.organizers) = 0, 'ok';

insert into res select 'AC-20  ajeno NO añade miembros',
  pg_temp.fails($q$select public.add_organizer_member(
      (select id from public.organizers order by created_at limit 1),
      '11111111-1111-1111-1111-111111111111','admin')$q$),
  pg_temp.err($q$select public.add_organizer_member(
      (select id from public.organizers order by created_at limit 1),
      '11111111-1111-1111-1111-111111111111','admin')$q$);

-- ── Como admin ──────────────────────────────────────────────────────────────
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
insert into res select 'AC-13b auth_is_admin() true para admin',
  private.auth_is_admin(), 'ok';
insert into res select 'AC-24c Admin ve todos los organizadores',
  (select count(*) from public.organizers) = 1, 'ok';
select public.approve_organizer((select id from public.organizers limit 1));
reset role;

-- Comprobación en un statement aparte: dentro de un mismo SELECT, las
-- subconsultas ven el snapshot anterior a la función y el AC parecería fallar.
insert into res select 'AC-24  Admin aprueba y queda sellado (Art. 4.3)',
  (select status = 'approved' and approved_at is not null
       and approved_by = '33333333-3333-3333-3333-333333333333'
     from public.organizers limit 1),
  (select 'status=' || status::text || ' approved_by=' || left(approved_by::text,8)
     from public.organizers limit 1);

-- ── Como anon ───────────────────────────────────────────────────────────────
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
insert into res
select 'AC-28  anon ' || tbl, denied, res_txt from (
  select 'profiles' as tbl,
         pg_temp.fails($q$select count(*) from public.profiles$q$) as denied,
         pg_temp.err($q$select count(*) from public.profiles$q$)  as res_txt
  union all select 'user_roles',
         pg_temp.fails($q$select count(*) from public.user_roles$q$),
         pg_temp.err($q$select count(*) from public.user_roles$q$)
  union all select 'organizers',
         pg_temp.fails($q$select count(*) from public.organizers$q$),
         pg_temp.err($q$select count(*) from public.organizers$q$)
  union all select 'organizer_members',
         pg_temp.fails($q$select count(*) from public.organizer_members$q$),
         pg_temp.err($q$select count(*) from public.organizer_members$q$)
  -- TRUNCATE no está sujeto a RLS: si el grant existe, anon vacía la tabla.
  union all select 'TRUNCATE organizers',
         pg_temp.fails($q$truncate public.organizers cascade$q$),
         pg_temp.err($q$truncate public.organizers cascade$q$)
) q;
reset role;

-- ── Resultado ───────────────────────────────────────────────────────────────
select ac,
       case when pass then '✓' else '✗ FALLA' end as r,
       detail
from res order by ac;

select count(*) filter (where not pass or pass is null) as fallos,
       count(*) as total
from res;

rollback;
