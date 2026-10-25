//! Session routes. Behind the gateway they need a `sid` session, and the engine reads the
//! real `x-uuid`. Responses are private: no shared or CDN cache.

use std::collections::HashMap;
use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::http::{header, HeaderMap, HeaderValue};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Serialize;
use utoipa::ToSchema;

use super::identity::{require_session, resolve_lang, Caller};
use super::public::{CatalogQuery, ReportQuery};
use super::server::AppState;
use crate::core::error::ReportError;
use crate::domain::datasets::{DatasetPage, FilterParam};
use crate::domain::models::{paginate, Paged, ReportSummary, ReportView};
use crate::domain::reports;

/// Default and maximum number of dataset rows per request.
pub const DEFAULT_ROW_LIMIT: usize = 500;
pub const MAX_ROW_LIMIT: usize = 5000;

/// Session responses must never be stored by a shared cache.
pub fn private<T: Serialize>(body: T) -> Response {
    let mut response = Json(body).into_response();
    response
        .headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("private, no-store"));
    response
}

#[derive(Debug, Serialize, ToSchema)]
pub struct MeResponse {
    /// Asodya user UUID from the gateway session; null for a service key.
    pub user_id: Option<String>,
    /// guest, viewer, project_admin, super_admin or service
    pub role: String,
    pub is_super_admin: bool,
    /// Projects where the user is project admin (from `user_project_roles`).
    pub admin_projects: Vec<String>,
}

#[utoipa::path(
    get,
    path = "/me",
    summary = "The current caller and its roles",
    description = "Example: `curl --cookie 'sid=...' https://api.asodya.com/apps/reports/v1/me`",
    responses((status = 200, description = "Caller and roles", body = MeResponse), (status = 401, description = "No session")),
    tag = "Session"
)]
pub async fn me(Caller(scope): Caller) -> Result<Response, ReportError> {
    require_session(&scope)?;
    Ok(private(MeResponse {
        user_id: scope.user_uuid().map(str::to_string),
        role: scope.role().to_string(),
        is_super_admin: scope.is_super_admin(),
        admin_projects: scope.admin_projects.clone(),
    }))
}

#[utoipa::path(
    get,
    path = "/me/projects/{project}/reports",
    summary = "Reports that the signed-in caller can read",
    params(("project" = String, Path, description = "Project slug"), CatalogQuery),
    responses((status = 200, description = "One page of report summaries", body = Paged<ReportSummary>), (status = 401, description = "No session")),
    tag = "Session"
)]
pub async fn my_reports(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path(project): Path<String>,
    Query(q): Query<CatalogQuery>,
    headers: HeaderMap,
) -> Result<Response, ReportError> {
    require_session(&scope)?;
    let lang = resolve_lang(q.lang.as_deref(), &headers);
    let items = reports::report_summaries(&state.datasets, &project, &lang, q.q.as_deref(), q.tier, &scope).await?;
    Ok(private(paginate(items, q.page, q.page_size, &lang)))
}

#[utoipa::path(
    get,
    path = "/projects/{project}/reports/{report}",
    summary = "Report view for the caller",
    description = "Readable datasets come with fields and filters. A dataset that the caller cannot read has `can_view = false` and no fields, filters or formula.",
    params(("project" = String, Path), ("report" = String, Path), ReportQuery),
    responses(
        (status = 200, description = "Report metadata and dataset descriptors", body = ReportView),
        (status = 401, description = "No session"),
        (status = 403, description = "Access limited"),
        (status = 404, description = "Not found")
    ),
    tag = "Reports"
)]
pub async fn report_view(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, report)): Path<(String, String)>,
    Query(q): Query<ReportQuery>,
    headers: HeaderMap,
) -> Result<Response, ReportError> {
    let lang = resolve_lang(q.lang.as_deref(), &headers);
    Ok(private(reports::report_view(&state.datasets, &project, &report, &lang, q.tier, &scope).await?))
}

#[utoipa::path(
    get,
    path = "/projects/{project}/reports/{report}/datasets/{dataset}",
    summary = "Dataset rows for the caller",
    description = "Runs the published definition. Filters: `f.<field>=a,b`, `f.<field>.from=`, `f.<field>.to=`. The same rows feed the PDF, Markdown and CSV exports.",
    params(
        ("project" = String, Path), ("report" = String, Path), ("dataset" = String, Path),
        ("lang" = Option<String>, Query, description = "en, pt-BR or th"),
        ("limit" = Option<usize>, Query, description = "Rows per page (default 500, maximum 5000)"),
        ("offset" = Option<usize>, Query, description = "First row"),
    ),
    responses(
        (status = 200, description = "Dataset rows", body = DatasetPage),
        (status = 400, description = "Invalid filter or paging"),
        (status = 401, description = "No session"),
        (status = 403, description = "Access limited"),
        (status = 404, description = "Not found")
    ),
    tag = "Reports"
)]
pub async fn dataset_page(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, report, dataset)): Path<(String, String, String)>,
    Query(query): Query<HashMap<String, String>>,
    headers: HeaderMap,
) -> Result<Response, ReportError> {
    let lang = resolve_lang(query.get("lang").map(String::as_str), &headers);
    let (offset, limit) = paging(&query)?;
    let filters = FilterParam::parse_query(&query);
    let page = reports::dataset_page(&state.datasets, &project, &report, &dataset, &filters, &lang, offset, limit, &scope).await?;
    Ok(private(page))
}

pub fn paging(query: &HashMap<String, String>) -> Result<(usize, usize), ReportError> {
    let parse = |k: &str| -> Result<Option<usize>, ReportError> {
        query
            .get(k)
            .map(|v| v.parse::<usize>().map_err(|_| ReportError::BadRequest(format!("'{k}' must be a number"))))
            .transpose()
    };
    let limit = parse("limit")?.unwrap_or(DEFAULT_ROW_LIMIT).clamp(1, MAX_ROW_LIMIT);
    Ok((parse("offset")?.unwrap_or(0), limit))
}
