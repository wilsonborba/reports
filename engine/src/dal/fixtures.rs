//! Ownership of sample data (`fixture_manifest`). Only entities written with a fixture
//! header are owned; a later manual write releases the entity, so a fixture delete keeps it.

use sqlx::Row;

use super::sql::Db;
use crate::core::error::ReportError;

/// Entity kinds, in delete order (cards before reports, definitions last).
pub const KINDS: &[&str] = &["dataset", "report", "calculation", "schema"];

pub async fn own(db: &Db, manifest: &str, kind: &str, id: &str) -> Result<(), ReportError> {
    sqlx::query(
        "INSERT INTO fixture_manifest (manifest_id, entity_type, entity_id) VALUES ($1, $2, $3) \
         ON CONFLICT (manifest_id, entity_type, entity_id) DO NOTHING",
    )
    .bind(manifest)
    .bind(kind)
    .bind(id)
    .execute(&db.pool)
    .await?;
    Ok(())
}

/// A manual write: the entity is no longer owned by any fixture manifest.
pub async fn release(db: &Db, kind: &str, id: &str) -> Result<(), ReportError> {
    sqlx::query("DELETE FROM fixture_manifest WHERE entity_type = $1 AND entity_id = $2")
        .bind(kind)
        .bind(id)
        .execute(&db.pool)
        .await?;
    Ok(())
}

/// Records ownership for a fixture write, or releases it for a manual write.
pub async fn track(db: &Db, fixture: Option<&str>, kind: &str, id: &str) -> Result<(), ReportError> {
    match fixture {
        Some(m) => own(db, m, kind, id).await,
        None => release(db, kind, id).await,
    }
}

pub async fn entities(db: &Db, manifest: &str, kind: &str) -> Result<Vec<String>, ReportError> {
    let rows = sqlx::query("SELECT entity_id FROM fixture_manifest WHERE manifest_id = $1 AND entity_type = $2 ORDER BY entity_id")
        .bind(manifest)
        .bind(kind)
        .fetch_all(&db.pool)
        .await?;
    rows.iter().map(|r| r.try_get::<String, _>("entity_id").map_err(ReportError::from)).collect()
}

pub async fn forget(db: &Db, manifest: &str, kind: &str, id: &str) -> Result<(), ReportError> {
    sqlx::query("DELETE FROM fixture_manifest WHERE manifest_id = $1 AND entity_type = $2 AND entity_id = $3")
        .bind(manifest)
        .bind(kind)
        .bind(id)
        .execute(&db.pool)
        .await?;
    Ok(())
}

pub fn report_id(project: &str, report: &str) -> String {
    format!("{project}/{report}")
}

pub fn dataset_id(project: &str, report: &str, dataset: &str) -> String {
    format!("{project}/{report}/{dataset}")
}

pub fn version_id(project: &str, name: &str, version: i64) -> String {
    format!("{project}/{name}/{version}")
}
