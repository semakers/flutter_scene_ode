#ifndef ODE_CONFIG_H
#define ODE_CONFIG_H

/* Este fichero lo GENERABA cmake (ode/src/config.h.in). Aquí está escrito a
 * mano porque el pod de Apple compila las fuentes de src/ sin cmake, y porque
 * el mismo árbol tiene que valer para el banco de host de Linux.
 *
 * Cuatro plataformas llegan aquí: Darwin (iOS y macOS, vía el podspec), Windows
 * (vía windows/CMakeLists.txt, que compila el mismo árbol con MSVC), esta caja
 * Linux (vía tool/build_vendored_host.sh, que es la verificación previa) y
 * emscripten/WebAssembly (vía tool/build_ode_wasm.sh, que produce el ode.wasm
 * que viaja commiteado en assets/, igual que el .so de Android viaja en
 * jniLibs/). Android NO usa este fichero: allí el .so sigue viniendo
 * precompilado de tool/build_ode.sh, con el config.h de cmake.
 *
 * Los valores de la rama de Darwin están SONDEADOS contra el SDK, no supuestos.
 */

#include "apple_compat.h"
#include "emscripten_compat.h"

#if defined(__APPLE__)

/* macOS/iOS: hay alloca.h, pero malloc.h no existe (es <malloc/malloc.h>) y
 * pthread_condattr_setclock tampoco está. Ni `__isnan`/`__isnanf` ni
 * `_isnan`/`_isnanf`: la única forma es `isnan`/`isnanf`, y `isnanf` lo aporta
 * apple_compat.h de arriba. */
#define HAVE_ALLOCA_H 1
/* HAVE_GETTIMEOFDAY no es relleno: ode/src/threading_impl_posix.h tiene una
 * rama `#if defined(__APPLE__)` que se apoya en gettimeofday PRECISAMENTE
 * porque en Darwin no hay pthread_condattr_setclock, y corta con un #error si
 * no está declarado. */
#define HAVE_GETTIMEOFDAY 1
#define HAVE_INTTYPES_H 1
#define HAVE_ISNAN 1
#define HAVE_ISNANF 1
/* #undef HAVE_MALLOC_H */
/* #undef HAVE_PTHREAD_ATTR_SETSTACKLAZY */
/* #undef HAVE_PTHREAD_CONDATTR_SETCLOCK */
#define HAVE_STDINT_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1
/* #undef HAVE__ISNAN */
/* #undef HAVE__ISNANF */
/* #undef HAVE___ISNAN */
/* #undef HAVE___ISNANF */

#elif defined(_MSC_VER)

/* Windows con MSVC (Visual Studio 2022). Sin esta rama el build caia en el
 * `#else` de glibc de abajo y el propio config.h hacia `#include <alloca.h>`,
 * que en MSVC no existe.
 *
 * `alloca` la trae <malloc.h>, no una cabecera propia. No hay <unistd.h>,
 * <sys/time.h> ni pthreads: en Windows el hilo lo pone ode/src/threading_pool_win.cpp
 * (ya vendorizado, con su cuerpo bajo `#if defined(_WIN32)`), asi que
 * threading_impl_posix.h ni se mira y HAVE_GETTIMEOFDAY no hace falta.
 *
 * Y de las cuatro variantes de isnan que busca include/ode/common.h solo
 * existe `_isnan`, declarada en <float.h> — que ya entra por odeconfig.h:34.
 * En precision simple (dSINGLE) la cadena `__isnanf`/`_isnanf`/`isnanf` no
 * encuentra ninguna y CAE en `_isnan`, que es justo el nombre de Visual C: es
 * el caso para el que se escribio ese `#else` de upstream. Por eso ninguna de
 * las HAVE_*ISNAN* se define aqui — definir HAVE__ISNAN no serviria (esa solo
 * la mira la rama de dDOUBLE) y HAVE_ISNANF romperia el build. */
#define HAVE_MALLOC_H 1
#define HAVE_STDINT_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_SYS_TYPES_H 1
/* #undef HAVE_ALLOCA_H */
/* #undef HAVE_GETTIMEOFDAY */
/* #undef HAVE_ISNAN */
/* #undef HAVE_ISNANF */
/* #undef HAVE_PTHREAD_ATTR_SETSTACKLAZY */
/* #undef HAVE_PTHREAD_CONDATTR_SETCLOCK */
/* #undef HAVE_SYS_TIME_H */
/* #undef HAVE_UNISTD_H */
/* #undef HAVE__ISNAN */
/* #undef HAVE__ISNANF */
/* #undef HAVE___ISNAN */
/* #undef HAVE___ISNANF */

#elif defined(__EMSCRIPTEN__)

/* WebAssembly con emscripten. Su libc es musl, y por eso NO puede caer en el
 * `#else` de glibc de abajo: allí se definen HAVE___ISNAN y HAVE___ISNANF, y
 * musl no tiene ni `__isnan` ni `__isnanf`. La cadena de include/ode/common.h
 * (líneas 298-314) elige `dIsNan` entre `__isnanf`, `_isnanf` e `isnanf`, y si
 * no encuentra ninguna cae en `_isnan`, que es el nombre de Visual C: el mismo
 * agujero exacto que Darwin. Se declara HAVE_ISNANF y lo aporta
 * emscripten_compat.h de arriba.
 *
 * Sondeado contra el SDK de emscripten por tool/build_ode_wasm.sh, que compila
 * una sonda antes de las 75 unidades y ABORTA si alguna de estas cabeceras o
 * funciones no está: aquí no hay nada supuesto. */
#define HAVE_ALLOCA_H 1
#define HAVE_GETTIMEOFDAY 1
#define HAVE_INTTYPES_H 1
#define HAVE_ISNAN 1
#define HAVE_ISNANF 1
#define HAVE_MALLOC_H 1
/* #undef HAVE_PTHREAD_ATTR_SETSTACKLAZY */
#define HAVE_PTHREAD_CONDATTR_SETCLOCK 1
#define HAVE_STDINT_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1
/* #undef HAVE__ISNAN */
/* #undef HAVE__ISNANF */
/* #undef HAVE___ISNAN */
/* #undef HAVE___ISNANF */

#else

/* Linux (glibc). Copia literal de lo que generó cmake en el build de host que
 * ya funciona, que es contra el que se contrastan los tests. */
#define HAVE_ALLOCA_H 1
#define HAVE_GETTIMEOFDAY 1
#define HAVE_INTTYPES_H 1
#define HAVE_ISNAN 1
#define HAVE_ISNANF 1
#define HAVE_MALLOC_H 1
/* #undef HAVE_PTHREAD_ATTR_SETSTACKLAZY */
#define HAVE_PTHREAD_CONDATTR_SETCLOCK 1
#define HAVE_STDINT_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1
/* #undef HAVE__ISNAN */
/* #undef HAVE__ISNANF */
#define HAVE___ISNAN 1
#define HAVE___ISNANF 1

#endif

/* Nunca: es de drawstuff, que no se compila. */
/* #undef HAVE_APPLE_OPENGL_FRAMEWORK */

/* Optimizaciones específicas de x86 que cmake tampoco encendía. */
/* #undef PENTIUM */
/* #undef X86_64_SYSTEM */

/* A partir de aquí, copia literal de lo que generaba cmake: ya era portable. */

/* Try to identify the platform */
#if defined(_XENON)
#define ODE_PLATFORM_XBOX360
#elif defined(SN_TARGET_PSP_HW)
#define ODE_PLATFORM_PSP
#elif defined(SN_TARGET_PS3)
#define ODE_PLATFORM_PS3
#elif defined(_MSC_VER) || defined(__CYGWIN__) || defined(__MINGW32__)
#define ODE_PLATFORM_WINDOWS
#elif defined(__EMSCRIPTEN__)
/* Emscripten NO define __linux__, así que sin esta rama el build muere en el
 * `#error` de doce líneas más abajo. De ODE_PLATFORM_* solo se consume
 * ODE_PLATFORM_WINDOWS (cuatro líneas tras el #endif, para definir WIN32), así
 * que esto es inerte salvo por callar el #error. */
#define ODE_PLATFORM_LINUX
#elif defined(__linux__)
#define ODE_PLATFORM_LINUX
#elif defined(__APPLE__) && defined(__MACH__)
#define ODE_PLATFORM_OSX
#elif defined(__FreeBSD__)
#define ODE_PLATFORM_FREEBSD
#else
#error "Need some help identifying the platform!"
#endif

/* Additional platform defines used in the code */
#if defined(ODE_PLATFORM_WINDOWS) && !defined(WIN32)
#define WIN32
#endif

#if defined(__CYGWIN__) || defined(__MINGW32__)
#define CYGWIN
#endif

/* Aquí el original definía `macintosh`. Se ha QUITADO a propósito: su único
 * uso en todo el árbol es ode/src/timer.cpp:227, en una rama que en Apple no
 * se alcanza nunca (gana antes la de `__APPLE__ && __MACH__`, línea 174). Y si
 * algún día se alcanzara, tiraría de `Microseconds()` de Carbon, que en iOS no
 * existe. O sea que es un macro cuyo único efecto posible es romper iOS. */

#ifdef HAVE_ALLOCA_H
#include <alloca.h>
#endif

#ifdef HAVE_MALLOC_H
#include <malloc.h>
#endif

#ifdef HAVE_STDINT_H
#include <stdint.h>
#endif

#ifdef HAVE_INTTYPES_H
#include <inttypes.h>
#endif

#include "typedefs.h"

#endif /* ODE_CONFIG_H */
