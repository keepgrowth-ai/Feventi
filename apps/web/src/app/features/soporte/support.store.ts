import { Injectable, signal } from '@angular/core';
import { supabase } from '../../core/supabase.client';

export type SupportKind =
  | 'payment' | 'ticket' | 'qr' | 'resale' | 'courtesy'
  | 'group' | 'refund' | 'cancellation' | 'ownership' | 'other';

export type SupportStatus =
  | 'open' | 'waiting_user' | 'in_progress' | 'escalated' | 'resolved' | 'closed';

export type SupportPriority = 'low' | 'normal' | 'high' | 'urgent';

export interface SupportCase {
  readonly id: string;
  readonly code: string;
  readonly kind: SupportKind;
  readonly status: SupportStatus;
  readonly priority: SupportPriority;
  readonly subject: string;
  readonly created_at: string;
  readonly updated_at: string;
  readonly resolved_at: string | null;
  readonly event_id: string | null;
  readonly ticket_id: string | null;
  readonly order_id: string | null;
  readonly checkin_id: string | null;
  readonly assigned_to: string | null;
  readonly event_title: string | null;
  readonly ticket_code: string | null;
  readonly order_code: string | null;
  /** «yo», el nombre real (solo Admin) o «un asistente». Nunca el id. */
  readonly opened_by_label: string;
  readonly messages: number;
}

export interface SupportMessage {
  readonly id: string;
  readonly case_id: string;
  readonly author_id: string | null;
  readonly body: string;
  readonly internal: boolean;
  readonly created_at: string;
}

/** Lo que se adjunta al abrir. Solo el OBJETO: el contexto lo pone el servidor. */
export interface CaseContext {
  readonly ticketId?: string;
  readonly orderId?: string;
  readonly eventId?: string;
  readonly checkinId?: string;
}

/**
 * Soporte contextual.
 *
 * `open` manda el objeto y NADA más: el evento y la orden los rellena
 * `open_support_case` desde el ticket (AC-03). Si el cliente los mandara,
 * podría adjuntar los de otro y ensuciar la cola de un organizador ajeno.
 *
 * Los mensajes de error de las RPC llegan tal cual a la UI: están escritos para
 * leerse — «ya hay un caso de recuperación abierto para este pedido (#1021)»— y
 * sustituirlos por un genérico deja al usuario sin saber qué hacer.
 */
@Injectable({ providedIn: 'root' })
export class SupportStore {
  readonly loading = signal(false);
  readonly error = signal<string | null>(null);

  async open(
    kind: SupportKind,
    subject: string,
    body: string,
    ctx: CaseContext = {},
  ): Promise<string | null> {
    this.loading.set(true);
    this.error.set(null);
    const { data, error } = await supabase.rpc('open_support_case', {
      p_kind: kind,
      p_subject: subject,
      p_body: body,
      p_ticket_id: ctx.ticketId ?? null,
      p_order_id: ctx.orderId ?? null,
      p_event_id: ctx.eventId ?? null,
      p_checkin_id: ctx.checkinId ?? null,
    });
    this.loading.set(false);
    if (error) {
      this.error.set(error.message);
      return null;
    }
    return data as unknown as string;
  }

  async list(filtro?: { status?: SupportStatus; kind?: SupportKind }): Promise<readonly SupportCase[]> {
    let q = supabase.from('v_support_queue').select('*');
    if (filtro?.status) q = q.eq('status', filtro.status);
    if (filtro?.kind) q = q.eq('kind', filtro.kind);
    const { data, error } = await q.order('created_at', { ascending: false });
    if (error) this.error.set(error.message);
    return (data as unknown as SupportCase[] | null) ?? [];
  }

  async get(id: string): Promise<SupportCase | null> {
    const { data } = await supabase.from('v_support_queue').select('*').eq('id', id).maybeSingle();
    return (data as unknown as SupportCase | null) ?? null;
  }

  /**
   * El hilo.
   *
   * No se filtra por `internal` aquí: la RLS ya decide qué mensajes salen
   * (AC-10). Filtrar en el cliente sería fingir una protección que no existe —
   * y el día que alguien mire la respuesta de red, la nota interna estaría ahí.
   */
  async messages(caseId: string): Promise<readonly SupportMessage[]> {
    const { data } = await supabase
      .from('support_messages')
      .select('*')
      .eq('case_id', caseId)
      .order('created_at');
    return (data as unknown as SupportMessage[] | null) ?? [];
  }

  async reply(caseId: string, body: string, internal = false): Promise<boolean> {
    this.error.set(null);
    const { error } = await supabase.rpc('post_support_message', {
      p_case_id: caseId,
      p_body: body,
      p_internal: internal,
    });
    if (error) this.error.set(error.message);
    return !error;
  }

  /** Solo Admin. La RPC lo comprueba; el guard de ruta es solo navegación. */
  async manage(
    caseId: string,
    cambios: { status?: SupportStatus; priority?: SupportPriority; assign?: string; note?: string },
  ): Promise<boolean> {
    this.error.set(null);
    const { error } = await supabase.rpc('manage_support_case', {
      p_case_id: caseId,
      p_status: cambios.status ?? null,
      p_priority: cambios.priority ?? null,
      p_assign: cambios.assign ?? null,
      p_note: cambios.note ?? null,
    });
    if (error) this.error.set(error.message);
    return !error;
  }

  async ticketAction(
    caseId: string,
    ticketId: string,
    action: 'voided' | 'refunded' | 'corrected' | 'transferred',
    note?: string,
    corrects?: string,
  ): Promise<boolean> {
    this.error.set(null);
    const { error } = await supabase.rpc('admin_ticket_action', {
      p_case_id: caseId,
      p_ticket_id: ticketId,
      p_action: action,
      p_note: note ?? null,
      p_corrects: corrects ?? null,
    });
    if (error) this.error.set(error.message);
    return !error;
  }
}

/**
 * Los tipos de caso, en lenguaje humano.
 *
 * `refund` y `cancellation` llevan una frase que los separa. Es el riesgo
 * central del feature (D-12): si el fan elige mal, se abre la vía equivocada y
 * la correcta queda bloqueada hasta cerrar la primera. La distinción no puede
 * estar solo en la etiqueta.
 */
export const KINDS: ReadonlyArray<{
  readonly value: SupportKind;
  readonly label: string;
  readonly hint: string;
}> = [
  { value: 'qr',          label: 'Mi QR no funciona',              hint: 'No carga, no lo aceptan en puerta o dice que ya se usó.' },
  { value: 'ticket',      label: 'Problema con mi entrada',        hint: 'Datos del titular, zona o asiento equivocados.' },
  { value: 'payment',     label: 'Problema con el pago',           hint: 'Me cobraron y no llegó la entrada, o el cobro no cuadra.' },
  { value: 'refund',      label: 'Quiero que me devuelvan el dinero', hint: 'Tú ya no puedes ir, pero el evento SÍ se hace. Lo decide Feventi según la política del evento.' },
  { value: 'cancellation',label: 'El evento se canceló o cambió',  hint: 'El organizador anuló o movió el evento. Esto NO es lo mismo que pedir un reembolso: aquí el problema no lo pusiste tú.' },
  { value: 'ownership',   label: 'La entrada no está a mi nombre', hint: 'Me la pasaron, o el titular está mal escrito.' },
  { value: 'resale',      label: 'Reventa oficial',                hint: 'Publicar, retirar o cobrar una entrada revendida.' },
  { value: 'courtesy',    label: 'Cortesías',                      hint: 'Un código de invitación que no funciona.' },
  { value: 'group',       label: 'Compra grupal',                  hint: 'Reservas de varias entradas coordinadas.' },
  { value: 'other',       label: 'Otra cosa',                      hint: 'Cuéntalo con tus palabras y lo derivamos.' },
];

export const STATUS_LABEL: Record<SupportStatus, { label: string; tone: 'success' | 'warn' | 'danger' | 'info' | 'neutral' }> = {
  open:         { label: 'Abierto',            tone: 'info' },
  waiting_user: { label: 'Esperando tu respuesta', tone: 'warn' },
  in_progress:  { label: 'En revisión',        tone: 'info' },
  escalated:    { label: 'Escalado',           tone: 'danger' },
  resolved:     { label: 'Resuelto',           tone: 'success' },
  closed:       { label: 'Cerrado',            tone: 'neutral' },
};

// AC-23: prioridad con el trío semántico Y texto. El color nunca va solo.
export const PRIORITY_LABEL: Record<SupportPriority, { label: string; tone: 'success' | 'warn' | 'danger' | 'neutral' }> = {
  low:    { label: 'Baja',    tone: 'neutral' },
  normal: { label: 'Normal',  tone: 'success' },
  high:   { label: 'Alta',    tone: 'warn' },
  urgent: { label: 'Urgente', tone: 'danger' },
};

export function kindLabel(k: SupportKind): string {
  return KINDS.find((x) => x.value === k)?.label ?? k;
}
