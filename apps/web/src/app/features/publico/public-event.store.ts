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

  /**
   * El catálogo. Filtros, orden y paginación por cursor.
   *
   * Se piden las columnas de forma explícita a propósito: `select('*')` traería
   * `search_text`, que son kilobytes de tsvector por fila y que solo existe para
   * filtrar.
   */
  async listCatalog(opts: CatalogQuery = {}): Promise<CatalogPage> {
    this.loading.set(true);
    this.error.set(null);

    const limit = opts.limit ?? 24;
    let q = supabase.from('v_event_public').select(CATALOG_COLUMNS);

    if (opts.search?.trim()) {
      // `websearch` y no `fts`: nunca falla con lo que el usuario teclee, y
      // entiende comillas y OR. La configuración tiene que ser la MISMA del
      // índice, o unaccent no se aplica al término buscado.
      q = q.textSearch('search_text', opts.search.trim(), {
        type: 'websearch',
        config: 'spanish_unaccent',
      });
    }
    if (opts.category) q = q.eq('category', opts.category);
    if (opts.city) q = q.eq('venue_city', opts.city);
    if (opts.from) q = q.gte('starts_at', opts.from);
    if (opts.to) q = q.lte('starts_at', opts.to);
    if (opts.maxPriceCents != null) q = q.lte('from_price_cents', opts.maxPriceCents);
    if (opts.onlyAvailable) q = q.gt('available_now', 0);

    if (opts.sort === 'price') {
      q = q.order('from_price_cents', { ascending: true, nullsFirst: false }).order('id');
    } else if (opts.sort === 'relevance') {
      // D-01: sin algoritmo. Relevancia = destacados de Admin primero, después
      // por fecha. Es curaduría manual y la UI no promete otra cosa.
      q = q.order('featured_at', { ascending: false, nullsFirst: false }).order('starts_at').order('id');
    } else {
      q = q.order('starts_at', { ascending: true, nullsFirst: false }).order('id');
      // Cursor keyset sobre (starts_at, id). `starts_at` NO es único —dos
      // eventos pueden empezar a la misma hora— así que paginar solo con
      // `.gt('starts_at')` salta eventos en cuanto hay un empate.
      if (opts.cursor) {
        const { at, id } = opts.cursor;
        q = q.or(`starts_at.gt.${at},and(starts_at.eq.${at},id.gt.${id})`);
      }
    }

    // Se pide uno más de lo que se muestra: si vuelve, hay página siguiente.
    const { data, error } = await q.limit(limit + 1);
    this.loading.set(false);

    if (error) {
      this.error.set(error.message);
      return { rows: [], nextCursor: null };
    }

    const all = (data as CatalogEvent[] | null) ?? [];
    const rows = all.slice(0, limit);
    const last = rows.at(-1);
    return {
      rows,
      nextCursor:
        all.length > limit && last?.starts_at ? { at: last.starts_at, id: last.id } : null,
    };
  }

  /** Las opciones de los filtros salen de lo que hay publicado, no de una lista fija. */
  async listFacets(): Promise<{ categories: string[]; cities: string[] }> {
    const { data } = await supabase.from('v_event_public').select('category,venue_city');
    const rows = (data as { category: string | null; venue_city: string | null }[] | null) ?? [];
    return {
      categories: [...new Set(rows.map((r) => r.category).filter((c): c is string => !!c))].sort(),
      cities: [...new Set(rows.map((r) => r.venue_city).filter((c): c is string => !!c))].sort(),
    };
  }
}

/**
 * Una sola cadena literal, sin concatenar: supabase-js parsea el `select` a
 * nivel de tipos, y un `+` lo degrada a `string` y rompe la inferencia.
 *
 * Se piden las columnas explícitas para NO traer `search_text`, que son
 * kilobytes de tsvector por fila y solo existe para filtrar.
 */
const CATALOG_COLUMNS =
  'id,slug,title,category,hero_image_url,starts_at,venue_name,venue_city,organizer_name,from_price_cents,currency,sale_open,next_phase_starts_at,available_now,featured_at,max_per_user,resale_enabled' as const;

export type CatalogSort = 'date' | 'price' | 'relevance';

export interface CatalogCursor {
  readonly at: string;
  readonly id: string;
}

export interface CatalogQuery {
  readonly search?: string;
  readonly category?: string | null;
  readonly city?: string | null;
  readonly from?: string | null;
  readonly to?: string | null;
  readonly maxPriceCents?: number | null;
  readonly onlyAvailable?: boolean;
  readonly sort?: CatalogSort;
  readonly cursor?: CatalogCursor | null;
  readonly limit?: number;
}

export interface CatalogPage {
  readonly rows: readonly CatalogEvent[];
  readonly nextCursor: CatalogCursor | null;
}

/**
 * La señal de demanda de la card. Del mockup: «Alta demanda», «Pocas entradas»,
 * «Agotado», «Nuevo».
 *
 * Siempre lleva texto: el color nunca va solo (Art. 10).
 */
export function demandBadge(
  e: CatalogEvent,
): { text: string; tone: 'success' | 'warn' | 'danger' | 'info' | 'neutral' } | null {
  if (!e.sale_open) {
    return e.next_phase_starts_at
      ? { text: 'Próxima fase', tone: 'neutral' }
      : { text: 'Venta cerrada', tone: 'neutral' };
  }
  if (e.available_now === 0) return { text: 'Agotado', tone: 'danger' };
  if (e.available_now <= 20) return { text: `Últimas ${e.available_now}`, tone: 'warn' };
  if (e.featured_at) return { text: 'Destacado', tone: 'info' };
  return { text: 'Disponible', tone: 'success' };
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
