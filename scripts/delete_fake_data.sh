#!/usr/bin/env bash
# Remove only the sample data that populate_fake_data.sh wrote (fixture manifests).
#   scripts/delete_fake_data.sh [--project <slug>] [--dry-run]
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/scripts/population"
exec python3 -I delete.py "$@"
