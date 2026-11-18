mod common;

use axum::http::StatusCode;
use common::*;
use serde_json::json;

#[tokio::test]
async fn dataset_meta_and_field_semantics_validate_store_and_appear_in_api() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.ingest(json!([
        event("a", "ollama", "qwen", 100, 10, true),
        event("b", "openai", "gpt", 50, 30, false)
    ]))
    .await;

    // Invalid timezone or missing_means is rejected before storage.
    let (st, _) = t
        .service(
            "PUT",
            "/projects/cortex/admin/reports/token-usage/datasets/latency-by-model/meta",
            json!({
                "source": "Cortex telemetry",
                "timezone": "InvalidZone",
                "freshness_mode": "live",
                "expected_refresh_minutes": 15
            }),
        )
        .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);

    let (st, _) = t
        .service(
            "PUT",
            "/projects/cortex/admin/reports/token-usage/datasets/latency-by-model/meta",
            json!({
                "source": "Cortex telemetry",
                "timezone": "Asia/Bangkok",
                "freshness_mode": "live",
                "expected_refresh_minutes": 15,
                "field_semantics": [{
                    "field_name": "avg_latency_ms",
                    "missing_means": "bad_value"
                }]
            }),
        )
        .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);

    let (st, initial_page, _) = t
        .call(
            "GET",
            "/projects/cortex/reports/token-usage/datasets/latency-by-model",
            &[("x-uuid", "11111111-1111-4111-8111-111111111111")],
            None,
        )
        .await;
    assert_eq!(st, StatusCode::OK);
    let target_field = initial_page["fields"][0]["name"]
        .as_str()
        .unwrap()
        .to_string();

    // Valid metadata and field semantics persist in normalized rows.
    let (st, saved) = t
        .service(
            "PUT",
            "/projects/cortex/admin/reports/token-usage/datasets/latency-by-model/meta",
            json!({
                "source": "Cortex telemetry",
                "source_url": "https://reports.asodya.com/cortex",
                "period_start": "2026-11-01T00:00:00Z",
                "period_end": "2026-11-18T00:00:00Z",
                "timezone": "Asia/Bangkok",
                "freshness_mode": "live",
                "expected_refresh_minutes": 15,
                "field_semantics": [{
                    "field_name": target_field,
                    "denominator_field": "requests",
                    "denominator_text": "completed requests",
                    "missing_means": "no_data"
                }]
            }),
        )
        .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(saved["meta"]["source"], "Cortex telemetry");

    // Public dataset endpoint returns meta block and field semantics.
    let (st, page, _) = t
        .call(
            "GET",
            "/projects/cortex/reports/token-usage/datasets/latency-by-model",
            &[("x-uuid", "11111111-1111-4111-8111-111111111111")],
            None,
        )
        .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(page["meta"]["source"], "Cortex telemetry");
    assert_eq!(page["meta"]["timezone"], "Asia/Bangkok");
    assert_eq!(page["meta"]["freshness_mode"], "live");
    assert_eq!(page["meta"]["expected_refresh_minutes"], 15);
    let fields = page["fields"].as_array().unwrap();
    let lat = fields
        .iter()
        .find(|f| f["name"] == target_field.as_str())
        .unwrap();
    assert_eq!(lat["missing_means"], "no_data");
    assert_eq!(lat["denominator_field"], "requests");
    assert_eq!(lat["denominator_text"], "completed requests");
}
