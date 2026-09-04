import {
  Component,
  ChangeDetectionStrategy,
  computed,
  inject,
  input,
  output,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { KINDS, SupportStore, type CaseContext, type SupportKind } from '../../features/soporte/support.store';

/**
 * «¿Algo va mal?» — el botón de soporte, con su formulario.
 *
 * Va incrustado donde está el problema (AC-21): en cada entrada de la wallet, en
 * el checkout, en el veredicto del validador y en el dashboard. Nunca obliga a
 * buscar un menú, porque quien tiene un problema en la puerta no va a navegar.
 *
 * El contexto llega YA CARGADO y visible (AC-22): el fan ve de qué entrada está
 * hablando antes de escribir. Y solo se manda el OBJETO —el `ticket_id`— porque
 * el evento y la orden los rellena el servidor: mandarlos desde aquí permitiría
 * adjuntar los de otro.
 */
@Component({
  selector: 'fv-support-button',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule],
  template: `
    @if (!abierto()) {
      <button
        type="button"
        (click)="abrir()"
        class="text-[12.5px] font-semibold text-violet underline underline-offset-2"
      >
        {{ etiqueta() }}
      </button>
    } @else {
      <div class="mt-2 rounded-[--radius-card] border border-border bg-surface p-4 text-left">
        <div class="flex items-start justify-between gap-3">
          <div>
            <p class="text-[14px] font-bold">Cuéntanos qué pasó</p>
            <!-- AC-22: qué entrada, antes de escribir. -->
            @if (contexto()) {
              <p class="mt-0.5 text-[12px] text-fg-muted">Sobre {{ contexto() }}</p>
            }
          </div>
          <button type="button" (click)="cerrar()" class="text-[12.5px] text-fg-muted">
            Cancelar
          </button>
        </div>

        @if (creado(); as code) {
          <div class="mt-3 rounded-[--radius-chip] bg-success-bg px-3 py-2.5 text-[13px] text-success-fg">
            <p class="font-bold">Caso {{ code }} registrado.</p>
            <!-- La compra sigue como está: el fan cree que abrir un caso la cancela. -->
            <p class="mt-0.5">
              Tu compra sigue exactamente como estaba mientras lo revisamos. Te
              respondemos por aquí; el código es {{ code }} si tienes que citarlo.
            </p>
          </div>
        } @else {
          <label class="mt-3 block text-[12px] font-semibold text-fg-muted">
            ¿Qué tipo de problema es?
          </label>
          <select
            [(ngModel)]="kind"
            class="mt-1 w-full rounded-[--radius-inner] border border-border bg-surface px-3 py-2.5 text-[13.5px]"
          >
            @for (k of tipos; track k.value) {
              <option [value]="k.value">{{ k.label }}</option>
            }
          </select>
          <!-- La pista NO es decorativa: es lo que separa «reembolso» de
               «cancelación» antes de que el fan elija mal y bloquee la vía
               correcta (D-12). -->
          <p class="mt-1.5 text-[12px] text-fg-soft">{{ pista() }}</p>

          <input
            [(ngModel)]="subject"
            maxlength="140"
            placeholder="Resume el problema en una línea"
            class="mt-3 w-full rounded-[--radius-inner] border border-border bg-surface px-3 py-2.5 text-[13.5px]"
          />

          <textarea
            [(ngModel)]="body"
            rows="4"
            maxlength="4000"
            placeholder="¿Qué pasó, cuándo, y qué esperabas que pasara?"
            class="mt-2 w-full rounded-[--radius-inner] border border-border bg-surface px-3 py-2.5 text-[13.5px]"
          ></textarea>

          @if (store.error(); as e) {
            <p class="mt-2 rounded-[--radius-chip] bg-danger-bg px-3 py-2 text-[12.5px] text-danger-fg">
              {{ e }}
            </p>
          }

          <button
            type="button"
            (click)="enviar()"
            [disabled]="!listo() || store.loading()"
            class="mt-3 w-full rounded-[--radius-chip] bg-coral px-4 py-2.5 text-[13.5px] font-bold text-white disabled:opacity-50"
          >
            {{ store.loading() ? 'Enviando…' : 'Enviar' }}
          </button>

          <!-- AC-24 · D-45: no se promete un tiempo de respuesta. Lo que sí se
               puede decir es qué pasa después. -->
          <p class="mt-2 text-[11.5px] text-fg-muted">
            Lo revisa una persona de Feventi. La respuesta te llega en «Mis casos».
          </p>
        }
      </div>
    }
  `,
})
export class SupportButton {
  readonly ctx = input<CaseContext>({});
  /** Sugerencia según dónde está el botón; el usuario puede cambiarla. */
  readonly defaultKind = input<SupportKind>('other');
  readonly label = input('¿Algo va mal con esta entrada?');
  /** Qué objeto es, en palabras. Se muestra antes de escribir (AC-22). */
  readonly contextLabel = input('');

  readonly created = output<string>();

  protected readonly store = inject(SupportStore);
  protected readonly tipos = KINDS;

  protected readonly abierto = signal(false);
  protected readonly creado = signal<string | null>(null);

  protected kind: SupportKind = 'other';
  protected subject = '';
  protected body = '';

  protected readonly etiqueta = computed(() => this.label());
  protected readonly contexto = computed(() => this.contextLabel());

  protected pista(): string {
    return KINDS.find((k) => k.value === this.kind)?.hint ?? '';
  }

  protected listo(): boolean {
    return this.subject.trim().length >= 3 && this.body.trim().length >= 10;
  }

  protected abrir(): void {
    this.kind = this.defaultKind();
    this.abierto.set(true);
    this.store.error.set(null);
  }

  protected cerrar(): void {
    this.abierto.set(false);
    this.creado.set(null);
    this.subject = '';
    this.body = '';
  }

  protected async enviar(): Promise<void> {
    const id = await this.store.open(this.kind, this.subject, this.body, this.ctx());
    if (!id) return;
    const caso = await this.store.get(id);
    this.creado.set(caso?.code ?? 'registrado');
    this.created.emit(id);
  }
}
