mod common;

use axum::http::StatusCode;
use common::*;
use reports::dal::templates::{seed_sets_templates, sets_catalog_templates};

#[tokio::test]
async fn all_3_sets_templates_publish_and_discover_in_all_languages() {
    let t = TestApp::new().await;
    t.seed_cortex().await;

    let catalog = sets_catalog_templates();
    assert_eq!(catalog.len(), 3);

    seed_sets_templates(&t.state.stores.db).await.unwrap();
    seed_sets_templates(&t.state.stores.db).await.unwrap();

    for lang in ["en", "pt-BR", "th"] {
        let (st, disc, _) = t
            .call("GET", "/projects/cortex/templates", &[("lang", lang)], None)
            .await;
        assert_eq!(st, StatusCode::OK);
        let list = disc["templates"].as_array().unwrap();
        assert_eq!(list.len(), 3, "missing sets templates for {lang}");
        for item in list {
            assert!(!item["title"].as_str().unwrap().is_empty());
        }
    }
}
