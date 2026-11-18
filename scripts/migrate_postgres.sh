#!/usr/bin/env bash
# Explicit PostgreSQL migration runner. Never loads an environment file.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${DATABASE_URL:?Set DATABASE_URL to the explicit migration target}"
psql_target() { psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1 "$@"; }
for migration in "$ROOT_DIR"/engine/migrations/*.sql; do
  if [[ "$(basename "$migration")" == "006_versioned_calculations.sql" ]]; then
    # Historical 006 retired spec without conversion. Preserve pre-006 rows by
    # applying its normalized replacement first. Historical SQL stays unchanged.
    has_spec="$(psql_target -Atc "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema=current_schema() AND table_name='datasets' AND column_name='spec')")"
    if [[ "$has_spec" == t ]] && [[ "$(psql_target -Atc 'SELECT EXISTS (SELECT 1 FROM datasets)')" == t ]]; then
      echo "Preserving pre-006 inline definitions with migration 007 ..."
      psql_target --single-transaction -f "$ROOT_DIR/engine/migrations/007_normalized_storage.sql"
    fi
  fi
  echo "Applying $(basename "$migration") ..."
  psql_target --single-transaction -f "$migration"
done
