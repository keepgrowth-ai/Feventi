# 008 — Tareas

**Estado: listo.** 22 comprobaciones en verde. Build limpio, advisors sin
hallazgos nuevos fuera de los dos `ERROR` argumentados que esta feature añade.

## Backend

| # | qué | dónde |
|---|---|---|
| T-01 | `private.order_commission_cents(orders)` — la fórmula, en un sitio | `0047` |
| T-02 | `v_event_sales` — Art. 5, cuatro conceptos nombrados | `0047` |
| T-03 | `v_event_phase_sales` — con el umbral de 5 (AC-06) | `0047` |
| T-04 | `v_gate_stats` ampliada al organizador | `0047` |
| T-05 | `checkins (event_id, result)` — AC-20 | `0047` |
| T-06 | `grant execute` del helper a `authenticated` | `0048` |

## Front

| # | qué | dónde |
|---|---|---|
| T-07 | `dashboard.store.ts` — tres vistas en paralelo, cero aritmética | `features/organizador/` |
| T-08 | `dashboard.page.ts` — métricas, fases, financiero, accesos | `features/organizador/` |
| T-09 | ruta `/organizador/eventos/:id/panel` | `app.routes.ts` |
| T-10 | enlace desde «Mis eventos», solo si hay algo que ver | `solicitudes.page.ts` |
| T-11 | tipos de las dos vistas nuevas | `db.types.ts` |

## Las decisiones que costaron pensar

### Un criterio del spec estaba equivocado, y se dice por qué

AC-04 pide `security_invoker = true`. Con invoker las vistas salen **en cero**:
agregan cuatro tablas que la RLS le cierra al organizador. Para que funcionara
habría que abrirle esas tablas — que es lo que **AC-02 prohíbe** en la línea
siguiente del mismo spec.

No se puede cumplir los dos. Gana AC-02, porque es la regla de privacidad
(Art. 7.5) y AC-04 solo era el medio que alguien supuso para llegar a ella.

> Un criterio de aceptación que describe un MEDIO puede estar equivocado sin que
> el objetivo lo esté. Cuando dos chocan, el que sobrevive es el que dice qué
> debe pasar, no el que dice cómo.

### «Bruto» no era obvio, y equivocarse cuesta dinero real

El cargo puede pagarlo el fan o absorberlo el organizador. Si «bruto» fuera el
subtotal en los dos casos, restar la comisión **cobraría dos veces** a quien ya
la trasladó al fan.

Se definió bruto = lo cobrado al fan, y así `neto = bruto − comisión −
devoluciones` vale en ambos. Hay un evento de cada tipo en la suite: con uno
solo, la fórmula parece correcta y está mal para la mitad de los eventos.

### La misma lección de `0025`, otra vez

`v_event_sales` daba `42501: permission denied for function
order_commission_cents`.

Una vista `security definer` corre con los privilegios de su dueño **para las
tablas**; el `EXECUTE` de las funciones que llama se comprueba contra el rol que
consulta. Ya había pasado en `0025` con `total_with_charge` y `anon`.

> Definer no es un pase general. Añadido a «lo que el linter no ve» del
> `advisor-baseline.md`, porque es la segunda vez que se paga.

### `paid_at`, no `status = 'paid'`

En Fase 2 una orden reembolsada pasará a `refunded` y su dinero **sí se cobró**.
Filtrar por `status = 'paid'` la sacaría del bruto y la dejaría en devoluciones:
restada dos veces. Es un bug que hoy no se puede observar —nada produce
reembolsos todavía— y que habría aparecido el primer día de Fase 2.

### El `filter` que faltaba en las fases

`count(oi.id)` sobre un `LEFT JOIN` a `orders` cuenta también las líneas cuya
orden no casó — es decir, las reservas sin pagar. Un LEFT JOIN que no encuentra
pareja no borra la fila izquierda.

Corregido a `count(oi.id) filter (where o.id is not null)`. Sin eso, una fase
recién abierta muestra ventas que nadie pagó.

## Lo que queda fuera, y por qué

- **AC-20 sin comprobar.** Los tiempos con 50 000 tickets necesitan un volumen
  que la suite no siembra. Los índices que pide existen; medir de verdad es una
  tarea con datos de carga, no una comprobación de esta suite.
- **Cortesías: métrica en «—».** El módulo es Fase 2. Se deja el hueco rotulado
  en vez de un cero, que se leería como «nadie reclamó».
- **Sin exportación** (D-07) y **sin multi-evento** (Fase 2), como dice el spec.
- **`v_gate_stats` no separa por turno.** Con un evento al día da igual; el día
  que un venue haga dos funciones seguidas habrá que meter la ventana en la
  vista. Anotado también en 006.
