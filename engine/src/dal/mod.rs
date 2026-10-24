//! Data access: PostgreSQL (definitions, roles), CouchDB (received records), Redis (cache),
//! and the domain_api client (project details).

pub mod cache;
pub mod calculations;
pub mod catalog;
pub mod documents;
pub mod domain_api;
pub mod fixtures;
pub mod grants;
pub mod schemas;
pub mod sql;

use std::sync::Arc;

pub use cache::{CacheStore, LockState, MemoryCache, RedisCache};
pub use catalog::{DatasetRecord, ProjectRole, PeriodSource, ProjectRecord, ReportMetadata, ReportRecord};
pub use grants::Grant;
pub use documents::{CouchDocuments, DocumentStore, InsertOutcome, MemoryDocuments, RecordDoc};
pub use calculations::{CalculationVersion, InputRef};
pub use schemas::SchemaVersion;
pub use sql::Db;

/// The three network stores of one engine process.
#[derive(Clone)]
pub struct Stores {
    pub db: Arc<Db>,
    pub docs: Arc<dyn DocumentStore>,
    pub cache: Arc<dyn CacheStore>,
    pub domain: Arc<dyn domain_api::DomainSource>,
}
