//! Domain project details for Reports projects, cached in Redis.
//!
//! One domain_api list request serves the whole catalog. Redis keeps a fresh copy (short
//! TTL) and a dated last-known copy (long TTL). When domain_api fails, Reports answers
//! with its own fields plus the last-known copy marked `stale`, or without Domain details.
//! A Domain failure never hides, deletes or deactivates a Reports project.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::core::error::ReportError;
use std::collections::HashSet;
use std::sync::Mutex;

use crate::dal::domain_api::{DomainProject, DomainProjectDetail};
use crate::dal::Stores;

const FRESH_KEY: &str = "domain:index:fresh:v1";
const LAST_KEY: &str = "domain:index:last:v1";
/// Lifetime of the last-known copy (30 days).
const LAST_TTL_SECS: u64 = 30 * 24 * 3600;

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Snapshot {
    fetched_at: String,
    projects: Vec<DomainProject>,
}

/// How current the Domain details of a response are.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum DomainStatus {
    /// The project has no Domain link.
    Unlinked,
    /// Details from a fresh Domain response (within the cache TTL).
    Fresh,
    /// domain_api failed: details from the last-known response (see `fetched_at`).
    Stale,
    /// domain_api failed and no earlier response exists.
    Unavailable,
    /// The linked UUID is not in domain_api (the Reports project stays).
    Missing,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct DomainDetails {
    #[serde(flatten)]
    pub project: DomainProject,
    /// Time of the domain_api response behind these details (RFC 3339).
    pub fetched_at: String,
    /// Links, categories, statistics and collaborators. None until the first background
    /// fetch finishes (the detail route of domain_api is slow).
    pub detail: Option<DomainProjectDetail>,
    pub detail_fetched_at: Option<String>,
    /// True when `detail` is the last-known copy and a refresh runs in the background.
    pub detail_stale: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct DetailSnapshot {
    fetched_at: String,
    detail: DomainProjectDetail,
}

/// Detail refreshes that run now (one per cache instance and project at a time).
static REFRESHING: Mutex<Option<HashSet<String>>> = Mutex::new(None);

fn fresh_detail_key(id: &str) -> String {
    format!("domain:detail:fresh:v1:{id}")
}

fn last_detail_key(id: &str) -> String {
    format!("domain:detail:last:v1:{id}")
}

/// Fetches one project detail and stores the fresh and last-known copies.
pub async fn refresh_detail(stores: &Stores, ttl_secs: u64, id: &str, slug: &str) -> Result<(), ReportError> {
    let detail = stores.domain.project_detail(slug).await?;
    let snapshot = DetailSnapshot { fetched_at: chrono::Utc::now().to_rfc3339(), detail };
    if let Ok(text) = serde_json::to_string(&snapshot) {
        stores.cache.set(&fresh_detail_key(id), &text, ttl_secs).await;
        stores.cache.set(&last_detail_key(id), &text, LAST_TTL_SECS).await;
    }
    Ok(())
}

/// Starts a background refresh unless one already runs for this project.
fn spawn_refresh(stores: &Stores, ttl_secs: u64, id: &str, slug: &str) {
    // One guard per cache instance and project.
    let guard_key = format!("{:p}:{id}", std::sync::Arc::as_ptr(&stores.cache));
    {
        let mut guard = REFRESHING.lock().unwrap();
        let set = guard.get_or_insert_with(HashSet::new);
        if !set.insert(guard_key.clone()) {
            return;
        }
    }
    let (stores, id, slug) = (stores.clone(), id.to_string(), slug.to_string());
    tokio::spawn(async move {
        if let Err(e) = refresh_detail(&stores, ttl_secs, &id, &slug).await {
            tracing::warn!(domain_project = %slug, "domain_api detail refresh failed: {}", e);
        }
        if let Some(set) = REFRESHING.lock().unwrap().as_mut() {
            set.remove(&guard_key);
        }
    });
}

/// Adds the cached detail. A missing or expired copy starts a background refresh; the
/// request never waits for the slow detail route.
pub async fn attach_detail(stores: &Stores, ttl_secs: u64, details: &mut DomainDetails) {
    let id = details.project.id.clone();
    let read = |key: String| async move {
        stores.cache.get(&key).await.and_then(|t| serde_json::from_str::<DetailSnapshot>(&t).ok())
    };
    if let Some(s) = read(fresh_detail_key(&id)).await {
        details.detail = Some(s.detail);
        details.detail_fetched_at = Some(s.fetched_at);
        return;
    }
    if let Some(s) = read(last_detail_key(&id)).await {
        details.detail = Some(s.detail);
        details.detail_fetched_at = Some(s.fetched_at);
        details.detail_stale = true;
    }
    spawn_refresh(stores, ttl_secs, &id, &details.project.slug);
}

/// The Domain index with its freshness. None when domain_api failed and nothing is cached.
pub struct DomainIndex {
    snapshot: Option<Snapshot>,
    pub stale: bool,
}

impl DomainIndex {
    pub fn lookup(&self, domain_project_id: Option<&str>) -> (DomainStatus, Option<DomainDetails>) {
        let Some(id) = domain_project_id else {
            return (DomainStatus::Unlinked, None);
        };
        let Some(snapshot) = &self.snapshot else {
            return (DomainStatus::Unavailable, None);
        };
        match snapshot.projects.iter().find(|p| p.id.eq_ignore_ascii_case(id)) {
            Some(p) => (
                if self.stale { DomainStatus::Stale } else { DomainStatus::Fresh },
                Some(DomainDetails {
                    project: p.clone(),
                    fetched_at: snapshot.fetched_at.clone(),
                    detail: None,
                    detail_fetched_at: None,
                    detail_stale: false,
                }),
            ),
            None if self.stale => (DomainStatus::Stale, None),
            None => (DomainStatus::Missing, None),
        }
    }

    pub fn is_available(&self) -> bool {
        self.snapshot.is_some()
    }
}

/// Reads the Domain index from Redis, or asks domain_api once and stores the answer.
pub async fn domain_index(stores: &Stores, ttl_secs: u64) -> DomainIndex {
    if let Some(snapshot) = read(stores, FRESH_KEY).await {
        return DomainIndex { snapshot: Some(snapshot), stale: false };
    }
    match refresh(stores, ttl_secs).await {
        Ok(snapshot) => DomainIndex { snapshot: Some(snapshot), stale: false },
        Err(e) => {
            tracing::warn!("domain_api failed, using the last-known Domain details: {}", e);
            DomainIndex { snapshot: read(stores, LAST_KEY).await, stale: true }
        }
    }
}

/// Asks domain_api now (no cache) and stores the answer. Admin writes use it to verify a link.
pub async fn refresh_index(stores: &Stores, ttl_secs: u64) -> Result<DomainIndex, ReportError> {
    Ok(DomainIndex { snapshot: Some(refresh(stores, ttl_secs).await?), stale: false })
}

async fn refresh(stores: &Stores, ttl_secs: u64) -> Result<Snapshot, ReportError> {
    let projects = stores.domain.list_projects().await?;
    let snapshot = Snapshot { fetched_at: chrono::Utc::now().to_rfc3339(), projects };
    if let Ok(text) = serde_json::to_string(&snapshot) {
        stores.cache.set(FRESH_KEY, &text, ttl_secs).await;
        stores.cache.set(LAST_KEY, &text, LAST_TTL_SECS).await;
    }
    Ok(snapshot)
}

async fn read(stores: &Stores, key: &str) -> Option<Snapshot> {
    stores.cache.get(key).await.and_then(|t| serde_json::from_str(&t).ok())
}
