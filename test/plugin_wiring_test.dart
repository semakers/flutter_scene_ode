import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El cableado nativo es plomería, y la plomería falla EN SILENCIO: si el pod
/// de Apple o el CMakeLists de Windows no entran en el build, `flutter_scene_ode` no
/// revienta — devuelve `isAvailable == false` y el niño ve la pantalla honesta,
/// igual que en un aparato sin soporte. Este banco no compila nada; solo cuida
/// que las piezas que hacen que el binario exista sigan estando y sigan
/// diciendo lo que tienen que decir. Corre en cualquier máquina: no necesita ni
/// un Mac ni una PC Windows delante.
///
/// La comprobación de verdad (que el símbolo acabó DENTRO del binario) la hacen
/// `ci_shared/verificar_ode.sh` sobre el archive de Apple,
/// `ci_shared/verificar_ode_windows.ps1` sobre el Release de Windows, y
/// `tool/verify_windows.ps1` antes de gastar un build entero.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final ios = File('ios/flutter_scene_ode.podspec');
  final macos = File('macos/flutter_scene_ode.podspec');
  final cmake = File('windows/CMakeLists.txt');

  /// SIN los comentarios. Estos ficheros explican en prosa las decisiones que
  /// aquí se comprueban, así que un `contains` sobre el texto entero se
  /// reconocería a sí mismo y el guard no probaría nada — que es exactamente
  /// como el guard de idempotencia del Podfile de la app dejó pasar seis builds
  /// vacíos.
  String soloCodigo(File f) => f
      .readAsLinesSync()
      .where((l) => !l.trimLeft().startsWith('#'))
      .join('\n');

  group('el plugin se declara para las cuatro plataformas nativas', () {
    test('pubspec.yaml las trae todas con ffiPlugin', () {
      // Sin esto no lo mira nadie: `flutter pub get` no anota el paquete en
      // .flutter-plugins-dependencies, `pod install` ni se entera y el
      // generated_plugins.cmake de Windows no incluye el add_subdirectory.
      for (final plataforma in ['android', 'ios', 'macos', 'windows']) {
        expect(
          RegExp('^ {6}$plataforma:\$', multiLine: true).hasMatch(pubspec),
          isTrue,
          reason: 'falta la plataforma $plataforma en flutter.plugin.platforms',
        );
      }
      expect('ffiPlugin: true'.allMatches(pubspec).length, 4);
    });

    test('los dos podspecs existen', () {
      expect(ios.existsSync(), isTrue);
      expect(macos.existsSync(), isTrue);
    });
  });

  group('las fuentes vendorizadas', () {
    for (final raiz in ['ios/Classes', 'macos/Classes']) {
      test('$raiz: son las 75 unidades del build bueno', () {
        final unidades = Directory(raiz)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.cpp') || f.path.endsWith('.c'))
            .length;
        // 74 .cpp + nextafterf.c. Si este número baja, algo se dejó de copiar y
        // el enlace de Apple fallaría con símbolos indefinidos.
        expect(unidades, 75);
      });

      test('$raiz: están las cabeceras que cmake generaba', () {
        expect(File('$raiz/generated/config.h').existsSync(), isTrue);
        expect(File('$raiz/generated/apple_compat.h').existsSync(), isTrue);
        // precision.h y version.h SÍ vienen en el tarball (a diferencia de
        // config.h), así que no se escriben a mano.
        expect(File('$raiz/include/ode/precision.h').existsSync(), isTrue);
        expect(File('$raiz/include/ode/version.h').existsSync(), isTrue);
      });

      test('$raiz: son DIRECTORIOS de verdad, no un symlink', () {
        // Esto no es quisquillosidad: `Pod::Sandbox::PathList` precalcula los
        // ficheros del pod con `Dir.glob(raiz + '**/*')`, y el `**` de Ruby NO
        // desciende por un symlink de directorio. Con symlink, `source_files`
        // devuelve [], el pod se construye VACÍO y el archive sale verde.
        // Comprobado con el CocoaPods 1.16.2 de verdad, y sufrido en el build
        // #230, que archivó sin compilar ni una unidad de ODE.
        expect(Link(raiz).existsSync(), isFalse, reason: '$raiz es un symlink');
        for (final d in ['$raiz/ode/src', '$raiz/ou/src/ou', '$raiz/include/ode']) {
          expect(Link(d).existsSync(), isFalse, reason: '$d es un symlink');
          expect(Directory(d).existsSync(), isTrue);
        }
      });
    }

    test('las cabeceras que chocan con la libc siguen siendo cuatro', () {
      // Si aparece una quinta, hay que saberlo: es la lista que justifica
      // USE_HEADERMAP = NO, y la que decide si un `#include <x.h>` del árbol
      // puede acabar resolviendo a sí mismo.
      const libc = {
        'assert.h', 'complex.h', 'ctype.h', 'errno.h', 'fenv.h', 'float.h',
        'inttypes.h', 'iso646.h', 'limits.h', 'locale.h', 'math.h', 'memory.h',
        'setjmp.h', 'signal.h', 'stdarg.h', 'stdatomic.h', 'stdbool.h',
        'stddef.h', 'stdint.h', 'stdio.h', 'stdlib.h', 'string.h', 'tgmath.h',
        'threads.h', 'time.h', 'uchar.h', 'wchar.h', 'wctype.h', 'malloc.h',
        'alloca.h',
      };
      final choques = Directory('ios/Classes')
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where(libc.contains)
          .toSet();
      expect(choques, {'assert.h', 'inttypes.h', 'malloc.h', 'memory.h'});
    });

    test('las dos copias son iguales', () {
      // vendor_ode.sh las escribe a la vez; esto caza que alguien toque una y
      // se olvide de la otra.
      String huella(String raiz) {
        final fs = Directory(raiz)
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => '${f.path.substring(raiz.length)}:${f.lengthSync()}')
            .toList()
          ..sort();
        return fs.join('\n');
      }

      expect(huella('macos/Classes'), huella('ios/Classes'));
    });

    test('config.h es el MISMO fichero en las dos copias, byte a byte', () {
      // La huella de arriba compara ruta:tamaño, así que un cambio de la MISMA
      // longitud en una sola copia se colaría — y config.h es justo el fichero
      // que se edita a mano.
      expect(
        File('macos/Classes/generated/config.h').readAsStringSync(),
        File('ios/Classes/generated/config.h').readAsStringSync(),
      );
    });
  });

  group('lo que el podspec no puede perder', () {
    for (final entry in {'ios': ios, 'macos': macos}.entries) {
      final texto = soloCodigo(entry.value);

      test('${entry.key}: sigue sin ser static_framework', () {
        // Es LA decisión que hace que los símbolos sobrevivan: con
        // `ffiPlugin` nada referencia a ODE desde Objective-C, y en un
        // framework estático el enlazador se llevaría los objetos por delante.
        expect(texto.contains('s.static_framework'), isFalse);
      });

      test('${entry.key}: exporta los símbolos', () {
        // ODE_API está vacío fuera de Windows: sin esto el dylib sale sin
        // tabla de exportación y DynamicLibrary.process() no ve nada.
        expect(texto.contains("'GCC_SYMBOLS_PRIVATE_EXTERN' => 'NO'"), isTrue);
      });

      test('${entry.key}: compila en precisión simple', () {
        // Los bindings tienen dReal = ffi.Float. En doble precisión no habría
        // error de enlace: leería basura.
        expect(texto.contains('dIDESINGLE=1'), isTrue);
      });

      test('${entry.key}: mete apple_compat.h con -include', () {
        // Sin el `isnanf` que aporta esa cabecera, ODE NO COMPILA en Darwin.
        expect(texto.contains('-include'), isTrue);
        expect(texto.contains('apple_compat.h'), isTrue);
      });

      test('${entry.key}: sigue sin header maps', () {
        // Xcode indexa el mapa de cabeceras POR NOMBRE DE FICHERO y lo consulta
        // antes que el sistema. El árbol de ODE trae cuatro que chocan con la
        // libc, y con el mapa puesto `#include <assert.h>` resuelve a
        // `ou/assert.h`. Tumbó el build #231 con 20 "use of undeclared
        // identifier 'assert'".
        expect(texto.contains("'USE_HEADERMAP' => 'NO'"), isTrue);
      });

      test('${entry.key}: compila con NDEBUG', () {
        // cmake lo pone en MinSizeRel y Xcode no lo pone nunca. Sin él, Apple
        // compilaría un ODE distinto del de Android y del que valida el banco,
        // con los OU_ASSERT vivos llamando a abort().
        expect(texto.contains('NDEBUG=1'), isTrue);
      });

      test('${entry.key}: conserva el mapeo de cabeceras', () {
        // ODE tiene ficheros con el mismo nombre en include/ode y en ode/src
        // (common.h, error.h, matrix.h...). Aplanados se pisan.
        expect(texto.contains("s.header_mappings_dir"), isTrue);
      });

      test('${entry.key}: los include paths apuntan a sitios que existen', () {
        final rutas = RegExp(r'\$\(PODS_TARGET_SRCROOT\)/Classes/([^"]*)')
            .allMatches(texto)
            .map((m) => m.group(1)!)
            .toSet();
        expect(rutas, isNotEmpty);
        for (final r in rutas) {
          final p = '${entry.key}/Classes/$r';
          expect(
            Directory(p).existsSync() || File(p).existsSync(),
            isTrue,
            reason: 'el podspec de ${entry.key} apunta a $p, que no existe',
          );
        }
      });
    }

    test('macos define MAC_OS_X_VERSION y iOS no lo necesita', () {
      // ou/include/ou/platform.h corta con un #error si el target es MAC y no
      // está definido; en iOS lo fija ella sola.
      expect(soloCodigo(macos).contains('MAC_OS_X_VERSION=1050'), isTrue);
      expect(soloCodigo(ios).contains('MAC_OS_X_VERSION'), isFalse);
    });
  });

  group('lo que el CMakeLists de Windows no puede perder', () {
    final texto = soloCodigo(cmake);

    test('existe', () {
      // Con `windows: ffiPlugin: true` en el pubspec y sin este fichero, el
      // add_subdirectory de generated_plugins.cmake mata el build de la app.
      expect(cmake.existsSync(), isTrue);
    });

    test('el target se llama `ode`, y el Dart busca ode.dll', () {
      // Las dos mitades del mismo contrato, juntas a propósito: el nombre del
      // target de CMake ES el nombre del fichero que Flutter copia junto al
      // .exe, y `ode_library.dart` lo abre por ese nombre. Renombrar uno sin el
      // otro no da error de compilación: da la pantalla honesta.
      expect(texto.contains('add_library(ode SHARED'), isTrue);
      expect(
        File('core/lib/src/ode/ode_library_ffi.dart').readAsStringSync().contains("'ode.dll'"),
        isTrue,
      );
    });

    test('compila el árbol canónico y NO hay una tercera copia', () {
      // La duplicación ios/macos existe por una limitación de CocoaPods
      // (Pod::Sandbox::PathList no desciende por symlinks), no de CMake. Salir
      // del directorio es además el patrón oficial de la plantilla plugin_ffi
      // de Flutter, y lo que ya hace nairda_compiler en producción.
      expect(texto.contains('../ios/Classes'), isTrue);
      expect(Directory('windows/Classes').existsSync(), isFalse);
    });

    test('exige las 75 unidades', () {
      // Un glob que se queda corto no da error: da una DLL a la que le faltan
      // símbolos, y eso solo se ve al abrir un mecano.
      expect(texto.contains('EQUAL 75'), isTrue);
    });

    // Los defines los coteja el grupo «un solo ODE en las seis plataformas»,
    // contra tool/ode_defines.txt y para los seis builders a la vez.

    test('quita el UNICODE que hereda de la app', () {
      // nairda_robot_programming/windows/CMakeLists.txt hace
      // add_definitions(-DUNICODE -D_UNICODE) ANTES de incluir
      // generated_plugins.cmake, y eso se hereda por add_subdirectory. Con
      // UNICODE, `MessageBox` es MessageBoxW y ode/src/error.cpp:145 le pasa un
      // char[1000]: error C2664, y muere el build entero por UNA unidad.
      // Comprobado en la PC del laboratorio quitando esta línea a propósito.
      expect(texto.contains('remove_definitions'), isTrue);
      expect(texto.contains('UNICODE'), isTrue);
    });

    test('apaga las macros min/max de <windows.h>', () {
      // convex.cpp usa std::min, y ou/atomic.h arrastra <windows.h>.
      expect(texto.contains('NOMINMAX'), isTrue);
    });

    test('pide M_PI a math.h en vez de dejar que ODE lo invente', () {
      // Sin _USE_MATH_DEFINES, <math.h> de MSVC no define M_PI, e
      // include/ode/common.h:43 lo definiría él mismo como REAL(3.14...) — que
      // en precisión simple es un FLOAT. En glibc y en Darwin math.h ya lo trae
      // como double y ese #ifndef ni dispara. Sin esto Windows correría una
      // física numéricamente distinta de la del resto, y no lo notaría nadie.
      expect(texto.contains('_USE_MATH_DEFINES'), isTrue);
    });

    test('le pide a Flutter que copie la DLL junto al .exe', () {
      // Sin esto la DLL se construye, se queda en el árbol de build y la app se
      // distribuye sin física sin que nadie se entere.
      expect(texto.contains('flutter_scene_ode_bundled_libraries'), isTrue);
      expect(texto.contains(r'$<TARGET_FILE:ode>'), isTrue);
      expect(texto.contains('PARENT_SCOPE'), isTrue);
    });

    test('NO llama a apply_standard_settings', () {
      // Añade /W4 /WX: cada C4244 de código de 2006 se volvería fatal. Y ata el
      // fichero a una función que solo existe en el CMake de la app, lo que
      // impediría verificarlo suelto con tool/verify_windows.ps1.
      expect(texto.contains('apply_standard_settings'), isFalse);
    });

    test('no fija _OU_TARGET_OS a mano', () {
      // ou/include/ou/platform.h lo autodetecta. Fijarlo es una forma de
      // equivocarse de plataforma sin enterarse; misma decisión que en Apple.
      expect(texto.contains('_OU_TARGET_OS'), isFalse);
    });

    test('los include paths apuntan a sitios que existen', () {
      final rutas = RegExp(r'\$\{ODE_TREE\}/([^"\s]*)')
          .allMatches(texto)
          .map((m) => m.group(1)!)
          .toSet();
      expect(rutas, isNotEmpty);
      for (final r in rutas) {
        // De un glob (`ode/src/*.cpp`) se comprueba el directorio: lo que
        // interesa es que la ruta base exista, no que haya un fichero llamado
        // literalmente `*.cpp`.
        final rel = r.contains('*') ? r.substring(0, r.lastIndexOf('/')) : r;
        final p = 'ios/Classes/$rel';
        expect(
          Directory(p).existsSync() || File(p).existsSync(),
          isTrue,
          reason: 'el CMakeLists apunta a $p, que no existe',
        );
      }
    });

    test('existe el banco corto que evita gastar un build entero', () {
      expect(File('tool/verify_windows.ps1').existsSync(), isTrue);
    });
  });

  group('config.h contempla MSVC', () {
    final config = File('ios/Classes/generated/config.h').readAsStringSync();

    test('tiene su propia rama', () {
      // Sin ella, MSVC caía en el #else de glibc y el propio config.h hacía
      // #include <alloca.h>, que en MSVC no existe.
      expect(config.contains('#elif defined(_MSC_VER)'), isTrue);
    });

    test('no le pide a MSVC lo que MSVC no tiene', () {
      final rama = ramaDeConfig(config, '#elif defined(_MSC_VER)');

      // alloca la trae <malloc.h>: es lo único innegociable, porque
      // ode/src/common.h la usa a pelo en dALLOCA16.
      expect(rama.contains('#define HAVE_MALLOC_H'), isTrue);

      // Se busca `#define X` y no `X` a secas: las líneas `/* #undef X */`
      // contienen el nombre y darían un falso positivo.
      for (final m in [
        'HAVE_ALLOCA_H',
        'HAVE_UNISTD_H',
        'HAVE_SYS_TIME_H',
        'HAVE_GETTIMEOFDAY',
        'HAVE_PTHREAD_CONDATTR_SETCLOCK',
      ]) {
        expect(rama.contains('#define $m'), isFalse, reason: '$m no existe en MSVC');
      }

      // Y las seis de isnan van SIN definir a propósito: la cadena de
      // include/ode/common.h:298-314 cae entonces en `_isnan`, que es
      // literalmente «the VC way» según el comentario de upstream. Definir
      // HAVE__ISNANF haría que dIsNan usara `_isnanf`, cuya presencia en la
      // UCRT no está garantizada.
      for (final m in [
        'HAVE_ISNAN',
        'HAVE_ISNANF',
        'HAVE__ISNAN',
        'HAVE__ISNANF',
        'HAVE___ISNAN',
        'HAVE___ISNANF',
      ]) {
        expect(rama.contains('#define $m'), isFalse, reason: '$m: ver el comentario de la rama');
      }
    });
  });

  test('el stub no promete de menos', () {
    // Es el texto que ve quien abra el constructor donde no hay backend, y ha
    // ido quedándose corto dos veces: primero decía «solo Android», luego
    // «Android, iOS, macOS o Windows» cuando web ya tenía WebAssembly. Un
    // mensaje honesto es media función de este paquete.
    final stub = File('core/lib/src/ode_unsupported.dart').readAsStringSync();
    expect(stub.contains('solo para Android'), isFalse);
    expect(stub.contains('WebAssembly'), isTrue,
        reason: 'web ya tiene backend: el motivo no puede decir que no');
  });

  group('un solo ODE en las seis plataformas', () {
    // POR QUÉ ESTE GRUPO
    // ------------------
    // El mismo árbol lo compilan seis builders con seis sintaxis distintas, y
    // no pueden leerse un fichero común: el podspec es Ruby que CocoaPods
    // evalúa en el runner y no puede salir del directorio del pod sin romper
    // `pod lib lint`. Así que no se comparte el fichero, se comparte la VERDAD,
    // y se coteja desde aquí.
    //
    // Un ODE distinto por plataforma es un bug que solo aparece en la
    // plataforma rara. Ya pasó con M_PI en Windows.
    final canonicos = _definesCanonicos();

    test('la lista canónica tiene lo que tiene que tener', () {
      expect(canonicos, contains('dIDESINGLE'),
          reason: 'precisión simple: los bindings tienen dReal clavado a Float');
      expect(canonicos, contains('NDEBUG'));
      expect(canonicos.length, greaterThanOrEqualTo(9));
    });

    // Los que REPITEN la lista, porque no pueden leerla: los podspecs son Ruby
    // que CocoaPods evalúa en el runner, y el CMakeLists de Windows lo incluye
    // la app. tool/build_ode_wasm.sh NO está aquí a propósito: ése sí la lee, y
    // eso lo comprueba el test de abajo.
    for (final builder in const [
      'ios/flutter_scene_ode.podspec',
      'macos/flutter_scene_ode.podspec',
      'windows/CMakeLists.txt',
      'tool/build_vendored_host.sh',
    ]) {
      test('$builder pasa todos los defines canónicos', () {
        final texto = File(builder).readAsStringSync();
        for (final d in canonicos) {
          // El nombre a secas vale igual que `X=1`: cada builder lo escribe a
          // su manera y lo que importa es que el define esté.
          final nombre = d.split('=').first;
          expect(texto.contains(nombre), isTrue,
              reason: 'a $builder le falta el define $d');
        }
      });
    }

    test('build_ode_wasm.sh los LEE de la lista, no los repite', () {
      // Es el builder nuevo y el único que puede leerla: es bash y el fichero
      // está a su lado. Que la lea es lo que impide que sea la quinta copia que
      // se queda atrás — y por eso NO se le exige que contenga los nombres.
      final texto = File('tool/build_ode_wasm.sh').readAsStringSync();
      expect(texto.contains('ode_defines.txt'), isTrue);
      for (final d in canonicos) {
        final nombre = d.split('=').first;
        expect(texto.contains('-D$nombre'), isFalse,
            reason: 'build_ode_wasm.sh repite $nombre en vez de leerlo');
      }
    });

    test('nadie fija _OU_TARGET_OS a mano', () {
      // ou/include/ou/platform.h lo autodetecta: GENUNIX por __unix__ (que
      // emscripten SÍ predefine, comprobado), IOS/MAC en Apple, WINDOWS en
      // MSVC. Clavarlo es una forma de equivocarse de plataforma sin
      // enterarse, y está en la sección [jamas] de la lista canónica.
      for (final builder in const [
        'ios/flutter_scene_ode.podspec',
        'macos/flutter_scene_ode.podspec',
        'windows/CMakeLists.txt',
        'tool/build_vendored_host.sh',
        'tool/build_ode_wasm.sh',
      ]) {
        expect(File(builder).readAsStringSync().contains('_OU_TARGET_OS='),
            isFalse,
            reason: '$builder fija _OU_TARGET_OS');
      }
    });
  });

  group('config.h contempla emscripten', () {
    final config = File('ios/Classes/generated/config.h').readAsStringSync();

    test('tiene su propia rama', () {
      // Sin ella, emscripten caía en el #else de glibc, que define
      // HAVE___ISNANF — y musl no tiene __isnanf.
      expect(config.contains('#elif defined(__EMSCRIPTEN__)'), isTrue);
    });

    test('no le pide a musl lo que musl no tiene', () {
      final rama = ramaDeConfig(config, '#elif defined(__EMSCRIPTEN__)');
      expect(rama, isNotEmpty);
      // Se busca `#define X`: las líneas `/* #undef X */` llevan el nombre y
      // darían un falso positivo.
      for (final m in ['HAVE___ISNAN', 'HAVE___ISNANF']) {
        expect(rama.contains('#define $m'), isFalse,
            reason: '$m es una extensión de glibc; musl no la tiene');
      }
      // Y la que sí, que es la que salva la cadena de common.h:298-314.
      expect(rama.contains('#define HAVE_ISNANF'), isTrue);
    });

    test('la identificación de plataforma no cae en el #error', () {
      // Emscripten no define __linux__ ni __APPLE__: sin rama propia, el build
      // moría en «Need some help identifying the platform!».
      final desde = config.indexOf('Try to identify the platform');
      expect(config.indexOf('#elif defined(__EMSCRIPTEN__)', desde),
          greaterThan(desde));
    });

    test('existe emscripten_compat.h en las dos copias, y son iguales', () {
      final a = File('ios/Classes/generated/emscripten_compat.h');
      final b = File('macos/Classes/generated/emscripten_compat.h');
      expect(a.existsSync(), isTrue);
      expect(b.existsSync(), isTrue);
      expect(a.readAsStringSync(), b.readAsStringSync());
      // Lo mismo que hace apple_compat.h, y por lo mismo.
      expect(a.readAsStringSync().contains('isnanf'), isTrue);
    });

    test('el build de wasm mete emscripten_compat.h con -include', () {
      // Igual que el podspec con apple_compat.h: así entra antes que nada,
      // venga la unidad de compilación por donde venga.
      final texto = File('tool/build_ode_wasm.sh').readAsStringSync();
      expect(texto.contains('-include'), isTrue);
      expect(texto.contains('emscripten_compat.h'), isTrue);
    });
  });

  group('el backend de web', () {
    test('el barrel tiene su rama de js_interop', () {
      // El barrel con las TRES ramas es el del núcleo puro (`core/`); el del
      // plugin solo lo re-exporta.
      final barrel = File('core/lib/flutter_scene_ode_core.dart').readAsStringSync();
      expect(barrel.contains('dart.library.js_interop'), isTrue);
      expect(barrel.contains('ode_web.dart'), isTrue);
    });

    test('el asset se llama igual que lo que busca el cargador', () {
      // Mismo contrato que `add_library(ode SHARED)` -> ode.dll: renombrarlo no
      // da error de compilación, da la pantalla honesta.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      // El que nombra el asset es el PLUGIN (bundle_web.dart): el núcleo puro
      // no sabe qué es un bundle y solo recibe los bytes.
      final cargador = File('lib/src/bundle_web.dart').readAsStringSync();
      expect(pubspec.contains('assets/ode.wasm'), isTrue);
      expect(pubspec.contains('assets/ode.js'), isTrue);
      expect(cargador.contains('packages/flutter_scene_ode/assets/ode.wasm'), isTrue);
      expect(cargador.contains('packages/flutter_scene_ode/assets/ode.js'), isTrue);
    });

    test('la física es UNA sola: ode_simulation.dart no sabe de plataformas',
        () {
      // La costura entera vive en los imports. Si alguien mete un kIsWeb aquí,
      // es que empezó a haber dos físicas.
      final fisica = File('core/lib/src/ode/ode_simulation.dart').readAsStringSync();
      expect(fisica.contains('kIsWeb'), isFalse);
      // Se mira el IMPORT, no la mención: los comentarios de ese fichero
      // hablan de `dart:ffi` para explicar la costura, y un `contains` a secas
      // los contaría. (Mismo tropiezo que el recuento de plataformas del
      // pubspec: aquí las cadenas del código y las de la prosa conviven.)
      expect(RegExp("^import 'dart:ffi'", multiLine: true).hasMatch(fisica),
          isFalse,
          reason: 'debe pasar por ffi_shim.dart');
      expect(RegExp("^import 'package:ffi/ffi.dart'", multiLine: true)
          .hasMatch(fisica), isFalse,
          reason: 'debe pasar por ffi_alloc.dart');
      expect(fisica.contains("import 'ffi_shim.dart' as ffi;"), isTrue);
    });

    test('la cara nativa del shim reexporta dart:ffi pelado', () {
      // Es lo que garantiza diff CERO en Android, iOS, macOS y Windows.
      expect(
        File('core/lib/src/ode/ffi_shim_native.dart').readAsStringSync(),
        contains("export 'dart:ffi';"),
      );
    });
  });
}
/// El trozo de `config.h` que va de [marcador] a la siguiente rama.
///
/// Corta por el siguiente `#elif` O `#else`, el que llegue antes: cortar solo
/// por `#else` hace que la última rama antes del `#else` se trague a todas las
/// que le metan detrás, y el test empieza a hablar de una rama mientras mira
/// otra.
String ramaDeConfig(String config, String marcador) {
  final desde = config.indexOf(marcador);
  if (desde < 0) return '';
  final finales = [
    config.indexOf('\n#elif', desde + marcador.length),
    config.indexOf('\n#else', desde + marcador.length),
  ].where((i) => i >= 0);
  return config.substring(desde, finales.isEmpty ? config.length : finales.reduce((a, b) => a < b ? a : b));
}

/// Los defines de la sección `[todos]` de tool/ode_defines.txt.
List<String> _definesCanonicos() {
  final lineas = File('tool/ode_defines.txt').readAsLinesSync();
  final desde = lineas.indexWhere((l) => l.trim() == '[todos]');
  var hasta = lineas.indexWhere((l) => l.startsWith('[solo-'), desde + 1);
  if (hasta < 0) hasta = lineas.length;
  return [
    for (final l in lineas.sublist(desde + 1, hasta))
      if (l.trim().isNotEmpty && !l.startsWith('#')) l.trim(),
  ];
}
