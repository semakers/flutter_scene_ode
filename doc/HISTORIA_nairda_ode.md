## 0.5.1 — escribir la masa deshacía el estado cinemático (2026-08-30)

Un defecto **silencioso** que sólo se destapó al pedirle al backend lo que
nunca se le había pedido: un cuerpo que no se mueva. Lo destapó el banco nuevo
`ode_kinematic_test.dart`, que nace con las piezas fijas del mecano.

`dBodySetKinematic` funciona poniendo `invMass` e `invI` a **cero** — así es
como la gravedad y los impactos dejan de moverlo, porque el integrador
multiplica las fuerzas por la inversa. `dBodySetMass` las vuelve a rellenar y
**no toca el flag**: el cuerpo se quedaba marcado como cinemático y cayéndose a
la vez.

Y el orden en que pasa es el natural: `createBody(type: kinematic)` seguido de
`createColliders`, que es quien deriva la masa. O sea, **declarar un cuerpo
cinemático al crearlo no funcionaba**, y el síntoma era una pieza fija que se
cae como si nadie la hubiera fijado. Sin excepción, sin log y sin NaN.

Arreglado en `_recomputeBodyMass`, que es el embudo único por el que pasan las
dos ramas de masa (la simple y la del compuesto) y sus dos clientes
(`createColliders` y `setBodyAdditionalMass`): tras escribir la masa, si el
cuerpo es cinemático se reafirma el flag.

**El camino de siempre no cambia un dígito**: la reafirmación sólo corre para
cuerpos cinemáticos, y hasta hoy no había ninguno.

### El banco: 100 → 107

`ode_kinematic_test.dart` prueba lo que el mecano necesita poder prometer:

- una pieza fija **no cae** aunque la gravedad esté puesta y no haya nada
  debajo, mientras la de al lado sí;
- **no la empuja** lo que le cae encima (desplazamiento < 1e-9);
- pero **sigue chocando**: lo que cae encima se queda encima, y sigue
  parándolo **diez segundos después** — la contraprueba del autodisable, que
  duerme a los cuerpos quietos y un cinemático lo está por definición;
- se alterna **en vivo** dinámico → cinemático → dinámico, y al volver cae;
- a `fixed` **sigue sin poder cambiarse**, que es la razón de elegir
  `kinematic`;
- un cinemático conserva su `dBodyID`, así que `wakeBody`, las velocidades y
  `setBodyPose` **no lanzan** — con `fixed` lanzarían los cinco, y son
  exactamente lo que el editor del mecano usa para mover y para volver a la
  pose de borrador.

## 0.5.0 — ODE en WebAssembly (2026-08-29)

La sexta plataforma, y la única que no es nativa. Web era la que faltaba, y el
bloqueante era **solo ODE**: el fork de `flutter_scene` ya renderizaba en el
navegador desde agosto.

### Un solo motor de física, dos ABIs

`ode_simulation.dart` —las 1488 líneas de física ganadas con sangre, las masas
en gramos, la banda muerta del servo, los grupos de mecanismo— **no cambió su
lógica**. Cambiaron dos imports:

```dart
-import 'dart:ffi' as ffi;          +import 'ffi_shim.dart' as ffi;
-import 'package:ffi/ffi.dart';     +import 'ffi_alloc.dart';
```

En nativo esos ficheros reexportan `dart:ffi` pelado, así que **el diff de
comportamiento en Android, iOS, macOS y Windows es CERO**. En web resuelven a
un shim sobre el heap del módulo wasm: `Pointer<T>` es un extension type sobre
`int`, y los cuatro structs son clases-vista.

La alternativa era un segundo `OdeSimulation` para web. Dos copias de esta
física divergirían en silencio: una física distinta en el navegador que nadie
vería nunca.

**La rama por defecto del shim es la web**, a propósito: el analizador resuelve
por ella, así que `flutter analyze` type-chequea la física entera contra la ABI
web y cada hueco aparece en el editor. La rama nativa la prueba el banco, que
corre en la VM.

### Lo que se añadió

- `tool/build_ode_wasm.sh`: compila **las mismas 75 unidades de `ios/Classes`**
  con emscripten, más una 76ª nuestra (`tool/wasm/nairda_ode_layout.cpp`).
  Produce dos artefactos: el que se envía (`-Oz`) y uno paranoico
  (`ASSERTIONS=2 + SAFE_HEAP`) para el banco de node.
- `assets/ode.{js,wasm}` **commiteados**: web se comporta como Android, no como
  Apple/Windows. El binario viaja hecho y ninguna máquina que construya la app
  necesita emscripten. **122 604 bytes**, contra los 746 816 del `.so` de
  Android.
- `tool/ode_defines.txt`: la lista canónica de defines, cotejada por
  `plugin_wiring_test.dart` contra los cinco builders. Eran cuatro copias
  sueltas y esto habría sido la quinta.
- Rama `__EMSCRIPTEN__` en `config.h` y `emscripten_compat.h`, hermano exacto de
  `apple_compat.h`.
- `tool/gen_bindings_web.dart`: genera el gemelo web de los bindings desde la
  MISMA lista de `ffigen.template.yaml` y las MISMAS firmas del fichero de
  ffigen.
- `MecanoWorlds.ensureAvailable()` / `OdeSimulation.ensureAvailable()`: la carga
  en web es asíncrona y `isAvailable` es un getter. Nunca lanza.

### Las trampas que costaron algo

1. **Emscripten no define `__linux__`.** Sin rama propia, `config.h` moría en
   `#error "Need some help identifying the platform!"`. Sí define `__unix__`,
   así que `ou/platform.h` detecta GENUNIX solo y **no hay que forzar
   `_OU_TARGET_OS`** (que un test prohíbe).
2. **`isnanf` no existe en musl.** Es el MISMO agujero que Darwin: la cadena de
   `common.h:298-314` cae en `_isnan`, que es de Visual C. Lo aporta
   `emscripten_compat.h`, metido con `-include`.
3. **`wasmBinary` hay que declararlo en `INCOMING_MODULE_JS_API`.** La variante
   de release lo aceptaba **en silencio**; la paranoica abortó con el nombre
   exacto. Ese es el argumento entero para compilar las dos.
4. **Un miembro `external call(...)` en interop resuelve a
   `Function.prototype.call`**, que se come el primer argumento como `this`. El
   módulo se instanciaba SIN opciones, no veía los bytes y se iba a buscar el
   `.wasm` por URL. El síntoma —«both async and sync fetching of the wasm
   failed»— no menciona el argumento perdido. Se usa `callAsFunction`.
5. **`ALLOW_MEMORY_GROWTH=0`, deliberado.** Si la memoria creciera, las vistas
   `HEAPF32` quedarían desacopladas del búfer nuevo y toda lectura daría basura.
   Con 32 MB fijos —que a ODE le sobran— las vistas se cachean una vez y esa
   clase entera de heisenbugs no existe.
6. **`JSFloat32Array.toDart` es vista en dart2js pero COPIA en dart2wasm.** Con
   la copia, el shim escribiría donde ODE no lee jamás: la física quieta, sin un
   solo error. Hay dos caminos y una **prueba de ida y vuelta del heap** al
   arrancar.
7. **`flutter test --platform chrome` NO sirve el bundle de assets** — no hay ni
   una línea de assets en `flutter_web_platform.dart`. `rootBundle` se queda
   esperando y el test muere por timeout a los 30 s sin mencionar los assets.
   Por eso el banco le inyecta los bytes (`debugOdeModuleBytes`).

### Cómo se comprobó

- **Paridad nativo↔wasm, medida**: `tool/wasm/paridad.sh` corre el mismo
  escenario contra `libode.so` y contra `ode.wasm`. Los nueve invariantes
  coinciden **hasta la sexta cifra** (`y_final` 0.997174 en los dos, 483
  contactos en los dos). La divergencia por contracción FMA que se temía no
  apareció.
- **Los 34 tests de física corren en Chrome contra wasm sin cambiar una sola
  aserción** (`flutter test --platform chrome`). Son los mismos que codifican
  las alturas de reposo, el sueño, las inercias principales y la penetración.
- `tool/wasm/freefall.mjs`: ODE en node, cero Dart. Desmiente la hipótesis
  entera por 1/20 del coste de llegar al navegador.
- `ci_shared/verificar_ode_web.sh` en la app: la guardia contra el fallo blando,
  hermana de `verificar_ode.sh` y `verificar_ode_windows.ps1`.

## 0.4.0 — ODE en Windows (2026-08-29)

La cuarta plataforma nativa, y sin una tercera copia del árbol ni un binario
más en el repo: `windows/CMakeLists.txt` compila con MSVC **las mismas 75
unidades de `ios/Classes/`**.

Salir del directorio del plugin no es un atajo: la duplicación `ios/` ↔ `macos/`
existe porque `Pod::Sandbox::PathList` no desciende por un symlink de
directorio, y **esa limitación es de CocoaPods, no de CMake**. Además es el
patrón oficial (la plantilla `plugin_ffi` de Flutter hace
`add_subdirectory("../src")`) y ya estaba probado en producción en este mismo
proyecto por `nairda_compiler`.

### Lo que se añade

- `windows/CMakeLists.txt`, con el target llamado **`ode`** —no `flutter_scene_ode`—
  porque produce `ode.dll`, que es literalmente lo que abre `ode_library.dart`
  en Windows. El Dart no se tocó ni una línea: ya saltaba
  `DynamicLibrary.process()` en `Platform.isWindows` y ya buscaba ese nombre.
- La rama **`#elif defined(_MSC_VER)`** de `Classes/generated/config.h` (en las
  dos copias). Antes solo había `__APPLE__` y un `#else` que era glibc: MSVC
  caía ahí y el propio `config.h` hacía `#include <alloca.h>`.
- `tool/verify_windows.ps1`: compila el CMakeLists de verdad y coteja la DLL
  (75 objetos, símbolos exportados, precisión simple). Una vuelta es ~1 minuto
  contra los ~15 de un `flutter build windows` en la máquina de 4 núcleos.
- 28 casos nuevos en el banco de cableado, que pasó a llamarse
  `test/plugin_wiring_test.dart` (ya no es solo de Apple). Corren en Linux, sin
  Windows delante.

### Las dos trampas, y las dos costaban un build

**El `UNICODE` heredado.** El `windows/CMakeLists.txt` de la app hace
`add_definitions(-DUNICODE -D_UNICODE)` antes de incluir
`generated_plugins.cmake`, y eso es una propiedad de *directorio*: la hereda el
`add_subdirectory` del plugin. Con `UNICODE`, `MessageBox` es `MessageBoxW` y
`ode/src/error.cpp:145` le pasa un `char[1000]` → `error C2664`, y muere el
build entero por una unidad de las 75. Se quita con `remove_definitions`.

Lo insidioso es que **un banco que compile el plugin suelto no lo reproduce**,
porque el `UNICODE` no viene del plugin. Por eso el arnés de
`tool/verify_windows.ps1` lo mete a propósito. Comprobado en la máquina de
verdad quitando el `remove_definitions`: el banco pasa de verde a `C2664`.

**`M_PI` como float.** Sin `_USE_MATH_DEFINES`, `<math.h>` de MSVC no define
`M_PI` y `include/ode/common.h:43` lo define él mismo como `REAL(3.14159…)`, que
en precisión simple es un **float**. En glibc y en Darwin `math.h` ya lo trae
como `double` y ese `#ifndef` ni dispara. No rompe nada: haría que Windows
corriera una física numéricamente distinta de la del resto, y no se vería nunca.

### Lo que salió gratis

`include/ode/odeconfig.h` convierte `ODE_API` en `__declspec(dllexport)` con
`_MSC_VER` + `ODE_DLL`, y `ODE_DLL` ya lo pasaban todos los builds: **639
símbolos exportados** sin hacer nada. El problema que en Apple obligó a
`GCC_SYMBOLS_PRIVATE_EXTERN = NO` no existe aquí.

Y de `isnan`: dejando las seis `HAVE_*ISNAN*` **sin definir**, la cadena de
`common.h` cae en `_isnan`, que es literalmente «the VC way» según upstream.
Definir `HAVE__ISNANF` rompería el build, porque `_isnanf` no está garantizada
en la UCRT. Hay un test que lo blinda.

### Verificado

`ode.dll` de 353 792 B, x64, precisión simple, 639 símbolos. Y el juez de
verdad, en la PC del laboratorio: el constructor abierto dentro de Nairda **a 60
fps**, con un servo puesto y la física corriendo —`ode t=15.1s pen=0.000 nc=4`,
sin NaN—. Contraprueba: apartando `ode.dll`, la pantalla honesta con el motivo
exacto (`open(ode.dll): … error code: 126`).

## 0.3.0 — ODE en Apple (2026-08-28)

El plugin deja de ser solo de Android: **iOS y macOS** también, y sin
vendorizar un solo binario nuevo.

El camino no se eligió por elegante, se eligió porque no había otro: **ninguna
máquina del proyecto puede compilar para iOS**. Esta caja es Linux ARM64 y el
Mac solo tiene Command Line Tools, sin SDK de iPhone. Así que en vez de producir
un `.xcframework` que nadie puede producir, viajan las fuentes en `src/` y las
compila el podspec — o sea, Xcode Cloud.

### Lo que se añade

- `ios/Classes/` y `macos/Classes/`, con las **75 unidades de traducción
  exactas** que compila el build bueno de cmake, copiadas por
  `tool/vendor_ode.sh` desde el tarball con el sha256 verificado. `--check`
  avisa si divergieron.

  **Son dos copias, y son directorios de verdad, no symlinks.** El symlink es
  lo que hace la plantilla oficial de Flutter y **no funciona**:
  `Pod::Sandbox::PathList` precalcula los ficheros con `Dir.glob('**/*')`, y el
  `**` de Ruby no desciende por un symlink de directorio. `source_files`
  devuelve `[]`, el pod sale VACÍO y el archive verde. Medido con el CocoaPods
  1.16.2 del runner (0 ficheros con symlink, 196 con directorios) y sufrido en
  el build #230, que archivó sin compilar ni una unidad de ODE.
- `Classes/generated/config.h`, que cmake generaba, ahora escrito a mano con una
  rama para Darwin sondeada contra el SDK.
- `Classes/generated/apple_compat.h`. Sin él **ODE no compila en Darwin**:
  `common.h` busca `isnanf` para `dIsNan` en precisión simple y en Darwin no
  está declarado, así que cae en `_isnan`, que es el nombre de Visual C.
- `ios/flutter_scene_ode.podspec` y `macos/flutter_scene_ode.podspec`, framework **dinámico**
  a propósito: con `ffiPlugin` nada referencia a ODE desde Objective-C y un
  framework estático se quedaría sin objetos.
- `tool/build_vendored_host.sh`, que compila el árbol aquí sin cmake y coteja que
  los 84 símbolos de los bindings están definidos.
- `tool/verify_apple.sh`, que lo verifica **en el Mac**: compila las tres
  variantes contra sus SDK de verdad (macOS, iPhone y simulador) y luego deja
  que **CocoaPods construya el pod** (`pod lib lint` + `xcodebuild`) y comprueba
  con `nm` que el framework sale dinámico, con los símbolos exportados y en
  precisión simple. Son ~5 minutos contra los ~16 de una vuelta de nube, y
  cubren justo donde han estado todos los fallos.
- `Classes/apple-shim/CoreServices/CoreServices.h`, vacía: `timer.cpp` la incluye en
  la rama de Apple sin usar ni un símbolo de ella, y en iOS nadie de este
  proyecto puede comprobar que exista.
- `test/apple_plugin_wiring_test.dart`, 22 comprobaciones sobre la plomería que
  falla en silencio — incluida la de que `Classes/` no vuelva a ser un symlink.

### Lo que NO cambia

Android sigue igual: `libode.so` precompilado en `jniLibs/`, mismas banderas,
mismo `.so` byte a byte. La precisión sigue siendo simple y libccd sigue
apagado.

## 0.2.0 — Los compuestos (2026-08-28)

`CompoundShape` deja de caer en el `default:` de `createColliders`.

Nace con los **soportes** del mecano —las placas que el niño dibuja en una
matriz 3×3—, y el argumento es de honestidad: una placa en L tiene que chocar
como una L. Con una caja envolvente, las piezas se quedan apoyadas sobre el
hueco vacío y el simulador miente en algo que el niño ve.

### Qué se puede hacer ahora

- Un cuerpo con **varias formas primitivas** (cajas, esferas y cilindros), cada
  una con su pose: `createColliders` las abre, crea un geom por hoja y devuelve
  **un handle por hoja** — que es para lo que la firma del contrato siempre
  devolvió una lista, y lo que el `Collider` de flutter_scene ya sabía guardar.
- La corrección de eje del cilindro (Y del contrato → Z de ODE) se aplica **por
  hoja**, no por el compuesto.
- Los compuestos **anidados** se rechazan con su mensaje: que quede plano.

### La masa, que era el problema de verdad

`_applyBodyMass` **reemplazaba** la masa en cada collider, así que dos formas en
un cuerpo se pisaban y quedaba la inercia de la última. Ahora la masa se calcula
**una sola vez, con todos los colliders del cuerpo delante** (`_recomputeBodyMass`):

- con **un** collider pasa por el camino de siempre, dígito a dígito — los
  veinte goldens del arnés del mecano dependen de ello;
- con **varios** acumula: el tensor de cada hoja se le pide a ODE
  (`dMassSet*Total`), se lleva al frame del cuerpo con R·I·Rᵀ y se le suma el
  término de Steiner `m(|d|²δ − d⊗d)`. El struct `dMass` se escribe a mano desde
  Dart, así que no hicieron falta bindings nuevos.

Y `setBodyAdditionalMass` deja de re-derivar la masa **desde el primer
collider** — con un compuesto, el cuerpo se quedaba pesando lo que su primera
cajita. Hoy no disparaba (el fork pasa la masa en `createBody`), pero el día que
alguien tocara `rigid.mass` en caliente habría aparecido como una resonancia.

### La guarda que ODE no tiene

**El centro de masa de un compuesto tiene que caer en el origen del cuerpo.**
ODE lo fija ahí y este backend no re-centra, así que un compuesto descentrado
pivotaría alrededor de un punto que no es el suyo — sin error, sin log y sin
NaN. En vez de dejarlo pasar, se lanza: quien construye la forma sabe dónde está
su centroide y puede poner ahí el origen.

### El banco

`test/ode_compound_test.dart`, once pruebas sin teléfono. Las dos que sostienen
todo lo demás:

- **una caja compuesta == la misma caja suelta**, masa e inercia dígito a
  dígito (la regresión que protege los goldens del mecano);
- **el hueco de una L es hueco**: un testigo soltado sobre el cuadrante vacío
  llega al suelo, y sobre la chapa se queda encima. Con la caja envolvente, el
  primero se quedaría flotando.

## 0.1.0

* El backend de ODE promovido del spike: cuerpos, colliders Box/Sphere/Cylinder,
  juntas Revolute y Fixed, raycast nativo y grupos de mecanismo.
