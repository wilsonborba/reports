//! Report catalog, report views and the guest showcase, with the access rules applied.
//!
//! Rules:
//! - The effective visibility of a dataset is the stricter of its report and its own value.
//! - Readable: public, signed-in for any session, restricted for admins and granted users.
//! - Not readable but discoverable: a safe placeholder (skeleton) with the stable ID, the
//!   approved title and the visibility label. No rows, fields, filters, formula or period.
//! - Not readable and not discoverable: hidden. It is omitted from lists and counts, and a
//!   direct request returns 404, so its existence does not leak.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::core::error::ReportError;
use crate::dal::{catalog, DatasetRecord, ProjectRecord, ReportRecord};
use crate::domain::auth::{ViewerScope, Visibility};
use crate::domain::composition::{domain_index, DomainIndex};
use crate::domain::datasets::engine::Row;
use crate::domain::datasets::service::AccessClass;
use crate::domain::datasets::spec::{resolve_text, DataTier, FilterParam};
use crate::domain::datasets::{DatasetDescriptor, DatasetPage, DatasetService};
use crate::domain::models::{AccessSummary, ProjectSummary, ReportPeriod, ReportSummary, ReportView};

/// Rows of each public card sent inline in the showcase.
pub const SHOWCASE_ROWS: usize = 500;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Access {
    Readable,
    /// Placeholder only.
    Discoverable,
    Hidden,
}

pub fn effective(report: &ReportRecord, dataset: &DatasetRecord) -> Visibility {
    Visibility::parse(&report.visibility).stricter(Visibility::parse(&dataset.visibility))
}

pub fn report_access(scope: &ViewerScope, r: &ReportRecord) -> Access {
    let v = Visibility::parse(&r.visibility);
    if scope.can_read_resource(&r.project, &r.slug, None, v)
        || (v == Visibility::Restricted && scope.is_authenticated() && scope.has_grant_in(&r.project, &r.slug))
    {
        Access::Readable
    } else if r.discoverable {
        Access::Discoverable
    } else {
        Access::Hidden
    }
}

/// Access to one dataset. `report` is the access to its report.
pub fn dataset_access(scope: &ViewerScope, r: &ReportRecord, report: Access, d: &DatasetRecord) -> Access {
    if report == Access::Hidden {
        return Access::Hidden;
    }
    if report == Access::Readable && scope.can_read_resource(&r.project, &r.slug, Some(&d.dataset_id), effective(r, d)) {
        Access::Readable
    } else if d.discoverable {
        Access::Discoverable
    } else {
        Access::Hidden
    }
}

/// Cards of a report in the order of its `card_order`, then the others by ID.
async fn ordered_datasets(svc: &DatasetService, r: &ReportRecord) -> Result<Vec<DatasetRecord>, ReportError> {
    let mut datasets = catalog::list_datasets(&svc.stores().db, &r.project, &r.slug).await?;
    let order = &r.metadata.card_order;
    let rank = |id: &str| order.iter().position(|o| o == id).unwrap_or(order.len());
    datasets.sort_by(|a, b| rank(&a.dataset_id).cmp(&rank(&b.dataset_id)).then_with(|| a.dataset_id.cmp(&b.dataset_id)));
    Ok(datasets)
}

fn report_tier(datasets: &[DatasetRecord]) -> DataTier {
    DataTier::aggregate(datasets.iter().map(|d| d.data_tier))
}

/// Distinct tiers of the cards, real first.
fn tiers_of(datasets: &[DatasetRecord]) -> Vec<DataTier> {
    [DataTier::Real, DataTier::Hybrid, DataTier::Sample]
        .into_iter()
        .filter(|t| datasets.iter().any(|d| d.data_tier == *t))
        .collect()
}

/// Counts of an answer. `cards` holds the effective visibility of each card and whether
/// the caller reads it. A signed-in placeholder opens with any session, so only a guest
/// needs to sign in for it; a restricted one needs an admin or a grant.
fn access_summary(scope: &ViewerScope, cards: &[(Visibility, bool)]) -> AccessSummary {
    let mut out = AccessSummary { total: cards.len(), ..AccessSummary::default() };
    for (visibility, readable) in cards {
        match (readable, visibility) {
            (true, _) => out.readable += 1,
            (false, Visibility::Restricted) => out.needs_admin += 1,
            (false, _) if !scope.is_authenticated() => out.needs_sign_in += 1,
            (false, _) => out.needs_admin += 1,
        }
    }
    out
}

fn class_of(v: Visibility) -> AccessClass {
    if v == Visibility::Public {
        AccessClass::Public
    } else {
        AccessClass::Gated
    }
}

/// Reports of a project that the caller can see (readable or discoverable), with access.
async fn visible_reports(svc: &DatasetService, project: &str, scope: &ViewerScope) -> Result<Vec<(ReportRecord, Access)>, ReportError> {
    let all = catalog::list_reports(&svc.stores().db, project).await?;
    Ok(all
        .into_iter()
        .map(|r| {
            let a = report_access(scope, &r);
            (r, a)
        })
        .filter(|(_, a)| *a != Access::Hidden)
        .collect())
}

pub async fn project_summary(
    svc: &DatasetService,
    p: ProjectRecord,
    lang: &str,
    scope: &ViewerScope,
    index: &DomainIndex,
) -> Result<ProjectSummary, ReportError> {
    let report_count = visible_reports(svc, &p.slug, scope).await?.len() as i64;
    let (domain_status, mut domain) = index.lookup(p.domain_project_id.as_deref());
    if let Some(d) = domain.as_mut() {
        crate::domain::composition::attach_detail(svc.stores(), svc.domain_ttl(), d).await;
    }
    Ok(ProjectSummary {
        name: resolve_text(&p.name, lang),
        tagline: resolve_text(&p.tagline, lang),
        description: resolve_text(&p.description, lang),
        website_url: p.website_url.clone(),
        repository_url: p.repository_url.clone(),
        report_count,
        theme: p.theme.clone(),
        domain_status,
        domain,
        slug: p.slug,
    })
}

/// Every active project, with Domain details from one cached domain_api request.
pub async fn project_summaries(svc: &DatasetService, lang: &str, scope: &ViewerScope, domain_ttl: u64) -> Result<Vec<ProjectSummary>, ReportError> {
    let projects = catalog::list_projects(&svc.stores().db, true).await?;
    let index = domain_index(svc.stores(), domain_ttl).await;
    let mut out = Vec::new();
    for p in projects {
        out.push(project_summary(svc, p, lang, scope, &index).await?);
    }
    Ok(out)
}

async fn period(svc: &DatasetService, r: &ReportRecord) -> Result<Option<ReportPeriod>, ReportError> {
    match &r.metadata.period_source {
        Some(p) => Ok(svc
            .period(&r.project, &p.collection, &p.field)
            .await?
            .map(|(start, end)| ReportPeriod { start, end })),
        None => Ok(None),
    }
}

/// Report summaries that the caller can see, with an optional text search.
pub async fn report_summaries(
    svc: &DatasetService,
    project: &str,
    lang: &str,
    query: Option<&str>,
    tier: Option<DataTier>,
    scope: &ViewerScope,
) -> Result<Vec<ReportSummary>, ReportError> {
    catalog::active_project(&svc.stores().db, project).await?;
    let needle = query.map(|q| q.trim().to_lowercase()).filter(|q| !q.is_empty());
    let mut out = Vec::new();
    for (r, access) in visible_reports(svc, project, scope).await? {
        if let Some(n) = &needle {
            let hay = format!(
                "{} {} {} {}",
                r.slug,
                r.title.values().cloned().collect::<Vec<_>>().join(" "),
                resolve_text(&r.description, lang),
                r.metadata.tags.join(" ")
            )
            .to_lowercase();
            if !hay.contains(n.as_str()) {
                continue;
            }
        }
        let datasets: Vec<DatasetRecord> = catalog::list_datasets(&svc.stores().db, project, &r.slug)
            .await?
            .into_iter()
            .filter(|d| dataset_access(scope, &r, access, d) != Access::Hidden)
            .collect();
        let data_tier = report_tier(&datasets);
        if tier.is_some_and(|t| t != data_tier) {
            continue;
        }
        let count = |v: Visibility| datasets.iter().filter(|d| effective(&r, d) == v).count();
        out.push(ReportSummary {
            slug: r.slug.clone(),
            project: r.project.clone(),
            title: resolve_text(&r.title, lang),
            description: resolve_text(&r.description, lang),
            period: if access == Access::Readable { period(svc, &r).await? } else { None },
            dataset_count: datasets.len() as i64,
            updated_at: r.updated_at.clone(),
            tags: r.metadata.tags.clone(),
            data_tier,
            visibility: Visibility::parse(&r.visibility),
            can_view: access == Access::Readable,
            signed_in_cards: count(Visibility::SignedIn),
            restricted_cards: count(Visibility::Restricted),
        });
    }
    Ok(out)
}

async fn load_report(svc: &DatasetService, project: &str, report: &str) -> Result<ReportRecord, ReportError> {
    catalog::active_project(&svc.stores().db, project).await?;
    catalog::get_report(&svc.stores().db, project, report)
        .await?
        .ok_or_else(|| ReportError::not_found(format!("report '{project}/{report}'")))
}

fn not_found(project: &str, report: &str) -> ReportError {
    ReportError::not_found(format!("report '{project}/{report}'"))
}

/// Removes everything that could reveal protected data.
pub fn sanitize(mut d: DatasetDescriptor) -> DatasetDescriptor {
    d.can_view = false;
    d.description = String::new();
    d.equation = None;
    d.fields = Vec::new();
    d.filters = Vec::new();
    d
}

fn skeleton_descriptor(d: &DatasetRecord, visibility: Visibility, lang: &str) -> DatasetDescriptor {
    sanitize(DatasetDescriptor {
        dataset_id: d.dataset_id.clone(),
        title: resolve_text(&d.spec.title, lang),
        description: String::new(),
        equation: None,
        data_tier: d.data_tier,
        fields: Vec::new(),
        filters: Vec::new(),
        can_view: false,
        visibility: visibility.as_str().to_string(),
    })
}

/// Full report view for a session caller. Hidden: 404. Discoverable only: 401 or 403.
/// `tier` keeps only the cards of that tier; the report tier and the tier list stay those
/// of all the visible cards.
pub async fn report_view(
    svc: &DatasetService,
    project: &str,
    report: &str,
    lang: &str,
    tier: Option<DataTier>,
    scope: &ViewerScope,
) -> Result<ReportView, ReportError> {
    let r = load_report(svc, project, report).await?;
    match report_access(scope, &r) {
        Access::Hidden => return Err(not_found(project, report)),
        Access::Discoverable => return Err(scope.denied(&format!("report '{project}/{report}'"))),
        Access::Readable => {}
    }
    let datasets = ordered_datasets(svc, &r).await?;
    let mut descriptors = Vec::with_capacity(datasets.len());
    let mut shown = Vec::new();
    let mut cards = Vec::new();
    for d in &datasets {
        let visibility = effective(&r, d);
        let access = dataset_access(scope, &r, Access::Readable, d);
        if access == Access::Hidden {
            continue;
        }
        shown.push(d.clone());
        if tier.is_some_and(|t| t != d.data_tier) {
            continue;
        }
        cards.push((visibility, access == Access::Readable));
        if access == Access::Readable {
            let mut desc = svc.describe(d, lang).await?;
            desc.visibility = visibility.as_str().to_string();
            descriptors.push(desc);
        } else {
            descriptors.push(skeleton_descriptor(d, visibility, lang));
        }
    }
    Ok(ReportView {
        project: r.project.clone(),
        report: r.slug.clone(),
        title: resolve_text(&r.title, lang),
        description: resolve_text(&r.description, lang),
        tags: r.metadata.tags.clone(),
        period: period(svc, &r).await?,
        updated_at: r.updated_at.clone(),
        language: lang.to_string(),
        data_tier: report_tier(&shown),
        tiers: tiers_of(&shown),
        visibility: Visibility::parse(&r.visibility),
        access: access_summary(scope, &cards),
        datasets: descriptors,
    })
}

/// One page of dataset rows. Hidden: 404. Not readable: 401 (guest) or 403 (session).
#[allow(clippy::too_many_arguments)]
pub async fn dataset_page(
    svc: &DatasetService,
    project: &str,
    report: &str,
    dataset_id: &str,
    filters: &[FilterParam],
    lang: &str,
    offset: usize,
    limit: usize,
    scope: &ViewerScope,
) -> Result<DatasetPage, ReportError> {
    let r = load_report(svc, project, report).await?;
    let report_level = report_access(scope, &r);
    let d = catalog::get_dataset(&svc.stores().db, project, report, dataset_id)
        .await?
        .ok_or_else(|| ReportError::not_found(format!("dataset '{project}/{report}/{dataset_id}'")))?;
    match dataset_access(scope, &r, report_level, &d) {
        Access::Hidden => Err(ReportError::not_found(format!("dataset '{project}/{report}/{dataset_id}'"))),
        Access::Discoverable => Err(scope.denied(&format!("dataset '{project}/{report}/{dataset_id}'"))),
        Access::Readable => {
            let visibility = effective(&r, &d);
            let mut page = svc.page(&d, filters, lang, offset, limit, class_of(visibility)).await?;
            page.descriptor.visibility = visibility.as_str().to_string();
            Ok(page)
        }
    }
}

// --- guest showcase ---------------------------------------------------------

/// Safe placeholder of a gated card: a fixed synthetic shape, never derived from data.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct Skeleton {
    /// Always `chart`: the client draws its own synthetic shape.
    pub layout: String,
    /// What the viewer needs: `login` for signed-in data, `access` for restricted data.
    pub action: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ShowcaseCard {
    pub dataset_id: String,
    pub title: String,
    pub visibility: Visibility,
    pub data_tier: DataTier,
    pub can_view: bool,
    /// Fields and filters of a public card; None for a skeleton.
    pub descriptor: Option<DatasetDescriptor>,
    /// First rows of a public card; None for a skeleton.
    #[schema(value_type = Option<Vec<Object>>)]
    pub rows: Option<Vec<Row>>,
    pub total_rows: Option<usize>,
    pub skeleton: Option<Skeleton>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ShowcaseView {
    pub project: String,
    pub report: String,
    pub title: String,
    pub description: String,
    pub tags: Vec<String>,
    /// Only for a readable (public) report.
    pub period: Option<ReportPeriod>,
    pub updated_at: String,
    pub language: String,
    /// Tier of the whole report (all its visible cards, before a `tier` filter).
    pub data_tier: DataTier,
    /// Tiers of the visible cards, for the card filter (before a `tier` filter).
    pub tiers: Vec<DataTier>,
    pub visibility: Visibility,
    pub can_view: bool,
    pub access: AccessSummary,
    pub cards: Vec<ShowcaseCard>,
}

fn skeleton_card(d: &DatasetRecord, visibility: Visibility, lang: &str) -> ShowcaseCard {
    ShowcaseCard {
        dataset_id: d.dataset_id.clone(),
        title: resolve_text(&d.spec.title, lang),
        visibility,
        data_tier: d.data_tier,
        can_view: false,
        descriptor: None,
        rows: None,
        total_rows: None,
        skeleton: Some(Skeleton {
            layout: "chart".into(),
            action: if visibility == Visibility::SignedIn { "login" } else { "access" }.into(),
        }),
    }
}

/// Guest view of a report: public cards with data, discoverable gated cards as skeletons.
/// `tier` keeps only the cards of that tier, like the session view.
pub async fn showcase(svc: &DatasetService, project: &str, report: &str, lang: &str, tier: Option<DataTier>) -> Result<ShowcaseView, ReportError> {
    let scope = ViewerScope::guest();
    let r = load_report(svc, project, report).await?;
    let access = report_access(&scope, &r);
    if access == Access::Hidden {
        return Err(not_found(project, report));
    }
    let datasets = ordered_datasets(svc, &r).await?;
    let mut cards = Vec::new();
    let mut shown = Vec::new();
    for d in &datasets {
        let visibility = effective(&r, d);
        let card_access = dataset_access(&scope, &r, access, d);
        if card_access != Access::Hidden {
            shown.push(d.clone());
        }
        if tier.is_some_and(|t| t != d.data_tier) {
            continue;
        }
        match card_access {
            Access::Readable => {
                let page = svc.page(d, &[], lang, 0, SHOWCASE_ROWS, AccessClass::Public).await?;
                cards.push(ShowcaseCard {
                    dataset_id: d.dataset_id.clone(),
                    title: page.descriptor.title.clone(),
                    visibility,
                    data_tier: d.data_tier,
                    can_view: true,
                    total_rows: Some(page.total_rows),
                    rows: Some(page.rows),
                    descriptor: Some(page.descriptor),
                    skeleton: None,
                });
            }
            Access::Discoverable => cards.push(skeleton_card(d, visibility, lang)),
            Access::Hidden => {}
        }
    }
    let counts: Vec<(Visibility, bool)> = cards.iter().map(|c| (c.visibility, c.can_view)).collect();
    Ok(ShowcaseView {
        project: r.project.clone(),
        report: r.slug.clone(),
        title: resolve_text(&r.title, lang),
        description: resolve_text(&r.description, lang),
        tags: r.metadata.tags.clone(),
        period: if access == Access::Readable { period(svc, &r).await? } else { None },
        updated_at: r.updated_at.clone(),
        language: lang.to_string(),
        data_tier: report_tier(&shown),
        tiers: tiers_of(&shown),
        visibility: Visibility::parse(&r.visibility),
        can_view: access == Access::Readable,
        access: access_summary(&scope, &counts),
        cards,
    })
}

/// Guest rows of one public card. A discoverable gated card: 401. Hidden: 404.
#[allow(clippy::too_many_arguments)]
pub async fn showcase_card(
    svc: &DatasetService,
    project: &str,
    report: &str,
    dataset_id: &str,
    filters: &[FilterParam],
    lang: &str,
    offset: usize,
    limit: usize,
) -> Result<DatasetPage, ReportError> {
    dataset_page(svc, project, report, dataset_id, filters, lang, offset, limit, &ViewerScope::guest()).await
}

/// After an ingestion: calculates again the public datasets marked `warm` (explicit
/// high-traffic KPIs) that read `schema` (every warm dataset when None). Other datasets wait
/// for a request. Never runs at engine start. Failures are logged; they never fail the caller.
pub async fn warm_public(svc: &DatasetService, project: &str, schema: Option<&str>) -> usize {
    let guest = ViewerScope::guest();
    let db = &svc.stores().db;
    let Ok(reports) = catalog::list_reports(db, project).await else {
        return 0;
    };
    let mut warmed = 0;
    for r in reports {
        let Ok(datasets) = catalog::list_datasets(db, project, &r.slug).await else {
            continue;
        };
        for d in datasets {
            let depends = schema.is_none_or(|s| crate::domain::datasets::service::dependencies(&d.spec).contains(s));
            if !d.spec.warm || !depends || effective(&r, &d) != Visibility::Public || report_access(&guest, &r) != Access::Readable {
                continue;
            }
            match svc.page(&d, &[], "en", 0, 1, AccessClass::Public).await {
                Ok(_) => warmed += 1,
                Err(e) => tracing::warn!(project, report = %r.slug, dataset = %d.dataset_id, "warm-up failed: {}", e),
            }
        }
    }
    warmed
}
