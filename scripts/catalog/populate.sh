#!/usr/bin/env bash
# Create or update the five selected Reports projects (catalog rows, not sample data).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 -I "$ROOT_DIR/scripts/catalog/catalog.py" "$@"
