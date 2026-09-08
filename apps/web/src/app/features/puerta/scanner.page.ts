import {
  Component,
  ChangeDetectionStrategy,
  OnDestroy,
  computed,
  inject,
  input,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { QrScanner } from '../../shared/ui/qr-scanner';
import { SupportButton } from '../../shared/ui/support-button';
import {
  GateStore,
  verdictCopy,
  type Checkin,
  type DniMatch,
  type GateEvent,
  type GateStats,
  type Verdict,
} from './gate.store';

type Panel = 'scanner' | 'dni' | 'historial';

/**
 * El escáner. La pantalla que se usa bajo presión (Art. 10, modo Puerta).
 *
 * Lo que manda el spec y no se toca:
 *
 *  - el veredicto ocupa el ancho completo, con el título a 34 px o más (AC-27);
 *  - color, icono y texto en cada resultado. Nunca solo color (AC-28);
 *  - `ACCESO PERMITIDO` se cierra solo a los 2 s para poder encadenar entradas
 *    sin tocar nada; los otros tres ESPERAN un toque (AC-32). Es deliberadamente
 *    asimétrico: lo que va bien no debe frenar la cola, y lo que va mal no debe
 *    desaparecer antes de leerse;
 *  - el botón de escanear mide 56 px de alto y vive en la mitad inferior, que es
 *    donde llega el pulgar de una mano (AC-29, AC-33);
 *  - sin conexión, el escaneo se BLOQUEA. No hay cola de lecturas pendientes
 *    (AC-31, D-04): un ticket dado por bueno que luego resulta inválido es peor
 *    que una cola.
 *
 * El header repite evento, fecha y puerta SIEMPRE. Operar la puerta equivocada
 * es el error más caro de la noche.
 */
@Component({
  selector: 'fv-gate-scanner',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule, RouterLink, QrScanner, SupportButton],
  template: `
    <!-- ── Cabecera: dónde estoy ─────────────────────────────────────────── -->
    <header class="sticky top-0 z-30 border-b border-white/10 bg-ink px-4 py-3">
      <div class="mx-auto flex max-w-lg items-center justify-between gap-3">
        <div class="min-w-0">
          <a routerLink="/puerta" class="text-base text-white/50">‹ Mis eventos</a>
          <p class="truncate text-lg font-bold text-white">{{ evento()?.title ?? '…' }}</p>
        </div>
        <div class="shrink-0 text-right">
          <p class="text-2xl font-black leading-none text-white">{{ evento()?.gate }}</p>
          <p class="text-base text-white/50">{{ reloj() }}</p>
        </div>
      </div>
    </header>

    <div class="mx-auto max-w-lg px-4 pb-8">
      @if (!evento() && !cargando()) {
        <p class="mt-8 rounded-[--radius-card] bg-danger-fg px-4 py-4 text-lg font-bold text-white">
          No estás asignado a este evento.
        </p>
      }

      @if (evento(); as e) {
        @if (!e.shift_active) {
          <p class="mt-4 rounded-[--radius-card] bg-warn-fg px-4 py-4 text-base font-semibold text-ink">
            Fuera de la ventana de turno. El escáner abre 2 h antes de puertas y cierra 4 h
            después del inicio.
          </p>
        }

        <!-- ── Contador del turno ─────────────────────────────────────────── -->
        @if (stats(); as s) {
          <div class="mt-4 grid grid-cols-4 gap-2">
            <div class="rounded-[--radius-inner] bg-success-fg/15 px-2 py-2 text-center">
              <p class="text-2xl font-black text-success-fg">{{ s.allowed }}</p>
              <p class="text-base text-white/60">validadas</p>
            </div>
            <div class="rounded-[--radius-inner] bg-warn-fg/15 px-2 py-2 text-center">
              <p class="text-2xl font-black text-amber">{{ s.manual_review }}</p>
              <p class="text-base text-white/60">revisión</p>
            </div>
            <div class="rounded-[--radius-inner] bg-danger-fg/15 px-2 py-2 text-center">
              <p class="text-2xl font-black text-coral-200">{{ s.denied + s.already_used }}</p>
              <p class="text-base text-white/60">rechazos</p>
            </div>
            <div class="rounded-[--radius-inner] bg-white/10 px-2 py-2 text-center">
              <p class="text-2xl font-black text-white">{{ aforo(s) }}%</p>
              <p class="text-base text-white/60">aforo</p>
            </div>
          </div>
        }

        <!-- ── Panel ──────────────────────────────────────────────────────── -->
        <div class="mt-4" [hidden]="panel() !== 'scanner'">
          <fv-qr-scanner [paused]="!!veredicto() || !online()" [alto]="300" (code)="escanear($event)" />
        </div>

        @if (panel() === 'dni') {
          <!-- Modo DNI · D-03: el fan sin batería o con la pantalla rota -->
          <div class="mt-4 rounded-[--radius-card] border border-white/15 bg-white/5 p-4">
            <p class="text-lg font-bold text-white">Buscar por documento</p>
            <p class="mt-1 text-base text-white/60">
              Solo si el asistente no puede mostrar su QR. Queda como revisión manual.
            </p>
            <div class="mt-3 flex gap-2">
              <input
                [(ngModel)]="dni"
                inputmode="numeric"
                maxlength="8"
                placeholder="8 dígitos"
                class="min-w-0 flex-1 rounded-[--radius-inner] border-2 border-white/20 bg-black/40 px-3 py-3 font-mono text-xl text-white placeholder:text-white/30"
              />
              <button
                type="button"
                (click)="buscar()"
                class="rounded-[--radius-inner] bg-white px-5 text-lg font-bold text-ink disabled:opacity-40"
                [disabled]="dni.length !== 8"
              >
                Buscar
              </button>
            </div>

            <ul class="mt-3 space-y-2">
              @for (m of hallazgos(); track m.ticket_id) {
                <li class="rounded-[--radius-inner] bg-black/30 p-3">
                  <div class="flex items-center justify-between gap-3">
                    <div class="min-w-0">
                      <p class="truncate text-lg font-bold text-white">{{ m.holder_name }}</p>
                      <p class="text-base text-white/60">
                        {{ m.zone_name }}@if (m.row_label) { · {{ m.row_label }}-{{ m.seat_number }} }
                        · <span class="font-mono">{{ m.code }}</span>
                      </p>
                    </div>
                    @if (m.status === 'active') {
                      <button
                        type="button"
                        (click)="validarPorDni(m)"
                        class="shrink-0 rounded-[--radius-inner] bg-turquoise px-4 py-3 text-lg font-bold text-ink"
                      >
                        Validar
                      </button>
                    } @else {
                      <span class="shrink-0 text-base font-bold text-coral-200">{{ m.status }}</span>
                    }
                  </div>
                </li>
              } @empty {
                @if (buscado()) {
                  <li class="py-2 text-base text-white/60">
                    Ninguna entrada nominada con ese documento en este evento.
                  </li>
                }
              }
            </ul>
          </div>
        }

        @if (panel() === 'historial') {
          <!-- Art. 8.1: se lee, no se borra. Y la pantalla lo dice. -->
          <div class="mt-4 rounded-[--radius-card] border border-white/15 bg-white/5 p-4">
            <p class="text-lg font-bold text-white">Historial de tu turno</p>
            <p class="mt-1 text-base text-white/60">
              Queda registrado y no se puede borrar. Para corregir un error, abre un caso de
              soporte.
            </p>
            <ul class="mt-3 divide-y divide-white/10">
              @for (c of historial(); track c.id) {
                <li class="flex items-center justify-between gap-3 py-2.5">
                  <span class="font-mono text-base text-white/60">{{ hora(c.created_at) }}</span>
                  <span class="flex-1 text-base text-white">{{ etiqueta(c) }}</span>
                  <span class="size-3 shrink-0 rounded-full" [class]="punto(c.result)"></span>
                </li>
              } @empty {
                <li class="py-2 text-base text-white/60">Todavía no has escaneado nada.</li>
              }
            </ul>
          </div>
        }

        @if (store.error(); as err) {
          <p role="alert" class="mt-4 rounded-[--radius-chip] bg-danger-fg px-3 py-3 text-base font-semibold text-white">
            {{ err }}
          </p>
        }
      }
    </div>

    <!-- ── Controles: mitad inferior, al alcance del pulgar (AC-33) ──────── -->
    <nav class="sticky bottom-0 border-t border-white/10 bg-ink px-4 py-3">
      <div class="mx-auto grid max-w-lg grid-cols-3 gap-2">
        <button
          type="button"
          (click)="panel.set('scanner')"
          class="min-h-14 rounded-[--radius-inner] text-lg font-bold"
          [class]="panel() === 'scanner' ? 'bg-white text-ink' : 'bg-white/10 text-white'"
        >
          Escanear
        </button>
        <button
          type="button"
          (click)="panel.set('dni')"
          class="min-h-14 rounded-[--radius-inner] text-lg font-bold"
          [class]="panel() === 'dni' ? 'bg-white text-ink' : 'bg-white/10 text-white'"
        >
          Modo DNI
        </button>
        <button
          type="button"
          (click)="verHistorial()"
          class="min-h-14 rounded-[--radius-inner] text-lg font-bold"
          [class]="panel() === 'historial' ? 'bg-white text-ink' : 'bg-white/10 text-white'"
        >
          Historial
        </button>
      </div>
    </nav>

    <!-- ── El veredicto ─────────────────────────────────────────────────── -->
    @if (veredicto(); as v) {
      <!-- El veredicto ATERRIZA. Un rechazo que aparece con la misma suavidad
           que una aprobación se lee como una aprobación durante el cuarto de
           segundo que el portero tarda en leer la palabra — y en una cola, ese
           cuarto de segundo es la persona que ya pasó. -->
      <div
        class="fixed inset-0 z-50 flex flex-col justify-between p-5 text-white"
        [class]="copy(v).clase + ' ' + entrada(v)"
        role="alert"
        (click)="cerrarSiEsManual(v)"
      >
        <div class="pt-10 text-center">
          <p
            class="fv-anim-veredicto text-[64px] leading-none font-black"
            style="animation-delay:90ms"
          >
            {{ copy(v).icono }}
          </p>
          <!-- AC-27: 34 px o más, ancho completo -->
          <h2 class="mt-3 text-[34px] leading-[1.05] font-black tracking-[-1px]">
            {{ copy(v).titulo }}
          </h2>
        </div>

        <div class="text-center">
          @if (v.ticket; as t) {
            <p class="text-3xl font-black">{{ t.zone_name }}</p>
            @if (t.row_label) {
              <p class="text-2xl font-bold">Fila {{ t.row_label }} · Asiento {{ t.seat_number }}</p>
            }
            <p class="mt-2 text-xl font-semibold">{{ t.holder_name ?? 'Sin nominar' }}</p>
            <p class="font-mono text-lg opacity-80">{{ t.code }}</p>
          }
          <p class="mx-auto mt-4 max-w-sm text-lg font-semibold leading-snug">
            {{ copy(v).instruccion }}
          </p>
          <!-- 013 · mockup L685. Solo en ACCESO PERMITIDO: es el único caso en
               que se otorgan. No cuesta una consulta — el punto ya se abonó en
               la misma transacción que el ingreso. -->
          @if (v.result === 'allowed') {
            <p class="mt-3 text-base font-bold opacity-90">+50 puntos por check-in</p>
          }
        </div>

        <div class="pb-2">
          @if (v.result === 'allowed') {
            <p class="text-center text-lg opacity-80">Sigue escaneando</p>
          } @else {
            <button
              type="button"
              (click)="cerrar()"
              class="min-h-14 w-full rounded-[--radius-inner] bg-white/95 text-xl font-black text-ink"
            >
              Entendido
            </button>
            <!-- 009 · historia 4: el caso nace del escaneo que lo disparó, con
                 su ticket y su puerta ya adjuntos. El staff no teclea nada.
                 Y D-05: la excepción NO la ejecuta él — la pantalla lo dice para
                 que no deje esperando a alguien en la cola. -->
            <div class="mt-3 rounded-[--radius-inner] bg-white/95 p-3 text-ink" (click)="$event.stopPropagation()">
              <fv-support-button
                [ctx]="{ ticketId: v.ticket?.id, checkinId: v.checkin_id, eventId: eventId() }"
                defaultKind="qr"
                [contextLabel]="'el escaneo de ' + (v.ticket?.code ?? 'un código ilegible') + ' en ' + v.gate"
                label="Reportar incidencia de este escaneo"
              />
              <p class="mt-1.5 text-[12px] text-fg-muted">
                Queda registrado para Feventi. La excepción de acceso la autoriza
                Feventi, no la puerta: no hagas esperar a la persona por esto.
              </p>
            </div>
            <p class="mt-2 text-center text-base opacity-75">
              Escaneo {{ v.checkin_id.slice(0, 8) }}
            </p>
          }
        </div>
      </div>
    }
  `,
})
export class GateScannerPage implements OnDestroy {
  /** Del router. */
  readonly eventId = input.required<string>();

  protected readonly store = inject(GateStore);
  protected readonly copy = verdictCopy;

  protected readonly evento = signal<GateEvent | null>(null);
  protected readonly cargando = signal(true);
  protected readonly veredicto = signal<Verdict | null>(null);
  protected readonly stats = signal<GateStats | null>(null);
  protected readonly historial = signal<readonly Checkin[]>([]);
  protected readonly hallazgos = signal<readonly DniMatch[]>([]);
  protected readonly buscado = signal(false);
  protected readonly panel = signal<Panel>('scanner');
  protected readonly online = signal(navigator.onLine);
  protected readonly reloj = signal(this.ahora());

  protected dni = '';

  private cierre?: ReturnType<typeof setTimeout>;
  private readonly tic = setInterval(() => this.reloj.set(this.ahora()), 10_000);
  private readonly onOnline = () => this.online.set(navigator.onLine);

  constructor() {
    addEventListener('online', this.onOnline);
    addEventListener('offline', this.onOnline);
    queueMicrotask(() => void this.cargar());
  }

  ngOnDestroy(): void {
    clearInterval(this.tic);
    clearTimeout(this.cierre);
    removeEventListener('online', this.onOnline);
    removeEventListener('offline', this.onOnline);
  }

  private async cargar(): Promise<void> {
    const míos = await this.store.myEvents();
    this.evento.set(míos.find((e) => e.event_id === this.eventId()) ?? null);
    this.cargando.set(false);
    await this.refrescarContador();
  }

  protected async escanear(token: string): Promise<void> {
    // AC-31 · D-04: sin red no se escanea, y no se guarda para después.
    if (!this.online() || this.veredicto()) return;
    await this.resolver({ token });
  }

  protected async validarPorDni(m: DniMatch): Promise<void> {
    if (!this.online()) return;
    await this.resolver({ mode: 'dni', ticket_id: m.ticket_id });
    this.hallazgos.set([]);
    this.dni = '';
    this.buscado.set(false);
  }

  private async resolver(body: { token: string } | { mode: 'dni'; ticket_id: string }): Promise<void> {
    const v = await this.store.validate(this.eventId(), body);
    if (!v) return;
    this.veredicto.set(v);

    // AC-32: solo el permitido se va solo. Los otros tres esperan.
    clearTimeout(this.cierre);
    if (v.result === 'allowed') this.cierre = setTimeout(() => this.cerrar(), 2000);

    void this.refrescarContador();
  }

  protected cerrar(): void {
    clearTimeout(this.cierre);
    this.veredicto.set(null);
    this.store.error.set(null);
  }

  /** Tocar el fondo cierra los que esperan; el permitido ya se va solo. */
  protected cerrarSiEsManual(v: Verdict): void {
    if (v.result !== 'allowed') this.cerrar();
  }

  protected async buscar(): Promise<void> {
    this.store.error.set(null);
    this.hallazgos.set(await this.store.findByDni(this.eventId(), this.dni));
    this.buscado.set(true);
  }

  protected async verHistorial(): Promise<void> {
    this.panel.set('historial');
    this.historial.set(await this.store.history(this.eventId()));
  }

  private async refrescarContador(): Promise<void> {
    this.stats.set(await this.store.stats(this.eventId()));
    if (this.panel() === 'historial') this.historial.set(await this.store.history(this.eventId()));
  }

  protected aforo(s: GateStats): number {
    return s.tickets_total ? Math.round((s.tickets_used / s.tickets_total) * 100) : 0;
  }

  protected hora(iso: string): string {
    return new Date(iso).toLocaleTimeString('es-PE', {
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });
  }

  private ahora(): string {
    return new Date().toLocaleTimeString('es-PE', {
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });
  }

  protected etiqueta(c: Checkin): string {
    return (
      {
        allowed: 'Acceso permitido',
        manual_review: 'Revisión manual',
        already_used: 'Ya utilizado',
        denied: 'Acceso denegado',
      }[c.result] + (c.result === 'allowed' ? '' : ` · ${MOTIVO[c.reason] ?? c.reason}`)
    );
  }

  /**
   * Permitido y revisión manual entran asentándose; lo que se rechaza entra
   * negando con la cabeza. Es la única animación del producto que distingue un
   * caso de otro, y lo hace porque el portero tiene que saber el resultado
   * antes de terminar de leer la palabra.
   */
  protected entrada(v: Verdict): string {
    return v.result === 'allowed' || v.result === 'manual_review'
      ? 'fv-anim-veredicto'
      : 'fv-anim-rechazo';
  }

  protected punto(r: string): string {
    return (
      { allowed: 'bg-turquoise', manual_review: 'bg-amber' }[r] ?? 'bg-coral'
    );
  }
}

const MOTIVO: Record<string, string> = {
  not_nominated: 'sin nominar',
  wrong_zone: 'otra zona',
  dni_mode: 'por documento',
  already_used: 'repetido',
  qr_unreadable: 'código ilegible',
  screenshot_suspected: 'captura de pantalla',
  wrong_event: 'otro evento',
  event_cancelled: 'evento cancelado',
  ticket_listed: 'en reventa',
  ticket_transferred: 'transferida',
  ticket_void: 'anulada',
  ticket_refunded: 'reembolsada',
};
