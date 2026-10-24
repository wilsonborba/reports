//! No redundant loads or calculations: one CouchDB load per schema, appends on ingestion,
//! cached filter options and statistics, and an operations view of the flow.

mod common;

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

use async_trait::async_trait;
use axum::http::StatusCode;
use common::*;
use reports::core::error::ReportError;
use reports::dal::{DocumentStore, InsertOutcome, MemoryDocuments, RecordDoc};
use serde_json::{json, Value};

/// Counts CouchDB reads.
struct CountingDocs {
    inner: Arc<MemoryDocuments>,
    loads: AtomicUsize,
}

#[async_trait]
impl DocumentStore for CountingDocs {
    async fn insert_records(&self, records: &[RecordDoc]) -> Result<InsertOutcome, ReportError> {
        self.inner.insert_records(records).await
    }
    async fn load_records(&self, project: &str, schema: &str, max: usize) -> Result<Vec<RecordDoc>, ReportError> {
        self.loads.fetch_add(1, Ordering::SeqCst);
        self.inner.load_records(project, schema, max).await
    }
    async fn put_snapshot(&self, s: &Value) -> Result<(), ReportError> {
        self.inner.put_snapshot(s).await
    }
    async fn list_snapshots(&self, p: &str, r: &str, d: &str, max: usize) -> Result<Vec<Value>, ReportError> {
        self.inner.list_snapshots(p, r, d, max).await
    }
    async fn delete_fixture_records(&self, f: &str) -> Result<usize, ReportError> {
        self.inner.delete_fixture_records(f).await
    }
    async fn check_ready(&self) -> Result<(), ReportError> {
        self.inner.check_ready().await
    }
}

async fn counting_app() -> (TestApp, Arc<CountingDocs>) {
    let t = TestApp::new().await;
    let docs = Arc::new(CountingDocs { inner: t.docs.clone(), loads: AtomicUsize::new(0) });
    let stores = reports::dal::Stores { db: t.db.clone(), docs: docs.clone(), cache: t.cache.clone(), domain: t.domain.clone() };
    let state = reports::presentation::api::server::AppState::new(stores, &settings());
    let app = reports::presentation::api::server::router(state.clone());
    (TestApp { state, app, ..t }, docs)
}

#[tokio::test]
async fn one_load_per_schema_and_appends_after_ingestion() {
    let (t, docs) = counting_app().await;
    t.seed_cortex().await;
    t.ingest(json!([event("a", "ollama", "qwen", 100, 10, true)])).await;
    let root = [("x-uuid", ROOT), ("x-access-level", "1")];
    // Three cards, a report view, statistics: all read the same schema once.
    for d in ["tokens-by-provider", "latency-by-model", "errors-by-type"] {
        assert_eq!(t.get(&format!("/projects/cortex/reports/token-usage/datasets/{d}"), &root).await.0, StatusCode::OK);
    }
    t.get("/projects/cortex/reports/token-usage", &root).await;
    t.get("/projects/cortex/reports", &[]).await;
    t.get("/projects/cortex/stats", &[]).await;
    assert_eq!(docs.loads.load(Ordering::SeqCst), 1, "one CouchDB load for every reader");

    // New records are appended to the loaded copy: no reload, fresh results.
    t.ingest(json!([event("b", "ollama", "qwen", 50, 10, true)])).await;
    let (_, v) = t.get("/projects/cortex/reports/token-usage/datasets/tokens-by-provider", &root).await;
    assert_eq!(v["rows"], json!([{"provider": "ollama", "tokens": 150.0}]));
    assert_eq!(v["lineage"]["source_watermark"]["telemetry_event"]["records"], 2);
    assert_eq!(docs.loads.load(Ordering::SeqCst), 1, "still one load after the ingestion");

    // The operations view shows the shared copy.
    let (s, ops) = t.get("/admin/operations", &root).await;
    assert_eq!(s, StatusCode::OK, "{ops}");
    assert_eq!(ops["collections"], json!([{"project": "cortex", "schema": "telemetry_event", "rows": 2,
        "watermark": ops["collections"][0]["watermark"].clone()}]));
    assert_eq!(ops["rows_in_memory"], 2);
    assert_eq!(t.get("/admin/operations", &[("x-uuid", ALICE)]).await.0, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn filter_options_and_statistics_are_cached_until_their_inputs_change() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.ingest(json!([event("a", "ollama", "qwen", 100, 10, true)])).await;
    let url = "/projects/cortex/reports/token-usage/datasets/tokens-by-provider";
    let (_, first) = t.get(url, &[]).await;
    assert_eq!(first["filters"][0]["options"].as_array().unwrap().len(), 1);
    let (_, stats) = t.get("/projects/cortex/stats", &[]).await;
    assert_eq!(stats["rows"], 1);
    let misses = t.cache.misses.load(Ordering::SeqCst);
    t.get(url, &[]).await;
    t.get("/projects/cortex/stats", &[]).await;
    assert_eq!(t.cache.misses.load(Ordering::SeqCst), misses, "descriptor, result and statistics are all cache hits");

    // A new provider shows up in the filter options and the statistics right away.
    t.ingest(json!([event("b", "openai", "gpt", 10, 10, true)])).await;
    let (_, after) = t.get(url, &[]).await;
    assert_eq!(after["filters"][0]["options"].as_array().unwrap().len(), 2);
    let (_, stats) = t.get("/projects/cortex/stats", &[]).await;
    assert_eq!(stats["rows"], 2);
    // A catalog change refreshes the statistics too.
    t.service("PUT", "/projects/cortex/admin/reports/token-usage", json!({"title": {"en": "Token Usage"}, "visibility": "restricted"})).await;
    let (_, stats) = t.get("/projects/cortex/stats", &[]).await;
    assert_eq!(stats["reports"], 0);
}
