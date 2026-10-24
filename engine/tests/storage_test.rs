//! SQL store on SQLite (same queries as PostgreSQL), the CouchDB adapter against an
//! in-process mock CouchDB server, and the Redis cache fallback.

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde_json::{json, Value};

use reports::dal::{catalog, CacheStore, CouchDocuments, Db, DocumentStore, LockState, ProjectRecord, RecordDoc, RedisCache};
use reports::domain::themes::ProjectTheme;

async fn sqlite() -> (tempfile::TempDir, String, Db) {
    let dir = tempfile::tempdir().unwrap();
    let url = format!("sqlite://{}?mode=rwc", dir.path().join("t.db").display());
    let db = Db::connect(&url).unwrap();
    db.create_sqlite_test_schema().await.unwrap();
    (dir, url, db)
}

#[tokio::test]
async fn schema_check_passes_on_a_migrated_database_and_names_missing_parts() {
    let (_dir, _url, db) = sqlite().await;
    db.check_schema().await.unwrap();
    sqlx::query("DROP TABLE schema_fields").execute(&db.pool).await.unwrap();
    let err = db.check_schema().await.unwrap_err().to_string();
    assert!(err.contains("schema_fields.field_path"), "{err}");
    assert!(err.contains("scripts/migrate.sh"), "{err}");
}

#[tokio::test]
async fn project_writes_persist_across_a_new_connection() {
    let (_dir, url, db) = sqlite().await;
    let p = ProjectRecord {
        slug: "fsm".into(),
        name: [("en".to_string(), "FSM Media Storage".to_string())].into(),
        tagline: Default::default(),
        description: [("pt-BR".to_string(), "Armazenamento de mídia na LAN".to_string())].into(),
        theme: ProjectTheme::default(),
        is_active: true,
        website_url: Some("https://github.com/wilsonborba/fsm".into()),
        repository_url: Some("https://github.com/wilsonborba/fsm".into()),
        sort_order: 5,
        domain_project_id: Some("203321df-c74d-4725-afdf-370d1d41a522".into()),
        updated_at: String::new(),
    };
    catalog::upsert_project(&db, &p).await.unwrap();
    db.pool.close().await;
    let db = Db::connect(&url).unwrap();
    let got = catalog::get_project(&db, "fsm").await.unwrap().unwrap();
    assert_eq!(got.name, p.name);
    assert_eq!(got.description, p.description);
    assert_eq!(got.domain_project_id, p.domain_project_id);
    assert_eq!(got.website_url, p.website_url);
    assert_eq!(got.sort_order, 5);
    assert!(got.is_active);
    assert!(!got.updated_at.is_empty());
    assert_eq!(catalog::list_projects(&db, true).await.unwrap().len(), 1);
}

#[tokio::test]
async fn database_outage_is_a_clear_error() {
    let db = Db::connect("postgres://reports:x@127.0.0.1:1/asodya_reports").unwrap();
    let err = catalog::list_projects(&db, true).await.unwrap_err();
    assert_eq!(err.status(), StatusCode::SERVICE_UNAVAILABLE, "{err}");
    assert!(!db.health().await);
}

// --- mock CouchDB -----------------------------------------------------------

type Docs = Arc<Mutex<HashMap<String, Value>>>;

async fn bulk(State(docs): State<Docs>, Path(_db): Path<String>, Json(body): Json<Value>) -> (StatusCode, Json<Value>) {
    let mut store = docs.lock().unwrap();
    let mut out = Vec::new();
    for d in body["docs"].as_array().unwrap() {
        let id = d["_id"].as_str().unwrap().to_string();
        if d.get("_deleted").and_then(Value::as_bool) == Some(true) {
            store.remove(&id);
            out.push(json!({"id": id, "ok": true}));
        } else if store.contains_key(&id) {
            out.push(json!({"id": id, "error": "conflict", "reason": "Document update conflict."}));
        } else {
            let mut doc = d.clone();
            doc["_rev"] = json!("1-abc");
            store.insert(id.clone(), doc);
            out.push(json!({"id": id, "ok": true, "rev": "1-abc"}));
        }
    }
    (StatusCode::CREATED, Json(json!(out)))
}

/// `_find` with equality selectors and bookmark pagination (bookmark = offset).
async fn find(State(docs): State<Docs>, Path(_db): Path<String>, Json(body): Json<Value>) -> Json<Value> {
    let store = docs.lock().unwrap();
    let selector = body["selector"].as_object().unwrap();
    let mut matched: Vec<Value> = store
        .values()
        .filter(|d| selector.iter().all(|(k, v)| d.get(k) == Some(v)))
        .cloned()
        .collect();
    matched.sort_by(|a, b| a["_id"].as_str().cmp(&b["_id"].as_str()));
    let start: usize = body["bookmark"].as_str().and_then(|b| b.parse().ok()).unwrap_or(0);
    let limit = body["limit"].as_u64().unwrap() as usize;
    let page: Vec<Value> = matched.into_iter().skip(start).take(limit).collect();
    let bookmark = (start + page.len()).to_string();
    Json(json!({"docs": page, "bookmark": bookmark}))
}

async fn mock_couch() -> (String, Docs) {
    let docs: Docs = Arc::default();
    let app = Router::new()
        .route("/:db", get(|Path(db): Path<String>| async move {
            if db == "reports_documents" { (StatusCode::OK, Json(json!({"db_name": db}))) } else { (StatusCode::NOT_FOUND, Json(json!({"error": "not_found"}))) }
        }))
        .route("/:db/_bulk_docs", post(bulk))
        .route("/:db/_find", post(find))
        .with_state(docs.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr: SocketAddr = listener.local_addr().unwrap();
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    (format!("http://{addr}"), docs)
}

fn record(key: &str, fixture: Option<&str>) -> RecordDoc {
    RecordDoc::new(
        "autodroid",
        "job",
        1,
        key,
        Some("2026-10-21T08:00:00Z".into()),
        fixture.map(str::to_string),
        json!({"job_type": "instagram.post", "adapter_name": "aiograpi", "status": "done", "attempt_count": 1}),
    )
}

#[tokio::test]
async fn couchdb_adapter_is_idempotent_and_reads_back_records() {
    let (url, _docs) = mock_couch().await;
    let couch = CouchDocuments::new(&url, "reports_documents", None, None).unwrap();
    couch.check_ready().await.unwrap();

    let first = couch.insert_records(&[record("job-1", None), record("job-2", Some("sample-v1"))]).await.unwrap();
    assert_eq!((first.created, first.duplicates), (2, 0));
    let retry = couch.insert_records(&[record("job-1", None)]).await.unwrap();
    assert_eq!((retry.created, retry.duplicates), (0, 1));

    let back = couch.load_records("autodroid", "job", 10).await.unwrap();
    assert_eq!(back.len(), 2);
    assert_eq!(back[0].schema_version, 1);
    assert_eq!(back[0].payload["adapter_name"], "aiograpi");
    assert!(couch.load_records("autodroid", "job", 1).await.is_err(), "scan limit applies");

    assert_eq!(couch.delete_fixture_records("sample-v1").await.unwrap(), 1);
    assert_eq!(couch.load_records("autodroid", "job", 10).await.unwrap().len(), 1, "manual record stays");
}

#[tokio::test]
async fn couchdb_outage_and_missing_database_are_clear() {
    let (url, _docs) = mock_couch().await;
    let missing = CouchDocuments::new(&url, "other_db", None, None).unwrap();
    let err = missing.check_ready().await.unwrap_err().to_string();
    assert!(err.contains("scripts/migrate.sh"), "{err}");
    let down = CouchDocuments::new("http://127.0.0.1:1", "reports_documents", None, None).unwrap();
    let err = down.insert_records(&[record("job-9", None)]).await.unwrap_err();
    assert_eq!(err.status(), StatusCode::SERVICE_UNAVAILABLE);
    assert!(!down.health().await);
}

#[tokio::test]
async fn redis_outage_is_a_cache_miss() {
    let cache = RedisCache::new("redis://127.0.0.1:1/6", "reports:").unwrap();
    cache.set("k", "v", 60).await;
    assert_eq!(cache.get("k").await, None);
    assert_eq!(cache.try_lock("k", "t", 5).await, LockState::Unavailable);
    assert_eq!(cache.invalidate_tag("schema:cortex:telemetry_event").await, 0);
    assert!(!cache.health().await);
}

#[tokio::test]
async fn memory_cache_tags_and_locks() {
    let cache = reports::dal::MemoryCache::default();
    cache.set("a", "1", 60).await;
    cache.set("b", "2", 60).await;
    cache.tag("schema:cortex:telemetry_event", "a", 60).await;
    assert_eq!(cache.invalidate_tag("schema:cortex:telemetry_event").await, 1);
    assert_eq!(cache.get("a").await, None);
    assert_eq!(cache.get("b").await.as_deref(), Some("2"));
    assert_eq!(cache.try_lock("g", "t1", 60).await, LockState::Acquired);
    assert_eq!(cache.try_lock("g", "t2", 60).await, LockState::Busy);
    cache.unlock("g", "t2").await;
    assert_eq!(cache.try_lock("g", "t3", 60).await, LockState::Busy, "only the owner unlocks");
    cache.unlock("g", "t1").await;
    assert_eq!(cache.try_lock("g", "t3", 60).await, LockState::Acquired);
}
