#!/usr/bin/env bash
# End-to-end check of the deployed Reports stack (issues #18 and #31):
#   gateway paths (public, guarded, admin), Domain composition, Redis cache,
#   engine health, export files (PDF, Markdown, CSV ZIP) and the guest browser check.
# It only reads: no write reaches production. It writes a report to build/e2e/report.md.
#
# Usage: scripts/verify_e2e.sh [--skip-exports] [--skip-browser]
# Environment (defaults are the production values):
#   REPORTS_GATEWAY_URL  https://api.asodya.com/apps/reports/v1
#   REPORTS_SITE_URL     https://reports.asodya.com
#   REPORTS_ENGINE_URL   http://127.0.0.1:8109   (engine host only)
#   REDIS_URL, REDIS_NAMESPACE from .env when present
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GW="${REPORTS_GATEWAY_URL:-https://api.asodya.com/apps/reports/v1}"
SITE="${REPORTS_SITE_URL:-https://reports.asodya.com}"
ENGINE="${REPORTS_ENGINE_URL:-http://127.0.0.1:8109}"
UA="reports-e2e/1.0 (+https://reports.asodya.com)"
OUT="$ROOT_DIR/build/e2e"
SKIP_EXPORTS=0
SKIP_BROWSER=0
for arg in "$@"; do
  case "$arg" in
    --skip-exports) SKIP_EXPORTS=1 ;;
    --skip-browser) SKIP_BROWSER=1 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done
if [[ -f "$ROOT_DIR/.env" ]]; then
  REDIS_URL="${REDIS_URL:-$(grep -E '^REDIS_URL=' "$ROOT_DIR/.env" | cut -d= -f2-)}"
  REDIS_NAMESPACE="${REDIS_NAMESPACE:-$(grep -E '^REDIS_NAMESPACE=' "$ROOT_DIR/.env" | cut -d= -f2-)}"
fi
REDIS_NAMESPACE="${REDIS_NAMESPACE:-reports:}"

mkdir -p "$OUT"
REPORT="$OUT/report.md"
PASS=0
FAIL=0
LINES=()

record() { # record <ok|FAIL> <text>
  if [[ "$1" == ok ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi
  LINES+=("- [$1] $2")
  printf '[%s] %s\n' "$1" "$2"
}

# fetch <method> <url> [header ...]: sets STATUS and writes the body to $OUT/body.json
fetch() {
  local method="$1" url="$2"; shift 2
  local args=(-s -o "$OUT/body.json" -w '%{http_code}' -X "$method" -A "$UA" --max-time 60)
  for h in "$@"; do args+=(-H "$h"); done
  STATUS="$(curl "${args[@]}" "$url" || echo 000)"
}

# expect <label> <method> <path> <allowed statuses, comma separated> [header ...]
expect() {
  local label="$1" method="$2" path="$3" allowed="$4"; shift 4
  fetch "$method" "$GW$path" "$@"
  if [[ ",$allowed," == *",$STATUS,"* ]]; then
    record ok "$label: $method $GW$path -> $STATUS"
  else
    record FAIL "$label: $method $GW$path -> $STATUS (expected $allowed)"
  fi
}

# json <python expression over the variable d>: evaluates against the last body
json() {
  python3 -c "import json,sys; d=json.load(open('$OUT/body.json')); print($1)" 2>/dev/null
}

echo "== Engine health ($ENGINE)"
fetch GET "$ENGINE/health"
if [[ "$STATUS" == 200 && "$(json "d.get('status')")" == ok ]]; then
  record ok "engine /health -> $(json "d.get('status')") (postgres=$(json "d.get('postgres')"), couchdb=$(json "d.get('couchdb')"), redis=$(json "d.get('redis')"))"
else
  record FAIL "engine /health -> $STATUS status=$(json "d.get('status')") (on the engine host, or set REPORTS_ENGINE_URL)"
fi
fetch GET "$ENGINE/ready"
[[ "$STATUS" == 200 ]] && record ok "engine /ready -> 200" || record FAIL "engine /ready -> $STATUS"

echo "== Public gateway paths"
expect "catalog" GET "/catalog?lang=en" 200
PROJECTS="$(json "' '.join(p['slug'] for p in d.get('items', []))")"
[[ -n "$PROJECTS" ]] && record ok "catalog projects: $PROJECTS" || record FAIL "catalog has no projects"
LINKED="$(json "' '.join(p['slug'] + '=' + p.get('domain_status', '?') for p in d.get('items', []))")"
if json "all(p.get('domain_status') in ('fresh', 'stale', 'unlinked') for p in d.get('items', []))" | grep -q True; then
  record ok "Domain composition status per project: $LINKED"
else
  record FAIL "Domain composition status per project: $LINKED"
fi
expect "project detail" GET "/projects/cortex?lang=en" 200
json "d.get('domain') is not None and d['domain'].get('name')" | grep -qv -E '^(None|False|)$' \
  && record ok "cortex detail carries the Domain block ($(json "d.get('domain_status')"))" \
  || record FAIL "cortex detail has no Domain block"
expect "project theme" GET "/projects/cortex/theme" 200
expect "stats" GET "/stats?lang=en" 200
expect "openapi" GET "/openapi.json" 200

# The first public report with a public card and a gated card, over all projects.
REPORT_PAIR=""; PUBLIC_CARD=""; GATED_CARD=""; PUBLIC_REPORTS=(); EXPORTABLE=()
for p in $PROJECTS; do
  expect "guest report list of $p" GET "/projects/$p/reports?lang=en&page_size=100" 200
  for r in $(json "' '.join(x['slug'] for x in d.get('items', []) if x.get('can_view', True))"); do
    PUBLIC_REPORTS+=("$p/$r")
    fetch GET "$GW/projects/$p/showcase/$r?lang=en"
    [[ "$STATUS" == 200 ]] || { record FAIL "showcase $p/$r -> $STATUS"; continue; }
    leak="$(json "[c['dataset_id'] for c in d.get('cards', []) if not c.get('can_view') and any(c.get(k) is not None for k in ('rows', 'descriptor', 'total_rows'))]")"
    [[ "$leak" == "[]" ]] && record ok "showcase $p/$r: gated cards carry no data" || record FAIL "showcase $p/$r: gated cards with data $leak"
    json "any(c.get('can_view') for c in d.get('cards', []))" | grep -q True && EXPORTABLE+=("$p/$r")
    if [[ -z "$REPORT_PAIR" ]]; then
      pub="$(json "next((c['dataset_id'] for c in d.get('cards', []) if c.get('can_view')), '')")"
      gat="$(json "next((c['dataset_id'] for c in d.get('cards', []) if not c.get('can_view')), '')")"
      if [[ -n "$pub" && -n "$gat" ]]; then REPORT_PAIR="$p/$r"; PUBLIC_CARD="$pub"; GATED_CARD="$gat"; fi
    fi
  done
done
[[ ${#PUBLIC_REPORTS[@]} -gt 0 ]] && record ok "public reports: ${PUBLIC_REPORTS[*]}" || record FAIL "no public report"

echo "== Guarded paths without a session"
if [[ -n "$REPORT_PAIR" ]]; then
  P="${REPORT_PAIR%%/*}"; R="${REPORT_PAIR#*/}"
  expect "public card rows" GET "/projects/$P/showcase/$R/cards/$PUBLIC_CARD?lang=en&limit=3" 200
  json "isinstance(d.get('rows'), list)" | grep -q True && record ok "public card $PUBLIC_CARD has rows" || record FAIL "public card $PUBLIC_CARD has no rows"
  expect "gated card on the guest route" GET "/projects/$P/showcase/$R/cards/$GATED_CARD" 401,404
  json "'rows' not in d" | grep -q True && record ok "gated card answer has no rows" || record FAIL "gated card answer has rows"
  expect "faked identity headers on the guest route" GET "/projects/$P/showcase/$R/cards/$GATED_CARD" 401,404 \
    "x-uuid: 00000000-0000-0000-0000-000000000001" "x-access-level: 1" "x-project-admin: true"
  expect "session report route" GET "/projects/$P/reports/$R" 401,403
  expect "session card route" GET "/projects/$P/reports/$R/cards/$GATED_CARD" 401,403
  expect "session dataset route" GET "/projects/$P/reports/$R/datasets/$PUBLIC_CARD" 401,403
else
  record FAIL "no public report with both a public and a gated card"
fi
expect "me" GET "/me" 401,403
expect "my reports" GET "/me/projects/cortex/reports" 401,403
expect "admin write without a key" PUT "/projects/cortex/admin/project" 401,403 "Content-Type: application/json"
expect "admin ingest without a key" POST "/projects/cortex/admin/ingest/telemetry_event" 401,403 "Content-Type: application/json"
expect "fixture delete without a key" DELETE "/admin/fixtures/sample-v1-cortex" 401,403,404

echo "== Redis cache"
if command -v redis-cli >/dev/null && [[ -n "${REDIS_URL:-}" ]]; then
  before="$(redis-cli --no-auth-warning -u "$REDIS_URL" --scan --pattern "${REDIS_NAMESPACE}*" 2>/dev/null | wc -l)"
  [[ -n "$REPORT_PAIR" ]] && fetch GET "$GW/projects/${REPORT_PAIR%%/*}/showcase/${REPORT_PAIR#*/}/cards/$PUBLIC_CARD?lang=en&limit=3"
  after="$(redis-cli --no-auth-warning -u "$REDIS_URL" --scan --pattern "${REDIS_NAMESPACE}*" 2>/dev/null | wc -l)"
  if [[ "$after" -gt 0 ]]; then record ok "Redis keys under $REDIS_NAMESPACE: $before before, $after after a public read"; else record FAIL "no Redis key under $REDIS_NAMESPACE"; fi
  ttl_missing="$(redis-cli --no-auth-warning -u "$REDIS_URL" --scan --pattern "${REDIS_NAMESPACE}*" 2>/dev/null | head -50 | while read -r k; do t="$(redis-cli --no-auth-warning -u "$REDIS_URL" ttl "$k")"; [[ "$t" == -1 ]] && echo "$k"; done | wc -l)"
  [[ "$ttl_missing" == 0 ]] && record ok "every sampled Redis key has a TTL" || record FAIL "$ttl_missing sampled Redis keys have no TTL"
else
  record FAIL "Redis check skipped: redis-cli or REDIS_URL missing"
fi

if [[ "$SKIP_EXPORTS" == 0 ]]; then
  echo "== Export files (browser code, guest showcase)"
  rm -rf "$ROOT_DIR/ui/build/real_exports"
  # Reports with at least one card a guest can read (a fully gated report exports no card).
  pairs="$(printf '%s\n' "${EXPORTABLE[@]:0:2}" | paste -sd, -)"
  if (cd "$ROOT_DIR/ui" && REPORT_API="$GW" REPORTS="$pairs" flutter test test/real_api_export_test.dart >"$OUT/exports.log" 2>&1); then
    if python3 "$ROOT_DIR/scripts/e2e/check_exports.py" "$ROOT_DIR/ui/build/real_exports" >"$OUT/exports_check.txt" 2>&1; then
      record ok "exports of $pairs: $(grep -c '^\[ok\]' "$OUT/exports_check.txt") files valid (build/e2e/exports_check.txt)"
    else
      record FAIL "export structure check failed (build/e2e/exports_check.txt)"
    fi
  else
    record FAIL "export run failed (build/e2e/exports.log)"
  fi
fi

if [[ "$SKIP_BROWSER" == 0 ]]; then
  echo "== Guest browser check ($SITE)"
  if python3 "$ROOT_DIR/scripts/e2e/browser_check.py" --site "$SITE" --api "$GW" --report "$OUT/browser.json" >"$OUT/browser.txt" 2>&1; then
    record ok "browser: $(tail -1 "$OUT/browser.txt")"
  else
    record FAIL "browser: $(tail -1 "$OUT/browser.txt") (build/e2e/browser.txt)"
  fi
fi

{
  echo "# Reports end-to-end check"
  echo
  echo "- Date: $(TZ=Asia/Bangkok date +'%Y-%m-%d %H:%M ICT')"
  echo "- Commit: $(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null)"
  echo "- Gateway: $GW"
  echo "- Site: $SITE"
  echo "- Engine: $ENGINE"
  echo "- Command: scripts/verify_e2e.sh $*"
  echo
  echo "## Results ($PASS passed, $FAIL failed)"
  echo
  printf '%s\n' "${LINES[@]}"
  echo
  echo "## Remaining gate"
  echo
  echo "- One real owner login through auth_apps: sign in, open a gated card, log out."
} >"$REPORT"
echo "Report: $REPORT"
echo "E2E: $PASS passed, $FAIL failed."
[[ "$FAIL" == 0 ]]
