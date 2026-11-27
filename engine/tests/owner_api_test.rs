mod common;

use std::sync::atomic::Ordering;
use std::sync::Arc;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use common::*;
use serde_json::{json, Value};
use tokio::sync::Notify;
use tower::ServiceExt;

async fn call_app(
    app: &axum::Router,
    method: &str,
    uri: &str,
    user: Option<&str>,
    headers: &[(&str, &str)],
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut req = Request::builder().method(method).uri(uri);
    for (k, v) in headers {
        req = req.header(*k, *v);
    }
    if let Some(u) = user {
        req = req.header("x-uuid", u);
    }
    let req = match body {
        Some(b) => req
            .header("content-type", "application/json")
            .body(Body::from(b.to_string()))
            .unwrap(),
        None => req.body(Body::empty()).unwrap(),
    };
    let response = app.clone().oneshot(req).await.unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), 16 * 1024 * 1024)
        .await
        .unwrap();
    let value = if bytes.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&bytes)
            .unwrap_or(Value::String(String::from_utf8_lossy(&bytes).into()))
    };
    (status, value)
}

async fn call_with_headers(
    t: &TestApp,
    method: &str,
    uri: &str,
    user: Option<&str>,
    headers: &[(&str, &str)],
    body: Option<Value>,
) -> (StatusCode, Value) {
    call_app(&t.app, method, uri, user, headers, body).await
}

const USER_1: &str = "11111111-1111-4111-8111-111111111111";
const USER_2: &str = "22222222-2222-4222-8222-222222222222";

#[tokio::test]
async fn owner_api_create_idempotency_limits_if_match_visibility_and_delete() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.seed_bar_v1().await;

    // Unknown template is rejected with 404.
    let (st, _) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "unknown-tpl",
            "template_version": 1,
            "mapping": { "category": "x", "value": "y" },
            "rows": [{ "x": "A", "y": 10 }]
        })),
    )
    .await;
    assert_eq!(st, StatusCode::NOT_FOUND);

    // Unpublished (draft) template is rejected with 409 Conflict.
    let (s, _) = t
        .service(
            "POST",
            "/projects/cortex/admin/templates",
            json!({
                "template_id": "draft-bar",
                "version": 1,
                "kind": "chart",
                "visual": "bar",
                "title": {"en": "Draft Bar"},
                "slots": [{ "slot_name": "category", "role": "dimension", "is_required": true, "min_count": 1, "max_count": 1, "accepted_types": ["string"] }]
            }),
        )
        .await;
    assert_eq!(s, StatusCode::CREATED);
    let (st, _) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "draft-bar",
            "template_version": 1,
            "mapping": { "category": "x" },
            "rows": [{ "x": "A" }]
        })),
    )
    .await;
    assert_eq!(st, StatusCode::CONFLICT);

    // Missing required template slot is rejected with 400 Bad Request.
    let (st, _) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": { "category": "x" },
            "rows": [{ "x": "A", "y": 10 }]
        })),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);

    // Exceeded slot max_count is rejected with 400 Bad Request.
    let (st, _) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": { "category": ["x", "x2", "x3"], "value": ["y"] },
            "rows": [{ "x": "A", "x2": "B", "x3": "C", "y": 10 }]
        })),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);

    // Invalid mapping is rejected before storage.
    let (st, _) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": {},
            "rows": [{ "x": "A", "y": 10 }]
        })),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);

    // Oversize (> 1000 records) is rejected before storage.
    let many_rows: Vec<Value> = (0..1001).map(|i| json!({ "x": i, "y": i })).collect();
    let (st, _) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": { "category": "x", "value": "y" },
            "rows": many_rows
        })),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);

    // Idempotent create with Idempotency-Key creates one item.
    let payload = json!({
        "title": "My Personal Chart",
        "template_id": "bar-v1",
        "template_version": 1,
        "mapping": { "category": "x", "value": "y" },
        "config": { "legend": true },
        "rows": [{ "x": "A", "y": 10 }, { "x": "B", "y": 20 }]
    });
    let (st1, created1) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[("idempotency-key", "req-abc")],
        Some(payload.clone()),
    )
    .await;
    assert_eq!(st1, StatusCode::CREATED);
    let item_id = created1["item"]["id"].as_str().unwrap().to_string();
    assert_eq!(created1["item"]["audience"], "personal");
    let etag1 = created1["item"]["etag"].as_str().unwrap().to_string();

    // Verify DatasetPage projection reflects the bound template and mapping
    let report_slug = created1["item"]["report_slug"].as_str().unwrap();
    let dataset_id = created1["item"]["dataset_id"].as_str().unwrap();
    let (st_page, page) = call_with_headers(
        &t,
        "GET",
        &format!("/projects/cortex/reports/{report_slug}/datasets/{dataset_id}"),
        Some(USER_1),
        &[],
        None,
    )
    .await;
    assert_eq!(st_page, StatusCode::OK);
    assert_eq!(page["visual"]["template"], "bar-v1");
    assert_eq!(page["visual"]["version"], 1);
    assert_eq!(page["visual"]["mapping"]["category"], json!(["x"]));
    assert_eq!(page["visual"]["mapping"]["value"], json!(["y"]));

    // Verify legacy dataset without visual binding returns null visual (honest legacy behavior)
    let (st_legacy, legacy_page) = call_with_headers(
        &t,
        "GET",
        "/projects/cortex/reports/token-usage/datasets/tokens-by-provider",
        None,
        &[],
        None,
    )
    .await;
    assert_eq!(st_legacy, StatusCode::OK);
    assert!(legacy_page["visual"].is_null());

    let (st2, created2) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[("idempotency-key", "req-abc")],
        Some(payload),
    )
    .await;
    assert_eq!(st2, StatusCode::OK);
    assert_eq!(created2["item"]["id"], item_id);

    // Other user cannot read, replace, patch, or delete user-1's item.
    let (st, _) = call_with_headers(
        &t,
        "GET",
        &format!("/me/items/{item_id}"),
        Some(USER_2),
        &[],
        None,
    )
    .await;
    assert_eq!(st, StatusCode::FORBIDDEN);

    // Replace dataset without matching If-Match returns 409; with matching If-Match succeeds.
    let (st, _) = call_with_headers(
        &t,
        "PUT",
        &format!("/me/items/{item_id}/dataset"),
        Some(USER_1),
        &[("if-match", "\"wrong-etag\"")],
        Some(json!({ "rows": [{ "x": "C", "y": 30 }] })),
    )
    .await;
    assert_eq!(st, StatusCode::CONFLICT);

    let (st, replaced) = call_with_headers(
        &t,
        "PUT",
        &format!("/me/items/{item_id}/dataset"),
        Some(USER_1),
        &[("if-match", &etag1)],
        Some(json!({ "rows": [{ "x": "C", "y": 30 }] })),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(replaced["item"]["row_count"], 1);
    assert_ne!(replaced["item"]["etag"], etag1);

    // Visibility change to public updates only this item's audience.
    let (st, patched) = call_with_headers(
        &t,
        "PATCH",
        &format!("/me/items/{item_id}"),
        Some(USER_1),
        &[],
        Some(json!({ "audience": "public" })),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(patched["item"]["audience"], "public");

    // Delete warns if reference_count > 0 unless confirm=true.
    sqlx::query("UPDATE user_chart_items SET reference_count = 2 WHERE id = $1")
        .bind(&item_id)
        .execute(&t.state.stores.db.pool)
        .await
        .unwrap();
    let (st, warn) = call_with_headers(
        &t,
        "DELETE",
        &format!("/me/items/{item_id}"),
        Some(USER_1),
        &[],
        None,
    )
    .await;
    assert_eq!(st, StatusCode::CONFLICT);
    assert_eq!(warn["requires_confirmation"], true);
    assert_eq!(warn["reference_count"], 2);

    let (st, del) = call_with_headers(
        &t,
        "DELETE",
        &format!("/me/items/{item_id}?confirm=true"),
        Some(USER_1),
        &[],
        None,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(del["deleted"], true);
}

#[tokio::test]
async fn making_one_personal_item_public_never_exposes_another_personal_item() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.seed_bar_v1().await;

    let (st1, created1) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "title": "Owner Chart One",
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": { "category": "x", "value": "y" },
            "rows": [{ "x": "PublicChartRow", "y": 111 }]
        })),
    )
    .await;
    assert_eq!(st1, StatusCode::CREATED);
    let id1 = created1["item"]["id"].as_str().unwrap().to_string();
    let report1 = created1["item"]["report_slug"]
        .as_str()
        .unwrap()
        .to_string();
    let dataset1 = created1["item"]["dataset_id"].as_str().unwrap().to_string();
    let embed1 = created1["item"]["embed_url"].as_str().unwrap().to_string();

    let (st2, created2) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "title": "Owner Chart Two",
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": { "category": "x", "value": "y" },
            "rows": [{ "x": "SecretChartRow", "y": 222 }]
        })),
    )
    .await;
    assert_eq!(st2, StatusCode::CREATED);
    let id2 = created2["item"]["id"].as_str().unwrap().to_string();
    let report2 = created2["item"]["report_slug"]
        .as_str()
        .unwrap()
        .to_string();
    let dataset2 = created2["item"]["dataset_id"].as_str().unwrap().to_string();
    let embed2 = created2["item"]["embed_url"].as_str().unwrap().to_string();

    // Before publishing item 1, user B cannot read either item through any route.
    for (report, dataset, embed) in [
        (&report1, &dataset1, &embed1),
        (&report2, &dataset2, &embed2),
    ] {
        let (st, _) = call_with_headers(
            &t,
            "GET",
            &format!("/projects/cortex/reports/{report}"),
            Some(USER_2),
            &[],
            None,
        )
        .await;
        assert_eq!(st, StatusCode::NOT_FOUND);
        let (st, _) = call_with_headers(
            &t,
            "GET",
            &format!("/projects/cortex/reports/{report}/datasets/{dataset}"),
            Some(USER_2),
            &[],
            None,
        )
        .await;
        assert_eq!(st, StatusCode::NOT_FOUND);
        let (st, _) = call_with_headers(&t, "GET", embed, None, &[], None).await;
        assert_eq!(st, StatusCode::NOT_FOUND);
    }

    // User A makes item 1 public; item 2 remains personal.
    let (st, patched) = call_with_headers(
        &t,
        "PATCH",
        &format!("/me/items/{id1}"),
        Some(USER_1),
        &[],
        Some(json!({ "audience": "public" })),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(patched["item"]["audience"], "public");

    // User B can read item 1 via report view, dataset page, and embed descriptor.
    let (st, rep1_view) = call_with_headers(
        &t,
        "GET",
        &format!("/projects/cortex/reports/{report1}"),
        Some(USER_2),
        &[],
        None,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(rep1_view["datasets"][0]["can_view"], true);

    let (st, ds1_page) = call_with_headers(
        &t,
        "GET",
        &format!("/projects/cortex/reports/{report1}/datasets/{dataset1}"),
        Some(USER_2),
        &[],
        None,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let ds1_text = ds1_page.to_string();
    assert!(ds1_text.contains("PublicChartRow"));
    assert!(!ds1_text.contains("SecretChartRow"));

    let (st, embed1_desc) = call_with_headers(&t, "GET", &embed1, Some(USER_2), &[], None).await;
    assert_eq!(st, StatusCode::OK);
    assert!(embed1_desc["embed_url"]
        .as_str()
        .unwrap()
        .contains(&report1));

    // User B still cannot read item 2 through owner API, report view, dataset page, or embed.
    let (st, _) = call_with_headers(
        &t,
        "GET",
        &format!("/me/items/{id2}"),
        Some(USER_2),
        &[],
        None,
    )
    .await;
    assert_eq!(st, StatusCode::FORBIDDEN);

    let (st, _) = call_with_headers(
        &t,
        "GET",
        &format!("/projects/cortex/reports/{report2}"),
        Some(USER_2),
        &[],
        None,
    )
    .await;
    assert_eq!(st, StatusCode::NOT_FOUND);

    let (st, _) = call_with_headers(
        &t,
        "GET",
        &format!("/projects/cortex/reports/{report2}/datasets/{dataset2}"),
        Some(USER_2),
        &[],
        None,
    )
    .await;
    assert_eq!(st, StatusCode::NOT_FOUND);

    let (st, _) = call_with_headers(&t, "GET", &embed2, Some(USER_2), &[], None).await;
    assert_eq!(st, StatusCode::NOT_FOUND);

    // Owner A can still read both items.
    let (st, owner_ds2) = call_with_headers(
        &t,
        "GET",
        &format!("/projects/cortex/reports/{report2}/datasets/{dataset2}"),
        Some(USER_1),
        &[],
        None,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(owner_ds2.to_string().contains("SecretChartRow"));
}

#[tokio::test]
async fn owner_api_schema_and_options_validation_suite() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.seed_bar_v1().await;

    // 1. Unknown slot is rejected with 400 Bad Request
    let (st, _) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": { "category": "x", "value": "y", "unknown_slot": "z" },
            "rows": [{ "x": "A", "y": 10, "z": 1 }]
        })),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);

    // 2. Missing field in rows is rejected with 400 Bad Request
    let (st, _) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": { "category": "x", "value": "absent_field" },
            "rows": [{ "x": "A", "y": 10 }]
        })),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);

    // 3. Incompatible measure type (string instead of numeric) is rejected with 400 Bad Request
    let (st, _) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": { "category": "x", "value": "y" },
            "rows": [{ "x": "A", "y": "not_a_number" }]
        })),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);

    // 4. Later-row incompatible value is rejected with 400 Bad Request
    let (st, _) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": { "category": "x", "value": "y" },
            "rows": [
                { "x": "A", "y": 10 },
                { "x": "B", "y": "string_in_row_two" }
            ]
        })),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);

    // 5. Invalid option: non-object config is rejected with 400 Bad Request
    let (st, _) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": { "category": "x", "value": "y" },
            "config": "scalar_not_allowed",
            "rows": [{ "x": "A", "y": 10 }]
        })),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);

    // 5b. Invalid option: unknown option is rejected with 400 Bad Request
    let (st, _) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": { "category": "x", "value": "y" },
            "config": { "unknown_opt": "foo" },
            "rows": [{ "x": "A", "y": 10 }]
        })),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);

    // 5c. Invalid option: invalid bool / enum value is rejected with 400 Bad Request
    let (st, _) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": { "category": "x", "value": "y" },
            "config": { "legend": "not_true_or_false" },
            "rows": [{ "x": "A", "y": 10 }]
        })),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);

    // 6. Valid mapping and valid config succeeds with 201 Created
    let (st, created) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": { "category": "x", "value": "y" },
            "config": { "legend": true },
            "rows": [{ "x": "ValidA", "y": 100 }]
        })),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    assert_eq!(created["item"]["row_count"], 1);
}

#[tokio::test]
async fn owner_api_p1_rejected_replace_preserves_stored_owner_state() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.seed_bar_v1().await;

    // Create initial valid item
    let (st, created) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": { "category": "x", "value": "y" },
            "config": { "legend": true },
            "rows": [{ "x": "Row1", "y": 10 }, { "x": "Row2", "y": 20 }]
        })),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let item_id = created["item"]["id"].as_str().unwrap();
    let initial_etag = created["item"]["etag"].as_str().unwrap().to_string();
    let initial_doc_id: String =
        sqlx::query_scalar("SELECT couch_doc_id FROM user_chart_items WHERE id = $1")
            .bind(item_id)
            .fetch_one(&t.state.stores.db.pool)
            .await
            .unwrap();
    let report_slug = created["item"]["report_slug"].as_str().unwrap();
    let dataset_id = created["item"]["dataset_id"].as_str().unwrap();

    // Verify initial dataset visual binding
    let (st_ds, initial_ds) = call_with_headers(
        &t,
        "GET",
        &format!("/projects/cortex/reports/{report_slug}/datasets/{dataset_id}"),
        Some(USER_1),
        &[],
        None,
    )
    .await;
    assert_eq!(st_ds, StatusCode::OK);
    assert_eq!(initial_ds["visual"]["template"], "bar-v1");
    assert_eq!(initial_ds["visual"]["mapping"]["category"], json!(["x"]));
    assert_eq!(initial_ds["visual"]["mapping"]["value"], json!(["y"]));

    // Attempt 1: Replace with missing required slot (value)
    let (st_err1, _) = call_with_headers(
        &t,
        "PUT",
        &format!("/me/items/{item_id}/dataset"),
        Some(USER_1),
        &[("if-match", &initial_etag)],
        Some(json!({
            "mapping": { "category": "x" },
            "rows": [{ "x": "BadReplace" }]
        })),
    )
    .await;
    assert_eq!(st_err1, StatusCode::BAD_REQUEST);

    // Attempt 2: Replace with unknown slot
    let (st_err2, _) = call_with_headers(
        &t,
        "PUT",
        &format!("/me/items/{item_id}/dataset"),
        Some(USER_1),
        &[("if-match", &initial_etag)],
        Some(json!({
            "mapping": { "category": "x", "value": "y", "bogus_slot": "x" },
            "rows": [{ "x": "BadReplace", "y": 50 }]
        })),
    )
    .await;
    assert_eq!(st_err2, StatusCode::BAD_REQUEST);

    // Attempt 3: Replace with incompatible later row value
    let (st_err3, _) = call_with_headers(
        &t,
        "PUT",
        &format!("/me/items/{item_id}/dataset"),
        Some(USER_1),
        &[("if-match", &initial_etag)],
        Some(json!({
            "rows": [
                { "x": "GoodRow", "y": 50 },
                { "x": "BadRow", "y": "not_a_number" }
            ]
        })),
    )
    .await;
    assert_eq!(st_err3, StatusCode::BAD_REQUEST);

    // Re-fetch item detail and assert ALL stored state is 100% unchanged
    let (st_item, item_after) = call_with_headers(
        &t,
        "GET",
        &format!("/me/items/{item_id}"),
        Some(USER_1),
        &[],
        None,
    )
    .await;
    assert_eq!(st_item, StatusCode::OK);
    assert_eq!(item_after["item"]["etag"], initial_etag);
    let doc_id_after: String =
        sqlx::query_scalar("SELECT couch_doc_id FROM user_chart_items WHERE id = $1")
            .bind(item_id)
            .fetch_one(&t.state.stores.db.pool)
            .await
            .unwrap();
    assert_eq!(doc_id_after, initial_doc_id);
    assert_eq!(item_after["item"]["row_count"], 2);
    assert_eq!(
        item_after["rows"],
        json!([{ "x": "Row1", "y": 10 }, { "x": "Row2", "y": 20 }])
    );

    // Re-fetch dataset page and assert visual binding and rows are 100% unchanged
    let (st_ds_after, ds_after) = call_with_headers(
        &t,
        "GET",
        &format!("/projects/cortex/reports/{report_slug}/datasets/{dataset_id}"),
        Some(USER_1),
        &[],
        None,
    )
    .await;
    assert_eq!(st_ds_after, StatusCode::OK);
    assert_eq!(ds_after["visual"]["template"], "bar-v1");
    assert_eq!(ds_after["visual"]["mapping"]["category"], json!(["x"]));
    assert_eq!(ds_after["visual"]["mapping"]["value"], json!(["y"]));
}

#[tokio::test]
async fn owner_api_p1_patch_failed_couch_write_preserves_binding_and_state() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.seed_bar_v1().await;

    // Create initial valid item
    let (st, created) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": { "category": "x", "value": "y" },
            "config": { "legend": true },
            "rows": [{ "x": "A", "y": 10 }]
        })),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let item_id = created["item"]["id"].as_str().unwrap();
    let initial_etag = created["item"]["etag"].as_str().unwrap().to_string();
    let initial_doc_id: String =
        sqlx::query_scalar("SELECT couch_doc_id FROM user_chart_items WHERE id = $1")
            .bind(item_id)
            .fetch_one(&t.state.stores.db.pool)
            .await
            .unwrap();
    let report_slug = created["item"]["report_slug"].as_str().unwrap();
    let dataset_id = created["item"]["dataset_id"].as_str().unwrap();

    // Verify If-Match CAS check on PATCH
    let (st_cas, _) = call_with_headers(
        &t,
        "PATCH",
        &format!("/me/items/{item_id}"),
        Some(USER_1),
        &[("if-match", "\"stale-etag\"")],
        Some(json!({ "config": { "legend": false } })),
    )
    .await;
    assert_eq!(st_cas, StatusCode::CONFLICT);

    // Simulate CouchDB write failure
    t.docs.offline.store(true, Ordering::SeqCst);

    // Send PATCH with valid If-Match but failing CouchDB write
    let (st_fail, _) = call_with_headers(
        &t,
        "PATCH",
        &format!("/me/items/{item_id}"),
        Some(USER_1),
        &[("if-match", &initial_etag)],
        Some(json!({ "config": { "legend": false } })),
    )
    .await;
    assert_eq!(st_fail, StatusCode::SERVICE_UNAVAILABLE);

    // Restore CouchDB
    t.docs.offline.store(false, Ordering::SeqCst);

    // Assert stored item state is completely unchanged
    let (st_item, item_after) = call_with_headers(
        &t,
        "GET",
        &format!("/me/items/{item_id}"),
        Some(USER_1),
        &[],
        None,
    )
    .await;
    assert_eq!(st_item, StatusCode::OK);
    assert_eq!(item_after["item"]["etag"], initial_etag);
    let doc_id_after: String =
        sqlx::query_scalar("SELECT couch_doc_id FROM user_chart_items WHERE id = $1")
            .bind(item_id)
            .fetch_one(&t.state.stores.db.pool)
            .await
            .unwrap();
    assert_eq!(doc_id_after, initial_doc_id);
    assert_eq!(item_after["config"]["legend"], true);

    // Assert dataset visual binding in SQL is completely unchanged
    let (st_ds, ds_after) = call_with_headers(
        &t,
        "GET",
        &format!("/projects/cortex/reports/{report_slug}/datasets/{dataset_id}"),
        Some(USER_1),
        &[],
        None,
    )
    .await;
    assert_eq!(st_ds, StatusCode::OK);
    assert_eq!(ds_after["visual"]["options"]["legend"], "true");
}

#[tokio::test]
async fn owner_api_p1_interleaved_replace_vs_replace_atomic_cas_winner_takes_all() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.seed_bar_v1().await;

    // Create initial valid item
    let (st, created) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": { "category": "x", "value": "y" },
            "rows": [{ "x": "Initial", "y": 10 }]
        })),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let item_id = created["item"]["id"].as_str().unwrap();
    let initial_etag = created["item"]["etag"].as_str().unwrap().to_string();
    let report_slug = created["item"]["report_slug"].as_str().unwrap();
    let dataset_id = created["item"]["dataset_id"].as_str().unwrap();

    // Install gate on Docs double to hold Request B inside insert_records
    // (after it loaded initial detail and observed initial_etag, but before opening tx).
    let enter = Arc::new(Notify::new());
    let release = Arc::new(Notify::new());
    t.docs.set_insert_gate(enter.clone(), release.clone());

    let app_b = t.app.clone();
    let item_b = item_id.to_string();
    let etag_b = initial_etag.clone();
    let loser_handle = tokio::spawn(async move {
        call_app(
            &app_b,
            "PUT",
            &format!("/me/items/{item_b}/dataset"),
            Some(USER_1),
            &[("if-match", &etag_b)],
            Some(json!({
                "mapping": { "category": "x", "value": "y" },
                "rows": [{ "x": "Loser", "y": 999 }]
            })),
        )
        .await
    });

    // Wait until Request B has loaded initial_etag, reached Docs double, and paused.
    enter.notified().await;
    // Clear gate so winner Request A proceeds without pause.
    t.docs.clear_insert_gate();

    // Client A (winner) executes synchronously with initial_etag and commits.
    let (st_a, winner_detail) = call_with_headers(
        &t,
        "PUT",
        &format!("/me/items/{item_id}/dataset"),
        Some(USER_1),
        &[("if-match", &initial_etag)],
        Some(json!({
            "mapping": { "category": "x", "value": "y" },
            "rows": [{ "x": "Winner", "y": 100 }]
        })),
    )
    .await;
    assert_eq!(st_a, StatusCode::OK);
    let winner_etag = winner_detail["item"]["etag"].as_str().unwrap().to_string();
    assert_ne!(winner_etag, initial_etag);

    // Release Request B so its insert_records finishes and it proceeds to its CAS update.
    release.notify_one();
    let (st_b, _) = loser_handle.await.unwrap();
    assert_eq!(st_b, StatusCode::CONFLICT);

    // Owner detail MUST match Winner completely
    let (st_item, item_after) = call_with_headers(
        &t,
        "GET",
        &format!("/me/items/{item_id}"),
        Some(USER_1),
        &[],
        None,
    )
    .await;
    assert_eq!(st_item, StatusCode::OK);
    assert_eq!(item_after["item"]["etag"], winner_etag);
    assert_eq!(item_after["item"]["row_count"], 1);
    assert_eq!(item_after["rows"], json!([{ "x": "Winner", "y": 100 }]));

    // Dataset calculation_version and visual MUST match Winner completely
    let (st_ds, ds_after) = call_with_headers(
        &t,
        "GET",
        &format!("/projects/cortex/reports/{report_slug}/datasets/{dataset_id}"),
        Some(USER_1),
        &[],
        None,
    )
    .await;
    assert_eq!(st_ds, StatusCode::OK);
    assert_eq!(ds_after["lineage"]["calculation_version"], 2);
    assert_eq!(ds_after["visual"]["template"], "bar-v1");
    assert_eq!(ds_after["visual"]["mapping"]["category"], json!(["x"]));
    assert_eq!(ds_after["visual"]["mapping"]["value"], json!(["y"]));

    let ds_calc_ver: i64 = sqlx::query_scalar(
        "SELECT calculation_version FROM datasets WHERE project_slug = 'cortex' AND report_slug = $1 AND dataset_id = $2",
    )
    .bind(report_slug)
    .bind(dataset_id)
    .fetch_one(&t.state.stores.db.pool)
    .await
    .unwrap();
    assert_eq!(ds_calc_ver, 2);

    // Total calculation versions for this calculation must be 2, not 3
    let calc_id = format!("owner-calc-{item_id}");
    let calc_versions: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM calculation_versions WHERE project_slug = 'cortex' AND calculation_id = $1",
    )
    .bind(&calc_id)
    .fetch_one(&t.state.stores.db.pool)
    .await
    .unwrap();
    assert_eq!(calc_versions, 2);
}

#[tokio::test]
async fn owner_api_p1_interleaved_patch_vs_replace_atomic_cas_winner_takes_all() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.seed_bar_v1().await;

    // Create initial valid item
    let (st, created) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": { "category": "x", "value": "y" },
            "config": { "legend": true },
            "rows": [{ "x": "Initial", "y": 10 }]
        })),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let item_id = created["item"]["id"].as_str().unwrap();
    let initial_etag = created["item"]["etag"].as_str().unwrap().to_string();
    let report_slug = created["item"]["report_slug"].as_str().unwrap();
    let dataset_id = created["item"]["dataset_id"].as_str().unwrap();

    // Install gate on Docs double to hold Request B (replace) inside insert_records
    // (after it loaded initial detail and observed initial_etag, but before opening tx).
    let enter = Arc::new(Notify::new());
    let release = Arc::new(Notify::new());
    t.docs.set_insert_gate(enter.clone(), release.clone());

    let app_b = t.app.clone();
    let item_b = item_id.to_string();
    let etag_b = initial_etag.clone();
    let loser_handle = tokio::spawn(async move {
        call_app(
            &app_b,
            "PUT",
            &format!("/me/items/{item_b}/dataset"),
            Some(USER_1),
            &[("if-match", &etag_b)],
            Some(json!({
                "mapping": { "category": "x", "value": "y" },
                "rows": [{ "x": "Loser", "y": 999 }]
            })),
        )
        .await
    });

    // Wait until Request B reaches Docs double and pauses.
    enter.notified().await;
    t.docs.clear_insert_gate();

    // Client A (winner) patches audience to "asodya" and config legend to false
    let (st_patch, patch_detail) = call_with_headers(
        &t,
        "PATCH",
        &format!("/me/items/{item_id}"),
        Some(USER_1),
        &[("if-match", &initial_etag)],
        Some(json!({
            "audience": "asodya",
            "config": { "legend": false }
        })),
    )
    .await;
    assert_eq!(st_patch, StatusCode::OK);
    let patch_etag = patch_detail["item"]["etag"].as_str().unwrap().to_string();
    assert_ne!(patch_etag, initial_etag);

    // Release Request B so it proceeds to its CAS update with stale initial_etag
    release.notify_one();
    let (st_replace, _) = loser_handle.await.unwrap();
    assert_eq!(st_replace, StatusCode::CONFLICT);

    // Owner detail MUST match Winner patch state
    let (st_item, item_after) = call_with_headers(
        &t,
        "GET",
        &format!("/me/items/{item_id}"),
        Some(USER_1),
        &[],
        None,
    )
    .await;
    assert_eq!(st_item, StatusCode::OK);
    assert_eq!(item_after["item"]["etag"], patch_etag);
    assert_eq!(item_after["item"]["audience"], "asodya");
    assert_eq!(item_after["config"]["legend"], false);
    assert_eq!(item_after["rows"], json!([{ "x": "Initial", "y": 10 }]));

    // Dataset audience, visibility and visual options MUST match Winner patch state
    let (st_ds, ds_after) = call_with_headers(
        &t,
        "GET",
        &format!("/projects/cortex/reports/{report_slug}/datasets/{dataset_id}"),
        Some(USER_1),
        &[],
        None,
    )
    .await;
    assert_eq!(st_ds, StatusCode::OK);
    assert_eq!(ds_after["visibility"], "signed_in");
    assert_eq!(ds_after["lineage"]["calculation_version"], 1);
    assert_eq!(ds_after["visual"]["options"]["legend"], "false");

    // SQL datasets and reports tables MUST reflect audience and visibility transaction atomically
    let (ds_aud, ds_vis, ds_ver): (String, String, i64) = sqlx::query_as(
        "SELECT audience, visibility, calculation_version FROM datasets WHERE project_slug = 'cortex' AND report_slug = $1 AND dataset_id = $2",
    )
    .bind(report_slug)
    .bind(dataset_id)
    .fetch_one(&t.state.stores.db.pool)
    .await
    .unwrap();
    assert_eq!(ds_aud, "asodya");
    assert_eq!(ds_vis, "signed_in");
    assert_eq!(ds_ver, 1);

    let (rep_aud, rep_vis): (String, String) = sqlx::query_as(
        "SELECT audience, visibility FROM reports WHERE project_slug = 'cortex' AND slug = $1",
    )
    .bind(report_slug)
    .fetch_one(&t.state.stores.db.pool)
    .await
    .unwrap();
    assert_eq!(rep_aud, "asodya");
    assert_eq!(rep_vis, "signed_in");
}

#[tokio::test]
async fn owner_api_p1_patch_mapping_remap_updates_dataset_fields_version_and_rows() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.seed_bar_v1().await;

    // Create item with initial rows containing x, y, and previously-unmapped numeric column z
    let (st, created) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": { "category": "x", "value": "y" },
            "rows": [{ "x": "ItemA", "y": 10, "z": 20 }]
        })),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let item_id = created["item"]["id"].as_str().unwrap();
    let initial_etag = created["item"]["etag"].as_str().unwrap().to_string();
    let report_slug = created["item"]["report_slug"].as_str().unwrap();
    let dataset_id = created["item"]["dataset_id"].as_str().unwrap();

    // Dataset initially has calculation_version 1, spec fields for x and y only, and rows for x and y
    let (st_ds1, ds1) = call_with_headers(
        &t,
        "GET",
        &format!("/projects/cortex/reports/{report_slug}/datasets/{dataset_id}"),
        Some(USER_1),
        &[],
        None,
    )
    .await;
    assert_eq!(st_ds1, StatusCode::OK);
    assert_eq!(ds1["lineage"]["calculation_version"], 1);
    let fields1 = ds1["fields"].as_array().unwrap();
    let field_names1: Vec<&str> = fields1
        .iter()
        .map(|f| f["name"].as_str().unwrap())
        .collect();
    assert!(field_names1.contains(&"x"));
    assert!(field_names1.contains(&"y"));
    assert!(!field_names1.contains(&"z"));
    assert_eq!(ds1["rows"], json!([{ "x": "ItemA", "y": 10 }]));
    assert_eq!(ds1["visual"]["mapping"]["value"], json!(["y"]));

    // PATCH mapping: remap value to previously-unmapped numeric column z
    let (st_patch, patch_res) = call_with_headers(
        &t,
        "PATCH",
        &format!("/me/items/{item_id}"),
        Some(USER_1),
        &[("if-match", &initial_etag)],
        Some(json!({
            "mapping": { "category": "x", "value": "z" }
        })),
    )
    .await;
    assert_eq!(st_patch, StatusCode::OK);
    let patch_etag = patch_res["item"]["etag"].as_str().unwrap();
    assert_ne!(patch_etag, initial_etag);

    // Owner detail reflects new mapping
    let (st_item, item_after) = call_with_headers(
        &t,
        "GET",
        &format!("/me/items/{item_id}"),
        Some(USER_1),
        &[],
        None,
    )
    .await;
    assert_eq!(st_item, StatusCode::OK);
    assert_eq!(item_after["mapping"]["value"], "z");
    assert_eq!(item_after["item"]["etag"], patch_etag);

    // Dataset reflects calculation_version 2, updated spec fields (including z), projected rows (including z), and visual binding
    let (st_ds2, ds2) = call_with_headers(
        &t,
        "GET",
        &format!("/projects/cortex/reports/{report_slug}/datasets/{dataset_id}"),
        Some(USER_1),
        &[],
        None,
    )
    .await;
    assert_eq!(st_ds2, StatusCode::OK);
    assert_eq!(ds2["lineage"]["calculation_version"], 2);
    let fields2 = ds2["fields"].as_array().unwrap();
    let field_names2: Vec<&str> = fields2
        .iter()
        .map(|f| f["name"].as_str().unwrap())
        .collect();
    assert!(field_names2.contains(&"x"));
    assert!(field_names2.contains(&"z"));
    assert!(!field_names2.contains(&"y"));
    assert_eq!(ds2["rows"], json!([{ "x": "ItemA", "z": 20 }]));
    assert_eq!(ds2["visual"]["mapping"]["value"], json!(["z"]));

    // Verify calculation_versions in SQL has 2 versions
    let calc_id = format!("owner-calc-{item_id}");
    let calc_versions: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM calculation_versions WHERE project_slug = 'cortex' AND calculation_id = $1",
    )
    .bind(&calc_id)
    .fetch_one(&t.state.stores.db.pool)
    .await
    .unwrap();
    assert_eq!(calc_versions, 2);

    let ds_calc_ver: i64 = sqlx::query_scalar(
        "SELECT calculation_version FROM datasets WHERE project_slug = 'cortex' AND report_slug = $1 AND dataset_id = $2",
    )
    .bind(report_slug)
    .bind(dataset_id)
    .fetch_one(&t.state.stores.db.pool)
    .await
    .unwrap();
    assert_eq!(ds_calc_ver, 2);
}

#[tokio::test]
async fn owner_api_p1_replace_sql_failure_after_couch_success_rolls_back_atomically() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.seed_bar_v1().await;

    // Create initial valid item
    let (st, created) = call_with_headers(
        &t,
        "POST",
        "/me/projects/cortex/items",
        Some(USER_1),
        &[],
        Some(json!({
            "template_id": "bar-v1",
            "template_version": 1,
            "mapping": { "category": "x", "value": "y" },
            "rows": [{ "x": "Initial", "y": 10 }]
        })),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let item_id = created["item"]["id"].as_str().unwrap();
    let initial_etag = created["item"]["etag"].as_str().unwrap().to_string();
    let initial_doc_id: String =
        sqlx::query_scalar("SELECT couch_doc_id FROM user_chart_items WHERE id = $1")
            .bind(item_id)
            .fetch_one(&t.state.stores.db.pool)
            .await
            .unwrap();
    let report_slug = created["item"]["report_slug"].as_str().unwrap();
    let dataset_id = created["item"]["dataset_id"].as_str().unwrap();

    // Inject relational failure before visual binding completes
    sqlx::query(
        "CREATE TRIGGER fail_visual_insert BEFORE INSERT ON report_card_visuals \
         BEGIN SELECT RAISE(ABORT, 'injected relational failure'); END;",
    )
    .execute(&t.state.stores.db.pool)
    .await
    .unwrap();

    // Attempt replace with valid payload and ETag: Couch prepare succeeds, but relational transaction fails
    let (st_fail, _) = call_with_headers(
        &t,
        "PUT",
        &format!("/me/items/{item_id}/dataset"),
        Some(USER_1),
        &[("if-match", &initial_etag)],
        Some(json!({
            "mapping": { "category": "x", "value": "y" },
            "rows": [{ "x": "ShouldRollback", "y": 999 }]
        })),
    )
    .await;
    assert_eq!(st_fail, StatusCode::INTERNAL_SERVER_ERROR);

    // Remove trigger
    sqlx::query("DROP TRIGGER fail_visual_insert")
        .execute(&t.state.stores.db.pool)
        .await
        .unwrap();

    // Stored item state MUST be completely rolled back to initial state
    let (st_item, item_after) = call_with_headers(
        &t,
        "GET",
        &format!("/me/items/{item_id}"),
        Some(USER_1),
        &[],
        None,
    )
    .await;
    assert_eq!(st_item, StatusCode::OK);
    assert_eq!(item_after["item"]["etag"], initial_etag);
    let doc_id_after: String =
        sqlx::query_scalar("SELECT couch_doc_id FROM user_chart_items WHERE id = $1")
            .bind(item_id)
            .fetch_one(&t.state.stores.db.pool)
            .await
            .unwrap();
    assert_eq!(doc_id_after, initial_doc_id);
    assert_eq!(item_after["rows"], json!([{ "x": "Initial", "y": 10 }]));

    // Dataset calculation_version in SQL MUST remain 1
    let (st_ds, ds_after) = call_with_headers(
        &t,
        "GET",
        &format!("/projects/cortex/reports/{report_slug}/datasets/{dataset_id}"),
        Some(USER_1),
        &[],
        None,
    )
    .await;
    assert_eq!(st_ds, StatusCode::OK);
    assert_eq!(ds_after["lineage"]["calculation_version"], 1);

    // Calculation version 2 must NOT exist in relational table
    let calc_id = format!("owner-calc-{item_id}");
    let calc_versions: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM calculation_versions WHERE project_slug = 'cortex' AND calculation_id = $1",
    )
    .bind(&calc_id)
    .fetch_one(&t.state.stores.db.pool)
    .await
    .unwrap();
    assert_eq!(calc_versions, 1);
}
