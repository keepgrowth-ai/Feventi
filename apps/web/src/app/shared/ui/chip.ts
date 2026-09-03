import { Component, ChangeDetectionStrategy, computed, input } from '@angular/core';

export type ChipTone = 'success' | 'warn' | 'danger' | 'info' | 'neutral';

/**
 * Chip de estado. Los tríos semánticos de design-system.md §1.
 *
 * El texto es obligatorio: el color nunca va solo (Art. 10, accesibilidad). Por
 * eso no hay una variante «solo punto» ni un modo icono sin etiqueta.
 */
@Component({
  selector: 'fv-chip',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <span
      class="inline-flex items-center gap-1.5 rounded-[--radius-pill] px-2.5 py-1 text-[11px] font-semibold"
      [class]="classes()"
    >
      @if (dot()) {
        <span class="size-1.5 rounded-full" [style.background]="dotColor()"></span>
      }
      <ng-content />
    </span>
  `,
})
export class Chip {
  readonly tone = input<ChipTone>('neutral');
  readonly dot = input(false);

  private static readonly TONES: Record<ChipTone, string> = {
    success: 'bg-success-bg text-success-fg',
    warn: 'bg-warn-bg-alt text-warn-fg',
    danger: 'bg-danger-bg-alt text-danger-fg',
    info: 'bg-info-bg-alt text-info-fg',
    neutral: 'bg-muted text-fg-muted',
  };

  private static readonly DOTS: Record<ChipTone, string> = {
    success: 'var(--color-turquoise)',
    warn: 'var(--color-amber)',
    danger: 'var(--color-coral)',
    info: 'var(--color-violet)',
    neutral: 'var(--color-border)',
  };

  readonly classes = computed(() => Chip.TONES[this.tone()]);
  readonly dotColor = computed(() => Chip.DOTS[this.tone()]);
}
