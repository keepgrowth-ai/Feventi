# 009 — Tareas

**Estado: listo.** 32 comprobaciones en verde. Build limpio, `service_role`
ausente del bundle, advisors **sin ningún hallazgo nuevo** — 009 no añade ni un
`ERROR`.

Con esto cierra **Fase 1**: los nueve features del roadmap están construidos y
verificados.

## Backend

| # | qué | dónde |
|---|---|---|
| T-01 | enums `support_kind`, `support_status`, `support_priority` | `0049` |
| T-02 | `support_cases` con los CHECK de contexto (AC-01, AC-02) | `0049` |
| T-03 | `support_messages`, append-only | `0049` |
| T-04 | el índice único parcial de D-12 | `0049` |
| T-05 | RLS de las dos tablas | `0049` |
| T-06 | `open_support_case` — AC-03, AC-04, AC-05 | `0050`, corregida en `0051` |
| T-07 | `post_support_message` — AC-16 | `0050` |
| T-08 | `manage_support_case` — AC-15, AC-18 | `0050` |
| T-09 | `admin_ticket_action` — AC-19, Art. 8.3 | `0050` |
| T-10 | `v_support_queue`, con `security_invoker = true` | `0050` |

## Front

| # | qué | dónde |
|---|---|---|
| T-11 | `support.store.ts` — RPC, tipos y el copy de los diez tipos | `features/soporte/` |
| T-12 | `support-button.ts` — el botón con contexto, incrustable | `shared/ui/` |
| T-13 | `mis-casos.page.ts` — el lado del usuario | `features/soporte/` |
| T-14 | `soporte.page.ts` — la cola de Admin | `features/admin/` |
| T-15 | el botón en wallet, checkout, validador y dashboard (AC-21) | 4 archivos |
| T-16 | rutas `/soporte` y `/admin/soporte` | `app.routes.ts` |
| T-17 | tipos de las dos tablas, la vista, las 4 RPC y los 3 enums | `db.types.ts` |

## Lo que salió mal, y qué se aprendió

### Autorizar dos veces cerró el caso de uso principal

`open_support_case` resolvía el `order_id` desde el ticket —correcto, es AC-03—
y **después lo revalidaba** contra quien abre. El staff se llevaba un 42501 al
reportar una entrada de su propia puerta, que es la historia 4 del spec.

La distinción que faltaba: un `order_id` que manda el **cliente** hay que
autorizarlo; uno que el **servidor** dedujo de un objeto ya autorizado, no.

> Repetir una comprobación no es «más seguro» por defecto. Si la primera ya
> respondió la pregunta, la segunda solo puede decir que no a algo que debía
> pasar.

Corregido en `0051`, con una comprobación para cada rama: el pedido mandado por
un fan ajeno sigue fallando, y el del staff pasa.

### `perform` no existe en SQL plano

Un `perform` en el arnés dio `42601: syntax error at or near "perform"`. Es
sintaxis de **plpgsql**, no de SQL. En un archivo `.sql` que se ejecuta directo,
llamar a una función que devuelve `void` se hace con `select`.

Trivial, pero costó una corrida entera de la suite.

### Una comprobación que llama a la función que después consulta

Esta vale para todo el proyecto:

```sql
-- NO funciona
(select corrects_id from public.ticket_events
  where id = public.admin_ticket_action(...)) = ...
```

La función escribe una fila en `ticket_events`, y la consulta que la envuelve ya
fijó su snapshot sobre esa misma tabla: **la fila recién insertada no es visible
para el `where` que la busca**. Devuelve nulo y la comprobación falla — por la
prueba, no por el producto.

La forma correcta es llamar en un statement, guardar el id, y comprobar en el
siguiente. Anotado en la cabecera del archivo de pruebas.

### `anon` da «permission denied», no «cero filas»

AC-14 esperaba que `anon` viera cero casos. Lo que pasa es mejor: la migración
`0009` le quitó el `select` por defecto, así que ni llega a evaluar la política.
La comprobación se reescribió para pedir el fallo, que es lo que de verdad
ocurre.

## Una decisión de diseño que no estaba en el spec

**El staff no ve los casos de sus compañeros**, solo los que él abrió (AC-12 lo
pedía, pero no decía por qué). La razón: un caso de puerta puede citar datos del
asistente —nombre, últimos dígitos del documento— y el turno siguiente no tiene
por qué leerlos. La política no tiene una rama para «staff del evento» a
propósito.

## Lo que queda fuera, y por qué

- **El dinero no se mueve** (AC-08, D-40…D-42). Un `refund` se registra y se
  clasifica; la devolución es Fase 2.
- **Sin SLA** (AC-24, D-45). Prometer un tiempo que no se puede cumplir genera un
  segundo caso quejándose del primero.
- **Sin chat en vivo, teléfono ni base de conocimiento**, como dice el spec.
- **Las excepciones de puerta las ejecuta Admin** (D-05). El staff las **pide**
  desde el veredicto, y la pantalla se lo dice para que no deje esperando a
  alguien en la cola.
- **`assigned_to` se escribe pero no hay pantalla para elegir a quién.** Con un
  solo Admin no hace falta un selector de personas; la RPC ya lo acepta cuando lo
  haya.
