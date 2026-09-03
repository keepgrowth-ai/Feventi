-- 004 · T-22, T-23
--
-- Dos features dejaron una tarea abierta POR DEPENDENCIA, no por olvido: las dos
-- necesitaban que `tickets` existiera. Ahora existe.
--
--   007/T-14 · AC-14, AC-15, AC-16 — D-08
--   003/T-15 · AC-19

-- ── 007: con entradas emitidas, los campos sensibles los cambia Feventi ─────
--
-- Por qué un trigger y no un privilegio de columna: la restricción no es
-- «nunca», es «ya no». El organizador SÍ edita `starts_at` mientras está en
-- draft. Un grant es estático; esto depende del estado de la fila.
create or replace function private.guard_sensitive_event_fields()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- AC-16: Admin sí puede, y su cambio deja asiento por la RPC que lo llama.
  if private.auth_is_admin() then return new; end if;

  -- AC-15: antes de vender, el organizador es dueño de su ficha.
  if not exists (select 1 from public.tickets where event_id = new.id) then
    return new;
  end if;

  -- AC-14
  if new.starts_at            is distinct from old.starts_at
  or new.venue_id             is distinct from old.venue_id
  or new.capacity             is distinct from old.capacity
  or new.service_charge_bps   is distinct from old.service_charge_bps
  or new.service_charge_payer is distinct from old.service_charge_payer
  or new.max_per_user         is distinct from old.max_per_user
  or new.qr_lead_days         is distinct from old.qr_lead_days
  or new.nomination_mode      is distinct from old.nomination_mode then
    raise exception
      'con entradas ya emitidas, la fecha, el lugar, el aforo y las reglas comerciales los cambia Feventi: abre un caso de soporte'
      using errcode = '42501';
  end if;

  return new;
end $$;

create trigger events_guard_sensitive_fields
  before update on public.events
  for each row execute function private.guard_sensitive_event_fields();

-- ── 003: con ventas, no se cambia el precio de un tier ─────────────────────
-- Un precio que cambia después de vender deja dos fans con el mismo asiento a
-- distinto precio, y una conciliación que no cierra.
create or replace function private.guard_sold_price_tier()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if private.auth_is_admin() then return new; end if;

  -- El `sold` de la propia fila ya dice si hubo ventas: no hace falta consultar
  -- `tickets`, y así el guard no depende de otra tabla.
  if old.sold > 0 and new.price_cents is distinct from old.price_cents then
    raise exception
      'esta entrada ya tiene % ventas: el precio lo cambia Feventi', old.sold
      using errcode = '42501';
  end if;

  -- AC-18 de 003: nunca por debajo de lo ya comprometido. El check de la tabla
  -- también lo atrapa, pero este mensaje dice qué hacer.
  if new.stock < old.sold + old.reserved then
    raise exception
      'no se puede bajar el stock a % : ya hay % vendidas y % reservadas',
      new.stock, old.sold, old.reserved
      using errcode = '23514';
  end if;

  return new;
end $$;

create trigger price_tiers_guard_sold
  before update on public.price_tiers
  for each row execute function private.guard_sold_price_tier();

-- ── 003/AC-20: una zona con tickets emitidos no se borra ───────────────────
create or replace function private.guard_zone_with_tickets()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.tickets where zone_id = old.id) then
    raise exception
      'esta zona ya tiene entradas emitidas y no se puede borrar: despublica el evento'
      using errcode = '42501';
  end if;
  return old;
end $$;

create trigger zones_guard_delete
  before delete on public.zones
  for each row execute function private.guard_zone_with_tickets();

revoke all on function private.guard_sensitive_event_fields() from public, anon, authenticated;
revoke all on function private.guard_sold_price_tier()        from public, anon, authenticated;
revoke all on function private.guard_zone_with_tickets()      from public, anon, authenticated;
