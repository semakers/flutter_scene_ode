// Verifica el módulo wasm INSTANCIÁNDOLO, no leyendo el binario por fuera.
//
// Es la misma lección que dejó escrita ci_shared/verificar_compilador.sh: no
// mirar banderas ni ficheros intermedios, mirar el artefacto final como lo hará
// el consumidor. Aquí además es obligatorio, porque con -Oz emscripten minifica
// los nombres del export section del .wasm (h, i, j...) y quien los vuelve a
// nombrar es el glue JS. Lo que el shim de Dart va a tocar es exactamente esto.
//
// Uso:  node tool/wasm/verify_module.mjs <dir con ode.js> <lista de funciones>
//       node tool/wasm/verify_module.mjs <dir> <lista> --layout <salida.json>
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const dir = resolve(process.argv[2]);
const listaPath = process.argv[3];
const layoutOut = process.argv.includes('--layout')
  ? process.argv[process.argv.indexOf('--layout') + 1]
  : null;

const require = createRequire(import.meta.url);
const createNairdaOde = require(resolve(dir, 'ode.js'));

const Module = await createNairdaOde({
  // Los bytes se inyectan igual que hará Dart: sin locateFile, sin URLs.
  wasmBinary: readFileSync(resolve(dir, 'ode.wasm')),
});

let fallos = 0;
const fallo = (m) => { console.error(`  FALLA: ${m}`); fallos++; };

// --- 1. Que estén todas las funciones que los bindings buscan por nombre.
const esperadas = readFileSync(listaPath, 'utf8').split('\n').map(s => s.trim()).filter(Boolean);
for (const f of esperadas) {
  if (typeof Module['_' + f] !== 'function') fallo(`no se exporta ${f}`);
}
for (const f of ['malloc', 'free']) {
  if (typeof Module['_' + f] !== 'function') fallo(`no se exporta ${f}`);
}

// --- 2. addFunction, que es lo que da un puntero a función de C al callback de
//        dSpaceCollide. Sin él la física correría SIN contactos, en silencio.
if (typeof Module.addFunction !== 'function') {
  fallo('no se exporta addFunction (ALLOW_TABLE_GROWTH)');
} else {
  const p = Module.addFunction((a, b, c) => a + b + c, 'iiii');
  if (!p) fallo('addFunction devolvió un puntero nulo');
  Module.removeFunction(p);
}

// --- 3. Las vistas del heap, que es sobre lo que trabaja el shim.
for (const v of ['HEAPU8', 'HEAP32', 'HEAPU32', 'HEAPF32']) {
  if (!Module[v]) fallo(`no se exporta ${v}`);
}

// --- 4. PRECISIÓN SIMPLE. Los bindings tienen dReal = ffi.Float clavado y un
//        binario en doble precisión no da error de enlace: LEE BASURA.
const leerCadena = (ptr) => {
  let s = '', i = ptr;
  while (Module.HEAPU8[i]) s += String.fromCharCode(Module.HEAPU8[i++]);
  return s;
};
const conf = leerCadena(Module._nairda_ode_configuration());
if (!conf.includes('ODE_single_precision')) {
  fallo(`precisión equivocada: ${conf}`);
}

// --- 5. El layout de wasm32 (ILP32), medido por la sonda que va DENTRO del
//        módulo. Nombres y valores salen de la misma X-macro.
const n = Module._nairda_ode_layout_count();
const buf = Module._malloc(n * 4);
const escritos = Module._nairda_ode_layout(buf, n);
if (escritos !== n) fallo(`nairda_ode_layout devolvió ${escritos}, esperaba ${n}`);
const nombres = leerCadena(Module._nairda_ode_layout_names()).split('\n').filter(Boolean);
if (nombres.length !== n) fallo(`${nombres.length} nombres para ${n} valores`);
const layout = {};
for (let i = 0; i < n; i++) layout[nombres[i]] = Module.HEAP32[(buf >> 2) + i];
Module._free(buf);

// Lo que NO puede cambiar sin que alguien se entere.
if (layout['sizeof.dReal'] !== 4) fallo(`sizeof(dReal) = ${layout['sizeof.dReal']}, no 4`);
if (layout['sizeof.pointer'] !== 4) fallo(`sizeof(void*) = ${layout['sizeof.pointer']}, no 4 (¿no es wasm32?)`);

if (layoutOut) {
  writeFileSync(layoutOut, JSON.stringify(layout, null, 2) + '\n');
  console.log(`  layout -> ${layoutOut}`);
}

console.log(`  ${esperadas.length} funciones de ffigen + malloc/free, addFunction, ${conf}`);
console.log(`  wasm32: dContactGeom=${layout['sizeof.dContactGeom']} dContact=${layout['sizeof.dContact']} dMass=${layout['sizeof.dMass']} dSurfaceParameters=${layout['sizeof.dSurfaceParameters']}`);
if (fallos) { console.error(`ABORTA: ${fallos} fallos`); process.exit(1); }
