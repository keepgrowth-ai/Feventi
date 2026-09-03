import type { Routes } from '@angular/router';
import { guestGuard } from './core/auth.guard';
import { FanLayout } from './layouts/fan.layout';

/**
 * Rutas en español: son URL que la gente comparte.
 *
 * Los guards son navegación, no seguridad (Art. 9.2): impiden aterrizar en una
 * pantalla que devolvería una lista vacía. Lo que protege los datos es la RLS.
 *
 * Las pantallas de 002-009 se van montando aquí a medida que cada feature cierra
 * su spec. Los `loadComponent` que faltan son deliberados, no un olvido.
 */
export const routes: Routes = [
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
        path: 'inicio',
        loadComponent: () => import('./features/home.page').then((m) => m.HomePage),
      },
      { path: '', pathMatch: 'full', redirectTo: 'inicio' },
    ],
  },

  // ── Pendientes, cada uno con su feature ──────────────────────────────────
  // 002  path: 'eventos'                 catálogo público
  // 003  path: 'eventos/:slug'           detalle de evento
  // 004  path: 'comprar/:orderId'        checkout            canActivate: [authGuard]
  // 005  path: 'entradas'                wallet y QR         canActivate: [authGuard]
  // 006  path: 'puerta'                  validador           GateLayout + roleGuard('staff')
  // 007  path: 'organizador/solicitudes' solicitud de evento roleGuard('organizer')
  //      path: 'admin/solicitudes'       aprobación          roleGuard('admin')
  // 008  path: 'organizador/:eventId'    dashboard           OpsLayout + roleGuard('organizer')
  // 009  path: 'soporte'                 casos               canActivate: [authGuard]

  { path: '**', redirectTo: '' },
];
