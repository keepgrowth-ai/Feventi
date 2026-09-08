import { Component, ChangeDetectionStrategy, computed, input } from '@angular/core';
import { Avatar } from './avatar';

/**
 * La señal social. Aparece en la tarjeta del catálogo y en la ficha del evento.
 *
 *     (D)(V)  Diego y Valeria quieren ir
 *             Solo ves señales de quienes no están en modo ninja.
 *
 * **Por qué avatares y no solo texto.** «Diego y Valeria quieren ir» escrito a
 * secas es la lectura de una base de datos. Dos círculos con sus iniciales
 * delante es una red social, y se entiende antes de leer la frase. Es el
 * diferencial del producto: merece ser un objeto, no un renglón.
 *
 * El color de cada avatar sale de los **mismos seis gradientes** que el
 * catálogo usa para un evento sin imagen, elegidos por el nombre. Así una
 * persona y un cartel hablan el mismo idioma visual, y dos personas distintas
 * salen siempre del mismo color — que es lo que hace que se reconozcan de una
 * tarjeta a otra sin leer.
 *
 * **Dice nombres, no números** (D-46). «2 amigos quieren ir» es un dato;
 * «Diego y Valeria quieren ir» es una razón para ir. Nombre de pila: el
 * apellido convierte la frase en una notificación de banco.
 *
 * La segunda línea es tan importante como la primera. Sin ella, un conteo bajo
 * se lee como «a nadie le interesa» en vez de «alguien se escondió».
 */
@Component({
  selector: 'fv-social-signal',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Avatar],
  template: `
    @if (hay()) {
      <div class="fv-anim-llega flex items-center gap-2">
        @if (caras().length) {
          <!-- Se solapan a propósito: es la forma de decir «un grupo» sin
               escribirlo, y ocupa menos que ponerlos en fila. -->
          <span class="flex shrink-0 -space-x-1.5" aria-hidden="true">
            @for (c of caras(); track c.nombre; let i = $index) {
              <fv-avatar
                class="fv-anim-llega size-6 text-[10px] ring-2 ring-surface"
                [nombre]="c.nombre"
                [style.animation-delay.ms]="80 + i * 70"
              />
            }
          </span>
        }

        <p class="text-[12.5px] font-semibold leading-snug text-info-fg">
          {{ linea() }}
        </p>
      </div>

      @if (conNota()) {
        <p class="fv-anim-llega mt-1 text-[11px] text-fg-muted" style="animation-delay:260ms">
          Solo ves señales de quienes no están en modo ninja.
        </p>
      }
    }
  `,
})
export class SocialSignal {
  readonly going = input(0);
  readonly interested = input(0);
  readonly goingNames = input<readonly string[] | null>(null);
  readonly interestedNames = input<readonly string[] | null>(null);

  /** La nota de ninja ocupa una línea: en la tarjeta del catálogo no cabe. */
  readonly conNota = input(false);

  readonly hay = computed(() => this.going() > 0 || this.interested() > 0);

  /**
   * Los que van primero: tener la entrada pesa más que quererla, y si solo
   * caben tres caras que sean las de quien ya pagó.
   */
  readonly caras = computed(() => {
    const nombres = [...(this.goingNames() ?? []), ...(this.interestedNames() ?? [])]
      .filter(Boolean)
      .slice(0, 3);
    return nombres.map((n) => ({ nombre: n }));
  });

  readonly linea = computed(() => {
    const partes: string[] = [];
    const i = this.frase(this.interested(), this.interestedNames(), 'quiere ir', 'quieren ir');
    const g = this.frase(this.going(), this.goingNames(), 'ya tiene entrada', 'ya tienen entrada');
    if (i) partes.push(i);
    if (g) partes.push(g);
    return partes.join(' · ');
  });

  /**
   * «Diego», «Diego y Valeria», «Diego, Valeria y 2 más».
   *
   * Si por lo que sea no llegan nombres, se cae al conteo de siempre: la señal
   * es un adorno y no puede quedarse en blanco por un null.
   */
  private frase(
    total: number,
    nombres: readonly string[] | null,
    singular: string,
    plural: string,
  ): string {
    if (total <= 0) return '';
    const verbo = total === 1 ? singular : plural;

    const n = (nombres ?? []).filter(Boolean);
    if (!n.length) return (total === 1 ? '1 amigo ' : total + ' amigos ') + verbo;

    const resto = total - n.length;
    let quien: string;
    if (resto > 0) quien = n.join(', ') + ' y ' + resto + ' más';
    else if (n.length === 1) quien = n[0];
    else quien = n.slice(0, -1).join(', ') + ' y ' + n[n.length - 1];

    return quien + ' ' + verbo;
  }
}
