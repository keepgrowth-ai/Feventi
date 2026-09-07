import { Injectable, signal } from '@angular/core';
import { supabase } from '../../core/supabase.client';

export interface Friend {
  readonly edge_id: string;
  readonly friend_id: string;
  readonly full_name: string | null;
  readonly avatar_url: string | null;
  readonly since: string | null;
}

export interface FriendRequest {
  readonly edge_id: string;
  readonly requester_id: string;
  readonly full_name: string | null;
  readonly avatar_url: string | null;
  readonly created_at: string;
}

export interface EventSignal {
  readonly event_id: string;
  readonly friends_going: number;
  readonly friends_interested: number;
  /** Hasta dos nombres de pila (D-46). Null si no llegan; la señal aguanta. */
  readonly going_names: readonly string[] | null;
  readonly interested_names: readonly string[] | null;
}

export interface BlockedUser {
  readonly blocked_id: string;
  readonly created_at: string;
}

/**
 * El grafo social.
 *
 * **Sin caché.** El grafo cambia por acción de OTRA persona: alguien acepta,
 * alguien te bloquea. Una lista guardada en una señal de servicio muestra
 * amigos que ya no lo son, y en esta pantalla eso no es una molestia visual
 * sino un dato de privacidad desactualizado.
 *
 * Ninguna respuesta trae `ninja_mode`, ni la del amigo ni la de nadie. Si el
 * front supiera quién está escondido, la función estaría rota por diseño: el
 * filtro vive en `private.can_see_activity_of` y no sale de la base de datos.
 */
@Injectable({ providedIn: 'root' })
export class SocialStore {
  readonly loading = signal(false);
  readonly error = signal<string | null>(null);

  /**
   * Lo que se le dice al usuario pase lo que pase al pedir amistad.
   *
   * Es el MISMO texto en el éxito y en los cuatro fallos —correo inexistente,
   * uno mismo, relación ya existente, bloqueo— porque distinguirlos convertiría
   * el formulario en un oráculo de «¿está esta persona registrada en Feventi?».
   * La RPC ya devuelve un único error; esto es la otra mitad de la misma idea.
   */
  static readonly RESULTADO_SOLICITUD =
    'Si esa persona usa Feventi, le llegará tu solicitud.';

  // Las tres lecturas se escriben enteras. Un helper que reciba el nombre de la
  // relación no compila: `blocks` es tabla y las otras dos son vistas, y las
  // sobrecargas del cliente tipado son dos listas distintas. La abstracción
  // salía más larga que las tres llamadas.
  async friends(): Promise<readonly Friend[]> {
    this.loading.set(true);
    this.error.set(null);
    const { data, error } = await supabase.from('v_my_friends').select('*').order('full_name');
    return this.unwrap<Friend>(data, error);
  }

  async requests(): Promise<readonly FriendRequest[]> {
    this.loading.set(true);
    this.error.set(null);
    const { data, error } = await supabase
      .from('v_my_friend_requests')
      .select('*')
      .order('created_at');
    return this.unwrap<FriendRequest>(data, error);
  }

  async blocked(): Promise<readonly BlockedUser[]> {
    this.loading.set(true);
    this.error.set(null);
    const { data, error } = await supabase.from('blocks').select('*').order('created_at');
    return this.unwrap<BlockedUser>(data, error);
  }

  /**
   * Todas mis señales de una vez, indexadas por evento.
   *
   * Una sola consulta sin filtro: la vista solo devuelve eventos donde algún
   * amigo mío aparece, así que ya viene acotada por definición. Pedir señal por
   * evento sería una consulta por tarjeta del catálogo.
   *
   * **Devuelve un Map vacío si falla, y no propaga el error.** La señal es un
   * adorno (011/AC-18): el catálogo tiene que pintarse igual.
   */
  async signals(): Promise<ReadonlyMap<string, EventSignal>> {
    const { data, error } = await supabase.from('v_my_event_signals').select('*');
    if (error) return new Map();
    return new Map((data as EventSignal[] | null)?.map((s) => [s.event_id, s]) ?? []);
  }

  /** Marcar interés es un insert; quitarlo, un delete. No hay estado «no». */
  async setInterest(eventId: string, on: boolean): Promise<string | null> {
    const { data: sesion } = await supabase.auth.getSession();
    const uid = sesion.session?.user.id;
    if (!uid) return 'Necesitas iniciar sesión.';

    return this.write(
      on
        ? supabase.from('event_interests').insert({ user_id: uid, event_id: eventId })
        : supabase.from('event_interests').delete().eq('event_id', eventId),
    );
  }

  /** ¿Marqué yo interés en este evento? Es mi propia fila, sin señal ajena. */
  async myInterest(eventId: string): Promise<boolean> {
    const { data } = await supabase
      .from('event_interests')
      .select('event_id')
      .eq('event_id', eventId)
      .maybeSingle();
    return data !== null;
  }

  private unwrap<T>(data: unknown, error: { message: string } | null): readonly T[] {
    this.loading.set(false);
    if (error) {
      this.error.set(error.message);
      return [];
    }
    return (data as T[] | null) ?? [];
  }

  /** Siempre resuelve con el mismo mensaje. Ver `RESULTADO_SOLICITUD`. */
  async request(email: string): Promise<string> {
    this.loading.set(true);
    await supabase.rpc('request_friendship', { target_email: email.trim() });
    this.loading.set(false);
    return SocialStore.RESULTADO_SOLICITUD;
  }

  async respond(edgeId: string, accept: boolean): Promise<string | null> {
    return this.write(supabase.rpc('respond_friendship', { edge_id: edgeId, accept }));
  }

  async block(userId: string): Promise<string | null> {
    return this.write(supabase.rpc('block_user', { target_id: userId }));
  }

  /** Desbloquear y dejar de ser amigos no necesitan RPC: la política basta. */
  async unblock(userId: string): Promise<string | null> {
    return this.write(supabase.from('blocks').delete().eq('blocked_id', userId));
  }

  async unfriend(edgeId: string): Promise<string | null> {
    return this.write(supabase.from('friend_edges').delete().eq('id', edgeId));
  }

  async setNinja(on: boolean): Promise<boolean> {
    const { data: sesion } = await supabase.auth.getSession();
    const uid = sesion.session?.user.id;
    if (!uid) return !on;

    // Se relee el valor devuelto en vez de asumir el que se mandó: si la
    // escritura falló, el interruptor tiene que volver, no quedarse mintiendo
    // sobre un estado de privacidad.
    const { data, error } = await supabase
      .from('profiles')
      .update({ ninja_mode: on })
      .eq('id', uid)
      .select('ninja_mode')
      .single();

    if (error) {
      this.error.set(error.message);
      return !on;
    }
    return (data as { ninja_mode: boolean }).ninja_mode;
  }

  async me(): Promise<{ full_name: string | null; email: string | null;
                        dni_last4: string | null; ninja_mode: boolean } | null> {
    const { data: sesion } = await supabase.auth.getSession();
    const uid = sesion.session?.user.id;
    if (!uid) return null;

    const { data, error } = await supabase
      .from('profiles')
      .select('full_name, email, dni_last4, ninja_mode')
      .eq('id', uid)
      .single();

    if (error) {
      this.error.set(error.message);
      return null;
    }
    return data as never;
  }

  private async write(p: PromiseLike<{ error: { message: string } | null }>): Promise<string | null> {
    this.loading.set(true);
    this.error.set(null);
    const { error } = await p;
    this.loading.set(false);
    if (error) this.error.set(error.message);
    return error?.message ?? null;
  }
}
