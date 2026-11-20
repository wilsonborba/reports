mod common;

use axum::http::StatusCode;
use common::*;
use reports::dal::templates::{
    science_ai_catalog_templates, seed_science_ai_templates,
};

#[tokio::test]
async fn all_10_science_ai_templates_publish_and_discover_in_all_languages() {
    let t = TestApp::new().await;
    t.seed_cortex().await;

    let catalog = science_ai_catalog_templates();
    assert_eq!(catalog.len(), 10);

    seed_science_ai_templates(&t.state.stores.db).await.unwrap();
    seed_science_ai_templates(&t.state.stores.db).await.unwrap();

    for lang in ["en", "pt-BR", "th"] {
        let (st, disc, _) = t
            .call("GET", "/projects/cortex/templates", &[("lang", lang)], None)
            .await;
        assert_eq!(st, StatusCode::OK);
        let list = disc["templates"].as_array().unwrap();
        assert_eq!(list.len(), 10, "missing science/AI templates for {lang}");
        for item in list {
            assert!(!item["title"].as_str().unwrap().is_empty());
        }
    }
}
