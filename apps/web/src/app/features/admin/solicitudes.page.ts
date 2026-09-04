import { Component, ChangeDetectionStrategy, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { Chip } from '../../shared/ui/chip';
import { Metric } from '../../shared/ui/metric';
import { EventsStore, type EventRow } from '../eventos/events.store';
import { EVENT_STATUS, REQUEST_STATUSES, type EventStatus } from '../eventos/event-status';

type Row = EventRow & {
  organizers?: { trade_name: string | null; legal_name: string; ruc: string | null } | null;
  venues?: { name: string; city: string } | null;
};

/**
 * Cola de revisión de Admin. La misma tabla `events` que ve el organizador;
 * lo que cambia es quién consulta y qué le deja ver la RLS.
 *
 * `pending_review` va primero y con más peso visual: es lo único donde alguien
 * está esperando una respuesta de Feventi.
 */
@Component({
  selector: 'fv-admin-solicitudes',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Chip, Metric],
  template: `
    <header class="mb-5">
      <h1 class="text-2xl font-black tracking-[-0.5px]">Solicitudes de evento</h1>
        <a routerLink="/admin/soporte" class="mt-1 inline-block text-[12.5px] font-semibold text-violet">
          Ir a la cola de soporte →
        </a>
      <p class="mt-1 text-[13px] text-fg-muted">
        Ninguna solicitud pasa a venta sin aprobación. Toda decisión queda registrada.
      </p>
    </header>

    <div class="mb-6 grid gap-3 sm:grid-cols-3">
      <fv-metric
        label="Esperando respuesta"
        [value]="count('pending_review').toString()"
        [sub]="'de ' + rows().length + ' solicitudes'"
        color="var(--color-warn-fg)"
      />
      <fv-metric
        label="Con info pendiente"
        [value]="count('changes_requested').toString()"
        sub="esperando al organizador"
      />
      <fv-metric
        label="En configuración"
        [value]="count('setup').toString()"
        sub="aprobadas, sin publicar"
        color="var(--color-info-fg)"
      />
    </div>

    <nav class="mb-4 flex flex-wrap gap-1.5">
      <button
        type="button"
        (click)="filter.set(null)"
        [class]="chipClass(filter() === null)"
      >
        Todas ({{ rows().length }})
      </button>
      @for (s of statuses; track s) {
        <button type="button" (click)="filter.set(s)" [class]="chipClass(filter() === s)">
          {{ label(s) }} ({{ count(s) }})
        </button>
      }
    </nav>

    @if (store.error(); as e) {
      <p class="mb-4 rounded-[--radius-chip] bg-danger-bg px-3 py-2 text-[13px] text-danger-fg">
        {{ e }}
      </p>
    }

    <div class="space-y-2">
      @for (ev of visible(); track ev.id) {
        <a
          [routerLink]="['/admin/solicitudes', ev.id]"
          class="block rounded-[--radius-card] border bg-surface p-4"
          [class]="
            ev.status === 'pending_review' ? 'border-warn-border border-2' : 'border-border'
          "
        >
          <div class="flex flex-wrap items-center gap-2">
            <span class="font-mono text-[12px] font-semibold text-fg-soft">{{ ev.code }}</span>
            <span class="font-bold">{{ ev.title || 'Sin título' }}</span>
            <fv-chip [tone]="copy(ev.status).tone">{{ copy(ev.status).label }}</fv-chip>
          </div>
          <p class="mt-1 text-[12.5px] text-fg-muted">{{ meta(ev) }}</p>
          @if (pendingItems(ev); as n) {
            @if (n > 0) {
              <p class="mt-1.5 text-[12.5px] font-semibold text-warn-fg">
                {{ n }} ítem{{ n === 1 ? '' : 's' }} del checklist sin marcar
              </p>
            }
          }
        </a>
      } @empty {
        <div class="rounded-[--radius-card] border border-border bg-surface p-6 text-center">
          @if (filter()) {
            <p class="text-[14px] font-semibold">Ninguna solicitud en este estado</p>
            <button
              type="button"
              (click)="filter.set(null)"
              class="mt-1 text-[13px] font-semibold text-coral"
            >
              Ver todas
            </button>
          } @else {
            <p class="text-[14px] font-semibold">Todavía no hay solicitudes</p>
          }
        </div>
      }
    </div>
  `,
})
export class AdminSolicitudesPage {
  protected readonly store = inject(EventsStore);
  protected readonly rows = signal<readonly Row[]>([]);
  protected readonly filter = signal<EventStatus | null>(null);

  protected readonly statuses: readonly EventStatus[] = [
    ...REQUEST_STATUSES,
    'setup',
    'published',
    'paused',
  ];

  protected readonly visible = computed(() => {
    const f = this.filter();
    const rows = f ? this.rows().filter((r) => r.status === f) : [...this.rows()];
    // Lo que espera respuesta de Feventi, arriba.
    const weight = (s: EventStatus) =>
      s === 'pending_review' ? 0 : s === 'changes_requested' ? 1 : 2;
    return rows.sort((a, b) => weight(a.status) - weight(b.status));
  });

  constructor() {
    void this.load();
  }

  private async load(): Promise<void> {
    const { data } = await this.store.listForReview();
    this.rows.set((data as Row[] | null) ?? []);
  }

  protected count(s: EventStatus): number {
    return this.rows().filter((r) => r.status === s).length;
  }

  protected copy(s: EventStatus) {
    return EVENT_STATUS[s];
  }

  protected label(s: EventStatus): string {
    return EVENT_STATUS[s].label;
  }

  protected chipClass(active: boolean): string {
    return active
      ? 'rounded-[--radius-chip] bg-navy px-3 py-1.5 text-[12.5px] font-semibold text-white'
      : 'rounded-[--radius-chip] border border-border bg-surface px-3 py-1.5 text-[12.5px] font-medium text-fg-soft';
  }

  protected meta(ev: Row): string {
    const parts = [ev.organizers?.trade_name || ev.organizers?.legal_name || 'Sin organizador'];
    if (ev.venues) parts.push(`${ev.venues.name} · ${ev.venues.city}`);
    if (ev.starts_at) {
      parts.push(
        new Date(ev.starts_at).toLocaleDateString('es-PE', { day: 'numeric', month: 'long' }),
      );
    }
    if (ev.submitted_at) {
      parts.push(
        `enviada el ${new Date(ev.submitted_at).toLocaleDateString('es-PE', {
          day: '2-digit',
          month: '2-digit',
        })}`,
      );
    }
    return parts.join(' · ');
  }

  protected pendingItems(ev: Row): number {
    const c = ev.review_checklist as Record<string, string> | null;
    if (!c) return 0;
    return Object.values(c).filter((v) => v === 'pending').length;
  }
}
