//! Test harness: SQLite database file, in-process document store and cache, real router.
#![allow(dead_code)]

use std::sync::Arc;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use axum::Router;
use serde_json::{json, Value};
use tower::ServiceExt;

use reports::core::config::Settings;
use reports::dal::domain_api::{DomainProject, StaticDomain};
use reports::dal::{Db, MemoryCache, MemoryDocuments, Stores};
use reports::presentation::api::server::{router, AppState};

pub const SERVICE_KEY: &str = "test-service-key";
pub const ALICE: &str = "6f1d2c3b-4a59-4e6f-8a7b-9c0d1e2f3a4b";
pub const BOB: &str = "0a1b2c3d-4e5f-4a6b-8c7d-8e9f0a1b2c3d";
pub const ROOT: &str = "9e8d7c6b-5a49-4382-9716-2f3e4d5c6b7a";

pub struct TestApp {
    pub dir: tempfile::TempDir,
    pub url: String,
    pub db: Arc<Db>,
    pub docs: Arc<MemoryDocuments>,
    pub cache: Arc<MemoryCache>,
    pub domain: Arc<StaticDomain>,
    pub state: Arc<AppState>,
    pub app: Router,
}

pub fn settings() -> Settings {
    Settings {
        environment: "test".into(),
        service_api_key: SERVICE_KEY.into(),
        ..Settings::default()
    }
}

impl TestApp {
    pub async fn new() -> Self {
        let _ = tracing_subscriber::fmt().with_test_writer().with_env_filter("reports=warn").try_init();
        let dir = tempfile::tempdir().unwrap();
        let url = format!("sqlite://{}?mode=rwc", dir.path().join("reports.db").display());
        let db = Arc::new(Db::connect(&url).unwrap());
        db.create_sqlite_test_schema().await.unwrap();
        let domain = Arc::new(StaticDomain::default());
        *domain.projects.lock().unwrap() = Some(domain_projects());
        Self::with(dir, url, db, Arc::new(MemoryDocuments::default()), Arc::new(MemoryCache::default()), domain)
    }

    fn with(dir: tempfile::TempDir, url: String, db: Arc<Db>, docs: Arc<MemoryDocuments>, cache: Arc<MemoryCache>, domain: Arc<StaticDomain>) -> Self {
        let stores = Stores { db: db.clone(), docs: docs.clone(), cache: cache.clone(), domain: domain.clone() };
        let state = AppState::new(stores, &settings());
        let app = router(state.clone());
        Self { dir, url, db, docs, cache, domain, state, app }
    }

    /// A new engine process over the same database file, document store, cache and Domain.
    pub async fn restart(self) -> Self {
        let TestApp { dir, url, db, docs, cache, domain, .. } = self;
        db.pool.close().await;
        let db = Arc::new(Db::connect(&url).unwrap());
        Self::with(dir, url, db, docs, cache, domain)
    }

    pub async fn call(&self, method: &str, path: &str, headers: &[(&str, &str)], body: Option<Value>) -> (StatusCode, Value, axum::http::HeaderMap) {
        let mut req = Request::builder().method(method).uri(path);
        for (k, v) in headers {
            req = req.header(*k, *v);
        }
        let req = match body {
            Some(b) => req.header("content-type", "application/json").body(Body::from(b.to_string())).unwrap(),
            None => req.body(Body::empty()).unwrap(),
        };
        let response = self.app.clone().oneshot(req).await.unwrap();
        let status = response.status();
        let headers = response.headers().clone();
        let bytes = axum::body::to_bytes(response.into_body(), 16 * 1024 * 1024).await.unwrap();
        let value = if bytes.is_empty() { Value::Null } else { serde_json::from_slice(&bytes).unwrap_or(Value::String(String::from_utf8_lossy(&bytes).into())) };
        (status, value, headers)
    }

    pub async fn get(&self, path: &str, headers: &[(&str, &str)]) -> (StatusCode, Value) {
        let (s, v, _) = self.call("GET", path, headers, None).await;
        (s, v)
    }

    pub async fn service(&self, method: &str, path: &str, body: Value) -> (StatusCode, Value) {
        let (s, v, _) = self.call(method, path, &[("x-reports-service-key", SERVICE_KEY)], Some(body)).await;
        (s, v)
    }

    /// Marks a user as project admin through the roles API.
    pub async fn make_project_admin(&self, user: &str, project: &str) {
        let (s, v) = self.service("PUT", &format!("/projects/{project}/admin/roles/{user}"), json!({"is_project_admin": true})).await;
        assert_eq!(s, StatusCode::OK, "{v}");
    }

    /// Cortex project, the published `telemetry_event` schema (fields of cortex_api
    /// `TelemetryEvent`), a report and three datasets (public, signed_in, restricted).
    pub async fn seed_cortex(&self) {
        let (s, v) = self.service("PUT", "/projects/cortex/admin/project", json!({
            "name": {"en": "Cortex", "pt-BR": "Cortex", "th": "Cortex"},
            "description": {"en": "Multi-model LLM orchestration", "pt-BR": "Orquestração de LLMs"}
        })).await;
        assert_eq!(s, StatusCode::OK, "{v}");
        let (s, v) = self.service("POST", "/projects/cortex/admin/schemas", telemetry_schema()).await;
        assert_eq!(s, StatusCode::CREATED, "{v}");
        let (s, v) = self.service("POST", "/projects/cortex/admin/schemas/telemetry_event/versions/1/publish", json!({})).await;
        assert_eq!(s, StatusCode::OK, "{v}");
        let (s, v) = self.service("PUT", "/projects/cortex/admin/reports/token-usage", json!({
            "title": {"en": "Token Usage", "pt-BR": "Uso de Tokens"},
            "visibility": "public",
            "metadata": {"tags": ["llm"], "period_source": {"collection": "telemetry_event", "field": "day"}}
        })).await;
        assert_eq!(s, StatusCode::OK, "{v}");
        for (id, visibility) in [("tokens-by-provider", "public"), ("latency-by-model", "signed_in"), ("errors-by-type", "restricted")] {
            self.publish_calculation("cortex", id, definition(id)).await;
            let (s, v) = self.service("PUT", &format!("/projects/cortex/admin/reports/token-usage/datasets/{id}"), dataset(id, visibility)).await;
            assert_eq!(s, StatusCode::OK, "{v}");
        }
    }

    /// Creates the next draft of a calculation and publishes it. Returns the version.
    pub async fn publish_calculation(&self, project: &str, id: &str, definition: Value) -> i64 {
        let (s, v) = self.service("POST", &format!("/projects/{project}/admin/calculations"), json!({"calculation_id": id, "definition": definition})).await;
        assert_eq!(s, StatusCode::CREATED, "{v}");
        let version = v["version"].as_i64().unwrap();
        let (s, v) = self.service("POST", &format!("/projects/{project}/admin/calculations/{id}/versions/{version}/publish"), json!({})).await;
        assert_eq!(s, StatusCode::OK, "{v}");
        version
    }

    pub async fn ingest(&self, records: Value) -> (StatusCode, Value) {
        self.service("POST", "/projects/cortex/admin/ingest/telemetry_event", json!({"schema_version": 1, "records": records})).await
    }
}

pub fn telemetry_schema() -> Value {
    json!({
        "schema_name": "telemetry_event",
        "description": "cortex_api TelemetryEvent",
        "fields": [
            {"path": "request_id", "type": "string", "required": true},
            {"path": "day", "type": "date", "required": true},
            {"path": "tier_requested", "type": "integer", "required": true},
            {"path": "provider", "type": "string", "required": true},
            {"path": "model", "type": "string", "required": true},
            {"path": "total_tokens", "type": "integer", "required": true},
            {"path": "latency_ms", "type": "integer", "required": true},
            {"path": "success", "type": "boolean", "required": true},
            {"path": "error_type", "type": "string", "required": false}
        ]
    })
}

pub fn event(id: &str, provider: &str, model: &str, tokens: i64, latency: i64, success: bool) -> Value {
    json!({
        "idempotency_key": id,
        "event_time": "2026-10-20T09:00:00+07:00",
        "payload": {
            "request_id": id, "day": "2026-10-20", "tier_requested": 2,
            "provider": provider, "model": model, "total_tokens": tokens,
            "latency_ms": latency, "success": success,
            "error_type": if success { Value::Null } else { json!("timeout") }
        }
    })
}

/// Card binding to version 1 of the calculation with the same ID.
pub fn dataset(id: &str, visibility: &str) -> Value {
    json!({"data_tier": "sample", "visibility": visibility, "calculation_id": id, "calculation_version": 1})
}

/// Definition of the test calculations over `telemetry_event`.
pub fn definition(id: &str) -> Value {
    let (group, measure, agg, field) = match id {
        "tokens-by-provider" => ("provider", "tokens", "sum", "total_tokens"),
        "latency-by-model" => ("model", "latency", "avg", "latency_ms"),
        _ => ("error_type", "errors", "count", "request_id"),
    };
    json!({
        "title": {"en": id},
        "source": "telemetry_event",
        "filters": [{"field": "provider", "label": {"en": "Provider"}, "type": "category"}],
        "stages": [{"group_by": [group], "measures": [{"name": measure, "agg": agg, "field": field}]}],
        "sort": [{"field": group}],
        "fields": [
            {"name": group, "label": {"en": group}, "type": "string", "role": "dimension"},
            {"name": measure, "label": {"en": measure}, "type": "float", "role": "measure"}
        ]
    })
}

pub fn user(uuid: &str) -> Vec<(&'static str, String)> {
    vec![("x-uuid", uuid.to_string())]
}

pub const CORTEX_DOMAIN_ID: &str = "4ef82613-e51e-42fa-9f3e-93809fdff54b";
pub const HOME_DOMAIN_ID: &str = "fc582b4a-9503-45b5-b0d3-9533be8ec9c7";

/// Two domain_api projects as `GET /projects` lists them (normalized).
pub fn domain_projects() -> Vec<DomainProject> {
    vec![
        DomainProject {
            id: CORTEX_DOMAIN_ID.into(),
            slug: "cortex".into(),
            name: "Cortex Web".into(),
            tagline: Some("Monochromatic Neural-Grid AI Assistant Interface".into()),
            description: Some("AI workstation frontend for Cortex".into()),
            status: Some("on development".into()),
            main_link: Some("https://cortex.asodya.com".into()),
            repository_url: Some("https://github.com/wilsonborba/cortex".into()),
            cover_url: Some("https://api.asodya.com/apps/domain/v1/projects/cortex/cover".into()),
        },
        DomainProject {
            id: HOME_DOMAIN_ID.into(),
            slug: "asodya-home".into(),
            name: "Asodya Home".into(),
            tagline: Some("Discovery Platform & Ecosystem Catalog Frontend".into()),
            description: None,
            status: None,
            main_link: Some("https://asodya.com".into()),
            repository_url: Some("https://github.com/wilsonborba/domain".into()),
            cover_url: None,
        },
    ]
}
