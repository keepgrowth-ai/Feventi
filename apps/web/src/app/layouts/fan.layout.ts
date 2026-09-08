import { Component, ChangeDetectionStrategy, inject, signal } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { AuthStore } from '../core/auth.store';
import { SocialStore } from '../features/social/social.store';

/**
 * Modo Fan / Público (Art. 10): blanco y pastel, mobile-first, acción coral.
 * Se diseña a 390 px y se ensancha.
 *
 * ── POR QUÉ HAY CUATRO DESTINOS Y NO NUEVE ─────────────────────────────────
 *
 * Al montar la capa social esta barra llegó a diez elementos —entradas, amigos,
 * grupos, perfil, casos, organizador, puerta, admin, salir— y a 390 px eso no
 * es una navegación, es una lista. Se reorganizó la información, no el CSS:
 *
 *   · **Grupos** pertenece al flujo de compra. Se llega desde la ficha del
 *     evento («Comprar con amigos») y desde Amigos. No es un destino, es un
 *     paso.
 *   · **Mis casos** y **Salir** viven en Perfil, que es donde alguien busca sus
 *     cosas administrativas.
 *   · **Organizador / Puerta / Admin** no son destinos de fan: son CAMBIOS DE
 *     MUNDO (Art. 10). Van agrupados y aparte, para que no compitan con lo que
 *     hace el 95 % del tráfico.
 *
 * Quedan cuatro: descubrir, lo que tengo, mi gente, yo. Es el producto entero.
 *
 * En móvil van abajo, al alcance del pulgar, que es donde las pone cualquier
 * app que se use andando por la calle. En pantalla ancha vuelven arriba.
 */
@Component({
  selector: 'fv-fan-layout',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  template: `
    <div class="min-h-dvh bg-bg">
      <header class="sticky top-0 z-40 bg-navy text-white">
        <div class="mx-auto flex max-w-[1180px] items-center justify-between gap-4 px-4 py-3">
          <a routerLink="/" class="flex items-center gap-2.5 text-white">
            <span
              class="grid size-9 place-items-center rounded-[--radius-icon] bg-coral text-[18px] font-black"
              >F</span
            >
            <span class="text-[18px] font-extrabold tracking-[-0.5px]">FEVENTI</span>
          </a>

          @if (auth.isSignedIn()) {
            <!-- Los cuatro destinos, solo en pantalla ancha. En móvil van abajo. -->
            <nav class="hidden items-center gap-1 sm:flex">
              @for (d of destinos; track d.ruta) {
                <a
                  [routerLink]="d.ruta"
                  routerLinkActive="bg-white/15"
                  class="relative rounded-[--radius-chip] px-3 py-1.5 text-[12.5px] font-medium"
                >
                  {{ d.texto }}
                  @if (d.ruta === '/amigos' && solicitudes() > 0) {
                    <span
                      class="absolute right-1 top-0.5 size-2 rounded-full bg-coral"
                      [attr.aria-label]="solicitudes() + ' solicitudes de amistad'"
                    ></span>
                  }
                </a>
              }
            </nav>

            <!-- Cambiar de mundo. Separado por una línea porque no es lo mismo
                 ir a «mis entradas» que dejar de ser fan y pasar a operar. -->
            <div class="flex items-center gap-1">
              @if (auth.isOrganizer() || auth.isStaff() || auth.isAdmin()) {
                <div class="mr-1 hidden items-center gap-1 border-r border-white/20 pr-2 sm:flex">
                  @if (auth.isOrganizer()) {
                    <a routerLink="/organizador" class="rounded-[--radius-chip] px-2.5 py-1.5 text-[12.5px] text-white/60">Organizador</a>
                  }
                  @if (auth.isStaff()) {
                    <a routerLink="/puerta" class="rounded-[--radius-chip] px-2.5 py-1.5 text-[12.5px] text-white/60">Puerta</a>
                  }
                  @if (auth.isAdmin()) {
                    <a routerLink="/admin" class="rounded-[--radius-chip] px-2.5 py-1.5 text-[12.5px] text-white/60">Admin</a>
                  }
                </div>
              }
              <a
                routerLink="/perfil"
                class="grid size-9 place-items-center rounded-full bg-white/15 text-[13px] font-bold sm:hidden"
                aria-label="Perfil"
                >{{ inicial() }}</a
              >
            </div>
          } @else {
            <a
              routerLink="/entrar"
              class="rounded-[--radius-chip] bg-coral px-4 py-1.5 text-[12.5px] font-semibold"
              >Entrar</a
            >
          }
        </div>
      </header>

      <!-- El padding de abajo deja sitio a la barra móvil: sin él, la última
           tarjeta del catálogo se queda debajo y parece que la lista se cortó. -->
      <main class="mx-auto max-w-[1180px] px-4 pt-6 pb-24 sm:pb-16">
        <router-outlet />
      </main>

      @if (auth.isSignedIn()) {
        <nav
          class="fixed inset-x-0 bottom-0 z-40 border-t border-border bg-surface/95 backdrop-blur sm:hidden"
          style="padding-bottom:env(safe-area-inset-bottom)"
        >
          <div class="mx-auto flex max-w-[520px]">
            @for (d of destinos; track d.ruta) {
              <a
                [routerLink]="d.ruta"
                routerLinkActive="text-coral-fg"
                #activo="routerLinkActive"
                class="relative flex flex-1 flex-col items-center gap-0.5 py-2.5 text-fg-muted"
              >
                <span class="relative">
                  <svg
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.75"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    class="size-6"
                    aria-hidden="true"
                  >
                    <path [attr.d]="d.icono" />
                  </svg>
                  @if (d.ruta === '/amigos' && solicitudes() > 0) {
                    <span
                      class="absolute -right-1 -top-0.5 size-2.5 rounded-full bg-coral ring-2 ring-surface"
                      [attr.aria-label]="solicitudes() + ' solicitudes de amistad'"
                    ></span>
                  }
                </span>
                <span class="text-[10.5px]" [class.font-bold]="activo.isActive">{{ d.texto }}</span>
              </a>
            }
          </div>
        </nav>
      }
    </div>
  `,
})
export class FanLayout {
  protected readonly auth = inject(AuthStore);
  private readonly social = inject(SocialStore);

  protected readonly solicitudes = signal(0);

  /**
   * Descubrir, lo que tengo, mi gente, yo.
   *
   * Los iconos son trazos sueltos y no una librería: son cuatro, pesan menos
   * que el `import`, y así el grosor y los remates son los mismos que los del
   * resto del producto en vez de los que traiga el paquete de turno.
   */
  protected readonly destinos = [
    {
      ruta: '/eventos',
      texto: 'Eventos',
      icono: 'M4 7h16M4 7a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2M4 7v10a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7M9 3v4M15 3v4',
    },
    {
      ruta: '/entradas',
      texto: 'Entradas',
      icono: 'M4 9a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2 2 2 0 0 0 0 4 2 2 0 0 1-2 2H6a2 2 0 0 1-2-2 2 2 0 0 0 0-4ZM14 7v10',
    },
    {
      ruta: '/amigos',
      texto: 'Amigos',
      icono: 'M16 19v-1a4 4 0 0 0-4-4H7a4 4 0 0 0-4 4v1M12 7a3 3 0 1 1-6 0 3 3 0 0 1 6 0ZM21 19v-1a4 4 0 0 0-3-3.87M16 4.13a4 4 0 0 1 0 7.75',
    },
    {
      ruta: '/perfil',
      texto: 'Perfil',
      icono: 'M19 20v-1a5 5 0 0 0-5-5h-4a5 5 0 0 0-5 5v1M15 7a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z',
    },
  ] as const;

  protected readonly inicial = signal('·');

  constructor() {
    if (this.auth.isSignedIn()) {
      void this.social.requests().then((r) => this.solicitudes.set(r.length));
      void this.social.me().then((p) => {
        const n = p?.full_name?.trim();
        if (n) this.inicial.set(n.charAt(0).toUpperCase());
      });
    }
  }
}
