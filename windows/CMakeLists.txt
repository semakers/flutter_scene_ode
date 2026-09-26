# El plugin FFI para Windows.
#
# Aqui NO viaja binario: se compilan las 75 unidades del arbol vendorizado, que
# es lo mismo que hace el podspec en iOS y macOS. En Android es al reves (el
# .so va precompilado en jniLibs/) porque alli hace falta el NDK; en Windows el
# compilador ya esta en la maquina que construye la app, asi que no hay motivo
# para meter un binario en el repo.
#
# El arbol vive en ../ios/Classes, que es la copia CANONICA. No hay una tercera
# copia en windows/ a proposito: la duplicacion ios/macos existe porque
# Pod::Sandbox::PathList de CocoaPods no desciende por un symlink de directorio
# (el pod salia VACIO y el archive VERDE), y esa limitacion es de CocoaPods, no
# de CMake. Salir del directorio es ademas el patron oficial: la plantilla
# plugin_ffi de Flutter hace add_subdirectory("../src"), y el
# windows/CMakeLists.txt de nairda_compiler ya referencia ../dist en produccion,
# a traves del mismo symlink de .plugin_symlinks.
cmake_minimum_required(VERSION 3.14)

# LANGUAGES incluye C: de las 75 unidades, ode/src/nextafterf.c no es C++.
# La plantilla de Flutter solo declara CXX y el fichero no compilaria.
project(flutter_scene_ode LANGUAGES CXX C)

set(ODE_TREE "${CMAKE_CURRENT_SOURCE_DIR}/../ios/Classes")

if(NOT EXISTS "${ODE_TREE}/ode/src/ode.cpp")
  message(FATAL_ERROR
    "flutter_scene_ode: no encuentro el arbol vendorizado en ${ODE_TREE}. "
    "Corre tool/vendor_ode.sh.")
endif()

# CONFIGURE_DEPENDS: si alguien vendoriza otra version, cmake se re-ejecuta solo
# en vez de construir con la lista de ayer.
file(GLOB_RECURSE ODE_SOURCES CONFIGURE_DEPENDS
  "${ODE_TREE}/ode/src/*.cpp"
  "${ODE_TREE}/ode/src/*.c"
  "${ODE_TREE}/ou/src/*.cpp"
  "${ODE_TREE}/ou/src/*.c"
)

# El mismo cotejo que `[ "$N" -eq 75 ]` de tool/verify_apple.sh. Un glob que se
# queda corto no da error: da una DLL a la que le faltan simbolos, y eso solo se
# ve al abrir un mecano.
list(LENGTH ODE_SOURCES ODE_UNIDADES)
if(NOT ODE_UNIDADES EQUAL 75)
  message(FATAL_ERROR
    "flutter_scene_ode: esperaba 75 unidades de compilacion y encontre ${ODE_UNIDADES}. "
    "Ver tool/vendor_ode.sh.")
endif()

# LA TRAMPA QUE MATA EL BUILD DE LA APP Y NO EL DE AQUI.
#
# nairda_robot_programming/windows/CMakeLists.txt:33 hace
# `add_definitions(-DUNICODE -D_UNICODE)` ANTES de incluir
# generated_plugins.cmake, y eso es una propiedad de DIRECTORIO: la hereda el
# add_subdirectory de este plugin. Con UNICODE, `MessageBox` es MessageBoxW y
# ode/src/error.cpp:145 le pasa un char[1000] -> error C2664, y muere el build
# entero por UNA unidad de las 75.
#
# ODE es ANSI de 2006 de arriba abajo. No se le pone UNICODE: se le quita.
# tool/verify_windows.ps1 mete UNICODE a proposito en su arnes, porque si no
# daria VERDE y la app moriria despues.
remove_definitions(-DUNICODE -D_UNICODE)

# El target se llama `ode` y no `flutter_scene_ode` A PROPOSITO: produce ode.dll, que
# es literalmente lo que busca lib/src/ode/ode_library.dart en Windows
# (`Platform.isWindows ? 'ode.dll' : ...`). Renombrarlo obliga a tocar el Dart.
add_library(ode SHARED ${ODE_SOURCES})

target_include_directories(ode PRIVATE
  "${ODE_TREE}/generated"
  "${ODE_TREE}/include"
  "${ODE_TREE}/ode/src"
  "${ODE_TREE}/ode/src/joints"
  "${ODE_TREE}/ou/include"
)

# Los mismos defines que los dos podspecs y que tool/build_vendored_host.sh. No
# se toca ninguno sin tocar los otros tres sitios: un ODE distinto por plataforma
# es un bug que solo aparece en la plataforma rara.
#
# ODE_DLL + ODE_EXPORTS: en Windows, y SOLO en Windows, include/ode/odeconfig.h
# los convierte en ODE_API = __declspec(dllexport). Sin ellos la DLL se
# construiria sin exportar un solo simbolo y DynamicLibrary.open la abriria
# igual: el fallo seria mudo.
#
# dIDESINGLE: precision simple, obligatorio. Los bindings tienen dReal =
# ffi.Float clavado y un ODE en doble precision no da error de enlace: LEE
# BASURA. assertOdeAbi() lo caza en caliente, pero mejor no llegar ahi.
target_compile_definitions(ode PRIVATE
  ODE_DLL
  ODE_EXPORTS
  dIDESINGLE
  dNODEBUG
  dOU_ENABLED
  dATOMICS_ENABLED
  dBUILTIN_THREADING_IMPL_ENABLED
  _OU_NAMESPACE=odeou
  _OU_FEATURE_SET=_OU_FEATURE_SET_ATOMICS
  # NDEBUG a mano y en TODAS las configuraciones. En Release MSVC ya lo pone,
  # pero en Debug no, y sin el los OU_ASSERT quedan vivos llamando a abort():
  # seria un ODE distinto del que corre en Android y en Apple. Misma razon por
  # la que esta escrito a mano en los podspecs.
  NDEBUG
  # <math.h> de MSVC no define M_PI salvo con esto, y entonces
  # include/ode/common.h:43 lo definiria el mismo como
  # REAL(3.1415926535897932...) que en precision simple es un FLOAT. En glibc y
  # en Darwin math.h ya lo trae como double y ese #ifndef ni dispara. Sin esta
  # linea Windows correria una fisica numericamente distinta de la de las otras
  # plataformas, y no lo notaria nadie.
  _USE_MATH_DEFINES
  # <windows.h> define min y max como macros y rompe std::min/std::max y
  # cualquier metodo que se llame asi. Lo arrastra ou/ y threading_pool_win.cpp.
  NOMINMAX
  WIN32_LEAN_AND_MEAN
  # ODE usa strcpy/sprintf por todas partes: son avisos C4996 de MSVC, no
  # errores, pero ahogan el log donde estan los errores de verdad.
  _CRT_SECURE_NO_WARNINGS
)

target_compile_features(ode PRIVATE cxx_std_17)

if(MSVC)
  # /EHsc: modelo de excepciones de C++. Sin el, MSVC avisa en cada unidad.
  # /O1: favorece tamano, que es el equivalente del -Os del resto de builds.
  # Los wd son ruido de conversiones numericas de codigo de 2006; apagarlos
  # deja ver los errores. No se apaga ningun error, solo avisos.
  #
  # /O1 va por configuracion y NO en Debug a proposito: CMAKE_CXX_FLAGS_DEBUG de
  # MSVC trae /RTC1, y cl corta con «D8016: '/RTC1' and '/O1' are incompatible».
  #
  # /MP: el generador de Visual Studio paraleliza entre PROYECTOS, no entre las
  # unidades de uno. Esto es un solo proyecto con 75 unidades, asi que sin /MP
  # se compilan en serie — y la maquina que construye Windows tiene 4 nucleos.
  target_compile_options(ode PRIVATE
    /EHsc
    /MP
    /bigobj
    $<$<CONFIG:Release>:/O1>
    $<$<CONFIG:Profile>:/O1>
    /wd4244 /wd4267 /wd4305 /wd4996 /wd4577
  )
endif()

# La unica dependencia de sistema que no es kernel32 ni el CRT: el MessageBox de
# ode/src/error.cpp. Viene por defecto en CMAKE_CXX_STANDARD_LIBRARIES de MSVC,
# pero explicito documenta que no hay ninguna otra (nada de winmm): lo demas es
# QueryPerformanceCounter en timer.cpp y _beginthreadex en threading_pool_win.cpp.
target_link_libraries(ode PRIVATE user32)

# Esto es lo unico que hace que la DLL viaje junto al .exe. Flutter copia al
# directorio de salida todo lo que aparezca en <plugin>_bundled_libraries; sin
# esta linea la DLL se construye, se queda en el arbol de build y la app se
# distribuye sin fisica sin que nadie se entere.
set(flutter_scene_ode_bundled_libraries
  "$<TARGET_FILE:ode>"
  PARENT_SCOPE
)
