import { Component, ChangeDetectionStrategy, input } from '@angular/core';
import { negative, soles, type PriceLine } from './money';

/**
 * Desglose de precio. Art. 5 y design-system.md §5.
 *
 * El cargo de servicio se muestra DESDE EL PRIMER PASO, y sigue visible aunque
 * sea cero: si lo absorbe el organizador, la línea dice `S/ 0.00` con su
 * leyenda. Ocultarla es lo que hace que el fan sienta que le cobraron algo al
 * final.
 */
@Component({
  selector: 'fv-price-breakdown',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <dl class="text-[13px]">
      @for (line of lines(); track line.label) {
        <div class="flex items-baseline justify-between gap-4 py-1.5">
          <dt [class]="line.kind === 'charge' ? 'text-fg-muted' : 'text-ink'">{{ line.label }}</dt>
          <dd class="font-semibold tabular-nums" [class]="valueClass(line)">
            {{ format(line) }}
          </dd>
        </div>
      }
      <div class="mt-1 flex items-baseline justify-between gap-4 border-t border-border pt-2.5">
        <dt class="font-bold">Total</dt>
        <dd class="text-lg font-black tabular-nums">{{ soles(totalCents()) }}</dd>
      </div>
    </dl>
  `,
})
export class PriceBreakdown {
  readonly lines = input.required<readonly PriceLine[]>();
  readonly totalCents = input.required<number>();

  protected readonly soles = soles;

  protected format(line: PriceLine): string {
    return line.kind === 'discount' ? negative(line.valueCents) : soles(line.valueCents);
  }

  protected valueClass(line: PriceLine): string {
    if (line.kind === 'discount') return 'text-success-fg';
    if (line.kind === 'charge') return 'text-fg-muted';
    return 'text-ink';
  }
}
