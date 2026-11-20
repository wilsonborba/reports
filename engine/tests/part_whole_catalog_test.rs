mod common;

use axum::http::StatusCode;
use common::*;
use reports::dal::templates::{part_whole_catalog_templates, seed_part_whole_templates};

#[tokio::test]
async fn all_11_part_whole_templates_publish_and_discover_in_all_languages() {
    let t = TestApp::new().await;
    t.seed_cortex().await;

    let catalog = part_whole_catalog_templates();
    assert_eq!(catalog.len(), 11);

    seed_part_whole_templates(&t.state.stores.db).await.unwrap();
    seed_part_whole_templates(&t.state.stores.db).await.unwrap();

    for lang in ["en", "pt-BR", "th"] {
        let (st, disc, _) = t
            .call("GET", "/projects/cortex/templates", &[("lang", lang)], None)
            .await;
        assert_eq!(st, StatusCode::OK);
        let list = disc["templates"].as_array().unwrap();
        assert_eq!(
            list.len(),
            11,
            "missing part-of-a-whole templates for {lang}"
        );
        for item in list {
            assert!(!item["title"].as_str().unwrap().is_empty());
        }
    }
}
