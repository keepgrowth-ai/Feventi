import { Injectable, signal } from '@angular/core';
import { environment } from '../../../environments/environment';
import { supabase } from '../../core/supabase.client';

export type QrState = 'available' | 'too_early' | 'disabled' | 'spent';

export interface WalletTicket {
  readonly id: string;
  readonly code: string;
  readonly status: string;
  readonly face_value_cents: number;
  readonly qr_available_from: string | null;
  readonly issued_at: string;
  readonly used_at: string | null;
  readonly holder_name: string | null;
  readonly holder_dni_last4: string | null;
  readonly event_id: string;
  readonly event_slug: string | null;
  readonly event_title: string | null;
  readonly starts_at: string | null;
  readonly doors_at: string | null;
  readonly event_status: string;
  readonly qr_lead_days: number;
  readonly resale_enabled: boolean;
  readonly venue_name: string | null;
  readonly venue_city: string | null;
  readonly zone_name: string;
  readonly zone_kind: 'standing' | 'seated';
  readonly row_label: string | null;
  readonly seat_number: number | null;
  readonly is_past: boolean;
  /** La regla del Art. 2, resuelta en el servidor. El front no la recalcula. */
  readonly qr_state: QrState;
  readonly disabled_reason: string | null;
}

export interface QrToken {
  readonly token: string;
  readonly slot: number;
  readonly slot_seconds: number;
  /** Segundos que faltan para el siguiente slot, según el reloj del SERVIDOR. */
  readonly expires_in: number;
}

/**
 * La wallet y el QR.
 *
 * El token **no se guarda en ningún sitio** (AC-21): ni `localStorage`, ni
 * `sessionStorage`, ni un caché. Vive en la señal del componente y muere con la
 * pestaña. Persistirlo sería fabricar exactamente la captura que el Art. 2.3
 * dice que no debe funcionar.
 */
@Injectable({ providedIn: 'root' })
export class WalletStore {
  readonly loading = signal(false);
  readonly error = signal<string | null>(null);

  async list(): Promise<readonly WalletTicket[]> {
    this.loading.set(true);
    this.error.set(null);
    const { data, error } = await supabase
      .from('v_my_tickets')
      .select('*')
      .order('is_past')
      .order('starts_at');
    this.loading.set(false);
    if (error) {
      this.error.set(error.message);
      return [];
    }
    return (data as unknown as WalletTicket[] | null) ?? [];
  }

  /**
   * El saldo de puntos (013). Una fila, una columna.
   *
   * Devuelve 0 si falla y no toca `error`: los puntos son un adorno de la
   * cabecera, y un fallo aquí no puede tapar la lista de entradas, que es
   * para lo que el fan abrió la pantalla.
   */
  async points(): Promise<number> {
    const { data, error } = await supabase.from('v_my_points').select('total').maybeSingle();
    if (error) return 0;
    return (data as { total: number } | null)?.total ?? 0;
  }

  /**
   * Pide el token del slot actual a la Edge Function.
   *
   * Se llama por `fetch` y no por `supabase.functions.invoke` para poder leer el
   * cuerpo de los 409: la función responde el MOTIVO —«el QR estará disponible
   * el 19 de octubre»— y ese motivo es lo que la pantalla tiene que mostrar. Un
   * error genérico deja al fan sin saber si esperar o escribir a soporte.
   */
  async qrToken(ticketId: string): Promise<{ data: QrToken | null; error: string | null }> {
    const { data: sesion } = await supabase.auth.getSession();
    const jwt = sesion.session?.access_token;
    if (!jwt) return { data: null, error: 'Tu sesión venció. Vuelve a entrar.' };

    const res = await fetch(`${environment.supabaseUrl}/functions/v1/qr-token`, {
      method: 'POST',
      headers: {
        apikey: environment.supabasePublishableKey,
        authorization: `Bearer ${jwt}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({ ticket_id: ticketId }),
    });

    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
      return { data: null, error: body.error ?? 'No se pudo generar el QR.' };
    }
    return { data: body as QrToken, error: null };
  }
}

/**
 * Qué decirle al fan sobre el QR de este ticket.
 *
 * «QR desde el 1 de julio» a secas se lee como un error. Explicar la REGLA —«14
 * días antes del evento»— convierte una negativa en una expectativa.
 */
export function qrCopy(t: WalletTicket): { chip: string; tone: 'success' | 'warn' | 'danger' | 'neutral'; detail: string } {
  switch (t.qr_state) {
    case 'available':
      return { chip: 'QR activo', tone: 'success', detail: '' };
    case 'too_early': {
      const desde = t.qr_available_from
        ? new Date(t.qr_available_from).toLocaleDateString('es-PE', {
            day: 'numeric',
            month: 'long',
          })
        : '';
      return {
        chip: `QR desde el ${desde}`,
        tone: 'neutral',
        detail: `Tu QR estará disponible desde el ${desde} (${t.qr_lead_days} días antes del evento).`,
      };
    }
    case 'spent':
      return {
        chip: 'Usada',
        tone: 'neutral',
        detail: t.used_at
          ? `Ingreso registrado el ${new Date(t.used_at).toLocaleString('es-PE', {
              day: 'numeric',
              month: 'long',
              hour: '2-digit',
              minute: '2-digit',
              hour12: false,
            })}.`
          : 'Esta entrada ya se usó en puerta.',
    };
    default: {
      // Art. 2.4: decir la CAUSA. «QR inhabilitado» a secas se lee como
      // «me robaron la entrada».
      const causa: Record<string, string> = {
        listed: 'Está publicada en reventa oficial.',
        transferred: 'La transferiste a otra persona.',
        void: 'Feventi anuló esta entrada.',
        refunded: 'Esta entrada fue reembolsada.',
      };
      return {
        chip: 'QR inhabilitado',
        tone: 'warn',
        detail: causa[t.disabled_reason ?? ''] ?? 'El evento fue cancelado.',
      };
    }
  }
}
