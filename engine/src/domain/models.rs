//! API views. They hold data descriptions only: no layout, chart type or color.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use utoipa::ToSchema;

use crate::domain::auth::Visibility;
use crate::domain::datasets::spec::DataTier;
use crate::domain::datasets::DatasetDescriptor;
use crate::domain::composition::{DomainDetails, DomainStatus};
use crate::domain::themes::ProjectTheme;

/// First and last value of the report period field.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ReportPeriod {
    #[schema(value_type = Object)]
    pub start: Value,
    #[schema(value_type = Object)]
    pub end: Value,
}

/// Project entry of the catalog. A project has no provenance: reports and datasets have it.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ProjectSummary {
    pub slug: String,
    pub name: String,
    pub tagline: String,
    pub description: String,
    /// Product website, or the GitHub repository when the project has no domain.
    pub website_url: Option<String>,
    pub repository_url: Option<String>,
    /// Reports that this caller can see.
    pub report_count: i64,
    /// Theme colors and chart palette per mode; a missing mode uses the frontend fallback.
    pub theme: ProjectTheme,
    pub domain_status: DomainStatus,
    /// Extra description, links and cover from domain_api (presentation only).
    pub domain: Option<DomainDetails>,
}

/// Report entry of a catalog list (metadata only).
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ReportSummary {
    pub slug: String,
    pub project: String,
    pub title: String,
    pub description: String,
    pub period: Option<ReportPeriod>,
    pub dataset_count: i64,
    pub updated_at: String,
    pub tags: Vec<String>,
    /// Computed from the datasets: their common tier, or hybrid when they differ.
    pub data_tier: DataTier,
    pub visibility: Visibility,
    /// False for a discoverable report that the caller cannot open (placeholder only).
    pub can_view: bool,
    /// Visible cards whose effective visibility is `signed_in` (any session reads them).
    pub signed_in_cards: usize,
    /// Visible cards whose effective visibility is `restricted` (admin or grant).
    pub restricted_cards: usize,
}

/// Cards of a report that the caller sees, and what opens the ones it cannot read. The
/// client shows these numbers as they are (the access rules live in the engine).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct AccessSummary {
    /// Cards in the answer (readable cards and placeholders).
    pub total: usize,
    pub readable: usize,
    /// Placeholders that any session opens: a guest who signs in reads them.
    pub needs_sign_in: usize,
    /// Placeholders that need a project admin, the super admin or a grant.
    pub needs_admin: usize,
}

/// Report metadata and the descriptors of its datasets.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ReportView {
    pub project: String,
    pub report: String,
    pub title: String,
    pub description: String,
    pub tags: Vec<String>,
    pub period: Option<ReportPeriod>,
    pub updated_at: String,
    pub language: String,
    /// Tier of the whole report (all its visible cards, before a `tier` filter).
    pub data_tier: DataTier,
    /// Tiers of the visible cards, for the card filter (before a `tier` filter).
    pub tiers: Vec<DataTier>,
    pub visibility: Visibility,
    pub access: AccessSummary,
    pub datasets: Vec<DatasetDescriptor>,
}

/// One page of a catalog list.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct Paged<T> {
    pub items: Vec<T>,
    pub page: usize,
    pub page_size: usize,
    pub total: usize,
    pub language: String,
}

pub const DEFAULT_PAGE_SIZE: usize = 12;
pub const MAX_PAGE_SIZE: usize = 100;

pub fn paginate<T>(items: Vec<T>, page: Option<usize>, page_size: Option<usize>, lang: &str) -> Paged<T> {
    let page_size = page_size.unwrap_or(DEFAULT_PAGE_SIZE).clamp(1, MAX_PAGE_SIZE);
    let page = page.unwrap_or(1).max(1);
    let total = items.len();
    let items = items.into_iter().skip((page - 1) * page_size).take(page_size).collect();
    Paged { items, page, page_size, total, language: lang.to_string() }
}
