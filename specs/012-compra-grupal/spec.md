# 012 — Compra grupal

**Mundo:** Fan · **Pantalla del mockup:** «Checkout» (grupo) ·
**Depende de:** 010, 004 · **Bloquea a:** —

El acta §5: *«La plataforma debe permitir o al menos mostrar la idea de comprar
con amigos, formar grupo y coordinar asistencia»*. Con D-37 vigente —nada es
maqueta— se construye.

Las reglas duras ya estaban fijadas en el **Art. 11** desde el primer día:

> Grupo de compra: hasta **4** personas, atado a evento y fecha, **todo o nada**
> en el MVP. Si alguien inicia el pago el grupo se bloquea; si el pago falla o
> expira, se libera la reserva.

---

## La idea que hace esto pequeño

**«Todo o nada» ya existe: es una orden con N ítems.**

`reserve_order` bloquea los tiers en orden, congela el precio, sube el contador y
calcula el cargo, todo en una transacción. Si falla, no queda media compra. Eso
*es* el todo-o-nada del Art. 11.

Así que el grupo **no es un mecanismo de compra**. Es la capa que decide **quién
entra** y luego le entrega a la compra que ya funciona una lista de personas. No
se toca `reserve_order` ni `confirm_payment`: las dos funciones más verificadas
del checkout se quedan como están.

## Objetivo

Que hasta cuatro amigos compren juntos en una sola operación, y que **cada uno
reciba su entrada en su propia wallet**.

## No objetivos

- Que cada miembro pague su parte. Eso son cuatro pagos que pueden fallar por
  separado, es decir, lo contrario del todo-o-nada. Paga uno.
- Grupo de evento (coordinar asistencia sin comprar): **D-21/D-22**, Fase 3.
- Chat de grupo, ubicación compartida: **D-31**, Fase 3.
- Invitar a alguien que no es amigo: sin grafo no hay grupo. Se añade desde la
  lista de amigos y de ningún otro sitio.
- Cambiar de zona por miembro: los cuatro van a la misma zona. Un grupo con
  cuatro zonas distintas no es un grupo, son cuatro compras.

---

## Lo que hace que cada uno reciba SU entrada

Este es el detalle que decide si la función es real o decorativa.

Si la compra la paga una persona, `confirm_payment` emite los cuatro tickets con
`owner_id = comprador`. Los otros tres tendrían su nombre impreso pero **la
entrada no estaría en su wallet**, no podrían enseñar su QR y no contarían como
«va» en la señal social de 011. La función quedaría en el folleto.

La solución no es transferir después. Es que **el ticket nazca con su dueño**:

1. Al bloquear el grupo se emparejan sus miembros con los `order_items` de la
   orden. Cada miembro se queda con un ítem: `group_members.order_item_id`.
2. Un trigger `before insert` sobre `tickets` mira si el `order_item_id` tiene
   miembro. Si lo tiene, escribe `owner_id` y `original_owner_id` con esa
   persona **antes** de que la fila exista.

No hay transferencia, no hay asiento de corrección, no hay ventana en la que la
entrada sea de otro. Y `orders.buyer_id` sigue siendo quien pagó, así que la
comisión y el dashboard del organizador no se enteran de nada.

---

## Modelo de datos

### `purchase_groups`

| col | tipo | nota |
|---|---|---|
| `id` | uuid PK | |
| `event_id` | uuid → events | el grupo está atado al evento (Art. 11) |
| `creator_id` | uuid → profiles | quien invita y quien paga |
| `status` | `purchase_group_status` | `open` · `locked` · `completed` · `cancelled` |
| `order_id` | uuid → orders | null mientras `open` |
| `created_at`, `locked_at` | timestamptz | |

```sql
-- Bloqueado y con orden van juntos, en los dos sentidos.
constraint purchase_groups_locked_has_order
  check ((status in ('locked','completed')) = (order_id is not null))
```

### `group_members`

| col | tipo | nota |
|---|---|---|
| `group_id` | uuid | |
| `user_id` | uuid → profiles | |
| `event_id` | uuid → events | **denormalizado** |
| `slot` | smallint 1–4 | el arbitro del «hasta 4» |
| `order_item_id` | uuid → order_items | se rellena al bloquear |
| `joined_at` | timestamptz | |

Tres garantías, las tres en índices y no en comprobaciones:

```sql
-- Art. 11: hasta 4. El slot lo asigna la RPC bajo candado; si dos entran a la
-- vez y calculan el mismo, el índice tumba a uno.
unique (group_id, slot)  +  check (slot between 1 and 4)

-- Una persona, un grupo por evento.
create unique index group_members_one_group_per_event
  on public.group_members (user_id, event_id);

-- Lección de 0045: un event_id denormalizado junto a una FK simple no obliga a
-- nada. La FK compuesta obliga a que el grupo sea DE ESE evento.
foreign key (group_id, event_id) references public.purchase_groups (id, event_id)
```

---

## Las operaciones

| RPC | quién | qué comprueba |
|---|---|---|
| `create_purchase_group(event_id)` | cualquiera con sesión | el evento existe y está publicado; el creador entra como slot 1 |
| `add_group_member(group_id, user_id)` | solo el creador | grupo `open`; **son amigos** (`private.are_friends`); quedan slots |
| `leave_purchase_group(group_id)` | cualquier miembro | grupo `open`. Si se va el creador, el grupo se cancela entero |
| `lock_purchase_group(group_id, order_id)` | solo el creador | grupo `open`; la orden es suya, del mismo evento y tiene **exactamente** tantos ítems como miembros |

Todas `security definer`, todas con `select … for update` sobre el grupo antes
de mirar su estado.

**Requerir amistad no es un adorno.** Sin ella, `add_group_member` acepta
cualquier uuid y se convierte en la forma de meter a alguien en una compra que
no pidió — y, de paso, de averiguar qué uuid existen.

---

## Criterios de aceptación

| # | Criterio | Cómo se verifica |
|---|---|---|
| AC-01 | Crear grupo mete al creador como slot 1 | SQL |
| AC-02 | El creador añade a un amigo: entra como slot 2 | SQL |
| AC-03 | Añadir a quien **no es amigo** falla | SQL |
| AC-04 | Un quinto miembro falla (Art. 11) | SQL |
| AC-05 | Quien no es el creador no puede añadir | SQL |
| AC-06 | La misma persona no entra en dos grupos del mismo evento | SQL |
| AC-07 | Sí puede estar en grupos de eventos distintos | SQL |
| AC-08 | Un miembro puede salir mientras el grupo está `open` | SQL |
| AC-09 | Si sale el creador, el grupo queda `cancelled` y sin miembros | SQL |
| AC-10 | Bloquear con una orden de otro evento falla | SQL |
| AC-11 | Bloquear con menos ítems que miembros falla | SQL |
| AC-12 | Bloquear pone `locked`, `order_id` y reparte los `order_item_id` | SQL |
| AC-13 | Con el grupo `locked`, añadir o salir falla | SQL |
| AC-14 | **Al pagar, cada ticket nace con su miembro como dueño** | SQL |
| AC-15 | `orders.buyer_id` sigue siendo quien pagó | SQL |
| AC-16 | Un ticket sin miembro (compra normal) no cambia de dueño | SQL |
| AC-17 | Nadie ve grupos ajenos | SQL |
| AC-18 | Nadie escribe `group_members` ni `purchase_groups` a mano | SQL |
| AC-19 | `anon` no lee nada | SQL |
| AC-20 | El grupo pasa a `completed` cuando su orden se paga | SQL |
