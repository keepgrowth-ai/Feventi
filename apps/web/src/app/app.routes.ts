import type { Routes } from '@angular/router';
import { authGuard, guestGuard, roleGuard } from './core/auth.guard';
import { FanLayout } from './layouts/fan.layout';
import { GateLayout } from './layouts/gate.layout';
import { OpsLayout } from './layouts/ops.layout';

/**
 * Rutas en español: son URL que la gente comparte.
 *
 * Los guards son navegación, no seguridad (Art. 9.2): impiden aterrizar en una
 * pantalla que devolvería una lista vacía. Lo que protege los datos es la RLS.
 *
 * Las pantallas de 002-006, 008 y 009 se montan a medida que cada feature
 * cierra su spec. Los huecos comentados son deliberados, no un olvido.
 */
export const routes: Routes = [
  // ── Mundo Fan / Público ──────────────────────────────────────────────────
  {
    path: '',
    component: FanLayout,
    children: [
      {
        path: 'entrar',
        canActivate: [guestGuard],
        loadComponent: () => import('./features/auth/sign-in.page').then((m) => m.SignInPage),
      },
      {
        path: 'registro',
        canActivate: [guestGuard],
        loadComponent: () => import('./features/auth/sign-up.page').then((m) => m.SignUpPage),
      },
      {
        path: 'eventos',
        loadComponent: () =>
          import('./features/publico/catalogo.page').then((m) => m.CatalogoPage),
      },
      {
        path: 'eventos/:slug',
        loadComponent: () =>
          import('./features/publico/evento.page').then((m) => m.EventoPublicoPage),
      },
      // La raíz ES el catálogo. Una home de marca aparte, antes de tener eventos
      // que mostrar, es una pantalla que se diseña dos veces.
      { path: '', pathMatch: 'full', redirectTo: 'eventos' },

      {
        path: 'comprar/:id',
        canActivate: [authGuard],
        loadComponent: () =>
          import('./features/checkout/checkout.page').then((m) => m.CheckoutPage),
      },
      {
        path: 'entradas',
        canActivate: [authGuard],
        loadComponent: () => import('./features/wallet/wallet.page').then((m) => m.WalletPage),
      },
      {
        path: 'soporte',
        canActivate: [authGuard],
        loadComponent: () => import('./features/soporte/mis-casos.page').then((m) => m.MisCasosPage),
      },
    ],
  },

  // ── Mundo Organizador · modo Operación (Art. 10) ─────────────────────────
  {
    path: 'organizador',
    component: OpsLayout,
    canActivate: [roleGuard('organizer')],
    children: [
      {
        path: 'eventos',
        loadComponent: () =>
          import('./features/organizador/solicitudes.page').then((m) => m.OrgSolicitudesPage),
      },
      {
        path: 'eventos/:id/zonas',
        loadComponent: () =>
          import('./features/organizador/zonas.page').then((m) => m.OrgZonasPage),
      },
      {
        path: 'eventos/:id',
        loadComponent: () =>
          import('./features/organizador/evento-form.page').then((m) => m.OrgEventoFormPage),
      },
      {
        path: 'eventos/:id/panel',
        loadComponent: () =>
          import('./features/organizador/dashboard.page').then((m) => m.OrgDashboardPage),
      },
      { path: '', pathMatch: 'full', redirectTo: 'eventos' },
    ],
  },

  // ── Mundo Admin · modo Operación ─────────────────────────────────────────
  {
    path: 'admin',
    component: OpsLayout,
    canActivate: [roleGuard('admin')],
    children: [
      {
        path: 'solicitudes',
        loadComponent: () =>
          import('./features/admin/solicitudes.page').then((m) => m.AdminSolicitudesPage),
      },
      {
        path: 'solicitudes/:id',
        loadComponent: () =>
          import('./features/admin/solicitud-detalle.page').then(
            (m) => m.AdminSolicitudDetallePage,
          ),
      },
      {
        path: 'soporte',
        loadComponent: () => import('./features/admin/soporte.page').then((m) => m.AdminSoportePage),
      },
      { path: '', pathMatch: 'full', redirectTo: 'solicitudes' },
    ],
  },

  // ── Mundo Staff · modo Puerta ────────────────────────────────────────────
  //
  // `authGuard` y NO `roleGuard('staff')`: ser staff no es un rol global, es una
  // asignación POR EVENTO en `event_staff`. La misma persona es staff del
  // festival del sábado y no lo es del concierto del domingo, así que no hay un
  // rol que comprobar aquí. Quien no esté asignado a nada ve «Mis eventos»
  // vacío, con el texto que explica por qué — y `qr-validate` le da 403 aunque
  // llegue a la pantalla, que es donde de verdad se decide.
  {
    path: 'puerta',
    component: GateLayout,
    canActivate: [authGuard],
    children: [
      {
        path: ':eventId',
        loadComponent: () =>
          import('./features/puerta/scanner.page').then((m) => m.GateScannerPage),
      },
      {
        path: '',
        loadComponent: () =>
          import('./features/puerta/mis-eventos.page').then((m) => m.GateEventosPage),
      },
    ],
  },

  { path: '**', redirectTo: '' },
];
