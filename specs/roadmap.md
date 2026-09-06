# Roadmap

> **Reordenado el 4 de septiembre de 2026** por el acta de reunión: la capa social
> deja de ser Fase 3 y pasa a ser el eje del MVP. Lo que cambió es el **orden**, no
> el contenido: nada de lo social era nuevo, estaba diferido.

## Fase 1 — MVP visible ✅

El eje del Art. 1: **evento → compra → wallet → QR → puerta**, más lo mínimo de
operación para que ese eje exista de verdad (alguien tiene que aprobar el evento y
alguien tiene que atender cuando algo falla).

| # | Feature | Mundo | Pantalla del mockup |
|---|---|---|---|
| [001](001-fundaciones/spec.md) ✅ | Fundaciones: auth, perfiles, roles, tenencia, RLS base | todos | — |
| [002](002-catalogo-publico/spec.md) ✅ | Catálogo público | Público | Catálogo |
| [003](003-detalle-evento/spec.md) ✅ | Detalle de evento: zonas, segmentos, fases, precios | Público | Evento |
| [004](004-checkout-emision/spec.md) ✅ | Checkout y emisión de tickets | Fan | Checkout |
| [005](005-wallet-qr/spec.md) ✅ | Wallet y QR dinámico | Fan | Wallet · QR |
| [006](006-validador-puerta/spec.md) ✅ | Validador de puerta | Staff | Validador |
| [007](007-solicitud-aprobacion/spec.md) ✅ | Solicitud de evento y aprobación | Organizador + Admin | Admin: solicitudes |
| [008](008-dashboard-organizador/spec.md) ✅ | Dashboard del organizador | Organizador | Dashboard |
| [009](009-soporte/spec.md) ✅ | Soporte contextual | Fan + Admin | Admin: soporte |

Orden de construcción obligatorio: **001 → 007 → 003 → 002 → 004 → 005 → 006 → 008 → 009**.

001 primero porque nada tiene RLS sin él. **007 antes que 002/003** aunque sea una
pantalla de operación: sin un evento aprobado y publicado no hay nada que catalogar, y
crear datos de prueba salteándose la aprobación instala el hábito que el Art. 4
prohíbe. 002 después de 003 porque el catálogo es una proyección del detalle.

## Fase 1.5 — Capa social

El acta del 4 de septiembre fija esto como **el diferencial del MVP**: Feventi no es
una ticketera, es una plataforma social de eventos. El efecto que se pide es concreto
y está en el mockup desde el principio: *«2 amigos quieren ir · 1 amigo ya tiene
entrada»* en la ficha del evento.

| # | Feature | Mundo | De dónde sale |
|---|---|---|---|
| [010](010-grafo-social/spec.md) | Grafo social: amistad, bloqueo y modo ninja efectivo | Fan | Art. 7.3 · acta §5, §7 |
| [011](011-senales-sociales/spec.md) | Señales sociales en catálogo y evento | Público + Fan | mockup L92/L153 · acta §6 |
| [012](012-compra-grupal/spec.md) | Compra grupal | Fan | Art. 11 · acta §5 |
| [013](013-puntos-wallet/spec.md) | Puntos por asistencia en la wallet | Fan | mockup L338/L685 · acta §5 |

Orden obligatorio: **010 → 011 → 012 → 013**.

010 primero por la misma razón que 001: sin grafo no hay a quién mostrarle nada, y
**el modo ninja tiene que existir antes que la primera señal**, no después. Una señal
social que se filtra una sola vez ya no se puede retirar.

011 es el efecto wow del acta §6 y se construye entero sobre 010.

012 y 013 son independientes entre sí y pueden ir en cualquier orden; 013 es el más
barato de los cuatro.

### Lo que NO entra en Fase 1.5

- **Comunidades con muro propio.** El acta las pide (§5) y a la vez avisa del riesgo
  (§12.3: «sin convertir la demo en una red social demasiado compleja»). **D-42**:
  se replantean como *seguir a un organizador o a una etiqueta*, que alimenta el
  descubrimiento sin abrir moderación de contenido. Fase 3.
- **Álbum del evento** — D-30, y el propio acta lo pone como fase posterior (§12.6).
- **Ubicación compartida** — D-31, Art. 7.4.
- **Importar contactos externos** — D-38. Sin agenda, sin Google Contacts, sin
  Instagram: es un problema de datos personales que no se abre para una demo.

## Fase 2 — MVP estructural

Cada uno ya tiene su artículo en la constitución, para que su schema no contradiga
Fase 1.

- **Reventa oficial** (Art. 6) — `resale_listings`; invalida el QR del vendedor y emite
  credencial nueva. La pantalla existe en el mockup; solo se corre de fase.
- **Cortesías** (Art. 3) — bolsas, códigos, reclamo, revocación.
- **Finanzas y liquidación** (Art. 5) — tramos 30/40/30, retenciones, estado de pago.
  En Fase 1 `events.payout_policy` guarda la política de forma declarativa y el
  dashboard la muestra; Fase 2 la convierte en `payouts` / `payout_tranches` con
  movimientos reales.
- **Notificaciones sociales** (acta §7) — invitación a grupo, amigo que asistirá.
  Depende de D-11: hoy no existe centro de notificaciones.

> **Grupos de compra** salió de aquí: subió a Fase 1.5 como 012.
> **Perfil y privacidad** salió de aquí: el modo ninja es el corazón de 010.

## Fase 3

Comunidades y seguimiento (D-42) · FanPass y canje de puntos (D-29) · Promotores ·
Grupo de evento · Grupo temporal y ubicación compartida · Álbum del evento y
moderación · Calificación de organizadores (D-26, D-34).

## Fase posterior — no prometer

Álbum automático completo con Instagram · Feed social avanzado · Mapa interno del
venue · Sorteos · Mystery Box · Tienda o saldo monetario · Venta en puerta visible ·
Páginas premium por evento.

Estas no aparecen en la UI ni en el copy hasta estar confirmadas. **Esto incluye a la
demo**: el acta §12.1 pregunta qué funciones quedan «solo representadas
visualmente», y la respuesta por defecto es **ninguna** (D-37). Un botón que no hace
nada delante de un inversor cuesta más caro que una función que falta.

### Definición de terminado, por feature

1. `spec.md` con criterios de aceptación verificables.
2. Migración aplicada; `mcp__supabase__get_advisors(security)` sin hallazgos nuevos.
3. Test de política RLS en SQL: un caso permitido y un caso denegado por cada rol que
   toca la tabla.
4. Tipos de TypeScript regenerados.
5. Pantalla de Angular fiel al mockup, en los tres modos que le corresponden.
6. `tasks.md` con todo marcado, o con la razón anotada de lo que quedó fuera.

## Puerta a producción

**Art. 13.** Fase 1, 1.5 y 2 corren en sandbox. El paso a dinero real es una decisión
de negocio con documento firmado, no un despliegue.
