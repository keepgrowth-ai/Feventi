import { Component, ChangeDetectionStrategy, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthStore } from '../../core/auth.store';
import { supabase } from '../../core/supabase.client';

/**
 * Reiniciar la demo. Para grabarla muchas veces.
 *
 * ── POR QUÉ NO ESTÁ ENLAZADA DESDE NINGÚN SITIO ────────────────────────────
 *
 * Porque no es producto. Es utilería, y si apareciera en un menú alguien
 * acabaría preguntando qué hace ese botón en medio de la presentación.
 * Se llega escribiendo `/demo` y de ninguna otra forma.
 *
 * Pero **esconderla no es lo que la protege**. Una URL que no está enlazada se
 * encuentra igual; lo que la protege es que `reset_demo()` comprueba que eres
 * Admin, solo toca ids escritos a mano, y se apaga sola en cuanto exista un
 * pago real. Ver la cabecera de la migración `0064`.
 *
 * ── EL ASPECTO ES A PROPÓSITO ──────────────────────────────────────────────
 *
 * Deliberadamente sosa, monoespaciada, sin el lenguaje visual de Feventi. Si
 * pareciera una pantalla del producto, alguien podría creer que lo es. Una
 * herramienta interna tiene que parecer una herramienta interna.
 */
@Component({
  selector: 'fv-demo-reset',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink],
  template: `
    <div class="mx-auto max-w-[560px] font-mono">
      <p class="text-[11px] uppercase text-fg-subtle">utilería interna · no es producto</p>
      <h1 class="mt-1 text-xl font-bold">Reiniciar la demo</h1>

      @if (!auth.isAdmin()) {
        <p
          role="alert"
          class="mt-4 rounded-[--radius-chip] bg-danger-bg px-3 py-2.5 text-[13px] text-danger-fg"
        >
          Esta herramienta es solo para Admin. Entra con
          <b>operaciones&#64;feventi.demo</b>.
        </p>
        <p class="mt-4 text-[12.5px]">
          <a routerLink="/eventos" class="underline">Volver al catálogo</a>
        </p>
      } @else {
        <p class="mt-3 text-[13px] leading-relaxed text-fg-soft">
          Devuelve la utilería de «Zona Ritmo» a su estado sembrado. Úsalo entre toma
          y toma: sin esto, a la tercera grabación Camila llega a su tope de 6
          entradas por evento y el paso de compra falla con un mensaje de límite.
        </p>

        <ul class="mt-4 space-y-1.5 text-[12.5px] text-fg-soft">
          <li>· las entradas usadas vuelven a activas, y se borran los escaneos</li>
          <li>· Camila vuelve a 150 puntos y 2 entradas</li>
          <li>· se borran las compras y los grupos hechos en vivo</li>
          <li>· la solicitud de Joaquín vuelve a estar sin responder</li>
          <li>· Nadia vuelve a modo ninja</li>
          <li>· el evento se recoloca con las puertas recién abiertas</li>
        </ul>

        <div class="mt-6">
          @if (!confirmando()) {
            <button
              type="button"
              (click)="confirmando.set(true)"
              class="min-h-11 rounded-[--radius-inner] bg-ink px-5 text-[14px] font-bold text-white"
            >
              Reiniciar
            </button>
          } @else {
            <div class="flex flex-wrap items-center gap-3">
              <button
                type="button"
                (click)="reiniciar()"
                [disabled]="corriendo()"
                class="min-h-11 rounded-[--radius-inner] bg-danger-fg px-5 text-[14px] font-bold text-white disabled:opacity-50"
              >
                {{ corriendo() ? 'Reiniciando…' : 'Sí, borrar y reiniciar' }}
              </button>
              <button
                type="button"
                (click)="confirmando.set(false)"
                [disabled]="corriendo()"
                class="text-[13px] underline"
              >
                Cancelar
              </button>
            </div>
          }
        </div>

        @if (error(); as e) {
          <p
            role="alert"
            class="mt-4 rounded-[--radius-chip] bg-danger-bg px-3 py-2.5 text-[12.5px] text-danger-fg"
          >
            {{ e }}
          </p>
        }

        @if (resultado(); as r) {
          <div
            role="status"
            aria-live="polite"
            class="mt-4 rounded-[--radius-inner] border border-success-border bg-success-bg p-4 text-[12.5px] text-success-fg"
          >
            <p class="font-bold">Listo. La demo vuelve a estar como el guion la describe.</p>
            <dl class="mt-2.5 space-y-1">
              @for (f of filas(r); track f.k) {
                <div class="flex justify-between gap-4">
                  <dt>{{ f.k }}</dt>
                  <dd class="font-bold">{{ f.v }}</dd>
                </div>
              }
            </dl>
            <p class="mt-3 border-t border-success-border/40 pt-2.5">
              Recarga las pestañas que tuvieras abiertas: el navegador sigue enseñando
              lo de antes.
            </p>
          </div>
        }
      }
    </div>
  `,
})
export class DemoResetPage {
  protected readonly auth = inject(AuthStore);

  protected readonly confirmando = signal(false);
  protected readonly corriendo = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly resultado = signal<Record<string, unknown> | null>(null);

  /**
   * Dos clics, sin teclear nada. Es destructivo, así que un clic suelto no
   * basta — pero escribir «CONFIRMAR» entre toma y toma de una grabación sería
   * el tipo de fricción que hace que alguien deje de usar la herramienta.
   */
  protected async reiniciar(): Promise<void> {
    this.corriendo.set(true);
    this.error.set(null);
    this.resultado.set(null);

    const { data, error } = await supabase.rpc('reset_demo');
    this.corriendo.set(false);
    this.confirmando.set(false);

    if (error) {
      this.error.set(error.message);
      return;
    }
    this.resultado.set(data as Record<string, unknown>);
  }

  /** Del jsonb que devuelve la RPC a algo que se lea de un vistazo. */
  protected filas(r: Record<string, unknown>) {
    const nombres: Record<string, string> = {
      puntos_de_camila: 'puntos de Camila',
      entradas_de_camila: 'entradas activas',
      solicitudes_pendientes: 'solicitudes sin responder',
      checkins_borrados: 'escaneos borrados',
      ordenes_borradas: 'compras borradas',
      grupos_borrados: 'grupos borrados',
      puerta_abierta: 'ventana de puerta',
    };
    return Object.entries(nombres)
      .filter(([k]) => k in r)
      .map(([k, etiqueta]) => ({
        k: etiqueta,
        v: typeof r[k] === 'boolean' ? (r[k] ? 'abierta' : 'CERRADA') : String(r[k]),
      }));
  }
}
