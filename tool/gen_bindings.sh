#!/usr/bin/env bash
# Regenera core/lib/src/ode/ode_bindings_ffi.dart con ffigen.
#
# Dos trampas que costaron el spike y que este script cocina:
#  1. ffigen se corre con un dart ARM64 NATIVO (~/dev/dart-arm64, el SDK suelto
#     que Dart sí publica para linux-arm64). El dart de flutter-3471 es x86_64
#     bajo qemu y no ve el libclang aarch64 de Fedora. Por eso existe
#     ffigen_runner/: un paquete aparte solo para ejecutarlo, y por eso basta
#     un Dart pelado -- no hace falta un Flutter entero, que además traería un
#     segundo engine al taller y envenenaría los shaders del fork compartido
#     (ver el build_apk.sh de Nairda).
#  2. libclang no encuentra sus propios builtin (stddef.h) por su cuenta: hay
#     que darle su resource-dir. Se DERIVA de clang, no se clava una ruta
#     (esta caja tiene clang 19 y 21 a la vez).
#
# Uso: tool/gen_bindings.sh
set -euo pipefail
source "$(dirname "$0")/ode_env.sh"

"$(dirname "$0")/fetch_ode.sh"

DART="${DART:-$HOME/dev/dart-arm64/bin/dart}"
[ -x "$DART" ] || { echo "no encuentro el dart ARM64 nativo en $DART" >&2; exit 1; }

CLANG_INC="$(clang -print-resource-dir)/include"
[ -d "$CLANG_INC" ] || { echo "no encuentro los builtin de clang en $CLANG_INC" >&2; exit 1; }

GEN="$REPO_ROOT/ffigen.gen.yaml"   # gitignorado: la plantilla es la fuente
sed -e "s|@OUTPUT@|$REPO_ROOT/core/lib/src/ode/ode_bindings_ffi.dart|g" \
    -e "s|@ODE_SRC@|$ODE_SRC|g" \
    -e "s|@BINDGEN_INCLUDE@|$REPO_ROOT/tool/bindgen-include|g" \
    -e "s|@CLANG_INCLUDE@|$CLANG_INC|g" \
    "$REPO_ROOT/ffigen.template.yaml" > "$GEN"

cd "$REPO_ROOT/ffigen_runner"
"$DART" pub get
"$DART" run ffigen --config "$GEN"

echo
echo "== cotejo obligatorio =="
B="$REPO_ROOT/core/lib/src/ode/ode_bindings_ffi.dart"
grep -q 'typedef dReal = ffi.Float;' "$B" \
  && echo "OK  dReal = ffi.Float (single precision)" \
  || { echo "FALLA: dReal no es ffi.Float"; exit 1; }
for f in dCreateCylinder dMassSetCylinderTotal dMassRotate dCheckConfiguration dJointGetHingeAnchor dCreateRay; do
  grep -q "$f" "$B" && echo "OK  $f presente" || { echo "FALLA: falta $f"; exit 1; }
done
grep -q 'dCreateCapsule' "$B" \
  && { echo "FALLA: dCreateCapsule sigue ahí — las cápsulas están prohibidas"; exit 1; } \
  || echo "OK  dCreateCapsule ausente"

# Y el gemelo WEB, desde este mismo fichero.
#
# Va encadenado a propósito: los bindings de web copian las firmas de los de
# ffigen, así que regenerar unos sin los otros los deja hablando de funciones
# distintas — y eso no da un error de compilación en ninguna plataforma, da una
# función que en el navegador hace otra cosa.
echo
echo "== el gemelo web =="
"$DART" "$REPO_ROOT/tool/gen_bindings_web.dart"
echo "OJO: si cambió el layout de los structs hay que recompilar el .wasm"
echo "     (tool/build_ode_wasm.sh) y revendorizarlo (tool/vendor_wasm.sh)."
