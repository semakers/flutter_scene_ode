#!/usr/bin/env bash
# Descarga y extrae las fuentes de ODE, verificando el SHA256.
# Sin esto, el .so que enviamos es un binario del que nadie sabe de qué fuente
# salió — que es un problema el día que haya que recompilarlo.
#
# Uso: tool/fetch_ode.sh
set -euo pipefail
source "$(dirname "$0")/ode_env.sh"

mkdir -p "$ODE_WORK/src"
TARBALL="$ODE_WORK/ode-$ODE_VERSION.tar.gz"

if [ -f "$ODE_SRC/include/ode/ode.h" ]; then
  echo "fuentes ya extraídas en $ODE_SRC"
  exit 0
fi

if [ ! -f "$TARBALL" ]; then
  echo "descargando $ODE_URL"
  curl -fL --retry 3 -o "$TARBALL.part" "$ODE_URL"
  mv "$TARBALL.part" "$TARBALL"
fi

echo "verificando sha256..."
ACTUAL="$(sha256sum "$TARBALL" | cut -d' ' -f1)"
if [ "$ACTUAL" != "$ODE_SHA256" ]; then
  echo "ABORTA: sha256 no cuadra" >&2
  echo "  esperado: $ODE_SHA256" >&2
  echo "  obtenido: $ACTUAL" >&2
  exit 1
fi
echo "sha256 OK"

tar -xzf "$TARBALL" -C "$ODE_WORK/src"
echo "fuentes en $ODE_SRC"
