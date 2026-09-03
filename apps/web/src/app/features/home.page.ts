import { Component, ChangeDetectionStrategy, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthStore } from '../core/auth.store';
import { Chip } from '../shared/ui/chip';

/**
 * Provisional. La home real de Fase 1 es el catálogo (002), y este archivo
 * desaparece cuando 002 monte su ruta. Existe para que el esqueleto de 001 se
 * pueda ver y probar con una sesión real.
 */
@Component({
  selector: 'fv-home',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Chip],
  template: `
    <section class="fv-grad-brand relative overflow-hidden rounded-[--radius-card] p-8 text-white">
      <div class="fv-hero-texture absolute inset-0"></div>
      <div class="relative">
        <h1 class="text-[32px] font-black leading-[1.05] tracking-[-1px]">
          Feventi — ticketera de eventos
        </h1>
        <p class="mt-2 max-w-lg text-[14px] text-white/85">
          Descubre eventos, compra entradas, guárdalas en tu wallet y muestra tu QR en puerta.
        </p>
      </div>
    </section>

    <div class="mt-6 rounded-[--radius-card] border border-border bg-surface p-5">
      <div class="flex items-center gap-2">
        <h2 class="text-[18px] font-extrabold tracking-[-0.5px]">Estado del proyecto</h2>
        <fv-chip tone="success" [dot]="true">001 Fundaciones</fv-chip>
      </div>

      @if (auth.isSignedIn()) {
        <dl class="mt-4 grid gap-2 text-[13px] sm:grid-cols-2">
          <div class="flex justify-between gap-4 border-b border-border py-1.5">
            <dt class="text-fg-muted">Sesión</dt>
            <dd class="font-semibold">{{ auth.profile()?.email }}</dd>
          </div>
          <div class="flex justify-between gap-4 border-b border-border py-1.5">
            <dt class="text-fg-muted">Nombre</dt>
            <dd class="font-semibold">{{ auth.profile()?.full_name ?? '—' }}</dd>
          </div>
          <div class="flex justify-between gap-4 border-b border-border py-1.5">
            <dt class="text-fg-muted">Roles</dt>
            <dd class="font-semibold">{{ auth.roles().join(', ') || '—' }}</dd>
          </div>
          <div class="flex justify-between gap-4 border-b border-border py-1.5">
            <dt class="text-fg-muted">DNI</dt>
            <dd class="font-mono font-semibold">
              @if (auth.hasDni()) {
                ••••{{ auth.profile()?.dni_last4 }}
              } @else {
                sin declarar
              }
            </dd>
          </div>
        </dl>
        <p class="mt-4 text-[12px] text-fg-muted">
          El hash del DNI no es legible desde aquí ni por ti: vive en
          <code class="font-mono">profile_identity</code>, con RLS activa y sin políticas
          (Art. 7.1).
        </p>
      } @else {
        <p class="mt-3 text-[13px] text-fg-muted">
          Sin sesión. <a routerLink="/entrar" class="font-semibold text-coral">Entrar</a> para ver
          el perfil y los roles que resuelve la base.
        </p>
      }
    </div>

    <p class="mt-6 text-[12px] text-fg-subtle">
      Las pantallas de catálogo, evento, checkout, wallet, puerta, dashboard y soporte se montan
      con sus features 002-009. Ver <code class="font-mono">specs/roadmap.md</code>.
    </p>
  `,
})
export class HomePage {
  protected readonly auth = inject(AuthStore);
}
