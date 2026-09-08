import {
  Component,
  ChangeDetectionStrategy,
  DestroyRef,
  effect,
  inject,
  input,
  signal,
} from '@angular/core';

/**
 * Un número que sube contando cuando cambia.
 *
 * **No es un adorno de carga.** La primera vez que se pinta, aparece ya en su
 * valor: contar desde cero cada vez que alguien abre la wallet sería animar por
 * animar. Solo cuenta cuando el número **cambia mientras miras** — que en este
 * producto pasa en un sitio: vuelves de la puerta y tienes 50 puntos más.
 *
 * Ese es el momento que la animación tiene que explicar. Un número que salta de
 * 150 a 200 no dice de dónde salió; uno que sube contando dice «esto acaba de
 * pasar y es por lo que hiciste».
 */
@Component({
  selector: 'fv-count-up',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `{{ mostrado() }}`,
  host: { class: 'tabular-nums' },
})
export class CountUp {
  readonly value = input.required<number>();

  protected readonly mostrado = signal(0);

  private primeraVez = true;
  private raf?: number;

  constructor() {
    inject(DestroyRef).onDestroy(() => this.raf && cancelAnimationFrame(this.raf));

    effect(() => {
      const destino = this.value();

      // Primer valor: se planta, no se cuenta.
      if (this.primeraVez) {
        this.primeraVez = false;
        this.mostrado.set(destino);
        return;
      }

      this.contarHasta(destino);
    });
  }

  private contarHasta(destino: number): void {
    const desde = this.mostrado();
    if (desde === destino) return;

    if (this.raf) cancelAnimationFrame(this.raf);

    // Quien pidió menos movimiento recibe el número, no el espectáculo.
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
      this.mostrado.set(destino);
      return;
    }

    const inicio = performance.now();
    const dur = 700;

    const paso = (t: number): void => {
      const p = Math.min((t - inicio) / dur, 1);
      // Desacelera al final: el ojo sigue mejor un número que frena.
      const eased = 1 - Math.pow(1 - p, 3);
      this.mostrado.set(Math.round(desde + (destino - desde) * eased));
      if (p < 1) this.raf = requestAnimationFrame(paso);
    };

    this.raf = requestAnimationFrame(paso);
  }
}
