import { Injectable, computed, signal } from '@angular/core';
import type { Session } from '@supabase/supabase-js';
import { supabase } from './supabase.client';
import type { Enums, Tables } from './db.types';

export type AppRole = Enums<'app_role'>;
export type Profile = Tables<'profiles'>;

/**
 * Sesión, perfil y roles del usuario actual.
 *
 * Los roles de aquí sirven SOLO para navegación: qué pestañas se pintan y a qué
 * ruta se redirige. La autorización real es la RLS (Art. 9.2) — un rol falseado
 * en el cliente abre un menú vacío, no un dato.
 */
@Injectable({ providedIn: 'root' })
export class AuthStore {
  private readonly _session = signal<Session | null>(null);
  private readonly _profile = signal<Profile | null>(null);
  private readonly _roles = signal<readonly AppRole[]>([]);
  private readonly _ready = signal(false);

  readonly session = this._session.asReadonly();
  readonly profile = this._profile.asReadonly();
  readonly roles = this._roles.asReadonly();
  /** false hasta que se resolvió la sesión inicial: los guards deben esperar. */
  readonly ready = this._ready.asReadonly();

  readonly userId = computed(() => this._session()?.user.id ?? null);
  readonly isSignedIn = computed(() => this._session() !== null);
  readonly isAdmin = computed(() => this._roles().includes('admin'));
  readonly isOrganizer = computed(() => this._roles().includes('organizer'));
  readonly isStaff = computed(() => this._roles().includes('staff'));

  /** El DNI se declara una vez y es requisito para pagar (004, AC-30). */
  readonly hasDni = computed(() => this._profile()?.dni_last4 != null);

  constructor() {
    void this.restore();
    supabase.auth.onAuthStateChange((_event, session) => {
      this._session.set(session);
      void this.loadIdentity(session);
    });
  }

  private async restore(): Promise<void> {
    const { data } = await supabase.auth.getSession();
    this._session.set(data.session);
    await this.loadIdentity(data.session);
    this._ready.set(true);
  }

  private async loadIdentity(session: Session | null): Promise<void> {
    if (!session) {
      this._profile.set(null);
      this._roles.set([]);
      return;
    }

    // Dos consultas en paralelo: el perfil y los roles no dependen entre sí.
    const [profile, roles] = await Promise.all([
      supabase.from('profiles').select('*').eq('id', session.user.id).maybeSingle(),
      supabase.from('user_roles').select('role').eq('user_id', session.user.id),
    ]);

    this._profile.set(profile.data ?? null);
    this._roles.set((roles.data ?? []).map((r) => r.role));
  }

  async signInWithPassword(email: string, password: string) {
    return supabase.auth.signInWithPassword({ email, password });
  }

  async signInWithMagicLink(email: string) {
    return supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: window.location.origin },
    });
  }

  /**
   * El perfil y el rol `fan` los crea el trigger `on_auth_user_created`
   * (001, AC-01/AC-02). El cliente no inserta nada.
   */
  async signUp(email: string, password: string, fullName: string) {
    return supabase.auth.signUp({
      email,
      password,
      options: { data: { full_name: fullName } },
    });
  }

  async signOut(): Promise<void> {
    await supabase.auth.signOut();
  }

  /** Solo los campos que el cliente tiene permitido escribir (001, AC-05). */
  async updateProfile(patch: Pick<Partial<Profile>, 'full_name' | 'phone' | 'avatar_url' | 'ninja_mode'>) {
    const id = this.userId();
    if (!id) throw new Error('no autenticado');

    const { data, error } = await supabase
      .from('profiles')
      .update(patch)
      .eq('id', id)
      .select('*')
      .single();

    if (!error && data) this._profile.set(data);
    return { data, error };
  }

  /**
   * El DNI se manda en claro por HTTPS y el servidor lo hashea con un pepper que
   * el cliente no ve (Art. 7.1). Nunca se calcula el hash aquí: si el cliente
   * pudiera elegirlo, copiaría el de otra persona.
   */
  async setOwnDni(dni: string) {
    const { error } = await supabase.rpc('set_own_dni', { p_dni: dni });
    if (!error) await this.loadIdentity(this._session());
    return { error };
  }
}
