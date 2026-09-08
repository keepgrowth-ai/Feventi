import { Component, ChangeDetectionStrategy, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { AuthStore } from '../../core/auth.store';

@Component({
  selector: 'fv-sign-in',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule, RouterLink],
  template: `
    <div class="mx-auto max-w-sm py-10">
      <h1 class="text-2xl font-black tracking-[-0.5px]">Entrar a Feventi</h1>
      <p class="mt-1.5 text-[13px] text-fg-muted">
        Tus entradas viven en tu wallet y el QR se muestra desde ahí.
      </p>

      <form class="mt-6 space-y-3" (ngSubmit)="submit()">
        <label class="block">
          <span class="text-[12px] font-semibold text-fg-soft">Email</span>
          <input
            name="email"
            type="email"
            required
            autocomplete="email"
            [(ngModel)]="email"
            class="mt-1 w-full rounded-[--radius-chip] border border-border bg-surface px-3 py-2.5 text-[14px]"
          />
        </label>

        @if (mode() === 'password') {
          <label class="block">
            <span class="text-[12px] font-semibold text-fg-soft">Contraseña</span>
            <input
              name="password"
              type="password"
              required
              autocomplete="current-password"
              [(ngModel)]="password"
              class="mt-1 w-full rounded-[--radius-chip] border border-border bg-surface px-3 py-2.5 text-[14px]"
            />
          </label>
        }

        @if (error(); as e) {
          <p role="alert" class="rounded-[--radius-chip] bg-danger-bg px-3 py-2 text-[13px] text-danger-fg">
            {{ e }}
          </p>
        }
        @if (sent()) {
          <p class="rounded-[--radius-chip] bg-success-bg px-3 py-2 text-[13px] text-success-fg">
            Te enviamos un enlace de acceso a {{ email }}. Revisa tu correo.
          </p>
        }

        <button
          type="submit"
          [disabled]="busy()"
          class="w-full rounded-[--radius-chip] bg-coral px-4 py-2.5 text-[14px] font-bold text-white disabled:opacity-50"
        >
          {{ busy() ? 'Un momento…' : mode() === 'password' ? 'Entrar' : 'Enviarme un enlace' }}
        </button>

        <button
          type="button"
          (click)="toggleMode()"
          class="w-full py-1 text-[12.5px] font-semibold text-coral-fg"
        >
          {{ mode() === 'password' ? 'Prefiero un enlace por correo' : 'Usar mi contraseña' }}
        </button>
      </form>

      <p class="mt-6 text-center text-[13px] text-fg-muted">
        ¿No tienes cuenta?
        <a routerLink="/registro" class="font-semibold text-coral-fg">Crear una</a>
      </p>
    </div>
  `,
})
export class SignInPage {
  private readonly auth = inject(AuthStore);
  private readonly router = inject(Router);

  protected email = '';
  protected password = '';
  protected readonly mode = signal<'password' | 'magic'>('password');
  protected readonly busy = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly sent = signal(false);

  protected toggleMode(): void {
    this.mode.update((m) => (m === 'password' ? 'magic' : 'password'));
    this.error.set(null);
    this.sent.set(false);
  }

  protected async submit(): Promise<void> {
    this.busy.set(true);
    this.error.set(null);
    this.sent.set(false);

    const { error } =
      this.mode() === 'password'
        ? await this.auth.signInWithPassword(this.email, this.password)
        : await this.auth.signInWithMagicLink(this.email);

    this.busy.set(false);

    if (error) {
      this.error.set(error.message);
      return;
    }
    if (this.mode() === 'magic') {
      this.sent.set(true);
      return;
    }

    const back = new URLSearchParams(location.search).get('volver');
    await this.router.navigateByUrl(back ?? '/');
  }
}
