#!/usr/bin/env bash
# Compila el árbol vendorizado de ios/Classes a WebAssembly con emscripten.
#
# Produce DOS artefactos:
#   $ODE_WASM_BUILD/release/ode.{js,wasm}  -> lo que se commitea en assets/
#   $ODE_WASM_BUILD/debug/ode.{js,wasm}    -> ASSERTIONS + SAFE_HEAP, para el
#                                             banco de node (tool/wasm/*.mjs)
#
# Web se comporta como ANDROID, no como Apple/Windows: el binario viaja
# commiteado y ninguna máquina que construya la app necesita emscripten jamás.
# Por eso aquí se compila una vez y el resultado se versiona.
#
# Uso:
#   tool/build_ode_wasm.sh              # los dos
#   tool/build_ode_wasm.sh release      # solo el que se envía
set -euo pipefail
source "$(dirname "$0")/ode_env.sh"

VENDOR="$REPO_ROOT/ios/Classes"
PROBE_SRC="$REPO_ROOT/tool/wasm"
OUT="$ODE_WASM_BUILD"
QUE="${1:-todo}"

[ -d "$VENDOR/ode/src" ] || { echo "no hay arbol vendorizado: corre tool/vendor_ode.sh" >&2; exit 1; }
[ -f "$EMSDK_ROOT/emsdk_env.sh" ] || {
  echo "no hay emsdk en $EMSDK_ROOT." >&2
  echo "  git clone --depth 1 https://github.com/emscripten-core/emsdk $EMSDK_ROOT" >&2
  echo "  cd $EMSDK_ROOT && ./emsdk install latest && ./emsdk activate latest" >&2
  echo "(solo 'latest' publica binarios arm64-linux; la version se pincha a" >&2
  echo " posteriori en tool/emsdk_version.txt)" >&2
  exit 1
}

# El emsdk trae su propio node y su propio clang. EM_CACHE va al disco externo
# junto al SDK: la primera compilación construye libc++ ahí y son cientos de MB.
export EM_CACHE="${EM_CACHE:-$EMSDK_ROOT/.cache}"
# shellcheck disable=SC1091
source "$EMSDK_ROOT/emsdk_env.sh" >/dev/null 2>&1

# ---------------------------------------------------------------- los defines
# De la lista canónica, sección [todos]. No hay una segunda copia aquí: si
# alguien añade un define, lo añade en un sitio y el test lo exige en los seis
# builders (test/plugin_wiring_test.dart).
mapfile -t DEFINE_NAMES < <(
  sed -n '/^\[todos\]/,/^\[solo-/p' "$REPO_ROOT/tool/ode_defines.txt" \
    | grep -vE '^#|^\[|^$'
)
DEFINES=()
for d in "${DEFINE_NAMES[@]}"; do DEFINES+=("-D$d"); done

INCLUDES=(
  -I"$VENDOR/generated"
  -I"$VENDOR/include"
  -I"$VENDOR/ode/src"
  -I"$VENDOR/ode/src/joints"
  -I"$VENDOR/ou/include"
)
# Igual que el podspec de Apple con apple_compat.h: entra ANTES que nada, venga
# la unidad de compilación por donde venga.
COMMON=(-include "$VENDOR/generated/emscripten_compat.h" "${DEFINES[@]}" "${INCLUDES[@]}")

# ------------------------------------------------------- la sonda de cabeceras
# Lo que la rama __EMSCRIPTEN__ de config.h AFIRMA, comprobado contra el SDK de
# verdad. Si algo de esto no está, config.h estaría mintiendo y el fallo
# aparecería como un error críptico dentro de ODE, no aquí.
echo "sondeando el SDK de emscripten (lo que afirma la rama de config.h)..."
PROBE="$OUT/probe.c"
mkdir -p "$OUT"
cat > "$PROBE" <<'PEOF'
#include <alloca.h>
#include <malloc.h>
#include <unistd.h>
#include <sys/time.h>
#include <sys/types.h>
#include <stdint.h>
#include <inttypes.h>
#include <math.h>
#include <pthread.h>
int main(void) {
  struct timeval tv; gettimeofday(&tv, 0);              /* HAVE_GETTIMEOFDAY */
  pthread_condattr_t a; pthread_condattr_init(&a);
  pthread_condattr_setclock(&a, CLOCK_MONOTONIC);       /* HAVE_PTHREAD_CONDATTR_SETCLOCK */
  volatile float f = 1.0f;
  return isnan(f) ? 1 : 0;                              /* HAVE_ISNAN */
}
PEOF
emcc -c "$PROBE" -o "$OUT/probe.o" || {
  echo "ABORTA: el SDK de emscripten no ofrece lo que config.h afirma." >&2
  echo "Ajusta la rama __EMSCRIPTEN__ de ios/Classes/generated/config.h" >&2
  echo "(y su espejo en macos/) en vez de suponer." >&2
  exit 1
}
echo "  el SDK cumple."

# ------------------------------------------------------------ las 75 unidades
mapfile -t SRCS < <(find "$VENDOR/ode/src" "$VENDOR/ou/src" \( -name '*.cpp' -o -name '*.c' \) | sort)
if [ "${#SRCS[@]}" -ne 75 ]; then
  echo "ABORTA: esperaba 75 unidades en el arbol vendorizado, encontre ${#SRCS[@]}." >&2
  echo "Si upstream cambio, actualiza tambien windows/CMakeLists.txt y el test." >&2
  exit 1
fi
# La 76a es NUESTRA (la sonda de layout), y por eso vive fuera de ios/Classes.
SRCS+=("$PROBE_SRC/nairda_ode_layout.cpp")

# --------------------------------------------------------- los exports
# La lista canónica es la MISMA que usa ffigen; si alguien añade una función a
# los bindings y no se exporta del .wasm, el fallo seria un TypeError en el
# navegador en vez de un error aqui. Mismo extractor que build_vendored_host.sh.
mapfile -t ODE_FUNCS < <(
  sed -n '/^functions:/,/^structs:/p' "$REPO_ROOT/ffigen.template.yaml" \
    | sed -n 's/^ *- \([A-Za-z_][A-Za-z0-9_]*\) *$/\1/p'
)
EXPORTS="_malloc,_free"
for f in "${ODE_FUNCS[@]}"; do EXPORTS="$EXPORTS,_$f"; done
for f in nairda_ode_layout nairda_ode_layout_count nairda_ode_layout_names \
         nairda_ode_configuration; do EXPORTS="$EXPORTS,_$f"; done
echo "${#ODE_FUNCS[@]} funciones de ffigen + malloc/free + 4 propias."

compilar() {   # compilar <variante> <flags de optimizacion...>
  local variante="$1"; shift
  local dir="$OUT/$variante"
  rm -rf "$dir"; mkdir -p "$dir/obj"
  echo "compilando ${#SRCS[@]} unidades ($variante)..."
  printf '%s\n' "${SRCS[@]}" \
    | COMMON="${COMMON[*]}" OPT="$*" DIR="$dir" VENDOR="$VENDOR" PROBE_SRC="$PROBE_SRC" \
      xargs -P "$(nproc)" -I{} bash -c '
        set -e
        f="{}"
        rel="${f#$VENDOR/}"; rel="${rel#$PROBE_SRC/}"
        o="$DIR/obj/$(echo "$rel" | tr / _).o"
        read -r -a C <<< "$COMMON"
        read -r -a O <<< "$OPT"
        case "$f" in
          *.c)   emcc "${O[@]}" "${C[@]}" -c "$f" -o "$o" ;;
          *.cpp) em++ -std=gnu++17 "${O[@]}" "${C[@]}" -c "$f" -o "$o" ;;
        esac'
}

enlazar() {   # enlazar <variante> <flags extra...>
  local variante="$1"; shift
  local dir="$OUT/$variante"
  echo "enlazando ($variante)..."
  em++ "$@" \
    -o "$dir/ode.js" "$dir"/obj/*.o \
    -sMODULARIZE=1 -sEXPORT_NAME=createNairdaOde -sEXPORT_ES6=0 \
    -sENVIRONMENT=web,node -sFILESYSTEM=0 -sSTRICT=1 -sINVOKE_RUN=0 --no-entry \
    -sALLOW_TABLE_GROWTH=1 \
    -sINCOMING_MODULE_JS_API=wasmBinary \
    -sALLOW_MEMORY_GROWTH=0 -sINITIAL_MEMORY=33554432 -sSTACK_SIZE=1048576 \
    -sABORTING_MALLOC=1 \
    -sEXPORTED_FUNCTIONS="$EXPORTS" \
    -sEXPORTED_RUNTIME_METHODS=addFunction,removeFunction,HEAPU8,HEAP32,HEAPU32,HEAPF32
  ls -l "$dir/ode.wasm" "$dir/ode.js" | awk '{print "  " $9 ": " $5 " bytes"}'
}

if [ "$QUE" = "todo" ] || [ "$QUE" = "release" ]; then
  # -Oz para igualar a MinSizeRel / -Os / /O1 de las otras cuatro plataformas.
  # emcc -Oz ya corre wasm-opt en el enlace: una segunda pasada no gana nada.
  compilar release -Oz
  enlazar  release -Oz -sASSERTIONS=0
fi
if [ "$QUE" = "todo" ] || [ "$QUE" = "debug" ]; then
  # La variante paranoica del banco de node: caza desbordes de pila y accesos
  # fuera del heap ANTES de que se conviertan en «la fisica va rara».
  compilar debug -O1 -g
  enlazar  debug -O1 -g -sASSERTIONS=2 -sSTACK_OVERFLOW_CHECK=2 -sSAFE_HEAP=1
fi

# ---------------------------------------------------- el cotejo de los exports
# nunca `grep -q` sobre una tuberia con pipefail: el productor muere de SIGPIPE
# JUSTO CUANDO ENCUENTRA la linea y el pipeline da error. Ya costo un build
# entero en Android. A fichero, y grep sobre el fichero.
printf '%s\n' "${ODE_FUNCS[@]}" nairda_ode_layout nairda_ode_layout_count \
  nairda_ode_layout_names nairda_ode_configuration > "$OUT/funciones.txt"

for variante in release debug; do
  [ -f "$OUT/$variante/ode.wasm" ] || continue
  echo "cotejando ($variante)..."
  # INSTANCIANDO el modulo, no leyendo el .wasm por fuera: con -Oz emscripten
  # minifica los nombres del export section (h, i, j...) y quien los vuelve a
  # nombrar es el glue JS. Lo que el shim de Dart tocara es exactamente esto.
  if [ "$variante" = "release" ]; then
    node "$PROBE_SRC/verify_module.mjs" "$OUT/$variante" "$OUT/funciones.txt" \
      --layout "$REPO_ROOT/tool/ode_wasm_layout.json"
  else
    node "$PROBE_SRC/verify_module.mjs" "$OUT/$variante" "$OUT/funciones.txt"
  fi
done

# A fichero y LUEGO la primera linea: `emcc -v | head -1` con pipefail devuelve
# 243, porque head cierra la tuberia y el python de emcc muere de BrokenPipe.
# Es la MISMA familia del `nm | grep -q` de build_vendored_host.sh.
emcc -v > "$OUT/emcc_v.txt" 2>&1
head -1 "$OUT/emcc_v.txt" > "$REPO_ROOT/tool/emsdk_version.txt"
echo
echo "hecho. release -> $OUT/release/ode.{js,wasm}"
