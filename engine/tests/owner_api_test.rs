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
