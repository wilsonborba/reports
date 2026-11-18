//! Durable catalog records in PostgreSQL: projects, reports, datasets and project roles.
//! Every write returns an error when the database refuses it; nothing is kept in memory.

use serde::{Deserialize, Serialize};
use sqlx::any::AnyRow;
use sqlx::Row;
use utoipa::ToSchema;

use super::sql::{flag_col, opt, opt_col, Db};
use crate::core::error::ReportError;
use crate::domain::datasets::spec::{DataTier, DatasetSpec, I18nText};
use crate::domain::themes::ProjectTheme;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
pub struct ProjectRecord {
    pub slug: String,
    #[schema(value_type = Object)]
    pub name: I18nText,
    #[serde(default)]
    #[schema(value_type = Object)]
    pub tagline: I18nText,
    #[serde(default)]
    #[schema(value_type = Object)]
    pub description: I18nText,
    #[serde(default)]
    pub theme: ProjectTheme,
    #[serde(default = "default_true")]
    pub is_active: bool,
    /// Product website; the GitHub repository when the project has no domain.
    #[serde(default)]
    pub website_url: Option<String>,
    #[serde(default)]
    pub repository_url: Option<String>,
    #[serde(default)]
    pub sort_order: i64,
    /// UUID of the matching domain_api project (stable when the Domain slug changes).
    #[serde(default)]
    pub domain_project_id: Option<String>,
    #[serde(default)]
    pub updated_at: String,
}

fn default_true() -> bool {
    true
}

/// Field of a stored collection that gives the report period (first and last value).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
pub struct PeriodSource {
    /// Schema name of the records.
    pub collection: String,
    pub field: String,
}

/// Report data that has no own column.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, ToSchema)]
pub struct ReportMetadata {
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub sort_order: i64,
    #[serde(default)]
    pub period_source: Option<PeriodSource>,
    /// Order of the cards in the report views: listed card IDs first, in this order, then
    /// the others by ID. The client groups the cards into sections in this order.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub card_order: Vec<String>,
}

fn default_source_app() -> String {
    "reports".to_string()
}

fn default_control_authority() -> String {
    "user_owned".to_string()
}

fn default_audience() -> String {
    "personal".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
pub struct ReportRecord {
    pub project: String,
    pub slug: String,
    #[schema(value_type = Object)]
    pub title: I18nText,
    #[serde(default)]
    #[schema(value_type = Object)]
    pub description: I18nText,
    #[serde(default)]
    pub metadata: ReportMetadata,
    pub visibility: String,
    /// A gated report that guests may see as a safe placeholder.
    #[serde(default)]
    pub discoverable: bool,
    #[serde(default)]
    pub updated_at: String,
    #[serde(default = "default_source_app")]
    pub source_app: String,
    #[serde(default)]
    pub owner_id: String,
    #[serde(default = "default_control_authority")]
    pub control_authority: String,
    #[serde(default = "default_audience")]
    pub audience: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatasetRecord {
    pub project: String,
    pub report_slug: String,
    pub dataset_id: String,
    /// Provenance of the records behind the dataset.
    pub data_tier: DataTier,
    /// Published calculation version that the card shows.
    pub calculation_id: String,
    pub calculation_version: i64,
    /// Definition assembled from that calculation version component rows.
    pub spec: DatasetSpec,
    pub visibility: String,
    /// A gated dataset that guests may see as a skeleton (no data).
    pub discoverable: bool,
    #[serde(default = "default_source_app")]
    pub source_app: String,
    #[serde(default)]
    pub owner_id: String,
    #[serde(default = "default_control_authority")]
    pub control_authority: String,
    #[serde(default = "default_audience")]
    pub audience: String,
}

fn tier_from(text: &str) -> DataTier {
    match text {
        "real" => DataTier::Real,
        "hybrid" => DataTier::Hybrid,
        _ => DataTier::Sample,
    }
}

pub fn tier_text(t: DataTier) -> &'static str {
    match t {
        DataTier::Real => "real",
        DataTier::Hybrid => "hybrid",
        DataTier::Sample => "sample",
    }
}

// --- projects ---------------------------------------------------------------

fn project_select(db: &Db) -> String {
    format!(
        "SELECT slug, {} AS is_active, \
         {} AS website_url, {} AS repository_url, CAST(sort_order AS BIGINT) AS sort_order, \
         {} AS domain_project_id, {} AS updated_at FROM catalog_projects",
        db.flag("is_active"),
        db.opt_text("website_url"),
        db.opt_text("repository_url"),
        db.opt_text("domain_project_id"),
        db.text("updated_at"),
    )
}

async fn project_from(db: &Db, row: &AnyRow) -> Result<ProjectRecord, ReportError> {
    Ok(ProjectRecord {
        slug: row.try_get("slug")?,
        name: super::catalog_storage::texts(db, &row.try_get::<String, _>("slug")?, None, "name")
            .await?,
        tagline: super::catalog_storage::texts(
            db,
            &row.try_get::<String, _>("slug")?,
            None,
            "tagline",
        )
        .await?,
        description: super::catalog_storage::texts(
            db,
            &row.try_get::<String, _>("slug")?,
            None,
            "description",
        )
        .await?,
        theme: super::catalog_storage::theme(db, &row.try_get::<String, _>("slug")?).await?,
        is_active: flag_col(row, "is_active")?,
        website_url: opt_col(row, "website_url")?,
        repository_url: opt_col(row, "repository_url")?,
        sort_order: row.try_get("sort_order")?,
        domain_project_id: opt_col(row, "domain_project_id")?,
        updated_at: row.try_get("updated_at")?,
    })
}

/// Projects ordered by sort order, then slug. `active_only` hides deactivated projects.
pub async fn list_projects(db: &Db, active_only: bool) -> Result<Vec<ProjectRecord>, ReportError> {
    let mut sql = project_select(db);
    if active_only {
        sql.push_str(" WHERE is_active = TRUE");
    }
    sql.push_str(" ORDER BY sort_order, slug");
    let rows = sqlx::query(&sql).fetch_all(&db.pool).await?;
    let mut out = Vec::new();
    for r in &rows {
        out.push(project_from(db, r).await?);
    }
    Ok(out)
}

pub async fn get_project(db: &Db, slug: &str) -> Result<Option<ProjectRecord>, ReportError> {
    let sql = format!("{} WHERE slug = $1", project_select(db));
    let row = sqlx::query(&sql)
        .bind(slug)
        .fetch_optional(&db.pool)
        .await?;
    match row {
        Some(r) => Ok(Some(project_from(db, &r).await?)),
        None => Ok(None),
    }
}

/// Active project or 404.
pub async fn active_project(db: &Db, slug: &str) -> Result<ProjectRecord, ReportError> {
    match get_project(db, slug).await? {
        Some(p) if p.is_active => Ok(p),
        _ => Err(ReportError::not_found(format!("project '{slug}'"))),
    }
}

pub async fn upsert_project(db: &Db, p: &ProjectRecord) -> Result<(), ReportError> {
    let mut tx = db.pool.begin().await?;
    let sql=format!("INSERT INTO catalog_projects(slug,is_active,website_url,repository_url,sort_order,domain_project_id,updated_at) VALUES($1,$2,{}, {},$5,{}, {}) ON CONFLICT(slug) DO UPDATE SET is_active=EXCLUDED.is_active,website_url=EXCLUDED.website_url,repository_url=EXCLUDED.repository_url,sort_order=EXCLUDED.sort_order,domain_project_id=EXCLUDED.domain_project_id,updated_at=EXCLUDED.updated_at",db.opt_in(3),db.opt_in(4),db.opt_uuid_in(6),db.now());
    let result = sqlx::query(&sql)
        .bind(&p.slug)
        .bind(p.is_active)
        .bind(opt(&p.website_url))
        .bind(opt(&p.repository_url))
        .bind(p.sort_order)
        .bind(opt(&p.domain_project_id))
        .execute(&mut *tx)
        .await;
    match result {
        Err(sqlx::Error::Database(e)) if e.is_unique_violation() => {
            return Err(ReportError::Conflict(
                "Domain project is already linked to another Reports project".into(),
            ))
        }
        Err(e) => return Err(e.into()),
        Ok(_) => {}
    }
    for (kind, text) in [
        ("name", &p.name),
        ("tagline", &p.tagline),
        ("description", &p.description),
    ] {
        super::catalog_storage::write_texts(&mut tx, &p.slug, None, kind, text).await?;
    }
    super::catalog_storage::write_theme(&mut tx, &p.slug, &p.theme).await?;
    tx.commit().await?;
    Ok(())
}

// --- reports ----------------------------------------------------------------

fn report_select(db: &Db) -> String {
    format!(
        "SELECT project_slug, slug, CAST(sort_order AS BIGINT) AS sort_order, {} AS period_collection, {} AS period_field, visibility, {} AS discoverable, {} AS updated_at, source_app, owner_id, control_authority, audience FROM reports",
        db.opt_text("period_collection"),
        db.opt_text("period_field"),
        db.flag("discoverable"),
        db.text("updated_at"),
    )
}

async fn report_from(db: &Db, row: &AnyRow) -> Result<ReportRecord, ReportError> {
    Ok(ReportRecord {
        project: row.try_get("project_slug")?,
        slug: row.try_get("slug")?,
        title: super::catalog_storage::texts(
            db,
            &row.try_get::<String, _>("project_slug")?,
            Some(&row.try_get::<String, _>("slug")?),
            "title",
        )
        .await?,
        description: super::catalog_storage::texts(
            db,
            &row.try_get::<String, _>("project_slug")?,
            Some(&row.try_get::<String, _>("slug")?),
            "description",
        )
        .await?,
        metadata: super::catalog_storage::metadata(
            db,
            &row.try_get::<String, _>("project_slug")?,
            &row.try_get::<String, _>("slug")?,
            row.try_get("sort_order")?,
            opt_col(row, "period_collection")?,
            opt_col(row, "period_field")?,
        )
        .await?,
        visibility: row.try_get("visibility")?,
        discoverable: flag_col(row, "discoverable")?,
        updated_at: row.try_get("updated_at")?,
        source_app: row.try_get("source_app")?,
        owner_id: row.try_get("owner_id")?,
        control_authority: row.try_get("control_authority")?,
        audience: row.try_get("audience")?,
    })
}

/// Reports of a project ordered by sort order, then slug.
pub async fn list_reports(db: &Db, project: &str) -> Result<Vec<ReportRecord>, ReportError> {
    let sql = format!(
        "{} WHERE project_slug = $1 ORDER BY slug",
        report_select(db)
    );
    let rows = sqlx::query(&sql).bind(project).fetch_all(&db.pool).await?;
    let mut out = Vec::new();
    for row in &rows {
        out.push(report_from(db, row).await?);
    }
    out.sort_by(|a, b| {
        a.metadata
            .sort_order
            .cmp(&b.metadata.sort_order)
            .then(a.slug.cmp(&b.slug))
    });
    Ok(out)
}

pub async fn get_report(
    db: &Db,
    project: &str,
    slug: &str,
) -> Result<Option<ReportRecord>, ReportError> {
    let sql = format!(
        "{} WHERE project_slug = $1 AND slug = $2",
        report_select(db)
    );
    let row = sqlx::query(&sql)
        .bind(project)
        .bind(slug)
        .fetch_optional(&db.pool)
        .await?;
    match row {
        Some(r) => Ok(Some(report_from(db, &r).await?)),
        None => Ok(None),
    }
}

pub async fn upsert_report(db: &Db, r: &ReportRecord) -> Result<(), ReportError> {
    let mut tx = db.pool.begin().await?;
    let source_app = if r.source_app.is_empty() {
        "reports"
    } else {
        r.source_app.as_str()
    };
    let authority = if r.control_authority.is_empty() {
        "user_owned"
    } else {
        r.control_authority.as_str()
    };
    let audience = if r.audience.is_empty() {
        crate::domain::auth::Audience::from_visibility(crate::domain::auth::Visibility::parse(
            &r.visibility,
        ))
        .as_str()
    } else {
        r.audience.as_str()
    };
    let sql = format!(
        "INSERT INTO reports(project_slug,slug,visibility,discoverable,sort_order,period_collection,period_field,source_app,owner_id,control_authority,audience,updated_at) VALUES($1,$2,$3,$4,$5,{}, {},$8,$9,$10,$11,{}) ON CONFLICT(project_slug,slug) DO UPDATE SET visibility=EXCLUDED.visibility,discoverable=EXCLUDED.discoverable,sort_order=EXCLUDED.sort_order,period_collection=EXCLUDED.period_collection,period_field=EXCLUDED.period_field,source_app=EXCLUDED.source_app,owner_id=EXCLUDED.owner_id,control_authority=EXCLUDED.control_authority,audience=EXCLUDED.audience,updated_at=EXCLUDED.updated_at",
        db.opt_in(6),
        db.opt_in(7),
        db.now()
    );
    sqlx::query(&sql)
        .bind(&r.project)
        .bind(&r.slug)
        .bind(&r.visibility)
        .bind(r.discoverable)
        .bind(r.metadata.sort_order)
        .bind(
            r.metadata
                .period_source
                .as_ref()
                .map(|p| p.collection.as_str())
                .unwrap_or(""),
        )
        .bind(
            r.metadata
                .period_source
                .as_ref()
                .map(|p| p.field.as_str())
                .unwrap_or(""),
        )
        .bind(source_app)
        .bind(&r.owner_id)
        .bind(authority)
        .bind(audience)
        .execute(&mut *tx)
        .await?;
    super::catalog_storage::write_texts(&mut tx, &r.project, Some(&r.slug), "title", &r.title)
        .await?;
    super::catalog_storage::write_texts(
        &mut tx,
        &r.project,
        Some(&r.slug),
        "description",
        &r.description,
    )
    .await?;
    super::catalog_storage::write_items(&mut tx, &r.project, &r.slug, &r.metadata).await?;
    tx.commit().await?;
    Ok(())
}

/// Deletes a report and its datasets (foreign key cascade). True when it existed.
pub async fn delete_report(db: &Db, project: &str, slug: &str) -> Result<bool, ReportError> {
    let done = sqlx::query("DELETE FROM reports WHERE project_slug = $1 AND slug = $2")
        .bind(project)
        .bind(slug)
        .execute(&db.pool)
        .await?;
    Ok(done.rows_affected() > 0)
}

// --- datasets ---------------------------------------------------------------

fn dataset_select(db: &Db) -> String {
    format!(
        "SELECT d.project_slug AS project_slug, d.report_slug AS report_slug, d.dataset_id AS dataset_id, \
         d.data_tier AS data_tier, d.visibility AS visibility, {} AS discoverable, \
         {} AS calculation_id, CAST(COALESCE(d.calculation_version, 0) AS BIGINT) AS calculation_version, \
         d.source_app AS source_app, d.owner_id AS owner_id, d.control_authority AS control_authority, d.audience AS audience, \
         1 AS unused FROM datasets d",
        db.flag("d.discoverable"),
        db.opt_text("d.calculation_id"),
    )
}

async fn dataset_from(db: &Db, row: &AnyRow) -> Result<DatasetRecord, ReportError> {
    Ok(DatasetRecord {
        project: row.try_get("project_slug")?,
        report_slug: row.try_get("report_slug")?,
        dataset_id: row.try_get("dataset_id")?,
        data_tier: tier_from(&row.try_get::<String, _>("data_tier")?),
        calculation_id: row.try_get("calculation_id")?,
        calculation_version: row.try_get("calculation_version")?,
        spec: super::calculations::load_definition(
            db,
            &row.try_get::<String, _>("project_slug")?,
            &row.try_get::<String, _>("calculation_id")?,
            row.try_get("calculation_version")?,
        )
        .await?,
        visibility: row.try_get("visibility")?,
        discoverable: flag_col(row, "discoverable")?,
        source_app: row.try_get("source_app")?,
        owner_id: row.try_get("owner_id")?,
        control_authority: row.try_get("control_authority")?,
        audience: row.try_get("audience")?,
    })
}

pub async fn list_datasets(
    db: &Db,
    project: &str,
    report: &str,
) -> Result<Vec<DatasetRecord>, ReportError> {
    let sql = format!(
        "{} WHERE d.project_slug = $1 AND d.report_slug = $2 ORDER BY d.dataset_id",
        dataset_select(db)
    );
    let rows = sqlx::query(&sql)
        .bind(project)
        .bind(report)
        .fetch_all(&db.pool)
        .await?;
    let mut out = Vec::new();
    for r in &rows {
        out.push(dataset_from(db, r).await?);
    }
    Ok(out)
}

/// Every dataset of a project (statistics and cache dependencies).
pub async fn list_project_datasets(
    db: &Db,
    project: &str,
) -> Result<Vec<DatasetRecord>, ReportError> {
    let sql = format!(
        "{} WHERE d.project_slug = $1 ORDER BY d.report_slug, d.dataset_id",
        dataset_select(db)
    );
    let rows = sqlx::query(&sql).bind(project).fetch_all(&db.pool).await?;
    let mut out = Vec::new();
    for r in &rows {
        out.push(dataset_from(db, r).await?);
    }
    Ok(out)
}

pub async fn get_dataset(
    db: &Db,
    project: &str,
    report: &str,
    id: &str,
) -> Result<Option<DatasetRecord>, ReportError> {
    let sql = format!(
        "{} WHERE d.project_slug = $1 AND d.report_slug = $2 AND d.dataset_id = $3",
        dataset_select(db)
    );
    let row = sqlx::query(&sql)
        .bind(project)
        .bind(report)
        .bind(id)
        .fetch_optional(&db.pool)
        .await?;
    match row {
        Some(r) => Ok(Some(dataset_from(db, &r).await?)),
        None => Ok(None),
    }
}

pub async fn upsert_dataset(db: &Db, d: &DatasetRecord) -> Result<(), ReportError> {
    let source_app = if d.source_app.is_empty() {
        "reports"
    } else {
        d.source_app.as_str()
    };
    let authority = if d.control_authority.is_empty() {
        "user_owned"
    } else {
        d.control_authority.as_str()
    };
    let audience = if d.audience.is_empty() {
        crate::domain::auth::Audience::from_visibility(crate::domain::auth::Visibility::parse(
            &d.visibility,
        ))
        .as_str()
    } else {
        d.audience.as_str()
    };
    let sql = "INSERT INTO datasets (project_slug, report_slug, dataset_id, data_tier, calculation_id, calculation_version, visibility, discoverable, source_app, owner_id, control_authority, audience) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) \
         ON CONFLICT (project_slug, report_slug, dataset_id) DO UPDATE SET \
         data_tier = EXCLUDED.data_tier, calculation_id = EXCLUDED.calculation_id, \
         calculation_version = EXCLUDED.calculation_version, visibility = EXCLUDED.visibility, \
         discoverable = EXCLUDED.discoverable, source_app = EXCLUDED.source_app, \
         owner_id = EXCLUDED.owner_id, control_authority = EXCLUDED.control_authority, audience = EXCLUDED.audience";
    sqlx::query(sql)
        .bind(&d.project)
        .bind(&d.report_slug)
        .bind(&d.dataset_id)
        .bind(tier_text(d.data_tier))
        .bind(&d.calculation_id)
        .bind(d.calculation_version)
        .bind(&d.visibility)
        .bind(d.discoverable)
        .bind(source_app)
        .bind(&d.owner_id)
        .bind(authority)
        .bind(audience)
        .execute(&db.pool)
        .await?;
    Ok(())
}

pub async fn delete_dataset(
    db: &Db,
    project: &str,
    report: &str,
    id: &str,
) -> Result<bool, ReportError> {
    let done = sqlx::query(
        "DELETE FROM datasets WHERE project_slug = $1 AND report_slug = $2 AND dataset_id = $3",
    )
    .bind(project)
    .bind(report)
    .bind(id)
    .execute(&db.pool)
    .await?;
    Ok(done.rows_affected() > 0)
}

// --- roles ------------------------------------------------------------------

/// True when `user_project_roles` marks the user as admin of the project.
pub async fn is_project_admin(
    db: &Db,
    user_uuid: &str,
    project: &str,
) -> Result<bool, ReportError> {
    let sql = format!(
        "SELECT {} AS is_admin FROM user_project_roles WHERE {} = $1 AND app_name = $2",
        db.flag("is_project_admin"),
        db.text("user_uuid"),
    );
    let row = sqlx::query(&sql)
        .bind(user_uuid)
        .bind(project)
        .fetch_optional(&db.pool)
        .await?;
    match row {
        Some(r) => flag_col(&r, "is_admin"),
        None => Ok(false),
    }
}

/// Projects where the user is project admin.
pub async fn admin_projects(db: &Db, user_uuid: &str) -> Result<Vec<String>, ReportError> {
    let sql = format!(
        "SELECT app_name FROM user_project_roles WHERE {} = $1 AND is_project_admin = TRUE ORDER BY app_name",
        db.text("user_uuid"),
    );
    let rows = sqlx::query(&sql)
        .bind(user_uuid)
        .fetch_all(&db.pool)
        .await?;
    rows.iter()
        .map(|r| {
            r.try_get::<String, _>("app_name")
                .map_err(ReportError::from)
        })
        .collect()
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
pub struct ProjectRole {
    pub user_uuid: String,
    pub project: String,
    pub is_project_admin: bool,
}

/// Stores the theme tokens of a project.
pub async fn set_theme(db: &Db, slug: &str, theme: &ProjectTheme) -> Result<bool, ReportError> {
    let mut tx = db.pool.begin().await?;
    let sql = format!(
        "UPDATE catalog_projects SET updated_at={} WHERE slug=$1",
        db.now()
    );
    let done = sqlx::query(&sql).bind(slug).execute(&mut *tx).await?;
    if done.rows_affected() > 0 {
        super::catalog_storage::write_theme(&mut tx, slug, theme).await?;
    }
    tx.commit().await?;
    Ok(done.rows_affected() > 0)
}

/// Sets or clears the project admin role of a user.
pub async fn set_project_admin(
    db: &Db,
    user_uuid: &str,
    project: &str,
    is_admin: bool,
) -> Result<(), ReportError> {
    let sql = format!(
        "INSERT INTO user_project_roles (user_uuid, app_name, is_project_admin) VALUES ({}, $2, $3) \
         ON CONFLICT (user_uuid, app_name) DO UPDATE SET is_project_admin = EXCLUDED.is_project_admin",
        db.uuid_in(1)
    );
    sqlx::query(&sql)
        .bind(user_uuid)
        .bind(project)
        .bind(is_admin)
        .execute(&db.pool)
        .await?;
    Ok(())
}

pub async fn delete_role(db: &Db, user_uuid: &str, project: &str) -> Result<bool, ReportError> {
    let sql = format!(
        "DELETE FROM user_project_roles WHERE {} = $1 AND app_name = $2",
        db.text("user_uuid")
    );
    let done = sqlx::query(&sql)
        .bind(user_uuid)
        .bind(project)
        .execute(&db.pool)
        .await?;
    Ok(done.rows_affected() > 0)
}

pub async fn list_roles(db: &Db, project: &str) -> Result<Vec<ProjectRole>, ReportError> {
    let sql = format!(
        "SELECT {} AS user_uuid, app_name, {} AS is_admin FROM user_project_roles WHERE app_name = $1 ORDER BY 1",
        db.text("user_uuid"),
        db.flag("is_project_admin")
    );
    let rows = sqlx::query(&sql).bind(project).fetch_all(&db.pool).await?;
    rows.iter()
        .map(|r| {
            Ok(ProjectRole {
                user_uuid: r.try_get("user_uuid")?,
                project: r.try_get("app_name")?,
                is_project_admin: flag_col(r, "is_admin")?,
            })
        })
        .collect()
}
