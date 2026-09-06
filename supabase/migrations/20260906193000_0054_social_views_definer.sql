-- 010 · corrección de 0052 · el mismo error que 0041 → 0042
--
-- `v_my_friends` salía VACÍA. Con `security_invoker = true` la vista hace join
-- con `profiles`, y la política de `profiles` es SOLO PARA SU DUEÑO (0007):
--
--   uid = A · aristas_visibles 1 · perfil_de_B_visible 0 · filas_en_vista 0
--
-- Es AC-07c, y falló por la razón correcta: para enseñar el nombre de un amigo
-- hay que poder leer algo de su perfil, y eso es una revelación deliberada. La
-- alternativa —añadir a `profiles` una rama de política «o si somos amigos»—
-- abriría la fila ENTERA: teléfono, dni_last4, dni_verified_at y ninja_mode.
-- Que un amigo pueda leer `ninja_mode` rompe la función entera (010/plan.md).
--
-- Se elige la vista `security definer` con dos columnas y nada más, igual que
-- 0042 hizo con la wallet.
--
-- ⚠️ Una vista definer APAGA la RLS de las tablas de debajo. Con
-- `security_invoker` era la política de `friend_edges` la que dejaba solo mis
-- aristas; ahora esa política no se evalúa, así que el filtro tiene que estar
-- ESCRITO en el `where`. Sin la línea marcada abajo, esta vista devuelve el
-- grafo social completo de la plataforma a cualquiera que la consulte.

drop view public.v_my_friends;
drop view public.v_my_friend_requests;

create view public.v_my_friends with (security_invoker = false) as
select
  e.id                                            as edge_id,
  case when e.requester_id = auth.uid()
       then e.addressee_id else e.requester_id end as friend_id,
  p.full_name,
  p.avatar_url,
  e.responded_at                                  as since
from public.friend_edges e
join public.profiles p
  on p.id = case when e.requester_id = auth.uid()
                 then e.addressee_id else e.requester_id end
where e.status = 'accepted'
  -- ⚠️ EL FILTRO. Sin esto, la vista es una fuga del grafo entero.
  and (e.requester_id = auth.uid() or e.addressee_id = auth.uid())
  -- Ahora sí ve los dos sentidos del bloqueo: con `invoker`, la rama
  -- «p me bloqueó a mí» nunca casaba porque la RLS de `blocks` la escondía, y
  -- quien me hubiera bloqueado seguía apareciendo en mi lista de amigos.
  and not exists (
    select 1 from public.blocks bl
     where (bl.blocker_id = auth.uid() and bl.blocked_id = p.id)
        or (bl.blocker_id = p.id and bl.blocked_id = auth.uid())
  );

create view public.v_my_friend_requests with (security_invoker = false) as
select
  e.id           as edge_id,
  e.requester_id,
  p.full_name,
  p.avatar_url,
  e.created_at
from public.friend_edges e
join public.profiles p on p.id = e.requester_id
where e.status = 'pending'
  -- El mismo filtro, aquí sí explícito desde 0052.
  and e.addressee_id = auth.uid()
  and not exists (
    select 1 from public.blocks bl
     where (bl.blocker_id = auth.uid() and bl.blocked_id = p.id)
        or (bl.blocker_id = p.id and bl.blocked_id = auth.uid())
  );

-- `drop view` se llevó los grants por delante.
grant select on public.v_my_friends         to authenticated;
grant select on public.v_my_friend_requests to authenticated;

comment on view public.v_my_friends is
  'Definer (como v_my_tickets, 0042): profiles solo lo lee su dueno. Emite SOLO full_name y avatar_url de un amigo aceptado — nunca ninja_mode, telefono ni dni_last4. El where lleva el filtro por auth.uid() escrito a mano porque definer apaga la RLS.';
