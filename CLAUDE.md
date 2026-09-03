# Feventi

Ticketera B2B2C para eventos. Angular 20 + Supabase. Desarrollo **spec-driven**.

## Antes de escribir código

Lee, en este orden:

1. `specs/constitution.md` — reglas no negociables. Si una tarea contradice un
   artículo, **la tarea está mal**.
2. `specs/roadmap.md` — qué toca ahora y en qué orden.
3. `specs/data-model.md` — el schema compartido.
4. `specs/NNN-*/spec.md` del feature en curso.

`specs/decisiones-pendientes.md` tiene lo que aún no está decidido, con su **default
seguro**. Ante una duda de producto, se busca ahí antes de inventar.

## Ciclo de trabajo

```
spec.md  →  plan.md  →  tasks.md  →  migración  →  test RLS  →  tipos  →  UI
```

- Ninguna migración ni componente entra sin criterios de aceptación verificables.
- **Migraciones inmutables.** Una aplicada no se edita; se corrige con otra.
- `db.types.ts` se **genera** (`npm run gen:types`). Editarlo a mano es un error.
- Cada feature cierra con `get_advisors(security)` limpio.

## Reglas que se rompen sin querer

- **RLS en la misma migración que crea la tabla.** Nunca después: entre las dos hay una
  ventana abierta.
- **`(select auth.uid())`**, no `auth.uid()`, dentro de una política. Envuelto, el
  planner lo evalúa una vez como InitPlan en lugar de una vez por fila.
- **Una sola política por operación y rol**, con los casos unidos por `OR` y el caso
  común primero. Dos políticas permisivas se evalúan las dos, siempre.
- **El rol no se lee del cliente.** Sale de `user_roles` / `organizer_members` /
  `event_staff` vía helper `security definer` en el schema `private`.
- **Un `revoke` de columna no recorta un `grant` de tabla.** Si hay que esconder un
  campo, va en su propia tabla con RLS y cero políticas — como `profile_identity`.
- **Los privilegios por defecto están invertidos** (migración `0009`): la tabla nueva
  nace con `select` para `authenticated` y nada para `anon`. Concede lo que necesites,
  explícitamente.
- **Nada de `service_role` en el front.** Lo privilegiado va en Edge Function.
- **Dinero en céntimos enteros.** El front formatea; no calcula.
- **Sin ticket antes del pago confirmado**, y la UI no lo insinúa.
- **`checkins` y `*_events` son append-only.** Sin `delete` para nadie.

## Comandos

```bash
npm run dev          # Angular en :4200
npm run gen:types    # regenera db.types.ts desde el schema
npm run test:rls     # corre supabase/tests/*.sql
npm run build
```

## Supabase

Proyecto `Feventi` — ref `orirleaujhpewiowaanq` (us-west-2). Se opera con las
herramientas MCP `mcp__supabase__*`: `apply_migration` para DDL, `execute_sql` para
consultas y tests, `get_advisors` para el cierre de cada feature.

## Fuentes

`docs/sources/` — la guía funcional (PDF y texto extraído) y los mockups
`.dc.html`. Si un spec y el mockup discrepan, **manda el mockup** y se corrige el spec.
