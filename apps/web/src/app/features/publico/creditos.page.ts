import { Component, ChangeDetectionStrategy, signal } from '@angular/core';

interface Credito {
  readonly archivo: string;
  readonly titulo: string | null;
  readonly autor: string;
  readonly licencia: string;
  readonly original: string;
}

/**
 * Créditos de las imágenes.
 *
 * **Existe porque una de las fotos es CC-BY y esa licencia exige crédito.** No
 * es una página de cortesía: sin ella el uso sería una infracción, por mucho
 * que la fuente se llame «libre».
 *
 * Se prefirió CC0 y dominio público justamente para no deber nada —tres de las
 * cuatro lo son— pero en cuanto una sola pide atribución hace falta el sitio
 * donde ponerla.
 *
 * El JSON lo genera `scripts/traer-imagenes.mjs` al descargar, así que la lista
 * no se puede quedar desactualizada respecto a lo que hay en `public/img`.
 */
@Component({
  selector: 'fv-creditos',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <header class="mb-5">
      <h1 class="text-2xl font-black tracking-[-0.5px]">Créditos de las imágenes</h1>
      <p class="mt-1 max-w-[62ch] text-[13px] text-fg-muted">
        Las fotos de los eventos son de Openverse, con licencia Creative Commons. Los
        retratos son de randomuser.me, publicados como datos de marcador: no
        corresponden a personas reales de Feventi.
      </p>
    </header>

    <ul class="space-y-2">
      @for (c of creditos(); track c.archivo) {
        <li class="rounded-[--radius-card] border border-border bg-surface p-3.5">
          <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
            <p class="text-[14px] font-semibold">{{ c.titulo || c.archivo }}</p>
            <span class="font-mono text-[11.5px] text-fg-muted">{{ c.licencia }}</span>
          </div>
          <p class="mt-0.5 text-[12.5px] text-fg-muted">
            {{ c.autor }} ·
            <a [href]="c.original" target="_blank" rel="noopener" class="text-info-fg underline">
              ver original
            </a>
          </p>
        </li>
      } @empty {
        <li class="text-[13px] text-fg-muted">Sin imágenes de terceros.</li>
      }
    </ul>
  `,
})
export class CreditosPage {
  protected readonly creditos = signal<readonly Credito[]>([]);

  constructor() {
    // Si el fichero no está, la página se queda vacía y no rompe nada: es
    // información, no funcionamiento.
    void fetch('/img/creditos.json')
      .then((r) => (r.ok ? r.json() : []))
      .then((d) => this.creditos.set(d))
      .catch(() => this.creditos.set([]));
  }
}
