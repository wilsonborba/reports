mod common;

use axum::http::StatusCode;
use common::*;
use reports::dal::templates::{comparison_catalog_templates, seed_comparison_templates};
use serde_json::json;

#[tokio::test]
async fn all_23_comparison_templates_publish_discover_and_bind() {
    let t = TestApp::new().await;
    t.seed_cortex().await;

    let catalog = comparison_catalog_templates();
    assert_eq!(catalog.len(), 23);

    seed_comparison_templates(&t.state.stores.db).await.unwrap();
    // Idempotent second call.
    seed_comparison_templates(&t.state.stores.db).await.unwrap();

    for lang in ["en", "pt-BR", "th"] {
        let (st, disc, _) = t
            .call("GET", "/projects/cortex/templates", &[("lang", lang)], None)
            .await;
        assert_eq!(st, StatusCode::OK);
        let list = disc["templates"].as_array().unwrap();
        assert_eq!(list.len(), 23, "missing comparison templates for {lang}");
        for item in list {
            assert!(!item["title"].as_str().unwrap().is_empty());
        }
    }

    // Bind vertical_bar to an existing dataset card.
    let (st, bound) = t
        .service(
            "PUT",
            "/projects/cortex/admin/reports/token-usage/datasets/tokens-by-provider/visual",
            json!({
                "template": "vertical_bar",
                "version": 1,
                "mapping": { "category": ["provider"], "value": ["tokens"] },
                "options": { "sort": "none" }
            }),
        )
        .await;
    assert_eq!(st, StatusCode::OK, "{bound}");
}
