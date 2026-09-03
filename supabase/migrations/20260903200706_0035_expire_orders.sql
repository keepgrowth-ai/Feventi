-- 004 · T-20, T-21 · AC-11 … AC-14
--
-- El stock tiene que volver a estar disponible AUNQUE NADIE ENTRE A LA PÁGINA.
-- Liberar «cuando alguien consulta» significa que el último cupo de un evento
-- agotado no vuelve nunca: nadie consulta un evento que dice «agotado».

create or replace function public.expire_orders()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare v_expired int;
begin
  -- AC-13: idempotente. Se baja `reserved` SOLO por las órdenes que esta pasada
  -- está moviendo a `expired`, y con la fila bloqueada. Correrlo dos veces no
  -- descuenta dos veces.
  --
  -- AC-14: `paid` no entra en el filtro, ni aunque su reserved_until haya
  -- pasado. Una orden pagada no tiene reserva que liberar: tiene tickets.
  with vencidas as (
    select id from public.orders
     where status in ('reserved', 'awaiting_payment', 'failed')
       and reserved_until < now()
     order by id
       for update skip locked      -- si otra pasada la tiene, esta la deja
  ),
  -- Cuánto libera cada tier, contado ANTES de borrar los ítems.
  liberado as (
    select oi.price_tier_id, count(*) as n
      from public.order_items oi
     where oi.order_id in (select id from vencidas)
     group by oi.price_tier_id
  ),
  devuelto as (
    update public.price_tiers t
       set reserved = greatest(t.reserved - l.n, 0)
      from liberado l
     where t.id = l.price_tier_id
    returning t.id
  ),
  -- AC-12: los ítems se BORRAN, y con eso el asiento queda libre sin que el
  -- unique index tenga que saber nada de estados.
  borrados as (
    delete from public.order_items
     where order_id in (select id from vencidas)
    returning id
  ),
  -- La orden se conserva con sus totales, para conciliación y soporte.
  marcadas as (
    update public.orders
       set status = 'expired', expired_at = now()
     where id in (select id from vencidas)
    returning id
  )
  select count(*)::int into v_expired from marcadas;

  return v_expired;
end $$;

revoke all on function public.expire_orders() from public, anon, authenticated;

comment on function public.expire_orders() is
  'AC-11: corre cada minuto por pg_cron. Idempotente (AC-13) y nunca toca una orden paid (AC-14).';

-- ── El job ──────────────────────────────────────────────────────────────────
create extension if not exists pg_cron;

do $$
begin
  -- Idempotente: si ya existe, se reemplaza en lugar de duplicarse.
  if exists (select 1 from cron.job where jobname = 'feventi-expire-orders') then
    perform cron.unschedule('feventi-expire-orders');
  end if;
  perform cron.schedule('feventi-expire-orders', '* * * * *',
                        $job$select public.expire_orders()$job$);
end $$;
