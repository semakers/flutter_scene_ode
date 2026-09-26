#!/usr/bin/env bash
# Mete el módulo recién compilado en el paquete: los assets, los bindings
# generados y los bytes que usa el banco de navegador.
#
# Se corre después de tool/build_ode_wasm.sh. Son tres artefactos derivados del
# MISMO .wasm, y desincronizarlos es el fallo silencioso que este paquete
# persigue: por eso los escribe un solo script y hay tests que los cotejan.
set -euo pipefail
source "$(dirname "$0")/ode_env.sh"

SRC="${1:-$ODE_WASM_BUILD/release}"
[ -f "$SRC/ode.wasm" ] || { echo "no hay $SRC/ode.wasm: corre tool/build_ode_wasm.sh" >&2; exit 1; }

# 1. Los assets, commiteados igual que el libode.so de Android.
mkdir -p "$REPO_ROOT/assets"
install -m 644 "$SRC/ode.js" "$SRC/ode.wasm" "$REPO_ROOT/assets/"
echo "assets/ode.wasm  $(stat -c%s "$REPO_ROOT/assets/ode.wasm") bytes"

# 2. Los bindings web, con los desplazamientos de ESTE módulo.
"${DART:-$HOME/dev/dart-arm64/bin/dart}" "$REPO_ROOT/tool/gen_bindings_web.dart"

# 3. Los bytes para el banco de navegador.
#
# POR QUÉ EN BASE64 Y NO POR rootBundle: `flutter test --platform chrome` NO
# sirve el bundle de assets. No es que falle: no hay ni una línea de assets en
# flutter_tools/lib/src/test/flutter_web_platform.dart, así que `rootBundle`
# se queda esperando para siempre y el test muere por timeout a los 30 s, con
# una traza que no menciona los assets por ningún lado.
#
# Así que el banco le INYECTA los bytes al cargador (debugOdeModuleBytes), que
# para eso existe ese hueco. Y como es un fichero derivado que se puede quedar
# rancio, test/ode_wasm_bytes_test.dart (en el plugin) lo coteja contra assets/ desde la VM.
OUT="$REPO_ROOT/core/test/ode_wasm_bytes.g.dart"
{
  cat <<'HEAD'
// GENERADO por tool/vendor_wasm.sh. No editar a mano.
//
// El módulo de assets/, en base64, para el banco de navegador: `flutter test
// --platform chrome` no sirve el bundle de assets (flutter_web_platform.dart
// no lo menciona siquiera), así que rootBundle se cuelga y el test muere por
// timeout sin decir por qué. Aquí los bytes viajan dentro del propio test.
//
// Que no se quede rancio lo vigila test/ode_wasm_bytes_test.dart, que lo
// compara con assets/ desde la VM.
library;

/// `assets/ode.wasm` en base64.
const String odeWasmBase64 =
HEAD
  base64 -w 100 "$REPO_ROOT/assets/ode.wasm" | sed "s/^/    '/; s/\$/'/"
  echo "    ;"
  echo
  echo "/// \`assets/ode.js\` en base64 (el glue de emscripten)."
  echo "const String odeGlueBase64 ="
  base64 -w 100 "$REPO_ROOT/assets/ode.js" | sed "s/^/    '/; s/\$/'/"
  echo "    ;"
} > "$OUT"
echo "$OUT  $(wc -l < "$OUT") lineas"
