#!/usr/bin/env bash
set -euo pipefail

UI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_BASE_URL="${API_BASE_URL:-https://api.asodya.com/apps/reports/v1}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M%S)}"

FLUTTER_BIN="${FLUTTER_BIN:-$(command -v flutter || true)}"
if [[ -z "$FLUTTER_BIN" && -x /opt/flutter/bin/flutter ]]; then
  FLUTTER_BIN=/opt/flutter/bin/flutter
fi
if [[ -z "$FLUTTER_BIN" ]]; then
  echo "Flutter was not found. Set FLUTTER_BIN or install Flutter at /opt/flutter." >&2
  exit 1
fi

cd "$UI_DIR"
"$FLUTTER_BIN" build web --release --base-href / --no-web-resources-cdn \
  --build-name="${BUILD_NAME:-1.0.0}" --build-number="$BUILD_NUMBER" \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=APP_VERSION="${BUILD_NAME:-1.0.0}" \
  --dart-define=BUILD_TIMESTAMP="$(TZ=Asia/Bangkok date +'%Y-%m-%d %H:%M ICT')"

echo "Cloudflare Pages artifact: $UI_DIR/build/web"
