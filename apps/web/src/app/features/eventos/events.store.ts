import { Injectable, signal } from '@angular/core';
import { supabase } from '../../core/supabase.client';
import type { ReviewChecklist, Tables } from '../../core/db.types';

export type EventRow = Tables<'events'>;
export type ReviewNote = Tables<'event_review_notes'>;
export type Venue = Tables<'venues'>;

/**
 * Acceso a eventos. Todo lo que cambia de estado pasa por RPC (Art. 9.4-9.5):
 * el cliente pide, no decide. Los `update` directos solo alcanzan los campos
 * de ficha, porque `status` está fuera del grant de columna del organizador.
 */
@Injectable({ providedIn: 'root' })
export class EventsStore {
  readonly loading = signal(false);
  readonly error = signal<string | null>(null);

  /**
   * Envuelve una llamada para que el mensaje del servidor llegue a la UI tal cual.
   *
   * `PromiseLike` y no `Promise`: los builders de supabase-js son thenables, no
   * promesas — les faltan `catch` y `finally` hasta que se les hace `await`.
   */
  private async run<T>(
    fn: () => PromiseLike<{ data: T | null; error: { message: string } | null }>,
  ): Promise<{ data: T | null; error: { message: string } | null }> {
    this.loading.set(true);
    this.error.set(null);
    const { data, error } = await fn();
    this.loading.set(false);
    if (error) {
      // Los mensajes de las RPC están escritos para leerse: «faltan datos
      // obligatorios: descripción, categoría…». No se sustituyen por un
      // genérico.
      this.error.set(error.message);
      return { data: null, error };
    }
    return { data, error: null };
  }

  // ── Lectura ───────────────────────────────────────────────────────────────

  /** Mis eventos. La RLS ya filtra por organizador (007, AC-17). */
  async listMine() {
    return this.run(() =>
      supabase
        .from('events')
        .select('*, venues(name, city), organizers(trade_name, legal_name)')
        .order('created_at', { ascending: false }),
    );
  }

  /** Cola de Admin. Misma tabla; lo que cambia es quién consulta. */
  async listForReview() {
    return this.run(() =>
      supabase
        .from('events')
        .select('*, venues(name, city), organizers(trade_name, legal_name, ruc)')
        .order('submitted_at', { ascending: true, nullsFirst: false }),
    );
  }

  async get(id: string) {
    return this.run(() =>
      supabase
        .from('events')
        .select('*, venues(name, city, capacity), organizers(trade_name, legal_name, ruc)')
        .eq('id', id)
        .single(),
    );
  }

  async listNotes(eventId: string) {
    return this.run(() =>
      supabase
        .from('event_review_notes')
        .select('*, profiles:actor_id(full_name)')
        .eq('event_id', eventId)
        .order('created_at', { ascending: true }),
    );
  }

  async listVenues() {
    return this.run(() => supabase.from('venues').select('*').order('name'));
  }

  // ── Ficha: update directo, solo campos permitidos ─────────────────────────

  /**
   * `status`, `code`, `review_checklist` y los sellos de tiempo NO están aquí
   * a propósito: están fuera del grant de columna, y mandarlos devolvería 42501.
   */
  async saveDraft(
    id: string,
    patch: Partial<
      Pick<
        EventRow,
        | 'title'
        | 'description'
        | 'category'
        | 'hero_image_url'
        | 'slug'
        | 'starts_at'
        | 'doors_at'
        | 'venue_id'
        | 'capacity'
        | 'max_per_user'
        | 'resale_enabled'
        | 'max_resales'
        | 'service_charge_bps'
        | 'service_charge_payer'
        | 'qr_lead_days'
        | 'nomination_mode'
      >
    >,
  ) {
    return this.run(() => supabase.from('events').update(patch).eq('id', id).select('*').single());
  }

  // ── Transiciones: siempre RPC ─────────────────────────────────────────────

  async create(organizerId: string, title?: string) {
    return this.run(() =>
      supabase.rpc('create_event', { p_organizer_id: organizerId, p_title: title }),
    );
  }

  /** Del organizador. Falla nombrando los campos que faltan (AC-03). */
  async submit(id: string) {
    return this.run(() => supabase.rpc('submit_event', { p_event_id: id }));
  }

  /** Del organizador, solo desde `setup`. Feventi autoriza; él abre la venta. */
  async publish(id: string) {
    return this.run(() => supabase.rpc('publish_event', { p_event_id: id }));
  }

  async approve(id: string, note?: string) {
    return this.run(() => supabase.rpc('approve_event', { p_event_id: id, p_note: note }));
  }

  async reject(id: string, note: string) {
    return this.run(() => supabase.rpc('reject_event', { p_event_id: id, p_note: note }));
  }

  /** La observación es obligatoria: el servidor la exige (AC-12). */
  async requestInfo(id: string, note: string, checklist?: ReviewChecklist) {
    return this.run(() =>
      supabase.rpc('request_event_info', {
        p_event_id: id,
        p_note: note,
        p_checklist: checklist,
      }),
    );
  }

  async setChecklist(id: string, checklist: ReviewChecklist) {
    return this.run(() =>
      supabase.rpc('set_event_checklist', { p_event_id: id, p_checklist: checklist }),
    );
  }

  async pause(id: string, note?: string) {
    return this.run(() => supabase.rpc('pause_event', { p_event_id: id, p_note: note }));
  }

  async resume(id: string, note?: string) {
    return this.run(() => supabase.rpc('resume_event', { p_event_id: id, p_note: note }));
  }

  async cancel(id: string, note: string) {
    return this.run(() => supabase.rpc('cancel_event', { p_event_id: id, p_note: note }));
  }
}
