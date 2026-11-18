//! Immutable calculation versions in PostgreSQL (`calculation_versions`).
//! A published version never changes; a dataset card points to one published version.

use serde::{Deserialize, Serialize};
use sqlx::any::AnyRow;
use sqlx::Row;
use utoipa::ToSchema;

use super::sql::{flag_col, opt, opt_col, opt_num, Db};
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
         {} AS needs_review, {} AS created_at, {} AS published_at \
         FROM calculation_versions",
        db.opt_text("input_schema"),
        db.flag("needs_review"),
        db.text("created_at"),
        db.opt_text("published_at"),
    )
}

async fn from_row(db: &Db, row: &AnyRow) -> Result<CalculationVersion, ReportError> {
    let input_version: i64 = row.try_get("input_schema_version")?;
    Ok(CalculationVersion {
        project: row.try_get("project_slug")?,
        calculation_id: row.try_get("calculation_id")?,
        version: row.try_get("version")?,
        status: row.try_get("status")?,
        input_schema: opt_col(row, "input_schema")?,
        input_schema_version: (input_version > 0).then_some(input_version),
        inputs: load_inputs(
            db,
            &row.try_get::<String, _>("project_slug")?,
            &row.try_get::<String, _>("calculation_id")?,
            row.try_get("version")?,
        )
        .await?,
        definition: load_definition(
            db,
            &row.try_get::<String, _>("project_slug")?,
            &row.try_get::<String, _>("calculation_id")?,
            row.try_get("version")?,
        )
        .await?,
        needs_review: flag_col(row, "needs_review")?,
        created_at: row.try_get("created_at")?,
        published_at: opt_col(row, "published_at")?,
    })
}

pub async fn get(db: &Db, project: &str, id: &str, version: i64) -> Result<Option<CalculationVersion>, ReportError> {
    let sql = format!("{} WHERE project_slug = $1 AND calculation_id = $2 AND version = $3", select(db));
    let row = sqlx::query(&sql).bind(project).bind(id).bind(version).fetch_optional(&db.pool).await?;
    match row {
        Some(r) => Ok(Some(from_row(db, &r).await?)),
        None => Ok(None),
    }
}

pub async fn list(db: &Db, project: &str) -> Result<Vec<CalculationVersion>, ReportError> {
    let sql = format!("{} WHERE project_slug = $1 ORDER BY calculation_id, version", select(db));
    let rows = sqlx::query(&sql).bind(project).fetch_all(&db.pool).await?;
    let mut out = Vec::new();
    for r in &rows {
        out.push(from_row(db, r).await?);
    }
    Ok(out)
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

pub async fn load_definition(db: &Db, project: &str, id: &str, version: i64) -> Result<DatasetSpec, ReportError> {
    let v = super::normalized::read(db, &super::normalized::Key { project, calculation: id, version }).await?;
    if v.is_null() {
        return Ok(DatasetSpec::default());
    }
    serde_json::from_value(v).map_err(|e| ReportError::Database(e.to_string()))
}
async fn load_inputs(db: &Db, project: &str, id: &str, version: i64) -> Result<Vec<InputRef>, ReportError> {
    let rows=sqlx::query("SELECT schema_name,CAST(schema_version AS BIGINT) AS schema_version FROM calculation_inputs WHERE project_slug=$1 AND calculation_id=$2 AND version=$3 ORDER BY position").bind(project).bind(id).bind(version).fetch_all(&db.pool).await?;
    rows.iter()
        .map(|r| Ok(InputRef { schema: r.try_get("schema_name")?, version: r.try_get("schema_version")? }))
        .collect()
}
async fn write_inputs(tx: &mut sqlx::Transaction<'_, sqlx::Any>, c: &CalculationVersion) -> Result<(), ReportError> {
    sqlx::query("DELETE FROM calculation_inputs WHERE project_slug=$1 AND calculation_id=$2 AND version=$3")
        .bind(&c.project)
        .bind(&c.calculation_id)
        .bind(c.version)
        .execute(&mut **tx)
        .await?;
    for (i, input) in c.inputs.iter().enumerate() {
        sqlx::query("INSERT INTO calculation_inputs(project_slug,calculation_id,version,position,schema_name,schema_version) VALUES ($1,$2,$3,$4,$5,$6)").bind(&c.project).bind(&c.calculation_id).bind(c.version).bind(i as i64).bind(&input.schema).bind(input.version).execute(&mut **tx).await?;
    }
    Ok(())
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
    let mut tx = db.pool.begin().await?;
    let sql=format!("INSERT INTO calculation_versions(project_slug,calculation_id,version,status,input_schema,input_schema_version,needs_review) VALUES ($1,$2,$3,'draft',{}, {},$6) ON CONFLICT(project_slug,calculation_id,version) DO UPDATE SET input_schema=EXCLUDED.input_schema,input_schema_version=EXCLUDED.input_schema_version,needs_review=EXCLUDED.needs_review WHERE calculation_versions.status='draft'",db.opt_in(4),db.opt_num_in(5));
    let done = sqlx::query(&sql)
        .bind(&c.project)
        .bind(&c.calculation_id)
        .bind(c.version)
        .bind(opt(&c.input_schema))
        .bind(opt_num(c.input_schema_version))
        .bind(c.needs_review)
        .execute(&mut *tx)
        .await?;
    if done.rows_affected() == 0 {
        return Err(ReportError::Conflict("calculation is no longer a draft".into()));
    }
    write_inputs(&mut tx, c).await?;
    let value = serde_json::to_value(&c.definition).map_err(|e| ReportError::Internal(e.to_string()))?;
    super::normalized::write(
        &mut tx,
        &super::normalized::Key { project: &c.project, calculation: &c.calculation_id, version: c.version },
        &value,
    )
    .await?;
    tx.commit().await?;
    Ok(())
}

/// Publishes a draft with its final input list (immutable from now on).
pub async fn publish(db: &Db, c: &CalculationVersion) -> Result<bool, ReportError> {
    let mut tx = db.pool.begin().await?;
    let sql=format!("UPDATE calculation_versions SET status='published',published_at={},needs_review=FALSE,input_schema={},input_schema_version={} WHERE project_slug=$3 AND calculation_id=$4 AND version=$5 AND status='draft'",db.now(),db.opt_in(1),db.opt_num_in(2));
    let done = sqlx::query(&sql)
        .bind(opt(&c.input_schema))
        .bind(opt_num(c.input_schema_version))
        .bind(&c.project)
        .bind(&c.calculation_id)
        .bind(c.version)
        .execute(&mut *tx)
        .await?;
    if done.rows_affected() > 0 {
        write_inputs(&mut tx, c).await?;
    }
    tx.commit().await?;
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
pub async fn mark_drafts_for_review(
    db: &Db,
    project: &str,
    schema: &str,
    new_version: i64,
) -> Result<u64, ReportError> {
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
    let done = sqlx::query(
        "DELETE FROM calculation_versions WHERE project_slug = $1 AND calculation_id = $2 AND version = $3",
    )
    .bind(project)
    .bind(id)
    .bind(version)
    .execute(&db.pool)
    .await?;
    Ok(done.rows_affected() > 0)
}
