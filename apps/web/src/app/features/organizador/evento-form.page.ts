import { Component, ChangeDetectionStrategy, computed, inject, input, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { Chip } from '../../shared/ui/chip';
import { bpsToPercent } from '../../shared/ui/money';
import { EventsStore, type EventRow, type ReviewNote, type Venue } from '../eventos/events.store';
import {
  CHECKLIST_LABELS,
  CHECKLIST_STATE_LABEL,
  CHECKLIST_TONE,
  EVENT_STATUS,
} from '../eventos/event-status';

/**
 * La ficha del evento, del lado del organizador.
 *
 * Tres reglas de copy que vienen del spec y no son negociables:
 *  - en `draft` el botón dice «Enviar a revisión», nunca «Publicar»;
 *  - `approved`/`setup` explica que aprobado ≠ publicado y que publicar es
 *    decisión del organizador;
 *  - `paused` aclara que las entradas emitidas siguen siendo válidas.
 */
@Component({
  selector: 'fv-org-evento-form',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule, RouterLink, Chip],
  template: `
    @if (ev(); as e) {
      <a routerLink="/organizador/eventos" class="text-[12.5px] font-semibold text-coral-fg"
        >← Mis eventos</a
      >

      <header class="mt-3 mb-5">
        <div class="flex flex-wrap items-center gap-2">
          <span class="font-mono text-[13px] font-semibold text-fg-soft">{{ e.code }}</span>
          <h1 class="text-2xl font-black tracking-[-0.5px]">{{ e.title || 'Evento sin título' }}</h1>
          <fv-chip [tone]="copy().tone">{{ copy().label }}</fv-chip>
        </div>

        <!-- El estado en palabras, no solo un chip de color. -->
        <div
          class="mt-3 rounded-[--radius-card] border p-4"
          [class]="
            copy().tone === 'danger'
              ? 'border-danger-border bg-danger-bg'
              : copy().tone === 'warn'
                ? 'border-warn-border bg-warn-bg'
                : copy().tone === 'success'
                  ? 'border-success-border bg-success-bg'
                  : 'border-border bg-surface'
          "
        >
          <p class="text-[13.5px] font-semibold">{{ copy().meaning }}</p>
          @if (copy().nextStep; as step) {
            <p class="mt-1 text-[13px] text-fg-soft">{{ step }}</p>
          }
        </div>
      </header>

      @if (store.error(); as err) {
        <p class="mb-4 rounded-[--radius-chip] bg-danger-bg px-3 py-2.5 text-[13px] text-danger-fg">
          {{ err }}
        </p>
      }
      @if (saved()) {
        <p class="mb-4 rounded-[--radius-chip] bg-success-bg px-3 py-2 text-[13px] text-success-fg">
          Cambios guardados.
        </p>
      }

      <!-- Observación de Feventi: lo primero que tiene que leer -->
      @if (lastRequest(); as note) {
        <section class="mb-6 rounded-[--radius-card] border-2 border-coral bg-danger-bg p-4">
          <h2 class="text-[13px] font-bold uppercase tracking-wide text-danger-fg">
            Observación de Feventi
          </h2>
          <p class="mt-1.5 text-[14px]">{{ note.note }}</p>
          <p class="mt-2 text-[12px] text-fg-muted">{{ when(note.created_at) }}</p>
        </section>
      }

      <!-- El checklist es de Admin: aquí solo se lee (AC-05b) -->
      @if (checklistItems().length && !editable()) {
        <section class="mb-6 rounded-[--radius-card] border border-border bg-surface p-4">
          <h2 class="mb-2.5 text-[13px] font-bold">Revisión de Feventi</h2>
          <ul class="space-y-1.5">
            @for (item of checklistItems(); track item.key) {
              <li class="flex items-center justify-between gap-3 text-[13px]">
                <span>{{ item.label }}</span>
                <fv-chip [tone]="item.tone">{{ item.state }}</fv-chip>
              </li>
            }
          </ul>
          <p class="mt-3 text-[12px] text-fg-muted">
            Este checklist lo completa Feventi. Tú lo ves para saber qué falta.
          </p>
        </section>
      }

      <form class="space-y-6" (ngSubmit)="save(e.id)">
        <fieldset [disabled]="!editable()" class="space-y-6">
          <section class="rounded-[--radius-card] border border-border bg-surface p-5">
            <h2 class="mb-3 text-[16px] font-bold">Ficha del evento</h2>
            <div class="grid gap-3 sm:grid-cols-2">
              <label class="block sm:col-span-2">
                <span class="text-[12px] font-semibold text-fg-soft">Título</span>
                <input name="title" [(ngModel)]="form.title" [class]="inputClass" />
              </label>
              <label class="block sm:col-span-2">
                <span class="text-[12px] font-semibold text-fg-soft">Descripción</span>
                <textarea
                  name="description"
                  rows="3"
                  [(ngModel)]="form.description"
                  [class]="inputClass"
                ></textarea>
              </label>
              <label class="block">
                <span class="text-[12px] font-semibold text-fg-soft">Categoría</span>
                <input name="category" [(ngModel)]="form.category" [class]="inputClass" />
              </label>
              <label class="block">
                <span class="text-[12px] font-semibold text-fg-soft">
                  Slug público
                  <span class="font-normal text-fg-muted">— hace falta para publicar</span>
                </span>
                <input name="slug" [(ngModel)]="form.slug" [class]="inputClass" />
              </label>
              <label class="block">
                <span class="text-[12px] font-semibold text-fg-soft">Fecha y hora</span>
                <input
                  name="starts_at"
                  type="datetime-local"
                  [(ngModel)]="form.starts_at"
                  [class]="inputClass"
                />
              </label>
              <label class="block">
                <span class="text-[12px] font-semibold text-fg-soft">Apertura de puertas</span>
                <input
                  name="doors_at"
                  type="datetime-local"
                  [(ngModel)]="form.doors_at"
                  [class]="inputClass"
                />
              </label>
              <label class="block">
                <span class="text-[12px] font-semibold text-fg-soft">Lugar</span>
                <select name="venue_id" [(ngModel)]="form.venue_id" [class]="inputClass">
                  <option [ngValue]="null">— elegir —</option>
                  @for (v of venues(); track v.id) {
                    <option [ngValue]="v.id">{{ v.name }} · {{ v.city }}</option>
                  }
                </select>
              </label>
              <label class="block">
                <span class="text-[12px] font-semibold text-fg-soft">Aforo</span>
                <input
                  name="capacity"
                  type="number"
                  min="1"
                  [(ngModel)]="form.capacity"
                  [class]="inputClass"
                />
              </label>
            </div>
          </section>

          <section class="rounded-[--radius-card] border border-border bg-surface p-5">
            <h2 class="mb-1 text-[16px] font-bold">Reglas comerciales</h2>
            <p class="mb-3 text-[12.5px] text-fg-muted">
              El cargo de servicio se le muestra al fan desde el primer paso de la compra, lo
              pagues tú o lo pague él.
            </p>
            <div class="grid gap-3 sm:grid-cols-2">
              <label class="block">
                <span class="text-[12px] font-semibold text-fg-soft">Límite por usuario</span>
                <input
                  name="max_per_user"
                  type="number"
                  min="1"
                  [(ngModel)]="form.max_per_user"
                  [class]="inputClass"
                />
              </label>
              <label class="block">
                <span class="text-[12px] font-semibold text-fg-soft">
                  Cargo de servicio ({{ chargePercent() }})
                </span>
                <select
                  name="service_charge_payer"
                  [(ngModel)]="form.service_charge_payer"
                  [class]="inputClass"
                >
                  <option value="fan">Lo paga el fan</option>
                  <option value="organizer">Lo absorbo yo</option>
                </select>
              </label>
              <label class="block">
                <span class="text-[12px] font-semibold text-fg-soft">
                  QR disponible desde (días antes)
                </span>
                <input
                  name="qr_lead_days"
                  type="number"
                  min="0"
                  [(ngModel)]="form.qr_lead_days"
                  [class]="inputClass"
                />
              </label>
              <label class="block">
                <span class="text-[12px] font-semibold text-fg-soft">Nominación</span>
                <select
                  name="nomination_mode"
                  [(ngModel)]="form.nomination_mode"
                  [class]="inputClass"
                >
                  <option value="flexible">Flexible — sin nominar entra a revisión</option>
                  <option value="strict">Estricta — sin nominar no entra</option>
                </select>
              </label>
              <label class="flex items-center gap-2 sm:col-span-2">
                <input
                  name="resale_enabled"
                  type="checkbox"
                  [(ngModel)]="form.resale_enabled"
                  class="size-4"
                />
                <span class="text-[13px]">
                  Permitir reventa oficial dentro de Feventi
                  <span class="text-fg-muted">
                    — al precio original, máximo {{ e.max_resales }} veces
                  </span>
                </span>
              </label>
            </div>
          </section>
        </fieldset>

        @if (!editable()) {
          <p class="text-[12.5px] text-fg-muted">
            @if (e.status === 'pending_review') {
              La ficha queda bloqueada mientras Feventi revisa la solicitud.
            } @else if (sensitiveLocked()) {
              Con entradas ya emitidas, la fecha, el lugar, el aforo y las reglas comerciales los
              cambia Feventi. Abre un caso de soporte.
            } @else {
              Esta ficha ya no se edita en el estado actual.
            }
          </p>
        }

        <div class="flex flex-wrap gap-2">
          @if (editable()) {
            <button
              type="submit"
              [disabled]="store.loading()"
              class="rounded-[--radius-chip] border border-border bg-surface px-4 py-2.5 text-[13px] font-bold disabled:opacity-50"
            >
              Guardar borrador
            </button>
          }

          <!-- draft / changes_requested: enviar, NUNCA "publicar" -->
          @if (e.status === 'draft' || e.status === 'changes_requested') {
            <button
              type="button"
              (click)="submitForReview(e.id)"
              [disabled]="store.loading()"
              class="rounded-[--radius-chip] bg-coral px-4 py-2.5 text-[13px] font-bold text-white disabled:opacity-50"
            >
              Enviar a revisión
            </button>
          }

          <!-- setup: publicar es decisión del organizador -->
          @if (e.status === 'setup') {
            <button
              type="button"
              (click)="publish(e.id)"
              [disabled]="store.loading()"
              class="rounded-[--radius-chip] bg-coral px-4 py-2.5 text-[13px] font-bold text-white disabled:opacity-50"
            >
              Publicar y abrir la venta
            </button>
          }
        </div>
      </form>

      <!-- Historial: append-only, en orden (AC-13) -->
      @if (notes().length) {
        <section class="mt-8">
          <h2 class="mb-2 text-[12px] font-bold uppercase tracking-wide text-fg-muted">
            Historial de la solicitud
          </h2>
          <ol class="space-y-2">
            @for (n of notes(); track n.id) {
              <li class="rounded-[--radius-inner] border border-border bg-surface p-3">
                <div class="flex flex-wrap items-baseline justify-between gap-2">
                  <span class="text-[13px] font-semibold">{{ actionLabel(n.action) }}</span>
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
    }
  `,
})
export class OrgEventoFormPage {
  readonly id = input.required<string>();

  protected readonly store = inject(EventsStore);
  protected readonly ev = signal<EventRow | null>(null);
  protected readonly notes = signal<readonly ReviewNote[]>([]);
  protected readonly venues = signal<readonly Venue[]>([]);
  protected readonly saved = signal(false);

  protected readonly inputClass =
    'mt-1 w-full rounded-[--radius-chip] border border-border bg-surface px-3 py-2 text-[14px] disabled:bg-muted disabled:text-fg-muted';

  protected form = {
    title: '' as string | null,
    description: '' as string | null,
    category: '' as string | null,
    slug: '' as string | null,
    starts_at: '' as string,
    doors_at: '' as string,
    venue_id: null as string | null,
    capacity: null as number | null,
    max_per_user: 5,
    service_charge_payer: 'fan' as 'fan' | 'organizer',
    qr_lead_days: 14,
    nomination_mode: 'flexible' as 'strict' | 'flexible',
    resale_enabled: true,
  };

  protected readonly copy = computed(() => EVENT_STATUS[this.ev()?.status ?? 'draft']);

  /** Solo se edita la ficha en los estados donde es del organizador. */
  protected readonly editable = computed(() => {
    const s = this.ev()?.status;
    return s === 'draft' || s === 'changes_requested' || s === 'approved' || s === 'setup';
  });

  protected readonly sensitiveLocked = computed(() => {
    const s = this.ev()?.status;
    return s === 'published' || s === 'paused';
  });

  /** La última observación de Feventi: lo primero que hay que leer. */
  protected readonly lastRequest = computed(
    () =>
      [...this.notes()].reverse().find((n) => n.action === 'info_requested' || n.action === 'rejected') ??
      null,
  );

  protected readonly checklistItems = computed(() => {
    const raw = this.ev()?.review_checklist as Record<string, string> | null;
    if (!raw) return [];
    return Object.entries(CHECKLIST_LABELS).map(([key, label]) => ({
      key,
      label,
      state: CHECKLIST_STATE_LABEL[raw[key]] ?? raw[key],
      tone: CHECKLIST_TONE[raw[key]] ?? 'neutral',
    }));
  });

  protected readonly chargePercent = computed(() =>
    bpsToPercent(this.ev()?.service_charge_bps ?? 600),
  );

  constructor() {
    queueMicrotask(() => void this.load());
  }

  private async load(): Promise<void> {
    const [{ data: ev }, { data: notes }, { data: venues }] = await Promise.all([
      this.store.get(this.id()),
      this.store.listNotes(this.id()),
      this.store.listVenues(),
    ]);

    const row = ev as EventRow | null;
    if (row) {
      this.ev.set(row);
      this.form = {
        title: row.title,
        description: row.description,
        category: row.category,
        slug: row.slug,
        starts_at: toLocalInput(row.starts_at),
        doors_at: toLocalInput(row.doors_at),
        venue_id: row.venue_id,
        capacity: row.capacity,
        max_per_user: row.max_per_user,
        service_charge_payer: row.service_charge_payer,
        qr_lead_days: row.qr_lead_days,
        nomination_mode: row.nomination_mode,
        resale_enabled: row.resale_enabled,
      };
    }
    this.notes.set((notes as ReviewNote[] | null) ?? []);
    this.venues.set((venues as Venue[] | null) ?? []);
  }

  protected async save(id: string): Promise<void> {
    this.saved.set(false);
    const { error } = await this.store.saveDraft(id, {
      title: this.form.title,
      description: this.form.description,
      category: this.form.category,
      slug: this.form.slug || null,
      starts_at: this.form.starts_at ? new Date(this.form.starts_at).toISOString() : null,
      doors_at: this.form.doors_at ? new Date(this.form.doors_at).toISOString() : null,
      venue_id: this.form.venue_id,
      capacity: this.form.capacity,
      max_per_user: this.form.max_per_user,
      service_charge_payer: this.form.service_charge_payer,
      qr_lead_days: this.form.qr_lead_days,
      nomination_mode: this.form.nomination_mode,
      resale_enabled: this.form.resale_enabled,
    });
    if (!error) {
      this.saved.set(true);
      await this.load();
    }
  }

  protected async submitForReview(id: string): Promise<void> {
    // Se guarda antes de enviar: el servidor valida contra lo persistido, no
    // contra lo que hay en pantalla.
    await this.save(id);
    if (this.store.error()) return;
    const { error } = await this.store.submit(id);
    if (!error) await this.load();
  }

  protected async publish(id: string): Promise<void> {
    const { error } = await this.store.publish(id);
    if (!error) await this.load();
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
        info_requested: 'Feventi pidió información',
        approved: 'Aprobado por Feventi',
        rejected: 'Rechazado por Feventi',
        published: 'Publicado',
        paused: 'Venta pausada',
        cancelled: 'Cancelado',
        note: 'Nota',
      }[a] ?? a
    );
  }
}

/** `datetime-local` quiere hora local sin zona; la base guarda timestamptz. */
function toLocalInput(iso: string | null): string {
  if (!iso) return '';
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
