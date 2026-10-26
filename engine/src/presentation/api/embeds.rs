use super::{identity::resolve_lang, server::AppState};
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
