//! Project links, Domain composition with Redis caching, themes and report provenance.

mod common;

use std::sync::atomic::Ordering;

use axum::http::StatusCode;
use common::*;
use serde_json::json;

fn cortex_body(domain_id: Option<&str>) -> serde_json::Value {
    json!({
        "name": {"en": "Cortex"},
        "tagline": {"en": "Multi-model LLM orchestration", "pt-BR": "Orquestração de vários modelos"},
        "website_url": "https://cortex.asodya.com",
        "repository_url": "https://github.com/wilsonborba/cortex",
        "domain_project_id": domain_id
    })
}

#[tokio::test]
async fn domain_link_is_validated_unique_and_durable() {
    let t = TestApp::new().await;
    let (s, v) = t.service("PUT", "/projects/cortex/admin/project", cortex_body(Some(CORTEX_DOMAIN_ID))).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(v["domain_project_id"], CORTEX_DOMAIN_ID);
    assert_eq!(v["website_url"], "https://cortex.asodya.com");

    // The same Domain UUID cannot link a second Reports project.
    let (s, v) = t.service("PUT", "/projects/domain/admin/project", json!({"name": {"en": "Asodya"}, "domain_project_id": CORTEX_DOMAIN_ID})).await;
    assert_eq!(s, StatusCode::CONFLICT, "{v}");
    // A UUID that domain_api does not know, and a value that is not a UUID.
    let (s, _) = t.service("PUT", "/projects/domain/admin/project", json!({"name": {"en": "Asodya"}, "domain_project_id": "00000000-0000-4000-8000-000000000000"})).await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (s, _) = t.service("PUT", "/projects/domain/admin/project", json!({"name": {"en": "Asodya"}, "domain_project_id": "asodya-home"})).await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    // A new link cannot be verified while domain_api is down.
    *t.domain.projects.lock().unwrap() = None;
    let (s, _) = t.service("PUT", "/projects/domain/admin/project", json!({"name": {"en": "Asodya"}, "domain_project_id": HOME_DOMAIN_ID})).await;
    assert_eq!(s, StatusCode::SERVICE_UNAVAILABLE);
    // An unchanged link needs no Domain call, so other edits work during the outage.
    let (s, _) = t.service("PUT", "/projects/cortex/admin/project", cortex_body(Some(CORTEX_DOMAIN_ID))).await;
    assert_eq!(s, StatusCode::OK);
    // http links are refused.
    let mut body = cortex_body(None);
    body["website_url"] = json!("http://cortex.asodya.com");
    assert_eq!(t.service("PUT", "/projects/cortex/admin/project", body).await.0, StatusCode::UNPROCESSABLE_ENTITY);

    let t = t.restart().await;
    let row = reports::dal::catalog::get_project(&t.db, "cortex").await.unwrap().unwrap();
    assert_eq!(row.domain_project_id.as_deref(), Some(CORTEX_DOMAIN_ID));
}

#[tokio::test]
async fn catalog_composes_domain_details_from_one_cached_request() {
    let t = TestApp::new().await;
    t.service("PUT", "/projects/cortex/admin/project", cortex_body(Some(CORTEX_DOMAIN_ID))).await;
    t.service("PUT", "/projects/fsm/admin/project", json!({"name": {"en": "FSM Media Storage"}, "website_url": "https://github.com/wilsonborba/fsm"})).await;
    // The link check stored a fresh copy; drop it to observe the catalog request.
    use reports::dal::CacheStore;
    t.cache.delete("domain:index:fresh:v1").await;
    let calls_before = t.domain.calls.load(Ordering::SeqCst);

    let (s, v) = t.get("/catalog", &[]).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let items = v["items"].as_array().unwrap();
    let cortex = items.iter().find(|p| p["slug"] == "cortex").unwrap();
    assert_eq!(cortex["domain_status"], "fresh");
    assert_eq!(cortex["domain"]["slug"], "cortex");
    assert_eq!(cortex["domain"]["cover_url"], "https://api.asodya.com/apps/domain/v1/projects/cortex/cover");
    assert!(cortex["domain"]["fetched_at"].is_string());
    let fsm = items.iter().find(|p| p["slug"] == "fsm").unwrap();
    assert_eq!(fsm["domain_status"], "unlinked");
    assert!(cortex.get("contact_url").is_none() && cortex.get("contact_email").is_none());
    assert_eq!(t.domain.calls.load(Ordering::SeqCst), calls_before + 1, "one request for the whole catalog");

    // Within the TTL, Redis answers and domain_api is not called.
    t.get("/catalog", &[]).await;
    t.get("/projects/cortex", &[]).await;
    assert_eq!(t.domain.calls.load(Ordering::SeqCst), calls_before + 1);

    // A Domain slug change keeps the link (matched by UUID).
    let mut renamed = domain_projects();
    renamed[0].slug = "cortex-web".into();
    *t.domain.projects.lock().unwrap() = Some(renamed);
    t.cache.delete("domain:index:fresh:v1").await;
    let (_, v) = t.get("/projects/cortex", &[]).await;
    assert_eq!(v["domain"]["slug"], "cortex-web");
    assert_eq!(v["slug"], "cortex", "the Reports slug never changes");

    // Fresh copy expired and domain_api down: dated last-known copy, marked stale.
    t.cache.delete("domain:index:fresh:v1").await;
    *t.domain.projects.lock().unwrap() = None;
    let (s, v) = t.get("/projects/cortex", &[]).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(v["domain_status"], "stale");
    assert_eq!(v["domain"]["slug"], "cortex-web");
}

#[tokio::test]
async fn domain_outage_without_cache_keeps_reports_projects() {
    let t = TestApp::new().await;
    t.service("PUT", "/projects/cortex/admin/project", cortex_body(Some(CORTEX_DOMAIN_ID))).await;
    t.cache.offline.store(true, Ordering::SeqCst);
    *t.domain.projects.lock().unwrap() = None;
    let (s, v) = t.get("/catalog", &[]).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(v["total"], 1);
    assert_eq!(v["items"][0]["domain_status"], "unavailable");
    assert!(v["items"][0]["domain"].is_null());
    assert_eq!(v["items"][0]["tagline"], "Multi-model LLM orchestration");
    // A linked UUID that disappeared from Domain: the project stays, status missing.
    t.cache.offline.store(false, Ordering::SeqCst);
    reports::dal::CacheStore::delete(t.cache.as_ref(), "domain:index:fresh:v1").await;
    *t.domain.projects.lock().unwrap() = Some(vec![domain_projects()[1].clone()]);
    let (_, v) = t.get("/projects/cortex", &[]).await;
    assert_eq!(v["domain_status"], "missing");
}

#[tokio::test]
async fn themes_are_validated_and_durable() {
    let t = TestApp::new().await;
    t.service("PUT", "/projects/cortex/admin/project", cortex_body(None)).await;
    let (_, default_theme) = t.get("/projects/cortex/theme", &[]).await;
    assert_eq!(default_theme["dark"]["canvas"], "#0B0C10");

    let mut dark = default_theme["dark"].clone();
    dark["accent"] = json!("#F5F5F7");
    let (s, v) = t.service("PUT", "/projects/cortex/admin/theme", json!({"dark": dark})).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let mut bad = dark.clone();
    bad["text_primary"] = json!("#0B0C11");
    let (s, _) = t.service("PUT", "/projects/cortex/admin/theme", json!({"dark": bad})).await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY, "text contrast is a hard rule");
    assert_eq!(t.call("PUT", "/projects/cortex/admin/theme", &[("x-uuid", ALICE)], Some(json!({"dark": dark.clone()}))).await.0, StatusCode::FORBIDDEN);

    let t = t.restart().await;
    let (_, v) = t.get("/projects/cortex/theme", &[]).await;
    assert_eq!(v["dark"]["accent"], "#F5F5F7");
    assert!(v["light"].is_null(), "only the stored mode");
}

#[tokio::test]
async fn report_tier_is_computed_from_datasets() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    let (_, v) = t.get("/projects/cortex/reports", &[]).await;
    assert_eq!(v["items"][0]["data_tier"], "sample");
    // One real dataset next to sample ones: hybrid, whatever the order.
    let mut d = dataset("tokens-by-provider", "public");
    d["data_tier"] = json!("real");
    t.service("PUT", "/projects/cortex/admin/reports/token-usage/datasets/tokens-by-provider", d).await;
    let (_, v) = t.get("/projects/cortex/reports/token-usage", &[("x-uuid", ROOT), ("x-access-level", "1")]).await;
    assert_eq!(v["data_tier"], "hybrid");
    // An unknown tier is refused.
    let mut d = dataset("tokens-by-provider", "public");
    d["data_tier"] = json!("live");
    assert_eq!(t.service("PUT", "/projects/cortex/admin/reports/token-usage/datasets/tokens-by-provider", d).await.0, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn domain_project_detail_is_cached_and_never_blocks_the_landing_page() {
    use reports::dal::domain_api::{DomainLink, DomainProjectDetail, DomainStatistic};
    let t = TestApp::new().await;
    t.service("PUT", "/projects/cortex/admin/project", cortex_body(Some(CORTEX_DOMAIN_ID))).await;
    t.domain.details.lock().unwrap().insert(
        "cortex".into(),
        DomainProjectDetail {
            links: vec![DomainLink { link_type: "Live Web App".into(), url: "https://cortex.asodya.com".into(), icon: Some("launch".into()) }],
            statistics: vec![DomainStatistic { name: "Total Commits".into(), value: "71 commits".into() }],
            ..Default::default()
        },
    );
    // First read: no detail yet, and a background refresh starts.
    let (_, v) = t.get("/projects/cortex", &[]).await;
    assert!(v["domain"]["detail"].is_null());
    for _ in 0..50 {
        if t.domain.detail_calls.load(Ordering::SeqCst) > 0 {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;
    }
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    // Next read: the cached detail, without another Domain call.
    let calls = t.domain.detail_calls.load(Ordering::SeqCst);
    let (_, v) = t.get("/catalog", &[]).await;
    let cortex = &v["items"][0];
    assert_eq!(cortex["domain"]["detail"]["links"][0]["url"], "https://cortex.asodya.com");
    assert_eq!(cortex["domain"]["detail"]["statistics"][0]["value"], "71 commits");
    assert_eq!(cortex["domain"]["detail_stale"], false);
    assert_eq!(t.domain.detail_calls.load(Ordering::SeqCst), calls);
    // Expired fresh copy and Domain failing: the last-known detail stays, marked stale.
    use reports::dal::CacheStore;
    t.cache.delete(&format!("domain:detail:fresh:v1:{CORTEX_DOMAIN_ID}")).await;
    t.domain.details.lock().unwrap().clear();
    let (_, v) = t.get("/projects/cortex", &[]).await;
    assert_eq!(v["domain"]["detail_stale"], true);
    assert_eq!(v["domain"]["detail"]["statistics"][0]["name"], "Total Commits");
}
