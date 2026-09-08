import { Component, ChangeDetectionStrategy, computed, input } from '@angular/core';

/**
 * El cartel de un evento que no tiene foto.
 *
 * ── POR QUÉ NO SON FOTOS ───────────────────────────────────────────────────
 *
 * Lo evidente sería traer fotos de un banco de imágenes. No se hace por dos
 * razones, y la segunda es la que decide:
 *
 * 1. Una foto de stock genérica sobre un evento concreto se nota. Un paisaje
 *    de montaña encima de «Noche de Stand Up» dice «cogimos lo primero», y eso
 *    resta más de lo que suma el color.
 *
 * 2. **Esto no es un adorno de demo: es lo que verá el 90 % de los eventos
 *    reales.** Un organizador pequeño no sube key visual. Si el hueco se rellena
 *    con stock, el catálogo entero acaba pareciendo un banco de imágenes; si se
 *    rellena con algo del propio idioma visual de Feventi, el catálogo parece
 *    Feventi. La segunda opción escala y la primera no.
 *
 * Cuando el organizador SÍ sube una imagen, esto no aparece: manda la suya.
 *
 * ── CÓMO SE CONSTRUYE ──────────────────────────────────────────────────────
 *
 * Dos capas. Abajo, uno de los seis gradientes del design-system, elegido por
 * el id del evento — el mismo evento tiene siempre el mismo, que es lo que
 * permite reconocerlo de una pantalla a otra sin leer el título.
 *
 * Encima, una figura elegida por la CATEGORÍA. Geométrica y abstracta, no
 * ilustración: un cartel, no un dibujo. Cada una dice algo del género —
 * un festival son ondas que salen del escenario, un concierto es un haz de luz
 * sobre una multitud, la comedia es un único foco y nada más.
 *
 * Sin animación, a propósito. Veinte tarjetas moviéndose a la vez es ruido, y
 * el movimiento de este producto está reservado a lo que cambia.
 */
@Component({
  selector: 'fv-event-visual',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="absolute inset-0" [class]="gradiente()">
      <svg
        viewBox="0 0 160 90"
        preserveAspectRatio="xMidYMid slice"
        class="size-full"
        aria-hidden="true"
      >
        @switch (figura()) {
          @case ('festival') {
            <!-- Ondas que salen del escenario. -->
            <g fill="none" stroke="#fff" stroke-linecap="round">
              @for (r of [18, 30, 42, 54, 66]; track r; let i = $index) {
                <path
                  [attr.d]="'M ' + (80 - r) + ' 90 A ' + r + ' ' + r + ' 0 0 1 ' + (80 + r) + ' 90'"
                  [attr.stroke-opacity]="0.26 - i * 0.04"
                  [attr.stroke-width]="1.6 - i * 0.18"
                />
              }
            </g>
            <!-- Luces del público. -->
            <g fill="#fff">
              @for (l of luces(); track l.x) {
                <circle [attr.cx]="l.x" [attr.cy]="l.y" [attr.r]="l.r" [attr.fill-opacity]="l.o" />
              }
            </g>
          }

          @case ('concierto') {
            <!-- Un haz de luz cayendo sobre la multitud. -->
            <path d="M74 0 L86 0 L118 90 L42 90 Z" fill="#fff" fill-opacity="0.09" />
            <path d="M78 0 L82 0 L98 90 L62 90 Z" fill="#fff" fill-opacity="0.07" />
            <g fill="#fff" fill-opacity="0.18">
              @for (c of cabezas(); track c.x) {
                <circle [attr.cx]="c.x" cy="88" [attr.r]="c.r" />
              }
            </g>
          }

          @case ('comedia') {
            <!-- Un foco, un micrófono, y nada más. Es el género. -->
            <circle cx="80" cy="52" r="30" fill="#fff" fill-opacity="0.10" />
            <circle cx="80" cy="52" r="18" fill="#fff" fill-opacity="0.08" />
            <g stroke="#fff" stroke-opacity="0.5" fill="none" stroke-linecap="round">
              <path d="M80 44 v26" stroke-width="1.4" />
              <path d="M74 90 h12" stroke-width="1.4" />
            </g>
            <ellipse cx="80" cy="41" rx="3.4" ry="4.6" fill="#fff" fill-opacity="0.62" />
          }

          @default {
            <!-- Sin categoría: anillos concéntricos, neutros. -->
            <g fill="none" stroke="#fff" stroke-opacity="0.14">
              @for (r of [22, 34, 46, 58]; track r) {
                <circle cx="118" cy="20" [attr.r]="r" stroke-width="1.1" />
              }
            </g>
          }
        }
      </svg>
    </div>
  `,
  host: { class: 'contents' },
})
export class EventVisual {
  /** El id del evento: fija el gradiente y la posición de las luces. */
  readonly seed = input.required<string>();
  readonly category = input<string | null>(null);

  /** Mismo evento, mismo gradiente, siempre. */
  readonly gradiente = computed(() => 'fv-grad-' + this.hash(this.seed()) % 6);

  readonly figura = computed(() => {
    const c = (this.category() ?? '').toLowerCase();
    if (c.includes('festival')) return 'festival';
    if (c.includes('concierto') || c.includes('música') || c.includes('musica')) return 'concierto';
    if (c.includes('comedia') || c.includes('stand')) return 'comedia';
    return 'otro';
  });

  /**
   * Las luces del público. Pseudoaleatorias pero DETERMINISTAS: el mismo evento
   * las tiene siempre en el mismo sitio. Si se movieran en cada render, la
   * tarjeta parpadearía al volver al catálogo.
   */
  readonly luces = computed(() => {
    let n = this.hash(this.seed());
    const paso = (): number => (n = (n * 1103515245 + 12345) % 2147483648) / 2147483648;
    return Array.from({ length: 14 }, () => {
      const x = paso() * 160;
      const y = 58 + paso() * 30;
      return { x, y, r: 0.5 + paso() * 1.1, o: 0.2 + paso() * 0.45 };
    });
  });

  readonly cabezas = computed(() => {
    let n = this.hash(this.seed()) + 7;
    const paso = (): number => (n = (n * 1103515245 + 12345) % 2147483648) / 2147483648;
    return Array.from({ length: 22 }, () => ({ x: paso() * 160, r: 2.4 + paso() * 2.2 }));
  });

  private hash(s: string): number {
    let h = 0;
    for (const ch of s) h = (h * 31 + ch.charCodeAt(0)) % 100000;
    return h;
  }
}
