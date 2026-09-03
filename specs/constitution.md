# Constitución de Feventi

Reglas no negociables. Todo `spec.md`, `plan.md`, migración y componente se valida
contra este archivo. Si una tarea contradice un artículo, **la tarea está mal**: se
cambia la constitución primero, por decisión explícita y con fecha.

Fuentes: `docs/sources/guia-funcional.txt` (Guía explicativa funcional, v. 7 jul 2026)
y `docs/sources/mockups/Feventi Pantallas Principales.dc.html` (mockups FVT-R0.8.0).

---

## Art. 1 — Qué es Feventi

Ticketera web **B2B2C** para eventos. Cinco mundos, un solo backend:

| Mundo | Quién | Qué hace |
|---|---|---|
| Público | visitante sin cuenta | descubre eventos y decide comprar |
| Fan | comprador autenticado | compra, guarda, coordina, asiste |
| Organizador | productor | crea, configura y opera eventos |
| Staff | personal de puerta | valida accesos con QR |
| Admin | equipo interno Feventi | aprueba, supervisa, resuelve, protege el dinero |

El recorrido central es **evento → compra → wallet → QR → puerta**. Todo lo demás es
periferia y no puede romper ese eje.

## Art. 2 — El ticket es una credencial viva, no un archivo

1. Un ticket **solo existe después de un pago confirmado**. Antes del pago no se emite
   ticket, no se genera QR y **la UI no puede afirmar que existe entrada válida**.
2. El QR es **dinámico y rotativo** (ventana por defecto **30 s**). Se sirve únicamente
   a la wallet autenticada del propietario.
3. Un QR **no se descarga, no se exporta como imagen y no se comparte**. Una captura de
   pantalla debe fallar en puerta, y el mensaje de error debe decir por qué.
4. El QR se **inhabilita** en cuanto el ticket se transfiere, se publica en reventa, se
   cancela, se reembolsa o se usa.
5. El QR puede tener **ventana de activación** (`events.qr_lead_days`). Fuera de esa
   ventana la wallet muestra el ticket pero no el QR, y dice desde cuándo estará.
6. El secreto criptográfico del ticket **nunca sale de la base de datos**. No es
   legible por `anon` ni por `authenticated`, ni por el propietario. Vive en una tabla
   aparte con RLS de negación total y solo lo toca el servidor.

## Art. 3 — El código de cortesía no es un QR

Un código de cortesía **se reclama** con una cuenta Feventi y se convierte en un ticket
dentro de la wallet. Nunca es la credencial de acceso. Estados obligatorios: válido,
usado, vencido, revocado, agotado.

## Art. 4 — Ninguna solicitud se publica sola

1. Un evento creado por un organizador nace en `draft` y **no vende nada** hasta que
   Admin lo aprueba y se publica.
2. Enviar una solicitud a revisión **no publica el evento**.
3. Toda decisión de Admin (aprobar, rechazar, pedir info) deja **evidencia trazable**:
   quién, cuándo, qué observó, sobre qué versión.
4. Un cambio sensible sobre un evento que **ya vendió entradas** (zonas, precios, fecha,
   aforo, venue) requiere control de Feventi. No es autoservicio del organizador.

## Art. 5 — El dinero se nombra con precisión

Prohibido presentar un número ambiguo. Se distingue siempre:

- **venta bruta** — lo que pagaron los fans
- **comisión Feventi** — `events.service_charge_bps`, por defecto **600** (6 %)
- **cargo de servicio** — lo paga el fan o lo absorbe el organizador
  (`events.service_charge_payer`), y **se muestra desde el primer paso** de la compra
- **devoluciones**, **retenciones**, **fondos congelados**
- **neto estimado** — no es dinero disponible
- **liquidado / pagado** — dinero que ya salió

`estimado ≠ disponible`. La UI no puede usar las dos palabras como sinónimos. Todo
importe se guarda en **céntimos, entero** (`*_cents`), con `currency` explícito (`PEN`
por defecto). Nunca coma flotante para dinero.

## Art. 6 — Reventa oficial, contenida

1. La reventa oficial vive **separada visualmente** de la venta primaria.
2. Precio de reventa **≤ precio original** pagado por el ticket emitido.
3. Máximo **2 reventas por ticket** (`events.max_resales`, por defecto 2).
4. Al completar una reventa: el QR del vendedor **se invalida** y se emite **credencial
   nueva** para el comprador. No se transfiere el mismo QR.
5. El pago al vendedor queda **retenido hasta 24 h después del evento**.
6. Comisión de reventa visible y descontada al vendedor (por defecto 10 %).

## Art. 7 — Identidad y datos personales

1. El **DNI se guarda hasheado** (`dni_hash`) más `dni_last4` para mostrar. El DNI en
   claro no se persiste en el esquema `public`.
2. El DNI se usa para **nominación** y **validación en puerta**, para nada más.
3. **Modo ninja** oculta la actividad social de un fan frente a otros usuarios. **No**
   desactiva controles de seguridad, validación, antifraude ni auditoría interna.
4. La ubicación compartida es **opcional, temporal y revocable**. Nunca se activa sola.
5. El organizador ve datos **agregados** de su evento. El acceso a datos individuales
   es una decisión pendiente y hasta que se cierre **se deniega por defecto**.

## Art. 8 — Todo lo que audita, no se borra

1. `checkins`, decisiones de Admin, cambios de titularidad y movimientos de dinero son
   **append-only**. No hay `DELETE` para staff ni para organizador.
2. Retirar acceso a un miembro del staff **no borra su historial** de acciones.
3. Corregir un registro auditado es un **asiento nuevo** que referencia al anterior,
   con actor y motivo.

## Art. 9 — Seguridad de datos: denegar por defecto

1. **RLS habilitada en toda tabla de `public`.** Una tabla sin política es una tabla
   inaccesible, y ese es el comportamiento correcto.
2. El rol de un usuario **nunca** se lee del cliente ni de un campo que él pueda
   editar. Vive en `user_roles` / `organizer_members` / `event_staff` y se resuelve en
   el servidor con funciones `SECURITY DEFINER`, `STABLE` y con `search_path` fijo.
3. La clave `service_role` **no aparece jamás** en el bundle de Angular. Lo que
   necesita privilegio vive en una Edge Function.
4. Emisión de tickets, rotación y validación de QR, confirmación de pago y aprobación
   de evento son **operaciones de servidor**. El cliente pide; no decide.
5. Toda escritura con reglas de negocio pasa por una función de base de datos o una
   Edge Function transaccional, no por un `UPDATE` suelto desde el cliente.

## Art. 10 — Tres modos visuales, un solo sistema

| Modo | Dónde | Cómo se siente |
|---|---|---|
| **Fan / Público** | home, catálogo, evento, checkout, wallet, perfil | blanco y pastel, juvenil, mobile-first, cards y tickets, gradientes coral → violeta → turquesa |
| **Operación** | paneles de organizador y admin, reportes, soporte, finanzas | profesional, ordenado, navy, cards blancas, tablas, métricas, estados |
| **Puerta / Scanner** | validador de staff | operativo, alto contraste, botones grandes, resultado a pantalla completa verde/ámbar/rojo, cero decoración |

Detalle en `specs/design-system.md`. El modo Puerta se diseña para un celular, con una
mano, con poca luz y bajo presión: **legibilidad antes que estética**.

## Art. 11 — Reglas de producto ya fijadas

- **Grupo de compra**: hasta **4** personas, atado a evento y fecha, **todo o nada** en
  el MVP. Si alguien inicia el pago el grupo se bloquea; si el pago falla o expira, se
  libera la reserva.
- **Grupo de evento** no es grupo de compra. Coordina asistencia, no comparte pago.
- **Límite por usuario** por evento (`events.max_per_user`, mockup: 5).
- **Nominación**: modo `strict` (sin nominar no entra) o `flexible` (sin nominar entra
  a revisión manual y **genera alerta en puerta**).
- **FanPass** se comunica como **beneficio**, nunca como garantía de stock.
- El precio de catálogo es **"desde"**: la UI debe dejar claro que existen fases,
  cargos y condiciones.

## Art. 12 — Cómo se construye

1. **Spec antes que código.** Ninguna migración ni componente entra sin un `spec.md`
   con criterios de aceptación verificables.
2. **Un feature, una carpeta**: `specs/NNN-slug/` con `spec.md` (QUÉ), `plan.md` (CÓMO)
   y `tasks.md` (checklist).
3. **El schema es la fuente de verdad de los tipos.** Los tipos de TypeScript se
   **generan** desde Supabase, no se escriben a mano.
4. **Migraciones inmutables.** Una migración aplicada no se edita; se corrige con otra.
5. **Lo más simple que cumpla el artículo.** Sin abstracción especulativa, sin
   dependencia nueva para lo que resuelven veinte líneas. Pero **ningún artículo de
   esta constitución se recorta por brevedad**.
6. Toda lógica no trivial deja **una verificación ejecutable**: un test de política RLS
   en SQL o un test de la Edge Function.

## Art. 13 — Antes del dinero real

No se conecta una pasarela en producción hasta cerrar por escrito: política de
cancelaciones, política de reembolsos, tratamiento de cargos de pasarela, retenciones
al organizador, garantías, calendario de liquidación, soporte de emergencia durante
evento, responsabilidad ante fraude y protocolo de operación en puerta.

Hasta entonces, **sandbox**: `payments.provider = 'culqi_sandbox'`.

---

## Decisiones pendientes

Bloquean el diseño final; **no** bloquean el schema de Fase 1. Cada una tiene un
comportamiento por defecto seguro mientras no se decide. Registro en
`specs/decisiones-pendientes.md`.
