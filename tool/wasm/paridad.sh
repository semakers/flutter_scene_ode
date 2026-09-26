#!/usr/bin/env bash
# ¿La física que corre dentro de wasm es la MISMA que llevamos verificada en las
# cuatro plataformas nativas?
#
# Corre el mismo escenario dos veces —nativo contra libode.so y wasm dentro de
# node— y compara. Y compara lo que TIENE SENTIDO comparar: no trayectorias.
#
# Por qué no trayectorias: un sólido rígido con contactos es caóticamente
# sensible, y aquí hay DOS fuentes de divergencia garantizada. La menor son
# sin/cos de musl (wasm) contra glibc (host), que difieren en el último bit. La
# mayor es la CONTRACCIÓN FMA: el host compila con -ffp-contract=fast y funde
# a*b+c en un fmadd con redondeo único, y wasm MVP no tiene FMA, así que no
# puede reproducirlo. Divergen desde el paso 1, no desde el paso 500. Cualquier
# tolerancia trayectoria-a-trayectoria sería o inútil o intermitente.
#
# Lo que sí es estable y sí discrimina son los INVARIANTES del reposo: dónde
# descansa, cuánto se hunde, si duerme. Es la misma vara que usan los goldens
# del mecano y los 34 tests del banco.
set -euo pipefail
source "$(dirname "$0")/../ode_env.sh"

VENDOR="$REPO_ROOT/ios/Classes"
LIB="$ODE_BUILD_DIR/vendored-host/libode.so"
OUT="$ODE_BUILD_DIR/paridad"
WASM="${1:-$ODE_WASM_BUILD/debug}"

[ -f "$LIB" ] || { echo "no hay libode.so de host: corre tool/build_vendored_host.sh" >&2; exit 1; }
[ -f "$WASM/ode.wasm" ] || { echo "no hay $WASM/ode.wasm: corre tool/build_ode_wasm.sh" >&2; exit 1; }

mkdir -p "$OUT"
cc -O2 -o "$OUT/freefall_native" "$REPO_ROOT/tool/wasm/freefall_native.c" \
  -DdIDESINGLE -I"$VENDOR/generated" -I"$VENDOR/include" \
  "$LIB" -lm -Wl,-rpath,"$(dirname "$LIB")"

"$OUT/freefall_native" | sort > "$OUT/nativo.txt"
node "$REPO_ROOT/tool/wasm/freefall.mjs" "$WASM" --kv > "$OUT/wasm_full.txt"
grep -E '^[a-z_][a-z_0-9]* -?[0-9]' "$OUT/wasm_full.txt" | sort > "$OUT/wasm.txt"

echo
printf '%-16s %12s %12s   %s\n' clave nativo wasm veredicto
FALLOS=0
while read -r clave vNat; do
  vWasm="$(awk -v k="$clave" '$1==k{print $2}' "$OUT/wasm.txt")"
  [ -n "$vWasm" ] || { echo "  falta $clave en el lado wasm"; FALLOS=$((FALLOS+1)); continue; }
  # Tolerancias por naturaleza del dato, no una sola para todo.
  case "$clave" in
    dormida)                    tol=0 ;;      # booleano: idéntico o nada
    y_final|hundimiento|pen_reposo) tol=0.005 ;;  # el reposo: 0.5 % de la unidad
    vy)                         tol=0.05 ;;   # ambos tienen que estar quietos
    pen_impacto)                tol=0.05 ;;   # el pico del choque, más ruidoso
    near_llamado|contactos)     tol=8 ;;      # un paso de diferencia en dormirse
    y0)                         tol=0 ;;      # la condición inicial es exacta
    *)                          tol=0.01 ;;
  esac
  veredicto="$(awk -v a="$vNat" -v b="$vWasm" -v t="$tol" \
    'BEGIN{d=a-b; if(d<0)d=-d; print (d<=t) ? "ok" : "DIVERGE"}')"
  printf '%-16s %12s %12s   %s\n' "$clave" "$vNat" "$vWasm" "$veredicto"
  [ "$veredicto" = ok ] || FALLOS=$((FALLOS+1))
done < "$OUT/nativo.txt"

echo
if [ "$FALLOS" -ne 0 ]; then
  echo "ABORTA: $FALLOS invariantes divergen entre nativo y wasm." >&2
  exit 1
fi
echo "PARIDAD: wasm reproduce los invariantes del backend nativo."
