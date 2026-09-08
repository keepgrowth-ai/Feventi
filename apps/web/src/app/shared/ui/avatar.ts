import { Component, ChangeDetectionStrategy, computed, input } from '@angular/core';

/**
 * La cara de una persona en Feventi.
 *
 * ── POR QUÉ NO SON FOTOS ───────────────────────────────────────────────────
 *
 * Poner retratos de un banco de imágenes a Diego, Valeria y Nadia sería
 * atribuir la cara de una persona real a un usuario inventado. No se hace, ni
 * siquiera para una demo: esas caras acaban en una captura, y la captura en una
 * presentación.
 *
 * Cuando exista subida de foto de perfil, `url` la pinta y esto desaparece.
 * Mientras tanto, la inicial sobre uno de los seis gradientes de la marca —
 * los MISMOS que usa el cartel de un evento sin foto. Que una persona y un
 * cartel compartan paleta no es pereza: es lo que hace que un avatar dentro de
 * una tarjeta de evento se lea como parte de la misma cosa.
 *
 * El color sale del nombre, así que la misma persona es siempre del mismo color
 * y se reconoce de una pantalla a otra antes de leerla.
 */
@Component({
  selector: 'fv-avatar',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (url()) {
      <img
        [src]="url()"
        [alt]="nombre() ?? ''"
        class="size-full rounded-full object-cover"
        loading="lazy"
      />
    } @else {
      <span
        class="grid size-full place-items-center rounded-full font-bold text-white"
        [class]="gradiente()"
        aria-hidden="true"
        >{{ inicial() }}</span
      >
    }
  `,
  host: { class: 'inline-grid shrink-0 overflow-hidden rounded-full' },
})
export class Avatar {
  readonly nombre = input<string | null>(null);
  readonly url = input<string | null>(null);

  readonly inicial = computed(() => (this.nombre()?.trim()?.[0] ?? '?').toUpperCase());

  readonly gradiente = computed(() => {
    const n = this.nombre() ?? '';
    let h = 0;
    for (const ch of n) h = (h * 31 + ch.charCodeAt(0)) % 6;
    return 'fv-grad-' + h;
  });
}
