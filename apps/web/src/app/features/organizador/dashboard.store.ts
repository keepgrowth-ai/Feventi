import { Injectable, signal } from '@angular/core';
import { supabase } from '../../core/supabase.client';
import type { Json } from '../../core/db.types';

/** Un tramo de la política de liquidación declarada en el evento. */
export interface PayoutTranche {
  readonly pct: number;
  readonly trigger: string;
}

export interface EventSales {
  readonly event_id: string;
  readonly capacity: number | null;
  readonly service_charge_bps: number;
  readonly service_charge_payer: 'fan' | 'organizer';
  readonly payout_policy: Json;
  readonly tickets_sold: number;
  readonly gross_cents: number;
  readonly feventi_commission_cents: number;
  readonly refunds_cents: number;
  readonly net_estimated_cents: number;
}

export interface PhaseSales {
  readonly event_id: string;
  /** Null en la fila agregada «Otras fases» (AC-06). */
  readonly phase_id: string | null;
  readonly name: string;
  readonly kind: string | null;
  readonly starts_at: string | null;
  readonly ends_at: string | null;
  readonly sort_order: number;
  readonly tickets: number;
  readonly gross_cents: number;
}

export interface GateStatsRow {
  readonly event_id: string;
  readonly gate: string;
  readonly scans: number;
  readonly allowed: number;
  readonly manual_review: number;
  readonly already_used: number;
  readonly denied: number;
  readonly screenshots: number;
  readonly tickets_total: number;
  readonly tickets_used: number;
}

/**
 * El dashboard del organizador.
 *
 * Todo sale de vistas AGREGADAS. Este store no tiene —ni puede tener— un método
 * que devuelva un comprador, una orden o un ticket: el organizador no lee esas
 * tablas (Art. 7.5, D-06), y la RLS lo impone aunque alguien escriba la consulta.
 *
 * Y no hay aritmética de dinero aquí. `net_estimated_cents` llega calculado del
 * servidor; restarlo en el cliente sería tener la fórmula en dos sitios y que un
 * día no coincidan — con el organizador reclamando, con razón.
 */
@Injectable({ providedIn: 'root' })
export class DashboardStore {
  readonly loading = signal(false);
  readonly error = signal<string | null>(null);

  async load(eventId: string): Promise<{
    sales: EventSales | null;
    phases: readonly PhaseSales[];
    gates: readonly GateStatsRow[];
  }> {
    this.loading.set(true);
    this.error.set(null);

    const [sales, phases, gates] = await Promise.all([
      supabase.from('v_event_sales').select('*').eq('event_id', eventId).maybeSingle(),
      supabase.from('v_event_phase_sales').select('*').eq('event_id', eventId).order('sort_order'),
      supabase.from('v_gate_stats').select('*').eq('event_id', eventId).order('gate'),
    ]);

    this.loading.set(false);
    const fallo = sales.error ?? phases.error ?? gates.error;
    if (fallo) this.error.set(fallo.message);

    return {
      sales: (sales.data as unknown as EventSales | null) ?? null,
      phases: (phases.data as unknown as PhaseSales[] | null) ?? [],
      gates: (gates.data as unknown as GateStatsRow[] | null) ?? [],
    };
  }
}

/**
 * La política de liquidación declarada en el evento.
 *
 * Se lee con cuidado porque es un `jsonb` libre: un evento antiguo, o uno tocado
 * a mano, puede traer cualquier cosa. Devolver `[]` deja la sección vacía en vez
 * de romper el dashboard entero por un tramo mal escrito.
 */
export function tranches(policy: Json): readonly PayoutTranche[] {
  if (!Array.isArray(policy)) return [];
  return policy.flatMap((t) => {
    if (typeof t !== 'object' || t === null || Array.isArray(t)) return [];
    const pct = (t as Record<string, unknown>)['pct'];
    const trigger = (t as Record<string, unknown>)['trigger'];
    return typeof pct === 'number' && typeof trigger === 'string' ? [{ pct, trigger }] : [];
  });
}
