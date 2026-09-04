# Feventi — el front, para Cloud Run.
#
# Es una SPA estática: Angular compila a HTML, JS y CSS, y nginx los sirve. No
# hay servidor de aplicación porque no hace falta — todo lo que necesita
# privilegio vive en Supabase (RLS) o en una Edge Function, nunca aquí.
#
# Eso tiene una consecuencia que conviene tener presente: **este contenedor no
# guarda ningún secreto**. La `publishable key` que lleva dentro es pública por
# diseño. Si alguien descarga la imagen entera, no obtiene nada que no tuviera ya
# abriendo el navegador.

# ── 1. Construir ────────────────────────────────────────────────────────────
FROM node:22-alpine AS build
WORKDIR /app

# Las dependencias primero, y solo los manifiestos: así Docker reutiliza esta
# capa mientras no cambien, que es casi siempre. Copiar todo de golpe obliga a
# reinstalar en cada cambio de código.
COPY package.json package-lock.json ./
COPY apps/web/package.json apps/web/
RUN npm ci

COPY apps/web apps/web
# `build:prod` es un SCRIPT, no `build -- --configuration production`. Pasar el
# flag a través de un workspace lo convierte en `ng build production`, que ng
# interpreta como nombre de proyecto y falla. Lo destapó escribir este
# Dockerfile, antes de llegar a Cloud Build.
#
# Y esto es lo que activa el fileReplacements de environment.production.ts: sin
# ello el bundle sale con `production: false`, que no rompe nada visible hoy
# pero deja el entorno mintiendo.
RUN npm run build:prod

# ── 2. Servir ───────────────────────────────────────────────────────────────
FROM nginx:1.27-alpine

# Angular 22 emite a dist/web/browser: solo el navegador, sin bundle de servidor.
COPY --from=build /app/apps/web/dist/web/browser /usr/share/nginx/html
COPY nginx.conf /etc/nginx/templates/default.conf.template

# Cloud Run inyecta el puerto en $PORT y no garantiza que sea 8080. La imagen de
# nginx procesa las plantillas de /etc/nginx/templates con envsubst al arrancar,
# así que el puerto se resuelve en ese momento en vez de quedar fijo.
ENV PORT=8080
EXPOSE 8080

# Cloud Run detiene el contenedor con SIGTERM. nginx interpreta esa señal como
# «apagado rápido»: corta las conexiones vivas en lugar de esperarlas. Con
# `quit` termina de servir lo que tiene entre manos, que es lo que se quiere
# durante un despliegue.
STOPSIGNAL SIGQUIT

CMD ["nginx", "-g", "daemon off;"]
