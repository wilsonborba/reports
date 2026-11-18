mod common;

use common::*;
use reports::dal::catalog::{self, DatasetRecord, ReportMetadata, ReportRecord};
use reports::domain::auth::{ControlAuthority, Viewer, ViewerScope};
use reports::domain::datasets::spec::{DataTier, I18nText};
use reports::domain::reports::{dataset_access, report_access, Access};

#[tokio::test]
async fn personal_ownership_isolation_control_authority_and_cache_invalidation() {
    let t = TestApp::new().await;
    t.seed_cortex().await;
    let stores = &t.state.stores;

    // User A owns a Personal report and dataset.
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
        owner_id: "user-a".into(),
        control_authority: "user_owned".into(),
        audience: "personal".into(),
    };
    catalog::upsert_report(&stores.db, &rep_a).await.unwrap();
    let loaded_a = catalog::get_report(&stores.db, "cortex", "user-a-personal")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(loaded_a.owner_id, "user-a");
    assert_eq!(loaded_a.source_app, "annotations");
    assert_eq!(loaded_a.audience, "personal");

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
        owner_id: "user-a".into(),
        control_authority: "user_owned".into(),
        audience: "personal".into(),
    };

    let scope_a = ViewerScope::resolve(
        &stores.db,
        Viewer::User {
            uuid: "user-a".into(),
            super_admin: false,
        },
    )
    .await
    .unwrap();
    let scope_b = ViewerScope::resolve(
        &stores.db,
        Viewer::User {
            uuid: "user-b".into(),
            super_admin: false,
        },
    )
    .await
    .unwrap();
    let scope_admin = ViewerScope::resolve(
        &stores.db,
        Viewer::User {
            uuid: "admin-1".into(),
            super_admin: true,
        },
    )
    .await
    .unwrap();

    // User A and Admin can read User A's Personal report and dataset; User B CANNOT.
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
    assert!(scope_a.can_publish_owned("cortex", "user-a", ControlAuthority::UserOwned));
    assert!(!scope_a.can_publish_owned("cortex", "user-a", ControlAuthority::AppControlled));
    assert!(scope_admin.can_publish_owned("cortex", "user-a", ControlAuthority::AppControlled));

    // Cache invalidation on visibility change.
    stores.cache.set("k-test", "cached-val", 60).await;
    stores
        .cache
        .tag("report:cortex:user-a-personal", "k-test", 60)
        .await;
    assert!(stores.cache.get("k-test").await.is_some());
    t.state
        .datasets
        .invalidate_visibility_change("cortex", "user-a-personal")
        .await;
    assert!(stores.cache.get("k-test").await.is_none());
}
