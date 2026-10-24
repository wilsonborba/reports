//! Server-to-server client of domain_api (project descriptions, links and images).
//! Reports uses Domain data for presentation only, never as report metrics.

use std::time::Duration;

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use utoipa::ToSchema;

use crate::core::error::ReportError;

/// One domain_api project, normalized to the fields that Reports shows.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
pub struct DomainProject {
    pub id: String,
    pub slug: String,
    pub name: String,
    #[serde(default)]
    pub tagline: Option<String>,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub status: Option<String>,
    /// Production website, or the repository when the project has no domain.
    #[serde(default)]
    pub main_link: Option<String>,
    /// `https://github.com/<owner>/<repo>` when known.
    #[serde(default)]
    pub repository_url: Option<String>,
    /// Public cover image through the gateway.
    #[serde(default)]
    pub cover_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
pub struct DomainLink {
    pub link_type: String,
    pub url: String,
    #[serde(default)]
    pub icon: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
pub struct DomainCategory {
    pub category: String,
    pub item: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
pub struct DomainStatistic {
    pub name: String,
    pub value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
pub struct DomainCollaborator {
    pub name: String,
    #[serde(default)]
    pub github_username: Option<String>,
    #[serde(default)]
    pub avatar_url: Option<String>,
    #[serde(default)]
    pub role: Option<String>,
}

/// Extra project details from `GET /projects/{slug}` (slow: domain_api reads GitHub data).
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, ToSchema)]
pub struct DomainProjectDetail {
    pub links: Vec<DomainLink>,
    pub categories: Vec<DomainCategory>,
    pub statistics: Vec<DomainStatistic>,
    pub collaborators: Vec<DomainCollaborator>,
    #[serde(default)]
    pub created_at: Option<String>,
    #[serde(default)]
    pub updated_at: Option<String>,
}

#[async_trait]
pub trait DomainSource: Send + Sync {
    /// Every Domain project (one request).
    async fn list_projects(&self) -> Result<Vec<DomainProject>, ReportError>;
    /// Links, categories, statistics and collaborators of one project.
    async fn project_detail(&self, slug: &str) -> Result<DomainProjectDetail, ReportError>;
}

/// Normalizes `MyResponse.data` of `GET /projects/{slug}`. Malformed entries are skipped.
pub fn normalize_detail(data: &Value) -> DomainProjectDetail {
    fn list<T: serde::de::DeserializeOwned>(v: &Value, key: &str) -> Vec<T> {
        v.get(key)
            .and_then(Value::as_array)
            .map(|a| a.iter().filter_map(|x| serde_json::from_value(x.clone()).ok()).collect())
            .unwrap_or_default()
    }
    DomainProjectDetail {
        links: list(data, "links"),
        categories: list(data, "categories"),
        statistics: list(data, "statistics"),
        collaborators: list(data, "collaborators"),
        created_at: text(data, "created_at"),
        updated_at: text(data, "updated_at"),
    }
}

pub struct HttpDomain {
    client: reqwest::Client,
    /// The detail route is slow (GitHub data), so it gets a longer timeout.
    detail_client: reqwest::Client,
    base_url: String,
    public_base: String,
}

impl HttpDomain {
    /// `base_url`: domain_api itself (for example http://localhost:8104).
    /// `public_base`: its gateway URL, used for browser image links.
    pub fn new(base_url: &str, public_base: &str, timeout: Duration) -> Result<Self, ReportError> {
        Ok(Self {
            client: reqwest::Client::builder()
                .timeout(timeout)
                .build()
                .map_err(|e| ReportError::Internal(format!("Domain client: {e}")))?,
            detail_client: reqwest::Client::builder()
                .timeout(Duration::from_secs(30))
                .build()
                .map_err(|e| ReportError::Internal(format!("Domain client: {e}")))?,
            base_url: base_url.trim_end_matches('/').to_string(),
            public_base: public_base.trim_end_matches('/').to_string(),
        })
    }
}

fn text(v: &Value, key: &str) -> Option<String> {
    v.get(key).and_then(Value::as_str).map(str::trim).filter(|s| !s.is_empty()).map(str::to_string)
}

/// Normalizes one item of `GET /projects` (`MyResponse.data.items[]`).
pub fn normalize(item: &Value, public_base: &str) -> Option<DomainProject> {
    let id = text(item, "id")?;
    let slug = text(item, "slug")?;
    let repository_url = text(item, "github_repo").map(|r| {
        if r.starts_with("https://") {
            r
        } else {
            format!("https://github.com/{}", r.trim_start_matches('/'))
        }
    });
    Some(DomainProject {
        name: text(item, "name").unwrap_or_else(|| slug.clone()),
        tagline: text(item, "tagline"),
        description: text(item, "description"),
        status: text(item, "status"),
        main_link: text(item, "main_link"),
        cover_url: text(item, "image_url").map(|_| format!("{public_base}/projects/{slug}/cover")),
        repository_url,
        id,
        slug,
    })
}

#[async_trait]
impl DomainSource for HttpDomain {
    async fn list_projects(&self) -> Result<Vec<DomainProject>, ReportError> {
        let url = format!("{}/projects?limit=100", self.base_url);
        let response = self
            .client
            .get(&url)
            .send()
            .await
            .map_err(|e| ReportError::Unavailable(format!("domain_api: {}", e.without_url())))?;
        if !response.status().is_success() {
            return Err(ReportError::Unavailable(format!("domain_api returned {}", response.status())));
        }
        let body: Value = response
            .json()
            .await
            .map_err(|e| ReportError::Unavailable(format!("domain_api body: {e}")))?;
        let items = body["data"]["items"].as_array().cloned().unwrap_or_default();
        Ok(items.iter().filter_map(|i| normalize(i, &self.public_base)).collect())
    }

    async fn project_detail(&self, slug: &str) -> Result<DomainProjectDetail, ReportError> {
        let url = format!("{}/projects/{}", self.base_url, urlencoding::encode(slug));
        let response = self
            .detail_client
            .get(&url)
            .send()
            .await
            .map_err(|e| ReportError::Unavailable(format!("domain_api detail: {}", e.without_url())))?;
        if !response.status().is_success() {
            return Err(ReportError::Unavailable(format!("domain_api detail returned {}", response.status())));
        }
        let body: Value = response
            .json()
            .await
            .map_err(|e| ReportError::Unavailable(format!("domain_api detail body: {e}")))?;
        Ok(normalize_detail(&body["data"]))
    }
}

/// Test double. `None` behaves like an unreachable domain_api.
#[derive(Default)]
pub struct StaticDomain {
    pub projects: std::sync::Mutex<Option<Vec<DomainProject>>>,
    /// Details by Domain slug; a missing slug fails like a timeout.
    pub details: std::sync::Mutex<std::collections::HashMap<String, DomainProjectDetail>>,
    pub calls: std::sync::atomic::AtomicUsize,
    pub detail_calls: std::sync::atomic::AtomicUsize,
}

#[async_trait]
impl DomainSource for StaticDomain {
    async fn list_projects(&self) -> Result<Vec<DomainProject>, ReportError> {
        self.calls.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        self.projects
            .lock()
            .unwrap()
            .clone()
            .ok_or_else(|| ReportError::Unavailable("domain_api: timeout (test)".into()))
    }

    async fn project_detail(&self, slug: &str) -> Result<DomainProjectDetail, ReportError> {
        self.detail_calls.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        self.details
            .lock()
            .unwrap()
            .get(slug)
            .cloned()
            .ok_or_else(|| ReportError::Unavailable("domain_api detail: timeout (test)".into()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn normalizes_a_domain_list_item() {
        let item = json!({
            "id": "4ef82613-e51e-42fa-9f3e-93809fdff54b", "slug": "cortex", "name": "Cortex Web",
            "tagline": "Monochromatic Neural-Grid AI Assistant Interface", "description": "",
            "main_link": "https://cortex.asodya.com", "github_repo": "wilsonborba/cortex",
            "image_url": "c0600e27da65492bad1de3a421ce6a44", "status": "on development"
        });
        let p = normalize(&item, "https://api.asodya.com/apps/domain/v1").unwrap();
        assert_eq!(p.repository_url.as_deref(), Some("https://github.com/wilsonborba/cortex"));
        assert_eq!(p.cover_url.as_deref(), Some("https://api.asodya.com/apps/domain/v1/projects/cortex/cover"));
        assert_eq!(p.description, None, "empty text is absent");
        assert!(normalize(&json!({"slug": "x"}), "").is_none(), "an item needs an id");
    }

    #[test]
    fn normalizes_a_domain_detail() {
        let data = json!({
            "links": [{"link_type": "GitHub Repository", "url": "https://github.com/wilsonborba/fsm", "icon": "github"}, {"bad": 1}],
            "categories": [{"category": "Media", "item": "S3 Storage"}],
            "statistics": [{"name": "Total Commits", "value": "26 commits"}],
            "collaborators": [{"name": "wilsonborba", "github_username": "wilsonborba", "role": "Contributor"}],
            "created_at": "2026-09-14T23:01:23+07:00"
        });
        let d = normalize_detail(&data);
        assert_eq!(d.links.len(), 1, "malformed entries are skipped");
        assert_eq!(d.statistics[0].value, "26 commits");
        assert_eq!(d.collaborators[0].github_username.as_deref(), Some("wilsonborba"));
    }
}

