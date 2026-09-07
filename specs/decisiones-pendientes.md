# Decisiones pendientes

De la sección 10 de la guía funcional. Cada una tiene un **default seguro** que rige
mientras no se decida, para que ninguna bloquee Fase 1.

Regla: cuando una se cierre, se anota la fecha y quién decidió, y se actualiza el
artículo o el feature afectado en el mismo commit.

Estado: `abierta` · `cerrada (fecha)` · `diferida a Fase N`

---

## Bloquean Fase 1

| # | Pregunta | Default vigente | Afecta | Estado |
|---|---|---|---|---|
| D-01 | ¿Qué criterio hace que un evento salga destacado: fecha, popularidad, categoría, campaña pagada o curaduría Feventi? | Curaduría manual: `events.featured_at` lo pone Admin. Sin algoritmo. | 002 | abierta |
| D-02 | ¿Cómo se recupera una compra expirada o un pago interrumpido? | La reserva expira y se libera; el fan vuelve a empezar. Sin recuperación automática. | 004 | abierta |
| D-03 | ¿Cómo ingresa un fan sin conexión, batería o dispositivo? | Modo DNI del validador: el staff busca por DNI y valida a mano. Queda `checkin` con `result = manual_review`. | 006 | abierta |
| D-04 | ¿Cómo trabaja el staff sin internet? | No se soporta. El validador exige conexión y lo dice en pantalla. Es la opción honesta hasta tener protocolo. | 006 | abierta |
| D-05 | ¿Quién autoriza una excepción en puerta y cómo se registra? | Nadie desde la app. La excepción se pide por soporte y la ejecuta Admin, dejando `ticket_events`. | 006, 009 | abierta |
| D-06 | ¿Qué datos individuales de asistentes puede ver el organizador? | Solo agregados (Art. 7.5). Ningún dato individual. | 008 | abierta |
| D-07 | ¿Qué reportes puede descargar el organizador? | Ninguno en Fase 1. Se ve en pantalla, no se exporta. | 008 | abierta |
| D-08 | ¿Qué cambios puede hacer el organizador después de vender entradas? | Ninguno sobre zonas, precios, fecha, aforo ni venue: pasa por Admin (Art. 4.4). Sí puede editar descripción e imagen. | 007 | abierta |
| D-09 | ¿Qué nivel de planos y asientos necesita el primer piloto? | Sin plano gráfico. Selección por fila y número desde una lista. | 003, 004 | abierta |
| D-10 | ¿Cómo se verifica la identidad finalmente? | DNI declarado y hasheado; `dni_verified_at` se sella a mano por Admin. Sin proveedor de KYC. | 001, 004 | abierta |
| D-11 | ¿Existe centro de notificaciones? | No. Las alertas viven en el inicio de cada mundo. | 005, 008 | abierta |
| D-12 | ¿Se diferencian «reembolso», «reclamo» y «disputa bancaria»? | Sí, ya está en `support_kind`. Falta el **proceso** de cada uno. Regla firme: no se abren dos vías de recuperación por el mismo pago. | 009 | abierta |

## Bloquean Fase 1.5 — capa social

Abiertas por el **acta del 4 de septiembre de 2026**. Las cinco primeras son,
literalmente, los «puntos a validar» del §12 del acta, con un default seguro cada
una para que el trabajo no se detenga esperando la respuesta.

| # | Pregunta | Default vigente | Afecta | Estado |
|---|---|---|---|---|
| D-37 | ¿Qué funciones sociales son reales y cuáles quedan solo representadas visualmente? (acta §12.1) | **Ninguna es visual.** Lo no confirmado no aparece en la UI ni en el copy (Art. 12.5, roadmap). Se construye poco y de verdad. Un botón muerto delante de un inversor cuesta más que una función que falta. | 010–013 | abierta |
| D-38 | ¿Qué nivel de conexión con contactos externos se muestra? (acta §12.2) | **Ninguno.** Sin agenda del teléfono, sin Google Contacts, sin Instagram. Se busca por correo exacto o por código de usuario. Importar la agenda es tratamiento de datos de terceros que no consintieron. | 010 | abierta |
| D-39 | ¿La amistad es mutua o asimétrica (seguir)? | **Mutua con aceptación.** El acta §7 dice «solicitudes de amistad». Simétrica es también lo único que hace la señal social defendible: nadie aparece en el conteo de un desconocido. | 010, 011 | abierta |
| D-40 | ¿Qué revela exactamente una señal social? | **El hecho, nunca el detalle.** «Ana ya tiene entrada». Nunca la zona, el precio, cuántas entradas ni el número de orden. La señal es un booleano, no una ventana a la compra. | 011 | abierta |
| D-41 | ¿Hay umbral mínimo de amigos antes de mostrar un conteo? | **No: se muestra desde 1.** Manda el mockup («1 amigo ya tiene entrada»). Riesgo aceptado y anotado: con un solo amigo el conteo revela exactamente quién compró. Es tolerable **solo** porque la amistad es mutua, consentida y revocable, y porque D-40 limita lo revelado al hecho. | 011 | abierta |
| D-42 | ¿Cómo se presentan las comunidades sin volverse una red social? (acta §12.3) | **Seguir a un organizador o a una etiqueta**, no grupos con muro propio. Alimenta el descubrimiento sin abrir moderación de contenido, reportes ni bloqueo de publicaciones. Fase 3. | Fase 3 | abierta |
| D-43 | ¿Cómo se explica el modo ninja en una frase? (acta §12.4) | Un interruptor en el perfil: **«Nadie ve a qué eventos vas. Tú sigues viendo a tus amigos.»** Ocultarse no es cegarse. Asimétrico a propósito: castigar la privacidad con menos producto empuja a desactivarla. | 010 | abierta |
| D-44 | ¿Qué relación tienen puntos, Wallet y FanPass en esta versión? (acta §12.5) | Los puntos **se acumulan y se muestran; no se canjean por nada**. Sin catálogo de premios, sin vencimiento, sin conversión a dinero. FanPass sigue siendo un chip que solo aparece si existe la membresía (D-29). | 013 | abierta |
| D-46 | ¿La señal social dice cuántos amigos van, o **quiénes**? | **Quiénes: hasta dos nombres de pila y el resto como «y N más».** El spec de 011 dijo «conteos» apoyándose en que el mockup los enseña y el mockup manda — pero el mockup se dibujó ANTES del acta, y el acta pide otra cosa (§4: «debe sentirse como una red social»; §6: «descubra que amigos también irán»). «2 amigos quieren ir» es un dato; «Diego y Valeria quieren ir» es una razón para ir. No contradice D-40: un nombre no es la zona ni el precio, y son amistades mutuas cuyos nombres ya salen en `/amigos`. Nombre de pila, no completo: «Diego Salazar y Valeria Ríos» es una notificación de banco. | 011 | abierta |
| D-45 | ¿Los puntos se otorgan por compra o por asistencia real? | **Por asistencia real**, en el `checkin` permitido. Es lo que dice el mockup («+50 puntos por check-in») y lo que no se puede farmear comprando y devolviendo. | 013 | abierta |

## Bloquean Fase 2

| # | Pregunta | Default vigente | Estado |
|---|---|---|---|
| D-20 | ¿Orden de publicaciones, límites de precio y retención al vendedor en reventa? | Cola FIFO, precio ≤ original, retención 24 h post-evento (Art. 6). | diferida a Fase 2 |
| D-21 | ¿El grupo de evento nace automáticamente de una compra grupal? | No: se crea a mano. | diferida a Fase 3 |
| D-23b | ¿Qué ve un miembro de un **grupo de compra** si alguien usa modo ninja? | Su presencia en el grupo sí (unirse es un acto explícito); su actividad social fuera del grupo no. Ver **D-23**. | movida a Fase 1.5 (012) |
| D-22 | ¿Se puede crear grupo de evento sin comprar juntos? | Sí. | diferida a Fase 3 |
| D-23 | ¿Qué ve un miembro del grupo si alguien usa modo ninja? | Nada de su actividad social; sí su presencia en el grupo, que es un acto explícito. | diferida a Fase 3 |
| D-24 | ¿Cómo se elige o cambia el coordinador del grupo? | Lo es quien lo creó; sin transferencia. | diferida a Fase 3 |
| D-25 | ¿Qué acciones financieras exigen doble aprobación? | Ninguna implementada. Antes de dinero real, todas las salidas (Art. 13). | diferida a Fase 2 |
| D-26 | ¿Cómo se calcula la reputación del organizador? | Sin fórmula. La columna existe y queda en null. | diferida a Fase 2 |
| D-27 | ¿Feventi solo mide atribución de promotores o también calcula sus pagos? | Solo atribución. | diferida a Fase 3 |
| D-28 | ¿La wallet guarda solo entradas o también saldo? | Solo entradas. El «Saldo S/ 180» del mockup de checkout es **decorativo** y no se implementa. | diferida |
| D-29 | ¿Planes, precios, beneficios, vencimiento de puntos y catálogo de canjes de FanPass? | Sin plan. El chip de FanPass se muestra solo si existe la membresía. | diferida a Fase 3 |
| D-30 | ¿El álbum entra al MVP? ¿Público, solo asistentes o mixto? ¿Instagram automático? ¿Videos? | Fuera. Sin álbum, sin hashtag activo, sin subida de fotos. | diferida a Fase 3 |
| D-31 | ¿Ubicación compartida entra al MVP? | No (Art. 7.4). | diferida a Fase 3 |
| D-32 | ¿El organizador modera contenido o solo reporta? | Solo reporta; modera Admin. | diferida a Fase 3 |
| D-33 | ¿Cuándo se activa venta en puerta? | Nunca en Fase 1–2. No aparece en la UI. | diferida |
| D-34 | ¿Cuándo se hacen públicas las calificaciones? | No existen. | diferida |
| D-35 | ¿Mystery Box y sorteos son producto real o exploración visual? | Exploración. No se prometen (Art. 12.5 y roadmap). | diferida |
| D-36 | ¿Se fusionan «Inicio» y «Explorar» del fan? | Fase 1 no tiene ninguna de las dos: la wallet es la home del fan. Se decide al diseñar Fase 3. | diferida a Fase 3 |

## Bloquean producción, no desarrollo

**Art. 13.** Ninguna se puede sustituir por un default: exigen documento.

| # | Pregunta |
|---|---|
| D-40 | Política de cancelaciones |
| D-41 | Política de reembolsos y plazos |
| D-42 | Tratamiento de los cargos de la pasarela ante un reembolso |
| D-43 | Retenciones y garantías al organizador |
| D-44 | Calendario de liquidación y condiciones de liberación de fondos |
| D-45 | Canal y SLA de emergencia durante un evento en curso |
| D-46 | Responsabilidad ante fraude, y quién absorbe la pérdida |
| D-47 | Proceso de apelación del organizador ante una retención |
| D-48 | Validaciones legales y contables previas a cobrar dinero real |
| D-49 | Protocolo de contingencia en puerta (caída de red, caída de Feventi) |
| D-50 | Plan de Supabase. **Leaked password protection** (chequeo contra HaveIBeenPwned) exige **Pro**; en free no existe el interruptor. Mientras tanto: longitud mínima 12 y caracteres exigidos. Decidir antes de abrir registro a usuarios reales. |
| D-51 | Custodia del **pepper del DNI**. Quién guarda la copia, dónde, y quién puede recuperarla. Sin copia, perder el proyecto o restaurar un backup viejo invalida todos los `dni_hash` y obliga a que cada usuario re-declare su documento. Ver **D-10** y T-35. |
