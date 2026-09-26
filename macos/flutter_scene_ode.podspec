#
# Gemelo de ios/flutter_scene_ode.podspec: el pod de macOS COMPILA ODE desde las
# fuentes de src/, sin vendorizar ningún binario. El porqué está entero en el de
# iOS; aquí solo cambian tres cosas: la plataforma, FlutterMacOS y
# MAC_OS_X_VERSION.
#
# Que compile desde fuentes también arregla lo del arco: no hay slice que
# elegir, así que el target de macOS no tiene que fijar ARCHS por culpa nuestra
# (a diferencia de nairda_compiler, que sí es un .a de arm64).
#
# La receta y la procedencia de las fuentes están en NATIVE.md y en
# tool/vendor_ode.sh (que las copia del tarball oficial con el sha256
# verificado). En Android NO se usa esto: allí el .so viaja precompilado.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_scene_ode'
  s.version          = '0.1.0'
  s.summary          = 'ODE (Open Dynamics Engine) physics backend for flutter_scene'
  s.homepage         = 'https://gitlab.com/amiba_proteus/flutter_scene_ode'
  # Sin `:file`: la ruta con `..` hace fallar `pod lib lint`. La copia de la
  # licencia vive en LICENSE-ODE-BSD.txt, en la raíz del paquete.
  s.license          = { :type => 'BSD-3-Clause' }
  s.author           = 'Adrián Álvarez'
  s.source           = { :path => '.' }
  s.platform         = :osx, '10.14'

  # Un podspec no puede referenciar rutas por encima de su directorio, así que
  # Classes es un symlink a ../src. Es lo que hace la plantilla oficial de
  # plugin FFI de Flutter.
  s.source_files = 'Classes/**/*.{c,cpp,h}'

  # NINGUNA cabecera es pública: ODE es un detalle de implementación al que solo
  # llega Dart por FFI. Y el mapeo hay que conservarlo: ODE tiene ficheros con
  # el MISMO nombre en include/ode y en ode/src (common.h, error.h, matrix.h,
  # misc.h, objects.h, odemath.h, timer.h...). Si CocoaPods los aplanara en
  # Pods/Headers, se pisarían unos a otros.
  s.private_header_files = 'Classes/**/*.h'
  s.header_mappings_dir  = 'Classes'

  s.libraries = 'c++'

  # NO se declara `s.static_framework`. El Podfile de la app usa
  # `use_frameworks!`, así que sin esa línea el pod se construye como framework
  # DINÁMICO, que es justo lo que hace falta:
  #
  #   - Con `ffiPlugin: true` no hay clase de plugin y NADA referencia a ODE
  #     desde Objective-C. En un framework estático el enlazador descartaría los
  #     objetos que nadie usa y el archive saldría verde y vacío; habría que
  #     parchear OTHER_LDFLAGS de Pods-Runner con -force_load o con 84 `-Wl,-u`.
  #     Un dylib enlaza todos sus objetos por construcción.
  #   - Y esquiva el strip: de un dylib no se pueden quitar los símbolos
  #     globales sin romperlo (ver el comentario de ios/Flutter/Release.xcconfig
  #     en la app, que existe por eso mismo).
  #
  # Aun así, ci_shared/verificar_ode.sh comprueba con nm que dInitODE2 acabó
  # DENTRO del binario: esto es plomería, y la plomería se verifica.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',

    # SIN header maps, y esto no es una manía: Xcode construye un mapa de
    # cabeceras del target INDEXADO POR NOMBRE DE FICHERO, y lo consulta antes
    # que los directorios del sistema. El árbol de ODE trae cuatro cabeceras
    # cuyo nombre choca con las de la libc —`ou/assert.h`, `ou/inttypes.h`,
    # `ou/malloc.h` y `ode/memory.h`—, así que `#include <assert.h>` acababa
    # resolviendo a la de ou, que ya estaba incluida y por tanto vacía: 20
    # errores de "use of undeclared identifier 'assert'". Tumbó el build #231.
    #
    # No hace falta el mapa para nada: HEADER_SEARCH_PATHS de abajo dice
    # exactamente dónde está cada cosa.
    'USE_HEADERMAP' => 'NO',

    # ODE_API está VACÍO fuera de Windows (include/ode/odeconfig.h): las
    # funciones no llevan visibility("default"). Con la visibilidad oculta por
    # defecto, el dylib saldría sin tabla de exportación y
    # DynamicLibrary.process() no encontraría nada.
    'GCC_SYMBOLS_PRIVATE_EXTERN' => 'NO',

    # Los mismos defines que el build bueno de cmake, con una ausencia
    # deliberada: _OU_TARGET_OS NO se define, que ou/include/ou/platform.h
    # detecta macOS solo. Lo que sí exige esa cabecera cuando el target es MAC
    # es MAC_OS_X_VERSION, y sin él corta con un #error; 1050 es el mismo valor
    # que pone la cmake de ODE. (En iOS lo fija ella sola, por eso allí no
    # está.)
    #
    # dIDESINGLE es innegociable: los bindings declaran dReal = ffi.Float y un
    # build en doble precisión NO daría error de enlace, leería basura.
    #
    # NDEBUG lo pone cmake en MinSizeRel y Xcode no lo pone en ninguna
    # configuración, así que sin esta línea Apple compilaría un ODE DISTINTO del
    # que se envía en Android y del que valida todo el banco de pruebas: con los
    # OU_ASSERT vivos, una aserción fallida llama a abort() y la app se muere en
    # las manos del niño en vez de que la física haga algo raro.
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) ODE_DLL=1 ODE_EXPORTS=1 ' \
      'dIDESINGLE=1 dNODEBUG=1 dOU_ENABLED=1 dATOMICS_ENABLED=1 ' \
      'NDEBUG=1 dBUILTIN_THREADING_IMPL_ENABLED=1 _OU_NAMESPACE=odeou ' \
      '_OU_FEATURE_SET=_OU_FEATURE_SET_ATOMICS MAC_OS_X_VERSION=1050',

    'HEADER_SEARCH_PATHS' => '$(inherited) ' \
      '"$(PODS_TARGET_SRCROOT)/Classes/generated" ' \
      '"$(PODS_TARGET_SRCROOT)/Classes/include" ' \
      '"$(PODS_TARGET_SRCROOT)/Classes/ode/src" ' \
      '"$(PODS_TARGET_SRCROOT)/Classes/ode/src/joints" ' \
      '"$(PODS_TARGET_SRCROOT)/Classes/ou/include"',

    # apple_compat.h le da a Darwin el `isnanf` que ODE busca para `dIsNan` en
    # precisión simple. Sin él NO COMPILA: common.h cae en `_isnan`, que es el
    # nombre de Visual C. Va con -include para que entre antes que todo, venga
    # la unidad de compilación por donde venga.
    #
    # -Wno-deprecated-declarations: la rama Apple de ou/include/ou/atomic.h llama
    # a una veintena de funciones OSAtomic*, deprecadas desde iOS 10 pero
    # perfectamente vivas en el SDK. Son avisos, no errores, pero llenarían el
    # log del runner y se volverían fatales el día que alguien encienda
    # GCC_TREAT_WARNINGS_AS_ERRORS.
    'OTHER_CFLAGS' => '$(inherited) -Wno-deprecated-declarations ' \
      '-include "$(PODS_TARGET_SRCROOT)/Classes/generated/apple_compat.h"',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -Wno-deprecated-declarations ' \
      '-include "$(PODS_TARGET_SRCROOT)/Classes/generated/apple_compat.h"',

    'CLANG_CXX_LANGUAGE_STANDARD' => 'gnu++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'CLANG_WARN_DOCUMENTATION_COMMENTS' => 'NO',

    # MinSizeRel, como el build de Android. ODE es del tamaño de la app, no del
    # bucle interno: lo que cuesta tiempo son los pasos de física, no el código.
    'GCC_OPTIMIZATION_LEVEL' => 's',

    # Redundante con el framework dinámico (de un dylib no se pueden quitar los
    # globales sin romperlo), pero escrito cuesta una línea y quita la duda.
    'DEAD_CODE_STRIPPING' => 'NO',
  }

  s.dependency 'FlutterMacOS'
end
