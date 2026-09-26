# El código nativo: de dónde sale ODE

Hay **dos caminos, y son distintos a propósito**:

| plataforma | qué se envía | quién compila |
|---|---|---|
| Android | `libode.so` precompilado y commiteado | esta caja, con el NDK (`tool/build_ode.sh android`) |
| iOS y macOS | **las fuentes**, en `ios/Classes/` y `macos/Classes/` | Xcode, en el runner de la nube (`ios/flutter_scene_ode.podspec`) |

En Android el binario viaja hecho para que la app se construya sin NDK, sin
cmake y sin qemu. En Apple no hay esa opción: **ninguna máquina del proyecto
puede compilar para iOS** — esta caja es Linux ARM64 y el Mac solo tiene
Command Line Tools, sin SDK de iPhone. El único compilador de Apple a mano es
el de Xcode Cloud, así que las fuentes viajan y el pod las compila allí.

Este documento es la contraparte de las dos cosas: la receta, para que ni el
binario ni el árbol de C++ sean algo de lo que nadie sabe de qué fuente salió.

## Qué es exactamente el binario que se envía

| | |
|---|---|
| Biblioteca | ODE — Open Dynamics Engine |
| Versión | **0.16.6** |
| SHA256 del tarball | `c91a28c6ff2650284784a79c726a380d6afec87ecf7a35c32a6be0c5b74513e8` |
| ABI | `arm64-v8a` únicamente |
| Tamaño | 746 816 bytes (stripped) |
| MD5 del `.so` | `bf83645778207c81813d4761b32f5fe8` |
| SONAME | `libode.so` (sin sufijo de versión — Android lo exige) |
| Precisión | **single** (`dSINGLE`) |
| NDK | 27.0.12077973, `android-24`, `c++_static` |
| Tipo de build | `MinSizeRel`, `llvm-strip --strip-unneeded` |

## Reproducirlo

```bash
tool/fetch_ode.sh          # descarga y VERIFICA el sha256 (aborta si no cuadra)
tool/build_ode.sh android  # compila y comprueba la sanidad del ELF
tool/build_ode.sh host     # variante de la caja actual, para el banco de tests
```

Las fuentes descargadas y los builds viven **fuera del repo** (por defecto en el
disco externo; se reapunta con `ODE_WORK`, ver `tool/ode_env.sh`).

## El árbol de `Classes/`: lo que compila Apple

```bash
tool/vendor_ode.sh           # copia del tarball verificado a los dos Classes/
tool/vendor_ode.sh --check   # NO toca nada; falla si alguno divergió
```

**Hay DOS copias, `ios/Classes/` y `macos/Classes/`, y son directorios de
verdad.** Lo natural sería tener el árbol una vez y que las dos fueran symlinks
—es lo que hace la plantilla oficial de plugin FFI de Flutter—, pero **no
funciona, y falla en silencio**: `Pod::Sandbox::PathList` precalcula los
ficheros del pod con `Dir.glob(raíz + '**/*')`, y el `**` de Ruby no desciende
por un symlink de directorio. Con symlink, `source_files` devuelve `[]`, el pod
se construye VACÍO, el archive sale verde y la app enseña la pantalla honesta.

Está medido con el CocoaPods 1.16.2 de verdad, el mismo del runner: con symlink
el `PathList` ve **0** ficheros; con directorios de verdad ve 191 y resuelve las
**75 unidades** y 116 cabeceras. Y está sufrido: el build **#230** archivó sin
compilar ni una unidad de ODE, y solo lo cantó `verificar_ode.sh`.

`ios/Classes/` es la copia canónica —es la que compilan `build_vendored_host.sh`
y `verify_apple.sh`—; `macos/Classes/` es su espejo. `--check` compara las dos
contra upstream y además entre sí, así que no pueden separarse sin que se note.

Son **exactamente las 75 unidades de traducción que compila el build bueno de
cmake**: 52 de `ode/src` (las 66 del tarball menos las 14 de trimesh, GIMPACT y
libccd, que son justo los interruptores apagados), las 18 de `ode/src/joints`,
`nextafterf.c` y 4 de `ou/src/ou`. Las cabeceras van enteras, que son pequeñas y
unas tiran de otras.

`Classes/generated/` es lo único que **no** sale del tarball:

- **`config.h`** lo generaba cmake desde `ode/src/config.h.in`. Aquí está escrito
  a mano, con una rama para Darwin y otra para Linux; los valores de la de
  Darwin están sondeados contra el SDK, no supuestos (no hay `malloc.h`, no hay
  `pthread_condattr_setclock`, no hay `__isnan`/`__isnanf`).
- **`apple_compat.h`** existe por un fallo concreto: `include/ode/common.h` elige
  `dIsNan` en precisión simple entre `__isnanf`, `_isnanf` e `isnanf`, y si no
  hay ninguno cae en `_isnan`, que es el de Visual C. **En Darwin no está
  declarado ninguno de los cuatro**, así que ODE no compila tal cual. La
  cabecera le da a `isnanf` el nombre que ODE busca, y el podspec la mete con
  `-include` para que entre antes que todo.

`precision.h` y `version.h` **sí** vienen en el tarball (a diferencia de
`config.h`), así que no hay que escribirlas.

### El `CoreServices` de `timer.cpp`, y el shim que hubo que retirar

`ode/src/timer.cpp:178` hace `#include <CoreServices/CoreServices.h>` dentro de
la rama `__APPLE__ && __MACH__`, **sin usar ni un símbolo de ahí**: se apaña con
`mach_absolute_time()` y `mach_timebase_info()`. Mientras no hubo un SDK de
iPhone a mano se neutralizó con una cabecera vacía en `Classes/apple-shim/`, y
**eso tumbó el build #233**: al construir el módulo `ApplicationServices` la
cabecera falsa suplantaba al framework real y el `<AE/AE.h>` de `HIServices`
dejaba de resolverse. `CoreServices` existe en los tres SDK —comprobado—, así
que el shim se borró entero en `6705eba`. La lección: no blindarse contra algo
que se puede mirar en un minuto.

Por el mismo motivo, el `config.h` **no** define `macintosh` como hacía el de
cmake: su único uso es una rama de `timer.cpp` inalcanzable en Apple que tiraría
de `Microseconds()` de Carbon, que en iOS no existe.

**Las dos verificaciones previas, que son las que ahorran vueltas de nube:**

```bash
tool/build_vendored_host.sh                       # compila el árbol SIN cmake, aquí
ODE_LIBRARY_PATH=<lo que imprime> \
  ~/dev/flutter-3471/bin/flutter test            # y corre el banco de física

tool/verify_apple.sh                              # y lo compila EN EL MAC
```

El primero termina cotejando que **los 84 símbolos de `functions.include` de
`ffigen.template.yaml` están todos definidos** en lo que acaba de compilar. Si
alguien añade una función a los bindings y no acaba en la librería, el fallo
sería un `StateError` en el teléfono; así sale aquí.

El segundo es el que de verdad cubre a Apple, y desde que el Mac tiene Xcode
(26.4, en `~/EXTRA/Apps/`) cubre **las dos mitades del problema**:

1. **Que el C++ compile**, en las tres variantes que construye el runner —macOS,
   iPhone y simulador de iPhone—, cada una contra su SDK de verdad. Comprueba
   los 75 objetos, que `dInitODE2` salga exportado y que el binario diga ser de
   precisión simple.
2. **Que CocoaPods lo empaquete bien**, en **las dos plataformas** —que no es lo
   mismo: el #233 murió solo en macOS, donde el prefix header del pod incluye
   `<Cocoa/Cocoa.h>` y arrastra módulos del sistema que en iOS no se tocan—.
   `pod lib lint` + `xcodebuild` sobre cada podspec, y luego `nm` sobre el
   framework. Prueba que `source_files` encuentra las 75 unidades, que los
   header maps no secuestran `#include <assert.h>`, que el framework sale
   **dinámico** y que los símbolos quedan exportados.

Son ~5 minutos contra los ~16 de una vuelta de nube, y dicen mucho más.

## Windows: el mismo árbol, con MSVC

Windows compila **exactamente las mismas 75 unidades de `ios/Classes/`**, desde
`windows/CMakeLists.txt`. No hay binario commiteado (a diferencia de Android) ni
tercera copia del árbol (a diferencia de macOS).

**Por qué no hay tercera copia.** La duplicación `ios/` ↔ `macos/` no existe por
gusto: existe porque `Pod::Sandbox::PathList` no desciende por un symlink de
directorio. **Esa limitación es de CocoaPods, no de CMake.** Aquí basta con
`${CMAKE_CURRENT_SOURCE_DIR}/../ios/Classes`, que además es el patrón oficial —la
plantilla `plugin_ffi` de Flutter hace `add_subdirectory("../src")`— y ya está
probado en producción en este mismo proyecto: `nairda_compiler/windows/CMakeLists.txt`
referencia `../dist/windows-x64/` a través del mismo symlink de
`.plugin_symlinks`.

**El nombre del target es un contrato.** `add_library(ode SHARED …)` produce
`ode.dll`, que es literalmente lo que abre `ode_library.dart` en Windows
(`Platform.isWindows ? 'ode.dll' : …`). Renombrar el target no da error de
compilación: da la pantalla honesta. Hay un test que ata las dos mitades.

**La rama de MSVC en `config.h`.** Antes solo había `__APPLE__` y un `#else` que
era glibc; MSVC caía en el segundo y el propio `config.h` hacía
`#include <alloca.h>`. Lo que MSVC necesita:

| macro | valor | por qué |
|---|---|---|
| `HAVE_MALLOC_H` | 1 | Lo innegociable: `alloca` no tiene cabecera propia en MSVC, la trae `<malloc.h>`, y `dALLOCA16` la usa a pelo |
| `HAVE_ALLOCA_H` | undef | `<alloca.h>` no existe: es lo que rompía el build en la rama de glibc |
| `HAVE_STDINT_H`, `HAVE_INTTYPES_H`, `HAVE_SYS_TYPES_H` | 1 | Existen en la UCRT |
| `HAVE_UNISTD_H`, `HAVE_SYS_TIME_H`, `HAVE_GETTIMEOFDAY` | undef | No existen. Solo los mira `threading_impl_posix.h`, que en Windows no se compila: manda `threading_pool_win.cpp` |
| `HAVE_PTHREAD_*` | undef | No hay pthreads |
| las **seis** `HAVE_*ISNAN*` | undef | Ver abajo |

Lo de `isnan` merece su nota, porque la tentación de "completar" la rama es
fuerte y **rompería el build**. La cadena de `include/ode/common.h:298-314` en
precisión simple es `__isnanf` → `_isnanf` → `isnanf` → y si no hay ninguna, cae
en `_isnan`, con un comentario de upstream que dice literalmente *«the VC way»*.
O sea que **dejando las tres sin definir se toma exactamente el camino de Visual
C**, que es el que queremos. `HAVE__ISNAN` sería inerte (solo la mira la rama de
`dDOUBLE`) y `HAVE__ISNANF` sería peligroso: `_isnanf` no está garantizada en la
UCRT. `_isnan(double)` sí lo está, en `<float.h>`, que ya entra por
`odeconfig.h:34`.

**La trampa que costó un build entero: el `UNICODE` heredado.**
`nairda_robot_programming/windows/CMakeLists.txt:33` hace
`add_definitions(-DUNICODE -D_UNICODE)` **antes** de incluir
`generated_plugins.cmake`, y `add_definitions` es una propiedad de *directorio*:
la hereda el `add_subdirectory` del plugin. Con `UNICODE`, `MessageBox` es
`MessageBoxW` y `ode/src/error.cpp:145` le pasa un `char[1000]` → `error C2664`,
y muere el build entero por **una** unidad de las 75. ODE es ANSI de 2006 de
arriba abajo: no se le pone `UNICODE`, se le quita con `remove_definitions`.

Lo insidioso es que **un banco que compile el plugin suelto no lo reproduce**,
porque el `UNICODE` no viene del plugin sino de la app. Por eso el arnés de
`tool/verify_windows.ps1` mete `add_definitions(-DUNICODE -D_UNICODE)` a
propósito. Comprobado quitando el `remove_definitions` a mano: el banco pasa de
verde a `C2664` en `error.cpp:145` y `:162`.

**`_USE_MATH_DEFINES` no es cosmético.** Sin él, `<math.h>` de MSVC no define
`M_PI` y `include/ode/common.h:43` lo define él mismo como
`REAL(3.1415926535897932…)`, que en precisión simple es un **float**. En glibc y
en Darwin `math.h` ya lo trae como `double` y ese `#ifndef` ni dispara. Sin esa
línea, Windows correría una física numéricamente distinta de la del resto de
plataformas, y no se vería nunca.

**Lo que no lleva, a propósito:** `apply_standard_settings` (mete `/W4 /WX`, y
cada `C4244` de código de 2006 se volvería fatal; además ataría el fichero al
CMake de la app e impediría verificarlo suelto), `_OU_TARGET_OS` fijado a mano
(`ou/platform.h` lo autodetecta), y `/fp:fast` (divergiría la física).

**La exportación de símbolos es gratis aquí.** `include/ode/odeconfig.h:44-51`
convierte `ODE_API` en `__declspec(dllexport)` con `_MSC_VER` + `ODE_DLL`, y
`ODE_DLL` ya lo pasan todos los builds del proyecto. El problema que en Apple
obligó a `GCC_SYMBOLS_PRIVATE_EXTERN = NO` no existe. Medido: **639 símbolos
exportados**, `ode.dll` de ~353 KB.

**Ninguna librería de sistema extra.** `user32` (por el `MessageBox` de
`error.cpp`) viene por defecto en `CMAKE_CXX_STANDARD_LIBRARIES` y se pone
explícito solo para documentarlo. Lo demás es `QueryPerformanceCounter`
(`timer.cpp`) y `_beginthreadex` (`threading_pool_win.cpp`): kernel32 y CRT.

**Las dos verificaciones:**

```bash
scp tool/verify_windows.ps1 winpc:C:/dev/flutter_scene_ode/tool/
ssh winpc "powershell -NoProfile -ExecutionPolicy Bypass -File C:\dev\flutter_scene_ode\tool\verify_windows.ps1"
```

`tool/verify_windows.ps1` construye el `CMakeLists.txt` de verdad dentro de un
arnés que imita el entorno de la app, y coteja la DLL: 75 objetos, los símbolos
exportados y la cadena `ODE_single_precision`. Una vuelta es ~1 minuto contra los
~15 de un `flutter build windows` en esa máquina de 4 núcleos.

`ci_shared/verificar_ode_windows.ps1` (en el repo de la app) hace lo mismo sobre
el `Release\` ya construido, y lo llama `tools/windows_release.ps1`, que además
tiene `ode.dll` entre sus piezas críticas. Es el equivalente de
`ci_shared/verificar_ode.sh` para Apple, y existe por el mismo motivo: **con
fallo blando, un build sin ODE es indistinguible de uno bueno.**

**Nunca mandes PowerShell en línea por ssh.** El escapado `ssh → cmd.exe →
powershell` se come las comillas y convierte `$_` en otra cosa. Fichero por
`scp` y `powershell -NoProfile -ExecutionPolicy Bypass -File`, siempre.

## Web: el mismo árbol, con emscripten

`tool/build_ode_wasm.sh` compila **las mismas 75 unidades de `ios/Classes`** a
WebAssembly, más una 76ª que es nuestra (`tool/wasm/nairda_ode_layout.cpp`, la
sonda de layout — vive fuera del árbol vendorizado justo para no descuadrar el
recuento de 75 que cotejan el CMakeLists de Windows y el banco).

**Web se comporta como ANDROID, no como Apple/Windows**: el binario viaja
commiteado (`assets/ode.{js,wasm}`) y ninguna máquina que construya la app
necesita emscripten. Son **122 604 bytes**, contra los 746 816 del `.so` de
Android: el enlazador descarta todo lo que no alcanza desde los 88 símbolos
exportados.

### El toolchain

emsdk `latest` (por omisión en `$HOME/emsdk`; se cambia con `EMSDK_ROOT`).
Emscripten y no clang+wasi-sdk por tres razones que no son de comodidad:

1. `ou/platform.h:111` detecta el OS por `__unix__`, que emscripten predefine y
   `wasm32-wasi` no. Con WASI habría que forzar `_OU_TARGET_OS`, que está
   prohibido por un test y por buenas razones.
2. `ou/src/ou/atomic.cpp` y `threadlocalstorage.cpp` usan pthreads (mutexes y
   TLS). emscripten los da funcionando en monohilo; wasi-libc no los tiene.
3. Hace falta pasar **un callback de Dart como puntero a función de C** para
   `dSpaceCollide`. Eso es `addFunction` + `-sALLOW_TABLE_GROWTH`. Sin él la
   física correría sin contactos y en silencio.

Solo `latest` publica binarios arm64-linux, así que la versión se pincha **a
posteriori** en `tool/emsdk_version.txt`, que se commitea junto al `.wasm`.

### Las banderas que no son obvias

- **`-sALLOW_MEMORY_GROWTH=0` con `-sINITIAL_MEMORY=32MB`.** Si la memoria
  creciera, las vistas `HEAPF32` quedarían DESACOPLADAS del búfer nuevo y toda
  lectura posterior daría basura o lanzaría. Con crecimiento apagado las vistas
  se cachean una sola vez: es a la vez la decisión de corrección y la de
  rendimiento. A ODE le sobran 32 MB (el solver usa un arena de heap, no
  `alloca`).
- **`-sSTACK_SIZE=1MB`.** El default son 64 KB, y
  `collision_space_internal.h:32` usa `ALLOCA` proporcional al número de geoms
  del espacio.
- **`-sINCOMING_MODULE_JS_API=wasmBinary`.** Sin declararlo, la variante con
  `ASSERTIONS` aborta y la de release **lo ignora en silencio**, se va a buscar
  el `.wasm` por URL y falla con «both async and sync fetching of the wasm
  failed». Por eso se compilan las dos variantes.
- **`-fno-exceptions` NO**, todavía: no hay ni un `try`/`throw`/`dynamic_cast`
  en las 75 unidades, así que sería inerte — pero un ODE distinto por plataforma
  es un bug que solo aparece en la plataforma rara.

### `config.h`: la cuarta rama, y sus dos trampas

**Emscripten no define `__linux__`**, así que sin rama propia el build muere en
el `#error "Need some help identifying the platform!"`. Sí define `__unix__` y
`__GNUC__` (comprobado con `emcc -dM -E`), que es lo que hace que `ou` detecte
GENUNIX y el compilador GCC por su cuenta.

Y **`isnanf` no existe en musl**: es el MISMO agujero que Darwin. La cadena de
`include/ode/common.h:298-314` elige `dIsNan` entre `__isnanf`, `_isnanf` e
`isnanf`, y si no encuentra ninguna cae en `_isnan`, que es el nombre de Visual
C. `ios/Classes/generated/emscripten_compat.h` se lo da, metido con `-include`
igual que `apple_compat.h`.

Los valores de la rama están **sondeados**: `build_ode_wasm.sh` compila una
sonda que incluye `<malloc.h>`, `<alloca.h>`, `<unistd.h>`, `<sys/time.h>` y usa
`gettimeofday` y `pthread_condattr_setclock` antes de tocar las 75 unidades, y
aborta si el SDK no cumple lo que `config.h` afirma.

### El layout: wasm32 es ILP32

Los punteros miden 4 bytes, así que los desplazamientos **no coinciden** con el
host arm64, y no es académico: `sizeof(dContactGeom)` se le pasa a `dCollide`
como el *skip* entre contactos, y equivocarlo no da error, da contactos leídos
desde direcciones corridas.

| | arm64 (LP64) | wasm32 (ILP32) |
|---|---|---|
| `dContactGeom` | 64 | **52** |
| `dContact` | 144 | **128** |
| `dMass` | 68 | 68 |
| `dSurfaceParameters` | 60 | 60 |

Por eso nada se adivina: `tool/wasm/nairda_ode_layout.cpp` publica sizes y
offsets desde DENTRO del módulo con una X-macro (nombres y valores salen de la
misma línea, así que no pueden derivar), `tool/ode_wasm_layout.json` los deja
commiteados y revisables, y **el cargador se los vuelve a preguntar al módulo
que carga** y se niega a arrancar si no cuadran.

### La paridad, medida

`tool/wasm/paridad.sh` corre el mismo escenario contra `libode.so` y contra
`ode.wasm` y compara los invariantes del reposo. Salieron **idénticos hasta la
sexta cifra** (`y_final` 0.997174, 483 contactos, 0.002826 de hundimiento en los
dos). Se temía la contracción FMA —el host funde `a*b+c` en un `fmadd` con
redondeo único y wasm MVP no tiene FMA— y no se materializó en estos caminos.

No se comparan trayectorias a propósito: un sólido rígido con contactos es
caóticamente sensible y una tolerancia trayectoria-a-trayectoria sería o inútil
o intermitente. La prueba fuerte es otra: **los 34 tests del banco de física
pasan en Chrome contra wasm sin cambiar una sola aserción**.

## El podspec: por qué framework DINÁMICO

`ios/flutter_scene_ode.podspec` **no** declara `s.static_framework`, y eso es la
decisión, no un olvido. El `Podfile` de la app usa `use_frameworks!`, así que
sin esa línea el pod se construye como framework dinámico:

- Con `ffiPlugin: true` **nada referencia a ODE desde Objective-C**. En un
  framework estático el enlazador descarta los objetos que nadie usa: el archive
  saldría verde y vacío, y habría que parchear `OTHER_LDFLAGS` de `Pods-Runner`
  con `-force_load` o con 84 `-Wl,-u`. Un dylib enlaza todos sus objetos por
  construcción.
- Y esquiva el strip: de un dylib no se pueden quitar los símbolos globales sin
  romperlo.

Hay dos ajustes que **no se pueden perder**, y `test/apple_plugin_wiring_test.dart`
los vigila: `GCC_SYMBOLS_PRIVATE_EXTERN = NO` (porque `ODE_API` está vacío fuera
de Windows y las funciones no llevan `visibility("default")`) y
`header_mappings_dir` (porque ODE tiene ficheros con el mismo nombre en
`include/ode` y en `ode/src` — aplanados se pisan).

Que el símbolo acabe **dentro del binario** lo comprueba
`ci_shared/verificar_ode.sh` en el repo de la app, con `nm` sobre el archive.

## Las banderas, y por qué cada una

- `-DODE_DOUBLE_PRECISION=OFF` — **obligatorio**. Los bindings declaran
  `dReal = ffi.Float`. Un `.so` en doble precisión no da error de enlace: lee
  basura. `ode_library.dart` lo verifica en caliente con
  `dCheckConfiguration('ODE_single_precision')`.
- `-DODE_WITH_OPCODE=OFF`, `-DODE_WITH_GIMPACT=OFF` — son los backends de
  colisión contra mallas arbitrarias. No hacen falta: todo colisiona con
  primitivas, y son lo que más pesa.
- `-DODE_WITH_LIBCCD=OFF` — **no es solo por peso, y encenderlo sería un tiro
  en el pie**. Con libccd, `ODE_WITH_LIBCCD_BOX_CYL` viene ON y **sustituye**
  el collider nativo `cylinder↔box`, que es justamente la única pareja que de
  verdad usamos (la llanta del motor contra el suelo y contra los cases de los
  servos).
- `-DCMAKE_POLICY_DEFAULT_CMP0057=NEW` — ODE declara
  `cmake_minimum_required(2.8.12)`; bajo ese scope `CMP0057` queda en OLD y el
  `IN_LIST` del `flags.cmake` del NDK revienta.
- `-G "Unix Makefiles"` — en esta caja Asahi no hay ninja nativo.

## Lo que este build NO tiene

- **`cylinder↔cylinder` no existe.** Dos llantas de dos motores se
  atravesarían, y en silencio (`dCollide` devuelve 0 sin avisar). Hoy hay un
  motor. Si algún día hay dos, esto es lo primero que hay que mirar.
- **`capsule↔cylinder` tampoco existe**, y por eso las cápsulas están
  prohibidas en todo el mecano: `dCreateCapsule` ni siquiera está en los
  bindings, y `CapsuleShape` lanza.
- **En Android, solo `arm64-v8a`.** Cualquier otro ABI cae en el fallo blando de
  `ode_library.dart` (`isAvailable == false`) y ve la pantalla honesta. En Apple
  no pasa: al compilarse desde fuentes, cada SDK y cada arquitectura salen
  solos, device y simulador incluidos.
- **Linux y web siguen sin ODE**, y por el mismo fallo blando.

## Una deuda conocida: los globales de glibc en los bindings

`ode_bindings.dart` resuelve por nombre nueve globales que no son de ODE sino de
`<stdio.h>` y `<time.h>` heredados del árbol de includes: `stdin`, `stdout`,
`stderr`, `signgam`, `timezone`, `tzname`, `daylight`, `__timezone` y
`__tzname`. **Ni en Darwin ni en MSVC existen con ese nombre** (allí son `__stdinp` y
compañía), así que si alguien los leyera, en un iPhone lanzaría.

No lanza hoy porque son `late final` y **nadie los toca** (comprobado: cero usos
fuera del propio fichero generado). Si algún día se regeneran los bindings,
conviene añadir un `globals: exclude` a `ffigen.template.yaml` y quitarlos.

## Licencia

ODE es **doble licencia: BSD de 3 cláusulas o LGPL 2.1+**, a elección de quien
lo usa. **Nairda toma la BSD**, que no impone obligaciones de distribución a un
producto comercial. Las dos licencias están copiadas en este repo
(`LICENSE-ODE-BSD.txt`, `LICENSE-ODE-LGPL.txt`).

**Pendiente de producto:** la atribución BSD tiene que aparecer en la pantalla
de licencias de Nairda cuando el constructor llegue a la app.
