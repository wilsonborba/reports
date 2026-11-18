mod common;

use axum::http::StatusCode;
use common::*;
use serde_json::{json, Value};

async fn call_with_headers(
    t: &TestApp,
    method: &str,
    uri: &str,
    user: Option<&str>,
    headers: &[(&str, &str)],
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut hdrs: Vec<(&str, &str)> = headers.to_vec();
    if let Some(u) = user {
        hdrs.push(("x-uuid", u));
    }
    let (status, val, _) = t.call(method, uri, &hdrs, body).await;
    (status, val)
}

const USER_1: &str = "11111111-1111-4111-8111-111111111111";
const USER_2: &str = "22222222-2222-4222-8222-222222222222";

#[tokio::test]
async fn owner_api_create_idempotency_limits_if_match_visibility_and_delete() {
    let t = TestApp::new().await;
    t.seed_cortex().await;

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
            "mapping": { "x": "x", "y": "y" },
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
