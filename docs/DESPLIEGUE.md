# Desplegar Feventi

GitHub + Cloud Run para el front, Supabase para el backend.

> **Esto despliega una DEMO, no producción.** Los pagos están en sandbox
> (Art. 13) y la base tiene datos de prueba dentro. Al final del documento está
> lo que falta para abrir la venta de verdad — y no es código.

---

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
