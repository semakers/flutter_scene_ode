#ifndef NAIRDA_ODE_EMSCRIPTEN_COMPAT_H
#define NAIRDA_ODE_EMSCRIPTEN_COMPAT_H

/* Lo que le falta a emscripten para compilar ODE en precisión simple.
 *
 * Es EL MISMO agujero que Darwin, y por la misma causa: `include/ode/common.h`
 * (líneas 298-314) elige la macro `dIsNan` entre `__isnanf`, `_isnanf` e
 * `isnanf`, y si no encuentra ninguna cae en `_isnan`, que es el nombre de
 * Visual C. La libc de emscripten es musl y no declara ninguna de las cuatro
 * (comprobado: `__isnanf` es una extensión de glibc, y `isnanf` no es estándar).
 *
 * Sin esto no compila ni una de las 75 unidades. La macro de C99 `isnan` ya
 * hace lo correcto con un float, así que basta con darle el nombre que ODE
 * busca. Va en cabecera aparte, y no solo dentro de config.h, porque
 * tool/build_ode_wasm.sh la mete con `-include`: así entra antes que cualquier
 * otra cosa, venga la unidad de compilación por donde venga. Exactamente el
 * mismo patrón que apple_compat.h, y por la misma razón.
 */

#if defined(__EMSCRIPTEN__)

#include <math.h>

#if !defined(isnanf)
#define isnanf(x) isnan(x)
#endif

#endif /* __EMSCRIPTEN__ */

#endif /* NAIRDA_ODE_EMSCRIPTEN_COMPAT_H */
