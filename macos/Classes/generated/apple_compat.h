#ifndef NAIRDA_ODE_APPLE_COMPAT_H
#define NAIRDA_ODE_APPLE_COMPAT_H

/* Lo que le falta a Darwin para compilar ODE en precisión simple.
 *
 * `include/ode/common.h` elige la macro `dIsNan` entre `__isnanf`, `_isnanf` e
 * `isnanf`, y si no encuentra ninguna cae en `_isnan`, que es el nombre de
 * Visual C. En Darwin NO existe ninguno de los cuatro: `isnan` es una macro de
 * <math.h> con sobrecarga por tipo y las variantes con sufijo `f` no están
 * declaradas (comprobado compilando contra el SDK: "call to undeclared
 * function 'isnanf'"). Sin esto, ODE no compila para iOS ni para macOS.
 *
 * La macro de C99 ya hace lo correcto con un float, así que basta con darle el
 * nombre que ODE busca. Va en una cabecera aparte, y no solo dentro de
 * config.h, porque el podspec la mete con `-include`: así entra antes que
 * cualquier otra cosa, venga la unidad de compilación por donde venga.
 */

#if defined(__APPLE__)

/* ou/include/ou/platform.h decide la plataforma con TARGET_OS_IPHONE y
 * TARGET_OS_MAC, y NO incluye <TargetConditionals.h> — ningún fichero de ODE
 * lo hace. Hoy funciona porque Apple clang los predefine (comprobado con
 * `clang -dM -E`), pero si dejara de hacerlo las dos ramas darían falso y el
 * fallo sería un `#error Build Apple target is not supported` sepultado en el
 * log del pod. Esto lo hace imposible, y mientras se predefinan es inerte. */
#include <TargetConditionals.h>

#include <math.h>

#if !defined(isnanf)
#define isnanf(x) isnan(x)
#endif

#endif /* __APPLE__ */

#endif /* NAIRDA_ODE_APPLE_COMPAT_H */
