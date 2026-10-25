//! Tier filter of report lists and report views, and the access counts of each caller.

mod common;

use axum::http::StatusCode;
use common::*;
use serde_json::{json, Value};

/// token-usage: tokens-by-provider (real, public), latency-by-model (sample, signed_in) and
/// errors-by-type (sample, restricted), both gated cards discoverable. A hybrid report.
/// real-only: one real public card. A real report.
async fn setup() -> TestApp {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.ingest(json!([event("a", "ollama", "qwen", 100, 10, true), event("b", "openai", "gpt", 50, 30, false)])).await;
    let base = "/projects/cortex/admin/reports";
    let mut real = dataset("tokens-by-provider", "public");
    real["data_tier"] = json!("real");
    assert_eq!(t.service("PUT", &format!("{base}/token-usage/datasets/tokens-by-provider"), real.clone()).await.0, StatusCode::OK);
    for (id, visibility) in [("latency-by-model", "signed_in"), ("errors-by-type", "restricted")] {
        let mut d = dataset(id, visibility);
        d["discoverable"] = json!(true);
        assert_eq!(t.service("PUT", &format!("{base}/token-usage/datasets/{id}"), d).await.0, StatusCode::OK);
    }
    let (s, v) = t.service("PUT", &format!("{base}/real-only"), json!({"title": {"en": "Real only"}, "visibility": "public"})).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(t.service("PUT", &format!("{base}/real-only/datasets/tokens-by-provider"), real).await.0, StatusCode::OK);
    t
}

fn slugs(list: &Value) -> Vec<&str> {
    list["items"].as_array().unwrap().iter().map(|r| r["slug"].as_str().unwrap()).collect()
}

fn ids(cards: &Value) -> Vec<&str> {
    cards.as_array().unwrap().iter().map(|c| c["dataset_id"].as_str().unwrap()).collect()
}

#[tokio::test]
async fn report_lists_filter_by_report_tier() {
    let t = setup().await;
    let list = "/projects/cortex/reports";
    let mut all = slugs(&t.get(list, &[]).await.1).into_iter().map(str::to_string).collect::<Vec<_>>();
    all.sort();
    assert_eq!(all, ["real-only", "token-usage"]);
    assert_eq!(slugs(&t.get(&format!("{list}?tier=real"), &[]).await.1), ["real-only"]);
    assert_eq!(slugs(&t.get(&format!("{list}?tier=hybrid"), &[]).await.1), ["token-usage"]);
    assert!(slugs(&t.get(&format!("{list}?tier=sample"), &[]).await.1).is_empty());
    // The session list uses the same filter.
    assert_eq!(slugs(&t.get("/me/projects/cortex/reports?tier=hybrid", &[("x-uuid", ALICE)]).await.1), ["token-usage"]);
    assert_eq!(t.get(&format!("{list}?tier=fake"), &[]).await.0, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn report_views_filter_cards_by_tier_and_keep_the_report_tier() {
    let t = setup().await;
    let (s, v) = t.get("/projects/cortex/showcase/token-usage?tier=real", &[]).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(ids(&v["cards"]), ["tokens-by-provider"]);
    assert_eq!(v["data_tier"], "hybrid", "the report tier counts every visible card");
    assert_eq!(v["tiers"], json!(["real", "sample"]));
    assert_eq!(v["access"], json!({"total": 1, "readable": 1, "needs_sign_in": 0, "needs_admin": 0}));

    let (s, v) = t.get("/projects/cortex/reports/token-usage?tier=sample", &[("x-uuid", ALICE)]).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let mut sample = ids(&v["datasets"]);
    sample.sort();
    assert_eq!(sample, ["errors-by-type", "latency-by-model"]);
    assert_eq!(v["tiers"], json!(["real", "sample"]));
}

#[tokio::test]
async fn access_counts_say_what_opens_the_placeholders_for_each_caller() {
    let t = setup().await;
    // Guest: the signed_in card opens with a sign in, the restricted one needs an admin.
    let (_, guest) = t.get("/projects/cortex/showcase/token-usage", &[]).await;
    assert_eq!(guest["access"], json!({"total": 3, "readable": 1, "needs_sign_in": 1, "needs_admin": 1}));
    // Signed in without a role: only the restricted card stays closed.
    let (_, viewer) = t.get("/projects/cortex/reports/token-usage", &[("x-uuid", ALICE)]).await;
    assert_eq!(viewer["access"], json!({"total": 3, "readable": 2, "needs_sign_in": 0, "needs_admin": 1}));
    // Super admin reads everything.
    let (_, root) = t.get("/projects/cortex/reports/token-usage", &[("x-uuid", ROOT), ("x-access-level", "1")]).await;
    assert_eq!(root["access"], json!({"total": 3, "readable": 3, "needs_sign_in": 0, "needs_admin": 0}));
}

#[tokio::test]
async fn card_order_of_the_report_sets_the_card_order_of_both_views() {
    let t = setup().await;
    let (s, v) = t.service("PUT", "/projects/cortex/admin/reports/token-usage", json!({
        "title": {"en": "Token Usage"}, "visibility": "public",
        "metadata": {"card_order": ["latency-by-model", "tokens-by-provider"]}
    })).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let (_, guest) = t.get("/projects/cortex/showcase/token-usage", &[]).await;
    // Listed cards first in the listed order, then the others by ID.
    assert_eq!(ids(&guest["cards"]), ["latency-by-model", "tokens-by-provider", "errors-by-type"]);
    let (_, root) = t.get("/projects/cortex/reports/token-usage", &[("x-uuid", ROOT), ("x-access-level", "1")]).await;
    assert_eq!(ids(&root["datasets"]), ["latency-by-model", "tokens-by-provider", "errors-by-type"]);
}
