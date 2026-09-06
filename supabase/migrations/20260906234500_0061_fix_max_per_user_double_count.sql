-- Corrección de 0033 · Art. 12.4 · bug de Fase 1, encontrado al probar el
-- camino feliz de extremo a extremo por HTTP.
--
--   «el límite es 6 entradas por usuario para este evento, y ya tienes 6»
--   … con TRES entradas.
--
-- EL DOBLE CONTEO
--
-- La comprobación del Art. 11 sumaba dos cosas:
--
--   a) los tickets que el fan posee del evento, y
--   b) los `order_items` de sus órdenes en estados
--      draft, reserved, awaiting_payment, failed **y paid**.
--
-- El comentario original decía bien la intención —«lo ya emitido MÁS las
-- reservas vivas»— pero `paid` no es una reserva viva: es *exactamente* lo ya
-- emitido. Cada entrada pagada se contaba dos veces —una como ticket y otra
-- como ítem de su orden— así que el límite real era **la mitad** del
-- configurado.
--
-- POR QUÉ NO LO VIO NINGUNA SUITE
--
-- Las de 004 compran una vez y hacen rollback. Esto solo aparece comprando dos
-- veces seguidas con la misma cuenta, contra una base que conserva la primera
-- compra. Lo destapó `015_camino_feliz.mjs` en su segunda pasada.
--
-- Y con 012 empeoraba: en una compra grupal el comprador tiene 4 ítems pagados
-- y **una** entrada suya —las otras tres son de sus amigos—, así que comprar
-- para tres amigos le gastaba cuatro de sus seis.
--
-- CÓMO SE CORRIGE
--
-- Sacando `paid` de la lista (b). Es un cambio de una palabra sobre una función
-- de 6 800 caracteres que ya está verificada por las 40 comprobaciones de 004,
-- así que **no se reescribe**: se lee el cuerpo actual, se sustituye la lista y
-- se vuelve a crear. Rehacer la función a mano para cambiar una palabra es
-- cómo se pierde sin querer el `for update` en orden ascendente de id.
--
-- De paso queda bien otro caso: una entrada **transferida** deja de contarle a
-- quien la compró y pasa a contarle a quien la tiene. Con `paid` dentro le
-- contaba a los dos.

do $cirugia$
declare
  v_src text;
  v_new text;
begin
  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'reserve_order';

  if v_src is null then
    raise exception 'reserve_order no existe: 0033 no se aplicó';
  end if;

  v_new := replace(
    v_src,
    '''draft'',''reserved'',''awaiting_payment'',''failed'',''paid''',
    '''draft'',''reserved'',''awaiting_payment'',''failed''');

  -- Reejecutable: si ya está corregida, no hay nada que hacer.
  if v_new = v_src then
    if position('''paid''' in v_src) > 0 then
      raise exception 'la lista de estados no tiene la forma esperada; revisar a mano';
    end if;
    return;
  end if;

  execute format(
    'create or replace function public.reserve_order(p_event_id uuid, p_items jsonb)
     returns uuid language plpgsql security definer
     set search_path = public, private, pg_temp as %L', v_new);
end $cirugia$;
