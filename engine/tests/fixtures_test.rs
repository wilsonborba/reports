//! Sample-data ownership: a fixture delete removes only what its manifest owns.

mod common;

use axum::http::StatusCode;
use common::*;
use serde_json::{json, Value};

const FIX: &str = "sample-v1-cortex";

async fn fx(t: &TestApp, method: &str, path: &str, body: Value) -> (StatusCode, Value) {
    let (s, v, _) = t.call(method, path, &[("x-reports-service-key", SERVICE_KEY), ("x-reports-fixture", FIX)], Some(body)).await;
    (s, v)
}

#[tokio::test]
async fn fixture_delete_removes_only_owned_entities() {
    let t = TestApp::new().await;
    // The project row comes from the catalog, not from the fixture.
    t.service("PUT", "/projects/cortex/admin/project", json!({"name": {"en": "Cortex"}})).await;
    assert_eq!(fx(&t, "POST", "/projects/cortex/admin/schemas", telemetry_schema()).await.0, StatusCode::CREATED);
    t.service("POST", "/projects/cortex/admin/schemas/telemetry_event/versions/1/publish", json!({})).await;
    for id in ["tokens-by-provider", "latency-by-model"] {
        let (s, v) = fx(&t, "POST", "/projects/cortex/admin/calculations", json!({"calculation_id": id, "definition": definition(id)})).await;
        assert_eq!(s, StatusCode::CREATED, "{v}");
        t.service("POST", &format!("/projects/cortex/admin/calculations/{id}/versions/1/publish"), json!({})).await;
    }
    fx(&t, "PUT", "/projects/cortex/admin/reports/token-usage", json!({"title": {"en": "Token Usage"}, "visibility": "public"})).await;
    for id in ["tokens-by-provider", "latency-by-model"] {
        assert_eq!(fx(&t, "PUT", &format!("/projects/cortex/admin/reports/token-usage/datasets/{id}"), dataset(id, "public")).await.0, StatusCode::OK);
    }
    // Fixture records plus one manual record of the same schema.
    let (s, _) = fx(&t, "POST", "/projects/cortex/admin/ingest/telemetry_event", json!({"schema_version": 1, "records": [event("f1", "ollama", "q", 1, 1, true), event("f2", "ollama", "q", 1, 1, true)]})).await;
    assert_eq!(s, StatusCode::CREATED);
    t.ingest(json!([event("manual-1", "openai", "gpt", 5, 5, true)])).await;
    // A manual edit releases that card from the fixture.
    assert_eq!(t.service("PUT", "/projects/cortex/admin/reports/token-usage/datasets/latency-by-model", dataset("latency-by-model", "signed_in")).await.0, StatusCode::OK);
    // A fixture header without a service key is refused.
    let (s, _, _) = t.call("PUT", "/admin/projects/cortex/reports/x9", &[("x-uuid", ROOT), ("x-access-level", "1"), ("x-reports-fixture", FIX)], Some(json!({"title": {"en": "X"}}))).await;
    assert_eq!(s, StatusCode::FORBIDDEN);

    let (s, v, _) = t.call("DELETE", &format!("/admin/fixtures/{FIX}"), &[("x-reports-service-key", SERVICE_KEY)], None).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(v["datasets"], 1, "{v}");
    assert_eq!(v["records"], 2);
    assert_eq!(v["reports"], 0, "the report still has the manually edited card");
    assert_eq!(v["calculations"], 1, "the calculation of the manual card stays");
    assert_eq!(v["schemas"], 0, "a manual record still uses the schema");
    assert_eq!(v["kept"].as_array().unwrap().len(), 3, "{v}");

    // What stays: the project, the manual card, the manual record.
    assert!(reports::dal::catalog::get_project(&t.db, "cortex").await.unwrap().is_some());
    let (s, page) = t.get("/projects/cortex/reports/token-usage/datasets/latency-by-model", &[("x-uuid", ALICE)]).await;
    assert_eq!(s, StatusCode::OK, "{page}");
    assert_eq!(page["rows"], json!([{"model": "gpt", "latency": 5.0}]));
    assert_eq!(t.docs.len(), 1);
    // A second delete finds nothing to remove.
    let (_, v, _) = t.call("DELETE", &format!("/admin/fixtures/{FIX}"), &[("x-reports-service-key", SERVICE_KEY)], None).await;
    assert_eq!((v["datasets"].as_i64(), v["records"].as_i64()), (Some(0), Some(0)));
    // Only a service key may delete fixtures.
    assert_eq!(t.call("DELETE", &format!("/admin/fixtures/{FIX}"), &[("x-uuid", ROOT), ("x-access-level", "1")], None).await.0, StatusCode::FORBIDDEN);
}

/// Creates the fixture like scripts/population/populate.py: an existing published schema
/// or calculation version is reused, the report, the card and the records are written again.
async fn populate(t: &TestApp) {
    let key = [("x-reports-service-key", SERVICE_KEY)];
    let (_, schemas) = t.get("/admin/projects/cortex/schemas", &key).await;
    if !schemas.as_array().unwrap().iter().any(|s| s["schema_name"] == "telemetry_event" && s["status"] == "published") {
        assert_eq!(fx(t, "POST", "/projects/cortex/admin/schemas", telemetry_schema()).await.0, StatusCode::CREATED);
        t.service("POST", "/projects/cortex/admin/schemas/telemetry_event/versions/1/publish", json!({})).await;
    }
    let (_, calcs) = t.get("/admin/projects/cortex/calculations", &key).await;
    if !calcs.as_array().unwrap().iter().any(|c| c["calculation_id"] == "tokens-by-provider" && c["status"] == "published") {
        let (s, v) = fx(t, "POST", "/projects/cortex/admin/calculations", json!({"calculation_id": "tokens-by-provider", "definition": definition("tokens-by-provider")})).await;
        assert_eq!(s, StatusCode::CREATED, "{v}");
        t.service("POST", "/projects/cortex/admin/calculations/tokens-by-provider/versions/1/publish", json!({})).await;
    }
    fx(t, "PUT", "/projects/cortex/admin/reports/token-usage", json!({"title": {"en": "Token Usage"}, "visibility": "public"})).await;
    assert_eq!(fx(t, "PUT", "/projects/cortex/admin/reports/token-usage/datasets/tokens-by-provider", dataset("tokens-by-provider", "public")).await.0, StatusCode::OK);
    let (s, v) = fx(t, "POST", "/projects/cortex/admin/ingest/telemetry_event", json!({"schema_version": 1, "records": [event("f1", "ollama", "q", 3, 1, true), event("f2", "ollama", "q", 4, 1, true)]})).await;
    assert!(s == StatusCode::CREATED || s == StatusCode::OK, "{s} {v}");
}

#[tokio::test]
async fn fixture_lifecycle_populate_twice_restart_and_scoped_delete() {
    let t = TestApp::new().await;
    t.service("PUT", "/projects/cortex/admin/project", json!({"name": {"en": "Cortex"}})).await;
    populate(&t).await;
    t.ingest(json!([event("manual-1", "openai", "gpt", 5, 5, true)])).await;
    let url = "/projects/cortex/reports/token-usage/datasets/tokens-by-provider";
    let (_, before) = t.get(url, &[]).await;

    // A second populate changes nothing: the same records, the same answer.
    populate(&t).await;
    assert_eq!(t.docs.len(), 3, "two fixture records and one manual record");
    let (_, again) = t.get(url, &[]).await;
    assert_eq!(again["rows"], before["rows"]);

    // Everything survives a restart.
    let t = t.restart().await;
    let (s, after) = t.get(url, &[]).await;
    assert_eq!(s, StatusCode::OK, "{after}");
    assert_eq!(after["rows"], before["rows"]);

    // The scoped delete removes the fixture and keeps the manual record and the schema.
    let (s, v, _) = t.call("DELETE", &format!("/admin/fixtures/{FIX}"), &[("x-reports-service-key", SERVICE_KEY)], None).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(v["records"], 2, "{v}");
    assert_eq!(v["calculations"], 1, "one calculation version: {v}");
    assert_eq!(v["schemas"], 0, "the manual record still uses the schema: {v}");
    assert_eq!(t.docs.len(), 1);
    assert_eq!(t.get(url, &[]).await.0, StatusCode::NOT_FOUND, "the fixture report is gone");
    assert!(reports::dal::catalog::get_project(&t.db, "cortex").await.unwrap().is_some());
}
