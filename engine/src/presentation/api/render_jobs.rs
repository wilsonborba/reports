use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Deserialize;

use super::identity::Caller;
use super::server::AppState;
use super::viewer::private;
use crate::core::error::ReportError;
use crate::domain::auth::ViewerScope;
use crate::domain::render_jobs::{self, CreateRenderJobInput};

fn require_trusted_service(scope: &ViewerScope) -> Result<(), ReportError> {
    if scope.is_super_admin() {
        Ok(())
    } else if !scope.is_authenticated() {
        Err(ReportError::Unauthorized)
    } else {
        Err(ReportError::Forbidden(
            "render_jobs require a trusted service key".into(),
        ))
    }
}

#[derive(Debug, Deserialize)]
pub struct DeleteRenderJobQuery {
    #[serde(default)]
    pub confirmed: bool,
}

#[derive(Debug, Deserialize)]
pub struct CleanupQuery {
    pub now_secs: Option<i64>,
}

#[utoipa::path(
    post,
    path = "/render_jobs",
    summary = "Create a temporary validated question visual render job",
    responses(
        (status = 201, description = "Render job created", body = render_jobs::RenderJob),
        (status = 400, description = "Invalid input"),
        (status = 401, description = "Unauthorized"),
        (status = 403, description = "Forbidden"),
        (status = 409, description = "Template not published")
    ),
    tag = "RenderJobs"
)]
pub async fn create(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Json(body): Json<CreateRenderJobInput>,
) -> Result<Response, ReportError> {
    require_trusted_service(&scope)?;
    let job = render_jobs::create_job(&state.stores, body).await?;
    let mut resp = private(job);
    *resp.status_mut() = StatusCode::CREATED;
    Ok(resp)
}

#[utoipa::path(
    get,
    path = "/render_jobs/{job_id}",
    summary = "Read a temporary question visual render job",
    responses(
        (status = 200, description = "Render job", body = render_jobs::RenderJob),
        (status = 401, description = "Unauthorized"),
        (status = 403, description = "Forbidden"),
        (status = 404, description = "Not found or expired")
    ),
    tag = "RenderJobs"
)]
pub async fn get(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path(job_id): Path<String>,
) -> Result<Response, ReportError> {
    require_trusted_service(&scope)?;
    let job = render_jobs::get_job(&state.stores, &job_id).await?;
    Ok(private(job))
}

#[utoipa::path(
    delete,
    path = "/render_jobs/{job_id}",
    summary = "Delete a temporary render job after durable FSM save confirmation",
    params(("confirmed" = bool, Query, description = "Must be true after durable save")),
    responses(
        (status = 200, description = "Render job deleted", body = render_jobs::DeleteRenderJobOutcome),
        (status = 409, description = "Save confirmation required"),
        (status = 404, description = "Not found")
    ),
    tag = "RenderJobs"
)]
pub async fn delete(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path(job_id): Path<String>,
    Query(q): Query<DeleteRenderJobQuery>,
) -> Result<Response, ReportError> {
    require_trusted_service(&scope)?;
    let out = render_jobs::delete_job(&state.stores, &job_id, q.confirmed).await?;
    Ok(private(out))
}

#[utoipa::path(
    post,
    path = "/render_jobs/cleanup",
    summary = "Clean up expired temporary render jobs",
    responses((status = 200, description = "Cleanup outcome", body = render_jobs::CleanupOutcome)),
    tag = "RenderJobs"
)]
pub async fn cleanup(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Query(q): Query<CleanupQuery>,
) -> Result<Response, ReportError> {
    require_trusted_service(&scope)?;
    let out = render_jobs::cleanup_expired(&state.stores, q.now_secs).await?;
    Ok((StatusCode::OK, private(out)).into_response())
}
