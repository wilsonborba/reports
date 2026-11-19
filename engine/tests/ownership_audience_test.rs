mod common;

use axum::http::StatusCode;
use common::*;
use reports::dal::catalog::{self, DatasetRecord, ReportMetadata, ReportRecord};
use reports::domain::auth::{ControlAuthority, Viewer, ViewerScope};
use reports::domain::datasets::spec::{DataTier, I18nText};
use reports::domain::reports::{dataset_access, report_access, Access};
use serde_json::json;

const USER_A: &str = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const USER_B: &str = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

#[tokio::test]
async fn personal_ownership_isolation_and_control_authority() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    let stores = &t.state.stores;

    let rep_a = ReportRecord {
        project: "cortex".into(),
        slug: "user-a-personal".into(),
        title: I18nText::from([("en".into(), "User A Personal".into())]),
        description: I18nText::default(),
        metadata: ReportMetadata::default(),
        visibility: "restricted".into(),
        discoverable: false,
        updated_at: String::new(),
        source_app: "annotations".into(),
        owner_id: USER_A.into(),
        control_authority: "user_owned".into(),
        audience: "personal".into(),
    };
    catalog::upsert_report(&stores.db, &rep_a).await.unwrap();
    let loaded_a = catalog::get_report(&stores.db, "cortex", "user-a-personal")
        .await
        .unwrap()
        .unwrap();

    let ds_a = DatasetRecord {
        project: "cortex".into(),
        report_slug: "user-a-personal".into(),
        dataset_id: "d1".into(),
        data_tier: DataTier::Real,
        calculation_id: "calc-1".into(),
        calculation_version: 1,
        spec: Default::default(),
        visibility: "restricted".into(),
        discoverable: false,
        source_app: "annotations".into(),
        owner_id: USER_A.into(),
        control_authority: "user_owned".into(),
        audience: "personal".into(),
    };

    let scope_a = ViewerScope::resolve(
        &stores.db,
        Viewer::User {
            uuid: USER_A.into(),
            super_admin: false,
        },
    )
    .await
    .unwrap();
    let scope_b = ViewerScope::resolve(
        &stores.db,
        Viewer::User {
            uuid: USER_B.into(),
            super_admin: false,
        },
    )
    .await
    .unwrap();
    let scope_admin = ViewerScope::resolve(
        &stores.db,
        Viewer::User {
            uuid: "cccccccc-cccc-4ccc-8ccc-cccccccccccc".into(),
            super_admin: true,
        },
    )
    .await
    .unwrap();

    let acc_a = report_access(&scope_a, &loaded_a);
    assert_eq!(acc_a, Access::Readable);
    assert_eq!(
        dataset_access(&scope_a, &loaded_a, acc_a, &ds_a),
        Access::Readable
    );

    let acc_b = report_access(&scope_b, &loaded_a);
    assert_eq!(acc_b, Access::Hidden);
    assert_eq!(
        dataset_access(&scope_b, &loaded_a, acc_b, &ds_a),
        Access::Hidden
    );

    assert_eq!(report_access(&scope_admin, &loaded_a), Access::Readable);

    // App-controlled data: User A can view it if owner, but CANNOT publish it.
    assert!(scope_a.can_publish_owned("cortex", USER_A, ControlAuthority::UserOwned));
    assert!(!scope_a.can_publish_owned("cortex", USER_A, ControlAuthority::AppControlled));
    assert!(scope_admin.can_publish_owned("cortex", USER_A, ControlAuthority::AppControlled));
}

#[tokio::test]
async fn http_personal_cache_isolation_and_route_visibility_change_invalidation() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    t.ingest(json!([
        event("a", "ollama", "qwen", 100, 10, true),
        event("b", "openai", "gpt", 50, 30, false)
    ]))
    .await;

    // Create a Personal report and dataset owned by USER_A through the HTTP admin routes.
    let (st, _) = t
        .service(
            "PUT",
            "/projects/cortex/admin/reports/personal-a",
            json!({
                "title": { "en": "Personal A" },
                "visibility": "restricted",
                "audience": "personal",
                "owner_id": USER_A,
                "discoverable": false
            }),
        )
        .await;
    assert_eq!(st, StatusCode::OK);

    let (st, _) = t
        .service(
            "PUT",
            "/projects/cortex/admin/reports/personal-a/datasets/latency-by-model",
            json!({
                "data_tier": "real",
                "calculation_id": "latency-by-model",
                "calculation_version": 1,
                "visibility": "restricted",
                "audience": "personal",
                "owner_id": USER_A,
                "discoverable": false
            }),
        )
        .await;
    assert_eq!(st, StatusCode::OK);

    // 1. User A requests their Personal report and dataset via HTTP (filling the cache).
    let (st_a_rep, rep_a, _) = t
        .call(
            "GET",
            "/projects/cortex/reports/personal-a",
            &[("x-uuid", USER_A)],
            None,
        )
        .await;
    assert_eq!(st_a_rep, StatusCode::OK);
    assert!(rep_a.to_string().contains("personal-a"));

    let (st_a_ds, ds_a, _) = t
        .call(
            "GET",
            "/projects/cortex/reports/personal-a/datasets/latency-by-model",
            &[("x-uuid", USER_A)],
            None,
        )
        .await;
    assert_eq!(st_a_ds, StatusCode::OK);
    assert!(!ds_a["rows"].as_array().unwrap().is_empty());

    // User B requests the exact same HTTP paths and gets 404 (never receives A's Personal data or A's cache).
    let (st_b_rep, _, _) = t
        .call(
            "GET",
            "/projects/cortex/reports/personal-a",
            &[("x-uuid", USER_B)],
            None,
        )
        .await;
    assert_eq!(st_b_rep, StatusCode::NOT_FOUND);

    let (st_b_ds, _, _) = t
        .call(
            "GET",
            "/projects/cortex/reports/personal-a/datasets/latency-by-model",
            &[("x-uuid", USER_B)],
            None,
        )
        .await;
    assert_eq!(st_b_ds, StatusCode::NOT_FOUND);

    // 2. Visibility change through the real route takes effect on the very next request (including caches).
    let (st, _) = t
        .service(
            "PUT",
            "/projects/cortex/admin/reports/personal-a",
            json!({
                "title": { "en": "Personal A" },
                "visibility": "public",
                "audience": "public",
                "owner_id": USER_A,
                "discoverable": true
            }),
        )
        .await;
    assert_eq!(st, StatusCode::OK);
    let (st, _) = t
        .service(
            "PUT",
            "/projects/cortex/admin/reports/personal-a/datasets/latency-by-model",
            json!({
                "data_tier": "real",
                "calculation_id": "latency-by-model",
                "calculation_version": 1,
                "visibility": "public",
                "audience": "public",
                "owner_id": USER_A,
                "discoverable": true
            }),
        )
        .await;
    assert_eq!(st, StatusCode::OK);

    // Very next request: User B can now read both the report and dataset (and fills public cache).
    let (st_b_rep_pub, _, _) = t
        .call(
            "GET",
            "/projects/cortex/reports/personal-a",
            &[("x-uuid", USER_B)],
            None,
        )
        .await;
    assert_eq!(st_b_rep_pub, StatusCode::OK);
    let (st_b_ds_pub, ds_b_pub, _) = t
        .call(
            "GET",
            "/projects/cortex/reports/personal-a/datasets/latency-by-model",
            &[("x-uuid", USER_B)],
            None,
        )
        .await;
    assert_eq!(st_b_ds_pub, StatusCode::OK);
    assert!(!ds_b_pub["rows"].as_array().unwrap().is_empty());

    // Change visibility back to Personal via the real route: very next request refuses User B even though public was cached.
    let (st, _) = t
        .service(
            "PUT",
            "/projects/cortex/admin/reports/personal-a",
            json!({
                "title": { "en": "Personal A" },
                "visibility": "restricted",
                "audience": "personal",
                "owner_id": USER_A,
                "discoverable": false
            }),
        )
        .await;
    assert_eq!(st, StatusCode::OK);

    let (st_b_after, _, _) = t
        .call(
            "GET",
            "/projects/cortex/reports/personal-a/datasets/latency-by-model",
            &[("x-uuid", USER_B)],
            None,
        )
        .await;
    assert_eq!(st_b_after, StatusCode::NOT_FOUND);

    // User A still reads their own Personal dataset.
    let (st_a_after, _, _) = t
        .call(
            "GET",
            "/projects/cortex/reports/personal-a/datasets/latency-by-model",
            &[("x-uuid", USER_A)],
            None,
        )
        .await;
    assert_eq!(st_a_after, StatusCode::OK);
}
