import { Component, ChangeDetectionStrategy, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { GateStore, type GateEvent } from './gate.store';

/**
 * «Mis eventos» — la primera pantalla del staff.
 *
 * La puerta y la fecha van GRANDES a propósito: operar el evento equivocado, o
 * la puerta equivocada, es el error más caro de la noche, y no se descubre hasta
 * que alguien reclama. Por lo mismo, cambiar de evento obliga a volver aquí: no
 * hay un selector dentro del escáner.
 *
 * Lo que se ve aquí sale de `v_my_gate_events`, que filtra por `auth.uid()` y
 * asignación viva. Si esta lista sale vacía no es un fallo: es que nadie ha
 * asignado a esta persona, o le revocaron el acceso.
 */
@Component({
  selector: 'fv-gate-eventos',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink],
  template: `
    <div class="mx-auto max-w-lg px-4 py-6">
      <h1 class="text-2xl font-black tracking-[-0.5px] text-white">Mis eventos</h1>
      <p class="mt-1 text-base text-white/60">
        Comprueba el evento y la puerta antes de empezar a escanear.
      </p>

      @if (store.error(); as e) {
        <p class="mt-4 rounded-[--radius-chip] bg-danger-fg px-3 py-3 text-base font-semibold text-white">
          {{ e }}
        </p>
      }

      <ul class="mt-5 space-y-3">
        @for (e of eventos(); track e.assignment_id) {
          <li>
            <a
              [routerLink]="['/puerta', e.event_id]"
              class="block rounded-[--radius-card] border-2 p-4 transition-colors"
              [class]="
                e.shift_active
                  ? 'border-turquoise/60 bg-white/10'
                  : 'border-white/15 bg-white/5'
              "
            >
              <div class="flex items-start justify-between gap-3">
                <div class="min-w-0">
                  <p class="truncate text-lg font-bold text-white">{{ e.title }}</p>
                  <p class="mt-0.5 text-base text-white/60">
                    {{ e.venue_name }}@if (e.venue_city) { · {{ e.venue_city }} }
                  </p>
                </div>
                <span
                  class="shrink-0 rounded-[--radius-pill] px-3 py-1 text-base font-bold"
                  [class]="e.shift_active ? 'bg-turquoise text-ink' : 'bg-white/15 text-white/70'"
                >
                  {{ e.shift_active ? 'En turno' : 'Fuera de turno' }}
                </span>
              </div>

              <!-- Lo que no se puede leer mal -->
              <div class="mt-3 grid grid-cols-2 gap-3">
                <div class="rounded-[--radius-inner] bg-black/30 px-3 py-2.5">
                  <p class="text-base text-white/50">Tu puerta</p>
                  <p class="text-2xl font-black text-white">{{ e.gate }}</p>
                  @if (e.zone_name) {
                    <p class="text-base text-white/60">solo {{ e.zone_name }}</p>
                  }
                </div>
                <div class="rounded-[--radius-inner] bg-black/30 px-3 py-2.5">
                  <p class="text-base text-white/50">Puertas</p>
                  <p class="text-2xl font-black text-white">{{ hora(e.doors_at ?? e.starts_at) }}</p>
                  <p class="text-base text-white/60">{{ fecha(e.starts_at) }}</p>
                </div>
              </div>

              @if (!e.shift_active) {
                <!-- Decir CUÁNDO, no solo que no. Si no, el staff reintenta. -->
                <p class="mt-3 text-base text-white/60">
                  El escáner se abre {{ desde(e) }}.
                </p>
              }
            </a>
          </li>
        } @empty {
          @if (!cargando()) {
            <li class="rounded-[--radius-card] border border-white/15 bg-white/5 p-6 text-center">
              <p class="text-lg font-bold text-white">No tienes eventos asignados</p>
              <p class="mt-1.5 text-base text-white/60">
                El organizador del evento te asigna a una puerta. Si deberías estar aquí,
                escríbele a quien te convocó.
              </p>
            </li>
          }
        }
      </ul>
    </div>
  `,
})
export class GateEventosPage {
  protected readonly store = inject(GateStore);
  protected readonly eventos = signal<readonly GateEvent[]>([]);
  protected readonly cargando = signal(true);

  constructor() {
    queueMicrotask(async () => {
      this.eventos.set(await this.store.myEvents());
      this.cargando.set(false);
    });
  }

  protected hora(iso: string | null): string {
    return iso
      ? new Date(iso).toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit', hour12: false })
      : '—';
  }

  protected fecha(iso: string | null): string {
    return iso
      ? new Date(iso).toLocaleDateString('es-PE', { weekday: 'short', day: 'numeric', month: 'short' })
      : 'sin fecha';
  }

  protected desde(e: GateEvent): string {
    if (!e.shift_from) return 'cuando el evento tenga fecha';
    const d = new Date(e.shift_from);
    return d > new Date()
      ? `el ${d.toLocaleDateString('es-PE', { day: 'numeric', month: 'long' })} a las ${this.hora(e.shift_from)}`
      : 'ya se cerró: el turno terminó';
  }
}
