# Modelo de datos — Fase 1

Contrato compartido por todos los features. Un `plan.md` puede **usar** estas tablas y
**añadir** columnas con una migración propia, pero no redefinir una entidad existente.

Convenciones:

- `id uuid primary key default gen_random_uuid()`, salvo tablas puente.
- Dinero: entero en céntimos, sufijo `_cents`, más `currency char(3) not null default 'PEN'`.
- Tiempo: `timestamptz`, nunca `timestamp`.
- Auditoría: `created_at timestamptz not null default now()`; `updated_at` solo donde
  hay edición real, mantenido por trigger.
- Enums de Postgres para estados cerrados. Estados abiertos: `text` + `check`.
- Nombres de tabla en plural, en inglés; el copy en español vive en el front.

Dos schemas:

- **`public`** — las tablas y la superficie real de RPC. PostgREST lo expone.
- **`private`** — helpers de RLS (`auth_is_admin`, `auth_organizer_ids`, …), funciones
  de trigger y `hash_dni`. PostgREST **no** lo expone, así que nada de ahí es un
  endpoint. Las políticas los resuelven por OID, no por nombre.

Los privilegios por defecto están invertidos respecto a Supabase (migración `0009`):
una tabla nueva nace con `select` para `authenticated`, **nada** para `anon`, y sin
`insert/update/delete` ni `truncate` para ninguno de los dos. Cada feature concede lo
suyo de forma explícita — Art. 9.1.

---

## 1. Identidad, roles y tenencia

### `profiles`
Espejo 1:1 de `auth.users`. Se crea con trigger `on auth.user created`.

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK → `auth.users.id` | on delete cascade |
| `full_name` | text | |
| `email` | text | denormalizado para búsqueda de soporte |
| `phone` | text | |
| `dni_last4` | char(4) | lo único que se muestra |
| `dni_verified_at` | timestamptz | null = no verificado |
| `ninja_mode` | boolean not null default false | **Art. 7.3** |
| `avatar_url` | text | |
| `created_at` | timestamptz | |

`profiles` es legible entero por su dueño: no esconde ninguna columna. El hash del
DNI vive aparte, en `profile_identity`, por lo que se explica abajo.

### `profile_identity`
**Art. 7.1.** El HMAC del DNI, aislado. RLS activa y **cero políticas**: el mismo
patrón que `ticket_secrets`. Solo la alcanzan `service_role` y las funciones
`security definer` de nominación (004) y de puerta (006).

| col | tipo | nota |
|---|---|---|
| `user_id` | uuid PK → profiles | on delete cascade |
| `dni_hash` | text not null | `hmac(dni, pepper, 'sha256')`, con el pepper en Vault |
| `created_at`, `updated_at` | timestamptz | |

El primer intento fue dejar `dni_hash` en `profiles` con un `revoke select` de
columna. Funciona, pero PostgREST emite `select *` cuando el cliente no pide
columnas, así que un `GET /profiles` devolvía 42501 — y el siguiente que lo
«arreglara» con un `grant select` reabriría el agujero sin notarlo. Una tabla sin
políticas no se reabre por accidente.

### `user_roles`
Roles globales. **Art. 9.2**: el cliente no escribe aquí nunca.

| col | tipo | nota |
|---|---|---|
| `user_id` | uuid → profiles | |
| `role` | `app_role` | PK compuesta `(user_id, role)` |

```
create type app_role as enum ('fan','organizer','staff','admin');
```

`fan` se asigna solo al registrarse. `admin` solo por `service_role`. `organizer` y
`staff` se derivan de las tablas de abajo y existen aquí solo como atajo de navegación.

### `organizers`

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `legal_name` | text not null | razón social |
| `trade_name` | text | nombre comercial, p. ej. `Andes Live SAC` |
| `ruc` | text | único cuando no es null |
| `status` | `organizer_status` | `draft, pending, approved, rejected, suspended` |
| `contact_email`, `contact_phone` | text | |
| `reputation` | int | reservado; fórmula pendiente |
| `created_by` | uuid → profiles | |
| `approved_at`, `approved_by` | | evidencia (**Art. 4.3**) |

### `organizer_members`
Multi-tenencia. Un usuario puede pertenecer a varios organizadores.

| col | tipo | nota |
|---|---|---|
| `organizer_id` | uuid → organizers | PK compuesta |
| `user_id` | uuid → profiles | PK compuesta |
| `role` | `organizer_role` | `owner, admin, viewer` |
| `revoked_at` | timestamptz | **Art. 8.2** — se revoca, no se borra |

### `event_staff`
Asignación de staff a un evento y una puerta.

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `event_id` | uuid → events | |
| `user_id` | uuid → profiles | |
| `gate` | text not null | `Puerta Principal` |
| `shift_starts_at`, `shift_ends_at` | timestamptz | |
| `assigned_by` | uuid → profiles | |
| `revoked_at` | timestamptz | **Art. 8.2** |

`unique (event_id, user_id, gate) where revoked_at is null`.

---

## 2. Evento

### `venues`

| col | tipo |
|---|---|
| `id` | uuid PK |
| `name` | text not null |
| `city` | text not null |
| `address` | text |
| `capacity` | int |

### `events`
Una sola tabla cubre **solicitud** y **evento**: la pantalla «Solicitudes» es esta
tabla filtrada por `status`. No hay entidad `event_request` duplicada.

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `code` | text unique | `REQ-001`, generado por secuencia |
| `organizer_id` | uuid → organizers | |
| `venue_id` | uuid → venues | |
| `slug` | text unique | URL pública |
| `title`, `description`, `category` | text | |
| `hero_image_url` | text | |
| `starts_at` | timestamptz not null | |
| `doors_at` | timestamptz | |
| `timezone` | text not null default `'America/Lima'` | |
| `status` | `event_status` | ver abajo |
| `visibility` | `event_visibility` | `public, unlisted, private` |
| `capacity` | int | aforo declarado |
| `max_per_user` | int not null default 5 | **Art. 11** |
| `resale_enabled` | boolean not null default true | |
| `max_resales` | int not null default 2 | **Art. 6.3** |
| `resale_commission_bps` | int not null default 1000 | **Art. 6.6** |
| `service_charge_bps` | int not null default 600 | **Art. 5** |
| `service_charge_payer` | `charge_payer` | `fan, organizer` |
| `qr_lead_days` | int not null default 14 | **Art. 2.5** |
| `nomination_mode` | `nomination_mode` | `strict, flexible` |
| `payout_policy` | jsonb | tramos declarativos, p. ej. `[{"pct":30,...}]` |
| `review_checklist` | jsonb | 6 ítems del mockup, `pending / ok / na` |
| `submitted_at`, `published_at`, `paused_at`, `cancelled_at` | timestamptz | |
| `created_by` | uuid → profiles | |

```
create type event_status as enum (
  'draft',              -- borrador del organizador, invisible
  'pending_review',     -- enviado a Admin; NO vende (Art. 4.2)
  'changes_requested',  -- Admin pidió info
  'rejected',
  'approved',           -- aprobado, aún no publicado
  'setup',              -- cargando zonas, fases y precios
  'published',          -- única condición que habilita venta
  'paused',             -- venta detenida, tickets siguen válidos
  'cancelled',
  'finished'
);
```

**Solo `published` habilita venta.** Se enforce en la función de reserva, no en la UI.

### `event_review_notes`
Append-only. **Art. 4.3** y **Art. 8**.

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `event_id` | uuid → events | |
| `actor_id` | uuid → profiles | quién decidió |
| `action` | `review_action` | `submitted, info_requested, approved, rejected, note, paused, cancelled` |
| `note` | text | observación al organizador |
| `checklist_snapshot` | jsonb | estado del checklist al decidir |
| `status_before`, `status_after` | `event_status` | |
| `created_at` | timestamptz | |

---

## 3. Inventario y precio

Tres ejes: **zona** (dónde), **segmento** (qué filas dentro de una zona numerada) y
**fase** (cuándo). El precio vive en el cruce.

### `zones`

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `event_id` | uuid → events | |
| `name` | text | `General — de pie`, `Platea — butacas`, `VIP` |
| `kind` | `zone_kind` | `standing, seated` |
| `numbered` | boolean not null default false | |
| `capacity` | int not null | |
| `notes` | text | `Sin numeración` |
| `sort_order` | int | |

### `zone_segments`
Solo zonas numeradas con precio distinto por bloque de filas.

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `zone_id` | uuid → zones | |
| `label` | text | `Filas A–C` |
| `row_from`, `row_to` | text | `A` … `C` |
| `sort_order` | int | |

### `price_phases`

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `event_id` | uuid → events | |
| `name` | text | `Preventa 1`, `Regular`, `Preventa FanPass` |
| `kind` | `phase_kind` | `presale, regular, fanpass_presale` |
| `starts_at`, `ends_at` | timestamptz | |
| `sort_order` | int | |

Fase activa = `now() between starts_at and ends_at`. Se calcula, no se guarda.

### `price_tiers`
El precio real. Una fila por (zona | segmento) × fase.

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `event_id` | uuid → events | denormalizado para RLS e índices |
| `zone_id` | uuid → zones | |
| `segment_id` | uuid → zone_segments | nullable |
| `phase_id` | uuid → price_phases | |
| `price_cents` | int not null check > 0 | precio base, sin cargo |
| `currency` | char(3) not null default `'PEN'` | |
| `stock` | int not null check >= 0 | cupos de esta combinación |
| `reserved` | int not null default 0 | reservas vivas |
| `sold` | int not null default 0 | |

`unique (zone_id, segment_id, phase_id)` (con `segment_id` null tratado como valor).
Invariante: `reserved + sold <= stock`, garantizada por la función de reserva.

### `seats`
Solo para zonas `numbered`. La disponibilidad **no** se guarda aquí: se deriva de
`order_items` vivos, para tener una sola fuente de verdad.

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `zone_id` | uuid → zones | |
| `segment_id` | uuid → zone_segments | |
| `row_label` | text not null | `B` |
| `seat_number` | int not null | `5` |
| `blocked` | boolean not null default false | bloqueo operativo |

`unique (zone_id, row_label, seat_number)`.

---

## 4. Compra, pago y emisión

### `orders`

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `code` | text unique | referencia para soporte |
| `event_id` | uuid → events | |
| `buyer_id` | uuid → profiles | |
| `status` | `order_status` | ver abajo |
| `subtotal_cents` | int not null default 0 | suma de precios base |
| `discount_cents` | int not null default 0 | |
| `service_charge_cents` | int not null default 0 | 0 si lo absorbe el organizador |
| `total_cents` | int not null default 0 | lo que se cobra |
| `currency` | char(3) not null default `'PEN'` | |
| `service_charge_payer` | `charge_payer` | congelado del evento al reservar |
| `promo_code` | text | `BBVA15` |
| `reserved_until` | timestamptz | vence la reserva |
| `created_at`, `paid_at`, `failed_at` | timestamptz | |

```
create type order_status as enum (
  'draft','reserved','awaiting_payment','paid','failed','expired','refunded','cancelled'
);
```

### `order_items`

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `order_id` | uuid → orders | on delete cascade |
| `price_tier_id` | uuid → price_tiers | |
| `seat_id` | uuid → seats | null en zonas de pie |
| `unit_price_cents` | int not null | congelado al reservar |
| `attendee_name` | text | nominación |
| `attendee_dni_hash` | text | **Art. 7.1** |
| `attendee_dni_last4` | char(4) | |
| `nominated_at` | timestamptz | null = sin nominar |

Una fila = una entrada. Sin columna `qty`: simplifica asientos y nominación.
`unique (seat_id) where seat_id is not null` sobre órdenes vivas, vía índice parcial.

### `payments`

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `order_id` | uuid → orders | |
| `provider` | text not null default `'culqi_sandbox'` | **Art. 13** |
| `provider_ref` | text | id del cargo en la pasarela |
| `status` | `payment_status` | `pending, succeeded, failed, refunded, disputed` |
| `amount_cents` | int not null | |
| `currency` | char(3) not null | |
| `raw` | jsonb | respuesta cruda, para conciliar |
| `created_at`, `settled_at` | timestamptz | |

### `tickets`
**Art. 2.1**: no existe fila aquí sin pago confirmado.

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `code` | text unique not null | `FVT-2026-A3B7K9` |
| `event_id` | uuid → events | |
| `order_item_id` | uuid → order_items | unique |
| `zone_id` | uuid → zones | |
| `seat_id` | uuid → seats | |
| `owner_id` | uuid → profiles | propietario **actual** |
| `original_owner_id` | uuid → profiles | primer comprador |
| `holder_name` | text | asistente nominado |
| `holder_dni_hash` | text | |
| `holder_dni_last4` | char(4) | |
| `status` | `ticket_status` | ver abajo |
| `face_value_cents` | int not null | techo de reventa (**Art. 6.2**) |
| `resale_count` | int not null default 0 | tope `events.max_resales` |
| `qr_available_from` | timestamptz | `starts_at - qr_lead_days` |
| `issued_at` | timestamptz not null default now() | |
| `used_at` | timestamptz | |

```
create type ticket_status as enum (
  'active',       -- válido; QR disponible dentro de ventana
  'listed',       -- en reventa: QR inhabilitado (Art. 2.4)
  'transferred',  -- cedido: esta fila ya no entra
  'used',         -- consumido en puerta
  'void',         -- anulado por Admin
  'refunded'
);
```

Solo `active` puede producir QR y solo `active` puede pasar a `used`.

### `ticket_secrets`
**Art. 2.6.** Tabla separada, RLS de negación total, sin ninguna política. Solo la
alcanza `service_role` desde una Edge Function.

| col | tipo | nota |
|---|---|---|
| `ticket_id` | uuid PK → tickets | on delete cascade |
| `secret` | bytea not null | 32 bytes aleatorios; base del HMAC del QR |
| `rotated_at` | timestamptz | |

### `ticket_events`
Append-only. **Art. 8.3**: una corrección es un asiento nuevo.

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `ticket_id` | uuid → tickets | |
| `actor_id` | uuid → profiles | null = sistema |
| `action` | text not null | `issued, nominated, listed, unlisted, transferred, used, voided, refunded, corrected` |
| `meta` | jsonb | |
| `corrects_id` | uuid → ticket_events | asiento que corrige |
| `created_at` | timestamptz | |

---

## 5. Puerta

### `checkins`
Append-only, **sin `DELETE` para nadie** (**Art. 8.1**). Se registra también el intento
fallido: un QR inválido es la señal más valiosa de la noche.

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `event_id` | uuid → events | |
| `ticket_id` | uuid → tickets | null si el QR no resolvió a un ticket |
| `staff_id` | uuid → profiles | |
| `gate` | text not null | |
| `result` | `checkin_result` | `allowed, manual_review, already_used, denied` |
| `reason` | text | `qr_expired`, `not_nominated`, `wrong_zone`, `screenshot_suspected` |
| `scanned_code` | text | lo que leyó la cámara, para peritaje |
| `device_id` | text | |
| `scanned_at` | timestamptz not null default now() | |

Los cuatro `result` son exactamente los cuatro resultados del mockup.

---

## 6. Soporte

### `support_cases`

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `code` | text unique | `#1042` |
| `kind` | `support_kind` | `payment, ticket, qr, resale, courtesy, group, refund, cancellation, ownership, other` |
| `priority` | `support_priority` | `low, medium, high` |
| `status` | `support_status` | `open, waiting_user, escalated, resolved, closed` |
| `event_id`, `order_id`, `ticket_id` | uuid | contexto; **Art.**: soporte siempre nace desde el objeto afectado |
| `opened_by` | uuid → profiles | |
| `assigned_to` | uuid → profiles | |
| `subject` | text not null | |
| `created_at`, `resolved_at` | timestamptz | |

### `support_messages`

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `case_id` | uuid → support_cases | |
| `author_id` | uuid → profiles | |
| `body` | text not null | |
| `internal` | boolean not null default false | nota interna: el fan no la ve |
| `created_at` | timestamptz | |

---

## 7. Vistas derivadas

Nunca se guarda un total que se puede calcular.

| vista | para | contenido |
|---|---|---|
| `v_event_public` | catálogo y detalle | eventos `published` + `precio desde` de la fase activa + señal de disponibilidad |
| `v_event_availability` | detalle de evento | por `price_tier`: `stock - reserved - sold` |
| `v_event_sales` | dashboard organizador | entradas vendidas, venta bruta, comisión, neto **estimado** (**Art. 5**) |
| `v_event_phase_sales` | dashboard organizador | venta e entradas por fase |
| `v_gate_stats` | validador | validados, revisión manual, denegados, % de aforo |

`v_event_public` es la única superficie que `anon` puede leer.

---

## Fuera de Fase 1

Con su artículo ya escrito en la constitución, para que el schema de Fase 2 no
contradiga nada: `resale_listings`, `courtesy_batches` / `courtesy_codes`,
`purchase_groups` / `group_members`, `event_groups`, `payouts` / `payout_tranches`,
`fanpass_memberships` / `point_ledger`, `promoters` / `promoter_codes`,
`event_albums` / `album_media` / `content_reports`.
