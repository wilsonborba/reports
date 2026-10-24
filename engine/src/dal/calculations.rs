//! Immutable calculation versions in PostgreSQL (`calculation_versions`).
//! A published version never changes; a dataset card points to one published version.

use serde::{Deserialize, Serialize};
use sqlx::any::AnyRow;
use sqlx::Row;
use utoipa::ToSchema;

use super::sql::{flag_col, json_col, opt_col, Db};
use crate::core::error::ReportError;
use crate::domain::datasets::spec::DatasetSpec;

/// One schema version that a calculation reads.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord, ToSchema)]
pub struct InputRef {
    pub schema: String,
    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct CalculationVersion {
    pub project: String,
    pub calculation_id: String,
    pub version: i64,
    /// draft, published or retired
    pub status: String,
    /// Main input schema (the definition `source`) and its version.
    pub input_schema: Option<String>,
    pub input_schema_version: Option<i64>,
    /// Every schema version the definition reads (source, unions and lookups).
    pub inputs: Vec<InputRef>,
    #[schema(value_type = Object)]
    pub definition: DatasetSpec,
    /// A newer version of an input schema was published after this draft was written.
    pub needs_review: bool,
    pub created_at: String,
    pub published_at: Option<String>,
}

fn select(db: &Db) -> String {
    format!(
        "SELECT project_slug, calculation_id, CAST(version AS BIGINT) AS version, status, \
         {} AS input_schema, CAST(COALESCE(input_schema_version, 0) AS BIGINT) AS input_schema_version, \
         {} AS inputs, {} AS definition, {} AS needs_review, {} AS created_at, {} AS published_at \
         FROM calculation_versions",
        db.opt_text("input_schema"),
        db.text("inputs"),
        db.text("definition"),
        db.flag("needs_review"),
        db.text("created_at"),
        db.opt_text("published_at"),
    )
}

fn from_row(row: &AnyRow) -> Result<CalculationVersion, ReportError> {
    let input_version: i64 = row.try_get("input_schema_version")?;
    Ok(CalculationVersion {
        project: row.try_get("project_slug")?,
        calculation_id: row.try_get("calculation_id")?,
        version: row.try_get("version")?,
        status: row.try_get("status")?,
        input_schema: opt_col(row, "input_schema")?,
        input_schema_version: (input_version > 0).then_some(input_version),
        inputs: json_col(row, "inputs")?,
        definition: json_col(row, "definition")?,
        needs_review: flag_col(row, "needs_review")?,
        created_at: row.try_get("created_at")?,
        published_at: opt_col(row, "published_at")?,
    })
}

pub async fn get(db: &Db, project: &str, id: &str, version: i64) -> Result<Option<CalculationVersion>, ReportError> {
    let sql = format!("{} WHERE project_slug = $1 AND calculation_id = $2 AND version = $3", select(db));
    let row = sqlx::query(&sql).bind(project).bind(id).bind(version).fetch_optional(&db.pool).await?;
    row.as_ref().map(from_row).transpose()
}

pub async fn list(db: &Db, project: &str) -> Result<Vec<CalculationVersion>, ReportError> {
    let sql = format!("{} WHERE project_slug = $1 ORDER BY calculation_id, version", select(db));
    let rows = sqlx::query(&sql).bind(project).fetch_all(&db.pool).await?;
    rows.iter().map(from_row).collect()
}

pub async fn latest_version(db: &Db, project: &str, id: &str) -> Result<Option<i64>, ReportError> {
    let row = sqlx::query(
        "SELECT CAST(COALESCE(MAX(version), 0) AS BIGINT) AS v FROM calculation_versions WHERE project_slug = $1 AND calculation_id = $2",
    )
    .bind(project)
    .bind(id)
    .fetch_one(&db.pool)
    .await?;
    let v: i64 = row.try_get("v")?;
    Ok((v > 0).then_some(v))
}

fn to_json<T: Serialize>(v: &T) -> Result<String, ReportError> {
    serde_json::to_string(v).map_err(|e| ReportError::Internal(e.to_string()))
}

/// Creates a draft or replaces an existing draft. A published or retired version is 409.
pub async fn save_draft(db: &Db, c: &CalculationVersion) -> Result<(), ReportError> {
    if let Some(existing) = get(db, &c.project, &c.calculation_id, c.version).await? {
        if existing.status != "draft" {
            return Err(ReportError::Conflict(format!(
                "calculation {}:{} v{} is {} and cannot change; create version {}",
                c.project,
                c.calculation_id,
                c.version,
                existing.status,
                c.version + 1
            )));
        }
    }
    let sql = format!(
        "INSERT INTO calculation_versions (project_slug, calculation_id, version, status, input_schema, \
         input_schema_version, inputs, definition, needs_review) \
         VALUES ($1, $2, $3, 'draft', $4, $5, {}, {}, $8) \
         ON CONFLICT (project_slug, calculation_id, version) DO UPDATE SET input_schema = EXCLUDED.input_schema, \
         input_schema_version = EXCLUDED.input_schema_version, inputs = EXCLUDED.inputs, \
         definition = EXCLUDED.definition, needs_review = EXCLUDED.needs_review",
        db.json_in(6),
        db.json_in(7)
    );
    sqlx::query(&sql)
        .bind(&c.project)
        .bind(&c.calculation_id)
        .bind(c.version)
        .bind(c.input_schema.clone())
        .bind(c.input_schema_version)
        .bind(to_json(&c.inputs)?)
        .bind(to_json(&c.definition)?)
        .bind(c.needs_review)
        .execute(&db.pool)
        .await?;
    Ok(())
}

/// Publishes a draft with its final input list (immutable from now on).
pub async fn publish(db: &Db, c: &CalculationVersion) -> Result<bool, ReportError> {
    let sql = format!(
        "UPDATE calculation_versions SET status = 'published', published_at = {}, needs_review = FALSE, \
         input_schema = $1, input_schema_version = $2, inputs = {} \
         WHERE project_slug = $4 AND calculation_id = $5 AND version = $6 AND status = 'draft'",
        db.now(),
        db.json_in(3)
    );
    let done = sqlx::query(&sql)
        .bind(c.input_schema.clone())
        .bind(c.input_schema_version)
        .bind(to_json(&c.inputs)?)
        .bind(&c.project)
        .bind(&c.calculation_id)
        .bind(c.version)
        .execute(&db.pool)
        .await?;
    Ok(done.rows_affected() > 0)
}

pub async fn retire(db: &Db, project: &str, id: &str, version: i64) -> Result<bool, ReportError> {
    let done = sqlx::query(
        "UPDATE calculation_versions SET status = 'retired' WHERE project_slug = $1 AND calculation_id = $2 AND version = $3 AND status = 'published'",
    )
    .bind(project)
    .bind(id)
    .bind(version)
    .execute(&db.pool)
    .await?;
    Ok(done.rows_affected() > 0)
}

/// Marks drafts that read an older version of `schema` for review. Returns how many.
pub async fn mark_drafts_for_review(db: &Db, project: &str, schema: &str, new_version: i64) -> Result<u64, ReportError> {
    let done = sqlx::query(
        "UPDATE calculation_versions SET needs_review = TRUE WHERE project_slug = $1 AND status = 'draft' \
         AND input_schema = $2 AND COALESCE(input_schema_version, 0) < $3",
    )
    .bind(project)
    .bind(schema)
    .bind(new_version)
    .execute(&db.pool)
    .await?;
    Ok(done.rows_affected())
}

/// Deletes a version of any status (fixture removal only).
pub async fn delete_version(db: &Db, project: &str, id: &str, version: i64) -> Result<bool, ReportError> {
    let done = sqlx::query("DELETE FROM calculation_versions WHERE project_slug = $1 AND calculation_id = $2 AND version = $3")
        .bind(project)
        .bind(id)
        .bind(version)
        .execute(&db.pool)
        .await?;
    Ok(done.rows_affected() > 0)
}
