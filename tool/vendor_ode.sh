#!/usr/bin/env bash
# Copia al repo las fuentes de ODE que compila el pod de Apple.
#
# POR QUÉ HAY FUENTES DE ODE DENTRO DE ESTE REPO
# ----------------------------------------------
# En Android el binario viaja precompilado (android/src/main/jniLibs) porque
# aquí hay NDK. Para iOS y macOS NO hay ninguna máquina que pueda compilar: esta
# caja es Linux ARM64 y el Mac del proyecto solo tiene Command Line Tools, sin
# SDK de iPhone. El único compilador de Apple a mano es el del runner de Xcode
# Cloud, así que las fuentes tienen que viajar para que el pod las compile allí.
#
# Este script es la contraparte: deja claro QUÉ se copió y de dónde, para que el
# árbol no sea un montón de C++ del que nadie sabe el origen.
#
# POR QUÉ HAY DOS COPIAS Y NO UN SYMLINK
# --------------------------------------
# Lo natural sería tener el árbol una vez y que `ios/Classes` y `macos/Classes`
# fueran symlinks —es lo que hace la plantilla oficial de plugin FFI de
# Flutter—. **No funciona**, y falla EN SILENCIO: `Pod::Sandbox::PathList`
# precalcula los ficheros del pod con `Dir.glob(raiz + '**/*')`, y el `**` de
# Ruby NO desciende por un symlink de directorio. Resultado: `source_files` no
# encuentra nada, el pod se construye VACÍO, el archive sale verde y la app
# enseña la pantalla honesta.
#
# Comprobado con el CocoaPods 1.16.2 de verdad (el mismo del runner):
# `PathList#glob(['Classes/**/*.{c,cpp,h}'])` devuelve `[]` con el symlink, y
# devuelve los ficheros con directorios de verdad. Y confirmado en la nube: el
# build #230 archivó sin compilar ni una unidad de ODE.
#
# Uso:
#   tool/vendor_ode.sh            # copia (sobrescribe los dos Classes/)
#   tool/vendor_ode.sh --check    # NO toca nada; falla si alguno divergió
set -euo pipefail
source "$(dirname "$0")/ode_env.sh"

MODE="${1:-copy}"
# El primero es el canónico: es el que compilan tool/build_vendored_host.sh y
# tool/verify_apple.sh. El segundo es su espejo, y `--check` verifica los dos
# contra upstream, así que no pueden separarse sin que se note.
VENDORS="$REPO_ROOT/ios/Classes $REPO_ROOT/macos/Classes"
VENDOR="$REPO_ROOT/ios/Classes"

# Las 14 unidades de ode/src que NO se compilan. Son exactamente las que apagan
# los interruptores de NATIVE.md: trimesh (OPCODE/GIMPACT) y libccd. Se queda
# collision_trimesh_disabled.cpp, que es el que da los stubs.
EXCLUDE_CPP=(
  collision_convex_trimesh.cpp
  collision_cylinder_trimesh.cpp
  collision_libccd.cpp
  collision_trimesh_box.cpp
  collision_trimesh_ccylinder.cpp
  collision_trimesh_gimpact.cpp
  collision_trimesh_internal.cpp
  collision_trimesh_opcode.cpp
  collision_trimesh_plane.cpp
  collision_trimesh_ray.cpp
  collision_trimesh_sphere.cpp
  collision_trimesh_trimesh.cpp
  collision_trimesh_trimesh_old.cpp
  gimpact_contact_export_helper.cpp
)

esta_excluido() {
  local b="$1"
  for e in "${EXCLUDE_CPP[@]}"; do [ "$b" = "$e" ] && return 0; done
  return 1
}

# Vuelca el árbol vendorizado en $1. Las cabeceras se copian ENTERAS (son
# pequeñas y unas tiran de otras); lo que se filtra son las unidades de
# compilación.
poblar() {
  local dest="$1"
  mkdir -p "$dest/include/ode" "$dest/ode/src/joints" "$dest/ou/include/ou" "$dest/ou/src/ou"

  cp "$ODE_SRC"/include/ode/*.h            "$dest/include/ode/"
  cp "$ODE_SRC"/ode/src/*.h                "$dest/ode/src/"
  cp "$ODE_SRC"/ode/src/joints/*.h         "$dest/ode/src/joints/"
  cp "$ODE_SRC"/ou/include/ou/*.h          "$dest/ou/include/ou/"

  local f b
  for f in "$ODE_SRC"/ode/src/*.cpp; do
    b="$(basename "$f")"
    esta_excluido "$b" || cp "$f" "$dest/ode/src/"
  done
  cp "$ODE_SRC"/ode/src/nextafterf.c       "$dest/ode/src/"
  cp "$ODE_SRC"/ode/src/joints/*.cpp       "$dest/ode/src/joints/"
  for b in atomic customization malloc threadlocalstorage; do
    cp "$ODE_SRC/ou/src/ou/$b.cpp"         "$dest/ou/src/ou/"
  done
}

"$(dirname "$0")/fetch_ode.sh" >/dev/null

if [ "$MODE" = "--check" ]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  poblar "$TMP"
  FALLO=0
  for V in $VENDORS; do
    # generated/ es NUESTRO (config.h y apple_compat.h no salen del tarball),
    # así que se excluye.
    if diff -r -x generated "$TMP" "$V" >/dev/null 2>&1; then
      echo "$V coincide con ODE $ODE_VERSION"
    else
      echo "ABORTA: $V NO coincide con ODE $ODE_VERSION" >&2
      diff -r -x generated "$TMP" "$V" | head -20 >&2
      FALLO=1
    fi
  done
  # Y que las dos copias sean IDÉNTICAS entre sí, generated/ incluido: eso no
  # lo cubre la comparación de arriba.
  if ! diff -r $VENDORS >/dev/null 2>&1; then
    echo "ABORTA: las dos copias no son iguales entre sí" >&2
    diff -r $VENDORS | head -20 >&2
    FALLO=1
  fi
  exit "$FALLO"
fi

for V in $VENDORS; do
  rm -rf "$V/include" "$V/ode" "$V/ou"
  poblar "$V"
  CPP="$(find "$V" -name '*.cpp' | wc -l)"
  C="$(find "$V" -name '*.c' | wc -l)"
  H="$(find "$V" -name '*.h' -not -path '*/generated/*' | wc -l)"
  echo "vendorizado en $V: $CPP .cpp + $C .c + $H cabeceras"
done
echo "(se esperan 74 .cpp + 1 .c = las 75 unidades del build bueno, en cada copia)"
