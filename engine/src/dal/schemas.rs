//! Versioned input schemas in PostgreSQL (`schema_versions`, `schema_fields`).
//! A published version never changes. A new structure needs a new version.

use serde::{Deserialize, Serialize};
use sqlx::any::AnyRow;
use sqlx::Row;
use utoipa::ToSchema;

use super::sql::{flag_col, opt_col, Db};
use crate::core::error::ReportError;
use crate::domain::guardrail::SchemaField;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
pub struct SchemaVersion {
    pub project: String,
    pub schema_name: String,
    pub version: i64,
    /// draft, published or retired
    pub status: String,
    #[serde(default)]
    pub description: Option<String>,
    pub fields: Vec<SchemaField>,
    #[serde(default)]
    pub created_at: String,
    #[serde(default)]
    pub published_at: Option<String>,
}

fn head_from(row: &AnyRow) -> Result<SchemaVersion, ReportError> {
    Ok(SchemaVersion {
        project: row.try_get("project_slug")?,
        schema_name: row.try_get("schema_name")?,
        version: row.try_get("version")?,
        status: row.try_get("status")?,
        description: opt_col(row, "description")?,
        fields: Vec::new(),
        created_at: row.try_get("created_at")?,
        published_at: opt_col(row, "published_at")?,
    })
}

fn head_select(db: &Db) -> String {
    format!(
        "SELECT project_slug, schema_name, CAST(version AS BIGINT) AS version, status, {} AS description, \
         {} AS created_at, {} AS published_at FROM schema_versions",
        db.opt_text("description"),
        db.text("created_at"),
        db.opt_text("published_at"),
    )
}

async fn load_fields(db: &Db, s: &mut SchemaVersion) -> Result<(), ReportError> {
    let sql = format!(
        "SELECT field_path, field_type, {} AS is_required, {} AS description FROM schema_fields \
         WHERE project_slug = $1 AND schema_name = $2 AND version = $3 ORDER BY field_path",
        db.flag("is_required"),
        db.opt_text("description")
    );
    let rows = sqlx::query(&sql)
        .bind(&s.project)
        .bind(&s.schema_name)
        .bind(s.version)
        .fetch_all(&db.pool)
        .await?;
    s.fields = rows
        .iter()
        .map(|r| {
            Ok(SchemaField {
                path: r.try_get("field_path")?,
                field_type: r.try_get("field_type")?,
                required: flag_col(r, "is_required")?,
                description: opt_col(r, "description")?,
            })
        })
        .collect::<Result<_, ReportError>>()?;
    Ok(())
}

pub async fn get(db: &Db, project: &str, name: &str, version: i64) -> Result<Option<SchemaVersion>, ReportError> {
    let sql = format!("{} WHERE project_slug = $1 AND schema_name = $2 AND version = $3", head_select(db));
    let row = sqlx::query(&sql).bind(project).bind(name).bind(version).fetch_optional(&db.pool).await?;
    match row {
        Some(r) => {
            let mut s = head_from(&r)?;
            load_fields(db, &mut s).await?;
            Ok(Some(s))
        }
        None => Ok(None),
    }
}

/// Every version of every schema of a project, with fields.
pub async fn list(db: &Db, project: &str) -> Result<Vec<SchemaVersion>, ReportError> {
    let sql = format!("{} WHERE project_slug = $1 ORDER BY schema_name, version", head_select(db));
    let rows = sqlx::query(&sql).bind(project).fetch_all(&db.pool).await?;
    let mut out = Vec::with_capacity(rows.len());
    for r in &rows {
        let mut s = head_from(r)?;
        load_fields(db, &mut s).await?;
        out.push(s);
    }
    Ok(out)
}

/// Highest version number of a schema (published or not).
pub async fn latest_version(db: &Db, project: &str, name: &str) -> Result<Option<i64>, ReportError> {
    let row = sqlx::query(
        "SELECT CAST(COALESCE(MAX(version), 0) AS BIGINT) AS v FROM schema_versions WHERE project_slug = $1 AND schema_name = $2",
    )
    .bind(project)
    .bind(name)
    .fetch_one(&db.pool)
    .await?;
    let v: i64 = row.try_get("v")?;
    Ok((v > 0).then_some(v))
}

/// Writes a draft version: creates it, or replaces the fields of an existing draft.
/// A published or retired version cannot change (409).
pub async fn save_draft(db: &Db, s: &SchemaVersion) -> Result<(), ReportError> {
    if let Some(existing) = get(db, &s.project, &s.schema_name, s.version).await? {
        if existing.status != "draft" {
            return Err(ReportError::Conflict(format!(
                "schema {}:{} v{} is {} and cannot change; create version {}",
                s.project,
                s.schema_name,
                s.version,
                existing.status,
                s.version + 1
            )));
        }
    }
    let mut tx = db.pool.begin().await?;
    sqlx::query(
        "INSERT INTO schema_versions (project_slug, schema_name, version, status, description) \
         VALUES ($1, $2, $3, 'draft', $4) \
         ON CONFLICT (project_slug, schema_name, version) DO UPDATE SET description = EXCLUDED.description",
    )
    .bind(&s.project)
    .bind(&s.schema_name)
    .bind(s.version)
    .bind(&s.description)
    .execute(&mut *tx)
    .await?;
    sqlx::query("DELETE FROM schema_fields WHERE project_slug = $1 AND schema_name = $2 AND version = $3")
        .bind(&s.project)
        .bind(&s.schema_name)
        .bind(s.version)
        .execute(&mut *tx)
        .await?;
    for f in &s.fields {
        sqlx::query(
            "INSERT INTO schema_fields (project_slug, schema_name, version, field_path, field_type, is_required, description) \
             VALUES ($1, $2, $3, $4, $5, $6, $7)",
        )
        .bind(&s.project)
        .bind(&s.schema_name)
        .bind(s.version)
        .bind(&f.path)
        .bind(&f.field_type)
        .bind(f.required)
        .bind(&f.description)
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(())
}

/// Changes the status of a version: draft to published, or published to retired.
pub async fn set_status(db: &Db, project: &str, name: &str, version: i64, from: &str, to: &str) -> Result<bool, ReportError> {
    let published = if to == "published" {
        format!(", published_at = {}", db.now())
    } else {
        String::new()
    };
    let sql = format!(
        "UPDATE schema_versions SET status = $1{published} \
         WHERE project_slug = $2 AND schema_name = $3 AND version = $4 AND status = $5"
    );
    let done = sqlx::query(&sql)
        .bind(to)
        .bind(project)
        .bind(name)
        .bind(version)
        .bind(from)
        .execute(&db.pool)
        .await?;
    Ok(done.rows_affected() > 0)
}

/// Deletes a draft version. Published versions stay for historical records.
pub async fn delete_draft(db: &Db, project: &str, name: &str, version: i64) -> Result<bool, ReportError> {
    let done = sqlx::query(
        "DELETE FROM schema_versions WHERE project_slug = $1 AND schema_name = $2 AND version = $3 AND status = 'draft'",
    )
    .bind(project)
    .bind(name)
    .bind(version)
    .execute(&db.pool)
    .await?;
    Ok(done.rows_affected() > 0)
}

/// Deletes a version of any status (fixture removal only; records stay in CouchDB until
/// their own fixture delete).
pub async fn delete_version(db: &Db, project: &str, name: &str, version: i64) -> Result<bool, ReportError> {
    let done = sqlx::query("DELETE FROM schema_versions WHERE project_slug = $1 AND schema_name = $2 AND version = $3")
        .bind(project)
        .bind(name)
        .bind(version)
        .execute(&db.pool)
        .await?;
    Ok(done.rows_affected() > 0)
}
