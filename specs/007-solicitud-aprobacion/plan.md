# 007 — Plan

## Migraciones

| # | nombre | contenido |
|---|---|---|
| 0012 | `event_enums` | `event_status`, `event_visibility`, `charge_payer`, `nomination_mode`, `review_action` |
| 0013 | `venues` | tabla + RLS |
| 0014 | `events` | tabla, secuencia de `code`, índices, RLS, privilegios de columna |
| 0015 | `event_review_notes` | bitácora append-only + RLS |
| 0016 | `event_transitions` | las RPC de la máquina de estados |
| 0017 | `event_guards` | triggers que protegen la edición con venta abierta |

## La decisión que estructura todo: una sola tabla

La guía habla de «Solicitudes» y de «Eventos» como dos pestañas, y la tentación es
hacer dos tablas: `event_requests` que al aprobarse copia a `events`.

Se hace con **una**, y `status` distingue. Dos tablas obligarían a duplicar cada
columna, a mantener una copia que se desincroniza, y a decidir qué pasa con la
solicitud cuando el evento aprobado cambia. Con una tabla, «Solicitudes» es
`events` filtrada por `status in ('draft','pending_review','changes_requested','rejected')`
y «Eventos» es la misma tabla con los estados de más adelante. La pantalla es una
vista; la entidad es una.

El coste es que `events` tiene columnas que en `draft` están vacías. Es un coste
barato: nullable y un `check` que solo exige en `submit_event`.

## La máquina de estados vive en funciones, no en políticas

Una política de RLS puede decir «este usuario puede tocar esta fila». No puede decir
«de `draft` puedes ir a `pending_review` pero no a `published`». Eso es una
transición, y las transiciones van en RPC `security definer`.

Siete funciones, y cada una es un arco del diagrama:

| función | quién | de | a |
|---|---|---|---|
| `create_event` | organizador | — | `draft` |
| `submit_event` | organizador | `draft`, `changes_requested` | `pending_review` |
| `request_event_info` | Admin | `pending_review` | `changes_requested` |
| `approve_event` | Admin | `pending_review` | `approved` |
| `reject_event` | Admin | `pending_review` | `rejected` |
| `publish_event` | **organizador** | `setup` | `published` |
| `pause_event` / `cancel_event` | Admin | `published`, `paused` | `paused` / `cancelled` |

`approved → setup` no es una función: lo hace `approve_event` de una vez, porque
«aprobado» y «cargando inventario» son el mismo momento desde el lado del
organizador. Lo que **sí** es un paso aparte es `setup → published`, y lo da el
organizador: Feventi autoriza, el organizador decide cuándo abre la venta (AC-07).

Todas comparten el mismo esqueleto, para que ninguna se olvide de la bitácora:

```sql
create or replace function public.approve_event(p_event_id uuid, p_note text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_before public.event_status;
begin
  if not private.auth_is_admin() then
    raise exception 'solo Admin' using errcode = '42501';
  end if;

  -- Bloquea la fila: dos Admins revisando la misma solicitud a la vez es real.
  select status into v_before from public.events where id = p_event_id for update;
  if v_before is null then
    raise exception 'evento inexistente' using errcode = '22023';
  end if;
  if v_before <> 'pending_review' then
    raise exception 'solo se aprueba desde pending_review (está en %)', v_before
      using errcode = '22023';
  end if;

  update public.events
     set status = 'setup', approved_at = now()
   where id = p_event_id;

  perform private.log_event_review(p_event_id, 'approved', p_note, v_before, 'setup');
end $$;
```

`private.log_event_review()` escribe el asiento con el `checklist_snapshot` leído en
ese instante. Que sea una función y no código repetido es lo que hace cumplible el
**AC-10**: no hay forma de escribir una transición sin su evidencia, porque el
`perform` está en la plantilla.

## `code`: legible y correlativo

`REQ-001`. Secuencia de Postgres más formato, en un `default`:

```sql
create sequence public.event_code_seq;
alter table public.events
  alter column code set default 'REQ-' || lpad(nextval('public.event_code_seq')::text, 3, '0');
```

Con secuencia hay huecos si una transacción falla, y da igual: es un identificador
para dictar por teléfono, no un contador de negocio. Lo que **no** puede pasar es que
se repita, y una secuencia lo garantiza sin bloquear. Un `max(code)+1` sí bloquearía.

## Qué campos se congelan al publicar, y quién los cuida

**D-08** dice: con entradas vendidas, el organizador no toca zonas, precios, fecha,
aforo ni venue. Eso se puede hacer de dos formas y la diferencia importa.

**Privilegio de columna no sirve aquí**, porque la restricción no es «nunca», es
«ya no». El organizador *sí* edita `starts_at` mientras está en `draft`. Un `grant`
es estático; esto depende del estado de la fila y de si hay tickets.

Así que va en un **trigger** `before update`:

```sql
create or replace function private.guard_sensitive_event_fields()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- Admin sí puede, y su cambio deja asiento (AC-16).
  if private.auth_is_admin() then return new; end if;

  -- Antes de vender, el organizador es dueño de su ficha.
  if not exists (select 1 from public.tickets where event_id = new.id) then
    return new;
  end if;

  if new.starts_at         is distinct from old.starts_at
  or new.venue_id          is distinct from old.venue_id
  or new.capacity          is distinct from old.capacity
  or new.service_charge_bps is distinct from old.service_charge_bps
  or new.service_charge_payer is distinct from old.service_charge_payer
  or new.max_per_user      is distinct from old.max_per_user
  or new.qr_lead_days      is distinct from old.qr_lead_days
  or new.nomination_mode   is distinct from old.nomination_mode then
    raise exception
      'con entradas emitidas, estos campos los cambia Feventi: abre un caso de soporte'
      using errcode = '42501';
  end if;

  return new;
end $$;
```

> `ponytail:` el trigger hace `exists` sobre `tickets` en cada update de `events`.
> Con el índice de `tickets(event_id)` es un index-only scan y a esta escala no se
> nota. Si algún día `events` recibe updates masivos, se cachea en un booleano
> `has_issued_tickets` mantenido por el trigger de emisión.

**`tickets` todavía no existe** — la crea 004. Hasta entonces el `exists` iría contra
una tabla ausente. Se resuelve con orden: el trigger se crea en `0017`, que se aplica
**después** de 004. Mientras tanto rige la parte que sí se puede: `status` fuera del
`grant` de columna del organizador, y las transiciones solo por RPC.

Anotado como dependencia explícita en `tasks.md`, T-14.

## El checklist es de Admin, no del organizador

Seis ítems, en `events.review_checklist` como `jsonb`:

```json
{"datos_generales":"ok","organizador_ruc":"ok","venue_plano":"pending",
 "fechas_funciones":"ok","zonas_fases":"pending","cortesias_bolsas":"na"}
```

`jsonb` y no una tabla porque son seis claves fijas que se leen y escriben siempre
juntas, siempre del mismo evento, y nunca se consultan de forma cruzada («dame los
eventos a los que les falta el plano» no es una pantalla que exista). Una tabla
`event_checklist_items` sería seis filas por evento para no ganar nada.

El organizador lo **lee** (necesita saber qué le falta) pero no lo escribe: la columna
queda fuera de su `grant`. Un `check` valida que las claves sean exactamente esas seis
y los valores `ok|pending|na`, para que un `jsonb` libre no se convierta en un vertedero.

## RLS

Siguiendo la convención de 001: una política por operación, casos unidos por `OR`,
caso común primero.

```sql
create policy events_select on public.events
  for select to authenticated
  using (
    organizer_id = any (private.auth_organizer_ids())
    or private.auth_is_admin()
  );
```

`anon` **no** lee `events` (AC-18). Lo público sale de `v_event_public`, que crea 002
y es la única superficie que se concede a `anon`.

`event_review_notes`: el organizador lee las de sus eventos pero no las notas internas
—se resuelve con una columna `internal boolean` y la política filtrándola, igual que
`support_messages` en 009— y nadie tiene `update` ni `delete` (AC-11).

## Front

```
features/
  organizador/
    solicitudes.page.ts       lista de mis eventos por estado
    solicitud-form.page.ts    la ficha: datos, fecha, venue, reglas comerciales
  admin/
    solicitudes.page.ts       cola de revisión, con filtro por estado
    solicitud-detalle.page.ts checklist + aprobar / rechazar / pedir info
```

Ambas en `OpsLayout` (Art. 10, modo Operación). Copy que el spec exige:

- El botón en `draft` dice **«Enviar a revisión»**, nunca «Publicar».
- Aprobado, la pantalla dice que falta cargar zonas y precios y que **publicar es
  decisión del organizador** — `approved` no es `published`.
- `paused` dice «venta pausada — las entradas ya emitidas siguen siendo válidas».

## Verificación

`supabase/tests/007_solicitud_aprobacion.sql`. Los que importan de verdad:

- **AC-05** el organizador no puede escribir `status` (privilegio de columna).
- **AC-08** transición inválida rechazada, con el estado actual en el mensaje.
- **AC-10** cada una de las siete funciones deja exactamente un asiento.
- **AC-11** `event_review_notes` sin `update` ni `delete` para nadie.
- **AC-17** aislamiento entre organizadores.
- Y una que no está en el spec y debería: **dos Admins aprobando la misma solicitud
  en paralelo** producen un éxito y un fallo, no dos asientos. Es lo que garantiza el
  `for update`.

## Riesgos

| riesgo | mitigación |
|---|---|
| El trigger de D-08 depende de `tickets`, que crea 004 | `0017` se aplica después de 004; anotado en T-14 |
| Una transición nueva se escribe sin bitácora | la plantilla incluye el `perform`; **AC-10** lo verifica función por función |
| El `jsonb` del checklist se convierte en vertedero | `check` de claves y valores exactos |
| Dos Admins deciden a la vez | `select ... for update` en las siete funciones |
