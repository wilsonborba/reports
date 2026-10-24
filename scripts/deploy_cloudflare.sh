#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Pages deployment does not need root. If a user invoked this script with
# sudo, drop back to that user so Flutter's toolchain and build artifacts keep
# the user's environment and ownership.
if [[ "$(id -u)" -eq 0 && -n "${SUDO_USER:-}" && "${REPORTS_DEPLOY_REEXEC:-0}" != "1" ]]; then
  USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
  exec sudo -u "$SUDO_USER" env \
    REPORTS_DEPLOY_REEXEC=1 \
    HOME="$USER_HOME" \
    PATH="/opt/flutter/bin:$USER_HOME/.local/bin:$USER_HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin" \
    "$0" "$@"
fi

PROJECT_NAME="${CLOUDFLARE_PAGES_PROJECT:-asodya-reports}"
DEPLOYER_DIR="${CLOUDFLARE_DEPLOYER_DIR:-$ROOT_DIR/scripts}"
DEPLOYER="$DEPLOYER_DIR/cloudflare_deployer.py"

"$ROOT_DIR/ui/scripts/build_cloudflare.sh"

if [[ ! -f "$DEPLOYER" ]]; then
  echo "Cloudflare deployer not found: $DEPLOYER" >&2
  echo "Set CLOUDFLARE_DEPLOYER_DIR to a neighboring Asodya scripts directory." >&2
  exit 2
fi

STAMP="$(TZ="Asia/Bangkok" date +"%Y-%m-%d %H:%M +07")"
python3 - "$DEPLOYER" "$PROJECT_NAME" "$ROOT_DIR/ui/build/web" "${CLOUDFLARE_PAGES_DOMAIN:-reports.asodya.com}" "$STAMP" <<'PY'
import importlib.util
import sys

deployer_path, project, build_dir, domain, stamp = sys.argv[1:]
spec = importlib.util.spec_from_file_location("asodya_cloudflare_deployer", deployer_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.deploy_pages_project(project, build_dir, custom_domain=domain, branch="main", timestamp_str=stamp)
PY
