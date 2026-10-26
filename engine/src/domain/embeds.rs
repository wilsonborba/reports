//! Individual public-card descriptors. Charts are rendered only by Flutter Reports.
use crate::{
    core::error::ReportError,
    domain::{
        auth::ViewerScope,
        datasets::{DatasetPage, DatasetService, FilterParam},
        reports,
    },
};
use serde::Serialize;
use std::collections::{BTreeMap, HashMap};
use utoipa::ToSchema;
#[derive(Serialize, ToSchema)]
pub struct EmbedDescriptor {
    pub title: String,
    pub source_url: String,
    pub embed_url: String,
    pub thumbnail_url: String,
    pub html: String,
    pub width: u32,
    pub height: u32,
}
pub fn item_urls(
    project: &str,
    report: &str,
    dataset: &str,
    query: &HashMap<String, String>,
) -> (String, String, String) {
    let query: BTreeMap<_, _> = query
        .iter()
        .filter(|(k, _)| {
            k.starts_with("f.")
                || matches!(k.as_str(), "lang" | "visual" | "view" | "theme" | "render")
        })
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect();
    let encoded = url::form_urlencoded::Serializer::new(String::new())
        .extend_pairs(query)
        .finish();
    let suffix = if encoded.is_empty() {
        String::new()
    } else {
        format!("?{encoded}")
    };
    let p = urlencoding::encode(project);
    let r = urlencoding::encode(report);
    let d = urlencoding::encode(dataset);
    (format!("https://reports.asodya.com/v1/menu/{p}/{r}/{d}{suffix}"),format!("https://reports.asodya.com/v1/embed/{p}/{r}/{d}{suffix}"),format!("https://api.asodya.com/apps/reports/v1/projects/{p}/showcase/{r}/cards/{d}/thumbnail.png{suffix}"))
}
pub async fn public_page(
    svc: &DatasetService,
    project: &str,
    report: &str,
    dataset: &str,
    query: &HashMap<String, String>,
    lang: &str,
) -> Result<DatasetPage, ReportError> {
    reports::dataset_page(
        svc,
        project,
        report,
        dataset,
        &FilterParam::parse_query(query),
        lang,
        0,
        8,
        &ViewerScope::guest(),
    )
    .await
}
pub async fn descriptor(
    svc: &DatasetService,
    project: &str,
    report: &str,
    dataset: &str,
    query: &HashMap<String, String>,
    lang: &str,
) -> Result<EmbedDescriptor, ReportError> {
    let page = public_page(svc, project, report, dataset, query, lang).await?;
    let (source_url, embed_url, thumbnail_url) = item_urls(project, report, dataset, query);
    let html=format!("<iframe src=\"{}\" title=\"{}\" width=\"100%\" height=\"480\" loading=\"lazy\" style=\"border:0\" referrerpolicy=\"strict-origin-when-cross-origin\"></iframe>",escape(&embed_url),escape(&page.descriptor.title));
    Ok(EmbedDescriptor {
        title: page.descriptor.title,
        source_url,
        embed_url,
        thumbnail_url,
        html,
        width: 800,
        height: 480,
    })
}
fn escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}
