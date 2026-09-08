import { Component, ChangeDetectionStrategy, computed, inject, input, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { Chip } from '../../shared/ui/chip';
import { Metric } from '../../shared/ui/metric';
import { SupportButton } from '../../shared/ui/support-button';
import { bpsToPercent, negative, soles } from '../../shared/ui/money';
import { EVENT_STATUS, type EventStatus } from '../eventos/event-status';
import { EventsStore, type EventRow } from '../eventos/events.store';
import {
  DashboardStore,
  tranches,
  type EventSales,
  type GateStatsRow,
  type PhaseSales,
} from './dashboard.store';

/**
 * El dashboard de UN evento.
 *
 * La palabra «disponible» NO aparece en esta pantalla, y no es una casualidad de
 * redacción: es AC-13. El riesgo principal del Art. 5 es que el organizador lea
 * el neto estimado como plata suya y la gaste. Cada sitio donde aparece ese
 * número dice «estimado», y los tramos van rotulados como estimación, sin fecha
 * de pago.
 *
 * Vendido y validado son DOS métricas y van en bloques distintos: confundirlas
 * —«vendí 800, ¿por qué el aforo dice 40 %?»— es un error caro y evitable.
 *
 * Y el organizador no ve a sus compradores. La pantalla lo dice en una línea con
 * su razón, en vez de dejar un hueco que parezca un bug y acabe en soporte.
 */
@Component({
  selector: 'fv-org-dashboard',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Chip, Metric, SupportButton],
  template: `
    @if (evento(); as e) {
      <header class="mb-6">
        <a routerLink="/organizador/eventos" class="text-[12px] text-fg-muted">‹ Mis eventos</a>
        <div class="mt-1 flex flex-wrap items-start justify-between gap-3">
          <div>
            <h1 class="text-2xl font-black tracking-[-0.5px]">{{ e.title ?? 'Sin título' }}</h1>
            <p class="mt-1 text-[13px] text-fg-muted">
              <span class="font-mono">{{ e.code }}</span>
              @if (e.starts_at) { · {{ fecha(e.starts_at) }} }
            </p>
          </div>
          <fv-chip [tone]="estado(e.status).tone">{{ estado(e.status).label }}</fv-chip>
        </div>

        @if (e.status !== 'published') {
          <!-- Art. 4: nada se publica solo. Si no vende, la cabecera dice por qué. -->
          <p class="mt-3 rounded-[--radius-chip] bg-warn-bg px-3 py-2.5 text-[12.5px] text-warn-fg">
            {{ porQueNoVende(e.status) }}
          </p>
        }
      </header>

      @if (store.error(); as err) {
        <p role="alert" class="mb-4 rounded-[--radius-chip] bg-danger-bg px-3 py-2 text-[13px] text-danger-fg">
          {{ err }}
        </p>
      }

      @if (ventas(); as s) {
        <!-- ── Métricas ─────────────────────────────────────────────────── -->
        <section class="mb-8 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <fv-metric
            label="Entradas vendidas"
            [value]="s.tickets_sold.toLocaleString('es-PE')"
            [sub]="'de ' + (s.capacity ?? 0).toLocaleString('es-PE') + ' de aforo'"
          />
          <fv-metric
            label="Venta bruta"
            [value]="money(s.gross_cents)"
            [sub]="'lo cobrado a los compradores'"
          />
          <fv-metric
            label="Neto estimado"
            [value]="money(s.net_estimated_cents)"
            sub="estimado, aún no liquidado"
            color="var(--color-turquoise)"
          />
          <fv-metric
            label="Cortesías"
            value="—"
            sub="el módulo llega en Fase 2"
          />
        </section>

        <div class="grid gap-6 lg:grid-cols-2">
          <!-- ── Ventas por fase ────────────────────────────────────────── -->
          <section class="rounded-[--radius-card] border border-border bg-surface p-5">
            <h2 class="text-[15px] font-bold">Ventas por fase</h2>
            <p class="mt-0.5 text-[12px] text-fg-muted">
              Solo entradas pagadas. Las reservas sin pagar no cuentan.
            </p>

            <ul class="mt-4 space-y-3">
              @for (f of fases(); track f.phase_id ?? f.name) {
                <li>
                  <div class="flex items-baseline justify-between gap-3 text-[13px]">
                    <span class="font-semibold">{{ f.name }}</span>
                    <span class="tabular-nums">
                      {{ money(f.gross_cents) }}
                      <span class="text-fg-muted">· {{ f.tickets }}</span>
                    </span>
                  </div>
                  <div class="mt-1 h-2 overflow-hidden rounded-full bg-muted">
                    <div
                      class="h-full rounded-full bg-violet"
                      [style.width.%]="ancho(f)"
                    ></div>
                  </div>
                </li>
              } @empty {
                <li class="py-2 text-[13px] text-fg-muted">Todavía no hay fases con ventas.</li>
              }
            </ul>

            @if (hayAgregadas()) {
              <!-- AC-06: decir POR QUÉ hay una fila agregada, o parece un bug. -->
              <p class="mt-3 border-t border-border pt-3 text-[11.5px] text-fg-muted">
                Las fases con menos de 5 entradas se agrupan en «Otras fases»: con tan
                pocas, el detalle permitiría identificar a un comprador concreto.
              </p>
            }
          </section>

          <!-- ── Resumen financiero (Art. 5) ────────────────────────────── -->
          <section class="rounded-[--radius-card] border border-border bg-surface p-5">
            <h2 class="text-[15px] font-bold">Resumen financiero</h2>

            <dl class="mt-4 space-y-2 text-[13px]">
              <div class="flex justify-between gap-3">
                <dt>Venta bruta</dt>
                <dd class="tabular-nums font-semibold">{{ money(s.gross_cents) }}</dd>
              </div>
              <div class="flex justify-between gap-3">
                <!-- No es un cargo nuevo: es el mismo del Art. 5, y la línea dice
                     quién lo pagó según service_charge_payer. -->
                <dt class="text-fg-muted">
                  Comisión Feventi ({{ pct(s.service_charge_bps) }})
                  <span class="block text-[11.5px]">{{ quienPaga(s) }}</span>
                </dt>
                <dd class="tabular-nums">{{ menos(s.feventi_commission_cents) }}</dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-fg-muted">Devoluciones</dt>
                <dd class="tabular-nums">{{ menos(s.refunds_cents) }}</dd>
              </div>
              <div
                class="flex justify-between gap-3 border-t border-border pt-2.5 text-[15px] font-black"
              >
                <dt>Neto estimado a liquidar</dt>
                <dd class="tabular-nums text-success-fg">{{ money(s.net_estimated_cents) }}</dd>
              </div>
            </dl>

            @if (tramos(s).length) {
              <div class="mt-4 border-t border-border pt-3">
                <p class="text-[12px] font-bold uppercase tracking-wide text-fg-muted">
                  Liquidación estimada
                </p>
                <ul class="mt-2 space-y-1.5 text-[12.5px]">
                  @for (t of tramos(s); track t.trigger) {
                    <li class="flex justify-between gap-3">
                      <span class="text-fg-muted">{{ t.trigger }}</span>
                      <span class="tabular-nums font-semibold">
                        {{ t.pct }}% · {{ money(tramoCents(s, t.pct)) }}
                      </span>
                    </li>
                  }
                </ul>
                <!-- AC-14: sin fecha de pago. La liquidación real es Fase 2, y
                     poner una fecha aquí sería prometer lo que no existe. -->
                <p class="mt-2.5 text-[11.5px] text-fg-muted">
                  Estimación sobre el neto actual, según la política declarada del evento.
                  No son pagos programados: la liquidación con movimientos reales llega
                  en la siguiente fase.
                </p>
              </div>
            }
          </section>
        </div>

        <!-- ── Accesos ──────────────────────────────────────────────────── -->
        <section class="mt-6 rounded-[--radius-card] border border-border bg-surface p-5">
          <div class="flex flex-wrap items-baseline justify-between gap-2">
            <h2 class="text-[15px] font-bold">Accesos en puerta</h2>
            <span class="text-[12px] text-fg-muted">
              Ocupación de acceso: {{ ocupacion() }}% del aforo ha ingresado
            </span>
          </div>

          @if (puertas().length) {
            <div class="mt-4 overflow-x-auto">
              <table class="w-full min-w-[420px] text-[13px]">
                <thead>
                  <tr class="border-b border-border text-left text-[11.5px] uppercase tracking-wide text-fg-muted">
                    <th class="pb-2 font-semibold">Puerta</th>
                    <th class="pb-2 text-right font-semibold">Validados</th>
                    <th class="pb-2 text-right font-semibold">Revisión</th>
                    <th class="pb-2 text-right font-semibold">Rechazos</th>
                    <th class="pb-2 text-right font-semibold">Capturas</th>
                  </tr>
                </thead>
                <tbody>
                  @for (g of puertas(); track g.gate) {
                    <tr class="border-b border-border last:border-0">
                      <td class="py-2 font-semibold">{{ g.gate }}</td>
                      <td class="py-2 text-right tabular-nums text-success-fg">{{ g.allowed }}</td>
                      <td class="py-2 text-right tabular-nums">{{ g.manual_review }}</td>
                      <td class="py-2 text-right tabular-nums">{{ g.denied + g.already_used }}</td>
                      <td class="py-2 text-right tabular-nums">{{ g.screenshots }}</td>
                    </tr>
                  }
                </tbody>
              </table>
            </div>
            <p class="mt-3 text-[11.5px] text-fg-muted">
              «Ocupación de acceso» es gente que ya entró; no es lo mismo que entradas
              vendidas. Las capturas son códigos válidos pero caducados: casi siempre
              alguien mostrando un pantallazo en vez de la app.
            </p>
          } @else {
            <p class="mt-3 text-[13px] text-fg-muted">
              Sin escaneos todavía. Los accesos aparecen aquí en vivo durante el evento.
            </p>
          }
        </section>

        <!-- 009/AC-21 · historia 5: el organizador abre un caso sobre SU evento
             —ventas, staff, liquidación o una emergencia durante el evento—. -->
        <div class="mt-6 rounded-[--radius-card] border border-border bg-surface p-4">
          <p class="text-[14px] font-bold">¿Necesitas ayuda con este evento?</p>
          <p class="mt-0.5 text-[12.5px] text-fg-muted">
            Ventas, liquidación, staff o una urgencia durante el evento.
          </p>
          <div class="mt-2">
            <fv-support-button
              [ctx]="{ eventId: e.id }"
              defaultKind="other"
              [contextLabel]="e.title ?? 'este evento'"
              label="Abrir un caso"
            />
          </div>
        </div>

        <!-- Art. 7.5 · explicar el hueco, o acaba en un caso de soporte -->
        <p class="mt-6 rounded-[--radius-card] border border-border bg-muted px-4 py-3 text-[12.5px] text-fg-muted">
          Aquí no verás nombres, correos ni documentos de tus compradores. Feventi es
          quien responde ante ellos por sus datos, así que el dashboard solo muestra
          agregados. Para una incidencia concreta, soporte puede actuar sobre una
          entrada sin exponer sus datos.
        </p>
      } @else if (!store.loading()) {
        <p class="rounded-[--radius-card] border border-border bg-surface p-6 text-[13px] text-fg-muted">
          No hay datos de venta para este evento.
        </p>
      }
    }
  `,
})
export class OrgDashboardPage {
  /** Del router. */
  readonly id = input.required<string>();

  protected readonly store = inject(DashboardStore);
  private readonly events = inject(EventsStore);

  protected readonly money = soles;
  protected readonly menos = negative;
  protected readonly pct = bpsToPercent;
  protected readonly tramos = (s: EventSales) => tranches(s.payout_policy);

  protected readonly evento = signal<EventRow | null>(null);
  protected readonly ventas = signal<EventSales | null>(null);
  protected readonly fases = signal<readonly PhaseSales[]>([]);
  protected readonly puertas = signal<readonly GateStatsRow[]>([]);

  protected readonly hayAgregadas = computed(() => this.fases().some((f) => !f.phase_id));

  /** AC-18: validados sobre aforo. Ocupación de ACCESO, no de venta. */
  protected readonly ocupacion = computed(() => {
    const aforo = this.ventas()?.capacity ?? 0;
    const dentro = this.puertas().reduce((n, g) => n + g.allowed, 0);
    return aforo ? Math.round((dentro / aforo) * 100) : 0;
  });

  private readonly mayor = computed(() =>
    Math.max(1, ...this.fases().map((f) => f.gross_cents)),
  );

  constructor() {
    queueMicrotask(() => void this.cargar());
  }

  private async cargar(): Promise<void> {
    const { data } = await this.events.get(this.id());
    this.evento.set(data ?? null);

    const { sales, phases, gates } = await this.store.load(this.id());
    this.ventas.set(sales);
    this.fases.set(phases);
    this.puertas.set(gates);
  }

  protected ancho(f: PhaseSales): number {
    return Math.round((f.gross_cents / this.mayor()) * 100);
  }

  /**
   * El tramo, en soles. Es aritmética de PORCENTAJE sobre un importe que ya vino
   * del servidor, no una suma de conceptos de dinero: la fórmula del neto vive
   * entera en `v_event_sales`. Y el redondeo aquí no puede descuadrar nada
   * porque es una estimación rotulada como tal, no un pago.
   */
  protected tramoCents(s: EventSales, pct: number): number {
    return Math.round((s.net_estimated_cents * pct) / 100);
  }

  protected quienPaga(s: EventSales): string {
    return s.service_charge_payer === 'fan'
      ? 'la pagó el comprador sobre el precio'
      : 'la absorbes tú: el comprador pagó solo el precio';
  }

  protected estado(s: string) {
    return EVENT_STATUS[s as EventStatus];
  }

  protected porQueNoVende(s: string): string {
    return (
      {
        draft: 'Es un borrador: no vende y no es visible. Complétalo y envíalo a revisión.',
        pending_review: 'En revisión por Feventi. No vende hasta que se apruebe y lo publiques.',
        changes_requested: 'Feventi pidió información. Revisa las notas y vuelve a enviarlo.',
        rejected: 'Rechazado por Feventi. Las notas dicen el motivo.',
        approved: 'Aprobado, pero aún sin inventario. Carga zonas, fases y precios.',
        setup: 'Con inventario en preparación. Publícalo cuando esté listo para vender.',
        paused: 'Venta pausada. Las entradas ya emitidas siguen siendo válidas y entran en puerta.',
        cancelled: 'Evento cancelado.',
        finished: 'Evento finalizado.',
      }[s] ?? 'Este evento no está vendiendo entradas.'
    );
  }

  protected fecha(iso: string): string {
    return new Date(iso).toLocaleDateString('es-PE', {
      weekday: 'long',
      day: 'numeric',
      month: 'long',
      year: 'numeric',
    });
  }
}
