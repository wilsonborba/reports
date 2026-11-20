//! Individual public-card descriptors. Charts are rendered only by Flutter Reports.
use crate::{
    core::error::ReportError,
    dal::catalog::{self, CardSnapshotRow},
    domain::{
        auth::ViewerScope,
        datasets::{DatasetDescriptor, DatasetPage, DatasetService, FilterParam},
        reports::{self, Access},
    },
};
use chrono::Utc;
use serde::Serialize;
use serde_json::{json, Value};
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

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct EmbedPlaceholder {
    pub layout: String,
    pub action: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct ViewerEmbedDescriptor {
    pub status: String,
    pub can_view: bool,
    pub title: String,
    pub source_url: String,
    pub embed_url: String,
    pub thumbnail_url: Option<String>,
    pub html: Option<String>,
    pub width: u32,
    pub height: u32,
    pub placeholder: Option<EmbedPlaceholder>,
    #[schema(value_type = Option<Vec<Object>>)]
    pub rows: Option<Vec<Value>>,
    pub total_rows: Option<usize>,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct CardSnapshotMeta {
    pub id: String,
    pub project: String,
    pub report: String,
    pub dataset_id: String,
    pub title: String,
    pub captured_at: String,
    pub captured_by: String,
    pub total_rows: i64,
    pub open_in_reports_url: String,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct CardSnapshotContent {
    pub id: String,
    pub project: String,
    pub report: String,
    pub dataset_id: String,
    pub title: String,
    pub captured_at: String,
    pub captured_by: String,
    pub total_rows: i64,
    pub descriptor: DatasetDescriptor,
    #[schema(value_type = Vec<Object>)]
    pub rows: Vec<Value>,
    pub open_in_reports_url: String,
}

pub async fn viewer_descriptor(
    svc: &DatasetService,
    project: &str,
    report: &str,
    dataset: &str,
    query: &HashMap<String, String>,
    lang: &str,
    scope: &ViewerScope,
) -> Result<ViewerEmbedDescriptor, ReportError> {
    let db = &svc.stores().db;
    catalog::active_project(db, project).await?;
    let r = catalog::get_report(db, project, report)
        .await?
        .ok_or_else(|| ReportError::not_found(format!("report '{project}/{report}'")))?;
    let d = catalog::get_dataset(db, project, report, dataset)
        .await?
        .ok_or_else(|| ReportError::not_found(format!("dataset '{project}/{report}/{dataset}'")))?;

    let report_level = reports::report_access(scope, &r);
    let access = reports::dataset_access(scope, &r, report_level, &d);
    let (source_url, embed_url, thumbnail_url) = item_urls(project, report, dataset, query);

    if access == Access::Readable {
        let page = reports::dataset_page(
            svc,
            project,
            report,
            dataset,
            &FilterParam::parse_query(query),
            lang,
            0,
            8,
            scope,
        )
        .await?;
        let html = format!(
            "<iframe src=\"{}\" title=\"{}\" width=\"100%\" height=\"480\" loading=\"lazy\" style=\"border:0\" referrerpolicy=\"strict-origin-when-cross-origin\"></iframe>",
            escape(&embed_url),
            escape(&page.descriptor.title)
        );
        let rows: Vec<Value> = page
            .rows
            .into_iter()
            .filter_map(|row| serde_json::to_value(row).ok())
            .collect();
        return Ok(ViewerEmbedDescriptor {
            status: "readable".to_string(),
            can_view: true,
            title: page.descriptor.title,
            source_url,
            embed_url,
            thumbnail_url: Some(thumbnail_url),
            html: Some(html),
            width: 800,
            height: 480,
            placeholder: None,
            rows: Some(rows),
            total_rows: Some(page.total_rows),
        });
    }

    let action = if !scope.is_authenticated() {
        "login"
    } else {
        "access"
    };
    let message = if action == "login" {
        "Sign in to view this report".to_string()
    } else {
        "Access to this report is restricted".to_string()
    };
    let title = if access == Access::Discoverable {
        crate::domain::datasets::spec::resolve_text(&d.spec.title, lang)
    } else {
        "Restricted chart".to_string()
    };

    Ok(ViewerEmbedDescriptor {
        status: "placeholder".to_string(),
        can_view: false,
        title,
        source_url,
        embed_url,
        thumbnail_url: None,
        html: None,
        width: 800,
        height: 480,
        placeholder: Some(EmbedPlaceholder {
            layout: "chart".to_string(),
            action: action.to_string(),
            message,
        }),
        rows: None,
        total_rows: None,
    })
}

async fn ensure_source_readable(
    svc: &DatasetService,
    project: &str,
    report: &str,
    dataset: &str,
    scope: &ViewerScope,
) -> Result<(), ReportError> {
    let db = &svc.stores().db;
    catalog::active_project(db, project).await?;
    let r = catalog::get_report(db, project, report)
        .await?
        .ok_or_else(|| ReportError::not_found(format!("report '{project}/{report}'")))?;
    let d = catalog::get_dataset(db, project, report, dataset)
        .await?
        .ok_or_else(|| ReportError::not_found(format!("dataset '{project}/{report}/{dataset}'")))?;
    let report_level = reports::report_access(scope, &r);
    match reports::dataset_access(scope, &r, report_level, &d) {
        Access::Readable => Ok(()),
        Access::Discoverable => {
            Err(scope.denied(&format!("dataset '{project}/{report}/{dataset}'")))
        }
        Access::Hidden => Err(ReportError::not_found(format!(
            "dataset '{project}/{report}/{dataset}'"
        ))),
    }
}

pub async fn capture_snapshot(
    svc: &DatasetService,
    project: &str,
    report: &str,
    dataset: &str,
    lang: &str,
    scope: &ViewerScope,
) -> Result<CardSnapshotMeta, ReportError> {
    let captured_by = scope
        .user_uuid()
        .ok_or(ReportError::Unauthorized)?
        .to_string();
    let page =
        reports::dataset_page(svc, project, report, dataset, &[], lang, 0, 5000, scope).await?;
    let snapshot_id = uuid::Uuid::new_v4().to_string();
    let couch_doc_id = format!("card-snapshot:{snapshot_id}");
    let captured_at = Utc::now().to_rfc3339();
    let (open_in_reports_url, _, _) = item_urls(project, report, dataset, &HashMap::new());
    let total_rows = page.total_rows as i64;
    let title = page.descriptor.title.clone();

    let doc = json!({
        "_id": couch_doc_id,
        "type": "snapshot",
        "kind": "card_snapshot",
        "snapshot_id": snapshot_id,
        "project": project,
        "report": report,
        "dataset_id": dataset,
        "title": title,
        "captured_by": captured_by,
        "created_at": captured_at,
        "total_rows": total_rows,
        "descriptor": page.descriptor,
        "rows": page.rows,
    });
    svc.stores().docs.put_snapshot(&doc).await?;

    let row = CardSnapshotRow {
        id: snapshot_id.clone(),
        project_slug: project.to_string(),
        report_slug: report.to_string(),
        dataset_id: dataset.to_string(),
        captured_by: captured_by.clone(),
        captured_at: captured_at.clone(),
        couch_doc_id,
        total_rows,
    };
    catalog::insert_card_snapshot(&svc.stores().db, &row).await?;

    Ok(CardSnapshotMeta {
        id: snapshot_id,
        project: project.to_string(),
        report: report.to_string(),
        dataset_id: dataset.to_string(),
        title,
        captured_at,
        captured_by,
        total_rows,
        open_in_reports_url,
    })
}

pub async fn get_snapshot_meta(
    svc: &DatasetService,
    project: &str,
    report: &str,
    dataset: &str,
    snapshot_id: &str,
    scope: &ViewerScope,
) -> Result<CardSnapshotMeta, ReportError> {
    ensure_source_readable(svc, project, report, dataset, scope).await?;
    let row = catalog::get_card_snapshot(&svc.stores().db, project, report, dataset, snapshot_id)
        .await?
        .ok_or_else(|| ReportError::not_found(format!("snapshot '{snapshot_id}'")))?;
    let doc = svc
        .stores()
        .docs
        .get_snapshot(&row.couch_doc_id)
        .await?
        .ok_or_else(|| ReportError::not_found(format!("snapshot payload '{snapshot_id}'")))?;
    let (open_in_reports_url, _, _) = item_urls(project, report, dataset, &HashMap::new());
    Ok(CardSnapshotMeta {
        id: row.id,
        project: row.project_slug,
        report: row.report_slug,
        dataset_id: row.dataset_id,
        title: doc["title"].as_str().unwrap_or_default().to_string(),
        captured_at: row.captured_at,
        captured_by: row.captured_by,
        total_rows: row.total_rows,
        open_in_reports_url,
    })
}

pub async fn get_snapshot_content(
    svc: &DatasetService,
    project: &str,
    report: &str,
    dataset: &str,
    snapshot_id: &str,
    scope: &ViewerScope,
) -> Result<CardSnapshotContent, ReportError> {
    ensure_source_readable(svc, project, report, dataset, scope).await?;
    let row = catalog::get_card_snapshot(&svc.stores().db, project, report, dataset, snapshot_id)
        .await?
        .ok_or_else(|| ReportError::not_found(format!("snapshot '{snapshot_id}'")))?;
    let doc = svc
        .stores()
        .docs
        .get_snapshot(&row.couch_doc_id)
        .await?
        .ok_or_else(|| ReportError::not_found(format!("snapshot payload '{snapshot_id}'")))?;
    let descriptor: DatasetDescriptor = serde_json::from_value(doc["descriptor"].clone())
        .map_err(|e| ReportError::Internal(format!("snapshot descriptor: {e}")))?;
    let rows: Vec<Value> = doc["rows"].as_array().cloned().unwrap_or_default();
    let (open_in_reports_url, _, _) = item_urls(project, report, dataset, &HashMap::new());
    Ok(CardSnapshotContent {
        id: row.id,
        project: row.project_slug,
        report: row.report_slug,
        dataset_id: row.dataset_id,
        title: doc["title"].as_str().unwrap_or_default().to_string(),
        captured_at: row.captured_at,
        captured_by: row.captured_by,
        total_rows: row.total_rows,
        descriptor,
        rows,
        open_in_reports_url,
    })
}
