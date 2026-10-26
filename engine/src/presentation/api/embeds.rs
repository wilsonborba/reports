use super::{identity::resolve_lang, public::public, server::AppState};
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
    Ok(public(
        embeds::descriptor(&state.datasets, &project, &report, &dataset, &query, &lang).await?,
    ))
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
    let bytes = tokio::task::spawn_blocking(move || {
        embeds::preview_png(
            &page,
            query.get("view").is_some_and(|v| v == "table"),
            query
                .get("visual")
                .is_some_and(|v| matches!(v.as_str(), "line" | "area")),
        )
    })
    .await
    .map_err(|_| ReportError::Internal("Preview rendering failed".into()))??;
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
