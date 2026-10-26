use std::net::SocketAddr;
use std::sync::Arc;

use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::{get, post, put};
use axum::{Json, Router};
use serde::Serialize;
use tower_http::trace::TraceLayer;
use utoipa::{OpenApi, ToSchema};

use super::{admin, docs::ApiDoc, public, viewer, embeds};
use crate::core::config::Settings;
use crate::core::error::ReportError;
use crate::dal::domain_api::HttpDomain;
use crate::dal::{CouchDocuments, Db, RedisCache, Stores};
use crate::domain::auth::ServiceKeyRing;
use crate::domain::datasets::service::CacheCounters;
use crate::domain::datasets::DatasetService;

pub struct AppState {
    pub stores: Stores,
    pub datasets: Arc<DatasetService>,
    pub keys: ServiceKeyRing,
    pub settings: Settings,
}

impl AppState {
    pub fn new(stores: Stores, settings: &Settings) -> Arc<Self> {
        Arc::new(Self {
            datasets: Arc::new(DatasetService::new(stores.clone(), settings)),
            keys: ServiceKeyRing::new(&settings.service_api_key, &settings.api_keys),
            settings: settings.clone(),
            stores,
        })
    }
}

#[derive(Debug, Serialize, ToSchema)]
pub struct HealthResponse {
    /// ok, degraded (Redis down: no cache) or down (PostgreSQL or CouchDB down)
    pub status: &'static str,
    pub version: &'static str,
    pub postgres: bool,
    pub couchdb: bool,
    pub redis: bool,
    pub cache: CacheCounters,
}

async fn health_of(state: &AppState) -> HealthResponse {
    let (postgres, couchdb, redis) = tokio::join!(
        state.stores.db.health(),
        state.stores.docs.health(),
        state.stores.cache.health()
    );
    HealthResponse {
        status: if !(postgres && couchdb) {
            "down"
        } else if !redis {
            "degraded"
        } else {
            "ok"
        },
        version: env!("CARGO_PKG_VERSION"),
        postgres,
        couchdb,
        redis,
        cache: state.datasets.counters(),
    }
}

#[utoipa::path(
    get,
    path = "/health",
    summary = "Liveness and store status",
    description = "Always 200 while the process runs. Example: `curl https://api.asodya.com/apps/reports/v1/health`",
    responses((status = 200, description = "Store status", body = HealthResponse)),
    tag = "Health"
)]
pub async fn health(State(state): State<Arc<AppState>>) -> Json<HealthResponse> {
    Json(health_of(&state).await)
}

#[utoipa::path(
    get,
    path = "/ready",
    summary = "Readiness",
    description = "200 when PostgreSQL and CouchDB answer. Redis down gives `degraded` but stays ready, because Redis is only a cache.",
    responses((status = 200, description = "Ready", body = HealthResponse), (status = 503, description = "Not ready", body = HealthResponse)),
    tag = "Health"
)]
pub async fn ready(State(state): State<Arc<AppState>>) -> (StatusCode, Json<HealthResponse>) {
    let h = health_of(&state).await;
    let code = if h.postgres && h.couchdb { StatusCode::OK } else { StatusCode::SERVICE_UNAVAILABLE };
    (code, Json(h))
}

/// Admin routes. `with_reads` adds the GET routes, only under `/admin/projects/...`:
/// under `/projects/*` the gateway treats every GET as public.
fn admin_routes(with_reads: bool) -> Router<Arc<AppState>> {
    let schemas = if with_reads {
        get(admin::list_schemas).post(admin::post_schema)
    } else {
        post(admin::post_schema)
    };
    let grants = if with_reads {
        get(admin::list_grants).post(admin::post_grant)
    } else {
        post(admin::post_grant)
    };
    let calcs = if with_reads {
        get(admin::list_calculations).post(admin::post_calculation)
    } else {
        post(admin::post_calculation)
    };
    let snapshots = if with_reads {
        get(admin::list_snapshots).post(admin::post_snapshot)
    } else {
        post(admin::post_snapshot)
    };
    let mut router = Router::new()
        .route("/calculations", calcs)
        .route("/calculations/:calculation/versions/:version/validate", post(admin::validate_calculation))
        .route("/calculations/:calculation/versions/:version/publish", post(admin::publish_calculation))
        .route("/calculations/:calculation/versions/:version/retire", post(admin::retire_calculation))
        .route("/reports/:report/datasets/:dataset/snapshots", snapshots)
        .route("/grants", grants)
        .route("/grants/:grant", axum::routing::delete(admin::delete_grant))
        .route("/roles/:user", put(admin::put_role).delete(admin::delete_role));
    if with_reads {
        router = router.route("/roles", get(admin::list_roles));
    }
    router
        .route("/project", put(admin::put_project))
        .route("/theme", put(admin::put_theme))
        .route("/reports/:report", put(admin::put_report).delete(admin::delete_report))
        .route(
            "/reports/:report/datasets/:dataset",
            put(admin::put_dataset).delete(admin::delete_dataset),
        )
        .route("/schemas", schemas)
        .route("/schemas/:schema/versions/:version/publish", post(admin::publish_schema))
        .route("/schemas/:schema/versions/:version/retire", post(admin::retire_schema))
        .route("/ingest/:schema", post(admin::ingest_records))
}

pub fn router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/logs/stream", get(super::logs::stream))
        .route("/openapi.json", get(|| async { Json(ApiDoc::openapi()) }))
        .route("/", get(|| async { Json(serde_json::json!({"service": "reports", "openapi": "/openapi.json"})) }))
        .route("/health", get(health))
        .route("/ready", get(ready))
        // Guest routes (gateway public rule).
        .route("/catalog", get(public::list_projects))
        .route("/projects", get(public::list_projects))
        .route("/projects/:project", get(public::project_detail))
        .route("/projects/:project/theme", get(public::project_theme))
        .route("/projects/:project/reports", get(public::list_reports))
        .route("/projects/:project/stats", get(public::project_stats))
        .route("/projects/:project/showcase/:report", get(public::showcase))
        .route("/projects/:project/showcase/:report/cards/:card", get(public::showcase_card))
        .route("/projects/:project/showcase/:report/cards/:dataset/embed", get(embeds::descriptor))
        .route("/projects/:project/showcase/:report/cards/:dataset/thumbnail.png", get(embeds::thumbnail))
        .route("/stats", get(public::global_stats))
        // Session routes (gateway session rule).
        .route("/me", get(viewer::me))
        .route("/me/projects/:project/reports", get(viewer::my_reports))
        .route("/projects/:project/reports/:report", get(viewer::report_view))
        .route("/projects/:project/reports/:report/datasets/:dataset", get(viewer::dataset_page))
        .route("/projects/:project/reports/:report/cards/:dataset", get(viewer::dataset_page))
        // Admin routes (both prefixes; the engine checks the role on every call).
        .nest("/projects/:project/admin", admin_routes(false))
        .nest("/admin/projects/:project", admin_routes(true))
        .route("/admin/fixtures/:manifest", axum::routing::delete(admin::delete_fixture))
        .route("/admin/operations", get(admin::operations))
        // The request log keeps the path only: a query can hold a login artifact.
        .layer(TraceLayer::new_for_http().make_span_with(|req: &axum::http::Request<axum::body::Body>| {
            tracing::debug_span!("request", method = %req.method(), path = %req.uri().path())
        }))
        .layer(axum::middleware::from_fn(super::logs::request_log))
        .with_state(state)
}

/// Opens the production stores and checks them. Nothing is migrated or created here.
pub async fn production_stores(settings: &Settings) -> Result<Stores, ReportError> {
    let db = Db::connect(&settings.database_url)?;
    db.check_schema().await?;
    let docs = CouchDocuments::new(
        &settings.couchdb_url,
        &settings.couchdb_database,
        settings.couchdb_user.clone(),
        settings.couchdb_password.clone(),
    )?;
    use crate::dal::DocumentStore;
    docs.check_ready().await?;
    let cache = RedisCache::new(&settings.redis_url, &settings.redis_namespace)
        .map_err(|e| ReportError::Internal(format!("Redis configuration: {e}")))?;
    let domain = HttpDomain::new(
        &settings.domain_api_url,
        &settings.domain_public_url,
        std::time::Duration::from_millis(settings.domain_timeout_ms),
    )?;
    Ok(Stores { db: Arc::new(db), docs: Arc::new(docs), cache: Arc::new(cache), domain: Arc::new(domain) })
}

pub async fn run_server(settings: Settings) -> anyhow::Result<()> {
    if settings.is_production() && settings.service_api_key.is_empty() {
        anyhow::bail!("REPORTS_SERVICE_API_KEY is required when APP_ENV is '{}'", settings.environment);
    }
    let stores = production_stores(&settings).await.map_err(|e| anyhow::anyhow!("{e}"))?;
    let state = AppState::new(stores, &settings);
    tracing::info!("service keys: {}", state.keys.names().join(", "));
    let addr: SocketAddr = format!("{}:{}", settings.server_host, settings.server_port).parse()?;
    tracing::info!("Reports engine listening on http://{addr} (OpenAPI at /openapi.json)");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, router(state)).await?;
    Ok(())
}
