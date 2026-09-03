import { Injectable, signal } from '@angular/core';
import { supabase } from '../../core/supabase.client';

/**
 * La forma exacta de lo que devuelve `get_public_event(slug)`.
 *
 * Es un solo viaje: evento + fases + zonas con sus tiers anidados. El detalle
 * necesita las tres cosas juntas para pintarse, y tres consultas serían tres
 * momentos distintos del inventario.
 */
export interface PublicTier {
  readonly tier_id: string;
  readonly segment_id: string | null;
  readonly segment_label: string | null;
  readonly row_from: string | null;
  readonly row_to: string | null;
  readonly phase_id: string;
  readonly phase_name: string;
  readonly phase_active: boolean;
  /** Céntimos. El front formatea, no calcula (Art. 5). */
  readonly base_cents: number;
  readonly total_cents: number;
  readonly service_charge_cents: number;
  readonly currency: string;
  readonly available: number;
  readonly stock: number;
}

export interface PublicZone {
  readonly id: string;
  readonly name: string;
  readonly kind: 'standing' | 'seated';
  readonly numbered: boolean;
  readonly notes: string | null;
  readonly tiers: readonly PublicTier[];
}

export interface PublicPhase {
  readonly id: string;
  readonly name: string;
  readonly kind: string;
  readonly starts_at: string;
  readonly ends_at: string;
  readonly state: 'past' | 'active' | 'future';
  readonly tickets: number;
}

export interface PublicEvent {
  readonly id: string;
  readonly slug: string;
  readonly title: string;
  readonly description: string | null;
  readonly category: string | null;
  readonly hero_image_url: string | null;
  readonly starts_at: string | null;
  readonly doors_at: string | null;
  readonly timezone: string;
  readonly venue: { name: string | null; city: string | null; address: string | null };
  readonly organizer_name: string | null;
  readonly max_per_user: number;
  readonly resale_enabled: boolean;
  readonly max_resales: number;
  readonly service_charge_bps: number;
  readonly service_charge_payer: 'fan' | 'organizer';
  readonly qr_lead_days: number;
  readonly nomination_mode: 'strict' | 'flexible';
  readonly sale_open: boolean;
  readonly phases: readonly PublicPhase[];
  readonly zones: readonly PublicZone[];
}

export interface CatalogEvent {
  readonly id: string;
  readonly slug: string;
  readonly title: string;
  readonly category: string | null;
  readonly hero_image_url: string | null;
  readonly starts_at: string | null;
  readonly venue_name: string | null;
  readonly venue_city: string | null;
  readonly organizer_name: string | null;
  readonly from_price_cents: number | null;
  readonly currency: string | null;
  readonly sale_open: boolean;
  readonly next_phase_starts_at: string | null;
  readonly available_now: number;
  readonly featured_at: string | null;
  readonly max_per_user: number;
  readonly resale_enabled: boolean;
}

/**
 * La superficie pública. Es lo único de `public` que `anon` puede leer, y son
 * dos cosas distintas a propósito:
 *
 * - `v_event_public` se puede listar → el catálogo.
 * - `get_public_event(slug)` exige el slug → el detalle, y así un evento no
 *   listado se abre por su enlace sin poder enumerarse.
 */
@Injectable({ providedIn: 'root' })
export class PublicEventStore {
  readonly loading = signal(false);
  readonly error = signal<string | null>(null);

  async getBySlug(slug: string): Promise<PublicEvent | null> {
    this.loading.set(true);
    this.error.set(null);
    const { data, error } = await supabase.rpc('get_public_event', { p_slug: slug });
    this.loading.set(false);
    if (error) {
      this.error.set(error.message);
      return null;
    }
    return (data as PublicEvent | null) ?? null;
  }

  /** El catálogo lo consume 002; aquí queda listo para que lo use. */
  async listCatalog(): Promise<readonly CatalogEvent[]> {
    this.loading.set(true);
    this.error.set(null);
    const { data, error } = await supabase
      .from('v_event_public')
      .select('*')
      .order('featured_at', { ascending: false, nullsFirst: false })
      .order('starts_at');
    this.loading.set(false);
    if (error) {
      this.error.set(error.message);
      return [];
    }
    return (data as CatalogEvent[] | null) ?? [];
  }
}

/**
 * El stock en lenguaje humano. Del mockup, y no es cosmético: «Agotado en
 * Preventa 1 — se libera stock en Preventa 2» es la diferencia entre perder al
 * fan y que vuelva.
 */
export function stockLabel(
  tier: PublicTier,
  phases: readonly PublicPhase[],
): { text: string; tone: 'success' | 'warn' | 'danger' | 'neutral' } {
  if (!tier.phase_active) {
    const phase = phases.find((p) => p.id === tier.phase_id);
    if (phase?.state === 'future') {
      return { text: `Abre en ${phase.name}`, tone: 'neutral' };
    }
    return { text: `${tier.phase_name} cerrada`, tone: 'neutral' };
  }

  if (tier.available === 0) {
    // Si hay una fase futura con entradas, decirlo. Es la diferencia entre
    // «agotado» y «agotado por ahora».
    const next = phases.find((p) => p.state === 'future' && p.tickets > 0);
    return next
      ? { text: `Agotado en ${tier.phase_name} — se libera stock en ${next.name}`, tone: 'warn' }
      : { text: 'Agotado', tone: 'danger' };
  }

  if (tier.available <= 10) {
    return { text: `Últimas ${tier.available}`, tone: 'warn' };
  }
  return { text: `${tier.available.toLocaleString('es-PE')} disponibles`, tone: 'success' };
}
