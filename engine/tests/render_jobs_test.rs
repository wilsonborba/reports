mod common;

use axum::http::StatusCode;
use common::*;
use serde_json::json;

#[tokio::test]
async fn render_jobs_lifecycle_save_confirmation_expiry_cleanup_and_no_catalog_row() {
    let t = TestApp::new().await;
    t.seed_cortex().await;

    // Publish a visual template first.
    let (st, _) = t
        .service(
            "POST",
            "/projects/cortex/admin/templates",
            json!({
                "template_id": "bar",
                "version": 1,
                "kind": "chart",
                "visual": "bar",
                "title": { "en": "Bar" },
                "slots": [
                    { "slot_name": "category", "role": "dimension", "is_required": true, "min_count": 1, "max_count": 1, "accepted_types": ["string"] },
                    { "slot_name": "value", "role": "measure", "is_required": true, "min_count": 1, "max_count": 1, "accepted_types": ["integer"] }
                ]
            }),
        )
        .await;
    assert_eq!(st, StatusCode::CREATED);
    let (st, _) = t
        .service(
            "POST",
            "/projects/cortex/admin/templates/bar/versions/1/publish",
            json!({}),
        )
        .await;
    assert_eq!(st, StatusCode::OK);

    // Ordinary / anonymous caller is refused.
    let (st, _, _) = t
        .call(
            "POST",
            "/render_jobs",
            &[],
            Some(json!({
                "template_id": "bar",
                "template_version": 1,
                "mapping": { "category": ["x"], "value": ["y"] },
                "rows": [{ "x": "A", "y": 1 }]
            })),
        )
        .await;
    assert_eq!(st, StatusCode::UNAUTHORIZED);

    // Invalid scale (must be 2 or 3) is rejected.
    let (st, _) = t
        .service(
            "POST",
            "/render_jobs",
            json!({
                "template_id": "bar",
                "template_version": 1,
                "mapping": { "category": ["x"], "value": ["y"] },
                "rows": [{ "x": "A", "y": 1 }],
                "scale": 5
            }),
        )
        .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);

    let reports_before: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM reports")
        .fetch_one(&t.state.stores.db.pool)
        .await
        .unwrap();
    let datasets_before: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM datasets")
        .fetch_one(&t.state.stores.db.pool)
        .await
        .unwrap();

    // Trusted service creates validated render job.
    let (st, job) = t
        .service(
            "POST",
            "/render_jobs",
            json!({
                "template_id": "bar",
                "template_version": 1,
                "mapping": { "category": ["x"], "value": ["y"] },
                "rows": [{ "x": "A", "y": 10 }],
                "originating_scope": "certifications:question:q-1",
                "width": 640,
                "height": 360,
                "scale": 2,
                "ttl_seconds": 300
            }),
        )
        .await;
    assert_eq!(st, StatusCode::CREATED, "{job}");
    let job_id = job["job_id"].as_str().unwrap().to_string();
    assert_eq!(job["scale"], 2);
    assert_eq!(job["width"], 640);

    // No catalog row appears for a job.
    let reports_after: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM reports")
        .fetch_one(&t.state.stores.db.pool)
        .await
        .unwrap();
    let datasets_after: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM datasets")
        .fetch_one(&t.state.stores.db.pool)
        .await
        .unwrap();
    assert_eq!(reports_after, reports_before);
    assert_eq!(datasets_after, datasets_before);

    // Read job succeeds.
    let (st, got) = t
        .service("GET", &format!("/render_jobs/{job_id}"), json!({}))
        .await;
    assert_eq!(st, StatusCode::OK, "{got}");
    assert_eq!(got["job_id"], job_id);

    // Delete without confirmed=true returns 409 Conflict and keeps job.
    let (st, _) = t
        .service("DELETE", &format!("/render_jobs/{job_id}"), json!({}))
        .await;
    assert_eq!(st, StatusCode::CONFLICT);
    let (st, _) = t
        .service("GET", &format!("/render_jobs/{job_id}"), json!({}))
        .await;
    assert_eq!(st, StatusCode::OK);

    // Delete with confirmed=true removes job.
    let (st, del) = t
        .service(
            "DELETE",
            &format!("/render_jobs/{job_id}?confirmed=true"),
            json!({}),
        )
        .await;
    assert_eq!(st, StatusCode::OK, "{del}");
    assert_eq!(del["deleted"], true);
    let (st, _) = t
        .service("GET", &format!("/render_jobs/{job_id}"), json!({}))
        .await;
    assert_eq!(st, StatusCode::NOT_FOUND);

    // Expired jobs are cleaned by cleanup.
    let (st, job2) = t
        .service(
            "POST",
            "/render_jobs",
            json!({
                "template_id": "bar",
                "template_version": 1,
                "mapping": { "category": ["x"], "value": ["y"] },
                "rows": [{ "x": "B", "y": 20 }],
                "ttl_seconds": 10
            }),
        )
        .await;
    assert_eq!(st, StatusCode::CREATED);
    let job2_id = job2["job_id"].as_str().unwrap().to_string();
    let exp = job2["expires_at"].as_i64().unwrap();

    let (st, cleaned) = t
        .service(
            "POST",
            &format!("/render_jobs/cleanup?now_secs={}", exp + 1),
            json!({}),
        )
        .await;
    assert_eq!(st, StatusCode::OK, "{cleaned}");
    assert_eq!(cleaned["cleaned"], 1);
    let (st, _) = t
        .service("GET", &format!("/render_jobs/{job2_id}"), json!({}))
        .await;
    assert_eq!(st, StatusCode::NOT_FOUND);
}
