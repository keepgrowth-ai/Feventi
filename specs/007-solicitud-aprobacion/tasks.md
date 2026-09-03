# 007 — Tasks

**Cerrado, salvo T-14.** 32 comprobaciones de política en verde, más la de
concurrencia con dos conexiones reales. Advisors: seguridad sin `ERROR`,
rendimiento sin `WARN`.

T-14 queda pendiente **por dependencia, no por olvido**: el trigger de D-08
consulta `tickets`, que crea 004. Se aplica ahí.

## Base de datos

- [x] T-01 `0012_event_enums`: `event_status` (10 valores), `event_visibility`, `charge_payer`, `nomination_mode`, `review_action`
- [x] T-02 `0013_venues`: tabla + RLS + `grant select` a `authenticated`; escritura solo Admin y organizador aprobado
- [x] T-03 `0014_events`: tabla completa según `data-model.md` §2
- [x] T-04 `0014_events`: secuencia + `default` de `code` → `REQ-001` — AC-02
- [x] T-05 `0014_events`: `check` del `review_checklist` (seis claves exactas, valores `ok|pending|na`)
- [x] T-06 `0014_events`: índices `(organizer_id, status)` y `(status, visibility, starts_at)` — el segundo lo necesita 002
- [x] T-07 `0014_events`: RLS on, una política de select con `OR` (convención de 001) — AC-17, AC-18
- [x] T-08 `0014_events`: `revoke insert, update, delete`; `grant update` solo de los campos de ficha. `status`, `code`, `organizer_id`, `review_checklist`, `approved_at`, `published_at` **fuera** del grant — AC-05
- [x] T-09 `0015_event_review_notes`: tabla append-only, columna `internal`, RLS; sin `update` ni `delete` para nadie — AC-11, AC-13
- [x] T-10 `0016_event_transitions`: `private.log_event_review()`, la plantilla que hace imposible una transición sin evidencia — AC-10
- [x] T-11 `0016_event_transitions`: `create_event`, `submit_event` (valida campos obligatorios) — AC-01, AC-03, AC-04
- [x] T-12 `0016_event_transitions`: `approve_event`, `reject_event`, `request_event_info` (nota obligatoria) — AC-06, AC-08, AC-12
- [x] T-13 `0016_event_transitions`: `publish_event` (organizador, solo desde `setup`, exige al menos un `price_tier` con stock), `pause_event`, `cancel_event` — AC-07
- [x] T-13b Las siete funciones con `select ... for update` sobre la fila — dos Admins a la vez
- [ ] T-14 `0017_event_guards`: trigger de D-08. **Depende de `tickets`, que crea 004** — esta migración se aplica *después* de 004 — AC-14, AC-15, AC-16

## Verificación

- [x] T-15 `supabase/tests/007_solicitud_aprobacion.sql`, un caso permitido y uno denegado por AC
- [x] T-16 Concurrencia: dos conexiones aprobando la misma solicitud. B se bloqueó
      en el lock de A, re-leyó el estado al liberarse y falló con «solo se aprueba
      desde pending_review (está en setup)». Quedó **un** asiento. Método anotado al
      final de `supabase/tests/007_solicitud_aprobacion.sql`
- [x] T-17 Todos los AC en verde
- [x] T-18 `get_advisors(security)` sin `ERROR`; diff contra `specs/advisor-baseline.md`
- [x] T-19 `get_advisors(performance)` sin `WARN` — ojo a políticas permisivas duplicadas
- [x] T-20 Migraciones espejadas en `supabase/migrations/`, 1:1 con lo aplicado
- [x] T-21 `npm run gen:types`

## Front

- [x] T-22 `organizador/solicitudes.page.ts`: mis eventos agrupados por estado, con lo que requiere acción arriba
- [x] T-23 `organizador/evento-form.page.ts`: ficha + reglas comerciales; en `draft` el botón dice **«Enviar a revisión»**
- [x] T-24 Pantalla de `changes_requested`: la observación de Admin y qué ítems del checklist faltan, en lectura
- [x] T-25 Estado `approved`/`setup`: decir que falta cargar zonas y precios, y que **publicar es decisión del organizador**
- [x] T-26 `admin/solicitudes.page.ts`: cola con `code` en monoespaciada, filtro por estado, prioridad visual a `pending_review`
- [x] T-27 `admin/solicitud-detalle.page.ts`: checklist editable + aprobar / rechazar / pedir info, nota obligatoria en «pedir info»
- [x] T-28 Historial de decisiones de una solicitud, en orden — AC-13
- [x] T-29 Copy de `paused`: «venta pausada — las entradas ya emitidas siguen siendo válidas»
- [x] T-30 Rutas en `app.routes.ts` con `roleGuard('organizer')` y `roleGuard('admin')`
- [x] T-31 `npm run build` limpio

## Cierre

- [x] T-32 007 marcado en `roadmap.md` y `README.md`
- [x] T-33 Defaults en los que se apoya: **D-08** (qué puede editar tras vender), **D-01** (`featured_at` manual, sin algoritmo)
