//! Replays the exact requests of scripts/populate_fake_data.sh (its --dump output) against
//! the test engine, so the sample definitions are validated before they reach production.

mod common;

use axum::http::StatusCode;
use common::*;
use serde_json::{json, Value};

fn dump() -> Option<Vec<Value>> {
    let file = tempfile::NamedTempFile::new().unwrap();
    let script = concat!(env!("CARGO_MANIFEST_DIR"), "/../scripts/population/populate.py");
    let status = std::process::Command::new("python3")
        .arg(script)
        .arg("--dump")
        .arg(file.path())
        .stdout(std::process::Stdio::null())
        .status()
        .ok()?;
    assert!(status.success(), "populate.py --dump failed");
    serde_json::from_str(&std::fs::read_to_string(file.path()).unwrap()).ok()
}

#[tokio::test]
async fn sample_data_scripts_load_cleanly_and_every_card_answers() {
    let Some(requests) = dump() else {
        eprintln!("python3 is not available; skipping");
        return;
    };
    let t = TestApp::new().await;
    for slug in ["domain", "certifications", "cortex", "autodroid", "fsm"] {
        let (s, v) = t.service("PUT", &format!("/projects/{slug}/admin/project"), json!({"name": {"en": slug, "pt-BR": slug, "th": slug}})).await;
        assert_eq!(s, StatusCode::OK, "{v}");
    }
    let mut cards = Vec::new();
    for r in &requests {
        let method = r["method"].as_str().unwrap();
        let path = r["path"].as_str().unwrap();
        if method == "GET" {
            continue;
        }
        let mut headers = vec![("x-reports-service-key", SERVICE_KEY)];
        let fixture = r["fixture"].as_str().map(str::to_string);
        if let Some(f) = &fixture {
            headers.push(("x-reports-fixture", f.as_str()));
        }
        let body = if r["body"].is_null() { None } else { Some(r["body"].clone()) };
        let (s, v, _) = t.call(method, path, &headers, body).await;
        assert!(s.is_success(), "{method} {path} -> {s}: {v}");
        if path.contains("/datasets/") {
            cards.push(path.replace("/admin/reports/", "/reports/"));
        }
    }
    assert_eq!(cards.len(), 30);
    // Every card calculates for the super admin and returns rows.
    let root = [("x-uuid", ROOT), ("x-access-level", "1")];
    for c in &cards {
        let (s, v) = t.get(c, &root).await;
        assert_eq!(s, StatusCode::OK, "{c}: {v}");
        assert!(!v["rows"].as_array().unwrap().is_empty(), "{c} has no rows");
        assert_eq!(v["data_tier"], "sample");
    }
    // Guests see at least one public chart in every project.
    for slug in ["domain", "certifications", "cortex", "autodroid", "fsm"] {
        let (_, list) = t.get(&format!("/projects/{slug}/reports"), &[]).await;
        let first = list["items"][0]["slug"].as_str().unwrap().to_string();
        let (_, show) = t.get(&format!("/projects/{slug}/showcase/{first}"), &[]).await;
        assert!(show["cards"].as_array().unwrap().iter().any(|c| c["can_view"] == true), "{slug}: {show}");
    }
    // A second run writes nothing new: same keys, same definitions.
    let before = t.docs.len();
    for r in requests.iter().filter(|r| r["path"].as_str().unwrap().contains("/ingest/")) {
        let (s, v, _) = t.call("POST", r["path"].as_str().unwrap(), &[("x-reports-service-key", SERVICE_KEY)], Some(r["body"].clone())).await;
        assert_eq!(s, StatusCode::CREATED);
        assert_eq!(v["created"], 0, "{v}");
    }
    assert_eq!(t.docs.len(), before);
}
