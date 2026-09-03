import { Injectable, signal } from '@angular/core';
import { supabase } from '../../core/supabase.client';
import type { Enums, Tables } from '../../core/db.types';

export type Zone = Tables<'zones'>;
export type ZoneSegment = Tables<'zone_segments'>;
export type PricePhase = Tables<'price_phases'>;
export type PriceTier = Tables<'price_tiers'>;
export type ZoneKind = Enums<'zone_kind'>;
export type PhaseKind = Enums<'phase_kind'>;

export interface Availability {
  readonly tier_id: string;
  readonly event_id: string;
  readonly zone_id: string;
  readonly zone_name: string;
  readonly segment_id: string | null;
  readonly segment_label: string | null;
  readonly phase_id: string;
  readonly phase_name: string;
  readonly phase_active: boolean;
  readonly price_cents: number;
  readonly currency: string;
  readonly stock: number;
  readonly reserved: number;
  readonly sold: number;
  readonly available: number;
}

/**
 * Inventario de un evento: zonas, segmentos, fases y precios.
 *
 * Aquí sí hay `insert`/`update` directos, al contrario que en las transiciones
 * de 007. La diferencia: estas escrituras no tienen reglas que una política no
 * pueda expresar. Las invariantes que sí las tienen —aforo, solape de fases,
 * pertenencia del segmento— las garantiza la base con constraints y triggers, y
 * su mensaje de error llega tal cual a la pantalla.
 *
 * `reserved` y `sold` no aparecen: los mueve 004 en funciones transaccionales, y
 * el cliente tiene el `update` de esas dos columnas revocado.
 */
@Injectable({ providedIn: 'root' })
export class InventoryStore {
  readonly loading = signal(false);
  readonly error = signal<string | null>(null);

  private async run<T>(
    fn: () => PromiseLike<{ data: T | null; error: { message: string } | null }>,
  ): Promise<{ data: T | null; error: { message: string } | null }> {
    this.loading.set(true);
    this.error.set(null);
    const { data, error } = await fn();
    this.loading.set(false);
    if (error) {
      // Los mensajes de los triggers están escritos para leerse: «el stock de la
      // zona General en esta fase (900) supera su aforo (800)».
      this.error.set(error.message);
      return { data: null, error };
    }
    return { data, error: null };
  }

  // ── Lectura ───────────────────────────────────────────────────────────────

  async listZones(eventId: string) {
    return this.run(() =>
      supabase
        .from('zones')
        .select('*, zone_segments(*)')
        .eq('event_id', eventId)
        .order('sort_order'),
    );
  }

  async listPhases(eventId: string) {
    return this.run(() =>
      supabase.from('price_phases').select('*').eq('event_id', eventId).order('starts_at'),
    );
  }

  /** La disponibilidad sale de la vista, no de una cuenta en el cliente. */
  async listAvailability(eventId: string) {
    return this.run(() =>
      supabase
        .from('v_event_availability')
        .select('*')
        .eq('event_id', eventId)
        .order('zone_name')
        .order('phase_name'),
    );
  }

  // ── Zonas ─────────────────────────────────────────────────────────────────

  /**
   * `numbered` no se pide: es consecuencia de `kind`, y un check lo verifica.
   * Ofrecerlo como casilla aparte invita a un estado que la base rechaza.
   */
  async createZone(input: {
    event_id: string;
    name: string;
    kind: ZoneKind;
    capacity: number;
    notes?: string | null;
    sort_order?: number;
  }) {
    return this.run(() =>
      supabase
        .from('zones')
        .insert({ ...input, numbered: input.kind === 'seated' })
        .select('*')
        .single(),
    );
  }

  async updateZone(id: string, patch: Partial<Pick<Zone, 'name' | 'capacity' | 'notes' | 'sort_order'>>) {
    return this.run(() => supabase.from('zones').update(patch).eq('id', id).select('*').single());
  }

  async deleteZone(id: string) {
    return this.run(() => supabase.from('zones').delete().eq('id', id));
  }

  // ── Segmentos ─────────────────────────────────────────────────────────────

  async createSegment(input: {
    zone_id: string;
    label: string;
    row_from?: string | null;
    row_to?: string | null;
    sort_order?: number;
  }) {
    return this.run(() =>
      supabase.from('zone_segments').insert(input).select('*').single(),
    );
  }

  async deleteSegment(id: string) {
    return this.run(() => supabase.from('zone_segments').delete().eq('id', id));
  }

  // ── Fases ─────────────────────────────────────────────────────────────────

  /** Si se solapa con otra, la restricción de exclusión lo rechaza. */
  async createPhase(input: {
    event_id: string;
    name: string;
    kind: PhaseKind;
    starts_at: string;
    ends_at: string;
    sort_order?: number;
  }) {
    return this.run(() => supabase.from('price_phases').insert(input).select('*').single());
  }

  async updatePhase(
    id: string,
    patch: Partial<Pick<PricePhase, 'name' | 'kind' | 'starts_at' | 'ends_at' | 'sort_order'>>,
  ) {
    return this.run(() =>
      supabase.from('price_phases').update(patch).eq('id', id).select('*').single(),
    );
  }

  async deletePhase(id: string) {
    return this.run(() => supabase.from('price_phases').delete().eq('id', id));
  }

  // ── Precios ───────────────────────────────────────────────────────────────

  /** El cruce (zona | segmento) × fase. Un solo precio por cruce. */
  async upsertTier(input: {
    event_id: string;
    zone_id: string;
    segment_id: string | null;
    phase_id: string;
    price_cents: number;
    stock: number;
  }) {
    return this.run(() =>
      supabase
        .from('price_tiers')
        .upsert(input, { onConflict: 'zone_id,segment_id,phase_id' })
        .select('*')
        .single(),
    );
  }

  async updateTier(id: string, patch: { price_cents?: number; stock?: number }) {
    return this.run(() =>
      supabase.from('price_tiers').update(patch).eq('id', id).select('*').single(),
    );
  }

  async deleteTier(id: string) {
    return this.run(() => supabase.from('price_tiers').delete().eq('id', id));
  }

  // ── Asientos ──────────────────────────────────────────────────────────────

  /**
   * Un bloque entero en una llamada. 45 filas × 20 asientos son 900 inserts;
   * a mano no es viable (D-09: sin plano gráfico, lista de fila y número).
   */
  async generateSeats(zoneId: string, rows: string[], perRow: number, segmentId?: string | null) {
    return this.run(() =>
      supabase.rpc('generate_seats', {
        p_zone_id: zoneId,
        p_rows: rows,
        p_per_row: perRow,
        p_segment_id: segmentId ?? undefined,
      }),
    );
  }

  async countSeats(zoneId: string) {
    const { count } = await supabase
      .from('seats')
      .select('id', { count: 'exact', head: true })
      .eq('zone_id', zoneId);
    return count ?? 0;
  }
}
