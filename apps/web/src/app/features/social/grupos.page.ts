import { Component, ChangeDetectionStrategy, inject, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { AuthStore } from '../../core/auth.store';
import { soles } from '../../shared/ui/money';
import { PublicEventStore, type PublicEvent } from '../publico/public-event.store';
import { GruposStore, type GroupMember, type PurchaseGroup } from './grupos.store';
import { SocialStore, type Friend } from './social.store';

interface Fila {
  readonly grupo: PurchaseGroup;
  readonly miembros: readonly GroupMember[];
  readonly evento: PublicEvent | null;
}

/**
 * «Comprar con amigos» — Art. 11.
 *
 * Hasta cuatro personas, una sola orden, todo o nada. Paga el creador y **cada
 * uno recibe su entrada en su propia wallet**: el ticket nace con su dueño, no
 * se transfiere después.
 *
 * Solo se puede añadir a un amigo. No es una restricción de producto sino la
 * única forma de que esta pantalla no sirva para meter a desconocidos en una
 * compra que no pidieron.
 */
@Component({
  selector: 'fv-grupos',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink],
  template: `
    <header class="mb-5">
      <h1 class="text-2xl font-black tracking-[-0.5px]">Comprar con amigos</h1>
      <p class="mt-1 text-[13px] text-fg-muted">
        Hasta cuatro personas, una sola compra. Pagas tú y cada uno recibe su entrada
        en su propia wallet.
      </p>
    </header>

    @if (store.error(); as e) {
      <p class="mb-4 rounded-[--radius-chip] bg-danger-bg px-3 py-2 text-[13px] text-danger-fg">
        {{ e }}
      </p>
    }

    @for (f of filas(); track f.grupo.id) {
      <section class="mb-4 rounded-[--radius-card] border border-border bg-surface p-4">
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div class="min-w-0">
            <h2 class="text-[16px] font-bold">{{ f.evento?.title ?? 'Evento' }}</h2>
            <p class="mt-0.5 text-[12.5px] text-fg-muted">
              {{ f.miembros.length }} de 4 · {{ etiqueta(f.grupo.status) }}
            </p>
          </div>
          @if (f.grupo.status === 'open' && !esCreador(f.grupo)) {
            <button
              type="button"
              (click)="salir(f.grupo.id)"
              class="shrink-0 text-[12.5px] font-medium text-fg-muted"
            >
              Salir del grupo
            </button>
          }
        </div>

        <!-- Los miembros -->
        <ul class="mt-3 flex flex-wrap gap-2">
          @for (m of f.miembros; track m.user_id) {
            <li
              class="flex items-center gap-2 rounded-[--radius-chip] bg-raised px-3 py-1.5 text-[12.5px]"
            >
              <span class="font-semibold">{{ nombre(m.user_id) }}</span>
              @if (m.slot === 1) {
                <span class="text-[10.5px] text-fg-muted">paga</span>
              }
            </li>
          }
        </ul>

        @if (f.grupo.status === 'open' && esCreador(f.grupo)) {
          <!-- Añadir amigos -->
          @if (f.miembros.length < 4) {
            <div class="mt-3 border-t border-border pt-3">
              <p class="mb-2 text-[12.5px] font-semibold">Añadir a un amigo</p>
              @if (disponibles(f).length) {
                <div class="flex flex-wrap gap-2">
                  @for (a of disponibles(f); track a.friend_id) {
                    <button
                      type="button"
                      (click)="anadir(f.grupo.id, a.friend_id)"
                      class="rounded-[--radius-chip] border border-border px-3 py-1.5 text-[12.5px] font-medium"
                    >
                      + {{ a.full_name ?? 'Sin nombre' }}
                    </button>
                  }
                </div>
              } @else {
                <p class="text-[12.5px] text-fg-muted">
                  No te quedan amigos por añadir.
                  <a routerLink="/amigos" class="font-semibold text-info-fg">Añade más</a>.
                </p>
              }
            </div>
          }

          <!-- Reservar -->
          <div class="mt-3 border-t border-border pt-3">
            <p class="mb-2 text-[12.5px] font-semibold">Reservar {{ f.miembros.length }} entradas</p>
            <div class="flex flex-wrap gap-2">
              @for (z of zonas(f); track z.tier_id) {
                <button
                  type="button"
                  (click)="reservar(f, z.tier_id)"
                  [disabled]="store.loading()"
                  class="rounded-[--radius-inner] bg-coral px-4 py-2 text-[13px] font-semibold text-white disabled:opacity-50"
                >
                  {{ z.zone_name }} · {{ money(z.total_cents * f.miembros.length) }}
                </button>
              }
            </div>
            <p class="mt-2 text-[11.5px] text-fg-subtle">
              Todo o nada: si el pago falla, se libera la reserva de las
              {{ f.miembros.length }} entradas.
            </p>
          </div>
        }

        @if (f.grupo.status === 'locked' && f.grupo.order_id) {
          <a
            [routerLink]="['/comprar', f.grupo.order_id]"
            class="mt-3 block rounded-[--radius-inner] bg-coral px-4 py-2.5 text-center text-[14px] font-semibold text-white"
          >
            Continuar al pago
          </a>
        }

        @if (f.grupo.status === 'completed') {
          <p class="mt-3 rounded-[--radius-chip] bg-success-bg px-3 py-2 text-[12.5px] text-success-fg">
            Pagado. Cada uno tiene su entrada en
            <a routerLink="/entradas" class="font-semibold underline">su wallet</a>.
          </p>
        }
      </section>
    } @empty {
      <div class="rounded-[--radius-card] border border-dashed border-border p-6 text-center">
        <p class="text-[13.5px] text-fg-muted">
          Todavía no tienes ningún grupo. Se crean desde la ficha de un evento, con el
          botón «Comprar con amigos».
        </p>
        <a
          routerLink="/eventos"
          class="mt-3 inline-block rounded-[--radius-chip] bg-coral px-4 py-2 text-[13px] font-semibold text-white"
        >
          Ver eventos
        </a>
      </div>
    }
  `,
})
export class GruposPage {
  protected readonly store = inject(GruposStore);
  private readonly social = inject(SocialStore);
  private readonly eventos = inject(PublicEventStore);
  private readonly auth = inject(AuthStore);
  private readonly router = inject(Router);

  protected readonly filas = signal<readonly Fila[]>([]);
  protected readonly amigos = signal<readonly Friend[]>([]);
  protected readonly money = soles;

  constructor() {
    queueMicrotask(() => void this.recargar());
  }

  private async recargar(): Promise<void> {
    const [grupos, amigos] = await Promise.all([this.store.mine(), this.social.friends()]);
    this.amigos.set(amigos);

    const filas = await Promise.all(
      grupos.map(async (grupo) => ({
        grupo,
        miembros: await this.store.members(grupo.id),
        evento: await this.eventos.getById(grupo.event_id),
      })),
    );
    this.filas.set(filas);
  }

  protected esCreador(g: PurchaseGroup): boolean {
    return g.creator_id === this.auth.userId();
  }

  /** El nombre sale de la lista de amigos; el mío, de la sesión. */
  protected nombre(userId: string): string {
    if (userId === this.auth.userId()) return 'Tú';
    return this.amigos().find((a) => a.friend_id === userId)?.full_name ?? 'Amigo';
  }

  /** Amigos que aún no están en este grupo. */
  protected disponibles(f: Fila): readonly Friend[] {
    const dentro = new Set(f.miembros.map((m) => m.user_id));
    return this.amigos().filter((a) => !dentro.has(a.friend_id));
  }

  /**
   * Una opción por zona con fase activa. Los cuatro van a la misma zona: un
   * grupo con cuatro zonas distintas no es un grupo, son cuatro compras.
   */
  protected zonas(f: Fila) {
    return (f.evento?.zones ?? []).flatMap((z) => {
      // Solo el tier sin segmento: los descuentos por segmento se acreditan
      // uno a uno y en un grupo no hay quién lo haga por los demás.
      const t = z.tiers.find((x) => x.phase_active && x.segment_id === null);
      if (!t) return [];
      return [{ tier_id: t.tier_id, zone_name: z.name, total_cents: t.total_cents }];
    });
  }

  protected async anadir(groupId: string, userId: string): Promise<void> {
    await this.store.add(groupId, userId);
    await this.recargar();
  }

  protected async salir(groupId: string): Promise<void> {
    await this.store.leave(groupId);
    await this.recargar();
  }

  protected async reservar(f: Fila, tierId: string): Promise<void> {
    const r = await this.store.reserveForGroup(
      f.grupo.id,
      f.grupo.event_id,
      tierId,
      f.miembros.length,
    );
    if (r.orderId) void this.router.navigate(['/comprar', r.orderId]);
    else await this.recargar();
  }

  protected etiqueta(s: PurchaseGroup['status']): string {
    return (
      {
        open: 'abierto',
        locked: 'reservado, esperando pago',
        completed: 'pagado',
        cancelled: 'cancelado',
      }[s] ?? s
    );
  }
}
