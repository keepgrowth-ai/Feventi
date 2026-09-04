import { Injectable, signal } from '@angular/core';
import { supabase } from '../../core/supabase.client';
import type { Json, Tables } from '../../core/db.types';

export type Order = Tables<'orders'>;
export type OrderItem = Tables<'order_items'>;
export type Ticket = Tables<'tickets'>;

/** Una entrada a reservar. Una por elemento: no hay cantidad. */
export interface ReserveItem {
  readonly tier_id: string;
  readonly seat_id: string | null;
}

export type OrderWithItems = Order & {
  order_items: (OrderItem & {
    price_tiers?: { price_cents: number; zone_id: string } | null;
    seats?: { row_label: string; seat_number: number } | null;
  })[];
  events?: {
    title: string | null;
    slug: string | null;
    starts_at: string | null;
    nomination_mode: 'strict' | 'flexible';
    venues?: { name: string; city: string } | null;
  } | null;
};

/**
 * El checkout. Todo pasa por RPC (Art. 9.4-9.5): el cliente **no** tiene
 * insert ni update sobre `orders`, `order_items`, `payments` ni `tickets`.
 *
 * Y ninguna aritmética de dinero vive aquí. `reserve_order` devuelve la orden
 * con `subtotal_cents`, `service_charge_cents` y `total_cents` ya calculados —
 * el cargo redondeado **una vez sobre el subtotal**, que es la diferencia entre
 * cuadrar y no cuadrar (Art. 5, AC-18).
 */
@Injectable({ providedIn: 'root' })
export class CheckoutStore {
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
      // Los mensajes de las RPC están escritos para leerse tal cual:
      // «solo quedan 0 entradas de esa zona y se piden 1»,
      // «alguien acaba de tomar uno de esos asientos: elige otro».
      this.error.set(error.message);
      return { data: null, error };
    }
    return { data, error: null };
  }

  /**
   * Reserva y retiene stock durante 15 minutos.
   *
   * Si otro se queda con el último cupo o con el asiento, esto falla — y ese
   * fallo es la garantía, no un problema: lo decide un lock y un índice único,
   * no una consulta de disponibilidad que ya estaría vieja.
   */
  async reserve(eventId: string, items: readonly ReserveItem[]) {
    return this.run<string>(() =>
      supabase.rpc('reserve_order', {
        p_event_id: eventId,
        p_items: items as unknown as Json,
      }),
    );
  }

  async get(orderId: string) {
    return this.run<OrderWithItems>(() =>
      supabase
        .from('orders')
        .select(
          'id,code,event_id,buyer_id,status,subtotal_cents,discount_cents,service_charge_cents,total_cents,currency,service_charge_payer,service_charge_bps,reserved_until,created_at,paid_at,' +
            'order_items(id,price_tier_id,seat_id,unit_price_cents,attendee_name,attendee_dni_last4,nominated_at,price_tiers(price_cents,zone_id),seats(row_label,seat_number)),' +
            'events(title,slug,starts_at,nomination_mode,venues(name,city))',
        )
        .eq('id', orderId)
        .single(),
    );
  }

  /**
   * El DNI viaja en claro por HTTPS y el servidor lo hashea con el pepper.
   * Nunca se calcula el hash aquí: si el cliente pudiera elegirlo, copiaría el
   * de otra persona y se haría pasar por ella en puerta (Art. 7.1).
   */
  async nominate(itemId: string, name: string, dni: string) {
    return this.run(() =>
      supabase.rpc('set_item_attendee', { p_item_id: itemId, p_name: name, p_dni: dni }),
    );
  }

  /** Exige DNI propio y, en modo `strict`, que todo esté nominado. */
  async startPayment(orderId: string) {
    return this.run(() => supabase.rpc('start_payment', { p_order_id: orderId }));
  }

  /** Conserva la reserva hasta `reserved_until`: se puede reintentar. */
  async failPayment(orderId: string, reason?: string) {
    return this.run(() =>
      supabase.rpc('fail_payment', { p_order_id: orderId, p_reason: reason }),
    );
  }

  /** Los tickets de una orden, una vez emitidos. */
  async ticketsOf(orderId: string) {
    return this.run<Ticket[]>(() =>
      supabase
        .from('tickets')
        .select('*, order_items!inner(order_id)')
        .eq('order_items.order_id', orderId)
        .order('code'),
    );
  }

  /** Los asientos libres de una zona, para el selector (D-09: lista, no plano). */
  async freeSeats(zoneId: string) {
    const { data, error } = await supabase
      .from('seats')
      .select('id,row_label,seat_number,blocked,order_items(id)')
      .eq('zone_id', zoneId)
      .order('row_label')
      .order('seat_number');

    if (error) {
      this.error.set(error.message);
      return [];
    }
    // La disponibilidad se DERIVA de los order_items vivos: `seats` no guarda
    // estado, porque un booleano ahí se desincroniza la primera vez que una
    // reserva expira sin que nadie lo actualice (003).
    return (data ?? [])
      .filter((s) => !s.blocked && (s.order_items?.length ?? 0) === 0)
      .map((s) => ({ id: s.id, row_label: s.row_label, seat_number: s.seat_number }));
  }
}

/**
 * Cuánto queda de la reserva, en segundos. Negativo si ya venció.
 *
 * El reloj del cliente puede ir desviado, así que esto es orientativo: quien
 * decide de verdad es el servidor, que rechaza `start_payment` con la reserva
 * vencida y tiene un job liberando cada minuto.
 */
export function secondsLeft(reservedUntil: string | null): number {
  if (!reservedUntil) return 0;
  return Math.floor((new Date(reservedUntil).getTime() - Date.now()) / 1000);
}

export function mmss(totalSeconds: number): string {
  const s = Math.max(totalSeconds, 0);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}
