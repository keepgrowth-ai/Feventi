import { Component, ChangeDetectionStrategy, computed, inject, input, output, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { soles } from '../../shared/ui/money';
import { CheckoutStore, type ReserveItem } from '../checkout/checkout.store';
import type { PublicTier, PublicZone } from './public-event.store';

interface FreeSeat {
  readonly id: string;
  readonly row_label: string;
  readonly seat_number: number;
}

/**
 * Elegir qué se compra, dentro de la card de la zona.
 *
 * Dos formas según el tipo de zona:
 *  - **de pie**: cantidad, con el máximo que permita el evento y el stock;
 *  - **numerada**: lista de asientos libres por fila y número (**D-09**: sin
 *    plano gráfico en el primer piloto).
 *
 * La disponibilidad que se muestra es orientativa y puede estar vieja medio
 * segundo. Quien decide es `reserve_order`, y si otro se queda con el asiento,
 * el error que vuelve ya está escrito para leerse.
 */
@Component({
  selector: 'fv-seleccion',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule],
  template: `
    @if (open()) {
      <div class="mt-3 rounded-[--radius-inner] border border-coral bg-danger-bg p-3.5">
        @if (zone().kind === 'standing') {
          <label class="block">
            <span class="text-[12px] font-semibold text-fg-soft">
              ¿Cuántas entradas? <span class="font-normal text-fg-muted">máximo {{ max() }}</span>
            </span>
            <div class="mt-1.5 flex items-center gap-2">
              <button
                type="button"
                (click)="dec()"
                class="size-9 rounded-[--radius-chip] border border-border bg-surface text-[16px] font-bold"
              >
                −
              </button>
              <span class="w-10 text-center text-[18px] font-black tabular-nums">{{ qty() }}</span>
              <button
                type="button"
                (click)="inc()"
                class="size-9 rounded-[--radius-chip] border border-border bg-surface text-[16px] font-bold"
              >
                +
              </button>
              <span class="ml-2 text-[13px] text-fg-soft">
                {{ money(qty() * tier().total_cents) }}
              </span>
            </div>
          </label>
        } @else {
          <span class="text-[12px] font-semibold text-fg-soft">
            Elige tu asiento
            <span class="font-normal text-fg-muted">— {{ seats().length }} libres</span>
          </span>
          @if (seats().length) {
            <div class="mt-1.5 flex max-h-40 flex-wrap gap-1.5 overflow-y-auto">
              @for (s of seats(); track s.id) {
                <button
                  type="button"
                  (click)="toggleSeat(s.id)"
                  [class]="
                    picked().includes(s.id)
                      ? 'rounded-[--radius-chip] bg-coral px-2.5 py-1.5 text-[12px] font-bold text-white'
                      : 'rounded-[--radius-chip] border border-border bg-surface px-2.5 py-1.5 text-[12px] font-medium'
                  "
                >
                  {{ s.row_label }}-{{ s.seat_number }}
                </button>
              }
            </div>
            @if (picked().length) {
              <p class="mt-2 text-[13px] font-semibold">
                {{ picked().length }}
                {{ picked().length === 1 ? 'asiento' : 'asientos' }} ·
                {{ money(picked().length * tier().total_cents) }}
              </p>
            }
          } @else {
            <p class="mt-1.5 text-[13px] text-fg-muted">
              No quedan asientos libres en esta zona.
            </p>
          }
        }

        @if (store.error(); as e) {
          <p role="alert" class="mt-2 rounded-[--radius-chip] bg-surface px-3 py-2 text-[12.5px] text-danger-fg">
            {{ e }}
          </p>
        }

        <div class="mt-3 flex flex-wrap gap-2">
          <button
            type="button"
            (click)="reserve()"
            [disabled]="!count() || store.loading()"
            class="rounded-[--radius-chip] bg-coral px-4 py-2.5 text-[13px] font-bold text-white disabled:opacity-50"
          >
            {{ store.loading() ? 'Reservando…' : 'Reservar ' + count() + ' y continuar' }}
          </button>
          <button
            type="button"
            (click)="cancel.emit()"
            class="rounded-[--radius-chip] border border-border bg-surface px-4 py-2.5 text-[13px] font-semibold"
          >
            Cancelar
          </button>
        </div>

        <!-- Art. 2.1: reservar no es comprar, y la pantalla lo dice antes -->
        <p class="mt-2 text-[11.5px] text-fg-muted">
          Reservar retiene tus entradas 15 minutos. La entrada se emite recién con el pago
          confirmado.
        </p>
      </div>
    }
  `,
})
export class Seleccion {
  readonly zone = input.required<PublicZone>();
  readonly tier = input.required<PublicTier>();
  readonly maxPerUser = input.required<number>();
  readonly open = input(false);

  readonly cancel = output<void>();
  readonly reserved = output<readonly ReserveItem[]>();

  protected readonly store = inject(CheckoutStore);
  protected readonly money = soles;

  protected readonly qty = signal(1);
  protected readonly picked = signal<readonly string[]>([]);
  protected readonly seats = signal<readonly FreeSeat[]>([]);

  protected readonly max = computed(() =>
    Math.min(this.maxPerUser(), this.tier().available, 10),
  );
  protected readonly count = computed(() =>
    this.zone().kind === 'standing' ? this.qty() : this.picked().length,
  );

  constructor() {
    queueMicrotask(() => {
      if (this.open() && this.zone().kind === 'seated') void this.loadSeats();
    });
  }

  private async loadSeats(): Promise<void> {
    this.seats.set(await this.store.freeSeats(this.zone().id));
  }

  protected inc(): void {
    this.qty.update((q) => Math.min(q + 1, this.max()));
  }
  protected dec(): void {
    this.qty.update((q) => Math.max(q - 1, 1));
  }

  protected toggleSeat(id: string): void {
    this.picked.update((p) => {
      if (p.includes(id)) return p.filter((x) => x !== id);
      if (p.length >= this.max()) return p;
      return [...p, id];
    });
  }

  /**
   * Una fila por entrada, igual que en la base: tres entradas de pie son tres
   * elementos con el mismo tier. Sin cantidad, para que `order_item → ticket`
   * sea uno a uno y la emisión no tenga nada que repartir.
   */
  protected reserve(): void {
    const tierId = this.tier().tier_id;
    const items: ReserveItem[] =
      this.zone().kind === 'standing'
        ? Array.from({ length: this.qty() }, () => ({ tier_id: tierId, seat_id: null }))
        : this.picked().map((seat_id) => ({ tier_id: tierId, seat_id }));
    this.reserved.emit(items);
  }
}
