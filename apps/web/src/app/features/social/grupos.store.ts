import { Injectable, inject, signal } from '@angular/core';
import { supabase } from '../../core/supabase.client';
import { CheckoutStore, type ReserveItem } from '../checkout/checkout.store';

export type GroupStatus = 'open' | 'locked' | 'completed' | 'cancelled';

export interface PurchaseGroup {
  readonly id: string;
  readonly event_id: string;
  readonly creator_id: string;
  readonly status: GroupStatus;
  readonly order_id: string | null;
  readonly created_at: string;
}

export interface GroupMember {
  readonly group_id: string;
  readonly user_id: string;
  readonly slot: number;
  readonly order_item_id: string | null;
}

/**
 * Compra grupal (Art. 11).
 *
 * El grupo **no es un mecanismo de compra**: decide quién entra y luego le pasa
 * la lista a `reserve_order`, que es quien hace el todo-o-nada de verdad — una
 * orden con N ítems, en una transacción. Ni `reserve_order` ni `confirm_payment`
 * se tocaron para esto.
 */
@Injectable({ providedIn: 'root' })
export class GruposStore {
  private readonly checkout = inject(CheckoutStore);

  readonly loading = signal(false);
  readonly error = signal<string | null>(null);

  async mine(): Promise<readonly PurchaseGroup[]> {
    const { data, error } = await supabase
      .from('purchase_groups')
      .select('*')
      .neq('status', 'cancelled')
      .order('created_at', { ascending: false });
    if (error) {
      this.error.set(error.message);
      return [];
    }
    return (data as PurchaseGroup[] | null) ?? [];
  }

  async members(groupId: string): Promise<readonly GroupMember[]> {
    const { data } = await supabase
      .from('group_members')
      .select('*')
      .eq('group_id', groupId)
      .order('slot');
    return (data as GroupMember[] | null) ?? [];
  }

  async create(eventId: string): Promise<string | null> {
    this.loading.set(true);
    this.error.set(null);
    const { data, error } = await supabase.rpc('create_purchase_group', { p_event_id: eventId });
    this.loading.set(false);
    if (error) {
      // El caso frecuente tiene su propia frase: «ya estás en un grupo de este
      // evento» es accionable; el mensaje del índice único no lo es.
      this.error.set(
        error.message.includes('one_group_per_event')
          ? 'Ya estás en un grupo para este evento.'
          : 'No se pudo crear el grupo.',
      );
      return null;
    }
    return data as string;
  }

  async add(groupId: string, userId: string): Promise<string | null> {
    return this.rpc('add_group_member', { p_group_id: groupId, p_user_id: userId }, {
      grupo_lleno: 'El grupo ya tiene cuatro personas.',
      grupo_bloqueado: 'El grupo ya está en pago y no admite cambios.',
    });
  }

  async leave(groupId: string): Promise<string | null> {
    return this.rpc('leave_purchase_group', { p_group_id: groupId }, {
      grupo_bloqueado: 'El grupo ya está en pago: no se puede salir.',
    });
  }

  /**
   * Reservar para el grupo: una orden con **un ítem por miembro**, del mismo
   * tier, y el grupo enganchado a esa orden.
   *
   * Si `lock_purchase_group` falla, la reserva queda huérfana — y eso está
   * bien: expira sola por el reloj de `reserved_until` y devuelve el stock.
   * Es preferible a un grupo que cree estar pagando una orden que no existe.
   */
  async reserveForGroup(
    groupId: string,
    eventId: string,
    tierId: string,
    miembros: number,
  ): Promise<{ orderId: string | null; error: string | null }> {
    this.loading.set(true);
    this.error.set(null);

    const items: ReserveItem[] = Array.from({ length: miembros }, () => ({
      tier_id: tierId,
      seat_id: null,
    }));

    const reserva = await this.checkout.reserve(eventId, items);
    if (reserva.error || !reserva.data) {
      this.loading.set(false);
      // El mensaje de `reserve_order` está escrito para leerse tal cual
      // —«solo quedan 2 entradas de esa zona y se piden 3»— y en una compra de
      // grupo es justo el que hace falta.
      const msg = reserva.error?.message ?? 'No se pudo reservar para el grupo.';
      this.error.set(msg);
      return { orderId: null, error: msg };
    }

    const orderId = reserva.data;
    const { error } = await supabase.rpc('lock_purchase_group', {
      p_group_id: groupId,
      p_order_id: orderId,
    });
    this.loading.set(false);

    if (error) {
      this.error.set('No se pudo enganchar la reserva al grupo.');
      return { orderId: null, error: error.message };
    }
    return { orderId, error: null };
  }

  private async rpc(
    fn: 'add_group_member' | 'leave_purchase_group',
    args: Record<string, string>,
    mensajes: Record<string, string>,
  ): Promise<string | null> {
    this.loading.set(true);
    this.error.set(null);
    const { error } = await supabase.rpc(fn as never, args as never);
    this.loading.set(false);
    if (!error) return null;

    const clave = Object.keys(mensajes).find((k) => error.message.includes(k));
    const msg = clave ? mensajes[clave] : 'No se pudo completar la acción.';
    this.error.set(msg);
    return msg;
  }
}
