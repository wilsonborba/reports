//! Project statistics for the public landing page. They count only what the caller can
//! read, so hidden reports never show up in a number.

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use utoipa::ToSchema;

use crate::core::error::ReportError;
use crate::dal::{catalog, schemas};
use crate::domain::auth::{ViewerScope, Visibility};
use crate::domain::datasets::service::dependencies;
use crate::domain::datasets::spec::resolve_text;
use crate::domain::datasets::DatasetService;
use crate::domain::reports::effective;

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ReportCount {
    pub report: String,
    pub title: String,
    pub value: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct DayCount {
    pub date: String,
    pub rows: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ProjectStats {
    pub project: String,
    pub reports: u64,
    /// Charts are the readable datasets.
    pub charts: u64,
    /// Schemas that the readable charts use.
    pub collections: u64,
    /// Stored records of those schemas.
    pub rows: u64,
    /// Fields of the published schemas that the readable charts use.
    pub fields: u64,
    /// Size of those payloads (JSON bytes).
    pub bytes: u64,
    pub period_start: Option<String>,
    pub period_end: Option<String>,
    pub rows_by_report: Vec<ReportCount>,
    pub charts_by_report: Vec<ReportCount>,
    pub rows_by_day: Vec<DayCount>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct GlobalStats {
    pub projects: u64,
    pub reports: u64,
    pub charts: u64,
    pub rows: u64,
    pub bytes: u64,
    pub items: Vec<ProjectStats>,
}

fn day_of(v: &Value) -> Option<String> {
    let s = v.as_str()?;
    let d = s.get(..10)?;
    let b = d.as_bytes();
    (b[4] == b'-' && b[7] == b'-' && d.chars().filter(|c| c.is_ascii_digit()).count() == 8).then(|| d.to_string())
}

/// Statistics of what guests can read, cached in Redis until the records of a used schema or
/// the catalog of the project change.
pub async fn project_stats(svc: &DatasetService, project: &str, lang: &str, scope: &ViewerScope) -> Result<ProjectStats, ReportError> {
    catalog::active_project(&svc.stores().db, project).await?;
    let cacheable = !scope.is_authenticated();
    let key = format!("stats:v1:{project}:{lang}");
    if cacheable {
        if let Some(hit) = svc.stores().cache.get(&key).await.and_then(|t| serde_json::from_str::<ProjectStats>(&t).ok()) {
            return Ok(hit);
        }
    }
    let (stats, used) = compute(svc, project, lang, scope).await?;
    if cacheable {
        if let Ok(text) = serde_json::to_string(&stats) {
            let cache = &svc.stores().cache;
            cache.set(&key, &text, svc.result_ttl()).await;
            cache.tag(&format!("catalog:{project}"), &key, svc.result_ttl()).await;
            for s in &used {
                cache.tag(&crate::domain::datasets::service::schema_tag(project, s), &key, svc.result_ttl()).await;
            }
        }
    }
    Ok(stats)
}

async fn compute(svc: &DatasetService, project: &str, lang: &str, scope: &ViewerScope) -> Result<(ProjectStats, BTreeSet<String>), ReportError> {
    let db = &svc.stores().db;
    let reports: Vec<_> = catalog::list_reports(db, project)
        .await?
        .into_iter()
        .filter(|r| scope.can_read(project, Visibility::parse(&r.visibility)))
        .collect();
    let mut used: BTreeSet<String> = BTreeSet::new();
    let mut charts = 0u64;
    let mut charts_by_report = Vec::new();
    let mut main_schema: Vec<(String, String, Option<String>)> = Vec::new();
    for r in &reports {
        let datasets: Vec<_> = catalog::list_datasets(db, project, &r.slug)
            .await?
            .into_iter()
            .filter(|d| scope.can_read(project, effective(r, d)))
            .collect();
        charts += datasets.len() as u64;
        charts_by_report.push(ReportCount {
            report: r.slug.clone(),
            title: resolve_text(&r.title, lang),
            value: datasets.len() as u64,
        });
        for d in &datasets {
            used.extend(dependencies(&d.spec));
        }
        let main = r
            .metadata
            .period_source
            .as_ref()
            .map(|p| p.collection.clone())
            .or_else(|| datasets.iter().find_map(|d| d.spec.source.clone()));
        main_schema.push((r.slug.clone(), resolve_text(&r.title, lang), main));
    }
    let mut counts: BTreeMap<String, u64> = BTreeMap::new();
    let mut rows = 0u64;
    let mut bytes = 0u64;
    for s in &used {
        let records = svc.collection(project, s).await?;
        counts.insert(s.clone(), records.len() as u64);
        rows += records.len() as u64;
        bytes += records
            .iter()
            .map(|p| serde_json::to_vec(p).map(|v| v.len() as u64).unwrap_or(0))
            .sum::<u64>();
    }
    let fields = schemas::list(db, project)
        .await?
        .into_iter()
        .filter(|s| s.status == "published" && used.contains(&s.schema_name))
        .map(|s| (s.schema_name, s.fields.len() as u64))
        .collect::<BTreeMap<_, _>>()
        .values()
        .sum();
    let rows_by_report = main_schema
        .iter()
        .map(|(slug, title, main)| ReportCount {
            report: slug.clone(),
            title: title.clone(),
            value: main.as_ref().and_then(|m| counts.get(m)).copied().unwrap_or(0),
        })
        .collect();
    let mut by_day: BTreeMap<String, u64> = BTreeMap::new();
    let mut seen = BTreeSet::new();
    for r in &reports {
        if let Some(p) = &r.metadata.period_source {
            if used.contains(&p.collection) && seen.insert((p.collection.clone(), p.field.clone())) {
                for doc in svc.collection(project, &p.collection).await?.iter() {
                    if let Some(day) = doc.get(&p.field).and_then(day_of) {
                        *by_day.entry(day).or_default() += 1;
                    }
                }
            }
        }
    }
    let stats = ProjectStats {
        project: project.to_string(),
        reports: reports.len() as u64,
        charts,
        collections: used.len() as u64,
        rows,
        fields,
        bytes,
        period_start: by_day.keys().next().cloned(),
        period_end: by_day.keys().next_back().cloned(),
        rows_by_report,
        charts_by_report,
        rows_by_day: by_day.into_iter().map(|(date, rows)| DayCount { date, rows }).collect(),
    };
    Ok((stats, used))
}

pub async fn global_stats(svc: &DatasetService, lang: &str, scope: &ViewerScope) -> Result<GlobalStats, ReportError> {
    let mut items = Vec::new();
    for p in catalog::list_projects(&svc.stores().db, true).await? {
        items.push(project_stats(svc, &p.slug, lang, scope).await?);
    }
    Ok(GlobalStats {
        projects: items.len() as u64,
        reports: items.iter().map(|s| s.reports).sum(),
        charts: items.iter().map(|s| s.charts).sum(),
        rows: items.iter().map(|s| s.rows).sum(),
        bytes: items.iter().map(|s| s.bytes).sum(),
        items,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn day_of_reads_iso_dates_only() {
        assert_eq!(day_of(&json!("2026-09-26")), Some("2026-09-26".into()));
        assert_eq!(day_of(&json!("2026-09-26T07:00:00+07:00")), Some("2026-09-26".into()));
        assert_eq!(day_of(&json!("26/09/2026")), None);
        assert_eq!(day_of(&json!(20260926)), None);
    }
}
