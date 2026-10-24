#!/usr/bin/env bash
# Runs the Reports UI on the LAN dev server (port 8110) against the LAN gateway and
# auth app (DEVELOPMENT_MODE). The gateway allows the origins of port 8110 for the
# session exchange. Open http://<this host>:8110/v1/home in the browser.
# Usage: ui/scripts/dev.sh [extra flutter run arguments]
set -euo pipefail

UI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-8110}"

FLUTTER_BIN="${FLUTTER_BIN:-$(command -v flutter || true)}"
if [[ -z "$FLUTTER_BIN" && -x /opt/flutter/bin/flutter ]]; then
  FLUTTER_BIN=/opt/flutter/bin/flutter
fi
if [[ -z "$FLUTTER_BIN" ]]; then
  echo "Flutter was not found. Set FLUTTER_BIN or install Flutter at /opt/flutter." >&2
  exit 1
fi

cd "$UI_DIR"
exec "$FLUTTER_BIN" run -d web-server --web-hostname 0.0.0.0 --web-port "$PORT" \
  --dart-define=DEVELOPMENT_MODE=true \
  --dart-define=BUILD_TIMESTAMP="dev $(TZ=Asia/Bangkok date +'%Y-%m-%d %H:%M ICT')" \
  "$@"
