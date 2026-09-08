// Trae las imágenes del catálogo y las guarda en el repositorio.
//
// ── POR QUÉ SE DESCARGAN Y NO SE ENLAZAN ───────────────────────────────────
//
// Enlazar a un servidor ajeno mete una dependencia de red en mitad de una
// demostración: si el wifi de la sala va mal o el otro servidor tarda, el
// catálogo sale con huecos. Se descargan una vez, se sirven desde nginx con el
// resto de la aplicación, y ya no dependen de nadie.
//
// ── DE DÓNDE SALEN ─────────────────────────────────────────────────────────
//
// **Openverse** (openverse.org, de WordPress) para eventos y locales: agrega
// imágenes con licencia Creative Commons, tiene API pública sin clave y —lo que
// decide— deja BUSCAR POR TÉRMINO. Un banco que solo da fotos aleatorias no
// sirve: un paisaje de montaña sobre «Noche de Stand Up» es peor que no poner
// nada. Se filtra por `license_type=commercial` para no traer nada con cláusula
// no-comercial.
//
// **randomuser.me** para los avatares. Son retratos publicados expresamente
// como datos de marcador, que es exactamente este caso: hacen falta caras
// reales sin colgarle la identidad a una persona concreta.
//
// **Pinterest no.** Son fotos con derechos de terceros y raspar el sitio va
// contra sus condiciones. Para un producto que se enseña a un inversor, eso es
// un riesgo que no compensa lo que aporta una foto.
//
// ── LA ATRIBUCIÓN NO ES OPCIONAL ───────────────────────────────────────────
//
// Se prefiere CC0 y dominio público, que NO deben crédito: así no hay forma de
// incumplirlos por descuido. Cuando no hay nada mejor se aceptan `by` y `by-sa`,
// que sí lo exigen. El autor, la licencia y el enlace al original de cada imagen
// quedan en `creditos.json`, y la aplicación los muestra en /creditos.
//
//   node scripts/traer-imagenes.mjs

import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const DESTINO = 'apps/web/public/img';
const UA = 'feventi-demo/1.0 (https://github.com/keepgrowth-ai/Feventi)';

/**
 * Varios términos por si el primero no da nada servible: «comedy club stage
 * microphone» devolvía resultados y ninguno descargable, y quedarse con un
 * hueco por no probar una segunda frase es tonto.
 */
const EVENTOS = [
  { archivo: 'zona-ritmo', q: ['music festival crowd night', 'festival stage lights crowd'] },
  { archivo: 'kpop-fest', q: ['concert stage lights audience', 'pop concert arena'] },
  {
    archivo: 'stand-up',
    q: ['stand up comedy microphone', 'microphone stage spotlight', 'comedian performing'],
  },
  { archivo: 'cumbia', q: ['live band concert musicians', 'latin music band playing'] },
];

// Los LOCALES se quitaron: ninguna pantalla muestra una foto del venue, así que
// descargarlas era dejar peso muerto en el repositorio. Si algún día la ficha
// del evento enseña el sitio, vuelven aquí con su término de búsqueda.

/**
 * Las cinco personas de la siembra, con su retrato fijado a mano.
 *
 * Se construye la URL directa en vez de pedirle una al azar a la API: con
 * `seed` salía una mujer para Diego, y un avatar que no case con el nombre es
 * de las cosas que alguien nota en una demo sin saber por qué le chirría.
 */
const PERSONAS = [
  { archivo: 'camila', url: 'https://randomuser.me/api/portraits/women/44.jpg' },
  { archivo: 'diego', url: 'https://randomuser.me/api/portraits/men/32.jpg' },
  { archivo: 'valeria', url: 'https://randomuser.me/api/portraits/women/68.jpg' },
  { archivo: 'nadia', url: 'https://randomuser.me/api/portraits/women/90.jpg' },
  { archivo: 'joaquin', url: 'https://randomuser.me/api/portraits/men/75.jpg' },
];

/** Por orden de preferencia: las dos primeras no deben crédito. */
const LICENCIAS_OK = ['cc0', 'pdm', 'by', 'by-sa'];

/** Ni miniatura pastosa ni foto que nadie espera a que cargue. */
const MIN_BYTES = 40_000;
const MAX_BYTES = 550_000;

async function buscarOpenverse(q) {
  const url =
    'https://api.openverse.org/v1/images/?' +
    new URLSearchParams({
      q,
      page_size: '20',
      license_type: 'commercial',
      // Horizontales: el hueco del catálogo es 16:9, y una foto vertical
      // recortada por el centro pierde justo lo que la hacía buena.
      aspect_ratio: 'wide',
      size: 'large',
      mature: 'false',
    });

  const r = await fetch(url, { headers: { 'User-Agent': UA } });
  if (!r.ok) throw new Error('openverse ' + r.status);
  const j = await r.json();
  return (j.results ?? [])
    .filter((x) => LICENCIAS_OK.includes(x.license))
    .sort((a, b) => LICENCIAS_OK.indexOf(a.license) - LICENCIAS_OK.indexOf(b.license));
}

/** Baja a memoria. No escribe: quien llama decide si el peso vale. */
async function bajar(url) {
  try {
    const r = await fetch(url, { headers: { 'User-Agent': UA }, redirect: 'follow' });
    if (!r.ok) return null;
    if (!(r.headers.get('content-type') ?? '').startsWith('image/')) return null;
    return Buffer.from(await r.arrayBuffer());
  } catch {
    return null;
  }
}

const espera = (ms) => new Promise((r) => setTimeout(r, ms));
const creditos = [];

async function traerGrupo(lista, carpeta) {
  mkdirSync(join(DESTINO, carpeta), { recursive: true });

  for (const { archivo, q } of lista) {
    let candidatos = [];

    for (const termino of q) {
      // Openverse limita el ritmo sin clave y devuelve 403 al tercer tirón
      // seguido. Esperar sale más barato que gestionar reintentos.
      await espera(2500);
      try {
        const r = await buscarOpenverse(termino);
        if (r.length) {
          candidatos = r;
          break;
        }
      } catch (e) {
        console.error('  · ' + archivo + ': ' + e.message + ' («' + termino + '»)');
      }
    }

    if (!candidatos.length) {
      console.error('  ✗ ' + archivo + ': sin candidatos');
      continue;
    }

    // Se acepta el PRIMER archivo cuyo peso esté en rango. Probar la grande y
    // «degradar» a la miniatura acababa restaurando la grande cuando la
    // miniatura tampoco valía; así es una sola regla y se entiende.
    let puesto = false;
    for (const c of candidatos) {
      for (const src of [c.url, c.thumbnail].filter(Boolean)) {
        const buf = await bajar(src);
        if (!buf || buf.length < MIN_BYTES || buf.length > MAX_BYTES) continue;

        writeFileSync(join(DESTINO, carpeta, archivo + '.jpg'), buf);
        creditos.push({
          archivo: 'img/' + carpeta + '/' + archivo + '.jpg',
          titulo: c.title ?? null,
          autor: c.creator ?? 'desconocido',
          licencia: (c.license ?? '').toUpperCase() + ' ' + (c.license_version ?? ''),
          original: c.foreign_landing_url ?? c.url,
        });
        console.log(
          '  ✓ ' + carpeta + '/' + archivo + '.jpg  ' +
          ((buf.length / 1024) | 0) + ' kB  ' + c.license + '  ' + (c.creator ?? ''),
        );
        puesto = true;
        break;
      }
      if (puesto) break;
    }
    if (!puesto) console.error('  ✗ ' + archivo + ': nada en rango de peso');
  }
}

async function traerAvatares() {
  mkdirSync(join(DESTINO, 'personas'), { recursive: true });
  for (const { archivo, url } of PERSONAS) {
    const buf = await bajar(url);
    if (!buf) {
      console.error('  ✗ ' + archivo);
      continue;
    }
    writeFileSync(join(DESTINO, 'personas', archivo + '.jpg'), buf);
    console.log('  ✓ personas/' + archivo + '.jpg  ' + ((buf.length / 1024) | 0) + ' kB');
  }
  creditos.push({
    archivo: 'img/personas/*.jpg',
    titulo: 'Retratos de marcador',
    autor: 'randomuser.me',
    licencia: 'Uso libre como datos de marcador',
    original: 'https://randomuser.me/',
  });
}

console.log('Eventos');
await traerGrupo(EVENTOS, 'eventos');
console.log('Personas');
await traerAvatares();

writeFileSync(join(DESTINO, 'creditos.json'), JSON.stringify(creditos, null, 2) + '\n');
console.log('\n' + creditos.length + ' entradas en creditos.json');
