import { Component, ChangeDetectionStrategy, inject, signal } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { AuthStore } from '../core/auth.store';
import { SocialStore } from '../features/social/social.store';

/**
 * Modo Fan / Público (Art. 10): blanco y pastel, mobile-first, acción coral.
 * Se diseña a 390 px y se ensancha.
 */
@Component({
  selector: 'fv-fan-layout',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  template: `
    <div class="min-h-dvh bg-bg">
      <header class="sticky top-0 z-50 bg-navy text-white">
        <div class="mx-auto flex max-w-[1180px] items-center justify-between gap-4 px-4 py-3">
          <a routerLink="/" class="flex items-center gap-2.5 text-white">
            <span
              class="grid size-9 place-items-center rounded-[--radius-icon] bg-coral text-[18px] font-black"
              >F</span
            >
            <span class="text-[18px] font-extrabold tracking-[-0.5px]">FEVENTI</span>
          </a>

          <nav class="flex items-center gap-1">
            @if (auth.isSignedIn()) {
              <a
                routerLink="/entradas"
                routerLinkActive="bg-coral"
                class="rounded-[--radius-chip] px-3 py-1.5 text-[12.5px] font-semibold"
                >Mis entradas</a
              >
              <!-- 010: el punto coral es lo más parecido a una notificación que
                   se puede hacer sin centro de notificaciones (D-11), y no
                   cuesta una consulta nueva: sale de v_my_friend_requests. -->
              <a
                routerLink="/amigos"
                routerLinkActive="bg-coral"
                class="relative rounded-[--radius-chip] px-3 py-1.5 text-[12.5px] font-medium text-white/70"
                >Amigos
                @if (solicitudes() > 0) {
                  <span
                    class="absolute right-1.5 top-1 size-2 rounded-full bg-coral"
                    [attr.aria-label]="solicitudes() + ' solicitudes de amistad'"
                  ></span>
                }
              </a>
              <a
                routerLink="/grupos"
                routerLinkActive="bg-coral"
                class="rounded-[--radius-chip] px-3 py-1.5 text-[12.5px] font-medium text-white/70"
                >Grupos</a
              >
              <a
                routerLink="/perfil"
                routerLinkActive="bg-coral"
                class="rounded-[--radius-chip] px-3 py-1.5 text-[12.5px] font-medium text-white/70"
                >Perfil</a
              >

              <!-- 009: los casos se ABREN desde la entrada afectada (AC-21); esto
                   es solo para volver a leer las respuestas. -->
              <a
                routerLink="/soporte"
                routerLinkActive="bg-coral"
                class="rounded-[--radius-chip] px-3 py-1.5 text-[12.5px] font-medium text-white/70"
                >Mis casos</a
              >
              @if (auth.isOrganizer()) {
                <a
                  routerLink="/organizador"
                  class="rounded-[--radius-chip] px-3 py-1.5 text-[12.5px] font-medium text-white/70"
                  >Organizador</a
                >
              }
              @if (auth.isStaff()) {
                <a
                  routerLink="/puerta"
                  class="rounded-[--radius-chip] px-3 py-1.5 text-[12.5px] font-medium text-white/70"
                  >Puerta</a
                >
              }
              @if (auth.isAdmin()) {
                <a
                  routerLink="/admin"
                  class="rounded-[--radius-chip] px-3 py-1.5 text-[12.5px] font-medium text-white/70"
                  >Admin</a
                >
              }
              <button
                type="button"
                (click)="auth.signOut()"
                class="rounded-[--radius-chip] px-3 py-1.5 text-[12.5px] font-medium text-white/70"
              >
                Salir
              </button>
            } @else {
              <a
                routerLink="/entrar"
                class="rounded-[--radius-chip] bg-coral px-4 py-1.5 text-[12.5px] font-semibold"
                >Entrar</a
              >
            }
          </nav>
        </div>
      </header>

      <main class="mx-auto max-w-[1180px] px-4 pb-16 pt-6">
        <router-outlet />
      </main>
    </div>
  `,
})
export class FanLayout {
  protected readonly auth = inject(AuthStore);
  private readonly social = inject(SocialStore);

  protected readonly solicitudes = signal(0);

  constructor() {
    if (this.auth.isSignedIn()) {
      void this.social.requests().then((r) => this.solicitudes.set(r.length));
    }
  }
}
