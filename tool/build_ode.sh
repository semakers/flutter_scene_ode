#!/usr/bin/env bash
# Compila libode. Dos objetivos:
#   android  -> arm64-v8a con el NDK (es lo que se envía; ya está commiteado
#               en android/src/main/jniLibs/, así que esto NO hace falta para
#               construir la app: es la receta para reproducirlo)
#   host     -> la caja actual, para el banco de tests de Dart puro
#               (`scene` es Dart puro: los tests corren sin Flutter ni qemu)
#
# Uso: tool/build_ode.sh android|host
set -euo pipefail
source "$(dirname "$0")/ode_env.sh"

TARGET="${1:-android}"
"$(dirname "$0")/fetch_ode.sh"

CMAKE="${CMAKE:-/usr/bin/cmake}"

COMMON_FLAGS=(
  -G "Unix Makefiles"           # no hay ninja nativo en esta caja Asahi
  # ODE declara cmake_minimum_required(2.8.12); bajo ese scope CMP0057 queda
  # OLD y el IN_LIST del flags.cmake del NDK revienta. Forzamos el default.
  -DCMAKE_POLICY_DEFAULT_CMP0057=NEW
  -DCMAKE_BUILD_TYPE=MinSizeRel
  -DODE_WITH_DEMOS=OFF
  -DODE_WITH_TESTS=OFF
  -DODE_WITH_OPCODE=OFF
  -DODE_WITH_GIMPACT=OFF
  # libccd APAGADO, y no es solo por peso: con libccd ON, ODE_WITH_LIBCCD_BOX_CYL
  # viene ON y SUSTITUYE el collider nativo cylinder-box, que es justo la única
  # pareja que de verdad usamos (la llanta contra el suelo y contra los cases).
  -DODE_WITH_LIBCCD=OFF
  # Los bindings tienen `dReal = ffi.Float` clavado: doble precisión leería
  # basura sin dar un solo error de enlace. ode_library.dart lo verifica en
  # caliente con dCheckConfiguration.
  -DODE_DOUBLE_PRECISION=OFF
  -DBUILD_SHARED_LIBS=ON
)

case "$TARGET" in
  android)
    BUILD="$ODE_BUILD_DIR/android-arm64"
    [ -d "$ANDROID_NDK_HOME" ] || { echo "no existe el NDK: $ANDROID_NDK_HOME" >&2; exit 1; }
    "$CMAKE" -S "$ODE_SRC" -B "$BUILD" "${COMMON_FLAGS[@]}" \
      -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
      -DANDROID_ABI=arm64-v8a \
      -DANDROID_PLATFORM=android-24 \
      -DANDROID_STL=c++_static
    "$CMAKE" --build "$BUILD" -j"$(nproc)"
    "$NDK_TOOLBIN/llvm-strip" --strip-unneeded "$BUILD"/libode.so*
    echo "== peso =="; ls -l "$BUILD"/libode.so
    echo "== sanidad =="
    "$NDK_TOOLBIN/llvm-readelf" -h "$BUILD/libode.so" | grep -E 'Class|Machine'
    "$NDK_TOOLBIN/llvm-readelf" -d "$BUILD/libode.so" | grep -i soname || echo "(sin SONAME)"
    "$NDK_TOOLBIN/llvm-nm" -D "$BUILD/libode.so" | grep -q dWorldQuickStep && echo "dWorldQuickStep: OK"
    echo
    echo "para enviarlo:  cp $BUILD/libode.so $REPO_ROOT/android/src/main/jniLibs/arm64-v8a/"
    ;;
  host)
    BUILD="$ODE_BUILD_DIR/host"
    "$CMAKE" -S "$ODE_SRC" -B "$BUILD" "${COMMON_FLAGS[@]}"
    "$CMAKE" --build "$BUILD" -j"$(nproc)"
    ls -l "$BUILD"/libode.so*
    echo
    echo "para los tests:  ODE_LIBRARY_PATH=$BUILD/libode.so flutter test"
    ;;
  *) echo "objetivo desconocido: $TARGET (android|host)" >&2; exit 1;;
esac
