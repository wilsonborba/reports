//! End-to-end engine flows through the real router: SQLite (definitions), in-process
//! document store and cache (test doubles with the CouchDB and Redis rules).

mod common;

use std::sync::atomic::Ordering;

use axum::http::StatusCode;
use common::*;
use serde_json::{json, Value};

fn rows(v: &Value) -> Vec<Value> {
    v["rows"].as_array().cloned().unwrap_or_default()
}

#[tokio::test]
async fn ingestion_is_durable_idempotent_and_validated() {
    let t = TestApp::new().await;
    t.seed_cortex().await;

    let (s, v) = t.ingest(json!([event("req-1", "ollama", "qwen2.5:7b", 1000, 900, true), event("req-2", "openai", "gpt-4o-mini", 500, 400, true)])).await;
    assert_eq!(s, StatusCode::CREATED, "{v}");
    assert_eq!(v["created"], 2);
    assert_eq!(v["duplicates"], 0);

    // A producer retry with the same idempotency keys writes nothing new.
    let (s, v) = t.ingest(json!([event("req-1", "ollama", "qwen2.5:7b", 1000, 900, true)])).await;
    assert_eq!(s, StatusCode::CREATED);
    assert_eq!(v["created"], 0);
    assert_eq!(v["duplicates"], 1);
    assert_eq!(t.docs.len(), 2);

    // One invalid record refuses the whole batch.
    let mut bad = event("req-3", "ollama", "qwen2.5:7b", 10, 10, true);
    bad["payload"]["total_tokens"] = json!("many");
    bad["payload"]["camera_id"] = json!("x");
    let (s, v) = t.ingest(json!([event("req-4", "ollama", "qwen2.5:7b", 10, 10, true), bad])).await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY, "{v}");
    assert_eq!(v["code"], "validation_failed");
    let paths: Vec<&str> = v["violations"].as_array().unwrap().iter().map(|x| x["field_path"].as_str().unwrap()).collect();
    assert!(paths.contains(&"records[1].total_tokens"), "{paths:?}");
    assert!(paths.contains(&"records[1].camera_id"), "{paths:?}");
    assert_eq!(t.docs.len(), 2, "nothing written");

    // Envelope and version must agree with a published schema.
    let (s, _) = t.service("POST", "/projects/cortex/admin/ingest/telemetry_event", json!({"schema_version": 9, "records": [event("req-5", "a", "b", 1, 1, true)]})).await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let (s, _) = t.service("POST", "/projects/cortex/admin/ingest/telemetry_event", json!({"project": "fsm", "schema_version": 1, "records": [event("req-5", "a", "b", 1, 1, true)]})).await;
    assert_eq!(s, StatusCode::BAD_REQUEST);

    // CouchDB down: no acknowledgement.
    t.docs.offline.store(true, Ordering::SeqCst);
    let (s, v) = t.ingest(json!([event("req-6", "ollama", "qwen2.5:7b", 10, 10, true)])).await;
    assert_eq!(s, StatusCode::SERVICE_UNAVAILABLE, "{v}");
    assert_eq!(v["code"], "storage_unavailable");
}

#[tokio::test]
async fn schema_versions_are_immutable_after_publish() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    // Changing published v1 is refused.
    let mut changed = telemetry_schema();
    changed["version"] = json!(1);
    let (s, v) = t.service("POST", "/projects/cortex/admin/schemas", changed).await;
    assert_eq!(s, StatusCode::CONFLICT, "{v}");
    // Without a version the next number is used.
    let (s, v) = t.service("POST", "/projects/cortex/admin/schemas", telemetry_schema()).await;
    assert_eq!(s, StatusCode::CREATED);
    assert_eq!(v["version"], 2);
    assert_eq!(v["status"], "draft");
    // A draft does not accept records.
    let (s, _) = t.service("POST", "/projects/cortex/admin/ingest/telemetry_event", json!({"schema_version": 2, "records": [event("r", "a", "b", 1, 1, true)]})).await;
    assert_eq!(s, StatusCode::CONFLICT);
    // Old records keep their schema version after v2 is published.
    t.ingest(json!([event("r1", "ollama", "m", 1, 1, true)])).await;
    let (s, _) = t.service("POST", "/projects/cortex/admin/schemas/telemetry_event/versions/2/publish", json!({})).await;
    assert_eq!(s, StatusCode::OK);
    let (s, _) = t.service("POST", "/projects/cortex/admin/schemas/telemetry_event/versions/2/publish", json!({})).await;
    assert_eq!(s, StatusCode::CONFLICT, "publishing twice is refused");
    let stored = reports::dal::DocumentStore::load_records(t.docs.as_ref(), "cortex", "telemetry_event", 100).await.unwrap();
    assert_eq!(stored[0].schema_version, 1);
    // Invalid field definitions are refused.
    let (s, _) = t.service("POST", "/projects/cortex/admin/schemas", json!({"schema_name": "x_schema", "fields": [{"path": "a", "type": "money"}]})).await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn access_matrix_and_sanitized_descriptors() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.ingest(json!([event("a", "ollama", "qwen", 100, 10, true), event("b", "openai", "gpt", 50, 30, false)])).await;
    t.make_project_admin(BOB, "cortex").await;
    // Both gated datasets are discoverable here, so a denied read is 401/403, not 404.
    for (id, visibility) in [("latency-by-model", "signed_in"), ("errors-by-type", "restricted")] {
        let mut d = dataset(id, visibility);
        d["discoverable"] = json!(true);
        t.service("PUT", &format!("/projects/cortex/admin/reports/token-usage/datasets/{id}"), d).await;
    }

    let base = "/projects/cortex/reports/token-usage/datasets";
    let alice = user(ALICE);
    let alice: Vec<(&str, &str)> = alice.iter().map(|(k, v)| (*k, v.as_str())).collect();
    let bob = user(BOB);
    let bob: Vec<(&str, &str)> = bob.iter().map(|(k, v)| (*k, v.as_str())).collect();
    let root = [("x-uuid", ROOT), ("x-access-level", "1")];

    // Guest: public only; 401 for gated (login may help).
    assert_eq!(t.get(&format!("{base}/tokens-by-provider"), &[]).await.0, StatusCode::OK);
    assert_eq!(t.get(&format!("{base}/latency-by-model"), &[]).await.0, StatusCode::UNAUTHORIZED);
    assert_eq!(t.get(&format!("{base}/errors-by-type"), &[]).await.0, StatusCode::UNAUTHORIZED);
    // Signed-in viewer: public + signed_in; 403 for restricted (no login loop).
    assert_eq!(t.get(&format!("{base}/latency-by-model"), &alice).await.0, StatusCode::OK);
    let (s, v) = t.get(&format!("{base}/errors-by-type"), &alice).await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    assert!(v.get("rows").is_none(), "a denied response has no rows");
    // A faked x-project-admin header is ignored.
    let mut faked = alice.clone();
    faked.push(("x-project-admin", "true"));
    assert_eq!(t.get(&format!("{base}/errors-by-type"), &faked).await.0, StatusCode::FORBIDDEN);
    // x-access-level without x-uuid does not make a super admin.
    assert_eq!(t.get(&format!("{base}/errors-by-type"), &[("x-access-level", "1")]).await.0, StatusCode::UNAUTHORIZED);
    // Project admin from the Reports database, and the super admin.
    assert_eq!(t.get(&format!("{base}/errors-by-type"), &bob).await.0, StatusCode::OK);
    assert_eq!(t.get(&format!("{base}/errors-by-type"), &root).await.0, StatusCode::OK);

    // Report view: gated descriptors are sanitized for the guest.
    let (s, v) = t.get("/projects/cortex/reports/token-usage", &[]).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    for d in v["datasets"].as_array().unwrap() {
        if d["dataset_id"] == "tokens-by-provider" {
            assert_eq!(d["can_view"], true);
            assert!(!d["fields"].as_array().unwrap().is_empty());
        } else {
            assert_eq!(d["can_view"], false);
            assert!(d["fields"].as_array().unwrap().is_empty());
            assert!(d["filters"].as_array().unwrap().is_empty());
            assert!(d["equation"].is_null());
        }
    }

    // A restricted, not discoverable report is hidden: 404, and its public dataset too.
    let (s, _) = t.service("PUT", "/projects/cortex/admin/reports/token-usage", json!({"title": {"en": "Token Usage"}, "visibility": "restricted"})).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(t.get(&format!("{base}/tokens-by-provider"), &[]).await.0, StatusCode::NOT_FOUND);
    assert_eq!(t.get(&format!("{base}/tokens-by-provider"), &alice).await.0, StatusCode::NOT_FOUND);
    assert_eq!(t.get(&format!("{base}/tokens-by-provider"), &bob).await.0, StatusCode::OK, "the project admin still reads it");
    // The guest list and the counts no longer show it.
    let (_, v) = t.get("/projects/cortex/reports", &[]).await;
    assert_eq!(v["total"], 0);
    let (_, v) = t.get("/catalog", &[]).await;
    assert_eq!(v["items"][0]["report_count"], 0);
}

#[tokio::test]
async fn results_are_cached_and_invalidated_by_ingestion_only() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.ingest(json!([event("a", "ollama", "qwen", 100, 10, true)])).await;
    let url = "/projects/cortex/reports/token-usage/datasets/tokens-by-provider";

    let (_, first) = t.get(url, &[]).await;
    assert_eq!(rows(&first), vec![json!({"provider": "ollama", "tokens": 100.0})]);
    let calculations = t.state.datasets.counters().calculations;
    let (_, again) = t.get(url, &[]).await;
    assert_eq!(rows(&again), rows(&first));
    assert_eq!(t.state.datasets.counters().calculations, calculations, "second read is a cache hit");

    // Filters and access class make separate entries.
    let (_, filtered) = t.get(&format!("{url}?f.provider=openai"), &[]).await;
    assert!(rows(&filtered).is_empty());

    // New records invalidate only the results that read this schema.
    t.ingest(json!([event("b", "ollama", "qwen", 50, 10, true)])).await;
    let (_, after) = t.get(url, &[]).await;
    assert_eq!(rows(&after), vec![json!({"provider": "ollama", "tokens": 150.0})]);

    // Redis down: the result is calculated from the durable stores.
    t.cache.offline.store(true, Ordering::SeqCst);
    let (s, v) = t.get(url, &[]).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(rows(&v), rows(&after));
    let (_, health) = t.get("/health", &[]).await;
    assert_eq!(health["status"], "degraded");
    assert_eq!(t.get("/ready", &[]).await.0, StatusCode::OK, "Redis is only a cache");
}

#[tokio::test]
async fn definitions_and_records_survive_a_restart() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.ingest(json!([event("a", "ollama", "qwen", 100, 10, true)])).await;
    let t = t.restart().await;
    let (s, v) = t.get("/projects/cortex/reports/token-usage/datasets/tokens-by-provider", &[]).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(rows(&v), vec![json!({"provider": "ollama", "tokens": 100.0})]);
    let (_, v) = t.get("/admin/projects/cortex/schemas", &[("x-reports-service-key", SERVICE_KEY)]).await;
    assert_eq!(v[0]["status"], "published");
    assert_eq!(v[0]["fields"].as_array().unwrap().len(), 9);
}

#[tokio::test]
async fn admin_routes_check_roles() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.make_project_admin(BOB, "cortex").await;
    let body = json!({"title": {"en": "Latency"}, "visibility": "signed_in"});
    // Guest and plain viewer.
    assert_eq!(t.call("PUT", "/admin/projects/cortex/reports/latency", &[], Some(body.clone())).await.0, StatusCode::UNAUTHORIZED);
    assert_eq!(t.call("PUT", "/admin/projects/cortex/reports/latency", &[("x-uuid", ALICE)], Some(body.clone())).await.0, StatusCode::FORBIDDEN);
    // Project admin of cortex: allowed here, refused for another project and for project writes.
    assert_eq!(t.call("PUT", "/admin/projects/cortex/reports/latency", &[("x-uuid", BOB)], Some(body.clone())).await.0, StatusCode::OK);
    assert_eq!(t.call("PUT", "/admin/projects/fsm/reports/latency", &[("x-uuid", BOB)], Some(body.clone())).await.0, StatusCode::FORBIDDEN);
    assert_eq!(
        t.call("PUT", "/projects/cortex/admin/project", &[("x-uuid", BOB)], Some(json!({"name": {"en": "Cortex"}}))).await.0,
        StatusCode::FORBIDDEN
    );
    // A wrong service key is refused, never treated as a guest.
    assert_eq!(t.call("PUT", "/projects/cortex/admin/reports/x1", &[("x-reports-service-key", "wrong")], Some(body.clone())).await.0, StatusCode::FORBIDDEN);
    // Writes default to restricted and refuse unknown visibility.
    let (_, v, _) = t.call("PUT", "/projects/cortex/admin/reports/defaults", &[("x-reports-service-key", SERVICE_KEY)], Some(json!({"title": {"en": "Defaults"}}))).await;
    assert_eq!(v["visibility"], "restricted");
    let (s, _, _) = t.call("PUT", "/projects/cortex/admin/reports/odd", &[("x-reports-service-key", SERVICE_KEY)], Some(json!({"title": {"en": "Odd"}, "visibility": "internal"}))).await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    // A card binds only a published calculation version.
    let mut d = dataset("tokens-by-provider", "public");
    d["calculation_version"] = json!(7);
    let (s, _, _) = t.call("PUT", "/projects/cortex/admin/reports/token-usage/datasets/x2", &[("x-reports-service-key", SERVICE_KEY)], Some(d)).await;
    assert_eq!(s, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn session_responses_are_private_and_old_routes_are_gone() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    let (_, _, headers) = t.call("GET", "/projects/cortex/reports/token-usage", &[("x-uuid", ALICE)], None).await;
    assert_eq!(headers.get("cache-control").unwrap(), "private, no-store");
    let (s, v) = t.get("/me", &[("x-uuid", ALICE)]).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(v["role"], "viewer");
    assert_eq!(t.get("/me", &[]).await.0, StatusCode::UNAUTHORIZED);
    for old in ["/api/v1/projects", "/public/projects", "/api/v1/auth/me", "/site", "/projects/cortex/token-usage"] {
        assert_eq!(t.get(old, &[]).await.0, StatusCode::NOT_FOUND, "{old}");
    }
    let (s, v) = t.get("/openapi.json", &[]).await;
    assert_eq!(s, StatusCode::OK);
    assert!(v["paths"]["/projects/{project}/admin/ingest/{schema}"].is_object());
}
