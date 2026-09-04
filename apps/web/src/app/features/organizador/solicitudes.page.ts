import { Component, ChangeDetectionStrategy, computed, inject, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { AuthStore } from '../../core/auth.store';
import { supabase } from '../../core/supabase.client';
import { Chip } from '../../shared/ui/chip';
import { EventsStore, type EventRow } from '../eventos/events.store';
import { EVENT_STATUS, type EventStatus } from '../eventos/event-status';

/**
 * Mis solicitudes y eventos. Lo que requiere acción va arriba: el objetivo de
 * la pantalla es que el organizador sepa qué tiene que hacer hoy, no que
 * contemple una tabla.
 */
@Component({
  selector: 'fv-org-solicitudes',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Chip],
  template: `
    <header class="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 class="text-2xl font-black tracking-[-0.5px]">Mis eventos</h1>
        <p class="mt-1 text-[13px] text-fg-muted">
          Ningún evento vende entradas hasta que Feventi lo aprueba y tú lo publicas.
        </p>
      </div>
      @if (organizerId(); as oid) {
        <button
          type="button"
          (click)="createEvent(oid)"
          [disabled]="store.loading()"
          class="rounded-[--radius-chip] bg-coral px-4 py-2.5 text-[13px] font-bold text-white disabled:opacity-50"
        >
          Nuevo evento
        </button>
      }
    </header>

    @if (store.error(); as e) {
      <p class="mb-4 rounded-[--radius-chip] bg-danger-bg px-3 py-2 text-[13px] text-danger-fg">
        {{ e }}
      </p>
    }

    @if (!organizerId() && !store.loading()) {
      <div class="rounded-[--radius-card] border border-border bg-surface p-6">
        <h2 class="text-[16px] font-bold">Todavía no tienes un organizador aprobado</h2>
        <p class="mt-1.5 text-[13px] text-fg-muted">
          Para crear eventos, Feventi primero tiene que aprobar tu alta como organizador.
        </p>
      </div>
    }

    @if (needsAction().length) {
      <section class="mb-8">
        <h2 class="mb-2 text-[12px] font-bold uppercase tracking-wide text-fg-muted">
          Requiere tu acción
        </h2>
        <div class="space-y-2">
          @for (ev of needsAction(); track ev.id) {
            <a
              [routerLink]="['/organizador/eventos', ev.id]"
              class="block rounded-[--radius-card] border-2 border-coral bg-danger-bg p-4"
            >
              <div class="flex flex-wrap items-center gap-2">
                <span class="font-mono text-[12px] font-semibold text-fg-soft">{{ ev.code }}</span>
                <span class="font-bold">{{ ev.title || 'Sin título' }}</span>
                <fv-chip [tone]="copy(ev.status).tone">{{ copy(ev.status).label }}</fv-chip>
              </div>
              <p class="mt-1.5 text-[13px] text-danger-fg">{{ copy(ev.status).nextStep }}</p>
            </a>
          }
        </div>
      </section>
    }

    @for (group of grouped(); track group.status) {
      <section class="mb-6">
        <h2 class="mb-2 flex items-center gap-2 text-[12px] font-bold uppercase tracking-wide text-fg-muted">
          {{ copy(group.status).label }}
          <span class="font-normal normal-case tracking-normal">({{ group.rows.length }})</span>
        </h2>
        <div class="space-y-2">
          @for (ev of group.rows; track ev.id) {
            <a
              [routerLink]="['/organizador/eventos', ev.id]"
              class="block rounded-[--radius-card] border border-border bg-surface p-4"
            >
              <div class="flex flex-wrap items-center gap-2">
                <span class="font-mono text-[12px] font-semibold text-fg-soft">{{ ev.code }}</span>
                <span class="font-bold">{{ ev.title || 'Sin título' }}</span>
                <fv-chip [tone]="copy(ev.status).tone">{{ copy(ev.status).label }}</fv-chip>
                @if (copy(ev.status).selling) {
                  <fv-chip tone="success" [dot]="true">A la venta</fv-chip>
                }
              </div>
              <p class="mt-1 text-[12.5px] text-fg-muted">{{ meta(ev) }}</p>
              @if (copy(ev.status).nextStep; as step) {
                <p class="mt-1.5 text-[12.5px] text-fg-soft">{{ step }}</p>
              }
            </a>
            <!-- El panel se ofrece solo cuando hay algo que mirar. Un enlace a
                 un dashboard de ceros, sobre un evento que aún no vende, invita
                 a un clic que decepciona. -->
            @if (copy(ev.status).selling || ev.status === 'paused' || ev.status === 'finished') {
              <a
                [routerLink]="['/organizador/eventos', ev.id, 'panel']"
                class="mt-1 inline-block text-[12.5px] font-semibold text-violet"
              >
                Ver ventas y accesos →
              </a>
            }
          }
        </div>
      </section>
    }

    @if (!rows().length && !store.loading() && organizerId()) {
      <div class="rounded-[--radius-card] border border-border bg-surface p-6 text-center">
        <p class="text-[14px] font-semibold">Todavía no has creado ningún evento</p>
        <p class="mt-1 text-[13px] text-fg-muted">
          Crea uno, completa la ficha y envíalo a revisión.
        </p>
      </div>
    }
  `,
})
export class OrgSolicitudesPage {
  protected readonly store = inject(EventsStore);
  private readonly auth = inject(AuthStore);
  private readonly router = inject(Router);

  protected readonly rows = signal<readonly EventRow[]>([]);
  protected readonly organizerId = signal<string | null>(null);

  /** `changes_requested` y `setup` son los que esperan algo del organizador. */
  protected readonly needsAction = computed(() =>
    this.rows().filter((e) => e.status === 'changes_requested' || e.status === 'setup'),
  );

  protected readonly grouped = computed(() => {
    const pending = new Set(this.needsAction().map((e) => e.id));
    const order: EventStatus[] = [
      'published',
      'paused',
      'pending_review',
      'draft',
      'approved',
      'rejected',
      'cancelled',
      'finished',
    ];
    return order
      .map((status) => ({
        status,
        rows: this.rows().filter((e) => e.status === status && !pending.has(e.id)),
      }))
      .filter((g) => g.rows.length > 0);
  });

  constructor() {
    void this.load();
  }

  private async load(): Promise<void> {
    const uid = this.auth.userId();
    if (!uid) return;

    // El organizador aprobado al que pertenezco. La RLS ya limita lo visible.
    const { data: orgs } = await supabase
      .from('organizers')
      .select('id, status')
      .eq('status', 'approved')
      .limit(1);
    this.organizerId.set(orgs?.[0]?.id ?? null);

    const { data } = await this.store.listMine();
    this.rows.set((data as EventRow[] | null) ?? []);
  }

  protected copy(s: EventStatus) {
    return EVENT_STATUS[s];
  }

  protected meta(ev: EventRow): string {
    const parts: string[] = [];
    if (ev.starts_at) {
      parts.push(
        new Date(ev.starts_at).toLocaleDateString('es-PE', {
          day: 'numeric',
          month: 'long',
          year: 'numeric',
        }),
      );
    }
    if (ev.capacity) parts.push(`aforo ${ev.capacity.toLocaleString('es-PE')}`);
    return parts.join(' · ') || 'Sin fecha ni aforo definidos';
  }

  protected async createEvent(organizerId: string): Promise<void> {
    const { data, error } = await this.store.create(organizerId);
    if (error) return;
    await this.router.navigate(['/organizador/eventos', data]);
  }
}
