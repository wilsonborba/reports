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

Migrations hold structure only. Projects, reports and sample data are added through the
admin API. The engine never runs DDL: at start it checks the required tables and columns
and stops with a message that names `scripts/migrate.sh` when the schema is missing or
outdated.

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

Interactive docs: `http://localhost:8109/scalar` (OpenAPI at `/openapi.json`).

Guest routes (the gateway checks no session; the engine treats every caller as a guest):

```bash
curl https://api.asodya.com/apps/reports/v1/catalog
curl https://api.asodya.com/apps/reports/v1/projects/cortex
curl https://api.asodya.com/apps/reports/v1/projects/cortex/theme
curl https://api.asodya.com/apps/reports/v1/projects/cortex/reports
```

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
- The sample data has every case (the `access` entry of each report in `scripts/population/projects/`):
  login only in `domain/repository-health`, `cortex/model-usage`, `autodroid/job-queue` and
  `certifications/study-progress`; login plus admin in `certifications/exam-results`,
  `autodroid/job-reliability` and `cortex/reliability`; a hidden card in `fsm/media-activity`.
- Guests get 401 for gated data (login may help). Signed-in callers get 403 (access limited).
- Super admin: `x-access-level: 1` together with `x-uuid` from the gateway session.
- Project admin: a `user_project_roles` row for the user UUID. The `x-project-admin` header is ignored.

## Tests

```bash
cargo test --manifest-path engine/Cargo.toml   # SQLite store, mock CouchDB server, cache fake
cd ui && flutter test
```

Tests never touch the production stores.
