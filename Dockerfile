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
#
# Debian (`slim`), no Alpine. Tailwind v4 compila el CSS con `lightningcss`, que
# es un binario NATIVO, y publica una variante por plataforma: glibc y musl son
# incompatibles entre sí. Debian usa glibc, que es donde esos binarios están
# mejor cubiertos. Con Alpine el build muere así:
#
#     Error: Cannot find module '../lightningcss.linux-x64-musl.node'
#
# La imagen final sigue siendo nginx-alpine, así que esto no engorda lo que se
# despliega: solo la capa de construcción, que se descarta.
FROM node:22-slim AS build
WORKDIR /app

# Las dependencias primero, y solo los manifiestos: así Docker reutiliza esta
# capa mientras no cambien, que es casi siempre. Copiar todo de golpe obliga a
# reinstalar en cada cambio de código.
COPY package.json package-lock.json ./
COPY apps/web/package.json apps/web/

# Se BORRA el lock antes de instalar, y esto es una concesión consciente.
#
# El `package-lock.json` se generó en Windows, y npm dejó dentro solo los
# binarios de win32: no hay una sola entrada `lightningcss-linux-*`. Con el lock
# presente, ni `npm ci` ni `npm install` traen el binario que falta — `install`
# también lo respeta y da por buena la resolución que hay escrita. El build
# muere al compilar el CSS:
#
#     Error: Cannot find module '../lightningcss.linux-x64-gnu.node'
#
# Sin lock, npm resuelve desde cero para la plataforma en la que corre y baja la
# variante de Linux. El coste es real y conviene decirlo: las versiones ya no
# quedan clavadas al lock, sino a los rangos del `package.json` — dos builds
# separados en el tiempo pueden traer parches distintos.
#
# La forma de recuperar `npm ci` es regenerar el lock EN Linux y commitearlo:
# entonces tendría las entradas de las dos plataformas y las dos rutas
# funcionarían. Mientras el desarrollo sea solo en Windows, esto es lo que hay.
# Y con npm 11, no con el 10.9.8 que trae la imagen: resolver un workspace sin
# lock revienta en el 10 con un error que no dice nada de lo que pasa —
# `Cannot read properties of null (reading 'edgesOut')`. El proyecto ya declara
# `packageManager: npm@11.12.1`, así que esto solo lo hace efectivo aquí.
RUN npm install -g npm@11 \
 && rm -f package-lock.json \
 && npm install --no-audit --no-fund

COPY apps/web apps/web
# La comprobación de backticks corre ANTES de compilar, así que su script tiene
# que estar en la imagen. Sin esta línea, `build:prod` falla aquí con un
# «Cannot find module» y el despliegue se cae por el guardarraíl en vez de por
# el fallo que el guardarraíl busca.
COPY scripts scripts

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
