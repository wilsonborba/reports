//! Current aggregate snapshots use the real versioned ingest and calculation paths.
mod common;

use axum::http::StatusCode;
use common::*;
use serde_json::{json, Value};

const PROJECT: &str = "domain";
const SCHEMA: &str = "aggregate_snapshot";

fn f(name: &str, field_type: &str) -> Value {
    json!({"name": name, "label": {"en": name}, "type": field_type})
}

fn measured_field(name: &str, field_type: &str, unit: &str) -> Value {
    json!({
        "name": name,
        "label": {"en": name},
        "type": field_type,
        "unit": unit,
        "role": "measure"
    })
}

async fn setup(t: &TestApp) {
    let (status, body) = t
        .service(
            "PUT",
            &format!("/projects/{PROJECT}/admin/project"),
            json!({"name": {"en": "Domain"}}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (status, body) = t
        .service(
            "PUT",
            &format!("/projects/{PROJECT}/admin/reports/overview"),
            json!({"title": {"en": "Overview"}, "visibility": "public"}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (status, body) = t
        .service(
            "POST",
            &format!("/projects/{PROJECT}/admin/schemas"),
            json!({
                "schema_name": SCHEMA,
                "fields": [
                    {"path": "snapshot_id", "type": "string", "required": true},
                    {"path": "snapshot_order", "type": "integer", "required": true},
                    {"path": "snapshot_complete", "type": "boolean", "required": true},
                    {"path": "availability", "type": "string", "required": true},
                    {"path": "metric", "type": "string", "required": true},
                    {"path": "group_key", "type": "string", "required": true},
                    {"path": "key", "type": "string", "required": true},
                    {"path": "value", "type": "integer", "required": true},
                    {"path": "denominator", "type": "integer"}
                ]
            }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let (status, body) = t
        .service(
            "POST",
            &format!("/projects/{PROJECT}/admin/schemas/{SCHEMA}/versions/1/publish"),
            json!({}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
}

fn marker(snapshot_id: &str, order: i64) -> Value {
    json!({
        "snapshot_id": snapshot_id,
        "snapshot_order": order,
        "snapshot_complete": true,
        "availability": "complete",
        "metric": "snapshot",
        "group_key": "",
        "key": "",
        "value": 0
    })
}

fn row(
    snapshot_id: &str,
    order: i64,
    metric: &str,
    group_key: &str,
    key: &str,
    value: i64,
    denominator: Option<i64>,
) -> Value {
    json!({
        "snapshot_id": snapshot_id,
        "snapshot_order": order,
        "snapshot_complete": false,
        "availability": "available",
        "metric": metric,
        "group_key": group_key,
        "key": key,
        "value": value,
        "denominator": denominator
    })
}

async fn ingest_payloads(t: &TestApp, payloads: Vec<Value>) -> Value {
    let records: Vec<Value> = payloads
        .into_iter()
        .map(|payload| {
            let snapshot_id = payload["snapshot_id"].as_str().unwrap();
            let idempotency_key = if payload["snapshot_complete"] == json!(true) {
                format!("v1:{snapshot_id}:complete")
            } else {
                use sha2::{Digest, Sha256};
                let natural_key = format!(
                    "{}\u{1f}{}\u{1f}{}",
                    payload["metric"], payload["group_key"], payload["key"]
                );
                let digest = Sha256::digest(natural_key.as_bytes());
                format!("v1:{snapshot_id}:{}", hex::encode(digest))
            };
            json!({
                "idempotency_key": idempotency_key,
                "event_time": "2026-11-24T00:00:00Z",
                "payload": payload
            })
        })
        .collect();
    let (status, body) = t
        .service(
            "POST",
            &format!("/projects/{PROJECT}/admin/ingest/{SCHEMA}"),
            json!({"schema_version": 1, "records": records}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    body
}

async fn ingest_snapshot(
    t: &TestApp,
    snapshot_id: &str,
    order: i64,
    payloads: Vec<Value>,
) -> Value {
    let data = if payloads.is_empty() {
        json!({"created": 0, "duplicates": 0})
    } else {
        ingest_payloads(t, payloads).await
    };
    let marker = ingest_payloads(t, vec![marker(snapshot_id, order)]).await;
    json!({
        "created": data["created"].as_u64().unwrap_or(0) + marker["created"].as_u64().unwrap_or(0),
        "duplicates": data["duplicates"].as_u64().unwrap_or(0) + marker["duplicates"].as_u64().unwrap_or(0)
    })
}

async fn publish_metric(t: &TestApp, id: &str, metric: &str, output: Value) -> Vec<Value> {
    let mut definition = json!({
        "title": {"en": id},
        "source": SCHEMA,
        "latest_snapshot": {
            "order_field": "snapshot_order",
            "complete_field": "snapshot_complete",
            "id_field": "snapshot_id"
        },
        "where": [
            {"field": "metric", "op": "eq", "value": metric},
            {"field": "snapshot_complete", "op": "eq", "value": false}
        ],
        "fields": output
    });
    if metric == "project_language_bytes" {
        definition["where"].as_array_mut().unwrap().push(json!({
            "field": "denominator", "op": "gt", "value": 0
        }));
        definition["stages"] = json!([{
            "group_by": ["group_key", "key"],
            "measures": [
                {"name": "bytes", "agg": "sum", "field": "value"},
                {"name": "total_bytes", "agg": "max", "field": "denominator"}
            ],
            "derived": [{"name": "percentage", "expr": "bytes / total_bytes * 100"}]
        }]);
    } else {
        definition["stages"] = json!([{
            "group_by": ["key"],
            "measures": [{"name": "count", "agg": "sum", "field": "value"}]
        }]);
    }
    t.publish_calculation(PROJECT, id, definition).await;
    let (status, body) = t
        .service(
            "PUT",
            &format!("/projects/{PROJECT}/admin/reports/overview/datasets/{id}"),
            json!({"visibility": "public", "calculation_id": id, "calculation_version": 1}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (status, body) = t
        .get(
            &format!("/projects/{PROJECT}/showcase/overview/cards/{id}"),
            &[],
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body["rows"].as_array().unwrap().clone()
}

async fn publish_language_states(t: &TestApp) -> Vec<Value> {
    t.publish_calculation(
        PROJECT,
        "project-language-state",
        json!({
            "title": {"en": "Project language source state"},
            "source": SCHEMA,
            "latest_snapshot": {
                "order_field": "snapshot_order",
                "complete_field": "snapshot_complete",
                "id_field": "snapshot_id"
            },
            "where": [
                {"field": "metric", "op": "eq", "value": "project_language_bytes"},
                {"field": "key", "op": "eq", "value": ""},
                {"field": "snapshot_complete", "op": "eq", "value": false}
            ],
            "fields": [f("group_key", "string"), f("availability", "string"), f("denominator", "integer")]
        }),
    )
    .await;
    let (status, body) = t
        .service(
            "PUT",
            &format!("/projects/{PROJECT}/admin/reports/overview/datasets/project-language-state"),
            json!({"visibility": "public", "calculation_id": "project-language-state", "calculation_version": 1}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (status, body) = t
        .get(
            "/projects/domain/showcase/overview/cards/project-language-state",
            &[],
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body["rows"].as_array().unwrap().clone()
}

#[tokio::test]
async fn latest_complete_snapshot_handles_retries_reordering_reversion_empty_and_zero() {
    let t = TestApp::new().await;
    setup(&t).await;

    let a = vec![row("a", 10, "projects_by_status", "", "idea", 2, None)];
    ingest_snapshot(&t, "a", 10, a.clone()).await;
    let retry = ingest_snapshot(&t, "a", 10, a).await;
    assert_eq!(retry["created"], json!(0));
    assert!(retry["duplicates"].as_u64().unwrap() >= 2);

    ingest_snapshot(
        &t,
        "b",
        20,
        vec![row("b", 20, "projects_by_status", "", "released", 3, None)],
    )
    .await;
    ingest_snapshot(
        &t,
        "c",
        30,
        vec![row("c", 30, "projects_by_status", "", "idea", 2, None)],
    )
    .await;
    let old_retry = ingest_snapshot(
        &t,
        "b",
        20,
        vec![row("b", 20, "projects_by_status", "", "released", 3, None)],
    )
    .await;
    assert_eq!(old_retry["created"], json!(0));

    let rows = publish_metric(
        &t,
        "projects-by-status",
        "projects_by_status",
        json!([f("key", "string"), f("count", "integer")]),
    )
    .await;
    assert_eq!(rows, vec![json!({"key": "idea", "count": 2.0})]);

    ingest_payloads(
        &t,
        vec![row(
            "partial",
            35,
            "projects_by_status",
            "",
            "released",
            99,
            None,
        )],
    )
    .await;
    let rows = publish_metric(
        &t,
        "projects-by-status",
        "projects_by_status",
        json!([f("key", "string"), f("count", "integer")]),
    )
    .await;
    assert_eq!(rows, vec![json!({"key": "idea", "count": 2.0})]);

    ingest_snapshot(&t, "empty", 40, vec![]).await;
    assert!(publish_metric(
        &t,
        "projects-by-status",
        "projects_by_status",
        json!([f("key", "string"), f("count", "integer")]),
    )
    .await
    .is_empty());

    // Equal order values resolve to one deterministic snapshot id, never a union.
    ingest_snapshot(
        &t,
        "tie-a",
        45,
        vec![row("tie-a", 45, "projects_by_status", "", "idea", 7, None)],
    )
    .await;
    ingest_snapshot(
        &t,
        "tie-z",
        45,
        vec![row(
            "tie-z",
            45,
            "projects_by_status",
            "",
            "released",
            8,
            None,
        )],
    )
    .await;
    let rows = publish_metric(
        &t,
        "projects-by-status",
        "projects_by_status",
        json!([f("key", "string"), f("count", "integer")]),
    )
    .await;
    assert_eq!(rows, vec![json!({"key": "released", "count": 8.0})]);

    ingest_snapshot(
        &t,
        "zero",
        50,
        vec![row(
            "zero",
            50,
            "projects_by_status",
            "",
            "released",
            0,
            None,
        )],
    )
    .await;
    let rows = publish_metric(
        &t,
        "projects-by-status",
        "projects_by_status",
        json!([f("key", "string"), f("count", "integer")]),
    )
    .await;
    assert_eq!(rows, vec![json!({"key": "released", "count": 0.0})]);
}

#[tokio::test]
async fn latest_project_language_bytes_keep_the_denominator_and_compute_percentages() {
    let t = TestApp::new().await;
    setup(&t).await;
    ingest_snapshot(
        &t,
        "languages",
        100,
        vec![
            row(
                "languages",
                100,
                "project_language_bytes",
                "repo-a",
                "Python",
                3000,
                Some(4000),
            ),
            row(
                "languages",
                100,
                "project_language_bytes",
                "repo-a",
                "Rust",
                1000,
                Some(4000),
            ),
            row(
                "languages",
                100,
                "project_language_bytes",
                "repo-b",
                "Kotlin",
                500,
                Some(1000),
            ),
            row(
                "languages",
                100,
                "project_language_bytes",
                "repo-c",
                "Unknown",
                0,
                Some(0),
            ),
            {
                let mut state = row(
                    "languages",
                    100,
                    "project_language_bytes",
                    "repo-d",
                    "",
                    0,
                    Some(0),
                );
                state["availability"] = json!("empty");
                state
            },
            {
                let mut state = row(
                    "languages",
                    100,
                    "project_language_bytes",
                    "repo-e",
                    "",
                    0,
                    None,
                );
                state["availability"] = json!("unavailable");
                state
            },
        ],
    )
    .await;
    let rows = publish_metric(
        &t,
        "project-language-bytes",
        "project_language_bytes",
        json!([
            {"name": "group_key", "label": {"en": "Project"}, "type": "string", "role": "dimension"},
            {"name": "key", "label": {"en": "Language"}, "type": "string", "role": "dimension"},
            measured_field("bytes", "integer", "bytes"),
            measured_field("total_bytes", "integer", "bytes"),
            measured_field("percentage", "percent", "percent")
        ]),
    )
    .await;
    assert_eq!(rows.len(), 3);
    assert_eq!(
        rows[0],
        json!({"group_key": "repo-a", "key": "Python", "bytes": 3000.0, "total_bytes": 4000.0, "percentage": 75.0})
    );
    assert_eq!(
        rows[1],
        json!({"group_key": "repo-a", "key": "Rust", "bytes": 1000.0, "total_bytes": 4000.0, "percentage": 25.0})
    );
    assert_eq!(
        rows[2],
        json!({"group_key": "repo-b", "key": "Kotlin", "bytes": 500.0, "total_bytes": 1000.0, "percentage": 50.0})
    );
    let (status, detail) = t
        .get(
            &format!("/projects/{PROJECT}/showcase/overview/cards/project-language-bytes"),
            &[],
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{detail}");
    let (status, meta) = t
        .service(
            "PUT",
            &format!(
                "/projects/{PROJECT}/admin/reports/overview/datasets/project-language-bytes/meta"
            ),
            json!({
                "source": "GitHub language byte rows",
                "timezone": "UTC",
                "freshness_mode": "live",
                "expected_refresh_minutes": 60,
                "field_semantics": [{
                    "field_name": "percentage",
                    "denominator_field": "total_bytes",
                    "denominator_text": "total language bytes",
                    "missing_means": "no_data"
                }]
            }),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{meta}");
    let (status, detail) = t
        .get(
            &format!("/projects/{PROJECT}/showcase/overview/cards/project-language-bytes"),
            &[],
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(detail["fields"][4]["unit"], json!("percent"));
    assert_eq!(
        detail["fields"][4]["denominator_field"],
        json!("total_bytes")
    );
    let states = publish_language_states(&t).await;
    assert_eq!(states.len(), 2);
    assert!(states
        .iter()
        .any(|row| row["group_key"] == "repo-d" && row["availability"] == "empty"));
    assert!(states
        .iter()
        .any(|row| row["group_key"] == "repo-e" && row["availability"] == "unavailable"));
}

#[tokio::test]
async fn latest_snapshot_selector_rejects_mistyped_source_fields() {
    let t = TestApp::new().await;
    setup(&t).await;
    let (status, body) = t
        .service(
            "POST",
            &format!("/projects/{PROJECT}/admin/calculations"),
            json!({
                "calculation_id": "invalid-snapshot-selector",
                "definition": {
                    "title": {"en": "Invalid selector"},
                    "source": SCHEMA,
                    "latest_snapshot": {
                        "order_field": "metric",
                        "complete_field": "snapshot_complete",
                        "id_field": "snapshot_id"
                    },
                    "fields": [f("key", "string")]
                }
            }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let (status, body) = t
        .service(
            "POST",
            &format!("/projects/{PROJECT}/admin/calculations/invalid-snapshot-selector/versions/1/publish"),
            json!({}),
        )
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert!(body.to_string().contains("latest_snapshot.order_field"));
}

#[tokio::test]
async fn real_consumer_aggregate_catalog_definitions_and_wilson_metrics_work_end_to_end() {
    let out = std::process::Command::new("python3")
        .args(["../scripts/catalog/aggregates.py", "--dump-json"])
        .output()
        .expect("run aggregates.py --dump-json");
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let bundle: Value = serde_json::from_slice(&out.stdout).unwrap();

    let t = TestApp::new().await;
    let (status, _) = t
        .service(
            "PUT",
            &format!("/projects/{PROJECT}/admin/project"),
            json!({"name": {"en": "Domain"}}),
        )
        .await;
    assert_eq!(status, StatusCode::OK);

    // Publish schema from bundle.
    let schema = &bundle["schema"];
    let (status, body) = t
        .service(
            "POST",
            &format!("/projects/{PROJECT}/admin/schemas"),
            json!({
                "schema_name": schema["schema_name"],
                "fields": schema["fields"]
            }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let (status, body) = t
        .service(
            "POST",
            &format!(
                "/projects/{PROJECT}/admin/schemas/{}/versions/{}/publish",
                schema["schema_name"].as_str().unwrap(),
                schema["version"]
            ),
            json!({}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");

    // Publish technical-aggregates report & all 7 calculations/cards/meta.
    let report = &bundle["report"];
    let report_id = report["id"].as_str().unwrap();
    let (status, body) = t
        .service(
            "PUT",
            &format!("/projects/{PROJECT}/admin/reports/{report_id}"),
            json!({
                "title": report["title"],
                "visibility": report["visibility"]
            }),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");

    let datasets = bundle["datasets"].as_array().unwrap();
    assert_eq!(datasets.len(), 8);
    for (idx, ds) in datasets.iter().enumerate() {
        let id = ds["id"].as_str().unwrap();
        let (status, body) = t
            .service(
                "POST",
                &format!("/projects/{PROJECT}/admin/calculations"),
                json!({"calculation_id": id, "definition": ds["calculation"]}),
            )
            .await;
        assert_eq!(status, StatusCode::CREATED, "{body}");
        let (status, body) = t
            .service(
                "POST",
                &format!("/projects/{PROJECT}/admin/calculations/{id}/versions/1/publish"),
                json!({}),
            )
            .await;
        assert_eq!(status, StatusCode::OK, "{body}");
        let (status, body) = t
            .service(
                "PUT",
                &format!("/projects/{PROJECT}/admin/reports/{report_id}/datasets/{id}"),
                json!({
                    "visibility": "public",
                    "calculation_id": id,
                    "calculation_version": 1,
                    "visual": ds["visual"],
                    "card_order": idx + 1
                }),
            )
            .await;
        assert_eq!(status, StatusCode::OK, "{body}");
        let (status, body) = t
            .service(
                "PUT",
                &format!("/projects/{PROJECT}/admin/reports/{report_id}/datasets/{id}/meta"),
                ds["meta"].clone(),
            )
            .await;
        assert_eq!(status, StatusCode::OK, "{body}");
    }

    // Ingest real Domain + Wilson producer-shaped snapshot + stable retry.
    let payloads = vec![
        row("snap-1", 1000, "projects_by_status", "", "active", 4, None),
        row(
            "snap-1",
            1000,
            "categories_distribution",
            "",
            "Platform",
            3,
            None,
        ),
        row(
            "snap-1",
            1000,
            "languages_distribution",
            "",
            "Rust",
            2,
            None,
        ),
        row(
            "snap-1",
            1000,
            "project_language_bytes",
            "domain",
            "Python",
            6000,
            Some(10000),
        ),
        row(
            "snap-1",
            1000,
            "project_language_bytes",
            "domain",
            "Dart",
            4000,
            Some(10000),
        ),
        row("snap-1", 1000, "skill_frequency", "", "Rust", 5, None),
        row("snap-1", 1000, "issuer_counts", "", "AWS", 2, None),
        row(
            "snap-1",
            1000,
            "certification_type_counts",
            "",
            "professional",
            3,
            None,
        ),
    ];
    let first = ingest_snapshot(&t, "snap-1", 1000, payloads.clone()).await;
    assert_eq!(first["created"], 9);
    let retry = ingest_snapshot(&t, "snap-1", 1000, payloads).await;
    assert_eq!(retry["created"], 0);
    assert_eq!(retry["duplicates"], 9);

    // Verify public catalog report lists all 8 cards and Wilson/Domain measures render cleanly.
    let (status, showcase) = t
        .get(&format!("/projects/{PROJECT}/showcase/{report_id}"), &[])
        .await;
    assert_eq!(status, StatusCode::OK, "{showcase}");
    assert_eq!(showcase["cards"].as_array().unwrap().len(), 8);

    let (status, skill_card) = t
        .get(
            &format!("/projects/{PROJECT}/showcase/{report_id}/cards/skill-frequency"),
            &[],
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{skill_card}");
    assert_eq!(skill_card["rows"][0]["count"], json!(5.0));

    let (status, lang_card) = t
        .get(
            &format!("/projects/{PROJECT}/showcase/{report_id}/cards/project-language-bytes"),
            &[],
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{lang_card}");
    assert_eq!(
        lang_card["fields"][4]["denominator_field"],
        json!("total_bytes")
    );
    assert_eq!(lang_card["rows"][0]["percentage"], json!(40.0));
    assert_eq!(lang_card["rows"][1]["percentage"], json!(60.0));

    let (status, global_lang_card) = t
        .get(
            &format!("/projects/{PROJECT}/showcase/{report_id}/cards/language-bytes-share"),
            &[],
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{global_lang_card}");
}

#[tokio::test]
async fn causal_global_language_bytes_share_produces_exact_nine_and_ninety_one() {
    let t = TestApp::new().await;
    setup(&t).await;

    // Causal 2-project fixture:
    // Project A total 100: Rust 90, Python 10
    // Project B total 900: Python 900
    // Global known byte share: Rust 9%, Python 91%
    ingest_snapshot(
        &t,
        "languages",
        100,
        vec![
            row(
                "languages",
                100,
                "project_language_bytes",
                "repo-a",
                "Rust",
                90,
                Some(100),
            ),
            row(
                "languages",
                100,
                "project_language_bytes",
                "repo-a",
                "Python",
                10,
                Some(100),
            ),
            row(
                "languages",
                100,
                "project_language_bytes",
                "repo-b",
                "Python",
                900,
                Some(900),
            ),
        ],
    )
    .await;

    let definition = json!({
        "title": {"en": "Language share"},
        "source": SCHEMA,
        "latest_snapshot": {
            "order_field": "snapshot_order",
            "complete_field": "snapshot_complete",
            "id_field": "snapshot_id"
        },
        "where": [
            {"field": "metric", "op": "eq", "value": "project_language_bytes"},
            {"field": "snapshot_complete", "op": "eq", "value": false},
            {"field": "denominator", "op": "gt", "value": 0}
        ],
        "stages": [{
            "group_by": ["key"],
            "measures": [
                {"name": "bytes", "agg": "sum", "field": "value"}
            ],
            "derived": [
                {"name": "total_bytes", "expr": "sum_bytes"},
                {"name": "percentage", "expr": "bytes / sum_bytes * 100"}
            ]
        }],
        "fields": [
            {"name": "key", "label": {"en": "Language"}, "type": "string", "role": "dimension"},
            {"name": "bytes", "label": {"en": "Bytes"}, "type": "integer", "role": "measure", "unit": "bytes"},
            {"name": "total_bytes", "label": {"en": "Total known bytes"}, "type": "integer", "role": "measure", "unit": "bytes"},
            {"name": "percentage", "label": {"en": "Share (%)"}, "type": "percent", "role": "measure", "unit": "%"}
        ]
    });
    t.publish_calculation(PROJECT, "language-bytes-share", definition).await;
    let (status, body) = t
        .service(
            "PUT",
            &format!("/projects/{PROJECT}/admin/reports/overview/datasets/language-bytes-share"),
            json!({"visibility": "public", "calculation_id": "language-bytes-share", "calculation_version": 1}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (status, body) = t
        .get(
            &format!("/projects/{PROJECT}/showcase/overview/cards/language-bytes-share"),
            &[],
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let rows = body["rows"].as_array().unwrap();
    let py = rows.iter().find(|r| r["key"] == "Python").unwrap();
    let rs = rows.iter().find(|r| r["key"] == "Rust").unwrap();
    assert_eq!(py["bytes"], json!(910.0));
    assert_eq!(py["total_bytes"], json!(1000.0));
    assert_eq!(py["percentage"], json!(91.0));
    assert_eq!(rs["bytes"], json!(90.0));
    assert_eq!(rs["total_bytes"], json!(1000.0));
    assert_eq!(rs["percentage"], json!(9.0));
}
