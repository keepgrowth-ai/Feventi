import { Component, ChangeDetectionStrategy, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthStore } from '../../core/auth.store';
import { SocialStore, type BlockedUser } from './social.store';

/**
 * «Perfil» — lo mínimo, y el interruptor que importa.
 *
 * El modo ninja es asimétrico a propósito (D-43): dejas de emitir señales y
 * sigues viendo las de tus amigos. Castigar la privacidad quitando producto es
 * la forma más segura de que nadie la active, y entonces la función existe en
 * el folleto y no en la realidad.
 *
 * Lo que el interruptor **no** hace se dice en pantalla. Un control de
 * privacidad que la gente cree más fuerte de lo que es hace más daño que uno
 * que no existe.
 */
@Component({
  selector: 'fv-perfil',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink],
  template: `
    <header class="mb-5">
      <h1 class="text-2xl font-black tracking-[-0.5px]">Perfil</h1>
    </header>

    @if (store.error(); as e) {
      <p role="alert" class="mb-4 rounded-[--radius-chip] bg-danger-bg px-3 py-2 text-[13px] text-danger-fg">
        {{ e }}
      </p>
    }

    <!-- ── Datos ─────────────────────────────────────────────────────────── -->
    <section class="mb-5 rounded-[--radius-card] border border-border bg-surface p-4">
      <dl class="space-y-2.5 text-[13.5px]">
        <div class="flex justify-between gap-4">
          <dt class="text-fg-muted">Nombre</dt>
          <dd class="truncate font-semibold">{{ yo()?.full_name ?? '—' }}</dd>
        </div>
        <div class="flex justify-between gap-4">
          <dt class="text-fg-muted">Correo</dt>
          <dd class="truncate font-mono text-[12.5px]">{{ yo()?.email ?? '—' }}</dd>
        </div>
        <div class="flex justify-between gap-4">
          <dt class="text-fg-muted">Documento</dt>
          <dd class="font-mono text-[12.5px]">
            @if (yo()?.dni_last4) {
              ••••{{ yo()?.dni_last4 }}
            } @else {
              sin registrar
            }
          </dd>
        </div>
      </dl>
    </section>

    <!-- ── Modo ninja ────────────────────────────────────────────────────── -->
    <section class="mb-5 rounded-[--radius-card] border border-border bg-surface p-4">
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <h2 class="text-[15px] font-bold">Modo ninja</h2>
          <p class="mt-1 text-[13px] text-fg-muted">
            Nadie ve a qué eventos vas. Tú sigues viendo a tus amigos.
          </p>
        </div>

        <button
          type="button"
          role="switch"
          [attr.aria-checked]="ninja()"
          aria-label="Modo ninja"
          (click)="alternarNinja()"
          [disabled]="store.loading()"
          class="relative mt-0.5 h-7 w-12 shrink-0 rounded-full transition-colors disabled:opacity-50"
          [class.bg-violet]="ninja()"
          [class.bg-border]="!ninja()"
        >
          <span
            class="absolute top-1 size-5 rounded-full bg-white transition-[left]"
            [class.left-6]="ninja()"
            [class.left-1]="!ninja()"
          ></span>
        </button>
      </div>

      <p class="mt-3 border-t border-border pt-3 text-[12px] leading-relaxed text-fg-muted">
        No es invisibilidad. Tu entrada se sigue validando en puerta con tu nombre, y
        soporte sigue pudiendo ayudarte con tus compras. Lo que se apaga es la señal
        social: dejas de aparecer en el «tus amigos van» de los demás.
      </p>
    </section>

    <!-- ── Bloqueados ────────────────────────────────────────────────────── -->
    <section class="rounded-[--radius-card] border border-border bg-surface p-4">
      <h2 class="text-[15px] font-bold">Personas bloqueadas</h2>
      <ul class="mt-3 space-y-2">
        @for (b of bloqueados(); track b.blocked_id) {
          <li class="flex items-center justify-between gap-3 text-[13px]">
            <span class="truncate font-mono text-[12px] text-fg-muted">{{ b.blocked_id }}</span>
            <button
              type="button"
              (click)="desbloquear(b.blocked_id)"
              class="shrink-0 text-[12.5px] font-semibold text-info-fg"
            >
              Desbloquear
            </button>
          </li>
        } @empty {
          <li class="text-[13px] text-fg-muted">No has bloqueado a nadie.</li>
        }
      </ul>
    </section>

    <!-- Lo que salió de la barra de navegación al reducirla a cuatro destinos.
         Aquí es donde alguien busca sus cosas administrativas. -->
    <section class="mt-5 overflow-hidden rounded-[--radius-card] border border-border bg-surface">
      <a
        routerLink="/grupos"
        class="flex items-center justify-between gap-3 border-b border-border px-4 py-3.5 text-[14px] font-medium"
      >
        Mis grupos de compra
        <span class="text-fg-subtle" aria-hidden="true">›</span>
      </a>
      <a
        routerLink="/soporte"
        class="flex items-center justify-between gap-3 border-b border-border px-4 py-3.5 text-[14px] font-medium"
      >
        Mis casos de soporte
        <span class="text-fg-subtle" aria-hidden="true">›</span>
      </a>
      <button
        type="button"
        (click)="auth.signOut()"
        class="flex w-full items-center justify-between gap-3 px-4 py-3.5 text-left text-[14px] font-medium text-danger-fg"
      >
        Cerrar sesión
      </button>
    </section>
  `,
})
export class PerfilPage {
  readonly store = inject(SocialStore);
  protected readonly auth = inject(AuthStore);

  readonly yo = signal<Awaited<ReturnType<SocialStore['me']>>>(null);
  readonly ninja = signal(false);
  readonly bloqueados = signal<readonly BlockedUser[]>([]);

  constructor() {
    void this.recargar();
  }

  private async recargar(): Promise<void> {
    const [p, b] = await Promise.all([this.store.me(), this.store.blocked()]);
    this.yo.set(p);
    this.ninja.set(p?.ninja_mode ?? false);
    this.bloqueados.set(b);
  }

  /**
   * Se pinta lo que devuelve el servidor, no lo que se pidió. Si la escritura
   * falló, el interruptor vuelve; quedarse mintiendo sobre un estado de
   * privacidad es peor que no tener el interruptor.
   */
  async alternarNinja(): Promise<void> {
    this.ninja.set(await this.store.setNinja(!this.ninja()));
  }

  async desbloquear(userId: string): Promise<void> {
    await this.store.unblock(userId);
    await this.recargar();
  }
}
