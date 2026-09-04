# 008 — Plan

Una pantalla de solo lectura, y aun así la más delicada del mundo organizador:
aquí se dice cuánto dinero hay. El riesgo no es técnico, es de lectura.

## Migraciones

| # | nombre | contenido |
|---|---|---|
| 0047 | `organizer_dashboard_views` | `order_commission_cents`, `v_event_sales`, `v_event_phase_sales`, `v_gate_stats` ampliada, índice |
| 0048 | `grant_order_commission_to_authenticated` | corrige un `42501` de 0047 |

Sin tablas nuevas. Todo lo que el dashboard muestra ya está en la base; lo que
faltaba era **leerlo agregado**.

## Qué es «bruto», y por qué no es obvio

Esta es la decisión que sostiene el resumen financiero entero.

| `service_charge_payer` | el fan paga | Feventi cobra | el organizador recibe |
|---|---|---|---|
| `fan` | subtotal + cargo | el cargo | el subtotal |
| `organizer` | subtotal | el cargo, **al organizador** | subtotal − cargo |

Si «bruto» fuera el subtotal en los dos casos, restarle la comisión **cobraría
dos veces** al organizador que ya la trasladó al fan. Por eso:

> **bruto = lo que se cobró al fan** (`orders.total_cents`)

y entonces `neto = bruto − comisión − devoluciones` se cumple literalmente en
los dos casos. Hay un evento de cada tipo en la suite, porque con uno solo la
fórmula parece correcta y está mal para la mitad de los eventos.

**La comisión sale del bps congelado en la ORDEN, no del evento** (AC-10).
Cambiar la política mañana no puede reescribir lo que ya se vendió. Y cuando el
organizador absorbe el cargo, `service_charge_cents` de la orden vale **cero**
—la orden guarda lo que pagó el fan, y el fan no lo pagó— así que ahí se
recalcula desde el subtotal.

Va en `private.order_commission_cents(orders)` y no repetida en la vista porque
Fase 2 la va a necesitar para la liquidación real: dos copias de esa fórmula son
dos números distintos en dos pantallas, con el organizador reclamando y con
razón.

## `paid_at is not null`, no `status = 'paid'`

En Fase 2 una orden reembolsada pasará a `refunded` y **su dinero sí se cobró**.
Filtrar por `status = 'paid'` la sacaría del bruto y la dejaría en devoluciones:
restada dos veces. El filtro correcto es «se cobró alguna vez», y las
devoluciones se cuentan aparte desde `payments`.

## AC-04 contra AC-02: gana AC-02

El spec pide `security_invoker = true` en las vistas «para que la RLS del
organizador se aplique dentro y no la esquive» (AC-04).

Con invoker, las vistas salen **en cero**. Agregan `orders`, `order_items`,
`payments` y `tickets`, y la RLS de esas cuatro no le deja al organizador ni una
fila — la misma trampa que dejó vacía la wallet en `0042`.

Para que invoker funcionara habría que darle políticas de lectura sobre esas
tablas. Y eso es **exactamente lo que AC-02 prohíbe**. Los dos criterios no
pueden cumplirse a la vez.

Gana AC-02: es la regla de privacidad del Art. 7.5, y AC-04 solo era el medio
que se supuso para llegar a ella. Las vistas van `definer` con
`e.organizer_id = any (private.auth_organizer_ids())`, que es más estrecho que
cuatro políticas nuevas y cabe en una línea auditable. Anotado en
`advisor-baseline.md` y verificado en las dos direcciones (AC-01 … AC-02d).

## El umbral de 5 en las fases

Una fase con 1 a 4 entradas vendidas no se expone sola: se suma a «Otras fases».
Con dos entradas en una fase de un evento pequeño, quien conozca a los
compradores los identifica.

El coste es real y está dicho en la pantalla, no escondido: un evento recién
abierto puede tener todas sus fases por debajo del umbral y mostrar una sola
barra. Es preferible a un umbral variable según el tamaño del evento — una regla
que nadie recuerda al mirar la pantalla.

Y el importe **no se pierde**: la suma por fase sigue cuadrando con el subtotal
del evento (AC-06b lo comprueba).

## `v_gate_stats` se amplía, no se duplica

006 la creó filtrada a `event_staff`. El organizador no es staff de su propio
evento —y no debe serlo— pero necesita los accesos en vivo.

Se añadió un segundo `exists` en lugar de crear `v_organizer_gate_stats`: dos
vistas que cuentan lo mismo se desincronizan el día que alguien corrija una.

Sigue siendo `definer`, y aquí la razón es la más fuerte de todas: `checkins`
guarda `scanned_code`, **el token crudo de cada escaneo**. Abrir esa tabla al
organizador para que pueda contar cuatro números sería regalarle la credencial
de cada asistente.

## La pantalla

Tres reglas de copy que son criterios, no estilo:

1. **La palabra «disponible» no aparece** (AC-13). El riesgo principal del Art. 5
   es que el organizador lea el neto estimado como plata suya y la gaste. Cada
   sitio donde sale ese número dice «estimado».
2. **Los tramos van sin fecha de pago** (AC-14). Poner una fecha sería prometer
   lo que no existe hasta Fase 2.
3. **Vendido y validado en bloques distintos.** «Vendí 800, ¿por qué el aforo
   dice 40 %?» es una llamada a soporte evitable con dos rótulos claros.

Y una cuarta que no estaba en el spec pero se deduce de él: **explicar el hueco**.
El organizador espera ver a sus compradores. La pantalla dice en una línea por
qué no los verá, en vez de dejar un vacío que parece un bug.

> El enlace al panel solo aparece cuando el evento vende, está pausado o
> terminó. Un dashboard de ceros sobre un borrador invita a un clic que
> decepciona.

## Lo que el front NO hace

No hay aritmética de dinero. `net_estimated_cents` llega calculado; restarlo aquí
sería tener la fórmula en dos sitios.

La única cuenta del cliente es el **porcentaje de un tramo** sobre un importe que
ya vino del servidor — y es una estimación rotulada como tal, no un pago, así que
su redondeo no puede descuadrar nada.

## Verificación

`supabase/tests/008_dashboard_organizador.sql`, 22 comprobaciones. Las dos que
importan de verdad:

- **que no se cobre dos veces la comisión** — con un evento de cada tipo de
  cargo, no con uno;
- **que el organizador no llegue a una fila individual** — contra las cuatro
  tablas por separado, y la de columnas contra `information_schema`, para que una
  columna nueva con nombre delator falle la prueba sola.

AC-20 (tiempos con 50 000 tickets) no está: necesita un volumen que la suite no
siembra. Los índices que pide existen.
