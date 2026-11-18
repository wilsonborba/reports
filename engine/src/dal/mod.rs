//! Data access: PostgreSQL (definitions, roles), CouchDB (received records), Redis (cache),
//! and the domain_api client (project details).

pub mod cache;
mod calculation_shape;
pub mod calculations;
pub mod catalog;
mod catalog_storage;
pub mod documents;
pub mod domain_api;
pub mod embed_preview;
pub mod fixtures;
pub mod grants;
mod normalized;
pub mod schemas;
pub mod sql;

use std::sync::Arc;

pub use cache::{CacheStore, LockState, MemoryCache, RedisCache};
pub use calculations::{CalculationVersion, InputRef};
pub use catalog::{DatasetRecord, PeriodSource, ProjectRecord, ProjectRole, ReportMetadata, ReportRecord};
pub use documents::{CouchDocuments, DocumentStore, InsertOutcome, MemoryDocuments, RecordDoc};
pub use grants::Grant;
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
