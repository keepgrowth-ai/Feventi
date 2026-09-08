import { Component, ChangeDetectionStrategy, computed, inject, input, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { Chip } from '../../shared/ui/chip';
import { bpsToPercent } from '../../shared/ui/money';
import type { ReviewChecklist } from '../../core/db.types';
import { EventsStore, type EventRow, type ReviewNote } from '../eventos/events.store';
import {
  CHECKLIST_LABELS,
  CHECKLIST_STATE_LABEL,
  CHECKLIST_TONE,
  EVENT_STATUS,
} from '../eventos/event-status';

type Row = EventRow & {
  organizers?: { trade_name: string | null; legal_name: string; ruc: string | null } | null;
  venues?: { name: string; city: string; capacity: number | null } | null;
};

type ChecklistState = 'ok' | 'pending' | 'na';

/**
 * Revisión de una solicitud. El checklist se marca aquí, y cada decisión deja
 * un asiento con el checklist congelado en ese instante — sin eso, «se aprobó
 * con el plano pendiente» es indemostrable seis meses después.
 *
 * «Pedir info» exige observación: el servidor la rechaza vacía, y la UI también,
 * para no gastar un viaje. Una solicitud en «requiere info» sin decir cuál es
 * una solicitud parada para siempre.
 */
@Component({
  selector: 'fv-admin-solicitud-detalle',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule, RouterLink, Chip],
  template: `
    @if (ev(); as e) {
      <a routerLink="/admin/solicitudes" class="text-[12.5px] font-semibold text-coral-fg"
        >← Solicitudes</a
      >

      <header class="mt-3 mb-5 flex flex-wrap items-start justify-between gap-4">
        <div>
          <div class="flex flex-wrap items-center gap-2">
            <span class="font-mono text-[13px] font-semibold text-fg-soft">{{ e.code }}</span>
            <h1 class="text-2xl font-black tracking-[-0.5px]">
              {{ e.title || 'Evento sin título' }}
            </h1>
            <fv-chip [tone]="copy().tone">{{ copy().label }}</fv-chip>
          </div>
          <p class="mt-1 text-[13px] text-fg-muted">
            {{ e.organizers?.trade_name || e.organizers?.legal_name }}
            @if (e.organizers?.ruc) {
              · RUC <span class="font-mono">{{ e.organizers?.ruc }}</span>
            }
          </p>
        </div>
      </header>

      @if (store.error(); as err) {
        <p role="alert" class="mb-4 rounded-[--radius-chip] bg-danger-bg px-3 py-2.5 text-[13px] text-danger-fg">
          {{ err }}
        </p>
      }
      @if (done(); as msg) {
        <p class="mb-4 rounded-[--radius-chip] bg-success-bg px-3 py-2 text-[13px] text-success-fg">
          {{ msg }}
        </p>
      }

      <div class="grid gap-5 lg:grid-cols-[1fr_340px]">
        <div class="space-y-5">
          <section class="rounded-[--radius-card] border border-border bg-surface p-5">
            <h2 class="mb-3 text-[16px] font-bold">Ficha enviada</h2>
            <dl class="grid gap-y-2 text-[13px] sm:grid-cols-[160px_1fr]">
              <dt class="text-fg-muted">Descripción</dt>
              <dd>{{ e.description || '—' }}</dd>
              <dt class="text-fg-muted">Categoría</dt>
              <dd>{{ e.category || '—' }}</dd>
              <dt class="text-fg-muted">Fecha y hora</dt>
              <dd>{{ e.starts_at ? when(e.starts_at) : '—' }}</dd>
              <dt class="text-fg-muted">Puertas</dt>
              <dd>{{ e.doors_at ? when(e.doors_at) : '—' }}</dd>
              <dt class="text-fg-muted">Lugar</dt>
              <dd>
                @if (e.venues) {
                  {{ e.venues.name }} · {{ e.venues.city }}
                  @if (e.venues.capacity) {
                    <span class="text-fg-muted">
                      (aforo del venue {{ e.venues.capacity.toLocaleString('es-PE') }})
                    </span>
                  }
                } @else {
                  —
                }
              </dd>
              <dt class="text-fg-muted">Aforo declarado</dt>
              <dd [class]="capacityWarn() ? 'font-semibold text-warn-fg' : ''">
                {{ e.capacity ? e.capacity.toLocaleString('es-PE') : '—' }}
                @if (capacityWarn()) {
                  — supera el aforo del venue
                }
              </dd>
              <dt class="text-fg-muted">Slug público</dt>
              <dd class="font-mono">{{ e.slug || '— falta, no podrá publicar' }}</dd>
            </dl>
          </section>

          <section class="rounded-[--radius-card] border border-border bg-surface p-5">
            <h2 class="mb-3 text-[16px] font-bold">Reglas comerciales</h2>
            <dl class="grid gap-y-2 text-[13px] sm:grid-cols-[160px_1fr]">
              <dt class="text-fg-muted">Límite por usuario</dt>
              <dd>{{ e.max_per_user }}</dd>
              <dt class="text-fg-muted">Cargo de servicio</dt>
              <dd>
                {{ bps(e.service_charge_bps) }} ·
                {{ e.service_charge_payer === 'fan' ? 'lo paga el fan' : 'lo absorbe el organizador' }}
              </dd>
              <dt class="text-fg-muted">Reventa oficial</dt>
              <dd>
                {{ e.resale_enabled ? 'permitida' : 'no permitida' }}
                @if (e.resale_enabled) {
                  · máx. {{ e.max_resales }} · comisión {{ bps(e.resale_commission_bps) }}
                }
              </dd>
              <dt class="text-fg-muted">QR disponible</dt>
              <dd>{{ e.qr_lead_days }} días antes del evento</dd>
              <dt class="text-fg-muted">Nominación</dt>
              <dd>
                {{ e.nomination_mode === 'strict' ? 'estricta' : 'flexible' }}
                <span class="text-fg-muted">
                  @if (e.nomination_mode === 'flexible') {
                    — sin nominar entra a revisión manual en puerta
                  } @else {
                    — sin nominar no entra
                  }
                </span>
              </dd>
            </dl>
          </section>

          @if (notes().length) {
            <section>
              <h2 class="mb-2 text-[12px] font-bold uppercase tracking-wide text-fg-muted">
                Historial de decisiones
              </h2>
              <ol class="space-y-2">
                @for (n of notes(); track n.id) {
                  <li class="rounded-[--radius-inner] border border-border bg-surface p-3">
                    <div class="flex flex-wrap items-baseline justify-between gap-2">
                      <span class="text-[13px] font-semibold">
                        {{ actionLabel(n.action) }}
                        @if (n.status_before && n.status_after) {
                          <span class="font-mono text-[11.5px] font-normal text-fg-muted">
                            {{ n.status_before }} → {{ n.status_after }}
                          </span>
                        }
                      </span>
                      <span class="text-[11.5px] text-fg-muted">{{ when(n.created_at) }}</span>
                    </div>
                    @if (n.note) {
                      <p class="mt-1 text-[13px] text-fg-soft">{{ n.note }}</p>
                    }
                  </li>
                }
              </ol>
            </section>
          }
        </div>

        <!-- Checklist + decisión -->
        <aside class="space-y-4">
          <section class="rounded-[--radius-card] border border-border bg-surface p-4">
            <h2 class="mb-1 text-[15px] font-bold">Checklist de {{ e.code }}</h2>
            <p class="mb-3 text-[12px] text-fg-muted">
              Se congela tal como esté al momento de decidir.
            </p>
            <ul class="space-y-2">
              @for (item of items(); track item.key) {
                <li>
                  <div class="mb-1 flex items-center justify-between gap-2">
                    <span class="text-[13px]">{{ item.label }}</span>
                    <fv-chip [tone]="item.tone">{{ item.stateLabel }}</fv-chip>
                  </div>
                  <div class="flex gap-1">
                    @for (opt of options; track opt) {
                      <button
                        type="button"
                        (click)="setItem(item.key, opt)"
                        [class]="optionClass(item.value === opt)"
                      >
                        {{ stateLabel(opt) }}
                      </button>
                    }
                  </div>
                </li>
              }
            </ul>
            <button
              type="button"
              (click)="saveChecklist(e.id)"
              [disabled]="store.loading()"
              class="mt-3 w-full rounded-[--radius-chip] border border-border px-3 py-2 text-[12.5px] font-semibold disabled:opacity-50"
            >
              Guardar checklist
            </button>
          </section>

          <section class="rounded-[--radius-card] border border-border bg-surface p-4">
            <h2 class="mb-2 text-[15px] font-bold">Decisión</h2>

            @if (e.status === 'pending_review') {
              <label class="block">
                <span class="text-[12px] font-semibold text-fg-soft">
                  Observación
                  <span class="font-normal text-fg-muted">
                    — obligatoria para pedir info o rechazar
                  </span>
                </span>
                <textarea
                  name="note"
                  rows="3"
                  [(ngModel)]="note"
                  placeholder="Falta plano del venue y detalle de zonas."
                  class="mt-1 w-full rounded-[--radius-chip] border border-border px-3 py-2 text-[13px]"
                ></textarea>
              </label>

              <div class="mt-3 space-y-2">
                <button
                  type="button"
                  (click)="approve(e.id)"
                  [disabled]="store.loading()"
                  class="w-full rounded-[--radius-chip] bg-turquoise px-4 py-2.5 text-[13px] font-bold text-on-turquoise disabled:opacity-50"
                >
                  Aprobar
                </button>
                <button
                  type="button"
                  (click)="requestInfo(e.id)"
                  [disabled]="store.loading() || !note.trim()"
                  class="w-full rounded-[--radius-chip] border-2 border-warn-border bg-warn-bg px-4 py-2.5 text-[13px] font-bold text-warn-fg disabled:opacity-50"
                >
                  Pedir información
                </button>
                <button
                  type="button"
                  (click)="reject(e.id)"
                  [disabled]="store.loading() || !note.trim()"
                  class="w-full rounded-[--radius-chip] border border-danger-border px-4 py-2.5 text-[13px] font-bold text-danger-fg disabled:opacity-50"
                >
                  Rechazar
                </button>
              </div>

              <p class="mt-3 text-[11.5px] text-fg-muted">
                Aprobar no publica el evento: pasa a configuración y el organizador decide cuándo
                abre la venta.
              </p>
            } @else if (e.status === 'published') {
              <label class="block">
                <span class="text-[12px] font-semibold text-fg-soft">Motivo</span>
                <textarea
                  name="note"
                  rows="2"
                  [(ngModel)]="note"
                  class="mt-1 w-full rounded-[--radius-chip] border border-border px-3 py-2 text-[13px]"
                ></textarea>
              </label>
              <button
                type="button"
                (click)="pause(e.id)"
                [disabled]="store.loading()"
                class="mt-3 w-full rounded-[--radius-chip] border-2 border-warn-border bg-warn-bg px-4 py-2.5 text-[13px] font-bold text-warn-fg disabled:opacity-50"
              >
                Pausar la venta
              </button>
              <p class="mt-2 text-[11.5px] text-fg-muted">
                Pausar detiene la venta y saca el evento del catálogo. Las entradas ya emitidas
                siguen siendo válidas y su QR funciona en puerta.
              </p>
            } @else if (e.status === 'paused') {
              <button
                type="button"
                (click)="resume(e.id)"
                [disabled]="store.loading()"
                class="w-full rounded-[--radius-chip] bg-turquoise px-4 py-2.5 text-[13px] font-bold text-on-turquoise disabled:opacity-50"
              >
                Reanudar la venta
              </button>
            } @else {
              <p class="text-[13px] text-fg-muted">{{ copy().meaning }}</p>
              @if (copy().nextStep; as step) {
                <p class="mt-1 text-[12.5px] text-fg-soft">{{ step }}</p>
              }
            }
          </section>
        </aside>
      </div>
    }
  `,
})
export class AdminSolicitudDetallePage {
  readonly id = input.required<string>();

  protected readonly store = inject(EventsStore);
  protected readonly ev = signal<Row | null>(null);
  protected readonly notes = signal<readonly ReviewNote[]>([]);
  protected readonly done = signal<string | null>(null);
  protected readonly checklist = signal<Record<string, ChecklistState>>({});

  protected note = '';
  protected readonly options: readonly ChecklistState[] = ['ok', 'pending', 'na'];
  protected readonly bps = bpsToPercent;

  protected readonly copy = computed(() => EVENT_STATUS[this.ev()?.status ?? 'draft']);

  protected readonly items = computed(() => {
    const c = this.checklist();
    return Object.entries(CHECKLIST_LABELS).map(([key, label]) => ({
      key,
      label,
      value: c[key],
      stateLabel: CHECKLIST_STATE_LABEL[c[key]] ?? c[key],
      tone: CHECKLIST_TONE[c[key]] ?? 'neutral',
    }));
  });

  /** Señal útil para el revisor: el aforo declarado no puede pasar el del venue. */
  protected readonly capacityWarn = computed(() => {
    const e = this.ev();
    const venueCap = e?.venues?.capacity;
    return !!e?.capacity && !!venueCap && e.capacity > venueCap;
  });

  constructor() {
    queueMicrotask(() => void this.load());
  }

  private async load(): Promise<void> {
    const [{ data: ev }, { data: notes }] = await Promise.all([
      this.store.get(this.id()),
      this.store.listNotes(this.id()),
    ]);
    const row = ev as Row | null;
    if (row) {
      this.ev.set(row);
      this.checklist.set({ ...(row.review_checklist as Record<string, ChecklistState>) });
    }
    this.notes.set((notes as ReviewNote[] | null) ?? []);
  }

  protected setItem(key: string, value: ChecklistState): void {
    this.checklist.update((c) => ({ ...c, [key]: value }));
  }

  protected stateLabel(s: ChecklistState): string {
    return CHECKLIST_STATE_LABEL[s];
  }

  protected optionClass(active: boolean): string {
    return active
      ? 'flex-1 rounded-[--radius-chip] bg-navy px-2 py-1 text-[11.5px] font-semibold text-white'
      : 'flex-1 rounded-[--radius-chip] border border-border px-2 py-1 text-[11.5px] font-medium text-fg-muted';
  }

  protected async saveChecklist(id: string): Promise<void> {
    this.done.set(null);
    const { error } = await this.store.setChecklist(id, this.checklist() as ReviewChecklist);
    if (!error) {
      this.done.set('Checklist guardado.');
      await this.load();
    }
  }

  protected async approve(id: string): Promise<void> {
    // El checklist se guarda antes, para que el snapshot del asiento sea el que
    // el revisor tenía en pantalla al decidir.
    await this.store.setChecklist(id, this.checklist() as ReviewChecklist);
    const { error } = await this.store.approve(id, this.note || undefined);
    if (!error) await this.after('Solicitud aprobada. Pasa a configuración.');
  }

  protected async requestInfo(id: string): Promise<void> {
    const { error } = await this.store.requestInfo(
      id,
      this.note,
      this.checklist() as ReviewChecklist,
    );
    if (!error) await this.after('Información solicitada al organizador.');
  }

  protected async reject(id: string): Promise<void> {
    await this.store.setChecklist(id, this.checklist() as ReviewChecklist);
    const { error } = await this.store.reject(id, this.note);
    if (!error) await this.after('Solicitud rechazada.');
  }

  protected async pause(id: string): Promise<void> {
    const { error } = await this.store.pause(id, this.note || undefined);
    if (!error) await this.after('Venta pausada. Las entradas emitidas siguen válidas.');
  }

  protected async resume(id: string): Promise<void> {
    const { error } = await this.store.resume(id);
    if (!error) await this.after('Venta reanudada.');
  }

  private async after(msg: string): Promise<void> {
    this.note = '';
    this.done.set(msg);
    await this.load();
  }

  protected when(iso: string): string {
    return new Date(iso).toLocaleString('es-PE', {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  }

  protected actionLabel(a: string): string {
    return (
      {
        submitted: 'Enviado a revisión',
        info_requested: 'Se pidió información',
        approved: 'Aprobado',
        rejected: 'Rechazado',
        published: 'Publicado',
        paused: 'Venta pausada',
        cancelled: 'Cancelado',
        note: 'Nota',
      }[a] ?? a
    );
  }
}
