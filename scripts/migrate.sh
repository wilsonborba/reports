#!/usr/bin/env bash
# Apply the Reports storage structure. This is the only place that changes it:
# the engine and scripts/install.sh never run migrations.
#
#   scripts/migrate.sh --dry-run   show the target and the steps, change nothing
#   scripts/migrate.sh --yes       apply them
#
# PostgreSQL: every file in engine/migrations/*.sql, in name order, each in one
# transaction. The files are idempotent and contain structure only (no data).
# CouchDB: the database and its Mango indexes.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPORTS_ENV_FILE:-$ROOT_DIR/.env}"
MODE="${1:-}"

if [[ "$MODE" != "--yes" && "$MODE" != "--dry-run" ]]; then
  echo "Usage: $0 --dry-run | --yes" >&2
  exit 2
fi
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE (copy .env.example and set the credentials)." >&2
  exit 1
fi
command -v psql >/dev/null || { echo "psql is required." >&2; exit 1; }
command -v curl >/dev/null || { echo "curl is required." >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${DATABASE_URL:?DATABASE_URL is required}"
: "${COUCHDB_URL:?COUCHDB_URL is required}"
COUCHDB_DATABASE="${COUCHDB_DATABASE:-reports_documents}"
DATABASE_URL="${DATABASE_URL//\\\//\/}"

# Target without the password.
PG_TARGET="$(printf '%s' "$DATABASE_URL" | sed -E 's#://([^:/@]+):[^@]*@#://\1:***@#')"
mapfile -t MIGRATIONS < <(find "$ROOT_DIR/engine/migrations" -maxdepth 1 -name '*.sql' | sort)

echo "PostgreSQL target: $PG_TARGET"
echo "CouchDB target:    $COUCHDB_URL/$COUCHDB_DATABASE"
for m in "${MIGRATIONS[@]}"; do
  echo "  migration: $(basename "$m")"
done

if [[ "$MODE" == "--dry-run" ]]; then
  echo "Dry run: nothing changed."
  exit 0
fi

for m in "${MIGRATIONS[@]}"; do
  echo "Applying $(basename "$m") ..."
  psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1 --single-transaction -f "$m"
done

COUCH_AUTH=()
if [[ -n "${COUCHDB_USER:-}" && -n "${COUCHDB_PASSWORD:-}" ]]; then
  COUCH_AUTH=(-u "$COUCHDB_USER:$COUCHDB_PASSWORD")
fi
couch() { curl -sS -o /dev/null -w '%{http_code}' "${COUCH_AUTH[@]}" "$@"; }

code="$(couch -X PUT "$COUCHDB_URL/$COUCHDB_DATABASE")"
case "$code" in
  201|202) echo "CouchDB database $COUCHDB_DATABASE created." ;;
  412) echo "CouchDB database $COUCHDB_DATABASE already exists." ;;
  *) echo "CouchDB database creation failed (HTTP $code)." >&2; exit 1 ;;
esac

index() {
  local name="$1" fields="$2"
  local code
  code="$(couch -X POST -H 'Content-Type: application/json' "$COUCHDB_URL/$COUCHDB_DATABASE/_index" \
    -d "{\"index\":{\"fields\":$fields},\"name\":\"$name\",\"ddoc\":\"reports\",\"type\":\"json\"}")"
  if [[ "$code" != "200" ]]; then
    echo "CouchDB index $name failed (HTTP $code)." >&2
    exit 1
  fi
  echo "CouchDB index $name ready."
}
index records-by-schema '["type","project","schema_name"]'
index records-by-time '["type","project","schema_name","event_time"]'
index records-by-fixture '["type","fixture"]'

echo "Migration finished. Start or restart the engine now."
