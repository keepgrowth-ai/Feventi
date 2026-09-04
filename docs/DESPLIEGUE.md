# Desplegar Feventi

GitHub + Cloud Run para el front, Supabase para el backend.

> **Esto despliega una DEMO, no producción.** Los pagos están en sandbox
> (Art. 13) y la base tiene datos de prueba dentro. Al final del documento está
> lo que falta para abrir la venta de verdad — y no es código.

---

> **Desplegado y verificado el 4 de septiembre de 2026** en
> `https://feventi-250048151842.us-central1.run.app`. Lo que salió por el camino
> está al final, en «Lo que costó la primera vez».

## 0. Antes de empezar

Necesitas:

- una cuenta de **GitHub**;
- un proyecto de **Google Cloud** con facturación activa (Cloud Run tiene capa
  gratuita, pero exige tarjeta);
- **gcloud CLI** — `https://cloud.google.com/sdk/docs/install`.

No hace falta Docker en tu máquina: la imagen la construye Cloud Build.

---

## 1. Subir a GitHub

El repo tiene commits desde el primer día, así que solo falta el remoto.

**Antes de nada**, comprueba que no se cuela ningún secreto:

```bash
cd C:/Users/Neo/Documents/Feventi

# Debe devolver SOLO líneas de documentación y comentarios explicando que no
# está en el bundle. Si aparece una clave de verdad, PARA.
grep -rn "service_role\|SUPABASE_SERVICE_ROLE" --include=*.ts --include=*.json apps/ | grep -v node_modules
```

La `publishable key` que verás en `environment.ts` **sí** va en el repo, y es
correcto: es pública por diseño. Lo que protege los datos es la RLS.

```bash
gh repo create feventi --private --source=. --remote=origin
git push -u origin main
```

O, sin `gh`:

```bash
git remote add origin https://github.com/<tu-usuario>/feventi.git
git branch -M main
git push -u origin main
```

> **Privado, no público.** Los specs describen decisiones de negocio, precios y
> comisiones. Nada de eso es un secreto técnico, pero tampoco tiene por qué
> estar indexado en Google.

---

## 2. Preparar Google Cloud

```bash
gcloud auth login
gcloud config set project TU_PROJECT_ID

gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com
```

Un repositorio para las imágenes:

```bash
gcloud artifacts repositories create feventi \
  --repository-format=docker \
  --location=southamerica-west1 \
  --description="Imágenes de Feventi"
```

> **`southamerica-west1` es Santiago**, y es la región más cercana a Lima con
> Cloud Run. Supabase está en `us-west-2` (Oregón), así que habrá un salto entre
> ambos de todas formas — pero el que importa es el del usuario al front, que es
> quien espera mirando la pantalla. Si prefieres tenerlo todo cerca de la base,
> usa `us-west1`.

---

## 3. Desplegar

Desde la raíz del repo:

```bash
gcloud run deploy feventi-web \
  --source . \
  --region southamerica-west1 \
  --allow-unauthenticated \
  --port 8080 \
  --memory 512Mi \
  --cpu 1 \
  --min-instances 0 \
  --max-instances 10
```

Tarda unos minutos la primera vez: sube el contexto, construye la imagen y la
publica. Al terminar imprime la URL, con esta forma:

```
https://feventi-web-XXXXXXXX-brs.a.run.app
```

**Anótala: la necesitas en el paso 4.**

Comprobaciones:

```bash
curl -s https://TU-URL.run.app/healthz          # → ok
curl -sI https://TU-URL.run.app/eventos | head -1   # → HTTP/2 200, no 404
```

La segunda es la que importa: si da **404**, el fallback de la SPA no está
funcionando y solo lo verías al recargar una página interna o al abrir un enlace
compartido — nunca navegando dentro de la app.

### Sobre `--allow-unauthenticated`

Suena a agujero y no lo es: significa «Cloud Run no pide credenciales de Google
para servir el HTML», que es lo que quieres en una web pública. La autenticación
de personas la hace Supabase, y lo que protege los datos es la RLS.

### Sobre `--min-instances 0`

Escala a cero cuando nadie entra, y eso ahorra dinero. El coste es el **arranque
en frío**: la primera visita tras un rato inactivo espera un par de segundos.

Para una demo está bien. **El día del evento, súbelo a 1**: el validador de
puerta no puede permitirse un arranque en frío con cola delante.

```bash
gcloud run services update feventi-web --region southamerica-west1 --min-instances 1
```

---

## 4. Conectar con Supabase

El front ya sabe a qué proyecto apunta —está en `environment.production.ts`— así
que **no hay que configurar nada del lado del código**. Lo que sí hay que hacer
es decirle a Supabase que confíe en el dominio nuevo.

### 4.1 Las URL de redirección · imprescindible

Sin esto, **registrarse o iniciar sesión falla en producción y funciona en
local**, que es la clase de fallo que cuesta una tarde encontrar.

En el panel de Supabase → **Authentication → URL Configuration**:

| campo | valor |
|---|---|
| **Site URL** | `https://TU-URL.run.app` |
| **Redirect URLs** | `https://TU-URL.run.app/**` <br> `http://localhost:4200/**` |

Los `/**` importan: el enlace de confirmación de correo vuelve a una ruta
concreta, no a la raíz. Y conserva `localhost` para poder seguir desarrollando.

### 4.2 CORS

**No hay que tocar nada.** PostgREST y las Edge Functions aceptan cualquier
origen: la petición se autoriza con la `apikey` y el JWT, no con el dominio.

### 4.3 Comprobar la conexión de verdad

Abre la URL y confirma **tres cosas**, en este orden:

1. **El catálogo carga eventos.** Prueba que `anon` llega a `v_event_public`.
2. **Puedes registrarte y te llega el correo**, y el enlace te devuelve a la app
   sin error. Esto prueba el paso 4.1.
3. **Con sesión, `/entradas` carga.** Prueba que el JWT viaja y que la RLS
   responde.

Si 1 funciona y 2 no, es la Site URL. Si 1 y 2 funcionan y 3 no, mira la consola
del navegador: probablemente sea la sesión, no la RLS.

---

## 5. Lo que queda pendiente en Supabase

Independiente del despliegue, y ya identificado:

| | qué | dónde |
|---|---|---|
| ⬜ | Desplegar `payment-webhook` | `supabase functions deploy payment-webhook` |
| ⬜ | Fijar `FEVENTI_WEBHOOK_SECRET` | `supabase secrets set FEVENTI_WEBHOOK_SECRET=…` |
| ⬜ | Subir la longitud mínima de contraseña a 12 | Authentication → Sign In / Providers → Email |
| ⬜ | Respaldo custodiado del pepper del DNI (**D-10**) | Vault → `dni_pepper` |

El último **no es opcional y no tiene marcha atrás**: si se pierde ese secreto,
todos los DNI hasheados quedan inservibles y no hay forma de recalcularlos. Cópialo
del SQL Editor a un gestor de contraseñas antes de que haya un solo dato real.

---

## 6. Despliegue continuo, si lo quieres

Cada `git push` a `main` reconstruye y despliega:

```bash
gcloud run deploy feventi-web \
  --source . \
  --region southamerica-west1 \
  --set-build-env-vars=_ \
  --async
```

O, mejor, con un disparador de Cloud Build conectado al repo:

```bash
gcloud builds triggers create github \
  --repo-name=feventi \
  --repo-owner=TU_USUARIO \
  --branch-pattern="^main$" \
  --build-config=cloudbuild.yaml
```

`cloudbuild.yaml` está en la raíz del repo.

> **Antes de automatizar, considera esto:** un despliegue automático a la misma
> URL que usa el validador de puerta significa que un push puede cambiar la app
> **durante un evento**. Si activas el disparador, apúntalo a un servicio de
> staging, no al que valida entradas esa noche.

---

## Lo que este despliegue NO es

Es una demo funcional. Para abrir la venta real falta:

**Lo que no es código:**

- La política de **reembolso, cancelación y retenciones** por escrito
  (**D-40…D-42**). Sin eso, cobrar dinero real significa cobrar sin haber
  decidido qué pasa cuando alguien pide que se lo devuelvas — y el sistema
  registra la petición pero no la resuelve.
- El **contrato con la pasarela** (Culqi u otra) y sus credenciales de
  producción. Hoy `payments.provider` vale `culqi_sandbox`, y está así a
  propósito (Art. 13).
- Las **51 decisiones abiertas** de `specs/decisiones-pendientes.md`, cada una
  con su default seguro anotado.

**Lo que sí es técnico:**

- Un **proyecto de Supabase nuevo y vacío** para producción. El actual tiene
  datos de demo mezclados con el schema, y limpiarlos a mano sobre datos
  mezclados es la forma más fácil de borrar lo que no tocaba. Se aplican las 51
  migraciones sobre uno limpio y se apunta `environment.production.ts` ahí.
- **Plan Pro** en Supabase: la protección contra contraseñas filtradas no existe
  en free (**D-50**).
- **Dominio propio** y correo transaccional con remitente verificado. El correo
  por defecto de Supabase tiene límite de envíos y acaba en spam.

**Y falta Fase 2 entera**: reventa oficial, cortesías, compras grupales y
finanzas reales están especificadas y sin construir — cuatro de los cinco mundos
del PDF. Fase 1 es lo necesario para vender y validar una entrada, no el
producto completo del documento.


---

## Lo que costó la primera vez

Cuatro fallos encadenados. Ninguno estaba en el código de la aplicación, y
ninguno daba un mensaje que apuntara al problema real.

### 1. Un build que falla sin dejar log

El trigger fallaba en 42 s y la consola decía «No logs were found for this
build», con tres motivos posibles. Ninguno era el correcto: la cuenta de
servicio **sí** tenía `logging.logWriter`.

Perseguir el log fue tiempo perdido. Lo que lo resolvió fue lanzar el build a
mano —`gcloud builds submit`— y leer el error en la terminal:

```
250048151842-compute@developer.gserviceaccount.com does not have
storage.objects.get access to ... buckets/feventi_cloudbuild
```

La cuenta no podía **leer el código fuente** que Cloud Build sube a Storage.
Fallaba antes de empezar a construir, y por eso no había nada que registrar.

```bash
gcloud projects add-iam-policy-binding feventi   --member="serviceAccount:250048151842-compute@developer.gserviceaccount.com"   --role="roles/storage.objectViewer"
```

> Cuando un build falla sin log, no busques el log: reproduce el build donde
> puedas ver la salida.

### 2. Alpine no sirve: Tailwind v4 usa un binario nativo

```
Error: Cannot find module '../lightningcss.linux-x64-musl.node'
```

Tailwind v4 compila el CSS con `lightningcss`, que se publica como binario por
plataforma. glibc y musl son incompatibles. Se cambió `node:22-alpine` por
`node:22-slim`.

La imagen final sigue siendo `nginx:alpine`, así que esto no engorda lo que se
despliega — solo la capa de construcción, que se descarta.

### 3. El `package-lock.json` solo tenía binarios de Windows

Con Debian el error cambió a `linux-x64-gnu`, y ahí se vio la causa de fondo: el
lock se generó en Windows y **no contiene una sola entrada `lightningcss-linux-*`**.

Ni `npm ci` ni `npm install` lo arreglan: los dos respetan lo que el lock dice.
La salida fue borrar el lock dentro del contenedor y dejar que npm resuelva para
Linux. Y con **npm 11**, porque el 10.9.8 que trae la imagen revienta al resolver
un workspace sin lock con un error que no dice nada:

```
npm error Cannot read properties of null (reading 'edgesOut')
```

> **Deuda anotada, no escondida:** las versiones ya no quedan clavadas al lock,
> sino a los rangos del `package.json`. La forma de recuperar `npm ci` es
> regenerar el lock en Linux y commitearlo — entonces tendría las entradas de
> ambas plataformas.

### 4. Las cabeceras de seguridad desaparecieron en silencio

El despliegue funcionaba, pero al comprobar las cabeceras faltaban las cuatro de
seguridad. Estaban escritas y no llegaban.

En nginx, **un `add_header` dentro de un `location` anula todos los del nivel
superior**. No se suman. Todo el HTML sale por un location con su propio
`Cache-Control`, así que perdía las demás.

`always` no arregla esto —solo hace que la cabecera se emita también en
errores—. La única salida es repetirlas en cada location que declare las suyas.

> Este es el que más miedo da de los cuatro: los otros tres rompen el build y se
> ven. Este desplegaba perfecto y dejaba la aplicación sin `X-Frame-Options`. Se
> encontró comprobando las cabeceras una por una, no mirando la página.

### Cómo quedó verificado

```
/          200      x-frame-options: DENY
/eventos   200      x-content-type-options: nosniff
/entradas  200      referrer-policy: strict-origin-when-cross-origin
/puerta    200      permissions-policy: camera=(self), ...

bundle     cache-control: public, immutable
index      cache-control: no-cache, must-revalidate

bundle apunta a Supabase   sí
production = true          sí
service_role en el bundle  NO          ← Art. 9.3
v_event_public desde anon  200
```
