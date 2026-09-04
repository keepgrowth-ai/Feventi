import { Injectable, signal } from '@angular/core';
import { environment } from '../../../environments/environment';
import { supabase } from '../../core/supabase.client';

export type CheckinResult = 'allowed' | 'manual_review' | 'already_used' | 'denied';

export interface GateEvent {
  readonly event_id: string;
  readonly title: string | null;
  readonly starts_at: string | null;
  readonly doors_at: string | null;
  readonly event_status: string;
  readonly nomination_mode: 'strict' | 'flexible';
  readonly venue_name: string | null;
  readonly venue_city: string | null;
  readonly venue_address: string | null;
  readonly assignment_id: string;
  readonly gate: string;
  readonly zone_id: string | null;
  readonly zone_name: string | null;
  readonly shift_from: string | null;
  readonly shift_to: string | null;
  /** Si está en turno lo decide el SERVIDOR, con la misma regla que gate_checkin. */
  readonly shift_active: boolean;
}

export interface VerdictTicket {
  readonly id: string;
  readonly code: string;
  readonly status: string;
  readonly holder_name: string | null;
  /** AC-20: los últimos cuatro. El hash del DNI no sale de la base. */
  readonly dni_last4: string | null;
  readonly nominated: boolean;
  readonly zone_name: string | null;
  readonly row_label: string | null;
  readonly seat_number: number | null;
}

export interface Verdict {
  readonly checkin_id: string;
  readonly result: CheckinResult;
  readonly reason: string;
  readonly gate: string;
  readonly ticket: VerdictTicket | null;
  readonly first_at: string | null;
  readonly first_gate: string | null;
}

export interface Checkin {
  readonly id: string;
  readonly result: CheckinResult;
  readonly reason: string;
  readonly gate: string;
  readonly created_at: string;
  readonly scanned_code: string | null;
  readonly ticket_id: string | null;
}

export interface GateStats {
  readonly scans: number;
  readonly allowed: number;
  readonly manual_review: number;
  readonly already_used: number;
  readonly denied: number;
  readonly screenshots: number;
  readonly tickets_total: number;
  readonly tickets_used: number;
}

export interface DniMatch {
  readonly ticket_id: string;
  readonly code: string;
  readonly status: string;
  readonly holder_name: string | null;
  readonly dni_last4: string | null;
  readonly zone_name: string | null;
  readonly row_label: string | null;
  readonly seat_number: number | null;
}

/**
 * El validador de puerta.
 *
 * Nada de lo que decide esta clase decide de verdad: la decisión entera vive en
 * `gate_checkin`, en una transacción. Aquí solo se manda el código y se pinta la
 * respuesta. Si algún día alguien quiere «agilizar» resolviendo en el cliente,
 * el resultado es dos personas dentro con una entrada.
 */
@Injectable({ providedIn: 'root' })
export class GateStore {
  readonly error = signal<string | null>(null);
  readonly validating = signal(false);

  async myEvents(): Promise<readonly GateEvent[]> {
    const { data, error } = await supabase
      .from('v_my_gate_events')
      .select('*')
      .order('starts_at');
    if (error) {
      this.error.set(error.message);
      return [];
    }
    return (data as unknown as GateEvent[] | null) ?? [];
  }

  /**
   * Manda un código a validar.
   *
   * Por `fetch` y no por `functions.invoke` para poder leer el cuerpo de los
   * 403: «no eres staff de este evento» y «fuera de la ventana de turno» son dos
   * cosas distintas, y el staff en la puerta necesita saber cuál de las dos.
   */
  async validate(
    eventId: string,
    body: { token: string } | { mode: 'dni'; ticket_id: string },
  ): Promise<Verdict | null> {
    this.validating.set(true);
    this.error.set(null);
    try {
      const { data: sesion } = await supabase.auth.getSession();
      const jwt = sesion.session?.access_token;
      if (!jwt) {
        this.error.set('Tu sesión venció. Vuelve a entrar.');
        return null;
      }

      const res = await fetch(`${environment.supabaseUrl}/functions/v1/qr-validate`, {
        method: 'POST',
        headers: {
          apikey: environment.supabasePublishableKey,
          authorization: `Bearer ${jwt}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify({ event_id: eventId, ...body }),
      });

      const json = await res.json().catch(() => ({}));
      if (!res.ok) {
        this.error.set(json.error ?? 'No se pudo validar. Reintenta.');
        return null;
      }
      return json as Verdict;
    } catch {
      // Se llega aquí sin red. El layout ya bloquea el escáner (AC-31); esto es
      // el caso de que la red se caiga ENTRE el disparo y la respuesta.
      this.error.set('Se perdió la conexión al validar. Vuelve a escanear.');
      return null;
    } finally {
      this.validating.set(false);
    }
  }

  /** Modo DNI (D-03): el fan sin batería o con la pantalla rota. */
  async findByDni(eventId: string, dni: string): Promise<readonly DniMatch[]> {
    const { data, error } = await supabase.rpc('gate_find_by_dni', {
      p_event_id: eventId,
      p_dni: dni,
    });
    if (error) {
      this.error.set(
        /22023/.test(error.code ?? '') || /8 d/i.test(error.message)
          ? 'El documento son ocho dígitos.'
          : error.message,
      );
      return [];
    }
    return (data as unknown as DniMatch[] | null) ?? [];
  }

  async history(eventId: string): Promise<readonly Checkin[]> {
    const { data } = await supabase
      .from('checkins')
      .select('id, result, reason, gate, created_at, scanned_code, ticket_id')
      .eq('event_id', eventId)
      .order('created_at', { ascending: false })
      .limit(50);
    return (data as unknown as Checkin[] | null) ?? [];
  }

  async stats(eventId: string): Promise<GateStats | null> {
    const { data } = await supabase
      .from('v_gate_stats')
      .select('*')
      .eq('event_id', eventId)
      .maybeSingle();
    return (data as unknown as GateStats | null) ?? null;
  }
}

export interface VerdictCopy {
  readonly titulo: string;
  readonly instruccion: string;
  readonly icono: string;
  readonly clase: string;
}

/**
 * Qué dice la pantalla, para cada resultado.
 *
 * Tres reglas que salen del spec y no se negocian:
 *
 *  1. `already_used` y `denied` comparten paleta pero NO mensaje. El primero es
 *     un diagnóstico para el supervisor; el segundo, una instrucción para el
 *     staff. Quien está en la puerta necesita saber qué HACER, no qué pasó.
 *  2. «REVISAR MANUALMENTE» no significa «no entra». Significa que entra con una
 *     comprobación, y el texto dice cuál.
 *  3. Cada resultado lleva color, icono y texto. Nunca solo color.
 */
export function verdictCopy(v: Verdict): VerdictCopy {
  const t = v.ticket;
  const sitio = t
    ? [t.zone_name, t.row_label ? `Fila ${t.row_label}-${t.seat_number}` : null]
        .filter(Boolean)
        .join(' · ')
    : '';

  switch (v.result) {
    case 'allowed':
      return {
        titulo: 'ACCESO PERMITIDO',
        instruccion: t?.nominated
          ? `${sitio}. Titular verificado con DNI ••••${t.dni_last4}.`
          : `${sitio}. Déjale pasar.`,
        icono: '✓',
        clase: 'bg-success-fg',
      };

    case 'manual_review':
      return {
        titulo: 'REVISAR MANUALMENTE',
        instruccion: MANUAL[v.reason] ?? 'Comprueba con el asistente y deja pasar si cuadra.',
        icono: '!',
        clase: 'bg-warn-fg',
      };

    case 'already_used': {
      const hora = v.first_at
        ? new Date(v.first_at).toLocaleTimeString('es-PE', {
            hour: '2-digit',
            minute: '2-digit',
            hour12: false,
          })
        : null;
      return {
        titulo: 'YA UTILIZADO',
        instruccion:
          (hora ? `Entró a las ${hora} por ${v.first_gate}. ` : 'Ya se registró un ingreso. ') +
          'Escala a supervisor: casi siempre es un doble escaneo o una pantalla compartida.',
        icono: '↺',
        clase: 'bg-danger-fg',
      };
    }

    default:
      return {
        titulo: 'ACCESO DENEGADO',
        instruccion: DENIED[v.reason] ?? 'Deriva a soporte con el código de la entrada.',
        icono: '✕',
        clase: 'bg-danger-fg',
      };
  }
}

// El motivo NO se muestra en crudo: cada uno tiene una acción distinta, y es la
// acción lo que el staff necesita leer de un vistazo.
const MANUAL: Record<string, string> = {
  not_nominated:
    'Esta entrada no tiene titular declarado. Pide un documento, anótalo y deja pasar.',
  wrong_zone:
    'La entrada es de otra zona. Indícale la puerta que le toca; si tu supervisor lo autoriza, déjala pasar aquí.',
  dni_mode:
    'Validada a mano por documento. Compara el nombre con el carné antes de dejar pasar.',
};

const DENIED: Record<string, string> = {
  qr_unreadable:
    'Ese código no es de Feventi o está dañado. Pide abrir la wallet en la app, no una captura.',
  screenshot_suspected:
    'Es una captura de pantalla: el código ya caducó. Pide abrir la wallet en la app.',
  wrong_event: 'Esa entrada es de otro evento. Comprueba la fecha con el asistente.',
  event_cancelled: 'El evento está cancelado. Deriva a soporte.',
  not_nominated:
    'Este evento exige nominación y esta entrada no la tiene. Se nomina desde la app, con el DNI del titular.',
  ticket_listed:
    'Está publicada en reventa, y eso inhabilita el QR. Pide que la retire de la reventa desde la app.',
  ticket_transferred: 'La transfirió a otra persona. Tiene que entrar quien la recibió.',
  ticket_void: 'Feventi anuló esta entrada. Deriva a soporte.',
  ticket_refunded: 'Esta entrada fue reembolsada. Deriva a soporte.',
};
