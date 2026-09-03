-- Corrige 0024.
--
-- `security_invoker = false` hace que los privilegios sobre las TABLAS de la
-- vista se comprueben contra su dueño. Con las FUNCIONES no: el `EXECUTE` se
-- comprueba contra quien consulta. Así que `v_event_public` reventaba para anon
-- con «permission denied for function total_with_charge».
--
-- Exponerla es inofensivo y es la opción correcta: es aritmética pura sobre tres
-- números que el llamante ya trae. No lee ninguna tabla, no toca `auth.uid()`,
-- no es un oráculo de nada. Lo contrario —inlinear la fórmula en la vista—
-- duplicaría el redondeo en dos sitios, que es justo lo que 0024 evitaba.
--
-- Sigue en `private`, así que PostgREST no la publica como endpoint: se puede
-- llamar desde una vista, no desde /rest/v1/rpc.

grant usage on schema private to anon;
grant execute on function private.total_with_charge(int, int, public.charge_payer)
  to anon, authenticated;

comment on function private.total_with_charge(int, int, public.charge_payer) is
  'Aritmética pura: total con cargo, redondeado UNA vez. El cargo se deriva restando (total - base), nunca se redondea aparte. Ejecutable por anon porque v_event_public la necesita y no expone nada.';
