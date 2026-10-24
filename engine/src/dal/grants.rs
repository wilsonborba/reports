//! Per-user read grants for restricted reports and cards (`resource_grants`).
//! A report grant has `card_id = ''` and covers every card of the report.

use serde::{Deserialize, Serialize};
use sqlx::any::AnyRow;
use sqlx::Row;
use utoipa::ToSchema;

use super::sql::{opt_col, Db};
use crate::core::error::ReportError;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
pub struct Grant {
    pub id: String,
    pub user_uuid: String,
    /// report or card
    pub resource_type: String,
    pub project: String,
    pub report: String,
    /// The card of a card grant; None for a report grant.
    pub card_id: Option<String>,
    pub granted_by: Option<String>,
    pub created_at: String,
}

impl Grant {
    /// True when this grant opens the card (a report grant opens every card of the report).
    pub fn covers(&self, project: &str, report: &str, card: Option<&str>) -> bool {
        self.project == project
            && self.report == report
            && match (&self.card_id, card) {
                (None, _) => true,
                (Some(own), Some(card)) => own == card,
                (Some(_), None) => false,
            }
    }
}

fn select(db: &Db) -> String {
    format!(
        "SELECT {} AS id, {} AS user_uuid, resource_type, project_slug, report_slug, card_id, {} AS granted_by, {} AS created_at FROM resource_grants",
        db.text("id"),
        db.text("user_uuid"),
        db.opt_text("granted_by"),
        db.text("created_at"),
    )
}

fn from_row(row: &AnyRow) -> Result<Grant, ReportError> {
    let card: String = row.try_get("card_id")?;
    Ok(Grant {
        id: row.try_get("id")?,
        user_uuid: row.try_get("user_uuid")?,
        resource_type: row.try_get("resource_type")?,
        project: row.try_get("project_slug")?,
        report: row.try_get("report_slug")?,
        card_id: (!card.is_empty()).then_some(card),
        granted_by: opt_col(row, "granted_by")?,
        created_at: row.try_get("created_at")?,
    })
}

/// Grants of one user (every project).
pub async fn for_user(db: &Db, user_uuid: &str) -> Result<Vec<Grant>, ReportError> {
    let sql = format!("{} WHERE {} = $1", select(db), db.text("user_uuid"));
    let rows = sqlx::query(&sql).bind(user_uuid).fetch_all(&db.pool).await?;
    rows.iter().map(from_row).collect()
}

/// Grants of one project, optionally of one user.
pub async fn for_project(db: &Db, project: &str, user_uuid: Option<&str>) -> Result<Vec<Grant>, ReportError> {
    let mut sql = format!("{} WHERE project_slug = $1", select(db));
    if user_uuid.is_some() {
        sql.push_str(&format!(" AND {} = $2", db.text("user_uuid")));
    }
    sql.push_str(" ORDER BY report_slug, card_id, created_at");
    let mut q = sqlx::query(&sql).bind(project);
    if let Some(u) = user_uuid {
        q = q.bind(u);
    }
    let rows = q.fetch_all(&db.pool).await?;
    rows.iter().map(from_row).collect()
}

pub async fn get(db: &Db, project: &str, id: &str) -> Result<Option<Grant>, ReportError> {
    let sql = format!("{} WHERE project_slug = $1 AND {} = $2", select(db), db.text("id"));
    let row = sqlx::query(&sql).bind(project).bind(id).fetch_optional(&db.pool).await?;
    row.as_ref().map(from_row).transpose()
}

/// Creates a grant. The same grant twice returns the first one.
pub async fn create(db: &Db, user_uuid: &str, project: &str, report: &str, card: Option<&str>, granted_by: Option<&str>) -> Result<Grant, ReportError> {
    let id = uuid::Uuid::new_v4().to_string();
    let resource_type = if card.is_some() { "card" } else { "report" };
    let sql = format!(
        "INSERT INTO resource_grants (id, user_uuid, resource_type, project_slug, report_slug, card_id, granted_by) \
         VALUES ({}, {}, $3, $4, $5, $6, $7) \
         ON CONFLICT (user_uuid, resource_type, project_slug, report_slug, card_id) DO NOTHING",
        db.uuid_in(1),
        db.uuid_in(2)
    );
    sqlx::query(&sql)
        .bind(&id)
        .bind(user_uuid)
        .bind(resource_type)
        .bind(project)
        .bind(report)
        .bind(card.unwrap_or(""))
        .bind(granted_by.unwrap_or(""))
        .execute(&db.pool)
        .await?;
    let sql = format!(
        "{} WHERE {} = $1 AND resource_type = $2 AND project_slug = $3 AND report_slug = $4 AND card_id = $5",
        select(db),
        db.text("user_uuid")
    );
    let row = sqlx::query(&sql)
        .bind(user_uuid)
        .bind(resource_type)
        .bind(project)
        .bind(report)
        .bind(card.unwrap_or(""))
        .fetch_one(&db.pool)
        .await?;
    from_row(&row)
}

/// Revokes a grant of a project. False when no such grant exists in this project.
pub async fn delete(db: &Db, project: &str, id: &str) -> Result<bool, ReportError> {
    let sql = format!("DELETE FROM resource_grants WHERE project_slug = $1 AND {} = $2", db.text("id"));
    let done = sqlx::query(&sql).bind(project).bind(id).execute(&db.pool).await?;
    Ok(done.rows_affected() > 0)
}

/// Removes the grants of a deleted report or card.
pub async fn delete_for_resource(db: &Db, project: &str, report: &str, card: Option<&str>) -> Result<u64, ReportError> {
    let done = match card {
        Some(c) => sqlx::query("DELETE FROM resource_grants WHERE project_slug = $1 AND report_slug = $2 AND card_id = $3")
            .bind(project)
            .bind(report)
            .bind(c)
            .execute(&db.pool)
            .await?,
        None => sqlx::query("DELETE FROM resource_grants WHERE project_slug = $1 AND report_slug = $2")
            .bind(project)
            .bind(report)
            .execute(&db.pool)
            .await?,
    };
    Ok(done.rows_affected())
}
