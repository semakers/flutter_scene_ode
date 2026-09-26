// El juez de NAVEGADOR: abre un build de web que hospede un mecano y comprueba
// que la física corre de verdad.
//
// Es el último eslabón, y hace falta porque todo lo anterior puede estar verde
// con la app enseñando la pantalla honesta: la carga de ODE es de fallo blando
// y un build sin física no se distingue de uno bueno mirándolo por fuera.
//
// El criterio es el mismo que en el device desde el primer día: las líneas
// `ode t=…s pen=… nc=…` de la telemetría, cero NaN, y los fps del `hud:`.
//
// Uso:
//   node tool/verify_web.mjs <directorio del build>  [--seconds 12] [--shot f.png]
//   node tool/verify_web.mjs http://...              (contra algo ya servido)
import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const arg = (n, d) => {
  const i = process.argv.indexOf('--' + n);
  return i > 0 ? process.argv[i + 1] : d;
};
const objetivo = process.argv[2];
const SEGUNDOS = Number(arg('seconds', 12));
const SHOT = arg('shot', null);

const TIPOS = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.json': 'application/json', '.wasm': 'application/wasm',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.ttf': 'font/ttf',
  '.otf': 'font/otf', '.bin': 'application/octet-stream',
  '.glb': 'model/gltf-binary', '.symbols': 'text/plain',
};

let servidor = null;
let url = objetivo;
if (!objetivo.startsWith('http')) {
  const raiz = path.resolve(objetivo);
  servidor = http.createServer((req, res) => {
    const limpio = decodeURIComponent(req.url.split('?')[0]);
    let f = path.join(raiz, limpio === '/' ? '/index.html' : limpio);
    if (!f.startsWith(raiz) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) {
      f = path.join(raiz, 'index.html');
    }
    // El Content-Type del .wasm importa: sin `application/wasm` el navegador no
    // puede compilarlo en streaming. Aquí los bytes van por wasmBinary, así que
    // no es crítico, pero un servidor de pruebas que miente sobre los tipos
    // esconde problemas que el servidor de verdad sí tendría.
    res.setHeader('Content-Type', TIPOS[path.extname(f)] ?? 'application/octet-stream');
    fs.createReadStream(f).pipe(res);
  });
  await new Promise((r) => servidor.listen(0, r));
  url = `http://127.0.0.1:${servidor.address().port}/`;
  console.log(`sirviendo ${raiz} en ${url}`);
}

const navegador = await chromium.launch();
// El locale va en el CONTEXTO, no en variables de entorno: esta caja tiene
// LANG=C.UTF-8 y el headless reporta `en-US@posix`, que revienta el
// Intl.Segmenter de Flutter y deja la página EN BLANCO. Parece un build roto y
// es la máquina de pruebas.
const ctx = await navegador.newContext({
  locale: 'es-MX',
  timezoneId: 'America/Mexico_City',
  viewport: { width: 1280, height: 800 },
});
const page = await ctx.newPage();

const consola = [];
page.on('console', (m) => consola.push(m.text()));
const errores = [];
page.on('pageerror', (e) => errores.push(String(e)));

await page.goto(url, { waitUntil: 'load' });
await page.waitForTimeout(8000);   // arranque + carga del .wasm + primer frame

// Armar y arrancar. Sin esto el mundo está vacío y en pausa, así que no hay
// telemetría que juzgar: el juez diría «no corre la física» de un build
// perfecto. Se pilota por el árbol de SEMÁNTICA y no por píxeles — Flutter web
// lo publica al pulsar su placeholder, y así cada botón es un nodo con su
// etiqueta en vez de una coordenada adivinada.
if (!process.argv.includes('--no-armar')) {
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(1200);
  const boton = async (etiqueta) => {
    // Reactivar la semántica antes de cada búsqueda: Flutter web la apaga sola
    // tras un rato sin uso, y después de cerrar un diálogo el árbol se
    // reconstruye. Sin esto, el botón «no existe» aunque esté en pantalla.
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await page.waitForTimeout(500);
    const n = await page.evaluate((e) => {
      // El nodo pulsable es el MÁS PEQUEÑO que lleva la etiqueta: el árbol trae
      // también contenedores cuya etiqueta es la concatenación de sus hijos.
      // La etiqueta puede venir en `aria-label` O en el texto del nodo, y el
      // texto de un contenedor es la CONCATENACIÓN del de sus hijos: el botón
      // de Play sale como «Ejecutar\nEjecutar» y no hay ningún nodo cuyo texto
      // sea «Ejecutar» a secas. Así que se busca por CONTIENE y se coge el más
      // pequeño, que es la regla que ya vale para el resto de esta app.
      const c = [...document.querySelectorAll('flt-semantics')]
        .filter((x) => (x.getAttribute('aria-label') || x.textContent || '').includes(e))
        .map((x) => x.getBoundingClientRect())
        .filter((r) => r.width > 0)
        .sort((a, b) => a.width * a.height - b.width * b.height);
      return c.length ? { x: c[0].x + c[0].width / 2, y: c[0].y + c[0].height / 2 } : null;
    }, etiqueta);
    if (!n) {
      // Con el diagnóstico puesto: un «no lo encuentro» sin decir qué SÍ hay
      // manda a depurar a ciegas, y el árbol de semántica cambia con cada
      // diálogo que se abre o se cierra.
      const hay = await page.evaluate(() => [...document.querySelectorAll('flt-semantics')]
        .map((x) => (x.getAttribute('aria-label') || x.textContent || '').trim())
        .filter((t) => t && t.length < 40));
      console.log(`  (no encontré «${etiqueta}»; hay: ${JSON.stringify(hay)})`);
      return false;
    }
    // Ratón de verdad, no element.click(): el gesto tiene que ser el de una
    // persona o el lienzo no se entera.
    await page.mouse.click(n.x, n.y);
    await page.waitForTimeout(1200);
    return true;
  };
  // «Añadir servo» abre un diálogo que pide el PIN, y el botón de confirmar
  // está deshabilitado hasta que se escribe uno. Sin rellenarlo no se añade la
  // pieza, no hay nada que simular y el juez diría «la física no corre» de un
  // build perfecto.
  if (await boton('Añadir servo')) {
    const escrito = await page.evaluate(() => {
      // El campo del PIN es el que está VACÍO: el del nombre viene con
      // «servo1» puesto.
      const vacio = [...document.querySelectorAll('input')].find((i) => !i.value);
      if (!vacio) return false;
      vacio.focus();
      return true;
    });
    if (escrito) {
      await page.keyboard.type('9');
      await page.waitForTimeout(600);
    }
    await boton('Añadir');
  }
  await boton('Ejecutar');
}

await page.waitForTimeout(SEGUNDOS * 1000);
if (SHOT) { await page.screenshot({ path: SHOT }); console.log(`captura -> ${SHOT}`); }

await navegador.close();
if (servidor) servidor.close();

// ---------------------------------------------------------------- veredicto
let fallos = 0;
const check = (ok, msg) => { console.log(`  ${ok ? 'ok  ' : 'FALLA'} ${msg}`); if (!ok) fallos++; };

const telemetria = consola.filter((l) => /\bode t=/.test(l));
const hud = consola.filter((l) => l.startsWith('hud:'));
const honesta = consola.some((l) => /no se pudo cargar ode\.wasm|no hay dart:ffi/.test(l));

console.log(`\n  ${consola.length} líneas de consola, ${telemetria.length} de telemetría, ${hud.length} de hud`);
for (const l of telemetria.slice(0, 3)) console.log(`    ${l}`);
for (const e of errores.slice(0, 5)) console.log(`    pageerror: ${e}`);
console.log();

check(errores.length === 0, `sin errores de página (${errores.length})`);
check(!honesta, 'ODE cargó (no salió el motivo de la pantalla honesta)');
check(telemetria.length > 0, 'la telemetría de ODE fluye: el paso de física CORRE');
check(!consola.some((l) => /NaN/.test(l)), 'cero NaN en toda la consola');

// `pen` es el diagnóstico que separa dos fallos parecidos: en sierra significa
// resonancia, creciente significa que algo se está hundiendo.
const pens = telemetria.map((l) => Number(/pen=([\d.]+)/.exec(l)?.[1] ?? NaN))
                       .filter(Number.isFinite);
if (pens.length) {
  check(Math.max(...pens) < 0.5, `la penetración se mantiene sana (máx ${Math.max(...pens).toFixed(3)})`);
}

const fps = hud.map((l) => Number(/fps (\d+)/.exec(l)?.[1] ?? NaN)).filter((n) => Number.isFinite(n) && n > 0);
if (fps.length) {
  const mediana = fps.sort((a, b) => a - b)[fps.length >> 1];
  const MIN = Number(arg('min-fps', 0));
  // Informativo por defecto, y a propósito: el Chromium headless de esta caja
  // rasteriza por software (SwiftShader), así que sus fps no dicen nada del
  // rendimiento real. Para juzgarlos hace falta un navegador con GPU —el de la
  // PC del laboratorio o el teléfono del usuario— y ahí se pasa --min-fps.
  console.log(`  fps mediana ${mediana} (${fps.length} muestras)${MIN ? '' : ' — informativo: headless rasteriza por software'}`);
  if (MIN) check(mediana >= MIN, `fps utilizables (mediana ${mediana} >= ${MIN})`);
}

console.log();
if (fallos) { console.error(`ABORTA: ${fallos} fallos`); process.exit(1); }
console.log('NAVEGADOR VERDE: el mecano tiene física en web.');
