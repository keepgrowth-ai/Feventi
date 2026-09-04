import {
  Component,
  ChangeDetectionStrategy,
  ElementRef,
  OnDestroy,
  effect,
  input,
  output,
  signal,
  viewChild,
} from '@angular/core';
import jsQR from 'jsqr';

/**
 * La cámara de la puerta.
 *
 * Decodifica con `jsqr` y no con `BarcodeDetector`, que sería lo nativo: esa API
 * no está en todos los navegadores que llega el staff con su propio teléfono, y
 * mantener dos caminos —nativo y librería— significa que uno de los dos solo se
 * prueba el día del evento. Un camino, probado.
 *
 * El bucle va a ~10 lecturas por segundo sobre un fotograma reducido a 480 px.
 * Leer a resolución completa a 60 fps calienta el teléfono y no encuentra un QR
 * antes; lo que ayuda es que la cámara enfoque, no que se decodifique más veces.
 *
 * > `ponytail:` sin linterna. Si la puerta está a oscuras y se ve que hace falta,
 * > se añade con `track.applyConstraints({ advanced: [{ torch: true }] })`, que
 * > es un botón y cuatro líneas. No se adelanta porque no todos los dispositivos
 * > lo soportan y habría que diseñar el caso de que no esté.
 */
@Component({
  selector: 'fv-qr-scanner',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="relative overflow-hidden rounded-[--radius-card] bg-black">
      <video
        #video
        class="block h-full w-full object-cover"
        playsinline
        muted
        aria-hidden="true"
      ></video>

      <!-- La mirilla. Da a la persona algo a lo que apuntar; sin ella el encuadre
           se hace a ojo y tarda más. -->
      <div class="pointer-events-none absolute inset-0 grid place-items-center">
        <div
          class="size-[62%] rounded-[--radius-card] border-4 transition-colors"
          [class]="paused() ? 'border-white/25' : 'border-white/80'"
        ></div>
      </div>

      @if (problema(); as p) {
        <div class="absolute inset-0 grid place-items-center bg-ink/90 p-5 text-center">
          <div>
            <p class="text-lg font-bold text-white">{{ p }}</p>
            <p class="mt-2 text-base text-white/70">
              Usa el modo DNI mientras tanto: no bloquea la puerta.
            </p>
          </div>
        </div>
      }
    </div>
  `,
})
export class QrScanner implements OnDestroy {
  /** Con el veredicto en pantalla no se sigue leyendo: sería escanear al siguiente. */
  readonly paused = input(false);
  readonly alto = input(300);

  readonly code = output<string>();

  protected readonly problema = signal<string | null>(null);

  private readonly video = viewChild.required<ElementRef<HTMLVideoElement>>('video');
  private stream?: MediaStream;
  private timer?: ReturnType<typeof setInterval>;
  private readonly lienzo = document.createElement('canvas');
  private ultimo = '';
  private ultimoEn = 0;

  constructor() {
    effect(() => {
      const el = this.video().nativeElement;
      el.style.height = `${this.alto()}px`;
      if (!this.stream) void this.arrancar(el);
    });
  }

  ngOnDestroy(): void {
    clearInterval(this.timer);
    // Sin esto la luz de la cámara se queda encendida al salir de la pantalla, y
    // el staff cree que sigue grabando.
    this.stream?.getTracks().forEach((t) => t.stop());
  }

  private async arrancar(el: HTMLVideoElement): Promise<void> {
    if (!navigator.mediaDevices?.getUserMedia) {
      this.problema.set('Este navegador no da acceso a la cámara.');
      return;
    }
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        // `environment`: la cámara trasera. Con la frontal el staff tendría que
        // dar la vuelta al teléfono en cada entrada.
        video: { facingMode: 'environment', width: { ideal: 1280 } },
        audio: false,
      });
      el.srcObject = this.stream;
      await el.play();
      this.timer = setInterval(() => this.leer(el), 100);
    } catch {
      // Permiso denegado, cámara ocupada o sin HTTPS. Los tres se arreglan igual
      // desde la puerta: seguir por DNI y avisar al supervisor.
      this.problema.set('Sin acceso a la cámara.');
    }
  }

  private leer(el: HTMLVideoElement): void {
    if (this.paused() || el.readyState < 2) return;

    // 480 px de ancho: suficiente para un QR de 51 caracteres a un palmo, y una
    // décima parte del trabajo que a resolución completa.
    const ancho = 480;
    const alto = Math.round((el.videoHeight / el.videoWidth) * ancho) || 480;
    this.lienzo.width = ancho;
    this.lienzo.height = alto;

    const ctx = this.lienzo.getContext('2d', { willReadFrequently: true });
    if (!ctx) return;
    ctx.drawImage(el, 0, 0, ancho, alto);

    const img = ctx.getImageData(0, 0, ancho, alto);
    const hallazgo = jsQR(img.data, ancho, alto, { inversionAttempts: 'dontInvert' });
    if (!hallazgo?.data) return;

    // Un QR en el encuadre se lee diez veces por segundo. Sin este freno, el
    // mismo código dispararía diez validaciones y nueve dirían YA UTILIZADO.
    const ahora = Date.now();
    if (hallazgo.data === this.ultimo && ahora - this.ultimoEn < 3000) return;
    this.ultimo = hallazgo.data;
    this.ultimoEn = ahora;

    this.code.emit(hallazgo.data);
  }
}
