import { Component, ChangeDetectionStrategy, computed, inject, input, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { AuthStore } from '../../core/auth.store';
import { Chip } from '../../shared/ui/chip';
import { EventVisual } from '../../shared/ui/event-visual';
import { SocialSignal } from '../../shared/ui/social-signal';
import { GruposStore } from '../social/grupos.store';
import { SocialStore, type EventSignal } from '../social/social.store';
import { soles } from '../../shared/ui/money';
import { CheckoutStore, type ReserveItem } from '../checkout/checkout.store';
import { Seleccion } from './seleccion';
import {
  PublicEventStore,
  stockLabel,
  type PublicEvent,
  type PublicTier,
  type PublicZone,
} from './public-event.store';

/**
 * Detalle público del evento. La pantalla más importante para conversión, y la
 * primera del proyecto que se ve sin sesión.
 *
 * Del mockup y del spec, lo que no es negociable:
 *  - el total CON cargo en grande y el desglose debajo, en la misma card y desde
 *    el primer momento (Art. 5). El «desde» leído como precio final es el riesgo
 *    número uno de esta pantalla;
 *  - los segmentos anidados DENTRO de la card de su zona, nunca como hermanos;
 *  - la línea de fases completa: la activa con lo que falta, las futuras con su
 *    fecha, las pasadas apagadas — no se ocultan;
 *  - el bloque «Ticket protegido» explicando el Art. 2 antes de comprar.
 */
@Component({
  selector: 'fv-evento-publico',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Chip, Seleccion, SocialSignal, EventVisual],
  template: `
    @if (ev(); as e) {
      <!-- Key visual -->
      <section
        class="relative overflow-hidden rounded-[--radius-card] bg-navy p-7 text-white sm:p-8"
      >
        @if (e.hero_image_url) {
          <img [src]="e.hero_image_url" [alt]="" class="absolute inset-0 size-full object-cover" />
        } @else {
          <fv-event-visual [seed]="e.id" [category]="e.category" />
        }
        <div class="fv-hero-texture absolute inset-0"></div>
        <!-- La imagen no puede comerse el texto: el título va encima de todo y
             tiene que leerse sobre cualquier foto que suba el organizador. -->
        <div class="absolute inset-0 bg-gradient-to-t from-navy/85 via-navy/45 to-navy/20"></div>
        <div class="relative">
          @if (activePhase(); as ph) {
            <span
              class="mb-3 inline-block rounded-[--radius-pill] bg-coral/20 px-2.5 py-1 text-[11px] font-semibold text-coral-200"
            >
              {{ e.category }} · {{ e.venue.city }} · {{ ph.name }}
            </span>
          }
          <h1 class="text-[clamp(1.75rem,6vw,2rem)] font-black leading-[1.05] tracking-[-1px]">
            {{ e.title }}
          </h1>
          <p class="mt-2 text-[14px] text-white/70">
            {{ e.venue.name }}@if (e.venue.city) { · {{ e.venue.city }} }@if (e.starts_at) { ·
            {{ longDate(e.starts_at) }} }
          </p>
          <div class="mt-3.5 flex flex-wrap gap-2">
            @if (e.sale_open) {
              <span
                class="rounded-[--radius-pill] bg-turquoise px-2.5 py-1 text-[11px] font-bold text-on-turquoise"
                >A la venta</span
              >
            } @else {
              <span
                class="rounded-[--radius-pill] bg-white/15 px-2.5 py-1 text-[11px] font-semibold"
                >{{ saleClosedLabel() }}</span
              >
            }
            <span
              class="rounded-[--radius-pill] bg-white/10 px-2.5 py-1 text-[11px] font-semibold text-white/80"
              >Límite {{ e.max_per_user }} por usuario</span
            >
            @if (e.resale_enabled) {
              <span
                class="rounded-[--radius-pill] bg-violet/20 px-2.5 py-1 text-[11px] font-semibold text-violet-200"
                >Reventa oficial</span
              >
            }
          </div>
        </div>
      </section>

      <!-- ── 011 · la señal social ────────────────────────────────────────
           Va justo debajo del key visual y ENCIMA del precio: el acta §6 dice
           que la señal debe llegar antes de la decisión de compra, no como
           confirmación después.

           Y va SOLA, en su propia caja. Antes compartía fila con los dos
           botones y competía con ellos por la atención; el diferencial del
           producto no puede leerse como el pie de foto de un botón. Los
           botones bajan una línea, que es su orden real: primero te enteras de
           que tus amigos van, después decides qué haces con eso.

           Si no hay señal, la caja no existe. -->
      @if (auth.isSignedIn()) {
        @if (senal(); as sn) {
          <section
            class="mt-4 rounded-[--radius-card] border border-info-border/40 bg-info-bg px-4 py-3"
          >
            <fv-social-signal
              [going]="sn.friends_going"
              [interested]="sn.friends_interested"
              [goingNames]="sn.going_names"
              [interestedNames]="sn.interested_names"
              [goingAvatars]="sn.going_avatars"
              [interestedAvatars]="sn.interested_avatars"
              [conNota]="true"
            />
          </section>
        }

        <div class="mt-3 flex flex-wrap gap-2">
          <!-- Solo con amigos: sin grafo no hay grupo. -->
          <button
            type="button"
            (click)="crearGrupo()"
            class="min-h-11 rounded-[--radius-inner] border border-info-border px-4 text-[13.5px] font-semibold text-info-fg"
          >
            Comprar con amigos
          </button>

          <!-- El botón cambia de estado al pulsarlo, y la transición muestra
               ese cambio. Es movimiento que responde a una acción: el único
               que este producto se permite fuera de los dos momentos grandes. -->
          <button
            type="button"
            (click)="alternarInteres()"
            [attr.aria-pressed]="meInteresa()"
            class="min-h-11 rounded-[--radius-inner] border px-4 text-[13.5px] font-semibold transition-colors duration-[--dur-fast]"
            [class]="
              meInteresa()
                ? 'border-info-border bg-info-bg-alt text-info-fg'
                : 'border-border text-fg-soft'
            "
          >
            {{ meInteresa() ? 'Te interesa' : 'Me interesa' }}
          </button>
        </div>
      }

      <div class="mt-6 grid gap-6 lg:grid-cols-[1fr_320px]">
        <div class="space-y-6">
          @if (e.description) {
            <section>
              <h2 class="mb-2 text-[18px] font-extrabold tracking-[-0.5px]">Sobre el evento</h2>
              <p class="whitespace-pre-line text-[14px] leading-relaxed text-fg-soft">
                {{ e.description }}
              </p>
            </section>
          }

          <!-- Zonas y precios -->
          <section>
            <h2 class="mb-1 text-[18px] font-extrabold tracking-[-0.5px]">Zonas y precios</h2>
            <p class="mb-3 text-[12.5px] text-fg-muted">
              @if (e.service_charge_payer === 'fan') {
                Precio calculado por fase activa. El cargo de servicio se muestra desde el primer
                paso.
              } @else {
                Precio calculado por fase activa. El cargo de servicio lo absorbe el organizador.
              }
            </p>

            <div class="space-y-3">
              @for (z of zones(); track z.id) {
                <article class="rounded-[--radius-card] border border-border bg-surface p-4">
                  <div class="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <h3 class="text-[15px] font-bold">{{ z.name }}</h3>
                      @if (z.notes) {
                        <p class="text-[12px] text-fg-muted">{{ z.notes }}</p>
                      }
                    </div>
                    @if (mainTier(z); as t) {
                      <div class="text-right">
                        <!-- El TOTAL en grande. El desglose debajo. Art. 5. -->
                        <div class="text-[20px] font-black tabular-nums leading-none">
                          {{ money(t.total_cents) }}
                        </div>
                        <div class="mt-1 text-[11.5px] text-fg-muted">
                          Base {{ money(t.base_cents) }}
                          @if (t.service_charge_cents > 0) {
                            + cargo {{ money(t.service_charge_cents) }}
                          } @else {
                            · cargo absorbido
                          }
                        </div>
                      </div>
                    }
                  </div>

                  @if (mainTier(z); as t) {
                    <div class="mt-3 flex flex-wrap items-center gap-2">
                      <fv-chip [tone]="stock(t).tone">{{ stock(t).text }}</fv-chip>
                      @if (z.numbered) {
                        <fv-chip tone="neutral">Numerada por fila y asiento</fv-chip>
                      }
                    </div>
                  }

                  <!-- Segmentos: ANIDADOS dentro de la zona, nunca hermanos -->
                  @if (segments(z).length) {
                    <div class="mt-3 rounded-[--radius-inner] bg-muted p-3">
                      <h4 class="mb-2 text-[12px] font-bold text-fg-soft">
                        {{ z.name }} — segmentos internos de precio
                      </h4>
                      <ul class="space-y-1.5">
                        @for (t of segments(z); track t.tier_id) {
                          <li class="flex flex-wrap items-baseline justify-between gap-2 text-[13px]">
                            <span class="font-medium">{{ t.segment_label }}</span>
                            <span class="flex items-baseline gap-2">
                              <span class="font-bold tabular-nums">{{ money(t.total_cents) }}</span>
                              <fv-chip [tone]="stock(t).tone">{{ stock(t).text }}</fv-chip>
                            </span>
                          </li>
                        }
                      </ul>
                    </div>
                  }

                  <div class="mt-3.5">
                    @if (canBuy(z)) {
                      @if (openZone() !== z.id) {
                        <button
                          type="button"
                          (click)="pick(z)"
                          class="w-full rounded-[--radius-chip] bg-coral px-4 py-2.5 text-[14px] font-bold text-white sm:w-auto"
                        >
                          {{ z.numbered ? 'Elegir asiento' : 'Comprar' }}
                        </button>
                      }
                      @if (openZone() === z.id && buyTier(z); as t) {
                        <fv-seleccion
                          [zone]="z"
                          [tier]="t"
                          [maxPerUser]="e.max_per_user"
                          [open]="true"
                          (cancel)="openZone.set(null)"
                          (reserved)="reserve(e.id, $event)"
                        />
                      }
                    } @else {
                      <button
                        type="button"
                        disabled
                        class="w-full cursor-not-allowed rounded-[--radius-chip] bg-muted px-4 py-2.5 text-[14px] font-bold text-fg-subtle sm:w-auto"
                      >
                        {{ mainTier(z) && stock(mainTier(z)!).text === 'Agotado' ? 'Agotado' : 'No disponible' }}
                      </button>
                    }
                  </div>
                </article>
              } @empty {
                <p
                  class="rounded-[--radius-card] border border-border bg-surface p-5 text-[13px] text-fg-muted"
                >
                  Este evento todavía no tiene entradas cargadas.
                </p>
              }
            </div>
          </section>

          <!-- Línea de fases: completa, incluidas las futuras y pasadas -->
          @if (e.phases.length) {
            <section>
              <h2 class="mb-2 text-[18px] font-extrabold tracking-[-0.5px]">Línea de fases</h2>
              <ul class="space-y-2">
                @for (p of e.phases; track p.id) {
                  <li
                    class="flex flex-wrap items-center justify-between gap-2 rounded-[--radius-inner] border p-3"
                    [class]="
                      p.state === 'active'
                        ? 'border-coral bg-danger-bg'
                        : p.state === 'past'
                          ? 'border-border bg-muted opacity-60'
                          : 'border-border bg-surface'
                    "
                  >
                    <span class="text-[13.5px] font-semibold">{{ p.name }}</span>
                    <span class="text-[12.5px] text-fg-muted">{{ phaseHint(p) }}</span>
                  </li>
                }
              </ul>
            </section>
          }
        </div>

        <!-- Ticket protegido: el Art. 2, antes de comprar -->
        <aside class="space-y-4">
          <section class="rounded-[--radius-card] border border-success-border bg-success-bg p-4">
            <h2 class="text-[15px] font-bold text-success-fg">Ticket protegido</h2>
            <ul class="mt-2 space-y-2 text-[12.5px] text-fg-soft">
              <li>
                QR dinámico en tu wallet autenticada — no se descarga ni se comparte por imagen.
              </li>
              <li>El QR estará disponible {{ e.qr_lead_days }} días antes del evento.</li>
              @if (e.resale_enabled) {
                <li>
                  Reventa oficial dentro de Feventi al precio original, máximo
                  {{ e.max_resales }} veces.
                </li>
              }
              <li>Titularidad y nominación controladas por el sistema.</li>
              @if (e.nomination_mode === 'strict') {
                <li class="font-semibold">
                  Cada entrada debe estar nominada: sin nominar no se permite el ingreso.
                </li>
              } @else {
                <li>
                  Una entrada sin nominar entra a revisión manual en puerta.
                </li>
              }
            </ul>
          </section>

          <section class="rounded-[--radius-card] border border-border bg-surface p-4">
            <h2 class="mb-2 text-[15px] font-bold">Detalles</h2>
            <dl class="space-y-1.5 text-[13px]">
              @if (e.starts_at) {
                <div class="flex justify-between gap-3">
                  <dt class="text-fg-muted">Inicio</dt>
                  <dd class="text-right font-medium">{{ longDate(e.starts_at) }}</dd>
                </div>
              }
              @if (e.doors_at) {
                <div class="flex justify-between gap-3">
                  <dt class="text-fg-muted">Puertas</dt>
                  <dd class="text-right font-medium">{{ time(e.doors_at) }}</dd>
                </div>
              }
              <div class="flex justify-between gap-3">
                <dt class="text-fg-muted">Lugar</dt>
                <dd class="text-right font-medium">{{ e.venue.name }}</dd>
              </div>
              @if (e.venue.address) {
                <div class="flex justify-between gap-3">
                  <dt class="text-fg-muted">Dirección</dt>
                  <dd class="text-right font-medium">{{ e.venue.address }}</dd>
                </div>
              }
              @if (e.organizer_name) {
                <div class="flex justify-between gap-3">
                  <dt class="text-fg-muted">Organiza</dt>
                  <dd class="text-right font-medium">{{ e.organizer_name }}</dd>
                </div>
              }
            </dl>
          </section>
        </aside>
      </div>
    } @else if (!store.loading()) {
      <div class="mx-auto max-w-md py-16 text-center">
        <h1 class="text-xl font-black">Este evento no está disponible</h1>
        <p class="mt-2 text-[13.5px] text-fg-muted">
          Puede que el enlace esté mal, que el evento no esté publicado o que la venta se haya
          cerrado.
        </p>
        <a routerLink="/" class="mt-4 inline-block text-[13px] font-semibold text-coral-fg">
          Ver otros eventos
        </a>
      </div>
    }
  `,
})
export class EventoPublicoPage {
  readonly slug = input.required<string>();

  protected readonly store = inject(PublicEventStore);
  private readonly checkout = inject(CheckoutStore);
  protected readonly auth = inject(AuthStore);
  private readonly social = inject(SocialStore);
  private readonly grupos = inject(GruposStore);
  private readonly router = inject(Router);

  protected readonly ev = signal<PublicEvent | null>(null);
  protected readonly senal = signal<EventSignal | null>(null);
  protected readonly meInteresa = signal(false);
  protected readonly openZone = signal<string | null>(null);
  protected readonly money = soles;

  protected readonly zones = computed(() => this.ev()?.zones ?? []);

  protected readonly activePhase = computed(() =>
    this.ev()?.phases.find((p) => p.state === 'active'),
  );

  /** Sin fase activa hay que decir cuándo abre, no dejar un hueco. */
  protected readonly saleClosedLabel = computed(() => {
    const next = this.ev()?.phases.find((p) => p.state === 'future');
    return next ? `La venta abre en ${next.name}` : 'Venta cerrada';
  });

  /** Uno de los seis gradientes por índice: sin imagen, sigue siendo legible. */
  protected readonly gradient = computed(() => {
    const id = this.ev()?.id ?? '';
    let h = 0;
    for (const ch of id) h = (h * 31 + ch.charCodeAt(0)) % 6;
    return `fv-grad-${h}`;
  });

  constructor() {
    queueMicrotask(() => void this.load());
  }

  protected async load(): Promise<void> {
    const e = await this.store.getBySlug(this.slug());
    this.ev.set(e);
    if (e && this.auth.isSignedIn()) void this.cargarSocial(e.id);
  }

  /**
   * Aparte de `load` y sin `await` en la ruta principal: la señal es un adorno
   * (AC-18). Si esta consulta se cae, la ficha ya está pintada.
   */
  private async cargarSocial(eventId: string): Promise<void> {
    const [mapa, mio] = await Promise.all([
      this.social.signals(),
      this.social.myInterest(eventId),
    ]);
    this.senal.set(mapa.get(eventId) ?? null);
    this.meInteresa.set(mio);
  }

  /**
   * Crea el grupo y lleva a `/grupos`, que es donde se añaden los amigos y se
   * reserva. No se hace aqui: mezclar el flujo de grupo con el de compra
   * individual en la misma pantalla es la forma mas facil de romper el que ya
   * funciona.
   */
  protected async crearGrupo(): Promise<void> {
    const e = this.ev();
    if (!e) return;
    const id = await this.grupos.create(e.id);
    // Si ya tenia grupo para este evento, la pagina se lo enseña igual.
    void this.router.navigate(['/grupos'], { queryParams: id ? { nuevo: id } : {} });
  }

  protected async alternarInteres(): Promise<void> {
    const e = this.ev();
    if (!e) return;
    const nuevo = !this.meInteresa();
    this.meInteresa.set(nuevo);
    const error = await this.social.setInterest(e.id, nuevo);
    // Se revierte si el servidor dijo que no: el botón no miente sobre lo que
    // los demás van a ver.
    if (error) this.meInteresa.set(!nuevo);
  }

  /** El tier de la zona sin segmento (o el más barato) en la fase activa. */
  protected mainTier(z: PublicZone): PublicTier | undefined {
    const active = z.tiers.filter((t) => t.phase_active);
    const pool = active.length ? active : z.tiers;
    return (
      pool.find((t) => t.segment_id === null) ??
      [...pool].sort((a, b) => a.total_cents - b.total_cents)[0]
    );
  }

  protected segments(z: PublicZone): readonly PublicTier[] {
    return z.tiers.filter((t) => t.segment_id !== null && t.phase_active);
  }

  protected stock(t: PublicTier) {
    return stockLabel(t, this.ev()?.phases ?? []);
  }

  protected canBuy(z: PublicZone): boolean {
    if (!this.ev()?.sale_open) return false;
    return z.tiers.some((t) => t.phase_active && t.available > 0);
  }

  /** El tier comprable de la zona: el de la fase activa con disponibilidad. */
  protected buyTier(z: PublicZone): PublicTier | undefined {
    return z.tiers.find((t) => t.phase_active && t.available > 0);
  }

  /** Comprar exige sesión: la reserva se ata a un usuario. */
  protected async pick(z: PublicZone): Promise<void> {
    if (!this.auth.isSignedIn()) {
      await this.router.navigate(['/entrar'], {
        queryParams: { volver: `/eventos/${this.slug()}` },
      });
      return;
    }
    this.openZone.set(z.id);
  }

  protected async reserve(eventId: string, items: readonly ReserveItem[]): Promise<void> {
    const { data, error } = await this.checkout.reserve(eventId, items);
    if (error || !data) {
      // El mensaje de `reserve_order` ya está escrito para leerse; lo pinta
      // <fv-seleccion>. Se recarga el detalle para que la disponibilidad
      // mostrada deje de estar vieja.
      await this.load();
      return;
    }
    await this.router.navigate(['/comprar', data]);
  }

  protected phaseHint(p: { state: string; name: string; starts_at: string; ends_at: string; tickets: number }): string {
    if (p.state === 'active') {
      const days = Math.ceil((new Date(p.ends_at).getTime() - Date.now()) / 86_400_000);
      const left = days <= 0 ? 'termina hoy' : days === 1 ? 'termina mañana' : `termina en ${days} días`;
      return `Activa · ${left}${p.tickets > 0 ? ` · ${p.tickets} cupos` : ''}`;
    }
    if (p.state === 'future') return `Abre el ${shortDate(p.starts_at)}`;
    return 'Cerrada';
  }

  protected longDate(iso: string): string {
    return new Date(iso).toLocaleString('es-PE', {
      day: 'numeric',
      month: 'long',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });
  }

  protected time(iso: string): string {
    return new Date(iso).toLocaleTimeString('es-PE', {
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });
  }
}

function shortDate(iso: string): string {
  return new Date(iso).toLocaleDateString('es-PE', { day: 'numeric', month: 'long' });
}
