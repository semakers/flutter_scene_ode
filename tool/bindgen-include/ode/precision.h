/* Commiteado a propósito.
 *
 * El `precision.h` de verdad lo GENERA cmake dentro del build tree, así que
 * regenerar los bindings exigía haber compilado ODE antes. Esta copia mínima
 * rompe esa dependencia: `tool/gen_bindings.sh` la pone en el include path y
 * ffigen puede correr contra las fuentes recién extraídas.
 *
 * dSINGLE es OBLIGATORIO y no es una preferencia: los bindings generados
 * declaran `dReal = ffi.Float`. Si algún día se compila el .so en doble
 * precisión, el binario NO da error de enlace: lee basura. Por eso
 * tool/build_ode.sh fuerza -DODE_DOUBLE_PRECISION=OFF y ode_library.dart lo
 * verifica en caliente con dCheckConfiguration('ODE_single_precision').
 */
#ifndef _ODE_PRECISION_H_
#define _ODE_PRECISION_H_

#define dSINGLE

#endif
