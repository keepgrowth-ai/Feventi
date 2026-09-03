import { Component, ChangeDetectionStrategy, input } from '@angular/core';

/**
 * Métrica de dashboard. design-system.md §5.
 *
 * `sub` es obligatorio a propósito: un número sin denominador ni comparación no
 * se muestra (008, AC-16 y AC-19). «1,010» no dice nada; «1,010 de 1,400 aforo»
 * sí. Si no hay denominador que poner, la métrica no está lista para la pantalla.
 */
@Component({
  selector: 'fv-metric',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="rounded-[--radius-card] border border-border bg-surface p-4">
      <div class="text-[11px] font-semibold uppercase tracking-wide text-fg-muted">
        {{ label() }}
      </div>
      <div
        class="mt-1.5 text-[28px] font-black leading-none tracking-[-1px] tabular-nums"
        [style.color]="color()"
      >
        {{ value() }}
      </div>
      <div class="mt-1.5 text-[12px] text-fg-muted">{{ sub() }}</div>
    </div>
  `,
})
export class Metric {
  readonly label = input.required<string>();
  readonly value = input.required<string>();
  /** Denominador o comparación. Sin esto la métrica no se pinta. */
  readonly sub = input.required<string>();
  readonly color = input('var(--color-ink)');
}
