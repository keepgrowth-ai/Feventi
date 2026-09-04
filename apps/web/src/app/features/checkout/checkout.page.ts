import {
  Component,
  ChangeDetectionStrategy,
  computed,
  inject,
  input,
  signal,
  OnDestroy,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { AuthStore } from '../../core/auth.store';
import { Chip } from '../../shared/ui/chip';
import { PriceBreakdown } from '../../shared/ui/price-breakdown';
import { soles, type PriceLine } from '../../shared/ui/money';
import { CheckoutStepper, type CheckoutStep } from './stepper';
import { CheckoutStore, mmss, secondsLeft, type OrderWithItems } from './checkout.store';

/**
 * Checkout: datos, nominación y pago de una orden ya reservada.
 *
 * Del spec, lo que no es negociable:
 *  - el desglose está desde el PRIMER momento, y el cargo sigue visible aunque
 *    sea cero (Art. 5). Que aparezca al final se siente como trampa;
 *  - la cuenta atrás dice cuánto queda y qué pasa si vence;
 *  - «reservado» no es «comprado». Hasta `paid` no aparece la palabra entrada
 *    en posesivo, y el botón dice «Pagar y emitir tickets» (Art. 2.1);
 *  - sin nominar, el copy dice la CONSECUENCIA concreta —alerta en puerta— no
 *    una advertencia genérica.
 *
 * El pago es sandbox (Art. 13). `confirm_payment` es de `service_role`: la llama
 * el webhook, no esta pantalla. Aquí el botón deja la orden en
 * `awaiting_payment` y el resto lo hace el servidor.
 */
@Component({
  selector: 'fv-checkout',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule, RouterLink, Chip, PriceBreakdown, CheckoutStepper],
  template: `
    @if (order(); as o) {
      <div class="mx-auto max-w-3xl">
        <fv-checkout-stepper [current]="step()" [skipped]="skipped()" />

        <!-- Cuenta atrás: cuánto queda y qué pasa si vence -->
        @if (isLive(o)) {
          <div
            class="mb-5 flex flex-wrap items-center justify-between gap-3 rounded-[--radius-card] border p-3.5"
            [class]="
              left() <= 120 ? 'border-danger-border bg-danger-bg' : 'border-border bg-surface'
            "
          >
            <div>
              <span class="text-[13.5px] font-bold">
                Tus entradas están reservadas · {{ clock() }}
              </span>
              <p class="text-[12.5px] text-fg-muted">
                Si se vence, se liberan y vuelven a estar disponibles para otros.
              </p>
            </div>
            @if (left() <= 0) {
              <fv-chip tone="danger">Reserva vencida</fv-chip>
            }
          </div>
        }

        @if (store.error(); as e) {
          <p
            class="mb-4 rounded-[--radius-chip] bg-danger-bg px-3 py-2.5 text-[13px] text-danger-fg"
          >
            {{ e }}
          </p>
        }

        <!-- Estado terminal: pagado -->
        @if (o.status === 'paid') {
          <section
            class="rounded-[--radius-card] border-2 border-success-border bg-success-bg p-6 text-center"
          >
            <h1 class="text-2xl font-black tracking-[-0.5px] text-success-fg">Pago confirmado</h1>
            <p class="mt-2 text-[14px]">
              Tus {{ o.order_items.length }}
              {{ o.order_items.length === 1 ? 'entrada está' : 'entradas están' }} en tu wallet.
            </p>
            <p class="mt-1 text-[12.5px] text-fg-muted">
              Muestra el QR desde la wallet en puerta. Las capturas no funcionan.
            </p>
            <a
              routerLink="/entradas"
              class="mt-4 inline-block rounded-[--radius-chip] bg-coral px-5 py-2.5 text-[14px] font-bold text-white"
            >
              Ver mis entradas
            </a>
          </section>
        } @else if (o.status === 'expired') {
          <section class="rounded-[--radius-card] border border-border bg-surface p-6 text-center">
            <h1 class="text-xl font-black">La reserva se venció</h1>
            <p class="mt-2 text-[13.5px] text-fg-muted">
              Tus entradas volvieron a estar disponibles. Vuelve a elegirlas si todavía quedan.
            </p>
            @if (o.events?.slug) {
              <a
                [routerLink]="['/eventos', o.events!.slug]"
                class="mt-4 inline-block rounded-[--radius-chip] bg-coral px-5 py-2.5 text-[14px] font-bold text-white"
              >
                Volver al evento
              </a>
            }
          </section>
        } @else {
          <header class="mb-5">
            <h1 class="text-2xl font-black tracking-[-0.5px]">
              {{ o.events?.title ?? 'Tu compra' }}
            </h1>
            <p class="mt-1 text-[13px] text-fg-muted">
              {{ o.events?.venues?.name }}@if (o.events?.starts_at) {
                · {{ longDate(o.events!.starts_at!) }}
              }
              · orden <span class="font-mono">{{ o.code }}</span>
            </p>
          </header>

          <div class="grid gap-5 lg:grid-cols-[1fr_300px]">
            <div class="space-y-5">
              <!-- Datos del comprador -->
              <section class="rounded-[--radius-card] border border-border bg-surface p-5">
                <h2 class="mb-1 text-[16px] font-bold">Tus datos</h2>
                <p class="mb-3 text-[12.5px] text-fg-muted">
                  El DNI se usa para nominar y validar en puerta. Se guarda hasheado: solo se
                  muestran los últimos 4 dígitos.
                </p>

                <dl class="grid gap-y-2 text-[13px] sm:grid-cols-[130px_1fr]">
                  <dt class="text-fg-muted">Nombre</dt>
                  <dd class="font-semibold">{{ auth.profile()?.full_name ?? '—' }}</dd>
                  <dt class="text-fg-muted">Email</dt>
                  <dd class="font-semibold">{{ auth.profile()?.email }}</dd>
                  <dt class="text-fg-muted">DNI</dt>
                  <dd class="font-mono font-semibold">
                    @if (auth.hasDni()) {
                      ••••{{ auth.profile()?.dni_last4 }}
                      @if (auth.profile()?.dni_verified_at) {
                        <fv-chip tone="success">Verificado</fv-chip>
                      }
                    } @else {
                      <span class="font-sans font-normal text-danger-fg">sin declarar</span>
                    }
                  </dd>
                </dl>

                @if (!auth.hasDni()) {
                  <form class="mt-3 flex flex-wrap gap-2" (ngSubmit)="saveDni()">
                    <input
                      name="dni"
                      inputmode="numeric"
                      maxlength="8"
                      placeholder="Tu DNI (8 dígitos)"
                      required
                      [(ngModel)]="dni"
                      class="flex-1 rounded-[--radius-chip] border border-border px-3 py-2 text-[13px]"
                    />
                    <button
                      type="submit"
                      class="rounded-[--radius-chip] bg-navy px-4 py-2 text-[13px] font-bold text-white"
                    >
                      Guardar
                    </button>
                  </form>
                  <p class="mt-1.5 text-[12px] text-danger-fg">
                    Hace falta declarar tu DNI antes de pagar.
                  </p>
                }
              </section>

              <!-- Nominación -->
              <section class="rounded-[--radius-card] border border-border bg-surface p-5">
                <h2 class="mb-1 text-[16px] font-bold">Nominación de asistentes</h2>
                <p class="mb-3 text-[12.5px] text-fg-muted">
                  @if (strict()) {
                    Este evento exige nominar cada entrada: sin nominar no se permite el ingreso.
                  } @else {
                    Puedes pagar sin nominar todo, pero esas entradas entran a revisión manual en
                    puerta.
                  }
                </p>

                <ul class="space-y-2.5">
                  @for (it of o.order_items; track it.id; let i = $index) {
                    <li class="rounded-[--radius-inner] border border-border p-3">
                      <div class="flex flex-wrap items-center justify-between gap-2">
                        <span class="text-[13.5px] font-semibold">
                          Entrada {{ i + 1 }}
                          @if (it.seats) {
                            · Fila {{ it.seats.row_label }}, asiento {{ it.seats.seat_number }}
                          }
                        </span>
                        @if (it.nominated_at) {
                          <fv-chip tone="success">Nominada</fv-chip>
                        } @else if (strict()) {
                          <fv-chip tone="danger">Falta nominar</fv-chip>
                        } @else {
                          <fv-chip tone="warn">Sin nominar</fv-chip>
                        }
                      </div>

                      @if (it.nominated_at) {
                        <p class="mt-1 text-[12.5px] text-fg-muted">
                          {{ it.attendee_name }} · DNI ••••{{ it.attendee_dni_last4 }}
                        </p>
                      } @else {
                        <!-- El copy dice la CONSECUENCIA, no una advertencia genérica -->
                        <p class="mt-1 text-[12px]" [class]="strict() ? 'text-danger-fg' : 'text-warn-fg'">
                          @if (strict()) {
                            Sin nominar, esta entrada no permite el ingreso.
                          } @else {
                            Sin nominar — se generará alerta en puerta (modo flexible).
                          }
                        </p>
                        <form class="mt-2 grid gap-1.5 sm:grid-cols-[1fr_8rem_auto]" (ngSubmit)="nominate(it.id)">
                          <input
                            [name]="'n' + it.id"
                            placeholder="Nombre completo"
                            required
                            [(ngModel)]="nom.name"
                            class="rounded-[--radius-chip] border border-border px-3 py-2 text-[13px]"
                          />
                          <input
                            [name]="'d' + it.id"
                            inputmode="numeric"
                            maxlength="8"
                            placeholder="DNI"
                            required
                            [(ngModel)]="nom.dni"
                            class="rounded-[--radius-chip] border border-border px-3 py-2 text-[13px]"
                          />
                          <button
                            type="submit"
                            [disabled]="store.loading()"
                            class="rounded-[--radius-chip] border border-border bg-surface px-3 py-2 text-[12.5px] font-semibold disabled:opacity-50"
                          >
                            Nominar
                          </button>
                        </form>
                      }
                    </li>
                  }
                </ul>
              </section>
            </div>

            <!-- Resumen: el desglose desde el primer momento -->
            <aside>
              <section class="rounded-[--radius-card] border border-border bg-surface p-4">
                <h2 class="mb-1 text-[15px] font-bold">Resumen</h2>
                <p class="mb-3 text-[12px] text-fg-muted">
                  {{ o.order_items.length }}
                  {{ o.order_items.length === 1 ? 'entrada' : 'entradas' }}
                </p>

                <fv-price-breakdown [lines]="lines()" [totalCents]="o.total_cents" />

                <button
                  type="button"
                  (click)="pay(o)"
                  [disabled]="!canPay(o)"
                  class="mt-4 w-full rounded-[--radius-chip] bg-coral px-4 py-3 text-[14px] font-bold text-white disabled:opacity-50"
                >
                  {{ o.status === 'awaiting_payment' ? 'Procesando…' : 'Pagar y emitir tickets' }}
                </button>

                <!-- Art. 2.1: hasta el pago confirmado no hay entrada válida -->
                <p class="mt-2 text-[11.5px] text-fg-muted">
                  Tus tickets se emiten solo tras pago confirmado y viven en tu wallet.
                </p>

                @if (blockedReason(o); as why) {
                  <p class="mt-2 text-[12px] font-semibold text-danger-fg">{{ why }}</p>
                }

                <p class="mt-3 border-t border-border pt-2 text-[11px] text-fg-subtle">
                  Pago en sandbox. Todavía no se procesan cobros reales.
                </p>
              </section>
            </aside>
          </div>
        }
      </div>
    } @else if (!store.loading()) {
      <div class="mx-auto max-w-md py-16 text-center">
        <h1 class="text-xl font-black">No encontramos esa compra</h1>
        <p class="mt-2 text-[13.5px] text-fg-muted">
          Puede que el enlace esté mal o que la orden sea de otra cuenta.
        </p>
        <a routerLink="/eventos" class="mt-4 inline-block text-[13px] font-semibold text-coral">
          Ver eventos
        </a>
      </div>
    }
  `,
})
export class CheckoutPage implements OnDestroy {
  readonly id = input.required<string>();

  protected readonly store = inject(CheckoutStore);
  protected readonly auth = inject(AuthStore);

  protected readonly order = signal<OrderWithItems | null>(null);
  protected readonly now = signal(Date.now());
  protected dni = '';
  protected nom = { name: '', dni: '' };

  private timer?: ReturnType<typeof setInterval>;

  protected readonly left = computed(() => {
    this.now();
    return secondsLeft(this.order()?.reserved_until ?? null);
  });
  protected readonly clock = computed(() => `quedan ${mmss(this.left())}`);

  protected readonly strict = computed(() => this.order()?.events?.nomination_mode === 'strict');

  /** Ya se eligió zona y asiento en el detalle: aquí se está en «Datos». */
  protected readonly step = computed<CheckoutStep>(() => {
    const s = this.order()?.status;
    if (s === 'paid') return 'wallet';
    if (s === 'awaiting_payment') return 'pago';
    return 'datos';
  });

  /**
   * Una compra sin asientos no pasó por el paso «Asientos». Se marca hecho, no
   * se oculta: el fan no debe sentir que el flujo cambió.
   */
  protected readonly skipped = computed<CheckoutStep[]>(() =>
    this.order()?.order_items.some((i) => i.seat_id) ? [] : ['asientos'],
  );

  /**
   * El desglose. Los importes vienen del servidor en céntimos; aquí solo se
   * ordenan y se formatean (Art. 5).
   *
   * El cargo aparece SIEMPRE, incluso en cero: ocultarlo cuando lo absorbe el
   * organizador rompería la costumbre de verlo, y es justo esa costumbre la que
   * evita que se lea como una sorpresa cuando sí se cobra.
   */
  protected readonly lines = computed<PriceLine[]>(() => {
    const o = this.order();
    if (!o) return [];
    const out: PriceLine[] = [
      {
        label: `${o.order_items.length} ${o.order_items.length === 1 ? 'entrada' : 'entradas'}`,
        valueCents: o.subtotal_cents,
        kind: 'base',
      },
    ];
    if (o.discount_cents > 0) {
      out.push({ label: 'Descuento', valueCents: o.discount_cents, kind: 'discount' });
    }
    out.push({
      label:
        o.service_charge_payer === 'fan'
          ? `Cargo de servicio Feventi (${o.service_charge_bps / 100}%)`
          : 'Cargo de servicio · absorbido por el organizador',
      valueCents: o.service_charge_cents,
      kind: 'charge',
    });
    return out;
  });

  constructor() {
    queueMicrotask(() => void this.load());
    // Solo mueve el reloj de la cuenta atrás; quien decide si la reserva sigue
    // viva es el servidor.
    this.timer = setInterval(() => this.now.set(Date.now()), 1000);
  }

  ngOnDestroy(): void {
    clearInterval(this.timer);
  }

  private async load(): Promise<void> {
    const { data } = await this.store.get(this.id());
    this.order.set((data as OrderWithItems | null) ?? null);
  }

  protected isLive(o: OrderWithItems): boolean {
    return o.status === 'reserved' || o.status === 'awaiting_payment' || o.status === 'failed';
  }

  protected canPay(o: OrderWithItems): boolean {
    if (this.store.loading()) return false;
    if (o.status !== 'reserved' && o.status !== 'failed') return false;
    if (this.left() <= 0) return false;
    if (!this.auth.hasDni()) return false;
    if (this.strict() && o.order_items.some((i) => !i.nominated_at)) return false;
    return true;
  }

  /** Por qué está bloqueado el botón. Un botón gris sin motivo es un caso de soporte. */
  protected blockedReason(o: OrderWithItems): string | null {
    if (o.status === 'awaiting_payment') return null;
    if (this.left() <= 0) return 'La reserva venció. Vuelve a elegir tus entradas.';
    if (!this.auth.hasDni()) return 'Declara tu DNI para poder pagar.';
    if (this.strict()) {
      const n = o.order_items.filter((i) => !i.nominated_at).length;
      if (n > 0) {
        return `Faltan ${n} ${n === 1 ? 'entrada' : 'entradas'} por nominar.`;
      }
    }
    return null;
  }

  protected async saveDni(): Promise<void> {
    const { error } = await this.auth.setOwnDni(this.dni);
    if (!error) this.dni = '';
  }

  protected async nominate(itemId: string): Promise<void> {
    const { error } = await this.store.nominate(itemId, this.nom.name, this.nom.dni);
    if (!error) {
      this.nom = { name: '', dni: '' };
      await this.load();
    }
  }

  /**
   * Deja la orden en `awaiting_payment` y bloquea el botón.
   *
   * La emisión NO ocurre aquí: `confirm_payment` es de `service_role` y la llama
   * el webhook de la pasarela (Art. 9.4). Esta pantalla pide; no decide.
   */
  protected async pay(o: OrderWithItems): Promise<void> {
    const { error } = await this.store.startPayment(o.id);
    if (error) return;
    await this.load();
  }

  protected longDate(iso: string): string {
    return new Date(iso).toLocaleString('es-PE', {
      day: 'numeric',
      month: 'long',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });
  }

  protected readonly money = soles;
}
