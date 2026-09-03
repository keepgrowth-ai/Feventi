import { Component, ChangeDetectionStrategy, inject, input } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { AuthStore } from '../core/auth.store';

export interface OpsTab {
  readonly label: string;
  readonly path: string;
}

/**
 * Modo Operación (Art. 10): profesional, ordenado, navy, cards blancas, tablas.
 * El color solo marca estado; nada decorativo.
 */
@Component({
  selector: 'fv-ops-layout',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  template: `
    <div class="min-h-dvh bg-bg">
      <header class="sticky top-0 z-50 bg-navy text-white">
        <div class="flex items-center justify-between gap-4 px-6 py-3">
          <div class="flex items-center gap-2.5">
            <span
              class="grid size-9 place-items-center rounded-[--radius-icon] bg-coral text-[18px] font-black"
              >F</span
            >
            <div>
              <div class="text-[18px] font-extrabold leading-tight tracking-[-0.5px]">FEVENTI</div>
              <div class="text-[11px] text-white/60">{{ subtitle() }}</div>
            </div>
          </div>
          <button
            type="button"
            (click)="auth.signOut()"
            class="rounded-[--radius-chip] bg-white/10 px-3 py-1.5 text-[12.5px] font-semibold"
          >
            Salir
          </button>
        </div>

        <nav class="flex gap-0.5 overflow-x-auto border-t border-white/10 px-4">
          @for (tab of tabs(); track tab.path) {
            <a
              [routerLink]="tab.path"
              routerLinkActive="border-coral text-white"
              class="whitespace-nowrap border-b-[3px] border-transparent px-3.5 py-2.5 text-[12.5px] font-medium text-white/65"
              >{{ tab.label }}</a
            >
          }
        </nav>
      </header>

      <main class="mx-auto max-w-[1180px] px-4 pb-16 pt-6">
        <router-outlet />
      </main>
    </div>
  `,
})
export class OpsLayout {
  readonly subtitle = input('');
  readonly tabs = input<readonly OpsTab[]>([]);
  protected readonly auth = inject(AuthStore);
}
