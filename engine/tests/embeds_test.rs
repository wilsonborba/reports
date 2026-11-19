mod common;
use axum::{
    body::{to_bytes, Body},
    http::{Request, StatusCode},
};
use common::*;
use serde_json::json;
use tower::ServiceExt;
#[tokio::test]
async fn item_descriptor_preserves_state_and_png_never_leaks_private_rows() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.ingest(json!([event("preview", "ollama", "local", 100, 10, true)]))
        .await;
    let base = "/projects/cortex/showcase/token-usage/cards/tokens-by-provider";
    let (status, value, _) = t
        .call(
            "GET",
            &format!("{base}/embed?view=table&f.provider=ollama&lang=en"),
            &[],
            None,
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{value}");
    assert!(value["embed_url"].as_str().unwrap().contains("/v1/embed/"));
    assert!(value["embed_url"].as_str().unwrap().contains("view=table"));
    assert!(value["html"].as_str().unwrap().contains("&amp;"));
    use reports::dal::CacheStore;
    let query = std::collections::HashMap::from([("view".to_string(), "table".to_string())]);
    let page = reports::domain::embeds::public_page(
        &t.state.datasets,
        "cortex",
        "token-usage",
        "tokens-by-provider",
        &query,
        "en",
    )
    .await
    .unwrap();
    let (_, url, _) =
        reports::domain::embeds::item_urls("cortex", "token-usage", "tokens-by-provider", &query);
    let key = reports::dal::embed_preview::cache_key(&url, &page);
    t.cache
        .set(
            &key,
            &hex::encode(include_bytes!("../../ui/web/icons/Icon-192.png")),
            120,
        )
        .await;
    let response = t
        .app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("{base}/thumbnail.png?view=table"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(response.headers()["content-type"], "image/png");
    let bytes = to_bytes(response.into_body(), 2_000_000).await.unwrap();
    assert_eq!(&bytes[..8], b"\x89PNG\r\n\x1a\n");
    let (status, _) = t
        .service(
            "PUT",
            "/projects/cortex/admin/reports/token-usage/datasets/tokens-by-provider",
            dataset("tokens-by-provider", "restricted"),
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _, _) = t.call("GET", &format!("{base}/embed"), &[], None).await;
    assert!(!status.is_success());
    let response = t
        .app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("{base}/thumbnail.png"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert!(!response.status().is_success());
}

#[tokio::test]
async fn viewer_aware_search_embeds_placeholders_and_immutable_snapshots() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    let user_a = "11111111-1111-4111-8111-111111111111";
    let user_b = "22222222-2222-4222-8222-222222222222";

    // Create a Personal chart owned by User A.
    let (st, created, _) = t
        .call(
            "POST",
            "/me/projects/cortex/items",
            &[("x-uuid", user_a)],
            Some(json!({
                "title": "Secret Alpha Chart",
                "template_id": "bar-v1",
                "template_version": 1,
                "mapping": { "category": "x", "value": "y" },
                "rows": [{ "x": "V1", "y": 10 }]
            })),
        )
        .await;
    assert_eq!(st, StatusCode::CREATED, "{created}");
    let item_id = created["item"]["id"].as_str().unwrap().to_string();
    let report_slug = created["item"]["report_slug"].as_str().unwrap().to_string();
    let dataset_id = created["item"]["dataset_id"].as_str().unwrap().to_string();
    let etag1 = created["item"]["etag"].as_str().unwrap().to_string();

    // 1. Search never reveals Personal items to anonymous or User B, but shows them to User A.
    let (st, anon_search, _) = t
        .call("GET", "/projects/cortex/reports?q=bar-v1", &[], None)
        .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(anon_search["items"].as_array().unwrap().len(), 0);

    let (st, b_search, _) = t
        .call(
            "GET",
            "/me/projects/cortex/reports?q=Secret",
            &[("x-uuid", user_b)],
            None,
        )
        .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(b_search["items"].as_array().unwrap().len(), 0);

    let (st, a_search, _) = t
        .call(
            "GET",
            "/me/projects/cortex/reports?q=bar-v1",
            &[("x-uuid", user_a)],
            None,
        )
        .await;
    assert_eq!(st, StatusCode::OK);
    let a_items = a_search["items"].as_array().unwrap();
    assert_eq!(a_items.len(), 1);
    assert_eq!(a_items[0]["slug"], report_slug);
    assert_eq!(a_items[0]["audience"], "personal");
    assert_eq!(a_items[0]["chart_types"], json!(["bar-v1"]));
    assert!(a_items[0]["open_in_reports_url"]
        .as_str()
        .unwrap()
        .contains(&report_slug));

    // 2. Anonymous embed of a Personal report returns only a placeholder (no values, no thumbnail).
    let embed_path = format!("/projects/cortex/reports/{report_slug}/cards/{dataset_id}/embed");
    let (st, anon_embed, _) = t.call("GET", &embed_path, &[], None).await;
    assert_eq!(st, StatusCode::OK, "{anon_embed}");
    assert_eq!(anon_embed["status"], "placeholder");
    assert_eq!(anon_embed["can_view"], false);
    assert_eq!(anon_embed["title"], "Restricted chart");
    assert!(anon_embed["thumbnail_url"].is_null());
    assert!(anon_embed["rows"].is_null());
    assert_eq!(anon_embed["placeholder"]["action"], "login");
    assert!(anon_embed["source_url"]
        .as_str()
        .unwrap()
        .contains(&report_slug));

    // User B also gets placeholder (action=access), never values.
    let (st, b_embed, _) = t
        .call("GET", &embed_path, &[("x-uuid", user_b)], None)
        .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(b_embed["status"], "placeholder");
    assert_eq!(b_embed["placeholder"]["action"], "access");
    assert!(b_embed["rows"].is_null());

    // Owner A gets full readable embed.
    let (st, a_embed, _) = t
        .call("GET", &embed_path, &[("x-uuid", user_a)], None)
        .await;
    assert_eq!(st, StatusCode::OK, "{a_embed}");
    assert_eq!(a_embed["status"], "readable");
    assert_eq!(a_embed["can_view"], true);
    assert!(a_embed["thumbnail_url"].as_str().is_some());
    assert_eq!(a_embed["rows"][0]["x"], "V1");

    // 3. Snapshot capture: fixed after capture, and guarded by source permissions.
    let snap_base = format!("/projects/cortex/reports/{report_slug}/cards/{dataset_id}/snapshots");
    let (st, snap_meta, _) = t
        .call("POST", &snap_base, &[("x-uuid", user_a)], Some(json!({})))
        .await;
    assert_eq!(st, StatusCode::CREATED, "{snap_meta}");
    let snap_id = snap_meta["id"].as_str().unwrap().to_string();

    // Update live dataset to V2.
    let (st, replaced, _) = t
        .call(
            "PUT",
            &format!("/me/items/{item_id}/dataset"),
            &[("x-uuid", user_a), ("if-match", &etag1)],
            Some(json!({ "rows": [{ "x": "V2", "y": 99 }] })),
        )
        .await;
    assert_eq!(st, StatusCode::OK, "{replaced}");

    // Snapshot content still returns V1.
    let (st, snap_content, _) = t
        .call(
            "GET",
            &format!("{snap_base}/{snap_id}/content"),
            &[("x-uuid", user_a)],
            None,
        )
        .await;
    assert_eq!(st, StatusCode::OK, "{snap_content}");
    assert_eq!(snap_content["rows"].as_array().unwrap().len(), 1);
    assert_eq!(snap_content["rows"][0]["x"], "V1");
    assert_eq!(snap_content["rows"][0]["y"], 10);

    // User B and anonymous cannot read the Personal snapshot.
    let (st, _, _) = t
        .call(
            "GET",
            &format!("{snap_base}/{snap_id}/content"),
            &[("x-uuid", user_b)],
            None,
        )
        .await;
    assert_eq!(st, StatusCode::NOT_FOUND);
    let (st, _, _) = t
        .call("GET", &format!("{snap_base}/{snap_id}"), &[], None)
        .await;
    assert_eq!(st, StatusCode::NOT_FOUND);
}
