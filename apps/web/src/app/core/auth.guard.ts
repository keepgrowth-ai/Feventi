import { inject } from '@angular/core';
import { Router, type CanActivateFn } from '@angular/router';
import { AuthStore, type AppRole } from './auth.store';

/**
 * Los guards son navegación, no seguridad (Art. 9.2). Evitan que alguien aterrice
 * en una pantalla que le va a devolver una lista vacía; lo que protege los datos
 * es la RLS.
 */

/** Espera a que la sesión inicial se resuelva antes de decidir. */
async function whenReady(auth: AuthStore): Promise<void> {
  if (auth.ready()) return;
  await new Promise<void>((resolve) => {
    const check = () => (auth.ready() ? resolve() : setTimeout(check, 20));
    check();
  });
}

export const authGuard: CanActivateFn = async (_route, state) => {
  const auth = inject(AuthStore);
  const router = inject(Router);
  await whenReady(auth);

  if (auth.isSignedIn()) return true;
  return router.createUrlTree(['/entrar'], { queryParams: { volver: state.url } });
};

export const roleGuard = (...roles: readonly AppRole[]): CanActivateFn => {
  return async (_route, state) => {
    const auth = inject(AuthStore);
    const router = inject(Router);
    await whenReady(auth);

    if (!auth.isSignedIn()) {
      return router.createUrlTree(['/entrar'], { queryParams: { volver: state.url } });
    }
    if (roles.some((r) => auth.roles().includes(r))) return true;

    return router.createUrlTree(['/']);
  };
};

/** Para /entrar y /registro: quien ya entró no vuelve al login. */
export const guestGuard: CanActivateFn = async () => {
  const auth = inject(AuthStore);
  const router = inject(Router);
  await whenReady(auth);

  return auth.isSignedIn() ? router.createUrlTree(['/']) : true;
};
