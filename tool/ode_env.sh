#!/usr/bin/env bash
# Rutas y versiones compartidas por los tres scripts de tool/.
# Todo lo pesado (fuentes y builds) va a .ode-work/, ignorado por git y
# reproducible.
# Se puede reapuntar con las variables de entorno.

ODE_VERSION="${ODE_VERSION:-0.16.6}"
# sha256 del tarball oficial de sourceforge. fetch_ode.sh ABORTA si no cuadra.
ODE_SHA256="${ODE_SHA256:-c91a28c6ff2650284784a79c726a380d6afec87ecf7a35c32a6be0c5b74513e8}"
ODE_URL="${ODE_URL:-https://bitbucket.org/odedevs/ode/downloads/ode-${ODE_VERSION}.tar.gz}"

# Dónde se descomprimen las fuentes y dónde se compila.
ODE_WORK="${ODE_WORK:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.ode-work}"
ODE_SRC="${ODE_SRC:-$ODE_WORK/src/ode-$ODE_VERSION}"
ODE_BUILD_DIR="${ODE_BUILD_DIR:-$ODE_WORK/build}"

# Emscripten, para el build de WebAssembly (tool/build_ode_wasm.sh). Vive en el
# disco externo por lo mismo que ODE_WORK: son ~1,5 GB y /home va al 95 %.
# Solo `latest` publica binarios arm64-linux, así que la version se pincha A
# POSTERIORI en tool/emsdk_version.txt, que se commitea junto al .wasm.
EMSDK_ROOT="${EMSDK_ROOT:-$HOME/emsdk}"
ODE_WASM_BUILD="${ODE_WASM_BUILD:-$ODE_BUILD_DIR/wasm}"

# Una sola fuente de verdad para el NDK, compartida con android/build.gradle
# (que la lee de android/gradle.properties con este mismo valor por defecto).
NDK_VERSION="${NDK_VERSION:-27.0.12077973}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_HOME:-$HOME/dev/android-sdk}/ndk/$NDK_VERSION}"

# El triple del host se DERIVA: el prebuilt del NDK es x86_64 y corre bajo qemu
# en esta caja aarch64, pero en un Mac sería darwin-*. Clavarlo es lo que impide
# correr esto en otra máquina.
case "$(uname -s)" in
  Linux)  NDK_HOST_TAG="linux-x86_64" ;;
  Darwin) NDK_HOST_TAG="darwin-x86_64" ;;
  *)      NDK_HOST_TAG="linux-x86_64" ;;
esac
NDK_TOOLBIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$NDK_HOST_TAG/bin"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
