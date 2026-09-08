import { Component, ChangeDetectionStrategy, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Chip } from '../../shared/ui/chip';
import {
  PRIORITY_LABEL,
  STATUS_LABEL,
  SupportStore,
  kindLabel,
  type SupportCase,
  type SupportMessage,
  type SupportPriority,
  type SupportStatus,
} from '../soporte/support.store';

/**
 * La cola de soporte de Admin.
 *
 * Todo el contexto se ve SIN salir del caso (historia 7): el ticket, la orden y
 * el evento vienen ya resueltos en `v_support_queue`, con sus códigos. Quien
 * atiende no tiene que abrir tres pestañas para entender de qué habla el fan.
 *
 * Las acciones sobre el ticket dejan asiento en `ticket_events` con el caso en
 * `meta` (Art. 8.3). Anular no se pregunta dos veces por gusto: es irreversible
 * en el sentido que importa —la persona no entra— y la corrección posterior es
 * otro asiento, no un deshacer.
 */
@Component({
  selector: 'fv-admin-soporte',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule, Chip],
  template: `
    <header class="mb-5 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 class="text-2xl font-black tracking-[-0.5px]">Soporte</h1>
        <p class="mt-1 text-[13px] text-fg-muted">
          {{ abiertos() }} sin resolver de {{ casos().length }} en total.
        </p>
      </div>
      <div class="flex gap-2">
        <select
          [(ngModel)]="filtroEstado"
          (ngModelChange)="recargar()"
          class="rounded-[--radius-chip] border border-border bg-surface px-3 py-2 text-[13px]"
        >
          <option value="">Todos los estados</option>
          @for (s of estados; track s) {
            <option [value]="s">{{ etiquetaEstado(s).label }}</option>
          }
        </select>
      </div>
    </header>

    @if (store.error(); as e) {
      <p role="alert" class="mb-4 rounded-[--radius-chip] bg-danger-bg px-3 py-2 text-[13px] text-danger-fg">
        {{ e }}
      </p>
    }

    <ul class="space-y-3">
      @for (c of casos(); track c.id) {
        <li class="rounded-[--radius-card] border border-border bg-surface p-4">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-2">
                <span class="select-all font-mono text-[12.5px] font-bold text-fg-soft">
                  {{ c.code }}
                </span>
                <!-- AC-23: prioridad con color Y texto. -->
                <fv-chip [tone]="prioridad(c.priority).tone">
                  {{ prioridad(c.priority).label }}
                </fv-chip>
                <fv-chip [tone]="etiquetaEstado(c.status).tone">
                  {{ etiquetaEstado(c.status).label }}
                </fv-chip>
              </div>
              <p class="mt-1 text-[14px] font-bold">{{ c.subject }}</p>
              <!-- El contexto, sin salir del caso -->
              <p class="mt-0.5 text-[12.5px] text-fg-muted">
                {{ tipo(c.kind) }} · {{ c.opened_by_label }}
                @if (c.event_title) { · {{ c.event_title }} }
                @if (c.ticket_code) { · entrada <span class="font-mono">{{ c.ticket_code }}</span> }
                @if (c.order_code) { · pedido <span class="font-mono">{{ c.order_code }}</span> }
                · {{ fecha(c.created_at) }}
              </p>
            </div>
            <button
              type="button"
              (click)="abrir(c)"
              class="shrink-0 rounded-[--radius-chip] bg-muted px-3 py-2 text-[12.5px] font-semibold"
            >
              {{ abiertoId() === c.id ? 'Cerrar' : 'Atender' }}
            </button>
          </div>

          @if (abiertoId() === c.id) {
            <div class="mt-3 grid gap-4 border-t border-border pt-3 lg:grid-cols-[1fr_260px]">
              <!-- ── El hilo ──────────────────────────────────────────────── -->
              <div>
                <ul class="space-y-2.5">
                  @for (m of hilo(); track m.id) {
                    <li
                      class="rounded-[--radius-inner] p-2.5 text-[13px]"
                      [class]="m.internal ? 'bg-warn-bg' : 'bg-muted'"
                    >
                      <p class="text-[11.5px] text-fg-muted">
                        {{ m.internal ? 'Nota interna · no la ve el usuario' : 'Conversación' }}
                        · {{ fecha(m.created_at) }}
                      </p>
                      <p class="mt-0.5 whitespace-pre-line">{{ m.body }}</p>
                    </li>
                  } @empty {
                    <li class="text-[13px] text-fg-muted">Sin mensajes todavía.</li>
                  }
                </ul>

                <textarea
                  [(ngModel)]="mensaje"
                  rows="3"
                  maxlength="4000"
                  placeholder="Escribe la respuesta o la nota"
                  class="mt-3 w-full rounded-[--radius-inner] border border-border bg-surface px-3 py-2.5 text-[13.5px]"
                ></textarea>
                <div class="mt-2 flex flex-wrap gap-2">
                  <button
                    type="button"
                    (click)="responder(c, false)"
                    [disabled]="!mensaje.trim()"
                    class="rounded-[--radius-chip] bg-coral px-4 py-2 text-[13px] font-bold text-white disabled:opacity-50"
                  >
                    Responder al usuario
                  </button>
                  <button
                    type="button"
                    (click)="responder(c, true)"
                    [disabled]="!mensaje.trim()"
                    class="rounded-[--radius-chip] bg-muted px-4 py-2 text-[13px] font-bold disabled:opacity-50"
                  >
                    Guardar como nota interna
                  </button>
                </div>
              </div>

              <!-- ── Gestión ──────────────────────────────────────────────── -->
              <div class="space-y-3">
                <div>
                  <label class="text-[11.5px] font-semibold uppercase tracking-wide text-fg-muted">
                    Estado
                  </label>
                  <select
                    [ngModel]="c.status"
                    (ngModelChange)="cambiar(c, { status: $event })"
                    class="mt-1 w-full rounded-[--radius-inner] border border-border bg-surface px-3 py-2 text-[13px]"
                  >
                    @for (s of estados; track s) {
                      <option [value]="s">{{ etiquetaEstado(s).label }}</option>
                    }
                  </select>
                </div>
                <div>
                  <label class="text-[11.5px] font-semibold uppercase tracking-wide text-fg-muted">
                    Prioridad
                  </label>
                  <select
                    [ngModel]="c.priority"
                    (ngModelChange)="cambiar(c, { priority: $event })"
                    class="mt-1 w-full rounded-[--radius-inner] border border-border bg-surface px-3 py-2 text-[13px]"
                  >
                    @for (p of prioridades; track p) {
                      <option [value]="p">{{ prioridad(p).label }}</option>
                    }
                  </select>
                </div>

                @if (c.ticket_id) {
                  <div class="rounded-[--radius-inner] border border-border p-3">
                    <p class="text-[11.5px] font-semibold uppercase tracking-wide text-fg-muted">
                      Sobre la entrada
                    </p>
                    <p class="mt-1 font-mono text-[12.5px]">{{ c.ticket_code }}</p>
                    <button
                      type="button"
                      (click)="anular(c)"
                      class="mt-2 w-full rounded-[--radius-chip] bg-danger-bg px-3 py-2 text-[12.5px] font-bold text-danger-fg"
                    >
                      {{ confirmando() === c.id ? '¿Seguro? Toca otra vez' : 'Anular entrada' }}
                    </button>
                    <p class="mt-1.5 text-[11.5px] text-fg-muted">
                      Queda asiento con tu nombre y el código del caso. Corregirlo después
                      es otro asiento, no un deshacer.
                    </p>
                  </div>
                }
              </div>
            </div>
          }
        </li>
      } @empty {
        @if (!cargando()) {
          <li class="rounded-[--radius-card] border border-border bg-surface p-8 text-center">
            <p class="text-[15px] font-bold">Sin casos con este filtro</p>
          </li>
        }
      }
    </ul>
  `,
})
export class AdminSoportePage {
  protected readonly store = inject(SupportStore);
  protected readonly etiquetaEstado = (s: SupportStatus) => STATUS_LABEL[s];
  protected readonly prioridad = (p: SupportPriority) => PRIORITY_LABEL[p];
  protected readonly tipo = kindLabel;

  protected readonly estados: readonly SupportStatus[] = [
    'open', 'waiting_user', 'in_progress', 'escalated', 'resolved', 'closed',
  ];
  protected readonly prioridades: readonly SupportPriority[] = ['low', 'normal', 'high', 'urgent'];

  protected readonly casos = signal<readonly SupportCase[]>([]);
  protected readonly hilo = signal<readonly SupportMessage[]>([]);
  protected readonly abiertoId = signal<string | null>(null);
  protected readonly cargando = signal(true);
  /** Anular pide dos toques: no hay deshacer. */
  protected readonly confirmando = signal<string | null>(null);

  protected filtroEstado = '';
  protected mensaje = '';

  protected readonly abiertos = computed(
    () => this.casos().filter((c) => c.status !== 'resolved' && c.status !== 'closed').length,
  );

  constructor() {
    queueMicrotask(() => void this.recargar());
  }

  protected async recargar(): Promise<void> {
    this.casos.set(
      await this.store.list(this.filtroEstado ? { status: this.filtroEstado as SupportStatus } : undefined),
    );
    this.cargando.set(false);
  }

  protected async abrir(c: SupportCase): Promise<void> {
    if (this.abiertoId() === c.id) {
      this.abiertoId.set(null);
      return;
    }
    this.abiertoId.set(c.id);
    this.confirmando.set(null);
    this.hilo.set(await this.store.messages(c.id));
  }

  protected async responder(c: SupportCase, interna: boolean): Promise<void> {
    if (!(await this.store.reply(c.id, this.mensaje, interna))) return;
    this.mensaje = '';
    this.hilo.set(await this.store.messages(c.id));
  }

  protected async cambiar(
    c: SupportCase,
    cambios: { status?: SupportStatus; priority?: SupportPriority },
  ): Promise<void> {
    if (await this.store.manage(c.id, cambios)) await this.recargar();
  }

  protected async anular(c: SupportCase): Promise<void> {
    if (this.confirmando() !== c.id) {
      this.confirmando.set(c.id);
      return;
    }
    this.confirmando.set(null);
    if (!c.ticket_id) return;
    if (await this.store.ticketAction(c.id, c.ticket_id, 'voided', `Anulada desde el caso ${c.code}`)) {
      this.hilo.set(await this.store.messages(c.id));
      await this.recargar();
    }
  }

  protected fecha(iso: string): string {
    return new Date(iso).toLocaleString('es-PE', {
      day: 'numeric',
      month: 'short',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });
  }
}
