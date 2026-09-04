# 009 — Plan

El último de Fase 1, y va último porque necesita que existan las cosas de las
que la gente se queja.

## Migraciones

| # | nombre | contenido |
|---|---|---|
| 0049 | `support_cases` | enums, `support_cases`, `support_messages`, RLS |
| 0050 | `support_rpcs` | las cuatro RPC y `v_support_queue` |
| 0051 | `fix_open_case_derived_order` | corrige un 42501 que dejaba al staff fuera |

## Un caso nace desde el objeto, no desde un formulario en blanco

Es la idea entera del feature. El fan pulsa «¿algo va mal con esta entrada?» y
el caso llega a Admin con el ticket, el evento y la orden ya adjuntos. Nadie
teclea un código, y nadie explica su problema desde cero.

**El cliente manda el OBJETO; el contexto lo rellena el servidor** (AC-03). Si
el cliente mandara `event_id` y `order_id`, podría adjuntar los de otro evento y
ensuciar la cola de un organizador ajeno.

### Autorizar un `order_id` deducido no es lo mismo que autorizar uno mandado

Esto costó una migración. La primera versión resolvía la orden desde el ticket
—correcto— y **después la revalidaba** contra quien abre. Para el fan cuadraba;
para el staff no, porque el pedido es del asistente:

```
42501: no puedes abrir un caso sobre ese pedido
```

Y eso cerraba justo la historia 4: la incidencia abierta desde el validador.

La distinción correcta:

- un `order_id` que manda el **cliente** hay que autorizarlo, porque podría ser
  el de cualquiera;
- uno que el **servidor** dedujo de un ticket ya autorizado, no: la autorización
  ya ocurrió sobre el ticket.

Revalidarlo no añadía ninguna seguridad. Solo rompía el caso de uso.

## D-12: no se abren dos vías de recuperación sobre el mismo pago

`refund` (el fan pide a Feventi), `cancellation` (el evento no ocurre) y una
disputa bancaria son **tres procesos distintos**. Si se abren dos a la vez sobre
el mismo pedido, se bloquean entre sí y el fan acaba sin ninguna de las dos.

Se cierra con un **índice único parcial**, no con una validación en la RPC:

```sql
create unique index support_cases_one_recovery_per_order
  on public.support_cases (order_id)
  where kind in ('refund', 'cancellation') and status not in ('resolved', 'closed');
```

Dos peticiones simultáneas pasarían las dos por un `if not exists`. El índice no.

Y es **parcial** a propósito: cerrado el primero se puede abrir otro (AC-07). La
cláusula `where` es la regla, no una optimización.

El mensaje traduce el `unique_violation` a algo accionable —«ya hay un caso de
recuperación abierto para este pedido (#1021)»— porque `duplicate key value
violates unique constraint` no le dice a nadie qué hacer.

### La distinción tiene que estar en la pantalla, no solo en el enum

Si el fan elige mal, se abre la vía equivocada y la correcta queda bloqueada. Por
eso cada tipo lleva una frase que lo separa:

> **Quiero que me devuelvan el dinero** — tú ya no puedes ir, pero el evento SÍ
> se hace.
>
> **El evento se canceló o cambió** — esto NO es lo mismo que pedir un reembolso:
> aquí el problema no lo pusiste tú.

## La nota interna es una columna, no una convención

`support_messages.internal` está protegido por RLS (AC-10, AC-16). El front **no
filtra**: la consulta pide todos los mensajes del caso y la base decide cuáles
salen.

Filtrarlo en el cliente sería fingir una protección que se cae en cuanto alguien
mire la respuesta de red. Y escribirla exige ser Admin, comprobado en la RPC.

## Qué ve cada uno

| | casos | quién los abrió | notas internas |
|---|---|---|---|
| fan | los suyos y los de sus entradas | «yo» | no |
| staff | **solo los que él abrió** | «yo» | no |
| organizador | los de sus eventos | «un asistente» | no |
| Admin | todos | el nombre real | sí |

El staff no ve los casos de sus compañeros a propósito: un caso de puerta puede
citar datos del asistente, y el turno siguiente no tiene por qué leerlos.

El organizador ve el caso pero **no quién lo abrió** (D-06). Por eso
`opened_by` no está en la vista y en su lugar va una etiqueta que depende de
quién consulta.

## `v_support_queue` va con `security_invoker = true`

Y funciona — a diferencia de las seis vistas anteriores del proyecto. La RLS de
`support_cases` ya deja ver exactamente los casos que tocan, y los joins son a
filas que el que consulta o ve, o le salen nulas.

**Cuando invoker basta, se usa invoker.** Las excepciones del
`advisor-baseline.md` existen porque no había alternativa, no porque definer sea
cómodo.

## Corregir es un asiento nuevo (Art. 8.3)

`admin_ticket_action` deja `ticket_events` con `actor_id`, el caso en `meta` y,
si corrige uno anterior, su `corrects_id`. El asiento viejo **se queda**.

En la UI, anular pide dos toques. No es fricción decorativa: no hay deshacer, y
la corrección posterior es otro asiento, no un retroceso.

## Los cinco sitios donde aparece el botón (AC-21)

Wallet (entrada destacada y cada una de las demás), checkout, veredicto del
validador y dashboard del organizador. Nunca hay que buscar un menú: quien tiene
un problema en la puerta no va a navegar.

`/soporte` existe solo para **volver a leer** las respuestas, no para abrir.

En el validador, el botón dice además lo que el staff necesita oír: **la
excepción la autoriza Feventi, no la puerta** (D-05). Sin esa frase, el staff
deja esperando a alguien en la cola creyendo que el caso lo resuelve ahora.

## Lo que NO hace, y se dice

- **No mueve dinero** (AC-08). Un `refund` en Fase 1 se registra y se clasifica;
  la devolución es Fase 2 y D-40…D-42.
- **No promete un tiempo de respuesta** (AC-24, D-45). Prometer «24 h» sin poder
  cumplirlo genera un segundo caso quejándose del primero. Lo que sí se dice es
  el estado y de quién es el turno.
- **No cancela la compra.** El fan lo cree, así que el mensaje de confirmación lo
  dice: «tu compra sigue exactamente como estaba mientras lo revisamos».

## Verificación

`supabase/tests/009_soporte.sql`, 32 comprobaciones. Las que importan:

- **AC-05b**: el mensaje de «ticket ajeno» y el de «ticket inexistente» son
  **idénticos**. Se comparan entre sí, no contra un texto esperado — si
  difirieran, la función sería un oráculo.
- **AC-06/AC-07**: la doble vía se bloquea y se desbloquea al cerrar.
- **AC-04b**: el staff abre un caso sobre un ticket de su evento aunque el
  pedido no sea suyo. Es la que destapó el bug de 0051.
