# Roadmap

## Fase 1 — MVP visible

El eje del Art. 1: **evento → compra → wallet → QR → puerta**, más lo mínimo de
operación para que ese eje exista de verdad (alguien tiene que aprobar el evento y
alguien tiene que atender cuando algo falla).

| # | Feature | Mundo | Pantalla del mockup |
|---|---|---|---|
| [001](001-fundaciones/spec.md) ✅ | Fundaciones: auth, perfiles, roles, tenencia, RLS base | todos | — |
| [002](002-catalogo-publico/spec.md) ✅ | Catálogo público | Público | Catálogo |
| [003](003-detalle-evento/spec.md) ✅ | Detalle de evento: zonas, segmentos, fases, precios | Público | Evento |
| [004](004-checkout-emision/spec.md) ✅ | Checkout y emisión de tickets | Fan | Checkout |
| [005](005-wallet-qr/spec.md) | Wallet y QR dinámico | Fan | Wallet · QR |
| [006](006-validador-puerta/spec.md) | Validador de puerta | Staff | Validador |
| [007](007-solicitud-aprobacion/spec.md) ✅ | Solicitud de evento y aprobación | Organizador + Admin | Admin: solicitudes |
| [008](008-dashboard-organizador/spec.md) | Dashboard del organizador | Organizador | Dashboard |
| [009](009-soporte/spec.md) | Soporte contextual | Fan + Admin | Admin: soporte |

Orden de construcción obligatorio: **001 → 007 → 003 → 002 → 004 → 005 → 006 → 008 → 009**.

001 primero porque nada tiene RLS sin él. **007 antes que 002/003** aunque sea una
pantalla de operación: sin un evento aprobado y publicado no hay nada que catalogar, y
crear datos de prueba salteándose la aprobación instala el hábito que el Art. 4
prohíbe. 002 después de 003 porque el catálogo es una proyección del detalle.

### Definición de terminado, por feature

1. `spec.md` con criterios de aceptación verificables.
2. Migración aplicada; `mcp__supabase__get_advisors(security)` sin hallazgos nuevos.
3. Test de política RLS en SQL: un caso permitido y un caso denegado por cada rol que
   toca la tabla.
4. Tipos de TypeScript regenerados.
5. Pantalla de Angular fiel al mockup, en los tres modos que le corresponden.
6. `tasks.md` con todo marcado, o con la razón anotada de lo que quedó fuera.

## Fase 2 — MVP estructural

Cada uno ya tiene su artículo en la constitución, para que su schema no contradiga
Fase 1.

- **Reventa oficial** (Art. 6) — `resale_listings`; invalida el QR del vendedor y emite
  credencial nueva. La pantalla existe en el mockup; solo se corre de fase.
- **Cortesías** (Art. 3) — bolsas, códigos, reclamo, revocación.
- **Grupos de compra** (Art. 11) — hasta 4, todo o nada, bloqueo al iniciar pago.
- **Finanzas y liquidación** (Art. 5) — tramos 30/40/30, retenciones, estado de pago.
  En Fase 1 `events.payout_policy` guarda la política de forma declarativa y el
  dashboard la muestra; Fase 2 la convierte en `payouts` / `payout_tranches` con
  movimientos reales.
- **Perfil y privacidad** (Art. 7) — modo ninja, notificaciones, permisos sociales.

## Fase 3

FanPass y puntos · Promotores · Grupo de evento · Grupo temporal y ubicación
compartida · Álbum del evento y moderación · Comunidad y señales sociales.

## Fase posterior — no prometer

Álbum automático completo con Instagram · Feed social avanzado · Mapa interno del
venue · Sorteos · Mystery Box · Tienda o saldo monetario · Venta en puerta visible ·
Páginas premium por evento.

Estas no aparecen en la UI ni en el copy hasta estar confirmadas.

## Puerta a producción

**Art. 13.** Fase 1 y 2 corren en sandbox. El paso a dinero real es una decisión de
negocio con documento firmado, no un despliegue.
