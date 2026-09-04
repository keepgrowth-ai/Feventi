-- Corrige 0047. `v_event_sales` daba 42501:
--
--     permission denied for function order_commission_cents
--
-- Es la MISMA lección que 0025, y la segunda vez que se paga: una vista
-- `security definer` corre con los privilegios de su dueño **para las tablas**,
-- pero el permiso de EXECUTE de las funciones que llama se comprueba contra el
-- rol que consulta. Definer no es un pase general.
--
-- Conceder EXECUTE aquí no abre nada: la función vive en `private`, que
-- PostgREST no expone (0010), así que no hay forma de llamarla desde fuera. Y no
-- lee ninguna tabla — recibe la fila de la orden ya resuelta por la vista, que
-- es la que decide qué órdenes son visibles.
grant execute on function private.order_commission_cents(public.orders) to authenticated;

comment on function private.order_commission_cents(public.orders) is
  'La comision de una orden, en un solo sitio. EXECUTE concedido a authenticated porque v_event_sales es definer y definer NO cubre el EXECUTE de las funciones (misma leccion que 0025). Vive en private, que PostgREST no expone.';
