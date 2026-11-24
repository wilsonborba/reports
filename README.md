# Reports

Reports is the Asodya reporting product: project reports, statistics and dashboards for
selected Asodya projects. The Flutter web app (`ui/`) builds PDF, Markdown and CSV ZIP
exports in the browser.

## Architecture

```
Browser (reports.asodya.com, Flutter Web on Cloudflare Pages)
   |  https://api.asodya.com/apps/reports/v1/...
api_for_apps (gateway: session cookies, public/session/admin route rules)
   |  http://localhost:8109/...   (the gateway removes /apps/reports/v1)
Reports engine (Rust, engine/)
   |-- PostgreSQL asodya_reports  projects, reports, datasets, versioned schemas, roles
   |-- CouchDB reports_documents  received records (idempotent by key)
   `-- Redis                      temporary result cache (a failure is a cache miss)
```

The engine listens on `127.0.0.1:8109`, so only local processes (the gateway and local
operator tools) reach it.

## Repository layout

| Path | Content |
| --- | --- |
| `engine/src/core` | settings and errors |
| `engine/src/dal` | PostgreSQL/SQLite SQL, CouchDB documents, Redis cache |
| `engine/src/domain` | access rules, schemas and ingestion, dataset calculations, reports, statistics |
| `engine/src/presentation` | HTTP API (guest, session and admin routes) and the `serve` command |
| `engine/migrations` | PostgreSQL structure (`*.sql`) and the SQLite test mirror |
| `engine/tests` | integration tests |
| `scripts` | migration, install and deploy scripts |
| `ui` | Flutter web app |

## Storage and migrations

The database structure changes only through `scripts/migrate.sh`:

```bash
scripts/migrate.sh --dry-run   # show the targets and the migration files
scripts/migrate.sh --yes       # apply engine/migrations/*.sql and the CouchDB database/indexes
```

Migration 007 converts existing catalog and calculation data into normalized rows.
Stop engine writers before applying it. Each migration runs in one transaction.
Applied migrations 001, 005 and 006 remain unchanged. For pre-006 databases
with inline dataset definitions, the runner applies 007 before the historical
006 drops those definitions. Later runs use the same idempotent migration path.
Projects, reports and sample data are added through the admin API. The engine never runs DDL: at start it checks the required tables and columns
and stops with a message that names `scripts/migrate.sh` when the schema is missing or
outdated.

Storage normalization replaces localized catalog fields, theme colors, report metadata,
calculation inputs and definition components with constrained rows and parent foreign keys.
Untyped legacy card/settings values and draft operands use scalar/property rows.
No current PostgreSQL column stores JSON or an array. API models and cache keys stay unchanged.
The SQLite test schema mirrors these tables. Historical schemas under test fixtures are
prior-release evidence; they do not define the current schema.

Rollback uses a separate empty database and the schema from the prior release containing
migration 006. Keep the export private. Stop writers, then run:

```bash
# Set REPORTS_STORAGE_DATABASE_URL explicitly to the normalized source database.
python3 scripts/storage_rollback.py --export storage-export.json
# Set REPORTS_STORAGE_DATABASE_URL explicitly to a separate empty restoration database.
python3 scripts/storage_rollback.py --restore storage-export.json --historical-schema prior-release-schema.sql
```

Verify the restored database before starting the prior engine against it. Preserve the
normalized source database until verification succeeds. Restoring into a nonempty schema
fails. The export includes current drafts and versions. Schema 005 cannot represent them,
so it is supported as an upgrade source only. Older inline dataset specs become published
calculation versions during upgrade. The engine does not run migrations at startup.

To test historical upgrades, schema constraints, rollback and idempotence, set
`REPORTS_NORMALIZED_TEST_DATABASE_URL` to an isolated PostgreSQL 16 database whose name
ends with `_test`. The test resets that database's public schema:

```bash
python3 scripts/test_storage_migration.py --reset-test-schema
cargo test --manifest-path engine/Cargo.toml --test normalized_storage_test
```

## Install and run

```bash
cp .env.example .env            # fill in the credentials (mode 0600)
scripts/migrate.sh --yes        # first time and after every new migration
scripts/install.sh              # builds the engine and (re)starts the user service
journalctl --user -u reports-engine.service -f
```

`scripts/install.sh` installs the service only. It never migrates.

Local development:

```bash
cargo run --manifest-path engine/Cargo.toml -- serve
```

## API

OpenAPI description: `http://localhost:8109/openapi.json`.

Guest routes (the gateway checks no session; the engine treats every caller as a guest):

```bash
curl https://api.asodya.com/apps/reports/v1/catalog
curl https://api.asodya.com/apps/reports/v1/projects/cortex
curl https://api.asodya.com/apps/reports/v1/projects/cortex/theme
curl https://api.asodya.com/apps/reports/v1/projects/cortex/reports
curl "https://api.asodya.com/apps/reports/v1/projects/cortex/reports?tier=real"
curl "https://api.asodya.com/apps/reports/v1/projects/cortex/showcase/model-usage?tier=sample"
```

Data tiers: `sample` (synthetic), `real`, and `hybrid` (a report whose cards mix tiers).
`tier` on a report list keeps the reports of that tier; on a report view or showcase it
keeps the cards of that tier, while `data_tier` and `tiers` still describe every visible
card. Each report view and showcase also carries `access`: `total`, `readable`,
`needs_sign_in` (placeholders that any session opens) and `needs_admin` (placeholders that
need a project admin or a grant), counted for the caller.

Session routes (the gateway checks the `sid` cookie and sends the real `x-uuid`):

```bash
curl --cookie "sid=..." https://api.asodya.com/apps/reports/v1/me
curl --cookie "sid=..." https://api.asodya.com/apps/reports/v1/projects/cortex/reports/token-usage
curl --cookie "sid=..." "https://api.asodya.com/apps/reports/v1/projects/cortex/reports/token-usage/datasets/tokens-by-provider?f.provider=ollama"
```

Admin routes (engine role check on every call). Local operator tools call the engine
directly with the service key:

```bash
curl -X POST -H "x-reports-service-key: $REPORTS_SERVICE_API_KEY" -H "Content-Type: application/json" \
  http://localhost:8109/projects/cortex/admin/ingest/telemetry_event \
  -d '{"schema_version": 1, "records": [{"idempotency_key": "req-1", "payload": {"request_id": "req-1"}}]}'
```

## Access rules

- Visibility: `public`, `signed_in`, `restricted`. A dataset uses the stricter of its report and its own value.
- `signed_in` opens for any session, with no role. `restricted` needs a project admin, the super admin or a grant.
- The sample data has 4 reports per project, each with 4 sections of 4 charts, and every
  access case (the `access` entry of each report in `scripts/population/projects/`; the list
  is in `scripts/population/populate.py`).
- Guests get 401 for gated data (login may help). Signed-in callers get 403 (access limited).
- Super admin: `x-access-level: 1` together with `x-uuid` from the gateway session.
- Project admin: a `user_project_roles` row for the user UUID. The `x-project-admin` header is ignored.

## Tests

```bash
cargo test --manifest-path engine/Cargo.toml   # SQLite store, mock CouchDB server, cache fake
cd ui && flutter test
```

Tests never touch the production stores.

## Individual embeds

The Share dialog for an individual chart or table offers **Link** and **Embed**.
The embed preserves `lang`, `visual`, `view` and `f.*` filter parameters. It renders
one item at `/v1/embed/{project}/{report}/{dataset}` without the application shell.
The API descriptor is `GET /projects/{project}/showcase/{report}/cards/{dataset}/embed`;
its `thumbnail_url` points to the corresponding `/thumbnail.png` endpoint.
Both API endpoints always apply guest/public visibility, even for an authenticated
caller. They do not expose an entire report or bypass gated content. Descriptors
and thumbnails use `no-store`. The PNG is rendered from the selected dataset.


The embed reuses the original `DatasetSlot` and `VisualChooser` card components,
including their layout slot, series, companion datasets, filters and selected table
view. Project themes are loaded as in the Reports application. Explicitly shared
full views retain their full-view renderer. The Link/Embed controls use the standard
2 px control radius. The dialog previews the live Reports iframe, not a redraw.
PNG thumbnails are captures of that same public Flutter renderer through a bounded
Chrome DevTools adapter (`REPORTS_CHROME_BINARY`, default `/usr/bin/google-chrome`).
The renderer waits for the actual card to paint, has a 25-second timeout, admits
one capture at a time, caches images in Redis for 120 seconds and checks public
access before every response. If rendering is unavailable it returns 503 rather
than substituting another chart. Isolated tests use a cached captured fixture.


## Backend live logs

`core/logs` provides debug, info, warning and error functions and formats each event
as `<RFC3339 timestamp> <LEVEL> <app> <module> <message>`. Debug is development-only;
info, warning and error are always enabled. Credentials are redacted before the same
line is written to stderr (journald) and the bounded in-process broadcast stream.
No local log files are created. Request logs omit queries, headers and bodies.

LAN operators use `GET /logs/stream` (SSE, no backend authentication). Keep the
service on its existing private listener. Public clients use the gateway's admin-only
`/apps/reports/v1/logs/stream`. Slow consumers receive a `gap` event instead of
unbounded buffering; there is no replay or persistence in this service.

Only api_for_apps records streams in appdb. Its deliberate safety locks stop one
recording after 30 minutes and purge saved rows older than 15 days. This backend
never connects to appdb or changes its schema.

Development follows `APP_ENV=development|dev|local|test`; production disables debug.

## Current aggregate snapshots

The `aggregate_snapshot` schema stores current producer aggregates as append-only rows.
Schema version 1 has required fields `snapshot_id` (string), `snapshot_order` (integer),
`snapshot_complete` (boolean), `availability` (string), `metric` (string),
`group_key` (string), `key` (string), and `value` (integer). `denominator` is an
optional integer. `snapshot_order` is a safe UTC epoch timestamp in microseconds.
Every row in one logical snapshot shares its id and order. Producers post value and
state rows first, then post exactly one `snapshot_complete=true` marker in a separate
ingest call only after all data calls succeed. Ingest can persist earlier chunks when a
later chunk fails, so an incomplete attempt remains invisible until its marker is written.
A retry uses the same snapshot id, order, and row keys. A valid empty snapshot contains
its state rows and marker but no value rows.

The marker uses availability `complete`, metric `snapshot`, empty group and key, and
value zero. Data rows use `snapshot_complete=false`. Value rows use availability
`available`; a language state row has empty key and availability `empty` or
`unavailable`, distinguishing a successful empty response from a missing or failed
source. Its group key is the stable project slug. A producer reuses the same snapshot id
and order when it retries. Idempotency keys include the schema version, snapshot id,
metric and a hash of the natural key. New observations use a new id and a higher order,
including when content returns to an earlier value.

A calculation opts into current-state selection with:

```json
"latest_snapshot": {
  "order_field": "snapshot_order",
  "complete_field": "snapshot_complete",
  "id_field": "snapshot_id"
}
```

The engine finds the greatest `(snapshot_order, snapshot_id)` among complete markers,
selects rows from exactly that snapshot, then applies calculation filters. The ID resolves
equal timestamps deterministically. The calculation filters markers and selects one metric
before grouping. An empty latest snapshot therefore cannot restore historical values.
Calculations without `latest_snapshot` keep their existing behavior.

The approved metric keys are:

| Producer | Metric | Key | Group key | Value and unit |
| --- | --- | --- | --- | --- |
| Domain | `projects_by_status` | status | empty | project count |
| Domain | `categories_distribution` | category | empty | distinct project count |
| Domain | `languages_distribution` | primary language | empty | project count |
| Domain | `project_language_bytes` | GitHub language | project slug | raw bytes; denominator is total language bytes |
| Wilson | `skill_frequency` | skill | empty | skill occurrences |
| Wilson | `issuer_counts` | issuer | empty | visible credential count |
| Wilson | `certification_type_counts` | stored type | empty | visible credential count |

Reports derives the language percentage as `100 * value / denominator` only when the
denominator is positive. It keeps integer bytes and the denominator as separate measures,
and exposes the unrounded numeric percentage with denominator semantics in dataset
metadata. Bytes are not lines of code. Producers send no preformatted percentages or
synthetic monthly rows.

Reproducible schema, `technical-aggregates` report, and 7 dataset/card definitions live in
`scripts/catalog/aggregates.py` (`scripts/catalog/populate_aggregates.sh --project <slug>`
or `REPORTS_AGGREGATE_PROJECT`). When no project slug is configured, the initializer
remains unconfigured and does not assume a deployed project slug.

## Frontend observability

The UI uses the shared [`screen_trail`](https://pub.dev/packages/screen_trail)
package. Errors and usage use separate SQL-backed gateway endpoints. The gateway derives identity and IP.
`ui/tracking_manifest.json` lists screens, stable element ids, labels, paths and
existing-header aliases. Matching constants live in `ui/lib/core/tracking_manifest.dart`.

The router observer and route listener record navigation. Root pointer handling
records mapped clicks. Search, filters and section names record non-sensitive input.
Save/apply callbacks record submits. Query strings and exchange artifacts are omitted.
No chart renderer, theme shape or authentication rule changes.

The header keeps its existing implementation. `ReportsTrackingRoot` maps its declared
localized semantic labels. Explicit control metadata takes priority. This also supports
projects where a shared header must remain unchanged. Custom language metadata follows
LanguageScope without changing widget localization.

The existing error-service interface delegates to the shared package. It keeps its
short duplicate throttle and safe service summaries. Injected mock clients disable
periodic delivery by default. Tests remain offline. The app detaches its tracker on
disposal so repeated widget fixtures restore their error handlers.

## Third-party map boundaries (`reports_view`)

Geographic charts bundle simplified Natural Earth 1:110m admin-0 (174 countries) and
1:10m admin-1 (77 Thailand provinces, 27 Brazil states) boundaries via `reports_view`
(`169,864` bytes in `lib/src/geo/natural_earth_boundaries.dart`), joined by ISO 3166-1
and ISO 3166-2 codes. Source: Natural Earth (Public Domain).
