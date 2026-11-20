use super::{
    identity::{require_session, resolve_lang, Caller},
    server::AppState,
    viewer::private,
};
use crate::{core::error::ReportError, domain::embeds};
use axum::{
    extract::{Path, Query, State},
    http::{header, HeaderMap, StatusCode},
    response::{IntoResponse, Response},
};
use std::{collections::HashMap, sync::Arc};
#[utoipa::path(get,path="/projects/{project}/showcase/{report}/cards/{dataset}/embed",summary="Embed descriptor of one public chart or table",responses((status=200,description="Copyable embed and thumbnail URLs",body=embeds::EmbedDescriptor),(status=401,description="Gated content is not public"),(status=404,description="Item not found")),tag="Reports")]
pub async fn descriptor(
    State(state): State<Arc<AppState>>,
    Path((project, report, dataset)): Path<(String, String, String)>,
    Query(query): Query<HashMap<String, String>>,
    headers: HeaderMap,
) -> Result<Response, ReportError> {
    let lang = resolve_lang(query.get("lang").map(String::as_str), &headers);
    Ok((
        [(header::CACHE_CONTROL, "no-store")],
        axum::Json(
            embeds::descriptor(&state.datasets, &project, &report, &dataset, &query, &lang).await?,
        ),
    )
        .into_response())
}
#[utoipa::path(get,path="/projects/{project}/showcase/{report}/cards/{dataset}/thumbnail.png",summary="PNG preview of one public chart or table",responses((status=200,description="PNG image"),(status=401,description="Gated content is not public"),(status=404,description="Item not found")),tag="Reports")]
pub async fn thumbnail(
    State(state): State<Arc<AppState>>,
    Path((project, report, dataset)): Path<(String, String, String)>,
    Query(query): Query<HashMap<String, String>>,
    headers: HeaderMap,
) -> Result<Response, ReportError> {
    let lang = resolve_lang(query.get("lang").map(String::as_str), &headers);
    let page =
        embeds::public_page(&state.datasets, &project, &report, &dataset, &query, &lang).await?;
    let (_, url, _) = embeds::item_urls(&project, &report, &dataset, &query);
    let key = crate::dal::embed_preview::cache_key(&url, &page);
    let bytes = if let Some(bytes) = state
        .stores
        .cache
        .get(&key)
        .await
        .and_then(|v| hex::decode(v).ok())
    {
        bytes
    } else {
        let bytes = crate::dal::embed_preview::capture(&state.settings, &url).await?;
        state
            .stores
            .cache
            .set(&key, &hex::encode(&bytes), 120)
            .await;
        bytes
    };
    Ok((
        StatusCode::OK,
        [
            (header::CONTENT_TYPE, "image/png"),
            (header::CACHE_CONTROL, "no-store"),
        ],
        bytes,
    )
        .into_response())
}

#[utoipa::path(
    get,
    path = "/projects/{project}/reports/{report}/cards/{dataset}/embed",
    summary = "Viewer-aware live or placeholder embed descriptor of one chart or table",
    responses(
        (status = 200, description = "Live embed descriptor or restricted placeholder", body = embeds::ViewerEmbedDescriptor),
        (status = 404, description = "Report or card not found")
    ),
    tag = "Reports"
)]
pub async fn viewer_descriptor(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, report, dataset)): Path<(String, String, String)>,
    Query(query): Query<HashMap<String, String>>,
    headers: HeaderMap,
) -> Result<Response, ReportError> {
    let lang = resolve_lang(query.get("lang").map(String::as_str), &headers);
    let body = embeds::viewer_descriptor(
        &state.datasets,
        &project,
        &report,
        &dataset,
        &query,
        &lang,
        &scope,
    )
    .await?;
    if scope.is_authenticated() {
        Ok(private(body))
    } else {
        Ok(([(header::CACHE_CONTROL, "no-store")], axum::Json(body)).into_response())
    }
}

#[utoipa::path(
    post,
    path = "/projects/{project}/reports/{report}/cards/{dataset}/snapshots",
    summary = "Capture a fixed durable snapshot of one card",
    responses(
        (status = 201, description = "Snapshot captured", body = embeds::CardSnapshotMeta),
        (status = 401, description = "No session"),
        (status = 403, description = "Access limited"),
        (status = 404, description = "Not found")
    ),
    tag = "Reports"
)]
pub async fn capture_snapshot(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, report, dataset)): Path<(String, String, String)>,
    Query(query): Query<HashMap<String, String>>,
    headers: HeaderMap,
) -> Result<Response, ReportError> {
    require_session(&scope)?;
    let lang = resolve_lang(query.get("lang").map(String::as_str), &headers);
    let meta =
        embeds::capture_snapshot(&state.datasets, &project, &report, &dataset, &lang, &scope)
            .await?;
    let mut response = private(meta);
    *response.status_mut() = StatusCode::CREATED;
    Ok(response)
}

#[utoipa::path(
    get,
    path = "/projects/{project}/reports/{report}/cards/{dataset}/snapshots/{snapshot}",
    summary = "Read metadata of one captured snapshot under source permissions",
    responses(
        (status = 200, description = "Snapshot metadata", body = embeds::CardSnapshotMeta),
        (status = 401, description = "No session"),
        (status = 403, description = "Access limited"),
        (status = 404, description = "Not found")
    ),
    tag = "Reports"
)]
pub async fn snapshot_meta(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, report, dataset, snapshot)): Path<(String, String, String, String)>,
) -> Result<Response, ReportError> {
    let meta = embeds::get_snapshot_meta(
        &state.datasets,
        &project,
        &report,
        &dataset,
        &snapshot,
        &scope,
    )
    .await?;
    Ok(private(meta))
}

#[utoipa::path(
    get,
    path = "/projects/{project}/reports/{report}/cards/{dataset}/snapshots/{snapshot}/content",
    summary = "Read fixed content of one captured snapshot under source permissions",
    responses(
        (status = 200, description = "Snapshot content", body = embeds::CardSnapshotContent),
        (status = 401, description = "No session"),
        (status = 403, description = "Access limited"),
        (status = 404, description = "Not found")
    ),
    tag = "Reports"
)]
pub async fn snapshot_content(
    State(state): State<Arc<AppState>>,
    Caller(scope): Caller,
    Path((project, report, dataset, snapshot)): Path<(String, String, String, String)>,
) -> Result<Response, ReportError> {
    let content = embeds::get_snapshot_content(
        &state.datasets,
        &project,
        &report,
        &dataset,
        &snapshot,
        &scope,
    )
    .await?;
    Ok(private(content))
}
