import { Component, ChangeDetectionStrategy, computed, input } from '@angular/core';

export type CheckoutStep = 'zona' | 'asientos' | 'datos' | 'pago' | 'wallet';

export const STEPS: readonly { id: CheckoutStep; label: string }[] = [
  { id: 'zona', label: 'Zona' },
  { id: 'asientos', label: 'Asientos' },
  { id: 'datos', label: 'Datos' },
  { id: 'pago', label: 'Pago' },
  { id: 'wallet', label: 'Wallet' },
];

/**
 * El stepper del mockup: `Zona · Asientos · Datos · Pago · Wallet`.
 *
 * Los cinco pasos son **fijos**. Si uno no aplica —una zona de pie no elige
 * asiento— se marca **hecho**, no se oculta: el fan no debe sentir que el flujo
 * cambió debajo de él a mitad de la compra.
 */
@Component({
  selector: 'fv-checkout-stepper',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <ol class="mb-6 flex flex-wrap gap-1.5">
      @for (s of steps(); track s.id) {
        <li
          class="flex flex-1 items-center gap-2 rounded-[--radius-chip] px-2.5 py-2"
          [class]="s.done ? 'bg-success-bg' : s.active ? 'bg-navy' : 'bg-muted'"
        >
          <span
            class="grid size-5 shrink-0 place-items-center rounded-full text-[11px] font-bold"
            [class]="
              s.done
                ? 'bg-turquoise text-on-turquoise'
                : s.active
                  ? 'bg-coral text-white'
                  : 'bg-border text-fg-muted'
            "
          >
            {{ s.done ? '✓' : s.n }}
          </span>
          <span
            class="text-[12px] font-semibold"
            [class]="s.done ? 'text-success-fg' : s.active ? 'text-white' : 'text-fg-subtle'"
            >{{ s.label }}</span
          >
        </li>
      }
    </ol>
  `,
})
export class CheckoutStepper {
  readonly current = input.required<CheckoutStep>();
  /** Pasos que no aplican a esta compra. Se marcan hechos, nunca se ocultan. */
  readonly skipped = input<readonly CheckoutStep[]>([]);

  protected readonly steps = computed(() => {
    const i = STEPS.findIndex((s) => s.id === this.current());
    const skip = this.skipped();
    return STEPS.map((s, n) => ({
      id: s.id,
      label: s.label,
      n: n + 1,
      active: n === i,
      done: n < i || (skip.includes(s.id) && n !== i),
    }));
  });
}
