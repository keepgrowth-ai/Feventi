import { Component, ChangeDetectionStrategy, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { AuthStore } from '../../core/auth.store';

/**
 * El perfil y el rol `fan` los crea el trigger `on_auth_user_created`
 * (001, AC-01/AC-02). Esta pantalla no inserta ninguna fila.
 */
@Component({
  selector: 'fv-sign-up',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule, RouterLink],
  template: `
    <div class="mx-auto max-w-sm py-10">
      <h1 class="text-2xl font-black tracking-[-0.5px]">Crear cuenta</h1>
      <p class="mt-1.5 text-[13px] text-fg-muted">
        Necesitas una cuenta para guardar tus entradas y mostrar tu QR en puerta.
      </p>

      <form class="mt-6 space-y-3" (ngSubmit)="submit()">
        <label class="block">
          <span class="text-[12px] font-semibold text-fg-soft">Nombre completo</span>
          <input
            name="fullName"
            required
            autocomplete="name"
            [(ngModel)]="fullName"
            class="mt-1 w-full rounded-[--radius-chip] border border-border bg-surface px-3 py-2.5 text-[14px]"
          />
        </label>
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
        <label class="block">
          <span class="text-[12px] font-semibold text-fg-soft">Contraseña</span>
          <input
            name="password"
            type="password"
            required
            minlength="8"
            autocomplete="new-password"
            [(ngModel)]="password"
            class="mt-1 w-full rounded-[--radius-chip] border border-border bg-surface px-3 py-2.5 text-[14px]"
          />
          <span class="mt-1 block text-[11px] text-fg-muted">Mínimo 8 caracteres.</span>
        </label>

        @if (error(); as e) {
          <p role="alert" class="rounded-[--radius-chip] bg-danger-bg px-3 py-2 text-[13px] text-danger-fg">
            {{ e }}
          </p>
        }
        @if (sent()) {
          <p class="rounded-[--radius-chip] bg-success-bg px-3 py-2 text-[13px] text-success-fg">
            Cuenta creada. Confirma tu correo para entrar.
          </p>
        }

        <button
          type="submit"
          [disabled]="busy()"
          class="w-full rounded-[--radius-chip] bg-coral px-4 py-2.5 text-[14px] font-bold text-white disabled:opacity-50"
        >
          {{ busy() ? 'Un momento…' : 'Crear cuenta' }}
        </button>
      </form>

      <p class="mt-6 text-center text-[13px] text-fg-muted">
        ¿Ya tienes cuenta? <a routerLink="/entrar" class="font-semibold text-coral-fg">Entrar</a>
      </p>
    </div>
  `,
})
export class SignUpPage {
  private readonly auth = inject(AuthStore);
  private readonly router = inject(Router);

  protected fullName = '';
  protected email = '';
  protected password = '';
  protected readonly busy = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly sent = signal(false);

  protected async submit(): Promise<void> {
    this.busy.set(true);
    this.error.set(null);

    const { data, error } = await this.auth.signUp(this.email, this.password, this.fullName);
    this.busy.set(false);

    if (error) {
      this.error.set(error.message);
      return;
    }
    // Con confirmación de correo activada no hay sesión todavía.
    if (data.session) await this.router.navigateByUrl('/');
    else this.sent.set(true);
  }
}
