// EL JUEZ DE LA FASE 2: ODE corriendo de verdad dentro de wasm, CERO Dart.
//
// Ejercita de una vez todo lo que puede desmentir la hipótesis, y por 1/20 del
// coste de llegar hasta el navegador: compilar, enlazar, malloc, el layout de
// wasm32, addFunction (el puntero a función de C que necesita dSpaceCollide) y
// el solver. Si esto sale verde, lo que quede por fallar es plomería de Dart.
//
// Corre contra la variante PARANOICA (ASSERTIONS=2 + SAFE_HEAP), que es la que
// convierte «la física va rara» en un aborto con dirección.
//
// Uso: node tool/wasm/freefall.mjs <dir con ode.js>
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const dir = resolve(process.argv[2]);
const require = createRequire(import.meta.url);
const M = await (require(resolve(dir, 'ode.js')))({
  wasmBinary: readFileSync(resolve(dir, 'ode.wasm')),
});

const L = JSON.parse(readFileSync(new URL('../ode_wasm_layout.json', import.meta.url), 'utf8'));
const F = (p) => M.HEAPF32[p >> 2];          // dReal es float: precisión simple
const setF = (p, v) => { M.HEAPF32[p >> 2] = v; };
const setI = (p, v) => { M.HEAP32[p >> 2] = v; };

let fallos = 0;
const check = (ok, msg) => { console.log(`  ${ok ? 'ok  ' : 'FALLA'} ${msg}`); if (!ok) fallos++; };

M._dInitODE2(0);

const world = M._dWorldCreate();
const space = M._dHashSpaceCreate(0);
const group = M._dJointGroupCreate(0);
// El MISMO tuning que OdeSimulation, línea por línea: un banco que configura
// otro mundo mide otra física y sus umbrales no significarían nada.
M._dWorldSetGravity(world, 0, -9.81, 0);
M._dWorldSetCFM(world, 1e-5);
M._dWorldSetERP(world, 0.2);
M._dWorldSetQuickStepNumIterations(world, 40);
M._dWorldSetContactSurfaceLayer(world, 0.001);
M._dWorldSetContactMaxCorrectingVel(world, 1.0);
M._dWorldSetAutoDisableFlag(world, 1);
M._dWorldSetAutoDisableLinearThreshold(world, 0.08);
M._dWorldSetAutoDisableAngularThreshold(world, 0.08);

// El suelo: un plano y=0. dCreatePlane es una de las cinco funciones que los
// bindings declaran y OdeSimulation no usa (allí el suelo es una caja); aquí
// viene de perlas y de paso prueba que exportarla sirvió de algo.
M._dCreatePlane(space, 0, 1, 0, 0);

// La esfera. UNIDADES DEL MECANO: 1 u ≈ 1 cm y las masas en GRAMOS (con masas
// en kg los multiplicadores del solver quedan al nivel del CFM y todo se
// vuelve gelatina resonante — la lección más cara del spike).
const R = 1.0;
const body = M._dBodyCreate(world);
const mass = M._malloc(L['sizeof.dMass']);
M._dMassSetSphereTotal(mass, 100.0, R);
M._dBodySetMass(body, mass);
const geom = M._dCreateSphere(space, R);
M._dGeomSetBody(geom, body);
M._dBodySetPosition(body, 0, 10, 0);

// --- El callback de colisión, que es LA pieza que sólo existe si
//     ALLOW_TABLE_GROWTH + addFunction funcionan.
const MAX = 8;
const geoms = M._malloc(MAX * L['sizeof.dContactGeom']);
const contact = M._malloc(L['sizeof.dContact']);
let vecesLlamado = 0, contactosVistos = 0, penMax = 0;

// Los mismos dos bits que pone OdeSimulation._near, con los valores de
// ode/contact.h: dContactApprox1 = 0x7000 (líneas 51) y dContactSoftCFM = 0x010
// (línea 39). Los bindings los llevan como dContactApprox1_1|_2|_N y 16.
const MODE = 0x7000 | 0x010;

const cb = M.addFunction((data, o1, o2) => {
  vecesLlamado++;
  const n = M._dCollide(o1, o2, MAX, geoms, L['sizeof.dContactGeom']);
  if (n === 0) return;
  contactosVistos += n;
  for (let i = 0; i < n; i++) {
    const src = geoms + i * L['sizeof.dContactGeom'];
    const d = F(src + L['dContactGeom.depth']);
    if (d > penMax) penMax = d;
    // Rellena el dContact exactamente como lo hace OdeSimulation._near.
    setI(contact + L['dContact.surface'] + L['dSurfaceParameters.mode'], MODE);
    setF(contact + L['dContact.surface'] + L['dSurfaceParameters.mu'], 0.8);
    setF(contact + L['dContact.surface'] + L['dSurfaceParameters.soft_cfm'], 1e-4);
    M.HEAPU8.copyWithin(contact + L['dContact.geom'],
                        src, src + L['sizeof.dContactGeom']);
    const j = M._dJointCreateContact(world, group, contact);
    M._dJointAttach(j, M._dGeomGetBody(o1), M._dGeomGetBody(o2));
  }
}, 'viii');
check(cb !== 0, `addFunction devolvió un puntero de función (${cb})`);

// --- El bucle, al paso fijo del mecano.
const DT = 1 / 240;
const yDe = () => F(M._dBodyGetPosition(body) + 4); // pos[1]
const y0 = yDe();
const correr = (segundos) => {
  for (let i = 0; i < 240 * segundos; i++) {
    M._dSpaceCollide(space, 0, cb);
    M._dWorldQuickStep(world, DT);
    M._dJointGroupEmpty(group);
  }
};
// La telemetría de verdad (`ode t=…s pen=…`) mide POR VENTANA, no acumulado
// desde el principio: `pen` en sierra significa resonancia y creciente
// significa que algo se hunde. Así que aquí van tres ventanas, y cada una
// responde una pregunta distinta.
correr(1.5);              // 1. el impacto: llega al suelo a ~14 u/s
const penImpacto = penMax;
penMax = 0;
correr(1.5);              // 2. el asentamiento, que todavía tiene transitorio
penMax = 0;
correr(0.5);              // 3. el REPOSO, ya dormida: esto es lo que se juzga
const y1 = yDe();
const vy = F(M._dBodyGetLinearVel(body) + 4);

console.log(`\n  y: ${y0.toFixed(3)} -> ${y1.toFixed(3)}   |vy| = ${Math.abs(vy).toFixed(4)}`);
console.log(`  el near se llamó ${vecesLlamado} veces, ${contactosVistos} contactos`);
console.log(`  pen: ${penImpacto.toFixed(4)} en el impacto, ${penMax.toFixed(4)} en reposo (hundimiento = ${(R - y1).toFixed(4)})\n`);

check(Number.isFinite(y1), 'la posición final NO es NaN');
check(vecesLlamado > 0, 'el callback de dSpaceCollide ENTRÓ (addFunction sirve)');
check(contactosVistos > 0, 'dCollide devolvió contactos de verdad');
check(Math.abs(y1 - R) < 0.05, `la esfera reposa a su radio (${y1.toFixed(3)} ≈ ${R})`);
check(Math.abs(vy) < 0.05, 'y está quieta');
// El autodisable es lo que hace que un mecano en reposo no cueste CPU. Que
// duerma prueba que el solver converge de verdad, no que oscila pequeñito.
check(M._dBodyIsEnabled(body) === 0, 'la esfera se DURMIÓ (el solver converge)');
check(penMax < 0.02, `la penetración EN REPOSO es sana (${penMax.toFixed(4)})`);
check(penImpacto < 0.5, `el pico del impacto no atraviesa el suelo (${penImpacto.toFixed(4)})`);

M._dJointGroupDestroy(group);
M._dSpaceDestroy(space);
M._dWorldDestroy(world);
M._dCloseODE();
check(true, 'destruir el mundo y dCloseODE no revientan');

// Formato plano clave=valor, el mismo que imprime freefall_native.c: es lo que
// compara tool/wasm/paridad.sh sin tener que parsear prosa.
if (process.argv.includes('--kv')) {
  const kv = {
    y0, y_final: y1, vy: Math.abs(vy),
    pen_impacto: penImpacto, pen_reposo: penMax, hundimiento: R - y1,
    dormida: M._dBodyIsEnabled(body) === 0 ? 1 : 0,
    near_llamado: vecesLlamado, contactos: contactosVistos,
  };
  for (const [k, v] of Object.entries(kv)) {
    console.log(`${k} ${Number.isInteger(v) && k !== 'y0' ? v : v.toFixed(6)}`);
  }
}

if (fallos) { console.error(`ABORTA: ${fallos} fallos`); process.exit(1); }
console.log('\nFASE 2 VERDE: ODE corre dentro de wasm.');
