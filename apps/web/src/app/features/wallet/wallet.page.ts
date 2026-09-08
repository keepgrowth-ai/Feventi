import {
  Component,
  ChangeDetectionStrategy,
  computed,
  inject,
  signal,
  OnDestroy,
} from '@angular/core';
import { RouterLink } from '@angular/router';
import { Chip } from '../../shared/ui/chip';
import { CountUp } from '../../shared/ui/count-up';
import { SupportButton } from '../../shared/ui/support-button';
import { TicketQr } from '../../shared/ui/ticket-qr';
import { WalletStore, qrCopy, type QrToken, type WalletTicket } from './wallet.store';

/**
 * La wallet. El centro de control del fan, y la implementación del Art. 2.
 *
 * Lo que no se negocia:
 *  - el QR va en canvas, sin descarga ni compartir (AC-19);
 *  - la cuenta atrás con barra: es lo que PRUEBA visualmente que el código
 *    cambia, y sin esa prueba el mensaje de abajo es una afirmación vacía;
 *  - «Muestra este QR en puerta. Las capturas no funcionan.» siempre visible,
 *    no en un tooltip ni en un acordeón (AC-20);
 *  - el token vive en memoria y muere con la pestaña (AC-21);
 *  - el código del ticket en monoespaciada y seleccionable — hay que poder
 *    dictarlo a soporte a las once de la noche (AC-22).
 */
@Component({
  selector: 'fv-wallet',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Chip, SupportButton, TicketQr, CountUp],
  template: `
    <header class="mb-5 flex flex-wrap items-start justify-between gap-4">
      <div>
        <h1 class="text-2xl font-black tracking-[-0.5px]">Mis entradas</h1>
        <p class="mt-1 text-[13px] text-fg-muted">
          Tu entrada es una credencial viva. El QR se muestra desde aquí y cambia cada
          {{ slotSeconds() }} segundos.
        </p>
      </div>

      <!-- 013 · mockup L338. Cero NO se pinta: «0 puntos» le dice al fan que la
           función existe y que él no la ha usado, que es la peor combinación. -->
      @if (puntos() > 0) {
        <div class="rounded-[--radius-card] bg-info-bg px-4 py-2.5 text-right">
          <p class="text-xl font-black text-info-fg">
            <fv-count-up [value]="puntos()" />
          </p>
          <p class="text-[11px] font-semibold text-fg-muted">puntos</p>
        </div>
      }
    </header>

    @if (store.loading() && !tickets().length) {
      <p class="fv-solo-lector" role="status" aria-live="polite">Cargando tus entradas…</p>
      <div class="space-y-3" aria-hidden="true">
        <div class="rounded-[--radius-card] border border-border bg-surface p-4">
          <div class="fv-bone h-4 w-40"></div>
          <div class="fv-bone mx-auto mt-4 size-56 rounded-[--radius-inner]"></div>
          <div class="fv-bone mx-auto mt-3 h-3 w-48"></div>
        </div>
        <div class="rounded-[--radius-card] border border-border bg-surface p-4">
          <div class="fv-bone h-4 w-52"></div>
          <div class="fv-bone mt-2 h-3 w-32"></div>
        </div>
      </div>
    }

    @if (store.error(); as e) {
      <p role="alert" class="mb-4 rounded-[--radius-chip] bg-danger-bg px-3 py-2.5 text-[13px] text-danger-fg">
        {{ e }}
      </p>
    }

    <!-- La próxima entrada, con su QR grande -->
    @if (proxima(); as t) {
      <section class="mb-6 overflow-hidden rounded-[--radius-card] border border-border bg-surface">
        <div class="bg-navy px-4 py-3 text-white">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div>
              <p class="text-[11px] text-white/60">Próxima entrada</p>
              <p class="text-[15px] font-bold">{{ t.event_title }}</p>
            </div>
            <fv-chip [tone]="copy(t).tone">{{ copy(t).chip }}</fv-chip>
          </div>
        </div>

        <div class="flex flex-col items-center gap-4 p-5 sm:flex-row sm:items-start">
          <div class="shrink-0 text-center">
            @if (t.qr_state === 'available' && token(); as tk) {
              <fv-ticket-qr [token]="tk.token" [label]="t.code" [px]="224" />

              <!-- La cuenta atrás PRUEBA que el código cambia -->
              <div class="mt-2.5 w-56">
                <div class="flex items-baseline justify-between text-[11.5px] text-fg-muted">
                  <span>Se actualiza en {{ left() }}s</span>
                  <span class="font-mono">{{ t.code }}</span>
                </div>
                <div class="mt-1 h-1 overflow-hidden rounded-full bg-muted">
                  <div
                    class="h-full bg-coral transition-[width] duration-1000 ease-linear"
                    [style.width.%]="progress()"
                  ></div>
                </div>
              </div>
            } @else {
              <div
                class="grid size-56 place-items-center rounded-[--radius-inner] border-2 border-dashed border-border bg-muted p-5 text-center"
              >
                <div>
                  <p class="text-[13px] font-bold">{{ copy(t).chip }}</p>
                  <p class="mt-1.5 text-[12px] text-fg-muted">{{ copy(t).detail }}</p>
                </div>
              </div>
              <p class="mt-2 w-56 text-center font-mono text-[12px] text-fg-soft">{{ t.code }}</p>
            }
          </div>

          <div class="min-w-0 flex-1">
            <dl class="grid gap-y-1.5 text-[13px]">
              <div class="flex justify-between gap-3">
                <dt class="text-fg-muted">Zona</dt>
                <dd class="text-right font-semibold">
                  {{ t.zone_name }}
                  @if (t.row_label) {
                    · Fila {{ t.row_label }}-{{ t.seat_number }}
                  }
                </dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-fg-muted">Titular</dt>
                <dd class="text-right font-semibold">
                  {{ t.holder_name ?? 'Sin nominar' }}
                  @if (t.holder_dni_last4) {
                    <span class="font-mono text-fg-muted">••••{{ t.holder_dni_last4 }}</span>
                  }
                </dd>
              </div>
              @if (t.starts_at) {
                <div class="flex justify-between gap-3">
                  <dt class="text-fg-muted">Cuándo</dt>
                  <dd class="text-right font-semibold">{{ fecha(t.starts_at) }}</dd>
                </div>
              }
              <div class="flex justify-between gap-3">
                <dt class="text-fg-muted">Dónde</dt>
                <dd class="text-right font-semibold">
                  {{ t.venue_name }}@if (t.venue_city) { · {{ t.venue_city }} }
                </dd>
              </div>
            </dl>

            @if (!t.holder_name) {
              <p class="mt-3 rounded-[--radius-chip] bg-warn-bg px-3 py-2 text-[12px] text-warn-fg">
                Esta entrada no está nominada: en puerta entrará a revisión manual.
              </p>
            }

            <!-- Art. 2.3 · siempre visible, nunca en un tooltip -->
            <p class="mt-3 text-[12px] font-semibold text-fg-soft">
              Muestra este QR en puerta. Las capturas no funcionan.
            </p>

            <!-- 009/AC-21: la ayuda vive DONDE está el problema. El caso sale ya
                 con esta entrada adjunta, así que el fan no teclea ningún código. -->
            <div class="mt-3">
              <fv-support-button
                [ctx]="{ ticketId: t.id }"
                [defaultKind]="t.qr_state === 'available' ? 'qr' : 'ticket'"
                [contextLabel]="t.event_title + ' · ' + t.code"
              />
            </div>
          </div>
        </div>
      </section>
    }

    <!-- Las demás -->
    @if (otras().length) {
      <section class="mb-6">
        <h2 class="mb-2 text-[12px] font-bold text-fg-muted">
          Otras entradas
        </h2>
        <ul class="space-y-2">
          @for (t of otras(); track t.id) {
            <li class="rounded-[--radius-card] border border-border bg-surface p-3.5">
              <div class="flex flex-wrap items-start justify-between gap-2">
                <div class="min-w-0">
                  <p class="text-[14px] font-bold">{{ t.event_title }}</p>
                  <p class="text-[12.5px] text-fg-muted">
                    @if (t.starts_at) { {{ fechaCorta(t.starts_at) }} · }
                    {{ t.zone_name }}@if (t.row_label) { {{ t.row_label }}-{{ t.seat_number }} } ·
                    <span class="font-mono">{{ t.code }}</span>
                  </p>
                </div>
                <fv-chip [tone]="copy(t).tone">{{ copy(t).chip }}</fv-chip>
              </div>
              @if (copy(t).detail) {
                <p class="mt-1.5 text-[12px] text-fg-muted">{{ copy(t).detail }}</p>
              }
              <div class="mt-2">
                <fv-support-button
                  [ctx]="{ ticketId: t.id }"
                  defaultKind="ticket"
                  [contextLabel]="t.event_title + ' · ' + t.code"
                  label="Reportar un problema"
                />
              </div>
            </li>
          }
        </ul>
      </section>
    }

    <!-- Pasadas -->
    @if (pasadas().length) {
      <section>
        <h2 class="mb-2 text-[12px] font-bold text-fg-muted">
          Entradas pasadas
        </h2>
        <ul class="space-y-2">
          @for (t of pasadas(); track t.id) {
            <li
              class="rounded-[--radius-card] border border-border bg-muted p-3.5 opacity-70"
            >
              <div class="flex flex-wrap items-center justify-between gap-2">
                <span class="text-[13.5px] font-semibold">{{ t.event_title }}</span>
                <fv-chip [tone]="copy(t).tone">{{ copy(t).chip }}</fv-chip>
              </div>
              <p class="mt-0.5 text-[12px] text-fg-muted">{{ copy(t).detail }}</p>
            </li>
          }
        </ul>
      </section>
    }

    @if (!tickets().length && !store.loading()) {
      <div class="rounded-[--radius-card] border border-border bg-surface p-8 text-center">
        <p class="text-[15px] font-bold">Todavía no tienes entradas</p>
        <p class="mt-1 text-[13px] text-fg-muted">
          Cuando compres, aparecerán aquí con su QR.
        </p>
        <a
          routerLink="/eventos"
          class="mt-4 inline-block rounded-[--radius-chip] bg-coral px-5 py-2.5 text-[14px] font-bold text-white"
        >
          Ver eventos
        </a>
      </div>
    }
  `,
})
export class WalletPage implements OnDestroy {
  protected readonly store = inject(WalletStore);
  protected readonly copy = qrCopy;

  protected readonly tickets = signal<readonly WalletTicket[]>([]);
  protected readonly puntos = signal(0);
  /** En memoria, y solo aquí. Nunca en localStorage (AC-21). */
  protected readonly token = signal<QrToken | null>(null);
  protected readonly left = signal(0);

  private timer?: ReturnType<typeof setInterval>;

  /**
   * Momento real en que vence el token, en milisegundos de reloj.
   *
   * La cuenta atrás NO puede ser «restar uno por cada tick». Chrome frena los
   * temporizadores de una pestaña en segundo plano a uno por minuto, y un
   * portátil que se bloquea los para del todo. Con el modelo de restar, el
   * contador cree que quedan 28 segundos cuando han pasado tres minutos — y el
   * QR en pantalla es de hace tres minutos.
   *
   * Eso no es un detalle cosmético: el validador rechaza un token de hace tres
   * minutos por `screenshot_suspected`, que es exactamente lo que tiene que
   * hacer. El fallo estaba aquí, no allí.
   */
  private venceEn = 0;
  /** Hay una petición de token en vuelo. Evita que se solapen. */
  private pidiendo = false;

  protected readonly slotSeconds = computed(() => this.token()?.slot_seconds ?? 30);
  protected readonly progress = computed(() =>
    Math.round((this.left() / this.slotSeconds()) * 100),
  );

  /** La primera con QR disponible; si no hay, la más próxima. */
  protected readonly proxima = computed(() => {
    const vivos = this.tickets().filter((t) => !t.is_past);
    return vivos.find((t) => t.qr_state === 'available') ?? vivos[0] ?? null;
  });

  protected readonly otras = computed(() => {
    const p = this.proxima();
    return this.tickets().filter((t) => !t.is_past && t.id !== p?.id);
  });

  protected readonly pasadas = computed(() => this.tickets().filter((t) => t.is_past));

  constructor() {
    // El temporizador arranca DESPUÉS de la primera carga, no a la vez.
    //
    // Antes empezaba aquí, y como `left` vale 0 hasta que llega el primer token,
    // en el segundo 1 el tick veía `0 - 1` —no mayor que cero— y disparaba un
    // refresco **encima del que ya estaba en vuelo**. Dos peticiones compitiendo
    // por escribir la misma señal, y el QR apareciendo tarde o a saltos.
    queueMicrotask(async () => {
      await this.load();
      this.timer = setInterval(() => this.tick(), 1000);
    });

    // Volver a la pestaña refresca YA, sin esperar al siguiente tick — que con
    // el navegador frenado puede tardar un minuto en llegar.
    //
    // Es el caso de la demostración, literalmente: se abre el QR en el
    // portátil, se coge el móvil para escanear, y al mirar la pantalla otra vez
    // el código lleva rato parado. Sin esto, el primer escaneo dice DENEGADO
    // por sospecha de captura — y el sistema tendría razón.
    document.addEventListener('visibilitychange', this.alVolver);
  }

  private readonly alVolver = (): void => {
    if (document.visibilityState !== 'visible') return;
    if (Date.now() < this.venceEn) return;
    const t = this.proxima();
    if (t?.qr_state === 'available') void this.refresh(t.id);
  };

  ngOnDestroy(): void {
    clearInterval(this.timer);
    document.removeEventListener('visibilitychange', this.alVolver);
  }

  private async load(): Promise<void> {
    // Aparte de las entradas: si el saldo falla, la wallet sigue sirviendo.
    void this.store.points().then((p) => this.puntos.set(p));
    this.tickets.set(await this.store.list());
    const t = this.proxima();
    if (t?.qr_state === 'available') await this.refresh(t.id);
  }

  private async refresh(ticketId: string): Promise<void> {
    // Una petición a la vez. Sin esto, dos refrescos solapados escriben la misma
    // señal en orden impredecible y puede quedar el token VIEJO encima del nuevo
    // — un QR que el validador rechaza por captura de pantalla, sin que el fan
    // haya hecho nada raro.
    if (this.pidiendo) return;
    this.pidiendo = true;
    try {
      const { data, error } = await this.store.qrToken(ticketId);
      if (error) {
        this.store.error.set(error);
        this.token.set(null);
        // Sin esto, `left` se queda en 0 y el tick reintenta CADA SEGUNDO: un
        // fallo persistente se convierte en una tormenta de peticiones. Con 5 s
        // el reintento existe pero no castiga a un servidor que ya va mal.
        this.venceEn = Date.now() + 5000;
        this.left.set(5);
        return;
      }
      this.token.set(data);
      // Los segundos vienen del SERVIDOR. Deducirlos del reloj del móvil haría
      // que la cuenta atrás mintiera en cuanto hubiera desfase — y esa cuenta
      // atrás es justamente lo que sostiene el mensaje de que el código cambia.
      //
      // El mínimo de 2 s es por el borde del slot: si el token se pide justo
      // antes de que cambie, `expires_in` llega valiendo 1, y con la latencia de
      // la petición el siguiente refresco entra antes de que el anterior acabe
      // de pintarse. Perder un segundo de vigencia no le importa a nadie;
      // encadenar peticiones, sí.
      const segundos = Math.max(data?.expires_in ?? 0, 2);
      this.venceEn = Date.now() + segundos * 1000;
      this.left.set(segundos);
    } finally {
      this.pidiendo = false;
    }
  }

  /**
   * Se calcula contra el reloj, no restando. Si el navegador frenó el
   * temporizador —pestaña en segundo plano, portátil bloqueado— el primer tick
   * al volver ve que ya venció y pide token nuevo, en vez de seguir enseñando
   * uno caducado como si estuviera fresco.
   */
  private tick(): void {
    const quedan = Math.ceil((this.venceEn - Date.now()) / 1000);
    if (quedan > 0) {
      this.left.set(quedan);
      return;
    }
    const t = this.proxima();
    if (t?.qr_state === 'available') void this.refresh(t.id);
    else this.left.set(0);
  }

  protected fecha(iso: string): string {
    return new Date(iso).toLocaleString('es-PE', {
      day: 'numeric',
      month: 'long',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });
  }

  protected fechaCorta(iso: string): string {
    return new Date(iso).toLocaleDateString('es-PE', { day: 'numeric', month: 'short' });
  }
}
