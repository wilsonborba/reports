//! Versioned calculations, common operators and representative report metrics for the five
//! launch projects. Every metric runs from a published definition; no project-specific code.

mod common;

use axum::http::StatusCode;
use common::*;
use serde_json::{json, Value};

async fn project(t: &TestApp, slug: &str) {
    let (s, v) = t.service("PUT", &format!("/projects/{slug}/admin/project"), json!({"name": {"en": slug}})).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let (s, v) = t.service("PUT", &format!("/projects/{slug}/admin/reports/overview"), json!({"title": {"en": "Overview"}, "visibility": "public"})).await;
    assert_eq!(s, StatusCode::OK, "{v}");
}

async fn schema(t: &TestApp, slug: &str, name: &str, fields: Value) {
    let (s, v) = t.service("POST", &format!("/projects/{slug}/admin/schemas"), json!({"schema_name": name, "fields": fields})).await;
    assert_eq!(s, StatusCode::CREATED, "{v}");
    let version = v["version"].as_i64().unwrap();
    let (s, v) = t.service("POST", &format!("/projects/{slug}/admin/schemas/{name}/versions/{version}/publish"), json!({})).await;
    assert_eq!(s, StatusCode::OK, "{v}");
}

async fn ingest(t: &TestApp, slug: &str, name: &str, payloads: Vec<Value>) {
    let records: Vec<Value> = payloads.into_iter().enumerate().map(|(i, p)| json!({"idempotency_key": format!("{name}-{i}"), "payload": p})).collect();
    let (s, v) = t.service("POST", &format!("/projects/{slug}/admin/ingest/{name}"), json!({"schema_version": 1, "records": records})).await;
    assert_eq!(s, StatusCode::CREATED, "{v}");
}

/// Publishes a calculation, binds it as a public card and returns its rows.
async fn metric(t: &TestApp, slug: &str, id: &str, definition: Value) -> Vec<Value> {
    t.publish_calculation(slug, id, definition).await;
    let (s, v) = t.service("PUT", &format!("/projects/{slug}/admin/reports/overview/datasets/{id}"), json!({"visibility": "public", "calculation_id": id, "calculation_version": 1})).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let (s, v) = t.get(&format!("/projects/{slug}/showcase/overview/cards/{id}"), &[]).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    v["rows"].as_array().unwrap().clone()
}

fn f(name: &str, t: &str) -> Value {
    json!({"name": name, "label": {"en": name}, "type": t})
}

#[tokio::test]
async fn representative_metrics_of_the_five_projects_run_from_definitions() {
    let t = TestApp::new().await;
    let mut passed = Vec::new();

    // cortex: TelemetryEvent (cortex_api/lib/dal/models.py)
    project(&t, "cortex").await;
    schema(&t, "cortex", "telemetry_event", json!([
        {"path": "request_id", "type": "string", "required": true}, {"path": "provider", "type": "string", "required": true},
        {"path": "model", "type": "string", "required": true}, {"path": "total_tokens", "type": "integer", "required": true},
        {"path": "latency_ms", "type": "integer", "required": true}, {"path": "success", "type": "boolean", "required": true},
        {"path": "started_at", "type": "datetime", "required": true}
    ])).await;
    let ev = |id: &str, tokens: i64, latency: i64, ok: bool, at: &str| json!({"request_id": id, "provider": "ollama", "model": "qwen2.5:7b", "total_tokens": tokens, "latency_ms": latency, "success": ok, "started_at": at});
    ingest(&t, "cortex", "telemetry_event", vec![
        ev("r1", 100, 1000, true, "2026-10-20T09:00:00+07:00"), ev("r2", 300, 3000, false, "2026-10-20T23:30:00+07:00"),
        ev("r3", 200, 2000, true, "2026-10-21T10:00:00+07:00"), ev("r4", 400, 4000, true, "2026-10-22T08:00:00+07:00"),
    ]).await;
    let rows = metric(&t, "cortex", "daily-usage", json!({
        "title": {"en": "Daily usage"}, "source": "telemetry_event",
        "buckets": [{"field": "started_at", "unit": "day", "name": "day"}],
        "stages": [{"group_by": ["day"], "measures": [
            {"name": "requests", "agg": "count"},
            {"name": "ok", "agg": "count", "where": [{"field": "success", "op": "eq", "value": true}]},
            {"name": "tokens", "agg": "sum", "field": "total_tokens"},
            {"name": "latency", "agg": "avg", "field": "latency_ms"}],
            "derived": [{"name": "success_rate", "expr": "ok / requests * 100"}],
            "windows": [{"name": "latency_2d", "agg": "avg", "field": "latency", "size": 2, "order_by": "day"}]}],
        "sort": [{"field": "day"}],
        "fields": [f("day", "date"), f("tokens", "integer"), f("success_rate", "percent"), f("latency_2d", "float")]
    })).await;
    assert_eq!(rows, vec![
        json!({"day": "2026-10-20", "tokens": 400.0, "success_rate": 50.0, "latency_2d": 2000.0}),
        json!({"day": "2026-10-21", "tokens": 200.0, "success_rate": 100.0, "latency_2d": 2000.0}),
        json!({"day": "2026-10-22", "tokens": 400.0, "success_rate": 100.0, "latency_2d": 3000.0}),
    ]);
    passed.push("cortex: tokens, success rate and 2-day latency per day");

    // autodroid: Job (autodroid/lib/domain/models/job_model.py)
    project(&t, "autodroid").await;
    schema(&t, "autodroid", "job", json!([
        {"path": "job_type", "type": "string", "required": true}, {"path": "adapter_name", "type": "string", "required": true},
        {"path": "status", "type": "string", "required": true}, {"path": "attempt_count", "type": "integer", "required": true},
        {"path": "max_attempts", "type": "integer", "required": true}, {"path": "error_message", "type": "string"},
        {"path": "created_at", "type": "datetime", "required": true}
    ])).await;
    let job = |adapter: &str, status: &str, attempts: i64| json!({"job_type": "instagram.post", "adapter_name": adapter, "status": status, "attempt_count": attempts, "max_attempts": 3, "error_message": if status == "failed" { json!("timeout") } else { Value::Null }, "created_at": "2026-10-21T08:00:00Z"});
    ingest(&t, "autodroid", "job", vec![job("aiograpi", "done", 1), job("aiograpi", "failed", 3), job("aiograpi", "done", 2), job("adb_mapper", "done", 1)]).await;
    let rows = metric(&t, "autodroid", "failure-by-adapter", json!({
        "title": {"en": "Failure rate"}, "source": "job",
        "stages": [{"group_by": ["adapter_name"], "measures": [
            {"name": "jobs", "agg": "count"},
            {"name": "failed", "agg": "count", "where": [{"field": "status", "op": "eq", "value": "failed"}]},
            {"name": "attempts", "agg": "avg", "field": "attempt_count"}],
            "derived": [{"name": "failure_rate", "expr": "failed / jobs * 100"}]}],
        "sort": [{"field": "adapter_name"}],
        "fields": [f("adapter_name", "string"), f("failure_rate", "percent"), f("attempts", "float")]
    })).await;
    assert_eq!(rows[1]["adapter_name"], "aiograpi");
    assert!((rows[1]["failure_rate"].as_f64().unwrap() - 100.0 / 3.0).abs() < 1e-9);
    assert_eq!(rows[1]["attempts"], json!(2.0));
    assert_eq!(rows[0], json!({"adapter_name": "adb_mapper", "failure_rate": 0.0, "attempts": 1.0}));
    passed.push("autodroid: failure rate and mean attempts per adapter");

    // fsm: MediaItem (fsm/src/domain/models/media_models.py)
    project(&t, "fsm").await;
    schema(&t, "fsm", "media_item", json!([
        {"path": "key", "type": "string", "required": true}, {"path": "app", "type": "string", "required": true},
        {"path": "album", "type": "string", "required": true}, {"path": "content_type", "type": "string", "required": true},
        {"path": "size_bytes", "type": "integer", "required": true}, {"path": "created_at", "type": "datetime", "required": true}
    ])).await;
    let item = |key: &str, app: &str, album: &str, size: i64| json!({"key": key, "app": app, "album": album, "content_type": "image/png", "size_bytes": size, "created_at": "2026-10-10T12:00:00Z"});
    ingest(&t, "fsm", "media_item", vec![item("a", "domain_api", "covers", 1000), item("b", "domain_api", "covers", 3000), item("c", "domain_api", "files", 500), item("d", "plane", "uploads", 200)]).await;
    let rows = metric(&t, "fsm", "storage-by-app", json!({
        "title": {"en": "Storage"}, "source": "media_item",
        "stages": [{"group_by": ["app"], "measures": [
            {"name": "bytes", "agg": "sum", "field": "size_bytes"},
            {"name": "albums", "agg": "count_distinct", "field": "album"},
            {"name": "largest", "agg": "max", "field": "size_bytes"}]}],
        "sort": [{"field": "bytes", "desc": true}],
        "fields": [f("app", "string"), f("bytes", "integer"), f("albums", "integer"), f("largest", "integer")]
    })).await;
    assert_eq!(rows[0], json!({"app": "domain_api", "bytes": 4500.0, "albums": 2, "largest": 3000.0}));
    passed.push("fsm: bytes, albums and largest file per app");

    // certifications: UserCertificationModel (certifications_api/src/domain/models/user_certification.py)
    project(&t, "certifications").await;
    schema(&t, "certifications", "user_certification", json!([
        {"path": "certification_title", "type": "string", "required": true}, {"path": "language", "type": "string", "required": true},
        {"path": "score", "type": "float", "required": true}, {"path": "total_questions", "type": "integer", "required": true},
        {"path": "correct_questions", "type": "integer", "required": true}, {"path": "created_at", "type": "datetime", "required": true}
    ])).await;
    let attempt = |score: f64, correct: i64| json!({"certification_title": "AWS Cloud Practitioner", "language": "pt-BR", "score": score, "total_questions": 10, "correct_questions": correct, "created_at": "2026-10-01T10:00:00Z"});
    ingest(&t, "certifications", "user_certification", vec![attempt(90.0, 9), attempt(60.0, 6), attempt(70.0, 7), attempt(80.0, 8)]).await;
    let rows = metric(&t, "certifications", "pass-rate", json!({
        "title": {"en": "Pass rate"}, "source": "user_certification",
        "stages": [{"group_by": ["certification_title"], "measures": [
            {"name": "attempts", "agg": "count"},
            {"name": "passed", "agg": "count", "where": [{"field": "score", "op": "gte", "value": 70}]},
            {"name": "correct", "agg": "sum", "field": "correct_questions"},
            {"name": "questions", "agg": "sum", "field": "total_questions"}],
            "derived": [{"name": "pass_rate", "expr": "passed / attempts * 100"}, {"name": "accuracy", "expr": "correct / questions * 100"}]}],
        "fields": [f("certification_title", "string"), f("pass_rate", "percent"), f("accuracy", "percent")]
    })).await;
    assert_eq!(rows, vec![json!({"certification_title": "AWS Cloud Practitioner", "pass_rate": 75.0, "accuracy": 75.0})]);
    passed.push("certifications: pass rate and accuracy per certification");

    // domain: domain_api projects (status and creation time)
    project(&t, "domain").await;
    schema(&t, "domain", "catalog_project", json!([
        {"path": "slug", "type": "string", "required": true}, {"path": "status", "type": "string", "required": true},
        {"path": "created_at", "type": "datetime", "required": true}
    ])).await;
    let p = |slug: &str, status: &str, at: &str| json!({"slug": slug, "status": status, "created_at": at});
    ingest(&t, "domain", "catalog_project", vec![p("cortex", "on development", "2026-09-14T23:01:12+07:00"), p("fsm", "released", "2026-09-20T10:00:00+07:00"), p("hippocampus", "released", "2026-10-02T10:00:00+07:00")]).await;
    let rows = metric(&t, "domain", "projects-per-month", json!({
        "title": {"en": "New projects"}, "source": "catalog_project",
        "buckets": [{"field": "created_at", "unit": "month", "name": "month"}],
        "stages": [{"group_by": ["month"], "measures": [{"name": "projects", "agg": "count"},
            {"name": "released", "agg": "count", "where": [{"field": "status", "op": "eq", "value": "released"}]}]}],
        "sort": [{"field": "month"}],
        "fields": [f("month", "string"), f("projects", "integer"), f("released", "integer")]
    })).await;
    assert_eq!(rows, vec![json!({"month": "2026-09", "projects": 2, "released": 1}), json!({"month": "2026-10", "projects": 1, "released": 1})]);
    passed.push("domain: new and released projects per month");

    // Coverage measured: every representative metric ran from a definition.
    assert_eq!(passed.len(), 5, "{passed:?}");
}

#[tokio::test]
async fn calculation_versions_are_immutable_validated_and_traceable() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.ingest(json!([event("a", "ollama", "qwen", 100, 10, true)])).await;

    // Publish refuses an invalid binding and reports every violation.
    let mut bad = definition("tokens-by-provider");
    bad["stages"][0]["measures"][0]["field"] = json!("provider");
    bad["stages"][0]["group_by"] = json!(["vendor"]);
    let (s, v) = t.service("POST", "/projects/cortex/admin/calculations", json!({"calculation_id": "bad-calc", "definition": bad})).await;
    assert_eq!(s, StatusCode::CREATED, "{v}");
    let (_, dry) = t.service("POST", "/projects/cortex/admin/calculations/bad-calc/versions/1/validate", json!({})).await;
    assert!(dry.as_array().unwrap().len() >= 2, "{dry}");
    let (s, v) = t.service("POST", "/projects/cortex/admin/calculations/bad-calc/versions/1/publish", json!({})).await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY, "{v}");

    // A published version cannot change; the next version is new.
    let (s, _) = t.service("POST", "/projects/cortex/admin/calculations", json!({"calculation_id": "tokens-by-provider", "version": 1, "definition": definition("tokens-by-provider")})).await;
    assert_eq!(s, StatusCode::CONFLICT);
    let mut v2 = definition("tokens-by-provider");
    v2["stages"][0]["measures"][0]["agg"] = json!("max");
    assert_eq!(t.publish_calculation("cortex", "tokens-by-provider", v2).await, 2);

    // Results carry their lineage; the card still shows v1 until it is rebound.
    let url = "/projects/cortex/reports/token-usage/datasets/tokens-by-provider";
    let (_, page) = t.get(url, &[]).await;
    assert_eq!(page["lineage"]["calculation_version"], 1);
    assert_eq!(page["lineage"]["inputs"], json!([{"schema": "telemetry_event", "version": 1}]));
    assert_eq!(page["lineage"]["source_watermark"]["telemetry_event"]["records"], 1);
    let calculations = t.state.datasets.counters().calculations;
    let mut bind = dataset("tokens-by-provider", "public");
    bind["calculation_version"] = json!(2);
    t.service("PUT", "/projects/cortex/admin/reports/token-usage/datasets/tokens-by-provider", bind).await;
    let (_, page) = t.get(url, &[]).await;
    assert_eq!(page["lineage"]["calculation_version"], 2);
    assert_eq!(t.state.datasets.counters().calculations, calculations + 1, "a new version has its own cache entry");

    // A newer schema version marks dependent drafts for review.
    t.service("POST", "/projects/cortex/admin/calculations", json!({"calculation_id": "draft-calc", "definition": definition("latency-by-model")})).await;
    t.service("POST", "/projects/cortex/admin/schemas", telemetry_schema()).await;
    t.service("POST", "/projects/cortex/admin/schemas/telemetry_event/versions/2/publish", json!({})).await;
    let (_, all) = t.get("/admin/projects/cortex/calculations", &[("x-reports-service-key", SERVICE_KEY)]).await;
    let draft = all.as_array().unwrap().iter().find(|c| c["calculation_id"] == "draft-calc").unwrap();
    assert_eq!(draft["needs_review"], true);
    let published = all.as_array().unwrap().iter().find(|c| c["calculation_id"] == "tokens-by-provider" && c["version"] == 1).unwrap();
    assert_eq!(published["needs_review"], false, "published versions keep their inputs");

    // A draft cannot be bound to a card.
    let mut bind = dataset("draft-calc", "public");
    bind["calculation_id"] = json!("draft-calc");
    assert_eq!(t.service("PUT", "/projects/cortex/admin/reports/token-usage/datasets/draft-card", bind).await.0, StatusCode::CONFLICT);
}

#[tokio::test]
async fn snapshots_keep_rows_and_lineage() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.ingest(json!([event("a", "ollama", "qwen", 100, 10, true)])).await;
    let (s, v) = t.service("POST", "/projects/cortex/admin/reports/token-usage/datasets/tokens-by-provider/snapshots", json!({})).await;
    assert_eq!(s, StatusCode::CREATED, "{v}");
    t.ingest(json!([event("b", "ollama", "qwen", 50, 10, true)])).await;
    let (_, list) = t.get("/admin/projects/cortex/reports/token-usage/datasets/tokens-by-provider/snapshots", &[("x-reports-service-key", SERVICE_KEY)]).await;
    let snap = &list[0];
    assert_eq!(snap["rows"], json!([{"provider": "ollama", "tokens": 100.0}]), "the snapshot keeps the old result");
    assert_eq!(snap["lineage"]["calculation_version"], 1);
}

#[tokio::test]
async fn warm_public_kpis_after_ingestion_only() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    let mut warm = definition("tokens-by-provider");
    warm["warm"] = json!(true);
    t.publish_calculation("cortex", "tokens-by-provider", warm).await;
    let mut bind = dataset("tokens-by-provider", "public");
    bind["calculation_version"] = json!(2);
    t.service("PUT", "/projects/cortex/admin/reports/token-usage/datasets/tokens-by-provider", bind).await;
    let before = t.state.datasets.counters().calculations;
    t.ingest(json!([event("a", "ollama", "qwen", 100, 10, true)])).await;
    for _ in 0..50 {
        if t.state.datasets.counters().calculations > before {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;
    }
    assert_eq!(t.state.datasets.counters().calculations, before + 1, "only the warm public KPI is calculated");
    let hits = t.state.datasets.counters().hits;
    t.get("/projects/cortex/showcase/token-usage/cards/tokens-by-provider", &[]).await;
    assert!(t.state.datasets.counters().hits > hits, "the first guest read is a cache hit");
}
