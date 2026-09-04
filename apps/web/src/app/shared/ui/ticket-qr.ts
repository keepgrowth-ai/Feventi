import {
  Component,
  ChangeDetectionStrategy,
  ElementRef,
  effect,
  input,
  viewChild,
} from '@angular/core';
import qrcode from 'qrcode-generator';

/**
 * El QR de un ticket, dibujado en canvas.
 *
 * **En `<canvas>`, no en `<img>`** (005/AC-19). Sin data URI, sin `href`
 * descargable y sin botón de compartir encima. Un `<img>` se guarda con clic
 * derecho en dos segundos, y el Art. 2.3 dice que una captura debe fallar en
 * puerta — así que la pantalla no debe facilitar la captura que luego rechaza.
 *
 * El encoder es `qrcode-generator`. Hubo un intento de escribir uno propio para
 * ahorrarse la dependencia; al contrastarlo contra esta librería, 429 de 1089
 * módulos salían distintos — no habría escaneado. Un QR que falla en la puerta,
 * con cola detrás, es lo más caro que puede romperse en este producto: no es
 * sitio para ahorrar 10 KB.
 */
@Component({
  selector: 'fv-ticket-qr',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <canvas
      #lienzo
      [width]="px()"
      [height]="px()"
      class="block rounded-[--radius-inner] bg-white"
      [style.width.px]="px()"
      [style.height.px]="px()"
      role="img"
      [attr.aria-label]="'Código QR de la entrada ' + label()"
    ></canvas>
  `,
})
export class TicketQr {
  /** El token del slot actual. Cambia cada 30 s. */
  readonly token = input.required<string>();
  readonly label = input('');
  readonly px = input(224);

  // Sin `.required`: así devuelve `undefined` en vez de lanzar, y el efecto
  // puede volver a intentarlo en el ciclo siguiente en lugar de romperse.
  private readonly lienzo = viewChild<ElementRef<HTMLCanvasElement>>('lienzo');

  constructor() {
    effect(() => {
      const texto = this.token();
      const size = this.px();

      // `viewChild.required()` LANZA si se lee antes de que exista el elemento,
      // y un error aquí deja el canvas en blanco sin decir por qué. El efecto
      // corre tras la detección de cambios, así que normalmente ya está — pero
      // «normalmente» no es «siempre», y este componente aparece dentro de un
      // `@if` que puede montarlo en mitad de un ciclo.
      //
      // Se lee el signal ANTES del try para que el efecto siga dependiendo de
      // él: dentro de un catch, la dependencia podría no registrarse y el QR no
      // se volvería a dibujar nunca al cambiar el token.
      const ref = this.lienzo();
      if (!ref) return;

      const canvas = ref.nativeElement;
      const ctx = canvas.getContext('2d');
      if (!ctx || !texto) return;

      // 0 = versión automática. 'M' = corrección media, el equilibrio habitual
      // para un código que se lee de una pantalla.
      const qr = qrcode(0, 'M');
      qr.addData(texto, 'Byte');
      qr.make();

      const n = qr.getModuleCount();
      // Zona de silencio: 4 módulos por norma. Sin ella muchos lectores fallan.
      const quiet = 4;
      const escala = Math.floor(size / (n + quiet * 2));
      const margen = Math.floor((size - escala * n) / 2);

      ctx.fillStyle = '#ffffff';
      ctx.fillRect(0, 0, size, size);
      ctx.fillStyle = '#09090B';
      for (let r = 0; r < n; r++) {
        for (let c = 0; c < n; c++) {
          if (qr.isDark(r, c)) {
            ctx.fillRect(margen + c * escala, margen + r * escala, escala, escala);
          }
        }
      }
    });
  }
}
