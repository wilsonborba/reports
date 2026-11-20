use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::IntoResponse;
use axum::Json;
use serde::Deserialize;

use crate::core::error::ReportError;
use crate::domain::owner::{self, CreateOwnerItemInput, PatchOwnerItemInput, ReplaceDatasetInput};
use crate::presentation::api::identity::Caller;
use crate::presentation::api::server::AppState;

#[derive(Deserialize)]
pub struct DeleteParams {
    #[serde(default)]
    pub confirm: bool,
}

pub async fn create_item(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path(project): Path<String>,
    headers: HeaderMap,
    Json(body): Json<CreateOwnerItemInput>,
) -> Result<impl IntoResponse, ReportError> {
    let idemp = headers.get("idempotency-key").and_then(|v| v.to_str().ok());
    let (detail, created) = owner::create_item(
        &state.stores,
        &state.datasets,
        &scope,
        &project,
        body,
        idemp,
    )
    .await?;
    let status = if created {
        StatusCode::CREATED
    } else {
        StatusCode::OK
    };
    Ok((
        status,
        [(header::ETAG, detail.item.etag.clone())],
        Json(detail),
    ))
}

pub async fn get_item(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path(id): Path<String>,
) -> Result<impl IntoResponse, ReportError> {
    let detail = owner::get_item(&state.stores, &scope, &id).await?;
    Ok((
        StatusCode::OK,
        [(header::ETAG, detail.item.etag.clone())],
        Json(detail),
    ))
}

pub async fn replace_dataset(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path(id): Path<String>,
    headers: HeaderMap,
    Json(body): Json<ReplaceDatasetInput>,
) -> Result<impl IntoResponse, ReportError> {
    let if_match = headers.get(header::IF_MATCH).and_then(|v| v.to_str().ok());
    let detail =
        owner::replace_dataset(&state.stores, &state.datasets, &scope, &id, if_match, body).await?;
    Ok((
        StatusCode::OK,
        [(header::ETAG, detail.item.etag.clone())],
        Json(detail),
    ))
}

pub async fn patch_item(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path(id): Path<String>,
    Json(body): Json<PatchOwnerItemInput>,
) -> Result<impl IntoResponse, ReportError> {
    let detail = owner::patch_item(&state.stores, &state.datasets, &scope, &id, body).await?;
    Ok((
        StatusCode::OK,
        [(header::ETAG, detail.item.etag.clone())],
        Json(detail),
    ))
}

pub async fn delete_item(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path(id): Path<String>,
    Query(q): Query<DeleteParams>,
) -> Result<impl IntoResponse, ReportError> {
    let outcome =
        owner::delete_item(&state.stores, &state.datasets, &scope, &id, q.confirm).await?;
    let status = if outcome.requires_confirmation {
        StatusCode::CONFLICT
    } else {
        StatusCode::OK
    };
    Ok((status, Json(outcome)))
}
