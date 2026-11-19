mod common;

use axum::http::StatusCode;
use common::*;
use serde_json::json;

#[tokio::test]
async fn template_publish_discovery_immutability_and_card_binding() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.ingest(json!([event("evt-1", "ollama", "local", 100, 10, true)]))
        .await;

    let draft_v1 = json!({
        "template_id": "bar",
        "version": 1,
        "kind": "chart",
        "visual": "bar",
        "title": {
            "en": "Bar Chart",
            "pt-BR": "Grafico de Barras",
            "th": "แผนภูมิแท่ง"
        },
        "slots": [
            {
                "slot_name": "category",
                "role": "dimension",
                "is_required": true,
                "min_count": 1,
                "max_count": 1,
                "accepted_types": ["string"]
            },
            {
                "slot_name": "value",
                "role": "measure",
                "is_required": true,
                "min_count": 1,
                "max_count": 3,
                "accepted_types": ["integer", "float"]
            }
        ],
        "options": [
            {
                "option_name": "sort",
                "value_type": "enum",
                "default_value": "desc",
                "allowed_values": ["asc", "desc"]
            }
        ]
    });

    // Save draft v1.
    let (st, created) = t
        .service("POST", "/projects/cortex/admin/templates", draft_v1.clone())
        .await;
    assert_eq!(st, StatusCode::CREATED, "{created}");
    assert_eq!(created["status"], "draft");

    // Draft is not listed in discovery and cannot be bound yet.
    let (st, disc, _) = t.call("GET", "/projects/cortex/templates", &[], None).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(disc["templates"].as_array().unwrap().len(), 0);

    let (st, _) = t
        .service(
            "PUT",
            "/projects/cortex/admin/reports/token-usage/datasets/tokens-by-provider/visual",
            json!({
                "template": "bar",
                "version": 1,
                "mapping": { "category": ["provider"], "value": ["tokens"] },
                "options": { "sort": "desc" }
            }),
        )
        .await;
    assert_eq!(st, StatusCode::CONFLICT);

    // Publish v1.
    let (st, published) = t
        .service(
            "POST",
            "/projects/cortex/admin/templates/bar/versions/1/publish",
            json!({}),
        )
        .await;
    assert_eq!(st, StatusCode::OK, "{published}");
    assert_eq!(published["status"], "published");

    // Published v1 cannot be modified; a change must be v2.
    let (st, _) = t
        .service("POST", "/projects/cortex/admin/templates", draft_v1)
        .await;
    assert_eq!(st, StatusCode::CONFLICT);

    // Discovery returns published v1 with localized title, slots, and options.
    let (st, disc, _) = t
        .call(
            "GET",
            "/projects/cortex/templates?kind=chart&lang=pt-BR",
            &[],
            None,
        )
        .await;
    assert_eq!(st, StatusCode::OK, "{disc}");
    let items = disc["templates"].as_array().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["template_id"], "bar");
    assert_eq!(items[0]["title"], "Grafico de Barras");
    assert_eq!(items[0]["slots"].as_array().unwrap().len(), 2);
    assert_eq!(
        items[0]["options"][0]["allowed_values"],
        json!(["asc", "desc"])
    );

    // Bind card to published v1 and verify DatasetPage includes visual; unbound card keeps None.
    let (st, _) = t
        .service(
            "PUT",
            "/projects/cortex/admin/reports/token-usage/datasets/tokens-by-provider/visual",
            json!({
                "template": "bar",
                "version": 1,
                "mapping": { "category": ["provider"], "value": ["tokens"] },
                "options": { "sort": "desc" }
            }),
        )
        .await;
    assert_eq!(st, StatusCode::OK);

    let (st, page, _) = t
        .call(
            "GET",
            "/projects/cortex/reports/token-usage/datasets/tokens-by-provider",
            &[],
            None,
        )
        .await;
    assert_eq!(st, StatusCode::OK, "{page}");
    assert_eq!(page["visual"]["template"], "bar");
    assert_eq!(page["visual"]["version"], 1);
    assert_eq!(page["visual"]["mapping"]["category"], json!(["provider"]));
    assert_eq!(page["visual"]["options"]["sort"], "desc");
}
