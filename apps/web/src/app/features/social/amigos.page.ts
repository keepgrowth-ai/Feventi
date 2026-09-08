import { Component, ChangeDetectionStrategy, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { Avatar } from '../../shared/ui/avatar';
import { SocialStore, type Friend, type FriendRequest } from './social.store';

/**
 * «Amigos» — el grafo social del fan.
 *
 * Tres bloques: solicitudes recibidas arriba porque es lo accionable, la lista,
 * y el formulario para añadir.
 *
 * El resultado de pedir amistad es **siempre el mismo texto**, en el éxito y en
 * los cuatro fallos. No es un mensaje perezoso: distinguirlos convertiría el
 * formulario en un oráculo de «¿está esta persona registrada en Feventi?», que
 * es una fuga de datos personales con formulario bonito.
 *
 * Aquí no aparece el modo ninja de nadie. La lista no lo trae y no puede
 * traerlo: el filtro vive en `private.can_see_activity_of`.
 */
@Component({
  selector: 'fv-amigos',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule, RouterLink, Avatar],
  template: `
    <header class="mb-5">
      <h1 class="text-2xl font-black tracking-[-0.5px]">Amigos</h1>
      <p class="mt-1 text-[13px] text-fg-muted">
        Cuando tengas amigos, verás a cuáles de tus eventos van — y ellos a los tuyos.
      </p>
    </header>

    @if (store.error(); as e) {
      <p
        role="alert"
        class="mb-4 rounded-[--radius-chip] bg-danger-bg px-3 py-2 text-[13px] text-danger-fg"
      >
        {{ e }}
      </p>
    }

    <!-- ── Solicitudes · solo si hay ─────────────────────────────────────── -->
    @if (solicitudes().length) {
      <section class="mb-6">
        <h2 class="mb-2 text-[12px] font-bold text-fg-muted">
          Solicitudes recibidas
        </h2>
        <ul class="space-y-2">
          @for (s of solicitudes(); track s.edge_id) {
            <li
              class="flex flex-wrap items-center justify-between gap-3 rounded-[--radius-card] border border-coral/40 bg-surface p-3"
            >
              <div class="flex min-w-0 items-center gap-3">
                <fv-avatar class="size-10 text-[14px]" [nombre]="s.full_name" [url]="s.avatar_url" />
                <p class="truncate text-[14px] font-bold">{{ s.full_name ?? 'Alguien' }}</p>
              </div>
              <div class="flex shrink-0 gap-2">
                <button
                  type="button"
                  (click)="responder(s.edge_id, true)"
                  class="min-h-9 rounded-[--radius-chip] bg-coral px-4 text-[13px] font-semibold text-white"
                >
                  Aceptar
                </button>
                <button
                  type="button"
                  (click)="responder(s.edge_id, false)"
                  class="min-h-9 rounded-[--radius-chip] border border-border px-4 text-[13px] font-medium"
                >
                  Rechazar
                </button>
              </div>
            </li>
          }
        </ul>
      </section>
    }

    <!-- ── Mis amigos ────────────────────────────────────────────────────── -->
    <section class="mb-6">
      <h2 class="mb-2 text-[12px] font-bold text-fg-muted">
        Mis amigos
      </h2>

      @if (cargando()) {
        <p class="fv-solo-lector" role="status" aria-live="polite">Cargando tus amigos…</p>
        <ul class="space-y-2" aria-hidden="true">
          @for (n of [1, 2, 3]; track n) {
            <li class="flex items-center gap-3 rounded-[--radius-card] border border-border bg-surface p-3">
              <div class="fv-bone size-10 rounded-full"></div>
              <div class="fv-bone h-4 w-32"></div>
            </li>
          }
        </ul>
      }

      <ul class="space-y-2" [attr.aria-busy]="cargando()">
        @for (a of amigos(); track a.edge_id) {
          <li
            class="flex flex-wrap items-center justify-between gap-3 rounded-[--radius-card] border border-border bg-surface p-3"
          >
            <div class="flex min-w-0 items-center gap-3">
              <fv-avatar class="size-10 text-[14px]" [nombre]="a.full_name" [url]="a.avatar_url" />
              <p class="truncate text-[14px] font-bold">{{ a.full_name ?? 'Sin nombre' }}</p>
            </div>
            <div class="flex shrink-0 gap-3 text-[12.5px]">
              <button type="button" (click)="quitar(a.edge_id)" class="font-medium text-fg-muted">
                Quitar
              </button>
              <button
                type="button"
                (click)="bloquear(a.friend_id, a.edge_id)"
                class="font-semibold text-danger-fg"
              >
                Bloquear
              </button>
            </div>
          </li>
        } @empty {
          @if (!cargando()) {
            <li class="rounded-[--radius-card] border border-dashed border-border p-5 text-center">
              <p class="text-[13.5px] text-fg-muted">
                Todavía no tienes amigos en Feventi. Cuando los tengas, verás a cuáles de
                tus eventos van.
              </p>
            </li>
          }
        }
      </ul>
    </section>

    <!-- ── Añadir ────────────────────────────────────────────────────────── -->
    <section class="rounded-[--radius-card] border border-border bg-surface p-4">
      <h2 class="text-[14px] font-bold">Añadir un amigo</h2>
      <p class="mt-0.5 text-[12.5px] text-fg-muted">
        Con su correo exacto. No buscamos por nombre ni importamos tu agenda.
      </p>

      <form (ngSubmit)="pedir()" class="mt-3 flex flex-wrap gap-2">
        <input
          type="email"
          name="correo"
          [(ngModel)]="correo"
          required
          autocomplete="off"
          placeholder="correo@ejemplo.com"
          class="min-h-11 min-w-0 flex-1 rounded-[--radius-inner] border border-border px-3 text-[14px]"
        />
        <button
          type="submit"
          [disabled]="!correo || store.loading()"
          class="min-h-11 rounded-[--radius-inner] bg-coral px-5 text-[14px] font-semibold text-white disabled:opacity-50"
        >
          Enviar
        </button>
      </form>

      @if (resultado(); as r) {
        <p
          role="status"
          aria-live="polite"
          class="mt-2.5 rounded-[--radius-chip] bg-success-bg px-3 py-2 text-[12.5px] text-success-fg"
        >
          {{ r }}
        </p>
      }
    </section>

    @if (amigos().length) {
      <p class="mt-4 text-[13px] text-fg-muted">
        Con ellos puedes
        <a routerLink="/grupos" class="font-semibold text-info-fg">comprar en grupo</a>:
        una sola compra, y la entrada de cada uno en su propia wallet.
      </p>
    }

    <p class="mt-4 text-[12.5px] text-fg-muted">
      ¿Prefieres que nadie vea a qué eventos vas?
      <a routerLink="/perfil" class="font-semibold text-info-fg">Activa el modo ninja</a>.
    </p>
  `,
})
export class AmigosPage {
  readonly store = inject(SocialStore);

  readonly amigos = signal<readonly Friend[]>([]);
  readonly solicitudes = signal<readonly FriendRequest[]>([]);
  readonly resultado = signal<string | null>(null);
  /**
   * Propio y no `store.loading()`: el store lo comparte con las otras pantallas
   * sociales, así que pulsar «Enviar» lo pone a true y la lista de amigos se
   * convertiría en esqueleto por una operación que no la afecta.
   */
  readonly cargando = signal(true);
  correo = '';

  constructor() {
    void this.recargar();
  }

  private async recargar(): Promise<void> {
    const [a, s] = await Promise.all([this.store.friends(), this.store.requests()]);
    this.amigos.set(a);
    this.solicitudes.set(s);
    this.cargando.set(false);
  }

  async pedir(): Promise<void> {
    this.resultado.set(await this.store.request(this.correo));
    this.correo = '';
    await this.recargar();
  }

  async responder(edgeId: string, aceptar: boolean): Promise<void> {
    await this.store.respond(edgeId, aceptar);
    await this.recargar();
  }

  async quitar(edgeId: string): Promise<void> {
    await this.store.unfriend(edgeId);
    await this.recargar();
  }

  /**
   * Bloquear NO borra la amistad en la base de datos: son dos hechos distintos
   * y el bloqueo tiene que sobrevivir a que la amistad se deshaga. Desde la
   * pantalla sí se hacen las dos cosas, porque nadie espera seguir viendo en su
   * lista a alguien que acaba de bloquear.
   */
  async bloquear(userId: string, edgeId: string): Promise<void> {
    await this.store.block(userId);
    await this.store.unfriend(edgeId);
    await this.recargar();
  }

  inicial(nombre: string | null): string {
    return (nombre?.trim()?.[0] ?? '?').toUpperCase();
  }
}
