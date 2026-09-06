-- 010 Grafo social — pruebas de política
--
-- Corre entero dentro de begin … rollback: no deja rastro.
--   mcp__supabase__execute_sql  con el contenido de este archivo
--
-- Bloque de identificadores de esta suite: `b0000000…`. La base tiene datos
-- permanentes (la semilla de demo), así que nada aquí asume una base vacía.
--
-- AC-06 NO está aquí: dos llamadas en la misma sesión se serializan solas y el
-- test pasaría por la razón equivocada. Vive en `010_concurrencia.mjs`.

begin;

-- ── Semilla · cuatro fans ───────────────────────────────────────────────────
-- A y B serán amigos. C es ajeno (AC-07). N acabará en modo ninja (AC-12/13).
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at)
values
  ('b0000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','a010@test.pe','x',now(),'{"provider":"email"}',
   '{"full_name":"Ana Diez"}',now(),now()),
  ('b0000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','b010@test.pe','x',now(),'{"provider":"email"}',
   '{"full_name":"Bruno Paz"}',now(),now()),
  ('b0000000-0000-0000-0000-00000000000c','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','c010@test.pe','x',now(),'{"provider":"email"}',
   '{"full_name":"Carla Ruiz"}',now(),now()),
  ('b0000000-0000-0000-0000-00000000000e','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','n010@test.pe','x',now(),'{"provider":"email"}',
   '{"full_name":"Nadia Soto"}',now(),now())
on conflict (id) do nothing;

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

-- ═══════════════════════════════════════════════════════════════════════════
-- Pedir amistad
-- ═══════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"b0000000-0000-0000-0000-00000000000a","role":"authenticated"}';

-- AC-01 · A pide a B por correo exacto
select public.request_friendship('b010@test.pe');

insert into res select 'AC-01  pedir por correo exacto crea arista pending',
  exists (select 1 from public.friend_edges
           where requester_id = 'b0000000-0000-0000-0000-00000000000a'
             and addressee_id = 'b0000000-0000-0000-0000-00000000000b'
             and status = 'pending'
             and responded_at is null),
  'pending y sin responded_at';

-- AC-02 · el mensaje del correo inexistente es IDÉNTICO al de «ya existe».
-- Si no lo fuera, el formulario sería un oráculo de «¿está registrado?».
--
-- `err()` ejecuta el statement: aquí no importa, los dos fallan sin efecto.
insert into res select 'AC-02  correo inexistente y relación repetida dicen lo mismo',
  pg_temp.err($q$select public.request_friendship('nadie-en-absoluto@test.pe')$q$)
  = pg_temp.err($q$select public.request_friendship('b010@test.pe')$q$),
  pg_temp.err($q$select public.request_friendship('nadie-en-absoluto@test.pe')$q$);

-- AC-03 · pedirse a uno mismo
insert into res select 'AC-03  pedirse amistad a uno mismo falla',
  pg_temp.fails($q$select public.request_friendship('a010@test.pe')$q$),
  'mismo mensaje que los demás fallos';

-- AC-04 · el árbitro. B intenta pedir a A cuando ya existe A→B.
set local request.jwt.claims = '{"sub":"b0000000-0000-0000-0000-00000000000b","role":"authenticated"}';

insert into res select 'AC-04  arista inversa bloqueada por friend_edges_one_per_pair',
  pg_temp.fails($q$select public.request_friendship('a010@test.pe')$q$)
  and (select count(*) from public.friend_edges
        where least(requester_id, addressee_id) = 'b0000000-0000-0000-0000-00000000000a'
          and greatest(requester_id, addressee_id) = 'b0000000-0000-0000-0000-00000000000b') = 1,
  'una sola arista entre los dos';

-- ═══════════════════════════════════════════════════════════════════════════
-- Responder
-- ═══════════════════════════════════════════════════════════════════════════

-- AC-05a · el camino feliz PRIMERO. Comprobar que algo falla no es comprobar
-- por qué falla: sin esta mitad, AC-05b daría verde aunque la RPC estuviera
-- rota del todo.
--
-- A intenta aceptar su propia solicitud → debe fallar. Se comprueba antes de
-- que B la acepte, porque después el motivo sería «ya_respondida».
set local request.jwt.claims = '{"sub":"b0000000-0000-0000-0000-00000000000a","role":"authenticated"}';

insert into res select 'AC-05a quien pide no puede aceptar su propia solicitud',
  pg_temp.fails(format($q$select public.respond_friendship(%L, true)$q$,
    (select id from public.friend_edges
      where requester_id = 'b0000000-0000-0000-0000-00000000000a'
        and addressee_id = 'b0000000-0000-0000-0000-00000000000b'))),
  'no_autorizado';

-- AC-05b · B sí puede
set local request.jwt.claims = '{"sub":"b0000000-0000-0000-0000-00000000000b","role":"authenticated"}';

select public.respond_friendship(
  (select id from public.friend_edges
    where requester_id = 'b0000000-0000-0000-0000-00000000000a'
      and addressee_id = 'b0000000-0000-0000-0000-00000000000b'), true);

insert into res select 'AC-05b el destinatario acepta y queda accepted con hora',
  exists (select 1 from public.friend_edges
           where requester_id = 'b0000000-0000-0000-0000-00000000000a'
             and addressee_id = 'b0000000-0000-0000-0000-00000000000b'
             and status = 'accepted'
             and responded_at is not null),
  'la constraint accepted_has_time obliga a las dos cosas a la vez';

-- AC-05c · responder dos veces
insert into res select 'AC-05c responder una arista ya aceptada falla',
  pg_temp.fails(format($q$select public.respond_friendship(%L, true)$q$,
    (select id from public.friend_edges
      where requester_id = 'b0000000-0000-0000-0000-00000000000a'
        and addressee_id = 'b0000000-0000-0000-0000-00000000000b'))),
  'ya_respondida — el guardarraíl que AC-06 prueba en concurrencia';

-- ═══════════════════════════════════════════════════════════════════════════
-- Visibilidad
-- ═══════════════════════════════════════════════════════════════════════════

-- AC-07 · C, ajeno, no ve la arista A↔B
set local request.jwt.claims = '{"sub":"b0000000-0000-0000-0000-00000000000c","role":"authenticated"}';

insert into res select 'AC-07  un tercero no ve la arista ajena',
  (select count(*) from public.friend_edges
    where least(requester_id, addressee_id) = 'b0000000-0000-0000-0000-00000000000a'
      and greatest(requester_id, addressee_id) = 'b0000000-0000-0000-0000-00000000000b') = 0,
  'RLS: cero filas, no error';

-- AC-07b · y A sí la ve. El camino feliz de la misma política.
set local request.jwt.claims = '{"sub":"b0000000-0000-0000-0000-00000000000a","role":"authenticated"}';

insert into res select 'AC-07b A sí ve su propia arista',
  (select count(*) from public.friend_edges
    where addressee_id = 'b0000000-0000-0000-0000-00000000000b') = 1,
  'la política deja pasar al implicado';

-- AC-07c · v_my_friends devuelve a B para A, con nombre
insert into res select 'AC-07c v_my_friends resuelve el otro extremo de la arista',
  (select friend_id from public.v_my_friends
    where friend_id = 'b0000000-0000-0000-0000-00000000000b')
    = 'b0000000-0000-0000-0000-00000000000b'
  and (select full_name from public.v_my_friends
        where friend_id = 'b0000000-0000-0000-0000-00000000000b') = 'Bruno Paz',
  'da igual quién pidió: la amistad es simétrica (D-39)';

-- AC-07d · la vista es `security definer` (0054) y eso APAGA la RLS de
-- friend_edges. El filtro por auth.uid() esta escrito a mano en el `where`;
-- esta comprobacion es la que dice si sigue ahi. Sin ella, un `where` mal
-- editado convierte la vista en el grafo social entero de la plataforma.
set local request.jwt.claims = '{"sub":"b0000000-0000-0000-0000-00000000000c","role":"authenticated"}';

insert into res select 'AC-07d v_my_friends no filtra el grafo ajeno (vista definer)',
  (select count(*) from public.v_my_friends) = 0,
  'C no es amigo de nadie: cero filas, aunque la RLS este apagada dentro';

-- AC-08 · simetría del helper
reset role;

insert into res select 'AC-08  are_friends(A,B) = are_friends(B,A)',
  private.are_friends('b0000000-0000-0000-0000-00000000000a',
                      'b0000000-0000-0000-0000-00000000000b')
  = private.are_friends('b0000000-0000-0000-0000-00000000000b',
                        'b0000000-0000-0000-0000-00000000000a')
  and private.are_friends('b0000000-0000-0000-0000-00000000000a',
                          'b0000000-0000-0000-0000-00000000000b'),
  'y las dos son ciertas, no las dos falsas';

-- ═══════════════════════════════════════════════════════════════════════════
-- Bloqueo
-- ═══════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"b0000000-0000-0000-0000-00000000000a","role":"authenticated"}';

select public.block_user('b0000000-0000-0000-0000-00000000000b');

-- AC-09 · el bloqueo rompe la amistad a efectos de visibilidad, sin borrarla
reset role;

insert into res select 'AC-09  bloquear pone are_friends en falso sin borrar la arista',
  not private.are_friends('b0000000-0000-0000-0000-00000000000a',
                          'b0000000-0000-0000-0000-00000000000b')
  and exists (select 1 from public.friend_edges
               where requester_id = 'b0000000-0000-0000-0000-00000000000a'
                 and addressee_id = 'b0000000-0000-0000-0000-00000000000b'
                 and status = 'accepted'),
  'la arista sigue ahí: bloquear y dejar de ser amigos son cosas distintas';

-- AC-10 · el bloqueado no puede saberlo
set local role authenticated;
set local request.jwt.claims = '{"sub":"b0000000-0000-0000-0000-00000000000b","role":"authenticated"}';

insert into res select 'AC-10  el bloqueado no ve la fila que lo bloquea',
  (select count(*) from public.blocks
    where blocked_id = 'b0000000-0000-0000-0000-00000000000b') = 0,
  'un bloqueo detectable no protege de nada';

-- AC-10d · y tampoco lo ve como amigo. Esta rama NO funcionaba con
-- `security_invoker`: la RLS de `blocks` escondia la fila «p me bloqueo a mi»,
-- asi que quien me hubiera bloqueado seguia saliendo en mi lista. La vista
-- definer de 0054 la arregla de paso.
insert into res select 'AC-10d el bloqueado tampoco ve al bloqueador entre sus amigos',
  (select count(*) from public.v_my_friends
    where friend_id = 'b0000000-0000-0000-0000-00000000000a') = 0,
  'con security_invoker esta rama nunca casaba';

-- AC-10b · y el bloqueador sí la ve
set local request.jwt.claims = '{"sub":"b0000000-0000-0000-0000-00000000000a","role":"authenticated"}';

insert into res select 'AC-10b el bloqueador sí ve su propio bloqueo',
  (select count(*) from public.blocks
    where blocked_id = 'b0000000-0000-0000-0000-00000000000b') = 1,
  'para poder desbloquear desde /perfil';

-- AC-10c · v_my_friends esconde al bloqueado
insert into res select 'AC-10c v_my_friends excluye a quien bloqueé',
  (select count(*) from public.v_my_friends
    where friend_id = 'b0000000-0000-0000-0000-00000000000b') = 0,
  'la vista aplica el bloqueo, no solo el helper';

-- AC-11 · el bloqueo sobrevive a dejar de ser amigos
delete from public.friend_edges
 where requester_id = 'b0000000-0000-0000-0000-00000000000a'
   and addressee_id = 'b0000000-0000-0000-0000-00000000000b';

insert into res select 'AC-11  el bloqueo sobrevive al borrado de la amistad',
  (select count(*) from public.blocks
    where blocker_id = 'b0000000-0000-0000-0000-00000000000a'
      and blocked_id = 'b0000000-0000-0000-0000-00000000000b') = 1
  and not exists (select 1 from public.friend_edges
                   where requester_id = 'b0000000-0000-0000-0000-00000000000a'
                     and addressee_id = 'b0000000-0000-0000-0000-00000000000b'),
  'esta es la razón de que blocks sea tabla aparte';

-- AC-11b · dejar de ser amigos borró de verdad (no es append-only)
insert into res select 'AC-11b dejar de ser amigos borra la fila',
  (select count(*) from public.friend_edges
    where least(requester_id, addressee_id) = 'b0000000-0000-0000-0000-00000000000a'
      and greatest(requester_id, addressee_id) = 'b0000000-0000-0000-0000-00000000000b') = 0,
  'el Art. 8 no lista amistades entre lo auditado';

-- ═══════════════════════════════════════════════════════════════════════════
-- Modo ninja · D-43
-- ═══════════════════════════════════════════════════════════════════════════
-- A y N se hacen amigos.
set local request.jwt.claims = '{"sub":"b0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select public.request_friendship('n010@test.pe');

set local request.jwt.claims = '{"sub":"b0000000-0000-0000-0000-00000000000e","role":"authenticated"}';
select public.respond_friendship(
  (select id from public.friend_edges
    where requester_id = 'b0000000-0000-0000-0000-00000000000a'
      and addressee_id = 'b0000000-0000-0000-0000-00000000000e'), true);

-- AC-12a · el camino feliz ANTES de encender ninja
reset role;

insert into res select 'AC-12a sin ninja, A ve la actividad de N',
  private.can_see_activity_of('b0000000-0000-0000-0000-00000000000a',
                              'b0000000-0000-0000-0000-00000000000e'),
  'sin esta mitad, AC-12b daría verde aunque la función devolviera false siempre';

-- N enciende ninja, desde su propia sesión: es una columna suya.
set local role authenticated;
set local request.jwt.claims = '{"sub":"b0000000-0000-0000-0000-00000000000e","role":"authenticated"}';
update public.profiles set ninja_mode = true
 where id = 'b0000000-0000-0000-0000-00000000000e';

-- AC-13c · la otra mitad de D-43, del lado de la pantalla: activar ninja no
-- vacia tu propia lista de amigos.
insert into res select 'AC-13c N en ninja SIGUE viendo a A en su lista de amigos',
  (select count(*) from public.v_my_friends
    where friend_id = 'b0000000-0000-0000-0000-00000000000a') = 1,
  'ninja no vacia tu propia lista';

reset role;

-- AC-12b · N en ninja deja de emitir
insert into res select 'AC-12b con ninja, N deja de emitir señales hacia A',
  not private.can_see_activity_of('b0000000-0000-0000-0000-00000000000a',
                                  'b0000000-0000-0000-0000-00000000000e'),
  'el filtro está en la base de datos, no en la pantalla';

-- AC-13 · pero sigue viendo. Esconderse no es cegarse.
insert into res select 'AC-13  N en ninja SIGUE viendo la actividad de A (D-43)',
  private.can_see_activity_of('b0000000-0000-0000-0000-00000000000e',
                              'b0000000-0000-0000-0000-00000000000a'),
  'asimétrico a propósito: castigar la privacidad hace que nadie la active';

-- AC-13b · y la amistad no se rompe
insert into res select 'AC-13b ninja no rompe la amistad, solo la señal',
  private.are_friends('b0000000-0000-0000-0000-00000000000a',
                      'b0000000-0000-0000-0000-00000000000e'),
  'are_friends ignora ninja; can_see_activity_of no';

-- AC-14 · ninja NO toca la puerta (Art. 7.3)
insert into res select 'AC-14  gate_find_by_dni no consulta ninja_mode (Art. 7.3)',
  (select count(*) from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('gate_find_by_dni','gate_checkin')
     and p.prosrc ilike '%ninja%') = 0,
  'ninja no es invisibilidad: no desactiva validación ni auditoría';

-- ═══════════════════════════════════════════════════════════════════════════
-- Superficie de escritura
-- ═══════════════════════════════════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims = '{"sub":"b0000000-0000-0000-0000-00000000000a","role":"authenticated"}';

-- AC-15a · el cliente no hace insert directo
insert into res select 'AC-15a authenticated no puede insertar una arista a mano',
  pg_temp.fails($q$insert into public.friend_edges (requester_id, addressee_id)
    values ('b0000000-0000-0000-0000-00000000000a',
            'b0000000-0000-0000-0000-00000000000c')$q$),
  'revoke insert: ni siquiera llega a evaluar política';

-- AC-15b · ni update de estado
insert into res select 'AC-15b authenticated no puede mover status a mano',
  pg_temp.fails($q$update public.friend_edges set status = 'accepted'
    where addressee_id = 'b0000000-0000-0000-0000-00000000000e'$q$),
  'una transición de estado vive en la RPC, no en una política';

-- AC-15c · y el camino feliz de la misma superficie: sí puede borrar
insert into res select 'AC-15c authenticated sí puede borrar su propia arista',
  not pg_temp.fails($q$delete from public.friend_edges
    where requester_id = 'b0000000-0000-0000-0000-00000000000a'
      and addressee_id = 'b0000000-0000-0000-0000-00000000000e'$q$),
  'dejar de ser amigos no necesita RPC: la política basta';

-- AC-15d · anon no toca nada
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

insert into res select 'AC-15d anon no lee el grafo',
  pg_temp.fails($q$select count(*) from public.friend_edges$q$),
  'permission denied, no cero filas — la 0009 le quitó el select';

-- AC-15e · una vista definer no es una vista publica. El unico freno es el
-- grant, y este es el que lo comprueba.
insert into res select 'AC-15e anon tampoco lee la vista definer',
  pg_temp.fails($q$select count(*) from public.v_my_friends$q$),
  'definer no significa publica: el grant es solo para authenticated';

-- ── Resultado ───────────────────────────────────────────────────────────────
reset role;

select ac,
       case when pass then '✓' else '✗ FALLA' end as r,
       detail
from res order by ac;

select count(*) filter (where not pass or pass is null) as fallos,
       count(*) as total
from res;

rollback;
