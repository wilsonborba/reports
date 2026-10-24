//! Admin routes. They exist under two prefixes with the same handlers:
//! - `/projects/{project}/admin/...` matches the gateway admin rule (super admin session or
//!   gateway key) and the engine checks the role again;
//! - `/admin/projects/{project}/...` is a plain session route, so a project admin (who cannot
//!   pass the gateway admin rule) can reach it; the engine checks the role.
//!
//! Local operator tools call the engine directly with `x-reports-service-key`.

use std::sync::Arc;

use axum::extract::{Path, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Deserialize;
use serde_json::json;
use utoipa::ToSchema;

use super::identity::{fixture_of, require_admin, require_super_admin, Caller};
use super::server::AppState;
use super::viewer::private;
use crate::core::error::ReportError;
use crate::dal::{calculations, catalog, fixtures, grants, schemas, DatasetRecord, Grant, ProjectRecord, ProjectRole, ReportMetadata, ReportRecord, SchemaVersion};
use crate::domain::catalog::{validate_dataset, validate_project, validate_report};
use crate::domain::datasets::spec::{DataTier, I18nText};
use crate::domain::ingest::{self, IngestRequest, IngestResponse, SchemaDraftRequest};
use crate::domain::composition::refresh_index;
use crate::domain::themes::{validate_theme, ProjectTheme, ThemeRecord};

#[derive(Debug, Deserialize, ToSchema)]
pub struct ProjectBody {
    #[schema(value_type = Object)]
    pub name: I18nText,
    #[serde(default)]
    #[schema(value_type = Object)]
    pub tagline: I18nText,
    #[serde(default)]
    #[schema(value_type = Object)]
    pub description: I18nText,
    #[serde(default)]
    pub is_active: Option<bool>,
    /// https URL of the product, or of the repository when there is no domain
    #[serde(default)]
    pub website_url: Option<String>,
    /// https URL of the GitHub repository
    #[serde(default)]
    pub repository_url: Option<String>,
    #[serde(default)]
    pub sort_order: i64,
    /// UUID of the domain_api project. It must exist in domain_api and be unused.
    #[serde(default)]
    pub domain_project_id: Option<String>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ReportBody {
    #[schema(value_type = Object)]
    pub title: I18nText,
    #[serde(default)]
    #[schema(value_type = Object)]
    pub description: I18nText,
    #[serde(default)]
    pub metadata: ReportMetadata,
    /// public, signed_in or restricted (default restricted)
    #[serde(default)]
    pub visibility: Option<String>,
    /// A gated report that guests may see as a placeholder (default false)
    #[serde(default)]
    pub discoverable: bool,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct DatasetBody {
    /// real, hybrid or sample (default sample)
    #[serde(default)]
    pub data_tier: DataTier,
    /// Published calculation version that this card shows.
    pub calculation_id: String,
    pub calculation_version: i64,
    /// public, signed_in or restricted (default restricted)
    #[serde(default)]
    pub visibility: Option<String>,
    /// A gated dataset that guests may see as a skeleton (default false)
    #[serde(default)]
    pub discoverable: bool,
}

fn restricted_default(v: Option<String>) -> String {
    v.unwrap_or_else(|| "restricted".to_string())
}

#[utoipa::path(
    put,
    path = "/projects/{project}/admin/project",
    summary = "Create or update a project (super admin)",
    request_body = ProjectBody,
    params(("project" = String, Path)),
    responses((status = 200, description = "Saved project", body = ProjectRecord), (status = 403, description = "Not a super admin"), (status = 422, description = "Invalid project")),
    tag = "Admin"
)]
pub async fn put_project(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path(project): Path<String>,
    Json(body): Json<ProjectBody>,
) -> Result<Response, ReportError> {
    require_super_admin(&scope)?;
    let existing = catalog::get_project(&state.stores.db, &project).await?;
    let domain_project_id = body.domain_project_id.map(|id| id.trim().to_lowercase()).filter(|id| !id.is_empty());
    let record = ProjectRecord {
        slug: project.clone(),
        name: body.name,
        tagline: body.tagline,
        description: body.description,
        theme: existing.as_ref().map(|p| p.theme.clone()).unwrap_or_default(),
        is_active: body.is_active.unwrap_or(true),
        website_url: body.website_url,
        repository_url: body.repository_url,
        sort_order: body.sort_order,
        domain_project_id,
        updated_at: String::new(),
    };
    validate_project(&record)?;
    if let Some(id) = &record.domain_project_id {
        let unchanged = existing.as_ref().and_then(|p| p.domain_project_id.as_deref()) == Some(id.as_str());
        if !unchanged {
            // A new link must resolve in domain_api now.
            let index = refresh_index(&state.stores, state.settings.domain_cache_ttl_secs).await?;
            if index.lookup(Some(id)).1.is_none() {
                return Err(ReportError::Validation {
                    message: "invalid project".into(),
                    violations: vec![crate::domain::guardrail::ValidationError::definition(
                        "domain_project_id",
                        format!("no domain_api project has the UUID {id}"),
                    )],
                });
            }
        }
    }
    catalog::upsert_project(&state.stores.db, &record).await?;
    state.datasets.catalog_changed(&project).await;
    let saved = catalog::get_project(&state.stores.db, &project)
        .await?
        .ok_or_else(|| ReportError::Internal("saved project is missing".into()))?;
    Ok(private(saved))
}

#[utoipa::path(
    put,
    path = "/projects/{project}/admin/reports/{report}",
    summary = "Create or update a report",
    request_body = ReportBody,
    params(("project" = String, Path), ("report" = String, Path)),
    responses((status = 200, description = "Saved report", body = ReportRecord), (status = 403, description = "Not an admin of the project"), (status = 422, description = "Invalid report")),
    tag = "Admin"
)]
pub async fn put_report(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, report)): Path<(String, String)>,
    headers: HeaderMap,
    Json(body): Json<ReportBody>,
) -> Result<Response, ReportError> {
    require_admin(&scope, &project)?;
    let fixture = fixture_of(&scope, &headers)?;
    catalog::active_project(&state.stores.db, &project).await?;
    let record = ReportRecord {
        project: project.clone(),
        slug: report.clone(),
        title: body.title,
        description: body.description,
        metadata: body.metadata,
        visibility: restricted_default(body.visibility),
        discoverable: body.discoverable,
        updated_at: String::new(),
    };
    validate_report(&record)?;
    catalog::upsert_report(&state.stores.db, &record).await?;
    state.datasets.catalog_changed(&project).await;
    fixtures::track(&state.stores.db, fixture.as_deref(), "report", &fixtures::report_id(&project, &report)).await?;
    let saved = catalog::get_report(&state.stores.db, &project, &report)
        .await?
        .ok_or_else(|| ReportError::Internal("saved report is missing".into()))?;
    Ok(private(saved))
}

#[utoipa::path(
    delete,
    path = "/projects/{project}/admin/reports/{report}",
    summary = "Delete a report and its datasets",
    params(("project" = String, Path), ("report" = String, Path)),
    responses((status = 204, description = "Deleted"), (status = 404, description = "Not found")),
    tag = "Admin"
)]
pub async fn delete_report(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, report)): Path<(String, String)>,
) -> Result<StatusCode, ReportError> {
    require_admin(&scope, &project)?;
    for d in catalog::list_datasets(&state.stores.db, &project, &report).await? {
        state.datasets.definition_changed(&project, &report, &d.dataset_id).await;
    }
    if catalog::delete_report(&state.stores.db, &project, &report).await? {
        grants::delete_for_resource(&state.stores.db, &project, &report, None).await?;
        state.datasets.catalog_changed(&project).await;
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(ReportError::not_found(format!("report '{project}/{report}'")))
    }
}

#[utoipa::path(
    put,
    path = "/projects/{project}/admin/reports/{report}/datasets/{dataset}",
    summary = "Bind a dataset card to a published calculation version",
    description = "The card shows the result of one published calculation version. Dataset references must stay in the report and form no cycle.",
    request_body = DatasetBody,
    params(("project" = String, Path), ("report" = String, Path), ("dataset" = String, Path)),
    responses((status = 200, description = "Saved dataset"), (status = 422, description = "Invalid dataset")),
    tag = "Admin"
)]
pub async fn put_dataset(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, report, dataset)): Path<(String, String, String)>,
    headers: HeaderMap,
    Json(body): Json<DatasetBody>,
) -> Result<Response, ReportError> {
    require_admin(&scope, &project)?;
    let fixture = fixture_of(&scope, &headers)?;
    if catalog::get_report(&state.stores.db, &project, &report).await?.is_none() {
        return Err(ReportError::not_found(format!("report '{project}/{report}'")));
    }
    let calc = calculations::get(&state.stores.db, &project, &body.calculation_id, body.calculation_version)
        .await?
        .ok_or_else(|| ReportError::not_found(format!("calculation {project}:{} v{}", body.calculation_id, body.calculation_version)))?;
    if calc.status != "published" {
        return Err(ReportError::Conflict(format!(
            "calculation {} v{} is {}; a card shows only a published version",
            calc.calculation_id, calc.version, calc.status
        )));
    }
    let record = DatasetRecord {
        project: project.clone(),
        report_slug: report.clone(),
        dataset_id: dataset.clone(),
        data_tier: body.data_tier,
        calculation_id: calc.calculation_id.clone(),
        calculation_version: calc.version,
        spec: calc.definition.clone(),
        visibility: restricted_default(body.visibility),
        discoverable: body.discoverable,
    };
    validate_dataset(&record)?;
    // Dataset references stay inside the report and form no cycle.
    let mut graph: std::collections::HashMap<String, Vec<String>> = catalog::list_datasets(&state.stores.db, &project, &report)
        .await?
        .into_iter()
        .map(|d| (d.dataset_id, d.spec.refs.values().map(|r| r.dataset.clone()).collect()))
        .collect();
    graph.insert(dataset.clone(), record.spec.refs.values().map(|r| r.dataset.clone()).collect());
    for target in record.spec.refs.values().map(|r| &r.dataset) {
        if !graph.contains_key(target) {
            return Err(ReportError::not_found(format!("referenced dataset '{target}' in report '{report}'")));
        }
    }
    crate::domain::calculations::check_ref_cycles(&graph)?;
    catalog::upsert_dataset(&state.stores.db, &record).await?;
    state.datasets.catalog_changed(&project).await;
    fixtures::track(&state.stores.db, fixture.as_deref(), "dataset", &fixtures::dataset_id(&project, &report, &dataset)).await?;
    state.datasets.definition_changed(&project, &report, &dataset).await;
    Ok(private(json!({
        "project": project, "report": report, "dataset_id": dataset,
        "data_tier": record.data_tier, "visibility": record.visibility,
        "discoverable": record.discoverable,
        "calculation_id": record.calculation_id, "calculation_version": record.calculation_version
    })))
}

#[utoipa::path(
    delete,
    path = "/projects/{project}/admin/reports/{report}/datasets/{dataset}",
    summary = "Delete a dataset",
    params(("project" = String, Path), ("report" = String, Path), ("dataset" = String, Path)),
    responses((status = 204, description = "Deleted"), (status = 404, description = "Not found")),
    tag = "Admin"
)]
pub async fn delete_dataset(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, report, dataset)): Path<(String, String, String)>,
) -> Result<StatusCode, ReportError> {
    require_admin(&scope, &project)?;
    state.datasets.definition_changed(&project, &report, &dataset).await;
    if catalog::delete_dataset(&state.stores.db, &project, &report, &dataset).await? {
        grants::delete_for_resource(&state.stores.db, &project, &report, Some(&dataset)).await?;
        state.datasets.catalog_changed(&project).await;
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(ReportError::not_found(format!("dataset '{project}/{report}/{dataset}'")))
    }
}

#[utoipa::path(
    get,
    path = "/admin/projects/{project}/schemas",
    summary = "Every schema version of a project",
    params(("project" = String, Path)),
    responses((status = 200, description = "Schema versions with fields", body = [SchemaVersion])),
    tag = "Admin"
)]
pub async fn list_schemas(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path(project): Path<String>,
) -> Result<Response, ReportError> {
    require_admin(&scope, &project)?;
    Ok(private(schemas::list(&state.stores.db, &project).await?))
}

#[utoipa::path(
    post,
    path = "/projects/{project}/admin/schemas",
    summary = "Create or replace a draft schema version",
    description = "Omit `version` to create the next version. A published version cannot change.",
    request_body = SchemaDraftRequest,
    params(("project" = String, Path)),
    responses((status = 201, description = "Draft saved", body = SchemaVersion), (status = 409, description = "Version is published"), (status = 422, description = "Invalid fields")),
    tag = "Admin"
)]
pub async fn post_schema(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path(project): Path<String>,
    headers: HeaderMap,
    Json(body): Json<SchemaDraftRequest>,
) -> Result<Response, ReportError> {
    require_admin(&scope, &project)?;
    let fixture = fixture_of(&scope, &headers)?;
    let saved = ingest::save_schema_draft(&state.datasets, &project, body).await?;
    fixtures::track(&state.stores.db, fixture.as_deref(), "schema", &fixtures::version_id(&project, &saved.schema_name, saved.version)).await?;
    Ok((StatusCode::CREATED, private(saved)).into_response())
}

#[utoipa::path(
    post,
    path = "/projects/{project}/admin/schemas/{schema}/versions/{version}/publish",
    summary = "Publish a draft schema version (it becomes immutable)",
    params(("project" = String, Path), ("schema" = String, Path), ("version" = i64, Path)),
    responses((status = 200, description = "Published", body = SchemaVersion), (status = 409, description = "Not a draft")),
    tag = "Admin"
)]
pub async fn publish_schema(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, schema, version)): Path<(String, String, i64)>,
) -> Result<Response, ReportError> {
    require_admin(&scope, &project)?;
    Ok(private(ingest::publish_schema(&state.datasets, &project, &schema, version).await?))
}

#[utoipa::path(
    post,
    path = "/projects/{project}/admin/schemas/{schema}/versions/{version}/retire",
    summary = "Retire a published schema version (no new records)",
    params(("project" = String, Path), ("schema" = String, Path), ("version" = i64, Path)),
    responses((status = 200, description = "Retired", body = SchemaVersion), (status = 409, description = "Not published")),
    tag = "Admin"
)]
pub async fn retire_schema(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, schema, version)): Path<(String, String, i64)>,
) -> Result<Response, ReportError> {
    require_admin(&scope, &project)?;
    Ok(private(ingest::retire_schema(&state.datasets, &project, &schema, version).await?))
}

#[utoipa::path(
    post,
    path = "/projects/{project}/admin/ingest/{schema}",
    summary = "Receive records for a published schema version",
    description = "All records are validated first; one invalid record refuses the whole request. Success means CouchDB stored every record. A repeated idempotency key is counted as a duplicate and not written again. Example: `curl -X POST -H 'x-reports-service-key: ...' http://localhost:8109/projects/cortex/admin/ingest/telemetry_event -d '{\"schema_version\":1,\"records\":[...]}'`",
    request_body = IngestRequest,
    params(("project" = String, Path), ("schema" = String, Path)),
    responses(
        (status = 201, description = "Stored", body = IngestResponse),
        (status = 409, description = "Schema version is not published"),
        (status = 422, description = "Invalid records; nothing written"),
        (status = 503, description = "CouchDB unavailable; nothing acknowledged")
    ),
    tag = "Admin"
)]
pub async fn ingest_records(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, schema)): Path<(String, String)>,
    headers: HeaderMap,
    Json(body): Json<IngestRequest>,
) -> Result<Response, ReportError> {
    require_admin(&scope, &project)?;
    let fixture = fixture_of(&scope, &headers)?;
    let result = ingest::ingest(&state.datasets, &project, &schema, body, fixture).await?;
    if result.outcome.created > 0 {
        let (svc, p, s) = (state.datasets.clone(), project.clone(), schema.clone());
        tokio::spawn(async move {
            let n = crate::domain::reports::warm_public(&svc, &p, Some(&s)).await;
            if n > 0 {
                tracing::info!(project = %p, schema = %s, warmed = n, "public KPIs warmed");
            }
        });
    }
    Ok((StatusCode::CREATED, private(result)).into_response())
}

// --- roles and grants -------------------------------------------------------

#[derive(Debug, Deserialize, ToSchema)]
pub struct RoleBody {
    pub is_project_admin: bool,
}

fn check_uuid(value: &str) -> Result<(), ReportError> {
    uuid::Uuid::parse_str(value)
        .map(|_| ())
        .map_err(|_| ReportError::BadRequest(format!("'{value}' is not a user UUID")))
}

#[utoipa::path(
    put,
    path = "/projects/{project}/admin/roles/{user}",
    summary = "Set the project admin role of a user (super admin)",
    request_body = RoleBody,
    params(("project" = String, Path), ("user" = String, Path, description = "Asodya user UUID")),
    responses((status = 200, description = "Role saved", body = ProjectRole), (status = 403, description = "Not a super admin")),
    tag = "Admin"
)]
pub async fn put_role(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, user)): Path<(String, String)>,
    Json(body): Json<RoleBody>,
) -> Result<Response, ReportError> {
    require_super_admin(&scope)?;
    check_uuid(&user)?;
    catalog::active_project(&state.stores.db, &project).await?;
    catalog::set_project_admin(&state.stores.db, &user, &project, body.is_project_admin).await?;
    Ok(private(ProjectRole { user_uuid: user, project, is_project_admin: body.is_project_admin }))
}

#[utoipa::path(
    delete,
    path = "/projects/{project}/admin/roles/{user}",
    summary = "Remove the project role of a user (super admin)",
    params(("project" = String, Path), ("user" = String, Path)),
    responses((status = 204, description = "Removed"), (status = 404, description = "No role")),
    tag = "Admin"
)]
pub async fn delete_role(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, user)): Path<(String, String)>,
) -> Result<StatusCode, ReportError> {
    require_super_admin(&scope)?;
    if catalog::delete_role(&state.stores.db, &user, &project).await? {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(ReportError::not_found(format!("role of {user} in '{project}'")))
    }
}

#[utoipa::path(
    get,
    path = "/admin/projects/{project}/roles",
    summary = "Project roles",
    params(("project" = String, Path)),
    responses((status = 200, description = "Roles", body = [ProjectRole])),
    tag = "Admin"
)]
pub async fn list_roles(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path(project): Path<String>,
) -> Result<Response, ReportError> {
    require_admin(&scope, &project)?;
    Ok(private(catalog::list_roles(&state.stores.db, &project).await?))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct GrantBody {
    /// Asodya user UUID
    pub user_uuid: String,
    pub report: String,
    /// One card of the report; omit it to grant the whole report.
    #[serde(default)]
    pub card_id: Option<String>,
}

#[utoipa::path(
    post,
    path = "/admin/projects/{project}/grants",
    summary = "Grant read access to a restricted report or card",
    description = "Super admin or project admin of this project. The same grant twice returns the first one. Also under `/projects/{project}/admin/grants` (super admin).",
    request_body = GrantBody,
    params(("project" = String, Path)),
    responses((status = 201, description = "Grant", body = Grant), (status = 403, description = "Not an admin of the project"), (status = 404, description = "Report or card not found")),
    tag = "Admin"
)]
pub async fn post_grant(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path(project): Path<String>,
    Json(body): Json<GrantBody>,
) -> Result<Response, ReportError> {
    require_admin(&scope, &project)?;
    check_uuid(&body.user_uuid)?;
    let db = &state.stores.db;
    if catalog::get_report(db, &project, &body.report).await?.is_none() {
        return Err(ReportError::not_found(format!("report '{project}/{}'", body.report)));
    }
    if let Some(card) = &body.card_id {
        if catalog::get_dataset(db, &project, &body.report, card).await?.is_none() {
            return Err(ReportError::not_found(format!("card '{project}/{}/{card}'", body.report)));
        }
    }
    let granted_by = match &scope.viewer {
        crate::domain::auth::Viewer::User { uuid, .. } => uuid.clone(),
        crate::domain::auth::Viewer::Service { app } => format!("service:{app}"),
        crate::domain::auth::Viewer::Guest => String::new(),
    };
    let grant = grants::create(db, &body.user_uuid, &project, &body.report, body.card_id.as_deref(), Some(&granted_by)).await?;
    Ok((StatusCode::CREATED, private(grant)).into_response())
}

#[derive(Debug, Deserialize, utoipa::IntoParams)]
pub struct GrantQuery {
    /// Only the grants of this user UUID
    pub user_uuid: Option<String>,
}

#[utoipa::path(
    get,
    path = "/admin/projects/{project}/grants",
    summary = "Grants of a project",
    params(("project" = String, Path), GrantQuery),
    responses((status = 200, description = "Grants", body = [Grant])),
    tag = "Admin"
)]
pub async fn list_grants(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path(project): Path<String>,
    axum::extract::Query(q): axum::extract::Query<GrantQuery>,
) -> Result<Response, ReportError> {
    require_admin(&scope, &project)?;
    Ok(private(grants::for_project(&state.stores.db, &project, q.user_uuid.as_deref()).await?))
}

#[utoipa::path(
    delete,
    path = "/admin/projects/{project}/grants/{grant}",
    summary = "Revoke a grant",
    description = "The next request of that user no longer reads the resource. A grant of another project returns 403.",
    params(("project" = String, Path), ("grant" = String, Path)),
    responses((status = 204, description = "Revoked"), (status = 403, description = "Grant of another project"), (status = 404, description = "No such grant")),
    tag = "Admin"
)]
pub async fn delete_grant(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, grant)): Path<(String, String)>,
) -> Result<StatusCode, ReportError> {
    require_admin(&scope, &project)?;
    let db = &state.stores.db;
    if grants::delete(db, &project, &grant).await? {
        return Ok(StatusCode::NO_CONTENT);
    }
    let elsewhere = sqlx::query(&format!("SELECT project_slug FROM resource_grants WHERE {} = $1", db.text("id")))
        .bind(&grant)
        .fetch_optional(&db.pool)
        .await?;
    if elsewhere.is_some() {
        Err(ReportError::Forbidden("the grant belongs to another project".into()))
    } else {
        Err(ReportError::not_found(format!("grant '{grant}'")))
    }
}

#[utoipa::path(
    put,
    path = "/projects/{project}/admin/theme",
    summary = "Store the light and dark theme tokens of a project (super admin)",
    description = "Text contrast below WCAG AA is refused. A weak accent contrast is a warning.",
    request_body = ProjectTheme,
    params(("project" = String, Path)),
    responses((status = 200, description = "Saved theme and warnings"), (status = 422, description = "Invalid tokens")),
    tag = "Admin"
)]
pub async fn put_theme(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path(project): Path<String>,
    Json(theme): Json<ProjectTheme>,
) -> Result<Response, ReportError> {
    require_super_admin(&scope)?;
    catalog::active_project(&state.stores.db, &project).await?;
    let mut errors = Vec::new();
    let mut warnings = Vec::new();
    for (mode, tokens) in [("light", &theme.light), ("dark", &theme.dark)] {
        if let Some(tokens) = tokens {
            let check = validate_theme(&ThemeRecord {
                project: project.clone(),
                mode: mode.into(),
                tokens: tokens.clone(),
                updated_at: String::new(),
            });
            errors.extend(check.errors.into_iter().map(|e| crate::domain::guardrail::ValidationError::definition(mode, e)));
            warnings.extend(check.warnings.into_iter().map(|w| format!("{mode}: {w}")));
        }
    }
    if !errors.is_empty() {
        return Err(ReportError::Validation { message: "invalid theme".into(), violations: errors });
    }
    catalog::set_theme(&state.stores.db, &project, &theme).await?;
    Ok(private(json!({"project": project, "theme": theme, "warnings": warnings})))
}

// --- calculations -----------------------------------------------------------

#[utoipa::path(
    post,
    path = "/projects/{project}/admin/calculations",
    summary = "Create or replace a draft calculation version",
    description = "Omit `version` to create the next version. A published version cannot change.",
    request_body = crate::domain::calculations::CalculationDraftRequest,
    params(("project" = String, Path)),
    responses((status = 201, description = "Draft saved", body = crate::dal::CalculationVersion), (status = 409, description = "Version is published")),
    tag = "Admin"
)]
pub async fn post_calculation(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path(project): Path<String>,
    headers: HeaderMap,
    Json(body): Json<crate::domain::calculations::CalculationDraftRequest>,
) -> Result<Response, ReportError> {
    require_admin(&scope, &project)?;
    let fixture = fixture_of(&scope, &headers)?;
    let saved = crate::domain::calculations::save_draft(&state.datasets, &project, body).await?;
    fixtures::track(&state.stores.db, fixture.as_deref(), "calculation", &fixtures::version_id(&project, &saved.calculation_id, saved.version)).await?;
    Ok((StatusCode::CREATED, private(saved)).into_response())
}

#[utoipa::path(
    post,
    path = "/projects/{project}/admin/calculations/{calculation}/versions/{version}/validate",
    summary = "Dry run: the violations that a publish would report",
    params(("project" = String, Path), ("calculation" = String, Path), ("version" = i64, Path)),
    responses((status = 200, description = "Violations (empty when valid)", body = [crate::domain::guardrail::ValidationError])),
    tag = "Admin"
)]
pub async fn validate_calculation(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, calc, version)): Path<(String, String, i64)>,
) -> Result<Response, ReportError> {
    require_admin(&scope, &project)?;
    Ok(private(crate::domain::calculations::validate(&state.datasets, &project, &calc, version).await?))
}

#[utoipa::path(
    post,
    path = "/projects/{project}/admin/calculations/{calculation}/versions/{version}/publish",
    summary = "Validate and publish a draft calculation version (immutable from now on)",
    params(("project" = String, Path), ("calculation" = String, Path), ("version" = i64, Path)),
    responses((status = 200, description = "Published", body = crate::dal::CalculationVersion), (status = 409, description = "Not a draft"), (status = 422, description = "Invalid definition")),
    tag = "Admin"
)]
pub async fn publish_calculation(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, calc, version)): Path<(String, String, i64)>,
) -> Result<Response, ReportError> {
    require_admin(&scope, &project)?;
    Ok(private(crate::domain::calculations::publish(&state.datasets, &project, &calc, version).await?))
}

#[utoipa::path(
    post,
    path = "/projects/{project}/admin/calculations/{calculation}/versions/{version}/retire",
    summary = "Retire a published calculation version (no new cards; existing cards keep it)",
    params(("project" = String, Path), ("calculation" = String, Path), ("version" = i64, Path)),
    responses((status = 200, description = "Retired", body = crate::dal::CalculationVersion), (status = 409, description = "Not published")),
    tag = "Admin"
)]
pub async fn retire_calculation(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, calc, version)): Path<(String, String, i64)>,
) -> Result<Response, ReportError> {
    require_admin(&scope, &project)?;
    Ok(private(crate::domain::calculations::retire(&state.datasets, &project, &calc, version).await?))
}

#[utoipa::path(
    get,
    path = "/admin/projects/{project}/calculations",
    summary = "Every calculation version of a project",
    params(("project" = String, Path)),
    responses((status = 200, description = "Calculation versions", body = [crate::dal::CalculationVersion])),
    tag = "Admin"
)]
pub async fn list_calculations(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path(project): Path<String>,
) -> Result<Response, ReportError> {
    require_admin(&scope, &project)?;
    Ok(private(calculations::list(&state.stores.db, &project).await?))
}

#[derive(Debug, Deserialize, utoipa::IntoParams)]
pub struct SnapshotQuery {
    /// en, pt-BR or th (default en)
    pub lang: Option<String>,
}

#[utoipa::path(
    post,
    path = "/projects/{project}/admin/reports/{report}/datasets/{dataset}/snapshots",
    summary = "Store a durable snapshot of the current result in CouchDB",
    description = "The snapshot keeps the rows and the lineage (calculation version, input schema versions, source watermark, time).",
    params(("project" = String, Path), ("report" = String, Path), ("dataset" = String, Path), SnapshotQuery),
    responses((status = 201, description = "Snapshot stored")),
    tag = "Admin"
)]
pub async fn post_snapshot(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, report, dataset)): Path<(String, String, String)>,
    axum::extract::Query(q): axum::extract::Query<SnapshotQuery>,
) -> Result<Response, ReportError> {
    require_admin(&scope, &project)?;
    let lang = q.lang.unwrap_or_else(|| "en".into());
    let page = crate::domain::reports::dataset_page(
        &state.datasets, &project, &report, &dataset, &[], &lang, 0, crate::presentation::api::viewer::MAX_ROW_LIMIT, &scope,
    )
    .await?;
    let now = chrono::Utc::now().to_rfc3339();
    let snapshot = json!({
        "_id": format!("snap:{project}:{report}:{dataset}:{now}"),
        "type": "snapshot",
        "project": project, "report": report, "dataset_id": dataset,
        "language": lang, "created_at": now,
        "lineage": page.lineage, "total_rows": page.total_rows, "rows": page.rows,
    });
    state.stores.docs.put_snapshot(&snapshot).await?;
    Ok((StatusCode::CREATED, private(json!({"id": snapshot["_id"], "created_at": now, "lineage": snapshot["lineage"]}))).into_response())
}

#[utoipa::path(
    get,
    path = "/admin/projects/{project}/reports/{report}/datasets/{dataset}/snapshots",
    summary = "Stored snapshots of a dataset, newest first (at most 50)",
    params(("project" = String, Path), ("report" = String, Path), ("dataset" = String, Path)),
    responses((status = 200, description = "Snapshots")),
    tag = "Admin"
)]
pub async fn list_snapshots(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, report, dataset)): Path<(String, String, String)>,
) -> Result<Response, ReportError> {
    require_admin(&scope, &project)?;
    Ok(private(state.stores.docs.list_snapshots(&project, &report, &dataset, 50).await?))
}

// --- sample data (fixtures) -------------------------------------------------

#[derive(Debug, Default, serde::Serialize, ToSchema)]
pub struct FixtureRemoval {
    pub manifest: String,
    pub datasets: usize,
    pub reports: usize,
    pub calculations: usize,
    pub schemas: usize,
    pub records: usize,
    /// Owned entities that were kept because something not owned depends on them.
    pub kept: Vec<String>,
}

fn split3(id: &str) -> Option<(String, String, String)> {
    let mut p = id.splitn(3, '/');
    Some((p.next()?.to_string(), p.next()?.to_string(), p.next()?.to_string()))
}

#[utoipa::path(
    delete,
    path = "/admin/fixtures/{manifest}",
    summary = "Remove the sample data of one fixture manifest (service key only)",
    description = "Removes only entities that the manifest owns: cards, reports, calculation and schema versions, and the CouchDB records tagged with the manifest. A manually edited entity is no longer owned and stays. An owned report, calculation or schema that something not owned still uses stays too (listed in `kept`). Project catalog rows are never removed.",
    params(("manifest" = String, Path)),
    responses((status = 200, description = "Removal summary", body = FixtureRemoval), (status = 403, description = "Not a service key")),
    tag = "Admin"
)]
pub async fn delete_fixture(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path(manifest): Path<String>,
) -> Result<Response, ReportError> {
    if !matches!(scope.viewer, crate::domain::auth::Viewer::Service { .. }) {
        return Err(ReportError::Forbidden("fixture removal needs a service key".into()));
    }
    let db = &state.stores.db;
    let mut out = FixtureRemoval { manifest: manifest.clone(), ..Default::default() };
    let mut touched_schemas: std::collections::BTreeSet<(String, String)> = Default::default();

    for id in fixtures::entities(db, &manifest, "dataset").await? {
        if let Some((p, r, d)) = split3(&id) {
            state.datasets.definition_changed(&p, &r, &d).await;
            if catalog::delete_dataset(db, &p, &r, &d).await? {
                grants::delete_for_resource(db, &p, &r, Some(&d)).await?;
                out.datasets += 1;
            }
        }
        fixtures::forget(db, &manifest, "dataset", &id).await?;
    }
    for id in fixtures::entities(db, &manifest, "report").await? {
        if let Some((p, r)) = id.split_once('/') {
            if !catalog::list_datasets(db, p, r).await?.is_empty() {
                out.kept.push(format!("report {id} (it has cards that the fixture does not own)"));
                fixtures::forget(db, &manifest, "report", &id).await?;
                continue;
            }
            if catalog::delete_report(db, p, r).await? {
                grants::delete_for_resource(db, p, r, None).await?;
                out.reports += 1;
            }
        }
        fixtures::forget(db, &manifest, "report", &id).await?;
    }
    for id in fixtures::entities(db, &manifest, "calculation").await? {
        if let Some((p, c, v)) = split3(&id) {
            let version: i64 = v.parse().unwrap_or(0);
            let used = catalog::list_project_datasets(db, &p)
                .await?
                .iter()
                .any(|d| d.calculation_id == c && d.calculation_version == version);
            if used {
                out.kept.push(format!("calculation {id} (a card that the fixture does not own shows it)"));
            } else if calculations::delete_version(db, &p, &c, version).await? {
                out.calculations += 1;
            }
        }
        fixtures::forget(db, &manifest, "calculation", &id).await?;
    }
    let records = state.stores.docs.delete_fixture_records(&manifest).await?;
    out.records = records;
    for id in fixtures::entities(db, &manifest, "schema").await? {
        if let Some((p, s, v)) = split3(&id) {
            let version: i64 = v.parse().unwrap_or(0);
            touched_schemas.insert((p.clone(), s.clone()));
            let other_records = state
                .stores
                .docs
                .load_records(&p, &s, state.settings.max_scan_rows)
                .await?
                .iter()
                .any(|r| r.schema_version == version);
            let used = calculations::list(db, &p).await?.iter().any(|c| c.inputs.iter().any(|i| i.schema == s && i.version == version));
            if other_records || used {
                out.kept.push(format!("schema {id} (records or calculations that the fixture does not own use it)"));
            } else if schemas::delete_version(db, &p, &s, version).await? {
                out.schemas += 1;
            }
        }
        fixtures::forget(db, &manifest, "schema", &id).await?;
    }
    for (p, s) in touched_schemas {
        state.datasets.records_changed(&p, &s).await;
        state.datasets.catalog_changed(&p).await;
    }
    tracing::info!(manifest = %manifest, datasets = out.datasets, reports = out.reports, records = out.records, kept = out.kept.len(), "fixture removed");
    Ok(private(out))
}

// --- operations -------------------------------------------------------------

#[derive(Debug, serde::Serialize, ToSchema)]
pub struct OperationsView {
    pub postgres: bool,
    pub couchdb: bool,
    pub redis: bool,
    /// Schema copies held in memory, shared by every card that reads them.
    pub collections: Vec<crate::domain::datasets::service::LoadedCollection>,
    pub rows_in_memory: usize,
    /// Cache hits and misses and calculations since the engine started.
    pub cache: crate::domain::datasets::service::CacheCounters,
    pub running_calculations: usize,
}

#[utoipa::path(
    get,
    path = "/admin/operations",
    summary = "Data flow and resource use of this engine (super admin)",
    description = "Read only. Loaded schema copies with their watermark, rows in memory, cache hits and misses, calculations and store health.",
    responses((status = 200, description = "Operations view", body = OperationsView), (status = 403, description = "Not a super admin")),
    tag = "Admin"
)]
pub async fn operations(State(state): State<Arc<AppState>>, Caller(scope): Caller) -> Result<Response, ReportError> {
    require_super_admin(&scope)?;
    let (postgres, couchdb, redis) = tokio::join!(state.stores.db.health(), state.stores.docs.health(), state.stores.cache.health());
    let collections = state.datasets.loaded_collections();
    Ok(private(OperationsView {
        postgres,
        couchdb,
        redis,
        rows_in_memory: collections.iter().map(|c| c.rows).sum(),
        collections,
        cache: state.datasets.counters(),
        running_calculations: state.datasets.running_calculations(),
    }))
}
