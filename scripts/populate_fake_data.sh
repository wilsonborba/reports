#!/usr/bin/env bash
# Load sample (synthetic) data for the five launch projects. Run scripts/catalog/populate.sh first.
#   scripts/populate_fake_data.sh [--project <slug>] [--dry-run]
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/scripts/population"
exec python3 -I populate.py "$@"
