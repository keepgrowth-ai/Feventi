import { ApplicationConfig, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter, withComponentInputBinding, withInMemoryScrolling } from '@angular/router';
import { routes } from './app.routes';

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideRouter(
      routes,

      // `withComponentInputBinding()` NO es opcional aquí, y su ausencia es
      // silenciosa: sin ella, un `input.required<string>()` enlazado a un
      // parámetro de ruta —`:slug`, `:id`, `:eventId`— simplemente no recibe
      // nada. No hay error, no hay aviso: el componente arranca con el valor
      // vacío y pide al servidor un recurso que no existe.
      //
      // Lo que se veía: el catálogo listaba «K-Pop Fest 2026», y al entrar salía
      // «Este evento no está disponible». La API respondía perfectamente —
      // comprobado con y sin sesión— porque el front nunca llegó a preguntar por
      // el slug correcto.
      //
      // Afectaba a las CUATRO pantallas con parámetro: el detalle público, el
      // checkout, el dashboard del organizador y el escáner de puerta. Ninguna
      // prueba lo detectó porque todas atacan la base o la API, no el router.
      withComponentInputBinding(),

      // Al navegar, arriba del todo; al volver atrás, donde estabas. Sin esto,
      // salir de un evento y volver al catálogo te deja en mitad de la lista
      // — que es exactamente donde no querías estar.
      withInMemoryScrolling({ scrollPositionRestoration: 'enabled', anchorScrolling: 'enabled' }),
    ),
  ],
};
