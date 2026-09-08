// Un backtick dentro de un `template:` de Angular cierra el literal de
// TypeScript a media frase.
//
// Lo desagradable es que el error NO menciona backticks. Sale «NG1001:
// Decorator argument must be literal», o «Cannot find name 'visual'», o pide
// una coma en un sitio donde no falta ninguna — así que se busca un rato en el
// lugar equivocado antes de mirar la comilla.
//
// Ha pasado TRES veces en este proyecto, siempre igual: escribiendo el nombre
// de un archivo entre comillas invertidas dentro de un comentario HTML del
// template. Esta comprobación existe para que no haya una cuarta.
//
//   node scripts/no-backticks-en-templates.mjs
//
// En los comentarios de un template se usan « », que además es lo que usa el
// resto de la documentación del proyecto.

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const raiz = 'apps/web/src';

function* ts(dir) {
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) yield* ts(p);
    else if (p.endsWith('.ts')) yield p;
  }
}

let malos = 0;
let mirados = 0;

for (const f of ts(raiz)) {
  const src = readFileSync(f, 'utf8');
  const i = src.indexOf('template: `');
  if (i < 0) continue;
  mirados++;

  const desde = i + 'template: `'.length;

  // El cierre de verdad es el backtick que va solo en su línea seguido de coma.
  // Cualquier backtick ANTES de ese punto está dentro del template y lo rompe.
  const cierre = src.indexOf('\n  `,', desde);
  const primero = src.indexOf('`', desde);

  if (cierre >= 0 && primero >= 0 && primero < cierre) {
    const linea = src.slice(0, primero).split('\n').length;
    const ctx = src.slice(Math.max(0, primero - 55), primero + 25).replace(/\n/g, ' ');
    console.error(`✗ ${f}:${linea}  backtick dentro del template`);
    console.error(`   …${ctx}…\n`);
    malos++;
  }
}

if (malos) {
  console.error(`${malos} archivo(s) rotos. En los comentarios del template usa « », no backticks.`);
  process.exit(1);
}
console.log(`✓ ${mirados} componentes revisados, ningún backtick dentro de un template`);
