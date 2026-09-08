import { Component, ChangeDetectionStrategy, computed, inject, input, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { Chip } from '../../shared/ui/chip';
import { soles } from '../../shared/ui/money';
import { EventsStore, type EventRow } from '../eventos/events.store';
import {
  InventoryStore,
  type Availability,
  type PricePhase,
  type Zone,
  type ZoneKind,
  type ZoneSegment,
} from '../eventos/inventory.store';

type ZoneWithSegments = Zone & { zone_segments: ZoneSegment[] };

/**
 * Zonas, segmentos, fases y precios. Es la pantalla que desbloquea la
 * publicación: `publish_event` exige al menos un precio con stock.
 *
 * Los invariantes no se validan aquí. El aforo por zona, el solape de fases y la
 * pertenencia del segmento los garantiza la base, y sus mensajes están escritos
 * para leerse: «el stock de la zona General en esta fase (900) supera su aforo
 * (800)». Duplicar esas reglas en el cliente solo crea un segundo sitio donde
 * pueden quedar desactualizadas.
 */
@Component({
  selector: 'fv-org-zonas',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule, RouterLink, Chip],
  template: `
    <a [routerLink]="['/organizador/eventos', id()]" class="text-[12.5px] font-semibold text-coral-fg"
      >← Volver al evento</a
    >

    <header class="mt-3 mb-5">
      <div class="flex flex-wrap items-center gap-2">
        @if (ev(); as e) {
          <span class="font-mono text-[13px] font-semibold text-fg-soft">{{ e.code }}</span>
          <h1 class="text-2xl font-black tracking-[-0.5px]">Zonas y precios</h1>
        }
      </div>
      <p class="mt-1 text-[13px] text-fg-muted">
        El precio vive en el cruce de zona (o segmento) y fase. Para publicar hace falta al menos
        un precio con stock.
      </p>
    </header>

    @if (inv.error(); as e) {
      <p class="mb-4 rounded-[--radius-chip] bg-danger-bg px-3 py-2.5 text-[13px] text-danger-fg">
        {{ e }}
      </p>
    }

    <!-- ── Fases ──────────────────────────────────────────────────────────── -->
    <section class="mb-6 rounded-[--radius-card] border border-border bg-surface p-5">
      <h2 class="mb-1 text-[16px] font-bold">Fases de venta</h2>
      <p class="mb-3 text-[12.5px] text-fg-muted">
        No pueden solaparse en el tiempo. Una puede empezar exactamente cuando termina la
        anterior.
      </p>

      @if (phases().length) {
        <ul class="mb-4 space-y-2">
          @for (p of phases(); track p.id) {
            <li
              class="flex flex-wrap items-center justify-between gap-2 rounded-[--radius-inner] border p-3"
              [class]="isActive(p) ? 'border-coral bg-danger-bg' : 'border-border'"
            >
              <div>
                <span class="text-[13.5px] font-semibold">{{ p.name }}</span>
                @if (isActive(p)) {
                  <fv-chip tone="success" [dot]="true">Activa</fv-chip>
                }
                <p class="text-[12px] text-fg-muted">
                  {{ dt(p.starts_at) }} → {{ dt(p.ends_at) }}
                </p>
              </div>
              <button
                type="button"
                (click)="removePhase(p.id)"
                class="text-[12px] font-semibold text-danger-fg"
              >
                Quitar
              </button>
            </li>
          }
        </ul>
      }

      <form class="grid gap-2 sm:grid-cols-[1fr_auto_auto_auto]" (ngSubmit)="addPhase()">
        <input
          name="phaseName"
          placeholder="Preventa 1"
          required
          [(ngModel)]="newPhase.name"
          [class]="inputClass"
        />
        <input
          name="phaseStart"
          type="datetime-local"
          required
          [(ngModel)]="newPhase.starts_at"
          [class]="inputClass"
        />
        <input
          name="phaseEnd"
          type="datetime-local"
          required
          [(ngModel)]="newPhase.ends_at"
          [class]="inputClass"
        />
        <button
          type="submit"
          [disabled]="inv.loading()"
          class="rounded-[--radius-chip] bg-navy px-4 py-2 text-[13px] font-bold text-white disabled:opacity-50"
        >
          Añadir fase
        </button>
      </form>
    </section>

    <!-- ── Zonas ──────────────────────────────────────────────────────────── -->
    <section class="mb-6 rounded-[--radius-card] border border-border bg-surface p-5">
      <h2 class="mb-1 text-[16px] font-bold">Zonas</h2>
      <p class="mb-3 text-[12.5px] text-fg-muted">
        Una zona de pie se compra por cantidad. Una numerada se compra eligiendo asiento y puede
        tener segmentos de precio por bloque de filas.
      </p>

      <div class="mb-4 space-y-3">
        @for (z of zones(); track z.id) {
          <article class="rounded-[--radius-inner] border border-border p-3.5">
            <div class="flex flex-wrap items-start justify-between gap-2">
              <div>
                <span class="text-[14px] font-bold">{{ z.name }}</span>
                <fv-chip [tone]="z.kind === 'seated' ? 'info' : 'neutral'">
                  {{ z.kind === 'seated' ? 'Numerada' : 'De pie' }}
                </fv-chip>
                <p class="mt-0.5 text-[12px] text-fg-muted">
                  Aforo {{ z.capacity.toLocaleString('es-PE') }}
                  @if (z.notes) { · {{ z.notes }} }
                  @if (seatCounts()[z.id] !== undefined) {
                    · {{ seatCounts()[z.id] }} asientos creados
                  }
                </p>
              </div>
              <button
                type="button"
                (click)="removeZone(z.id)"
                class="text-[12px] font-semibold text-danger-fg"
              >
                Quitar
              </button>
            </div>

            <!-- Segmentos, dentro de su zona -->
            @if (z.kind === 'seated') {
              <div class="mt-3 rounded-[--radius-chip] bg-muted p-3">
                <h3 class="mb-2 text-[12px] font-bold text-fg-soft">Segmentos de precio</h3>
                @if (z.zone_segments?.length) {
                  <ul class="mb-2 space-y-1">
                    @for (s of z.zone_segments; track s.id) {
                      <li class="flex items-center justify-between gap-2 text-[12.5px]">
                        <span>
                          {{ s.label }}
                          @if (s.row_from) {
                            <span class="text-fg-muted">({{ s.row_from }}–{{ s.row_to }})</span>
                          }
                        </span>
                        <button
                          type="button"
                          (click)="removeSegment(s.id)"
                          class="font-semibold text-danger-fg"
                        >
                          Quitar
                        </button>
                      </li>
                    }
                  </ul>
                }
                <form class="grid gap-1.5 sm:grid-cols-[1fr_5rem_5rem_auto]" (ngSubmit)="addSegment(z.id)">
                  <input
                    [name]="'segLabel' + z.id"
                    placeholder="Filas A–C"
                    required
                    [(ngModel)]="segForm.label"
                    [class]="smallInputClass"
                  />
                  <input
                    [name]="'segFrom' + z.id"
                    placeholder="A"
                    [(ngModel)]="segForm.row_from"
                    [class]="smallInputClass"
                  />
                  <input
                    [name]="'segTo' + z.id"
                    placeholder="C"
                    [(ngModel)]="segForm.row_to"
                    [class]="smallInputClass"
                  />
                  <button
                    type="submit"
                    class="rounded-[--radius-chip] border border-border bg-surface px-3 py-1.5 text-[12px] font-semibold"
                  >
                    Añadir
                  </button>
                </form>

                <!-- Asientos: por rango, D-09 (sin plano gráfico) -->
                <form
                  class="mt-2 grid gap-1.5 border-t border-border pt-2 sm:grid-cols-[1fr_5rem_auto]"
                  (ngSubmit)="makeSeats(z.id)"
                >
                  <input
                    [name]="'rows' + z.id"
                    placeholder="Filas: A,B,C,D"
                    required
                    [(ngModel)]="seatForm.rows"
                    [class]="smallInputClass"
                  />
                  <input
                    [name]="'perRow' + z.id"
                    type="number"
                    min="1"
                    placeholder="20"
                    required
                    [(ngModel)]="seatForm.perRow"
                    [class]="smallInputClass"
                  />
                  <button
                    type="submit"
                    class="rounded-[--radius-chip] border border-border bg-surface px-3 py-1.5 text-[12px] font-semibold"
                  >
                    Generar asientos
                  </button>
                </form>
              </div>
            }
          </article>
        } @empty {
          <p class="text-[13px] text-fg-muted">Todavía no hay zonas.</p>
        }
      </div>

      <form class="grid gap-2 sm:grid-cols-[1fr_auto_6rem_auto]" (ngSubmit)="addZone()">
        <input
          name="zoneName"
          placeholder="General — de pie"
          required
          [(ngModel)]="newZone.name"
          [class]="inputClass"
        />
        <select name="zoneKind" [(ngModel)]="newZone.kind" [class]="inputClass">
          <option value="standing">De pie</option>
          <option value="seated">Numerada</option>
        </select>
        <input
          name="zoneCapacity"
          type="number"
          min="1"
          placeholder="Aforo"
          required
          [(ngModel)]="newZone.capacity"
          [class]="inputClass"
        />
        <button
          type="submit"
          [disabled]="inv.loading()"
          class="rounded-[--radius-chip] bg-navy px-4 py-2 text-[13px] font-bold text-white disabled:opacity-50"
        >
          Añadir zona
        </button>
      </form>
    </section>

    <!-- ── Precios: el cruce ──────────────────────────────────────────────── -->
    <section class="rounded-[--radius-card] border border-border bg-surface p-5">
      <h2 class="mb-1 text-[16px] font-bold">Precios</h2>
      <p class="mb-3 text-[12.5px] text-fg-muted">
        Un precio por cada cruce de zona (o segmento) y fase. El stock de una zona no puede
        superar su aforo dentro de la misma fase.
      </p>

      @if (availability().length) {
        <div class="mb-4 overflow-x-auto">
          <table class="w-full min-w-[640px] text-[13px]">
            <thead>
              <tr class="border-b border-border text-left text-[11.5px] uppercase text-fg-muted">
                <th class="pb-2">Zona / segmento</th>
                <th class="pb-2">Fase</th>
                <th class="pb-2 text-right">Precio base</th>
                <th class="pb-2 text-right">Stock</th>
                <th class="pb-2 text-right">Vendido</th>
                <th class="pb-2 text-right">Disponible</th>
              </tr>
            </thead>
            <tbody>
              @for (a of availability(); track a.tier_id) {
                <tr class="border-b border-border">
                  <td class="py-2">
                    {{ a.zone_name }}
                    @if (a.segment_label) {
                      <span class="text-fg-muted">· {{ a.segment_label }}</span>
                    }
                  </td>
                  <td class="py-2">
                    {{ a.phase_name }}
                    @if (a.phase_active) {
                      <fv-chip tone="success">Activa</fv-chip>
                    }
                  </td>
                  <td class="py-2 text-right font-semibold tabular-nums">
                    {{ money(a.price_cents) }}
                  </td>
                  <td class="py-2 text-right tabular-nums">{{ a.stock }}</td>
                  <td class="py-2 text-right tabular-nums">{{ a.sold }}</td>
                  <td class="py-2 text-right font-semibold tabular-nums">{{ a.available }}</td>
                </tr>
              }
            </tbody>
          </table>
        </div>
      }

      <form class="grid gap-2 sm:grid-cols-[1fr_1fr_7rem_6rem_auto]" (ngSubmit)="addTier()">
        <select name="tierTarget" [(ngModel)]="newTier.target" [class]="inputClass">
          <option value="">— zona o segmento —</option>
          @for (opt of targets(); track opt.value) {
            <option [value]="opt.value">{{ opt.label }}</option>
          }
        </select>
        <select name="tierPhase" [(ngModel)]="newTier.phase_id" [class]="inputClass">
          <option value="">— fase —</option>
          @for (p of phases(); track p.id) {
            <option [value]="p.id">{{ p.name }}</option>
          }
        </select>
        <input
          name="tierPrice"
          type="number"
          min="0.01"
          step="0.01"
          placeholder="Precio S/"
          required
          [(ngModel)]="newTier.price"
          [class]="inputClass"
        />
        <input
          name="tierStock"
          type="number"
          min="0"
          placeholder="Stock"
          required
          [(ngModel)]="newTier.stock"
          [class]="inputClass"
        />
        <button
          type="submit"
          [disabled]="inv.loading()"
          class="rounded-[--radius-chip] bg-coral px-4 py-2 text-[13px] font-bold text-white disabled:opacity-50"
        >
          Fijar precio
        </button>
      </form>
      <p class="mt-2 text-[11.5px] text-fg-muted">
        El precio se escribe en soles y se guarda en céntimos enteros.
      </p>
    </section>
  `,
})
export class OrgZonasPage {
  readonly id = input.required<string>();

  protected readonly inv = inject(InventoryStore);
  private readonly events = inject(EventsStore);

  protected readonly ev = signal<EventRow | null>(null);
  protected readonly zones = signal<readonly ZoneWithSegments[]>([]);
  protected readonly phases = signal<readonly PricePhase[]>([]);
  protected readonly availability = signal<readonly Availability[]>([]);
  protected readonly seatCounts = signal<Record<string, number>>({});

  protected readonly money = soles;
  protected readonly inputClass =
    'rounded-[--radius-chip] border border-border bg-surface px-3 py-2 text-[13px]';
  protected readonly smallInputClass =
    'rounded-[--radius-chip] border border-border bg-surface px-2 py-1.5 text-[12px]';

  protected newZone = { name: '', kind: 'standing' as ZoneKind, capacity: null as number | null };
  protected newPhase = { name: '', starts_at: '', ends_at: '' };
  protected segForm = { label: '', row_from: '', row_to: '' };
  protected seatForm = { rows: '', perRow: 20 as number | null };
  protected newTier = { target: '', phase_id: '', price: null as number | null, stock: null as number | null };

  /** Zona suelta o zona+segmento, en un solo desplegable. */
  protected readonly targets = computed(() =>
    this.zones().flatMap((z) => {
      const segs = z.zone_segments ?? [];
      if (z.kind === 'seated' && segs.length) {
        return segs.map((s) => ({ value: `${z.id}:${s.id}`, label: `${z.name} · ${s.label}` }));
      }
      return [{ value: `${z.id}:`, label: z.name }];
    }),
  );

  constructor() {
    queueMicrotask(() => void this.load());
  }

  private async load(): Promise<void> {
    const [{ data: ev }, { data: zones }, { data: phases }, { data: avail }] = await Promise.all([
      this.events.get(this.id()),
      this.inv.listZones(this.id()),
      this.inv.listPhases(this.id()),
      this.inv.listAvailability(this.id()),
    ]);
    this.ev.set((ev as EventRow | null) ?? null);
    const zs = (zones as ZoneWithSegments[] | null) ?? [];
    this.zones.set(zs);
    this.phases.set((phases as PricePhase[] | null) ?? []);
    this.availability.set((avail as Availability[] | null) ?? []);

    const counts: Record<string, number> = {};
    for (const z of zs.filter((z) => z.kind === 'seated')) {
      counts[z.id] = await this.inv.countSeats(z.id);
    }
    this.seatCounts.set(counts);
  }

  protected isActive(p: PricePhase): boolean {
    const now = Date.now();
    return now >= new Date(p.starts_at).getTime() && now < new Date(p.ends_at).getTime();
  }

  protected dt(iso: string): string {
    return new Date(iso).toLocaleString('es-PE', {
      day: 'numeric',
      month: 'short',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });
  }

  protected async addZone(): Promise<void> {
    if (!this.newZone.name || !this.newZone.capacity) return;
    const { error } = await this.inv.createZone({
      event_id: this.id(),
      name: this.newZone.name,
      kind: this.newZone.kind,
      capacity: this.newZone.capacity,
      sort_order: this.zones().length,
    });
    if (!error) {
      this.newZone = { name: '', kind: 'standing', capacity: null };
      await this.load();
    }
  }

  protected async removeZone(id: string): Promise<void> {
    const { error } = await this.inv.deleteZone(id);
    if (!error) await this.load();
  }

  protected async addSegment(zoneId: string): Promise<void> {
    if (!this.segForm.label) return;
    const zone = this.zones().find((z) => z.id === zoneId);
    const { error } = await this.inv.createSegment({
      zone_id: zoneId,
      label: this.segForm.label,
      row_from: this.segForm.row_from || null,
      row_to: this.segForm.row_to || null,
      sort_order: zone?.zone_segments?.length ?? 0,
    });
    if (!error) {
      this.segForm = { label: '', row_from: '', row_to: '' };
      await this.load();
    }
  }

  protected async removeSegment(id: string): Promise<void> {
    const { error } = await this.inv.deleteSegment(id);
    if (!error) await this.load();
  }

  protected async makeSeats(zoneId: string): Promise<void> {
    const rows = this.seatForm.rows
      .split(',')
      .map((r) => r.trim().toUpperCase())
      .filter(Boolean);
    if (!rows.length || !this.seatForm.perRow) return;
    const { error } = await this.inv.generateSeats(zoneId, rows, this.seatForm.perRow);
    if (!error) {
      this.seatForm = { rows: '', perRow: 20 };
      await this.load();
    }
  }

  protected async addPhase(): Promise<void> {
    if (!this.newPhase.name || !this.newPhase.starts_at || !this.newPhase.ends_at) return;
    const { error } = await this.inv.createPhase({
      event_id: this.id(),
      name: this.newPhase.name,
      kind: 'presale',
      starts_at: new Date(this.newPhase.starts_at).toISOString(),
      ends_at: new Date(this.newPhase.ends_at).toISOString(),
      sort_order: this.phases().length,
    });
    if (!error) {
      this.newPhase = { name: '', starts_at: '', ends_at: '' };
      await this.load();
    }
  }

  protected async removePhase(id: string): Promise<void> {
    const { error } = await this.inv.deletePhase(id);
    if (!error) await this.load();
  }

  protected async addTier(): Promise<void> {
    const { target, phase_id, price, stock } = this.newTier;
    if (!target || !phase_id || price == null || stock == null) return;

    const [zoneId, segmentId] = target.split(':');
    const { error } = await this.inv.upsertTier({
      event_id: this.id(),
      zone_id: zoneId,
      segment_id: segmentId || null,
      phase_id,
      // Soles a céntimos enteros. Único sitio donde el front toca aritmética de
      // dinero, y es una conversión de unidad, no un cálculo (Art. 5).
      price_cents: Math.round(price * 100),
      stock,
    });
    if (!error) {
      this.newTier = { target: '', phase_id: '', price: null, stock: null };
      await this.load();
    }
  }
}
