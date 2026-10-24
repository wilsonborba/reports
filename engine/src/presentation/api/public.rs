//! Guest routes. The gateway forwards them without a session check, so every caller here
//! is a guest and no identity header is read.

use std::sync::Arc;

use std::collections::HashMap;

use axum::extract::{Path, Query, State};
use axum::http::{header, HeaderMap, HeaderValue};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Deserialize;
use utoipa::IntoParams;

use super::identity::resolve_lang;
use super::server::AppState;
use crate::core::error::ReportError;
use crate::dal::catalog;
use crate::domain::auth::ViewerScope;
use crate::domain::composition::domain_index;
use crate::domain::datasets::{DatasetPage, FilterParam};
use crate::domain::models::{paginate, Paged, ProjectSummary, ReportSummary};
use crate::domain::reports::ShowcaseView;
use crate::domain::stats::{GlobalStats, ProjectStats};
use crate::domain::themes::{asodya_theme, ProjectTheme};
use crate::domain::{reports, stats};

#[derive(Debug, Deserialize, IntoParams)]
pub struct LangQuery {
    /// en, pt-BR or th (default: Accept-Language, then en)
    pub lang: Option<String>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct CatalogQuery {
    /// en, pt-BR or th
    pub lang: Option<String>,
    /// Page number, starting at 1 (default 1)
    pub page: Option<usize>,
    /// Items per page (default 12, maximum 100)
    pub page_size: Option<usize>,
    /// Text search in slug, title, description and tags (reports only)
    pub q: Option<String>,
}

#[utoipa::path(
    get,
    path = "/catalog",
    summary = "List the selected projects",
    description = "Active Reports projects. Public. `report_count` counts only reports that a guest can read. Example: `curl https://api.asodya.com/apps/reports/v1/catalog`",
    params(CatalogQuery),
    responses((status = 200, description = "One page of the project catalog", body = Paged<ProjectSummary>)),
    tag = "Projects"
)]
pub async fn list_projects(
    State(state): State<Arc<AppState>>,
    Query(q): Query<CatalogQuery>,
    headers: HeaderMap,
) -> Result<Json<Paged<ProjectSummary>>, ReportError> {
    let lang = resolve_lang(q.lang.as_deref(), &headers);
    let items = reports::project_summaries(&state.datasets, &lang, &ViewerScope::guest(), state.settings.domain_cache_ttl_secs).await?;
    Ok(Json(paginate(items, q.page, q.page_size, &lang)))
}

#[utoipa::path(
    get,
    path = "/projects/{project}",
    summary = "Project detail",
    description = "Reports fields plus Domain details from one cached domain_api response. `domain_status` tells whether the Domain part is fresh, stale (dated last-known copy), unavailable, missing or unlinked. Example: `curl https://api.asodya.com/apps/reports/v1/projects/cortex`",
    params(("project" = String, Path, description = "Project slug, for example cortex"), LangQuery),
    responses(
        (status = 200, description = "Project summary", body = ProjectSummary),
        (status = 404, description = "Project not found")
    ),
    tag = "Projects"
)]
pub async fn project_detail(
    State(state): State<Arc<AppState>>,
    Path(project): Path<String>,
    Query(q): Query<LangQuery>,
    headers: HeaderMap,
) -> Result<Json<ProjectSummary>, ReportError> {
    let lang = resolve_lang(q.lang.as_deref(), &headers);
    let p = catalog::active_project(&state.stores.db, &project).await?;
    let index = domain_index(&state.stores, state.settings.domain_cache_ttl_secs).await;
    Ok(Json(reports::project_summary(&state.datasets, p, &lang, &ViewerScope::guest(), &index).await?))
}

#[utoipa::path(
    get,
    path = "/projects/{project}/theme",
    summary = "Project theme tokens",
    description = "Stored light and dark tokens, or the Asodya defaults. Example: `curl https://api.asodya.com/apps/reports/v1/projects/cortex/theme`",
    params(("project" = String, Path, description = "Project slug")),
    responses((status = 200, description = "Theme tokens", body = ProjectTheme), (status = 404, description = "Project not found")),
    tag = "Projects"
)]
pub async fn project_theme(
    State(state): State<Arc<AppState>>,
    Path(project): Path<String>,
) -> Result<Json<ProjectTheme>, ReportError> {
    let p = catalog::active_project(&state.stores.db, &project).await?;
    Ok(Json(if p.theme.light.is_some() || p.theme.dark.is_some() {
        p.theme
    } else {
        asodya_theme(&project)
    }))
}

#[utoipa::path(
    get,
    path = "/projects/{project}/reports",
    summary = "Reports that a guest can read",
    description = "Example: `curl https://api.asodya.com/apps/reports/v1/projects/cortex/reports`",
    params(("project" = String, Path, description = "Project slug"), CatalogQuery),
    responses((status = 200, description = "One page of report summaries", body = Paged<ReportSummary>), (status = 404, description = "Project not found")),
    tag = "Reports"
)]
pub async fn list_reports(
    State(state): State<Arc<AppState>>,
    Path(project): Path<String>,
    Query(q): Query<CatalogQuery>,
    headers: HeaderMap,
) -> Result<Json<Paged<ReportSummary>>, ReportError> {
    let lang = resolve_lang(q.lang.as_deref(), &headers);
    let items = reports::report_summaries(&state.datasets, &project, &lang, q.q.as_deref(), &ViewerScope::guest()).await?;
    Ok(Json(paginate(items, q.page, q.page_size, &lang)))
}

#[utoipa::path(
    get,
    path = "/stats",
    summary = "Totals over the data that a guest can read",
    params(LangQuery),
    responses((status = 200, description = "Totals of every project", body = GlobalStats)),
    tag = "Projects"
)]
pub async fn global_stats(
    State(state): State<Arc<AppState>>,
    Query(q): Query<LangQuery>,
    headers: HeaderMap,
) -> Result<Json<GlobalStats>, ReportError> {
    let lang = resolve_lang(q.lang.as_deref(), &headers);
    Ok(Json(stats::global_stats(&state.datasets, &lang, &ViewerScope::guest()).await?))
}

#[utoipa::path(
    get,
    path = "/projects/{project}/stats",
    summary = "Project statistics over the data that a guest can read",
    params(("project" = String, Path, description = "Project slug"), LangQuery),
    responses((status = 200, description = "Statistics of one project", body = ProjectStats), (status = 404, description = "Project not found")),
    tag = "Projects"
)]
pub async fn project_stats(
    State(state): State<Arc<AppState>>,
    Path(project): Path<String>,
    Query(q): Query<LangQuery>,
    headers: HeaderMap,
) -> Result<Json<ProjectStats>, ReportError> {
    let lang = resolve_lang(q.lang.as_deref(), &headers);
    Ok(Json(stats::project_stats(&state.datasets, &project, &lang, &ViewerScope::guest()).await?))
}

/// Guest responses are the same for everyone, so a shared cache may keep them briefly.
pub fn public<T: serde::Serialize>(body: T) -> Response {
    let mut response = Json(body).into_response();
    response
        .headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("public, max-age=30"));
    response
}

#[utoipa::path(
    get,
    path = "/projects/{project}/showcase/{report}",
    summary = "Guest view of a report",
    description = "Public cards come with their first rows. Discoverable signed-in or restricted cards come as a skeleton only (stable ID, title, visibility, no data). Other cards are omitted. Example: `curl https://api.asodya.com/apps/reports/v1/projects/cortex/showcase/token-usage`",
    params(("project" = String, Path), ("report" = String, Path), LangQuery),
    responses((status = 200, description = "Report with public cards and skeletons", body = ShowcaseView), (status = 404, description = "Not found or hidden")),
    tag = "Reports"
)]
pub async fn showcase(
    State(state): State<Arc<AppState>>,
    Path((project, report)): Path<(String, String)>,
    Query(q): Query<LangQuery>,
    headers: HeaderMap,
) -> Result<Response, ReportError> {
    let lang = resolve_lang(q.lang.as_deref(), &headers);
    Ok(public(reports::showcase(&state.datasets, &project, &report, &lang).await?))
}

#[utoipa::path(
    get,
    path = "/projects/{project}/showcase/{report}/cards/{card}",
    summary = "Guest rows of one public card",
    description = "401 for a gated card (login may help), 404 for a hidden one. Same filters and paging as the session route. Example: `curl https://api.asodya.com/apps/reports/v1/projects/cortex/showcase/token-usage/cards/tokens-by-provider`",
    params(
        ("project" = String, Path), ("report" = String, Path), ("card" = String, Path),
        ("lang" = Option<String>, Query, description = "en, pt-BR or th"),
        ("limit" = Option<usize>, Query, description = "Rows per page (default 500, maximum 5000)"),
        ("offset" = Option<usize>, Query, description = "First row"),
    ),
    responses((status = 200, description = "Card rows", body = DatasetPage), (status = 401, description = "Gated card"), (status = 404, description = "Not found or hidden")),
    tag = "Reports"
)]
pub async fn showcase_card(
    State(state): State<Arc<AppState>>,
    Path((project, report, card)): Path<(String, String, String)>,
    Query(query): Query<HashMap<String, String>>,
    headers: HeaderMap,
) -> Result<Response, ReportError> {
    let lang = resolve_lang(query.get("lang").map(String::as_str), &headers);
    let (offset, limit) = super::viewer::paging(&query)?;
    let filters = FilterParam::parse_query(&query);
    Ok(public(reports::showcase_card(&state.datasets, &project, &report, &card, &filters, &lang, offset, limit).await?))
}
