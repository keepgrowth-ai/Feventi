import { Component, ChangeDetectionStrategy, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { AuthStore } from '../../core/auth.store';
import { Chip } from '../../shared/ui/chip';
import {
  STATUS_LABEL,
  SupportStore,
  kindLabel,
  type SupportCase,
  type SupportMessage,
} from './support.store';

/**
 * «Mis casos» — el lado del usuario.
 *
 * No hay tiempo de respuesta estimado (AC-24, D-45): prometer «te contestamos en
 * 24 h» sin poder cumplirlo genera un segundo caso quejándose del primero. Lo
 * que sí se dice es en qué estado está y si la pelota está en su tejado.
 *
 * Las notas internas no se filtran aquí: no llegan. La RLS decide qué mensajes
 * salen (AC-10), y filtrarlas en el cliente sería fingir una protección que se
 * cae en cuanto alguien mire la respuesta de red.
 */
@Component({
  selector: 'fv-mis-casos',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule, RouterLink, Chip],
  template: `
    <header class="mb-5">
      <h1 class="text-2xl font-black tracking-[-0.5px]">Mis casos</h1>
      <p class="mt-1 text-[13px] text-fg-muted">
        Todo lo que has reportado, con su estado. Los casos se abren desde la entrada o
        la compra afectada.
      </p>
    </header>

    @if (store.error(); as e) {
      <p class="mb-4 rounded-[--radius-chip] bg-danger-bg px-3 py-2 text-[13px] text-danger-fg">
        {{ e }}
      </p>
    }

    <ul class="space-y-3">
      @for (c of casos(); track c.id) {
        <li class="rounded-[--radius-card] border border-border bg-surface p-4">
          <div class="flex flex-wrap items-start justify-between gap-2">
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-2">
                <!-- Monoespaciada y seleccionable: se dicta por teléfono (AC-20). -->
                <span class="select-all font-mono text-[12.5px] font-bold text-fg-soft">
                  {{ c.code }}
                </span>
                <fv-chip [tone]="estado(c.status).tone">{{ estado(c.status).label }}</fv-chip>
              </div>
              <p class="mt-1 text-[14px] font-bold">{{ c.subject }}</p>
              <p class="mt-0.5 text-[12.5px] text-fg-muted">
                {{ tipo(c.kind) }}
                @if (c.event_title) { · {{ c.event_title }} }
                @if (c.ticket_code) { · <span class="font-mono">{{ c.ticket_code }}</span> }
              </p>
            </div>
            <button
              type="button"
              (click)="abrir(c)"
              class="shrink-0 text-[12.5px] font-semibold text-info-fg"
            >
              {{ abiertoId() === c.id ? 'Ocultar' : 'Ver conversación' }}
            </button>
          </div>

          @if (c.status === 'waiting_user') {
            <p class="mt-2 rounded-[--radius-chip] bg-warn-bg px-3 py-2 text-[12.5px] text-warn-fg">
              Te pedimos información. Responde aquí abajo para que siga avanzando.
            </p>
          }

          @if (abiertoId() === c.id) {
            <div class="mt-3 border-t border-border pt-3">
              <ul class="space-y-2.5">
                @for (m of hilo(); track m.id) {
                  <li class="text-[13px]">
                    <p class="text-[11.5px] text-fg-muted">
                      {{ m.author_id === yo() ? 'Tú' : 'Feventi' }} ·
                      {{ fecha(m.created_at) }}
                    </p>
                    <p class="mt-0.5 whitespace-pre-line">{{ m.body }}</p>
                  </li>
                } @empty {
                  <li class="text-[13px] text-fg-muted">
                    Todavía no hay respuestas en este caso.
                  </li>
                }
              </ul>

              @if (c.status !== 'closed') {
                <div class="mt-3">
                  <textarea
                    [(ngModel)]="respuesta"
                    rows="3"
                    maxlength="4000"
                    placeholder="Escribe tu respuesta"
                    class="w-full rounded-[--radius-inner] border border-border bg-surface px-3 py-2.5 text-[13.5px]"
                  ></textarea>
                  <button
                    type="button"
                    (click)="responder(c)"
                    [disabled]="respuesta.trim().length < 1"
                    class="mt-2 rounded-[--radius-chip] bg-coral px-4 py-2 text-[13px] font-bold text-white disabled:opacity-50"
                  >
                    Responder
                  </button>
                </div>
              } @else {
                <p class="mt-3 text-[12.5px] text-fg-muted">
                  Este caso está cerrado. Si el problema sigue, abre uno nuevo desde la
                  entrada y cita el código {{ c.code }}.
                </p>
              }
            </div>
          }
        </li>
      } @empty {
        @if (!cargando()) {
          <li class="rounded-[--radius-card] border border-border bg-surface p-8 text-center">
            <p class="text-[15px] font-bold">No tienes ningún caso</p>
            <p class="mt-1 text-[13px] text-fg-muted">
              Si algo va mal con una entrada, el botón de ayuda está en la propia entrada:
              así el caso llega con todo el contexto y no tienes que explicarlo desde cero.
            </p>
            <a
              routerLink="/entradas"
              class="mt-4 inline-block rounded-[--radius-chip] bg-coral px-5 py-2.5 text-[14px] font-bold text-white"
            >
              Ir a mis entradas
            </a>
          </li>
        }
      }
    </ul>
  `,
})
export class MisCasosPage {
  protected readonly store = inject(SupportStore);
  protected readonly estado = (s: SupportCase['status']) => STATUS_LABEL[s];
  protected readonly tipo = kindLabel;

  // El autor se compara contra MI uid, no contra `opened_by` del caso: la vista
  // no expone ese campo a propósito (D-06), y un hilo puede tener mensajes de
  // Feventi y míos mezclados.
  protected readonly yo = inject(AuthStore).userId;

  protected readonly casos = signal<readonly SupportCase[]>([]);
  protected readonly hilo = signal<readonly SupportMessage[]>([]);
  protected readonly abiertoId = signal<string | null>(null);
  protected readonly cargando = signal(true);

  protected respuesta = '';

  constructor() {
    queueMicrotask(async () => {
      this.casos.set(await this.store.list());
      this.cargando.set(false);
    });
  }

  protected async abrir(c: SupportCase): Promise<void> {
    if (this.abiertoId() === c.id) {
      this.abiertoId.set(null);
      return;
    }
    this.abiertoId.set(c.id);
    this.hilo.set(await this.store.messages(c.id));
  }

  protected async responder(c: SupportCase): Promise<void> {
    if (!(await this.store.reply(c.id, this.respuesta))) return;
    this.respuesta = '';
    this.hilo.set(await this.store.messages(c.id));
    this.casos.set(await this.store.list());
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
