import { Component, ChangeDetectionStrategy, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { AuthStore } from '../../core/auth.store';
import { Chip } from '../../shared/ui/chip';
import { EventVisual } from '../../shared/ui/event-visual';
import { SocialSignal } from '../../shared/ui/social-signal';
import { SocialStore, type EventSignal } from '../social/social.store';
import { soles } from '../../shared/ui/money';
import {
  PublicEventStore,
  demandBadge,
  type CatalogCursor,
  type CatalogEvent,
  type CatalogSort,
} from './public-event.store';

/**
 * Catálogo público. Es una proyección de 003: aquí no se define nada, solo se
 * muestra, filtra y pagina.
 *
 * Dos cosas del spec que no son cosméticas:
 *  - el «desde» va con la leyenda de que hay fases y cargos. Leerlo como precio
 *    final es el riesgo número uno de esta pantalla;
 *  - hay DOS estados vacíos distintos. «Ningún evento coincide con estos
 *    filtros» y «todavía no hay eventos publicados» dicen cosas opuestas, y
 *    confundirlos deja al visitante creyendo que Feventi está vacío.
 */
@Component({
  selector: 'fv-catalogo',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule, RouterLink, Chip, SocialSignal, EventVisual],
  template: `
    <!-- Destacado -->
    @if (featured(); as f) {
      <a
        [routerLink]="['/eventos', f.slug]"
        class="relative mb-6 block overflow-hidden rounded-[--radius-card] bg-navy p-7 text-white sm:p-8"
        [class]="grad(f)"
      >
        <div class="fv-hero-texture absolute inset-0"></div>
        <div class="relative">
          <span
            class="mb-3 inline-block rounded-[--radius-pill] bg-coral/20 px-2.5 py-1 text-[11px] font-semibold text-coral-200"
          >
            {{ f.category }} · {{ f.venue_city }}
          </span>
          <h2 class="text-[clamp(1.6rem,5.5vw,2rem)] font-black leading-[1.05] tracking-[-1px]">
            {{ f.title }}
          </h2>
          <p class="mt-2 text-[14px] text-white/70">
            {{ f.venue_name }}@if (f.starts_at) { · {{ longDate(f.starts_at) }} }
          </p>
          <div class="mt-3.5 flex flex-wrap items-center gap-2">
            @if (badge(f); as b) {
              <span
                class="rounded-[--radius-pill] px-2.5 py-1 text-[11px] font-bold"
                [class]="heroBadgeClass(b.tone)"
                >{{ b.text }}</span
              >
            }
            @if (f.from_price_cents != null) {
              <span
                class="rounded-[--radius-pill] bg-white/10 px-2.5 py-1 text-[11px] font-semibold"
                >desde {{ money(f.from_price_cents) }}</span
              >
            }
          </div>
        </div>
      </a>
    }

    <header class="mb-4">
      <h1 class="text-2xl font-black tracking-[-0.5px]">Eventos</h1>
      <p class="mt-1 text-[13px] text-fg-muted">
        Los precios se muestran con el cargo de servicio incluido cuando lo paga el fan. Cada
        evento puede tener varias fases de precio.
      </p>
    </header>

    <!-- Filtros -->
    <form class="mb-5 grid gap-2 sm:grid-cols-2 lg:grid-cols-4" (ngSubmit)="apply()">
      <input
        name="q"
        type="search"
        placeholder="Buscar evento, lugar o categoría"
        [(ngModel)]="form.search"
        (search)="apply()"
        class="rounded-[--radius-chip] border border-border bg-surface px-3 py-2 text-[13px] sm:col-span-2"
      />
      <select
        name="category"
        [(ngModel)]="form.category"
        (change)="apply()"
        class="rounded-[--radius-chip] border border-border bg-surface px-3 py-2 text-[13px]"
      >
        <option [ngValue]="null">Todas las categorías</option>
        @for (c of facets().categories; track c) {
          <option [ngValue]="c">{{ c }}</option>
        }
      </select>
      <select
        name="city"
        [(ngModel)]="form.city"
        (change)="apply()"
        class="rounded-[--radius-chip] border border-border bg-surface px-3 py-2 text-[13px]"
      >
        <option [ngValue]="null">Todas las ciudades</option>
        @for (c of facets().cities; track c) {
          <option [ngValue]="c">{{ c }}</option>
        }
      </select>
      <!-- 011 · mockup L92. Solo para quien tiene sesión: anon, por
           definición, no tiene amigos. Filtra sobre la lista ya cargada, sin
           ida y vuelta al servidor. -->
      @if (auth.isSignedIn()) {
        <label
          class="flex cursor-pointer items-center gap-2 rounded-[--radius-chip] border border-border bg-surface px-3 py-2 text-[13px]"
        >
          <input
            name="conAmigos"
            type="checkbox"
            [(ngModel)]="form.conAmigos"
            (change)="apply()"
            class="size-4 accent-violet"
          />
          Con amigos asistiendo
        </label>
      }
      <input
        name="from"
        type="date"
        [(ngModel)]="form.from"
        (change)="apply()"
        class="rounded-[--radius-chip] border border-border bg-surface px-3 py-2 text-[13px]"
      />
      <input
        name="to"
        type="date"
        [(ngModel)]="form.to"
        (change)="apply()"
        class="rounded-[--radius-chip] border border-border bg-surface px-3 py-2 text-[13px]"
      />
      <select
        name="sort"
        [(ngModel)]="form.sort"
        (change)="apply()"
        class="rounded-[--radius-chip] border border-border bg-surface px-3 py-2 text-[13px]"
      >
        <option value="date">Por fecha</option>
        <option value="price">Por precio</option>
        <option value="relevance">Destacados primero</option>
      </select>
      <label class="flex items-center gap-2 px-1 text-[13px]">
        <input
          name="onlyAvailable"
          type="checkbox"
          [(ngModel)]="form.onlyAvailable"
          (change)="apply()"
          class="size-4"
        />
        Solo con entradas
      </label>
    </form>

    @if (store.error(); as e) {
      <p class="mb-4 rounded-[--radius-chip] bg-danger-bg px-3 py-2 text-[13px] text-danger-fg">
        {{ e }}
      </p>
    }

    <!-- Cards -->
    <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      @for (e of visibles(); track e.id) {
        <a
          [routerLink]="['/eventos', e.slug]"
          class="flex flex-col overflow-hidden rounded-[--radius-card] border border-border bg-surface"
        >
          <!-- Si el organizador subió imagen, manda la suya. Si no —que es el
               caso del 90 % de los eventos reales— el cartel se genera a partir
               de la categoría. Ver «event-visual.ts». -->
          <div class="relative aspect-[16/9] overflow-hidden">
            @if (e.hero_image_url) {
              <img [src]="e.hero_image_url" [alt]="e.title" class="size-full object-cover" />
            } @else {
              <fv-event-visual [seed]="e.id" [category]="e.category" />
            }
            @if (badge(e); as b) {
              <span class="absolute right-2.5 top-2.5">
                <fv-chip [tone]="b.tone">{{ b.text }}</fv-chip>
              </span>
            }
          </div>
          <div class="flex flex-1 flex-col p-3.5">
            <h3 class="text-[15px] font-bold leading-tight">{{ e.title }}</h3>
            <p class="mt-1 text-[12.5px] text-fg-muted">
              {{ e.venue_name }}@if (e.venue_city) { · {{ e.venue_city }} }
            </p>
            @if (e.starts_at) {
              <p class="text-[12.5px] text-fg-muted">{{ longDate(e.starts_at) }}</p>
            }
            <!-- Sin la nota de ninja: en la tarjeta no cabe una segunda línea,
                 y sí cabe en la ficha, que es donde se decide comprar. -->
            @if (senales().get(e.id); as sn) {
              <div class="mt-1.5">
                <fv-social-signal
                  [going]="sn.friends_going"
                  [interested]="sn.friends_interested"
                  [goingNames]="sn.going_names"
                  [interestedNames]="sn.interested_names"
                />
              </div>
            }
            <div class="mt-auto pt-3">
              @if (e.from_price_cents != null) {
                <div class="flex items-baseline gap-1.5">
                  <span class="text-[11.5px] text-fg-muted">desde</span>
                  <span class="text-[17px] font-black tabular-nums">{{
                    money(e.from_price_cents)
                  }}</span>
                </div>
                <!-- Que el «desde» se lea como total es el riesgo nº1 de esta pantalla -->
                <p class="mt-0.5 text-[11px] text-fg-subtle">
                  Precio de la fase actual. Puede variar por zona y fase.
                </p>
              } @else if (e.next_phase_starts_at) {
                <p class="text-[12.5px] font-semibold text-warn-fg">
                  La venta abre el {{ shortDate(e.next_phase_starts_at) }}
                </p>
              } @else {
                <p class="text-[12.5px] font-semibold text-fg-muted">Venta cerrada</p>
              }
            </div>
          </div>
        </a>
      }
    </div>

    <!-- Dos estados vacíos, que dicen cosas opuestas -->
    @if (!rows().length && !store.loading()) {
      <div class="rounded-[--radius-card] border border-border bg-surface p-8 text-center">
        @if (filtered()) {
          <p class="text-[15px] font-bold">Ningún evento coincide con estos filtros</p>
          <p class="mt-1 text-[13px] text-fg-muted">Prueba con menos filtros o otra fecha.</p>
          <button
            type="button"
            (click)="clear()"
            class="mt-3 rounded-[--radius-chip] bg-coral px-4 py-2 text-[13px] font-bold text-white"
          >
            Limpiar filtros
          </button>
        } @else {
          <p class="text-[15px] font-bold">Todavía no hay eventos publicados</p>
          <p class="mt-1 text-[13px] text-fg-muted">
            Vuelve pronto. Si organizas eventos, puedes publicar el tuyo en Feventi.
          </p>
        }
      </div>
    }

    @if (cursor()) {
      <div class="mt-6 text-center">
        <button
          type="button"
          (click)="more()"
          [disabled]="store.loading()"
          class="rounded-[--radius-chip] border border-border bg-surface px-5 py-2.5 text-[13px] font-bold disabled:opacity-50"
        >
          {{ store.loading() ? 'Cargando…' : 'Ver más eventos' }}
        </button>
      </div>
    }
  `,
})
export class CatalogoPage {
  protected readonly store = inject(PublicEventStore);
  protected readonly auth = inject(AuthStore);
  private readonly social = inject(SocialStore);
  protected readonly money = soles;
  protected readonly badge = demandBadge;

  protected readonly rows = signal<readonly CatalogEvent[]>([]);
  protected readonly senales = signal<ReadonlyMap<string, EventSignal>>(new Map());
  protected readonly cursor = signal<CatalogCursor | null>(null);
  protected readonly facets = signal<{ categories: string[]; cities: string[] }>({
    categories: [],
    cities: [],
  });

  protected form = {
    search: '',
    category: null as string | null,
    city: null as string | null,
    from: '',
    to: '',
    sort: 'date' as CatalogSort,
    onlyAvailable: false,
    conAmigos: false,
  };

  /** Distingue «vacío por filtro» de «vacío de verdad». */
  protected readonly filtered = computed(
    () =>
      !!this.form.search ||
      !!this.form.category ||
      !!this.form.city ||
      !!this.form.from ||
      !!this.form.to ||
      this.form.onlyAvailable ||
      this.form.conAmigos,
  );

  /**
   * El filtro social se resuelve en el cliente, no en la consulta: el catálogo
   * es la misma vista pública que lee `anon`, y meterle un join social
   * obligaría a un left join que da null para la mitad del tráfico.
   */
  protected readonly visibles = computed(() =>
    this.form.conAmigos
      ? this.rows().filter((e) => this.senales().has(e.id))
      : this.rows(),
  );

  /** El destacado solo se pinta sin filtros: con filtros, estorba. */
  protected readonly featured = computed(() => {
    if (this.filtered()) return null;
    const rows = this.rows();
    return rows.find((e) => e.featured_at) ?? rows[0] ?? null;
  });

  constructor() {
    queueMicrotask(() => void this.init());
  }

  private async init(): Promise<void> {
    this.facets.set(await this.store.listFacets());
    await this.apply();
    // Después del catálogo y sin bloquearlo: la señal es un adorno (AC-18).
    if (this.auth.isSignedIn()) this.senales.set(await this.social.signals());
  }

  protected async apply(): Promise<void> {
    this.cursor.set(null);
    const page = await this.store.listCatalog(this.query(null));
    this.rows.set(page.rows);
    this.cursor.set(page.nextCursor);
  }

  protected async more(): Promise<void> {
    const c = this.cursor();
    if (!c) return;
    const page = await this.store.listCatalog(this.query(c));
    this.rows.update((r) => [...r, ...page.rows]);
    this.cursor.set(page.nextCursor);
  }

  protected async clear(): Promise<void> {
    this.form = {
      search: '',
      category: null,
      city: null,
      from: '',
      to: '',
      sort: 'date',
      onlyAvailable: false,
      conAmigos: false,
    };
    await this.apply();
  }

  private query(cursor: CatalogCursor | null) {
    return {
      search: this.form.search,
      category: this.form.category,
      city: this.form.city,
      from: this.form.from ? new Date(this.form.from).toISOString() : null,
      // El filtro «hasta» es un día inclusivo: quien pone 28 de agosto espera
      // ver lo del 28 de agosto a las 20:00.
      to: this.form.to ? new Date(this.form.to + 'T23:59:59').toISOString() : null,
      onlyAvailable: this.form.onlyAvailable,
      sort: this.form.sort,
      cursor,
    };
  }

  /** Uno de los seis gradientes del design system, estable por id. */
  protected grad(e: CatalogEvent): string {
    let h = 0;
    for (const ch of e.id) h = (h * 31 + ch.charCodeAt(0)) % 6;
    return `fv-grad-${h}`;
  }

  protected heroBadgeClass(tone: string): string {
    return (
      {
        success: 'bg-turquoise text-on-turquoise',
        warn: 'bg-amber text-warn-fg',
        danger: 'bg-coral text-white',
        info: 'bg-violet text-on-violet',
        neutral: 'bg-white/15 text-white',
      }[tone] ?? 'bg-white/15 text-white'
    );
  }

  protected longDate(iso: string): string {
    return new Date(iso).toLocaleString('es-PE', {
      day: 'numeric',
      month: 'long',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });
  }

  protected shortDate(iso: string): string {
    return new Date(iso).toLocaleDateString('es-PE', { day: 'numeric', month: 'long' });
  }
}
