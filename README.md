# Feventi

Ticketera web **B2B2C** para eventos. El eje del producto es
**evento → compra → wallet → QR → puerta**; todo lo demás es periferia y no puede
romper ese eje.

Angular 22 + Supabase. Desarrollo **spec-driven**: primero el spec con criterios de
aceptación verificables, después el código.

---

## Empezar por aquí

| archivo | qué es |
|---|---|
| [`specs/constitution.md`](specs/constitution.md) | **las 13 reglas no negociables.** Si una tarea contradice un artículo, la tarea está mal |
| [`specs/roadmap.md`](specs/roadmap.md) | qué toca ahora, en qué orden, y qué cuenta como terminado |
| [`specs/data-model.md`](specs/data-model.md) | el schema compartido por todos los features |
| [`specs/design-system.md`](specs/design-system.md) | color, tipografía, los tres modos visuales, patrones |
| [`specs/decisiones-pendientes.md`](specs/decisiones-pendientes.md) | lo que aún no está decidido, con su **default seguro** |
| [`specs/advisor-baseline.md`](specs/advisor-baseline.md) | hallazgos del linter aceptados, cada uno con su razón |
| [`CLAUDE.md`](CLAUDE.md) | instrucciones para trabajar en este repo |

## Estado

| # | Feature | Estado |
|---|---|---|
| 001 | Fundaciones: auth, perfiles, roles, tenencia, RLS base | ✅ **listo** — 43 comprobaciones en verde |
| 007 | Solicitud de evento y aprobación | ✅ **listo** — 32 comprobaciones + concurrencia |
| 003 | Detalle de evento: zonas, segmentos, fases, precios | ✅ **listo** — 56 comprobaciones |
| 002 | Catálogo público | ✅ **listo** — 25 comprobaciones |
| 004 | Checkout y emisión de tickets | ✅ **listo** — 52 comprobaciones + 4 de concurrencia + compra e2e |
| 005 | Wallet y QR dinámico | ✅ **listo** — 17 comprobaciones por HTTP |
| 006 | Validador de puerta | ✅ **listo** — 40 comprobaciones + 25 por HTTP, con doble escaneo en paralelo |
| 008 | Dashboard del organizador | ✅ **listo** — 22 comprobaciones, con los dos modelos de cargo |
| 009 | Soporte contextual | ✅ **listo** — 32 comprobaciones, con la doble vía cerrada por índice |

Orden de construcción: **001 → 007 → 003 → 002 → 004 → 005 → 006 → 008 → 009**.

## La demo de la presentación

**https://feventi-250048151842.us-central1.run.app**

Dos cuentas, una por dispositivo. La del portátil lleva los tres roles de gestión
para no tener que cerrar sesión durante el recorrido.

| dispositivo | cuenta | clave | rol |
|---|---|---|---|
| móvil | `camila@feventi.demo` | `Feventi2026!` | compradora |
| portátil | `operaciones@feventi.demo` | `Feventi2026!` | puerta · organizador · Feventi |

El escenario lo siembra `supabase/seed/demo_presentacion.sql`, y **no caduca**: un
trabajo de `pg_cron` recoloca el evento cada medianoche y devuelve las entradas
usadas a activas, así que el recorrido se puede repetir cualquier día sin
preparar nada.

> Los pagos siguen en sandbox (Art. 13). No se procesa ningún cobro real.

## Desplegar

`docs/DESPLIEGUE.md` — GitHub, Cloud Run y la conexión con Supabase, paso a paso.

Lo que sale de ahí es una **demo**: los pagos están en sandbox (Art. 13) y la
base tiene datos de prueba. Lo que falta para abrir la venta real está al final
de ese documento, y en su mayoría no es código.
El por qué está en el roadmap.

## Estructura

```
specs/                  la fuente de verdad del producto
  constitution.md
  NNN-slug/             spec.md (QUÉ) · plan.md (CÓMO) · tasks.md (checklist)
supabase/
  migrations/           inmutables; una aplicada se corrige con otra, no se edita
  tests/                pruebas de política RLS, un caso permitido y uno denegado por AC
apps/web/               Angular 22, standalone, signals, zoneless, Tailwind v4
docs/sources/           la guía funcional y los mockups originales
```

## Comandos

```bash
npm install
npm run dev            # Angular en :4200
npm run build
npm run gen:types      # regenera apps/web/src/app/core/db.types.ts desde el schema
```

Las migraciones y las pruebas se operan con las herramientas MCP de Supabase:
`apply_migration` para DDL, `execute_sql` para las pruebas de
`supabase/tests/*.sql`, y `get_advisors(security)` al cerrar cada feature.

## Supabase

Proyecto `Feventi`, ref `orirleaujhpewiowaanq`, región us-west-2.

En el bundle solo va la **publishable key**. La `service_role` no aparece jamás en el
front (Art. 9.3): lo que necesita privilegio vive en una Edge Function.

## Antes de producción

**Art. 13.** Nada de dinero real hasta cerrar por escrito: política de cancelaciones,
de reembolsos, tratamiento de cargos de pasarela, retenciones, garantías, calendario de
liquidación, soporte de emergencia durante evento, responsabilidad ante fraude y
protocolo de operación en puerta. Ver **D-40 … D-49**.

Hasta entonces, sandbox: `payments.provider = 'culqi_sandbox'`.
