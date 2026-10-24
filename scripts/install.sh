#!/usr/bin/env bash
# Build and (re)start the Reports engine as a systemd user service.
#
# It installs the service only. It never creates databases and never runs
# migrations: run scripts/migrate.sh --yes before the first start and after
# every new migration file. The engine refuses to start on an outdated schema.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT_NAME="reports-engine.service"

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run this installer as the service user, not as root (it installs a user unit)." >&2
  exit 1
fi
if [[ ! -f "$ROOT_DIR/.env" ]]; then
  echo "Create $ROOT_DIR/.env first (see .env.example). The installer copies no credentials." >&2
  exit 1
fi
command -v cargo >/dev/null || { echo "cargo is required." >&2; exit 1; }
command -v systemctl >/dev/null || { echo "systemctl is required." >&2; exit 1; }

echo "Building the Reports engine..."
cargo build --manifest-path "$ROOT_DIR/engine/Cargo.toml" --release

mkdir -p "$UNIT_DIR"
sed "s#@ROOT_DIR@#$ROOT_DIR#g" "$ROOT_DIR/scripts/reports-engine.user.service" > "$UNIT_DIR/$UNIT_NAME"
systemctl --user daemon-reload
systemctl --user enable "$UNIT_NAME"
systemctl --user restart "$UNIT_NAME"
sleep 2
systemctl --user --no-pager --full status "$UNIT_NAME" || {
  echo "The engine did not start. Check: journalctl --user -u $UNIT_NAME -n 50" >&2
  echo "An outdated schema needs: scripts/migrate.sh --yes" >&2
  exit 1
}
echo "Reports engine runs on 127.0.0.1:8109. No migration was run."
