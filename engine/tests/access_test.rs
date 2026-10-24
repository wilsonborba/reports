//! Guest showcase, discoverable placeholders, grants and roles.

mod common;

use axum::http::StatusCode;
use common::*;
use serde_json::{json, Value};

async fn setup() -> TestApp {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.ingest(json!([event("a", "ollama", "qwen", 100, 10, true), event("b", "openai", "gpt", 50, 30, false)])).await;
    // latency (signed_in) is discoverable; errors (restricted) is hidden.
    let mut d = dataset("latency-by-model", "signed_in");
    d["discoverable"] = json!(true);
    let (s, v) = t.service("PUT", "/projects/cortex/admin/reports/token-usage/datasets/latency-by-model", d).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    t
}

fn card<'a>(view: &'a Value, id: &str) -> Option<&'a Value> {
    view["cards"].as_array().unwrap().iter().find(|c| c["dataset_id"] == id)
}

#[tokio::test]
async fn guest_showcase_has_public_data_and_safe_skeletons_only() {
    let t = setup().await;
    let (s, v, headers) = t.call("GET", "/projects/cortex/showcase/token-usage", &[], None).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(headers.get("cache-control").unwrap(), "public, max-age=30");
    assert_eq!(v["can_view"], true);

    let public = card(&v, "tokens-by-provider").unwrap();
    assert_eq!(public["can_view"], true);
    assert_eq!(public["rows"].as_array().unwrap().len(), 2);
    assert!(public["skeleton"].is_null());

    let gated = card(&v, "latency-by-model").unwrap();
    assert_eq!(gated["can_view"], false);
    assert!(gated["rows"].is_null() && gated["descriptor"].is_null() && gated["total_rows"].is_null());
    assert_eq!(gated["skeleton"], json!({"layout": "chart", "action": "login"}));
    // Nothing from the gated definition leaks into the text of the response.
    let text = v.to_string();
    assert!(!text.contains("latency_ms") && !text.contains("\"latency\""), "{text}");

    assert!(card(&v, "errors-by-type").is_none(), "hidden card is omitted");
    // Card rows: public 200, gated 401, hidden 404.
    let base = "/projects/cortex/showcase/token-usage/cards";
    assert_eq!(t.get(&format!("{base}/tokens-by-provider"), &[]).await.0, StatusCode::OK);
    assert_eq!(t.get(&format!("{base}/latency-by-model"), &[]).await.0, StatusCode::UNAUTHORIZED);
    assert_eq!(t.get(&format!("{base}/errors-by-type"), &[]).await.0, StatusCode::NOT_FOUND);
    // The guest route ignores identity: a session header does not open gated data.
    assert_eq!(t.get(&format!("{base}/latency-by-model"), &[("x-uuid", ALICE), ("x-access-level", "1")]).await.0, StatusCode::UNAUTHORIZED);
    // The guest list counts only visible cards.
    let (_, list) = t.get("/projects/cortex/reports", &[]).await;
    assert_eq!(list["items"][0]["dataset_count"], 2);
}

#[tokio::test]
async fn discoverable_gated_report_shows_placeholders_without_period_or_data() {
    let t = setup().await;
    let (s, _) = t.service("PUT", "/projects/cortex/admin/reports/token-usage", json!({
        "title": {"en": "Token Usage"}, "visibility": "signed_in", "discoverable": true,
        "metadata": {"period_source": {"collection": "telemetry_event", "field": "day"}}
    })).await;
    assert_eq!(s, StatusCode::OK);
    let (s, v) = t.get("/projects/cortex/showcase/token-usage", &[]).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(v["can_view"], false);
    assert!(v["period"].is_null());
    let cards = v["cards"].as_array().unwrap();
    assert_eq!(cards.len(), 1, "only the discoverable card: {cards:?}");
    assert!(cards[0]["rows"].is_null());
    // The guest list shows it as a placeholder.
    let (_, list) = t.get("/projects/cortex/reports", &[]).await;
    assert_eq!(list["items"][0]["can_view"], false);
    assert!(list["items"][0]["period"].is_null());
    // Session routes: guest 401, viewer reads it.
    assert_eq!(t.get("/projects/cortex/reports/token-usage", &[]).await.0, StatusCode::UNAUTHORIZED);
    let (s, v) = t.get("/projects/cortex/reports/token-usage", &[("x-uuid", ALICE)]).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(v["datasets"].as_array().unwrap().len(), 2, "restricted hidden card stays omitted");
}

#[tokio::test]
async fn grants_open_one_card_or_one_report_and_revoke_takes_effect() {
    let t = setup().await;
    let url = "/projects/cortex/reports/token-usage/datasets/errors-by-type";
    assert_eq!(t.get(url, &[("x-uuid", ALICE)]).await.0, StatusCode::NOT_FOUND);

    let (s, grant) = t.service("POST", "/admin/projects/cortex/grants", json!({"user_uuid": ALICE, "report": "token-usage", "card_id": "errors-by-type"})).await;
    assert_eq!(s, StatusCode::CREATED, "{grant}");
    let (s, again) = t.service("POST", "/admin/projects/cortex/grants", json!({"user_uuid": ALICE, "report": "token-usage", "card_id": "errors-by-type"})).await;
    assert_eq!(s, StatusCode::CREATED);
    assert_eq!(again["id"], grant["id"], "the same grant twice is one grant");

    assert_eq!(t.get(url, &[("x-uuid", ALICE)]).await.0, StatusCode::OK);
    assert_eq!(t.get(url, &[("x-uuid", BOB)]).await.0, StatusCode::NOT_FOUND, "other users stay out");
    assert_eq!(t.get(url, &[]).await.0, StatusCode::NOT_FOUND, "guests never use grants");

    let (_, list) = t.get("/admin/projects/cortex/grants", &[("x-reports-service-key", SERVICE_KEY)]).await;
    assert_eq!(list.as_array().unwrap().len(), 1);

    let id = grant["id"].as_str().unwrap();
    let (s, _, _) = t.call("DELETE", &format!("/admin/projects/fsm/grants/{id}"), &[("x-reports-service-key", SERVICE_KEY)], None).await;
    assert_eq!(s, StatusCode::FORBIDDEN, "a grant of another project");
    let (s, _, _) = t.call("DELETE", &format!("/admin/projects/cortex/grants/{id}"), &[("x-reports-service-key", SERVICE_KEY)], None).await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    assert_eq!(t.get(url, &[("x-uuid", ALICE)]).await.0, StatusCode::NOT_FOUND, "revoked on the next request");

    // A report grant opens a restricted report and every card in it.
    t.service("PUT", "/projects/cortex/admin/reports/token-usage", json!({"title": {"en": "Token Usage"}, "visibility": "restricted"})).await;
    let (s, _) = t.service("POST", "/admin/projects/cortex/grants", json!({"user_uuid": ALICE, "report": "token-usage"})).await;
    assert_eq!(s, StatusCode::CREATED);
    let (s, v) = t.get("/projects/cortex/reports/token-usage", &[("x-uuid", ALICE)]).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert!(v["datasets"].as_array().unwrap().iter().all(|d| d["can_view"] == true));
    let (_, mine) = t.get("/me/projects/cortex/reports", &[("x-uuid", ALICE)]).await;
    assert_eq!(mine["total"], 1);
    let (_, bobs) = t.get("/me/projects/cortex/reports", &[("x-uuid", BOB)]).await;
    assert_eq!(bobs["total"], 0, "hidden for users without a grant");
}

#[tokio::test]
async fn grant_and_role_admin_rules() {
    let t = setup().await;
    t.make_project_admin(BOB, "cortex").await;
    // A project admin manages grants of its project only, on the session route.
    let body = json!({"user_uuid": ALICE, "report": "token-usage"});
    assert_eq!(t.call("POST", "/admin/projects/cortex/grants", &[("x-uuid", BOB)], Some(body.clone())).await.0, StatusCode::CREATED);
    assert_eq!(t.call("POST", "/admin/projects/fsm/grants", &[("x-uuid", BOB)], Some(body.clone())).await.0, StatusCode::FORBIDDEN);
    assert_eq!(t.call("POST", "/admin/projects/cortex/grants", &[("x-uuid", ALICE)], Some(body)).await.0, StatusCode::FORBIDDEN);
    // Unknown targets and bad UUIDs.
    assert_eq!(t.service("POST", "/admin/projects/cortex/grants", json!({"user_uuid": ALICE, "report": "nope"})).await.0, StatusCode::NOT_FOUND);
    assert_eq!(t.service("POST", "/admin/projects/cortex/grants", json!({"user_uuid": "bob", "report": "token-usage"})).await.0, StatusCode::BAD_REQUEST);
    // Roles need a super admin; the session super admin works.
    let role = json!({"is_project_admin": true});
    assert_eq!(t.call("PUT", &format!("/projects/cortex/admin/roles/{ALICE}"), &[("x-uuid", BOB)], Some(role.clone())).await.0, StatusCode::FORBIDDEN);
    assert_eq!(t.call("PUT", &format!("/projects/cortex/admin/roles/{ALICE}"), &[("x-uuid", ROOT), ("x-access-level", "1")], Some(role)).await.0, StatusCode::OK);
    let (_, roles) = t.get("/admin/projects/cortex/roles", &[("x-uuid", BOB)]).await;
    assert_eq!(roles.as_array().unwrap().len(), 2);
    // Deleting a report removes its grants.
    let (s, _, _) = t.call("DELETE", "/projects/cortex/admin/reports/token-usage", &[("x-reports-service-key", SERVICE_KEY)], None).await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (_, list) = t.get("/admin/projects/cortex/grants", &[("x-reports-service-key", SERVICE_KEY)]).await;
    assert!(list.as_array().unwrap().is_empty());
}

#[tokio::test]
async fn cached_results_never_cross_users_or_access_classes() {
    let t = setup().await;
    let restricted = "/projects/cortex/reports/token-usage/datasets/errors-by-type";
    let gated = "/projects/cortex/reports/token-usage/datasets/latency-by-model";
    let root = [("x-uuid", ROOT), ("x-access-level", "1")];

    // The super admin reads the restricted card twice: the second read is a cache hit.
    let (s, first) = t.get(restricted, &root).await;
    assert_eq!(s, StatusCode::OK, "{first}");
    let calculations = t.state.datasets.counters().calculations;
    assert_eq!(t.get(restricted, &root).await.1["rows"], first["rows"]);
    assert_eq!(t.state.datasets.counters().calculations, calculations, "second read is a cache hit");
    assert!(!t.cache.is_empty(), "the result is in the cache");

    // The cached rows never answer a viewer, a guest or a faked header.
    for headers in [vec![("x-uuid", ALICE)], vec![], vec![("x-access-level", "1")], vec![("x-uuid", ALICE), ("x-project-admin", "true")]] {
        let (s, v) = t.get(restricted, &headers).await;
        assert_ne!(s, StatusCode::OK, "{headers:?}");
        assert!(v.get("rows").is_none(), "{headers:?}: {v}");
    }

    // A signed-in card read by a viewer is cached, and a guest still gets 401 without rows.
    assert_eq!(t.get(gated, &[("x-uuid", ALICE)]).await.0, StatusCode::OK);
    let (s, v) = t.get(gated, &[]).await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);
    assert!(v.get("rows").is_none());
    let (s, v) = t.get("/projects/cortex/showcase/token-usage/cards/latency-by-model", &[]).await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);
    assert!(v.get("rows").is_none());
}
