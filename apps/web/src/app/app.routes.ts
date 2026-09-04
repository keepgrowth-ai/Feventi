import type { Routes } from '@angular/router';
import { authGuard, guestGuard, roleGuard } from './core/auth.guard';
import { FanLayout } from './layouts/fan.layout';
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
      // 009  path: 'soporte'              mis casos       canActivate: [authGuard]
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
      { path: '', pathMatch: 'full', redirectTo: 'eventos' },

      // 008  path: 'eventos/:id/panel'    dashboard del evento
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
      { path: '', pathMatch: 'full', redirectTo: 'solicitudes' },

      // 009  path: 'soporte'              cola de casos
    ],
  },

  // ── Mundo Staff · modo Puerta ────────────────────────────────────────────
  // 006  path: 'puerta'  GateLayout + roleGuard('staff')

  { path: '**', redirectTo: '' },
];
