#!/usr/bin/env bash
# build_web.sh — construye el bundle web de gamma-app contra un backend GAMMA.
#
# Uso:
#   ./tool/build_web.sh                       # backend local (http://localhost:8420)
#   ./tool/build_web.sh http://gamma-pi:8420  # backend de la Raspberry Pi
#
# Salida: build/web — servirlo con cualquier servidor estático, p.ej.:
#   cd build/web && python3 -m http.server 8080
#
# CORS: el backend debe permitir el ORIGEN desde el que se abre la web en
# GAMMA_WEB_ORIGINS (p.ej. http://localhost:8080). Si no, el navegador
# bloquea las llamadas a la API.
set -euo pipefail

BACKEND="${1:-http://localhost:8420}"
cd "$(dirname "$0")/.."

flutter build web --release --dart-define="GAMMA_PI=${BACKEND}"

echo "Listo: build/web — backend: ${BACKEND}"
echo "Servir: cd build/web && python3 -m http.server 8080"
