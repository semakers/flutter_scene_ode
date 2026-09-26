/* La sonda de LAYOUT: qué mide wasm32 realmente.
 *
 * POR QUÉ EXISTE
 * --------------
 * wasm32 es ILP32 (punteros de 4 bytes) y el host de esta caja es arm64 LP64
 * (punteros de 8). Los offsets NO coinciden, y no es una diferencia académica:
 * `sizeof(dContactGeom)` se le pasa a dCollide como el *skip* entre contactos.
 * Equivocarlo no da error: da contactos leídos desde direcciones desplazadas,
 * o sea una física que se mueve mal y no se queja. Medido: dContactGeom pasa de
 * 64 a 52 bytes y dContact de 144 a 128.
 *
 * Así que el shim web NO adivina los offsets: los pregunta al MISMÍSIMO binario
 * que está usando, al arrancar. Y tool/build_ode_wasm.sh los vuelca además a
 * tool/ode_wasm_layout.json, que se commitea y que un test coteja contra el
 * .wasm de assets/ — eso es lo que caza «el .wasm de assets/ es de hace tres
 * semanas».
 *
 * Los nombres viajan CON los valores (nairda_ode_layout_names) en vez de vivir
 * en una lista paralela del lado Dart: con una X-macro, orden y nombres salen
 * de la misma línea y no se pueden desincronizar.
 *
 * Vive en tool/wasm/ y no en ios/Classes/ a propósito: el árbol vendorizado son
 * 75 unidades EXACTAS, cotejadas por windows/CMakeLists.txt y por
 * test/plugin_wiring_test.dart. Ésta es la 76ª y es NUESTRA, no de upstream.
 */

#include <cstddef>
#include <cstring>

#include <ode/ode.h>

/* nombre visible desde Dart  ->  expresión que lo mide */
#define NAIRDA_ODE_LAYOUT_TABLE(X)                                             \
  X(sizeof.dReal,                sizeof(dReal))                                \
  X(sizeof.pointer,              sizeof(void *))                               \
  X(sizeof.int,                  sizeof(int))                                  \
                                                                               \
  X(sizeof.dMass,                sizeof(dMass))                                \
  X(dMass.mass,                  offsetof(dMass, mass))                        \
  X(dMass.c,                     offsetof(dMass, c))                           \
  X(dMass.I,                     offsetof(dMass, I))                           \
                                                                               \
  X(sizeof.dContactGeom,         sizeof(dContactGeom))                         \
  X(dContactGeom.pos,            offsetof(dContactGeom, pos))                  \
  X(dContactGeom.normal,         offsetof(dContactGeom, normal))               \
  X(dContactGeom.depth,          offsetof(dContactGeom, depth))                \
  X(dContactGeom.g1,             offsetof(dContactGeom, g1))                   \
  X(dContactGeom.g2,             offsetof(dContactGeom, g2))                   \
  X(dContactGeom.side1,          offsetof(dContactGeom, side1))                \
  X(dContactGeom.side2,          offsetof(dContactGeom, side2))                \
                                                                               \
  X(sizeof.dSurfaceParameters,   sizeof(dSurfaceParameters))                   \
  X(dSurfaceParameters.mode,     offsetof(dSurfaceParameters, mode))           \
  X(dSurfaceParameters.mu,       offsetof(dSurfaceParameters, mu))             \
  X(dSurfaceParameters.mu2,      offsetof(dSurfaceParameters, mu2))            \
  X(dSurfaceParameters.rho,      offsetof(dSurfaceParameters, rho))            \
  X(dSurfaceParameters.rho2,     offsetof(dSurfaceParameters, rho2))           \
  X(dSurfaceParameters.rhoN,     offsetof(dSurfaceParameters, rhoN))           \
  X(dSurfaceParameters.bounce,   offsetof(dSurfaceParameters, bounce))         \
  X(dSurfaceParameters.bounce_vel, offsetof(dSurfaceParameters, bounce_vel))   \
  X(dSurfaceParameters.soft_erp, offsetof(dSurfaceParameters, soft_erp))       \
  X(dSurfaceParameters.soft_cfm, offsetof(dSurfaceParameters, soft_cfm))       \
  X(dSurfaceParameters.motion1,  offsetof(dSurfaceParameters, motion1))        \
  X(dSurfaceParameters.motion2,  offsetof(dSurfaceParameters, motion2))        \
  X(dSurfaceParameters.motionN,  offsetof(dSurfaceParameters, motionN))        \
  X(dSurfaceParameters.slip1,    offsetof(dSurfaceParameters, slip1))          \
  X(dSurfaceParameters.slip2,    offsetof(dSurfaceParameters, slip2))          \
                                                                               \
  X(sizeof.dContact,             sizeof(dContact))                             \
  X(dContact.surface,            offsetof(dContact, surface))                  \
  X(dContact.geom,               offsetof(dContact, geom))                     \
  X(dContact.fdir1,              offsetof(dContact, fdir1))

extern "C" {

/* Cuántas entradas tiene la tabla. */
int nairda_ode_layout_count(void) {
#define X(name, expr) +1
  return 0 NAIRDA_ODE_LAYOUT_TABLE(X);
#undef X
}

/* Los valores, en el orden de la tabla. Devuelve cuántos escribió, o -1 si no
 * cabían: un buffer corto se nota, no se trunca en silencio. */
int nairda_ode_layout(int *out, int cap) {
  const int n = nairda_ode_layout_count();
  if (out == 0 || cap < n) return -1;
  int i = 0;
#define X(name, expr) out[i++] = (int)(expr);
  NAIRDA_ODE_LAYOUT_TABLE(X)
#undef X
  return i;
}

/* Los nombres, separados por '\n', en el MISMO orden. Que salgan de la misma
 * línea de la X-macro es justo lo que impide que orden y nombres deriven. */
const char *nairda_ode_layout_names(void) {
#define X(name, expr) #name "\n"
  static const char kNames[] = NAIRDA_ODE_LAYOUT_TABLE(X);
#undef X
  return kNames;
}

/* La cadena de configuración, para poder cotejar la precisión sin exportar los
 * ayudantes de string de emscripten. */
const char *nairda_ode_configuration(void) { return dGetConfiguration(); }

}  /* extern "C" */
