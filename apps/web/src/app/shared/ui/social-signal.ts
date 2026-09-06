import { Component, ChangeDetectionStrategy, computed, input } from '@angular/core';

/**
 * La señal social del mockup, palabra por palabra:
 *
 *     2 amigos quieren ir · 1 amigo ya tiene entrada
 *     Solo ves señales de quienes no están en modo ninja.
 *
 * Vive en `shared/ui` porque aparece en dos sitios —la tarjeta del catálogo y
 * la ficha del evento— y dos copias del mismo texto acaban divergiendo. La
 * segunda línea es tan importante como la primera: sin ella, un conteo bajo se
 * lee como «a nadie le interesa» en vez de «alguien se escondió».
 *
 * No recibe nombres ni ids, solo dos números. La decisión de no dar nombres
 * está en D-40 y en el spec de 011; aquí simplemente no hay dónde ponerlos.
 */
@Component({
  selector: 'fv-social-signal',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (hay()) {
      <p class="text-[12.5px] font-semibold text-violet">{{ linea() }}</p>
      @if (conNota()) {
        <p class="mt-0.5 text-[11px] text-fg-muted">
          Solo ves señales de quienes no están en modo ninja.
        </p>
      }
    }
  `,
})
export class SocialSignal {
  readonly going = input(0);
  readonly interested = input(0);

  /** La nota de ninja ocupa una línea: en la tarjeta del catálogo no cabe. */
  readonly conNota = input(false);

  readonly hay = computed(() => this.going() > 0 || this.interested() > 0);

  readonly linea = computed(() => {
    const partes: string[] = [];
    const i = this.interested();
    const g = this.going();
    // El verbo concuerda con el número. El mockup enseña justo el caso de uno
    // —«1 amigo ya tiene entrada»— y ese es el que más se ve cuando el grafo
    // está recién empezado, así que «1 amigos quieren» no es un detalle menor.
    if (i > 0) partes.push(i === 1 ? '1 amigo quiere ir' : i + ' amigos quieren ir');
    if (g > 0) partes.push(g === 1 ? '1 amigo ya tiene entrada' : g + ' amigos ya tienen entrada');
    return partes.join(' · ');
  });
}
