# Design system — Feventi

Extraído de `docs/sources/mockups/Feventi Pantallas Principales.dc.html`. Los valores de
aquí son la fuente de verdad de los tokens de Tailwind v4 en `apps/web/src/styles.css`.
Si el mockup y este archivo discrepan, **manda el mockup** y se corrige aquí.

---

## 1. Color

### Marca

| token | hex | uso |
|---|---|---|
| `--color-navy` | `#1D184C` | tinta de marca, header, sidebar de operación, fondos sólidos de hero |
| `--color-coral` | `#FF4D6D` | acción primaria, foco, enlaces, indicador de pestaña activa |
| `--color-turquoise` | `#00D4C4` | disponible, éxito, acceso permitido |
| `--color-violet` | `#9B8CFF` | FanPass, informativo, categorías |
| `--color-amber` | `#FFB07A` | advertencia, stock bajo, revisión manual |

Claros para texto y chips sobre navy: `--color-coral-200 #FF8FA3`,
`--color-violet-200 #C0B6FF`.

### Neutrales (escala Zinc)

`--color-bg #FAFAFA` · `--color-surface #FFFFFF` · `--color-muted #F4F4F5` ·
`--color-border #E4E4E7` · `--color-fg-subtle #A1A1AA` · `--color-fg-muted #71717A` ·
`--color-fg-soft #52525B` · `--color-ink #09090B`

### Pares semánticos

Cada estado es un trío **fondo suave / texto oscuro / borde**. Los hex de marca son
para superficie y acento; **no** se usan como color de texto sobre blanco: no pasan
contraste. Para texto va la variante oscura.

| estado | fondo | texto | borde | dónde |
|---|---|---|---|---|
| éxito / permitido | `#E0FAF8` | `#0A8A80` | `#00D4C4` | QR activo, acceso permitido, neto |
| advertencia / manual | `#FFF9F0` `#FFF3E0` | `#C47C00` | `#FFB07A` | sin nominar, QR inhabilitado, en revisión |
| error / denegado | `#FFF5F6` `#FFE4E9` | `#C9203F` | `#FF4D6D` | QR inválido, ya utilizado, requiere info |
| info / FanPass | `#F5F3FF` `#EDE9FF` | `#5B4CCC` | `#9B8CFF` | FanPass, cortesías, en setup |
| neutro | `#F4F4F5` | `#71717A` | `#E4E4E7` | borrador, prioridad baja, deshabilitado |

Texto **sobre** color saturado: `#04322F` sobre turquesa, `#2B2260` sobre violeta,
`#FFFFFF` sobre coral y navy.

### Gradientes

Marca: `linear-gradient(135deg, #FF4D6D, #9B8CFF, #00D4C4)` — coral → violeta →
turquesa (Art. 10).

Placeholder de key visual de evento — seis gradientes rotativos por índice, para que un
catálogo sin imágenes siga siendo legible:

```
0  linear-gradient(135deg,#2d1b69,#1e3a5f)   3  linear-gradient(135deg,#713f12,#451a03)
1  linear-gradient(135deg,#7c2d12,#881337)   4  linear-gradient(135deg,#1c1917,#44403c)
2  linear-gradient(135deg,#134e4a,#1e3a5f)   5  linear-gradient(135deg,#052e16,#14532d)
```

Textura de hero: `repeating-linear-gradient(115deg, rgba(255,255,255,.05) 0 2px, transparent 2px 14px)`.

---

## 2. Tipografía

- **Inter** — 400, 500, 600, 700, 800, 900. Todo el producto.
- **JetBrains Mono** — 400, 600. Exclusivamente para lo que se lee en voz alta o se
  dicta a soporte: código de ticket (`FVT-2026-A3B7K9`), código de solicitud
  (`REQ-002`), número de caso (`#1042`), reloj del scanner.

| rol | tamaño / peso | tracking |
|---|---|---|
| hero de evento | 32 / 900 | `-1px` |
| título de sección | 18 / 800 | `-.5px` |
| título de card | 15–16 / 700 | |
| cuerpo | 13–14 / 400–500 | |
| meta y ayuda | 11–12.5 / 500–600 | |
| métrica de dashboard | 26–30 / 900 | `-1px` |
| resultado de scanner | 34–44 / 900 | `-1px`, mayúsculas |

Regla del modo Puerta: nada por debajo de **16 px**, y el veredicto ocupa el ancho
completo.

---

## 3. Forma y espacio

Radios: `8px` botón y chip cuadrado · `10px` icono y avatar · `12–14px` card interna ·
`18px` card y panel · `20px` pill · `999px` badge circular.

Bordes: `1px solid var(--color-border)`. El estado se comunica **cambiando el color del
borde**, no engordándolo, salvo la card seleccionada (`2px` coral) y el resultado del
scanner (`3px` del color del veredicto).

Espaciado: múltiplos de 4. Padding de página `24px 18px 64px`, ancho máximo de
contenido `1180px`. Gap entre cards `12–20px`.

Sombras: casi ninguna. La jerarquía la dan borde y fondo. Solo el resultado del scanner
y los modales elevan.

---

## 4. Los tres modos

### Fan / Público
Fondo `--color-bg`, cards blancas con borde, chips pastel, acción coral. Mobile-first:
se diseña a 390 px y se ensancha. El ticket se dibuja como objeto físico —
troquelado, código en mono, QR centrado.

### Operación (organizador / admin)
Navegación navy, contenido sobre `--color-bg`, cards blancas, tablas densas, métricas
grandes con subtítulo comparativo. El color solo marca estado; nada decorativo.
Toda métrica de dinero lleva su etiqueta literal del Art. 5 — «neto **estimado**»,
nunca «disponible».

### Puerta / Scanner
Fondo `--color-ink`, cámara a pantalla completa, un único botón primario de 56 px de
alto. El veredicto tapa la pantalla con el trío semántico correspondiente:

| veredicto | fondo | borde | texto |
|---|---|---|---|
| `ACCESO PERMITIDO` | `#F0FDFC` | `#00D4C4` | `#0A8A80` |
| `REVISAR MANUALMENTE` | `#FFF9F0` | `#FFB07A` | `#C47C00` |
| `YA UTILIZADO` | `#FFF5F6` | `#FF4D6D` | `#C9203F` |
| `ACCESO DENEGADO` | `#FFF5F6` | `#FF4D6D` | `#C9203F` |

`YA UTILIZADO` y `ACCESO DENEGADO` comparten paleta pero **no** mensaje: el primero
dice hora y puerta del primer ingreso, el segundo dice qué hacer («abre la wallet en la
app»). El staff necesita la acción, no el diagnóstico.

Cada veredicto además de color lleva **texto e icono** — nunca solo color (Art. 10,
accesibilidad).

---

## 5. Patrones

**Card de evento** — key visual 16:9 con gradiente y badge de demanda arriba a la
derecha, luego título, venue · fecha, «desde S/ X» y la fase activa. La señal social
(«3 amigos quieren ir») solo aparece si el visor tiene permiso y el otro no está en modo
ninja (Art. 7.3).

**Chip de estado** — pill de 4/10 px, 11 px/600, del trío semántico. Texto siempre;
el color nunca va solo.

**Stepper de checkout** — `Zona · Asientos · Datos · Pago · Wallet`. Hecho = turquesa
suave, actual = navy con punto coral, futuro = gris. Cinco pasos fijos: si un paso no
aplica (zona de pie no elige asiento) se marca hecho, no se oculta — el fan no debe
sentir que el flujo cambió.

**Desglose de precio** — `base → descuento → cargo de servicio → total`, una línea por
concepto, el descuento en verde `#0A8A80`, el cargo en gris. El cargo aparece **desde el
primer paso** (Art. 5). Si lo absorbe el organizador la línea sigue visible con
`S/ 0.00` y la leyenda «absorbido por el organizador».

**Ticket con QR** — el QR y su cuenta atrás («se actualiza en 24 s») con barra de
progreso, código en mono, zona y titular. Debajo, siempre, la razón de existir del
Art. 2: «Muestra este QR en puerta. Las capturas no funcionan.»

**Línea de fases** — lista vertical: fase, precio, estado y cuándo abre o cierra. La
activa se destaca; las futuras muestran fecha, no se ocultan.

**Métrica de dashboard** — etiqueta pequeña, valor 900, subtítulo comparativo
(«de 1,400 aforo», «+12% vs. semana pasada»). Un número sin denominador no se muestra.

---

## 6. Voz

Español peruano, tuteo, frases cortas. `S/ ` con espacio y dos decimales. Fechas largas
en español (`28 de agosto`), hora 24 h (`20:00`).

Un mensaje de error dice **qué pasó y qué hacer**: no «QR inválido», sino «QR inválido o
expirado — probable captura de pantalla. Solicita abrir la wallet en la app de Feventi».

Nunca se promete lo que no está confirmado (Art. 2.1): antes del pago se dice
«tus tickets se emiten solo tras pago confirmado», no «ya tienes tu entrada».
