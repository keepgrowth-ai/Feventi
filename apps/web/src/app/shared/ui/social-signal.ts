import { Component, ChangeDetectionStrategy, computed, input } from '@angular/core';

/**
 * La señal social. Aparece en la tarjeta del catálogo y en la ficha del evento.
 *
 *     Diego ya tiene entrada · Valeria quiere ir
 *     Solo ves señales de quienes no están en modo ninja.
 *
 * **Dice nombres, no números** (D-46). El mockup enseñaba «2 amigos quieren
 * ir», y así estuvo hasta que el acta dejó claro que la app tiene que SENTIRSE
 * como una red social: «2 amigos quieren ir» es un dato; «Diego y Valeria
 * quieren ir» es una razón para ir.
 *
 * Nombre de pila, no completo. «Diego Salazar y Valeria Ríos ya tienen entrada»
 * es una notificación de banco.
 *
 * Vive en `shared/ui` porque aparece en dos sitios y dos copias del mismo texto
 * acaban divergiendo. La segunda línea es tan importante como la primera: sin
 * ella, un conteo bajo se lee como «a nadie le interesa» en vez de «alguien se
 * escondió».
 */
@Component({
  selector: 'fv-social-signal',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (hay()) {
      <p class="text-[12.5px] font-semibold leading-snug text-violet">{{ linea() }}</p>
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
  readonly goingNames = input<readonly string[] | null>(null);
  readonly interestedNames = input<readonly string[] | null>(null);

  /** La nota de ninja ocupa una línea: en la tarjeta del catálogo no cabe. */
  readonly conNota = input(false);

  readonly hay = computed(() => this.going() > 0 || this.interested() > 0);

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
