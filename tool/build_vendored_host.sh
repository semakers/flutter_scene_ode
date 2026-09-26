#!/usr/bin/env bash
# Compila el árbol vendorizado de src/ para ESTA máquina, sin cmake, con los
# mismos defines e includes que usará el podspec de Apple.
#
# Es la única verificación previa que existe: en Apple compila Xcode Cloud, y
# cada vuelta allí son ~16 minutos. Si falta un fichero en src/, si config.h
# está incompleto o si un símbolo de los bindings no acaba definido, se ve aquí
# en un minuto.
#
# No sustituye a tool/build_ode.sh: aquél usa cmake sobre las fuentes de fuera
# del repo y es el que produce el .so de Android que se envía.
#
# Uso:
#   tool/build_vendored_host.sh
#   ODE_LIBRARY_PATH=<lo que imprime> ~/dev/flutter-3471/bin/flutter test
set -euo pipefail
source "$(dirname "$0")/ode_env.sh"

VENDOR="$REPO_ROOT/ios/Classes"
OUT="${ODE_BUILD_DIR}/vendored-host"
LIB="$OUT/libode.so"

[ -d "$VENDOR/ode/src" ] || { echo "no hay arbol vendorizado: corre tool/vendor_ode.sh" >&2; exit 1; }

# Los mismos que el build de cmake que ya funciona, con una diferencia
# deliberada: _OU_TARGET_OS NO se define. ou/include/ou/platform.h lo autodetecta
# (GENUNIX aquí, IOS o MAC en Apple) y fijarlo a mano es una forma de
# equivocarse de plataforma sin enterarse.
DEFINES=(
  -DODE_DLL -DODE_EXPORTS
  -DdIDESINGLE -DdNODEBUG
  -DdOU_ENABLED -DdATOMICS_ENABLED -DdBUILTIN_THREADING_IMPL_ENABLED
  -D_OU_NAMESPACE=odeou -D_OU_FEATURE_SET=_OU_FEATURE_SET_ATOMICS
)
INCLUDES=(
  -I"$VENDOR/generated"
  -I"$VENDOR/include"
  -I"$VENDOR/ode/src"
  -I"$VENDOR/ode/src/joints"
  -I"$VENDOR/ou/include"
)

rm -rf "$OUT"
mkdir -p "$OUT/obj"

mapfile -t SRCS < <(find "$VENDOR/ode/src" "$VENDOR/ou/src" -name '*.cpp' -o -name '*.c' | sort)
echo "compilando ${#SRCS[@]} unidades..."

JOBS="$(nproc)"
compilar_uno() {
  local f="$1" o
  o="$OUT/obj/$(echo "${f#$VENDOR/}" | tr / _).o"
  case "$f" in
    *.c)   cc  -Os -DNDEBUG -fPIC "${DEFINES[@]}" "${INCLUDES[@]}" -c "$f" -o "$o" ;;
    *.cpp) c++ -Os -DNDEBUG -fPIC "${DEFINES[@]}" "${INCLUDES[@]}" -c "$f" -o "$o" ;;
  esac
}
export OUT VENDOR
export -f compilar_uno
printf '%s\n' "${SRCS[@]}" | DEFINES="${DEFINES[*]}" INCLUDES="${INCLUDES[*]}" \
  xargs -P "$JOBS" -I{} bash -c '
    set -e
    f="{}"
    o="$OUT/obj/$(echo "${f#$VENDOR/}" | tr / _).o"
    read -r -a D <<< "$DEFINES"
    read -r -a I <<< "$INCLUDES"
    case "$f" in
      *.c)   cc  -Os -DNDEBUG -fPIC "${D[@]}" "${I[@]}" -c "$f" -o "$o" ;;
      *.cpp) c++ -Os -DNDEBUG -fPIC "${D[@]}" "${I[@]}" -c "$f" -o "$o" ;;
    esac'

c++ -shared -o "$LIB" "$OUT"/obj/*.o
echo "$LIB"

# El cotejo que de verdad importa: que los símbolos que los bindings buscan por
# nombre en runtime estén TODOS definidos. La lista canónica es la misma que usa
# ffigen; si alguien añade una función a los bindings y no está en la librería,
# el fallo sería un StateError en el teléfono, no aquí.
echo "cotejando los símbolos de ffigen.template.yaml..."
# nm a un fichero y luego grep SOBRE EL FICHERO, nunca `nm | grep -q`: con
# `set -o pipefail`, grep -q cierra la tubería, nm muere de SIGPIPE (141) y el
# pipeline da error JUSTO CUANDO ENCUENTRA el símbolo. Ya costó un build entero
# la vez anterior que se escribió así.
nm -D --defined-only "$LIB" > "$OUT/symbols.txt"
FALTAN=0
while read -r sym; do
  grep -qE "[[:space:]]T[[:space:]]$sym\$" "$OUT/symbols.txt" || {
    echo "  FALTA: $sym" >&2; FALTAN=$((FALTAN + 1)); }
done < <(sed -n '/^functions:/,/^structs:/p' "$REPO_ROOT/ffigen.template.yaml" \
           | sed -n 's/^ *- \([A-Za-z_][A-Za-z0-9_]*\) *$/\1/p')
if [ "$FALTAN" -ne 0 ]; then
  echo "ABORTA: $FALTAN símbolos de los bindings no están en la librería" >&2
  exit 1
fi
echo "los símbolos de los bindings están todos."
