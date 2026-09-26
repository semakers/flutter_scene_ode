#!/usr/bin/env bash
# Compila el árbol vendorizado EN EL MAC, contra el SDK de macOS de las Command
# Line Tools. Es la verificación previa de más valor que existe para Apple.
#
# Desde que el Mac tiene Xcode (26.4, con el SDK de iOS 26.4), esto compila las
# TRES variantes de verdad: macOS, iPhone y simulador de iPhone. O sea que el
# `isnanf` que Darwin no declara, la rama OSAtomic de ou, la ausencia de
# malloc.h, el include de CoreServices de timer.cpp y la visibilidad de los
# símbolos se comprueban contra el SDK que de verdad va a usar el runner.
#
# Cada vuelta a Xcode Cloud son ~16 minutos. Esto es un minuto.
#
# Lo que NO cubre, y por eso sigue haciendo falta ci_shared/verificar_ode.sh en
# el repo de la app: cómo empaqueta CocoaPods el framework, la firma, y el
# enlazado con el Runner.
#
# Uso: tool/verify_apple.sh        (necesita `ssh mac`)
set -euo pipefail
source "$(dirname "$0")/ode_env.sh"

HOST="${MAC_HOST:-mac}"
REMOTE="${MAC_WORK:-/tmp/flutter-scene-ode-verify}"

echo "=== copiando ios/Classes a $HOST:$REMOTE ==="
ssh "$HOST" "rm -rf '$REMOTE' && mkdir -p '$REMOTE'"
tar -C "$REPO_ROOT/ios" -czf - Classes | ssh "$HOST" "tar -C '$REMOTE' -xzf -"

ssh "$HOST" "bash -s" <<'EOS'
set -euo pipefail
cd /tmp/flutter-scene-ode-verify

BASE="-Os -DNDEBUG -fPIC -Wno-deprecated-declarations
      -include Classes/generated/apple_compat.h
      -DODE_DLL -DODE_EXPORTS -DdIDESINGLE -DdNODEBUG
      -DdOU_ENABLED -DdATOMICS_ENABLED -DdBUILTIN_THREADING_IMPL_ENABLED
      -D_OU_NAMESPACE=odeou -D_OU_FEATURE_SET=_OU_FEATURE_SET_ATOMICS
      -IClasses/generated -IClasses/include
      -IClasses/ode/src -IClasses/ode/src/joints -IClasses/ou/include"

# Las TRES que compila el runner. En macOS ou/platform.h autodetecta MAC (y por
# eso hace falta MAC_OS_X_VERSION); en las dos de iPhone autodetecta IOS y lo
# pone él solo. La del simulador no es un capricho: es una slice distinta, y es
# donde suelen salir los "building for iOS Simulator, but linking object built
# for iOS".
for VARIANTE in "macOS:macosx:-target arm64-apple-macos11.0 -DMAC_OS_X_VERSION=1050" \
                "iPhone:iphoneos:-target arm64-apple-ios13.0" \
                "simulador:iphonesimulator:-target arm64-apple-ios13.0-simulator"; do
  NOMBRE="$(echo "$VARIANTE" | cut -d: -f1)"
  SDKNAME="$(echo "$VARIANTE" | cut -d: -f2)"
  EXTRA="$(echo "$VARIANTE" | cut -d: -f3-)"
  SDK="$(xcrun --sdk "$SDKNAME" --show-sdk-path)"
  COMMON="-isysroot $SDK $BASE"
  echo ""
  echo "=== variante: $NOMBRE  ($SDKNAME) ==="
  rm -rf obj && mkdir obj
  ERR=0
  for f in $(find Classes/ode/src Classes/ou/src -name '*.cpp' -o -name '*.c' | sort); do
    o="obj/$(echo "$f" | tr / _).o"
    case "$f" in
      *.c)   clang   $COMMON $EXTRA -c "$f" -o "$o" || ERR=1 ;;
      *.cpp) clang++ -std=gnu++17 $COMMON $EXTRA -c "$f" -o "$o" || ERR=1 ;;
    esac
  done
  [ "$ERR" -eq 0 ] || { echo "ABORTA: hubo errores de compilación"; exit 1; }

  N="$(ls obj | wc -l | tr -d ' ')"
  [ "$N" -eq 75 ] || { echo "ABORTA: $N objetos, se esperaban 75"; exit 1; }

  # shellcheck disable=SC2086
  clang++ -isysroot "$SDK" $EXTRA -dynamiclib -o libode.dylib obj/*.o -lc++

  # nm a un fichero y grep SOBRE EL FICHERO: `nm | grep -q` da error justo
  # cuando encuentra el símbolo (grep cierra la tubería y nm muere de SIGPIPE).
  nm -gU libode.dylib > syms.txt
  for s in _dInitODE2 _dWorldQuickStep _dCreateCylinder _dCheckConfiguration; do
    grep -qE "[[:space:]]T[[:space:]]$s\$" syms.txt || { echo "ABORTA: $s no exportado"; exit 1; }
  done

  # La misma guardia de ABI que ode_library.dart hace en caliente, pero estática:
  # la cadena de configuración viaja compilada dentro del binario.
  strings -a libode.dylib > str.txt
  grep -q 'ODE_single_precision' str.txt || { echo "ABORTA: no está compilado en precisión simple"; exit 1; }

  ARCH="$(lipo -archs libode.dylib 2>/dev/null || echo '?')"
  echo "OK $NOMBRE: 75 objetos ($ARCH), $(grep -c '[[:space:]]T[[:space:]]_' syms.txt) símbolos exportados, precisión simple"
done

echo ""
echo "=== las tres variantes compilan y exportan ==="
EOS

# ---------------------------------------------------------------------------
# Y la prueba decisiva: que lo construya COCOAPODS, no nosotros.
#
# Las tres pasadas de arriba prueban que el C++ compila. Esto prueba lo otro
# —que es donde ha estado cada fallo de esta migración—: que `source_files`
# encuentra las 75 unidades, que los header maps de Xcode no secuestran
# `#include <assert.h>`, que el pod sale como framework DINÁMICO y que los
# símbolos quedan exportados. Que es exactamente lo que verifica
# ci_shared/verificar_ode.sh en la nube, pero aquí y en cinco minutos.
#
# La dependencia `Flutter` se quita para el lint: no se puede resolver fuera de
# una app de Flutter, y no es lo que se está comprobando.
#
# Y en LAS DOS plataformas, que no es lo mismo: el build #233 murio solo en
# macOS, porque alli el prefix header del pod incluye <Cocoa/Cocoa.h> y eso
# arrastra modulos del sistema que en iOS no se tocan.
for PLAT in ios macos; do
case "$PLAT" in
  ios)   PODPLAT=ios; PODSDK=iphoneos;  PODSCHEME_ARCH="" ;;
  macos) PODPLAT=osx; PODSDK=macosx;    PODSCHEME_ARCH="" ;;
esac

echo ""
echo "=== construyendo el pod con CocoaPods ($PODSDK) ==="
tar -C "$REPO_ROOT/$PLAT" -czf - flutter_scene_ode.podspec Classes \
  | ssh "$HOST" "rm -rf '$REMOTE-pod' && mkdir -p '$REMOTE-pod' && tar -C '$REMOTE-pod' -xzf -"

# Heredoc SIN comillas a proposito (hace falta expandir $PODPLAT y $PODSDK
# aqui), asi que dentro TODO lo demas va escapado: \$var, \$(...) — y NADA de
# backticks, ni siquiera en los comentarios. Un `x` en un comentario de aqui
# dentro EJECUTA x en esta maquina al expandir el heredoc: dos comentarios
# estaban corriendo `-type f` y `strings | grep -q` en la caja Linux, y su
# ruido salia en medio del log del Mac.
ssh "$HOST" "bash -s" <<EOS2
set -euo pipefail
export PATH="/usr/local/bin:\$PATH"
export LANG=en_US.UTF-8
cd "$REMOTE-pod"
sed -i '' '/s.dependency .Flutter/d' flutter_scene_ode.podspec
rm -rf /tmp/flutter-scene-ode-lint /tmp/flutter-scene-ode-dd
pod lib lint flutter_scene_ode.podspec --platforms=$PODPLAT --allow-warnings --no-clean \
    --skip-import-validation --validation-dir=/tmp/flutter-scene-ode-lint > /tmp/lint.log 2>&1 || {
  echo "ABORTA: pod lib lint fallo"; grep -E "ERROR|error:" /tmp/lint.log | head -20; exit 1; }
echo "pod lib lint: OK"

cd /tmp/flutter-scene-ode-lint
xcodebuild -workspace App.xcworkspace -scheme flutter_scene_ode -sdk $PODSDK \
  -configuration Release -derivedDataPath /tmp/flutter-scene-ode-dd \
  CODE_SIGNING_ALLOWED=NO build > /tmp/xb.log 2>&1 || {
  echo "ABORTA: xcodebuild fallo"; grep "error:" /tmp/xb.log | head -20; exit 1; }

# En macOS el framework es "versionado": el binario vive en Versions/A/ y el de
# la raiz es un SYMLINK, asi que '-type f' lo descartaba. En iOS es plano.
FW=\$(find /tmp/flutter-scene-ode-dd/Build/Products -path '*flutter_scene_ode.framework/Versions/A/flutter_scene_ode' -type f | head -1)
[ -n "\$FW" ] || FW=\$(find /tmp/flutter-scene-ode-dd/Build/Products -path '*flutter_scene_ode.framework/flutter_scene_ode' -type f | head -1)
[ -n "\$FW" ] || { echo "ABORTA: no salio flutter_scene_ode.framework"; exit 1; }

# DYLIB, no staticlib: si sale estatico, el enlazador del Runner descartaria
# los objetos porque nada referencia a ODE desde Objective-C.
otool -hv "\$FW" | grep -q DYLIB || { echo "ABORTA: el framework NO es dinamico"; exit 1; }

nm -gU "\$FW" > /tmp/fwsyms.txt
for s in _dInitODE2 _dWorldQuickStep _dCreateCylinder _dCheckConfiguration; do
  grep -qE "[[:space:]][A-Za-z][[:space:]]\$s\\$" /tmp/fwsyms.txt \
    || { echo "ABORTA: \$s no exportado en el framework"; exit 1; }
done
# strings a un FICHERO y luego grep, nunca 'strings | grep -q': con pipefail,
# grep -q cierra la tuberia, strings muere de SIGPIPE y el pipeline da error
# JUSTO CUANDO ENCUENTRA la cadena. Es carrera pura: en iOS pasaba y en macOS
# no. Tercera vez que este proyecto tropieza con lo mismo.
strings -a "\$FW" > /tmp/fwstr.txt
grep -q ODE_single_precision /tmp/fwstr.txt \
  || { echo "ABORTA: el framework no es de precision simple"; exit 1; }

echo "OK pod $PODSDK: framework dinamico arm64, \$(wc -l < /tmp/fwsyms.txt | tr -d ' ') simbolos exportados, precision simple"
EOS2
done

echo ""
echo "=== todo verde: el C++ compila y CocoaPods lo empaqueta bien en las dos ==="
