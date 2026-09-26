# flutter_scene_ode

El backend de física de **ODE** (Open Dynamics Engine) detrás del contrato
`PhysicsSimulation` de `package:scene`. Es lo que hace que el mecano de Nairda
se caiga, choque y gire como si pesara.

No depende de `flutter_scene`: el backend es *headless*, y así el fork del
motor gráfico queda limpio.

## Plataformas

| | estado |
|---|---|
| Android (`arm64-v8a`) | `libode.so` precompilado y commiteado |
| iOS, macOS | el podspec compila las fuentes de `Classes/` |
| Windows (x64) | `windows/CMakeLists.txt` compila las MISMAS fuentes con MSVC |
| **Web** | **`assets/ode.wasm` precompilado y commiteado (122 KB)** |
| Linux | sin ODE — fallo blando |

**Nada revienta donde no hay ODE.** `openOdeLibrary()` devuelve `null` y guarda
el motivo; `OdeSimulation.isAvailable` es la pregunta que hay que hacer antes de
crear nada, y el mecano enseña su «pantalla honesta» en vez de caerse.

En web la carga es ASÍNCRONA (hay que descargar e instanciar el módulo), así que
antes de preguntar hay que esperar a **`OdeSimulation.ensureAvailable()`**. En
las plataformas nativas no espera a nada.

Todo el porqué del código nativo —las banderas, las 75 unidades que se compilan,
por qué libccd está apagado, por qué el pod de Apple es un framework dinámico y
cómo se compila a WebAssembly— está en [`NATIVE.md`](NATIVE.md).

## Una sola física para las seis plataformas

`core/lib/src/ode/ode_simulation.dart` (el núcleo Dart puro, desde el 2026-09-17) está escrito contra `dart:ffi` y **no tiene ni
un `kIsWeb`**. Lo único que cambia entre plataformas son sus dos imports:

```dart
import 'ffi_shim.dart' as ffi;   // -> dart:ffi        (nativo)
                                 // -> shim sobre wasm (web)
import 'ffi_alloc.dart';         // -> package:ffi     (nativo)
```

En nativo esos ficheros reexportan `dart:ffi` pelado: el diff de comportamiento
en Android, iOS, macOS y Windows es **cero**. Un segundo `OdeSimulation` para
web habría duplicado 1488 líneas de física (las masas en gramos, la banda muerta
del servo, los grupos de mecanismo) y las dos copias habrían divergido en
silencio.

La rama **por defecto** del shim es la web a propósito: el analizador resuelve
por ella, así que `flutter analyze` type-chequea la física entera contra la ABI
web. La nativa la prueba el banco, que corre en la VM.

## Compilar el módulo de WebAssembly

Solo hace falta si se toca el árbol de C++ o las banderas: el `.wasm` viaja
commiteado, igual que el `.so` de Android.

```bash
tool/build_ode_wasm.sh        # las 75 unidades + la sonda de layout
tool/vendor_wasm.sh           # -> assets/, bindings web, bytes del banco
tool/wasm/freefall.mjs        # ODE corriendo en node, cero Dart
tool/wasm/paridad.sh          # el mismo escenario, nativo contra wasm
```

## El banco de host: probar física sin teléfono

`scene` es Dart puro, así que los tests corren nativos en segundos, sin Android,
sin emulador y sin qemu:

```bash
tool/build_vendored_host.sh                        # compila el árbol para esta caja
ODE_LIBRARY_PATH=<lo que imprime el script> \
  ~/dev/flutter-3471/bin/flutter test
```

Es también la verificación previa de Apple: si al árbol le falta una unidad o
una cabecera, se ve aquí en un minuto y no en una vuelta de 16 en la nube. Y
`tool/verify_apple.sh` lo compila además **en el Mac**, contra el SDK de macOS.

### El mismo banco, contra WebAssembly

```bash
CHROME_EXECUTABLE=~/.cache/ms-playwright/chromium-1234/chrome-linux/chrome \
  ~/dev/flutter-3471/bin/flutter test --platform chrome \
  test/ode_simulation_test.dart test/ode_compound_test.dart \
  test/ode_raycast_test.dart test/ode_cylinder_test.dart
```

Son **los mismos 34 tests, sin cambiar una aserción**, y eso es justamente la
prueba de paridad: codifican las alturas de reposo, el sueño, las inercias
principales y la penetración, que es lo que de verdad importa que coincida.

`plugin_wiring_test.dart` se queda fuera de esa lista a propósito: es `dart:io`
de arriba abajo y no tiene nada que hacer en un navegador.

## Regenerar los bindings

```bash
tool/gen_bindings.sh
```

Lee `ffigen.template.yaml` (la lista explícita de los 84 símbolos que se
exponen) y coteja al final que `dReal` siga siendo `ffi.Float`, que estén las
funciones del cilindro y que `dCreateCapsule` **no** esté — las cápsulas están
prohibidas en el mecano porque este build no trae el collider
`capsule↔cylinder`.
