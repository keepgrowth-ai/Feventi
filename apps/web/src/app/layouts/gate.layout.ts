import { Component, ChangeDetectionStrategy, signal } from '@angular/core';
import { RouterOutlet } from '@angular/router';

/**
 * Modo Puerta / Scanner (Art. 10 y 006).
 *
 * Se usa con una mano, con poca luz, con cola detrás. Alto contraste, nada por
 * debajo de 16 px, controles en la mitad inferior de la pantalla, cero
 * decoración.
 *
 * El aviso de conexión no es cosmético: sin red el escaneo se BLOQUEA (006,
 * AC-31). No se acumulan lecturas para enviarlas luego — un ticket validado que
 * después resulta inválido es peor que una cola.
 */
@Component({
  selector: 'fv-gate-layout',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterOutlet],
  host: { class: 'fv-gate block min-h-dvh' },
  template: `
    @if (!online()) {
      <div
        class="sticky top-0 z-50 bg-danger-fg px-4 py-3 text-center text-base font-bold text-white"
        role="alert"
      >
        Sin conexión — el escáner está bloqueado
      </div>
    }
    <router-outlet />
  `,
})
export class GateLayout {
  protected readonly online = signal(navigator.onLine);

  constructor() {
    addEventListener('online', () => this.online.set(true));
    addEventListener('offline', () => this.online.set(false));
  }
}
