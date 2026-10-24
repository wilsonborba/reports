//! Versioned schemas and the receiver path.
//!
//! Flow of one ingestion request:
//! 1. The envelope names the project and schema (path) and the declared schema version.
//! 2. The version must exist and be published. Drafts and retired versions are refused.
//! 3. Every payload must match the version's fields (guardrail). One invalid payload
//!    refuses the whole batch; nothing is written.
//! 4. The records go to CouchDB. Success is reported only after CouchDB confirms them.
//! 5. Cached results that read this schema are invalidated.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use utoipa::ToSchema;

use crate::core::error::ReportError;
use crate::dal::{catalog, schemas, InsertOutcome, RecordDoc, SchemaVersion};
use crate::domain::catalog::valid_slug;
use crate::domain::datasets::DatasetService;
use crate::domain::guardrail::{check_fields, validate_payload, SchemaField, ValidationError};

/// Most records in one ingestion request.
pub const MAX_BATCH: usize = 5000;

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct SchemaDraftRequest {
    pub schema_name: String,
    /// Version number. Omit it to create the next version.
    #[serde(default)]
    pub version: Option<i64>,
    #[serde(default)]
    pub description: Option<String>,
    pub fields: Vec<SchemaField>,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct IngestRecord {
    /// Stable key of the source event. A retry with the same key writes nothing new.
    /// Without it, the key is the hash of the payload.
    #[serde(default)]
    pub idempotency_key: Option<String>,
    /// Time of the source event (RFC 3339).
    #[serde(default)]
    pub event_time: Option<String>,
    #[schema(value_type = Object)]
    pub payload: Value,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct IngestRequest {
    /// Optional copy of the path values; when present they must agree with the path.
    #[serde(default)]
    pub project: Option<String>,
    #[serde(default)]
    pub schema_name: Option<String>,
    /// Declared schema version of every record in the request.
    pub schema_version: i64,
    pub records: Vec<IngestRecord>,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct IngestResponse {
    pub project: String,
    pub schema_name: String,
    pub schema_version: i64,
    #[serde(flatten)]
    pub outcome: InsertOutcome,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct RecordFailure {
    pub index: usize,
    pub violations: Vec<ValidationError>,
}

fn invalid(message: impl Into<String>, violations: Vec<ValidationError>) -> ReportError {
    ReportError::Validation { message: message.into(), violations }
}

/// Creates or replaces a draft schema version after checking the field list.
pub async fn save_schema_draft(svc: &DatasetService, project: &str, req: SchemaDraftRequest) -> Result<SchemaVersion, ReportError> {
    let db = &svc.stores().db;
    catalog::active_project(db, project).await?;
    if !valid_slug(&req.schema_name) {
        return Err(ReportError::BadRequest(format!("schema name '{}' is not a valid slug", req.schema_name)));
    }
    let errors = check_fields(&req.fields);
    if !errors.is_empty() {
        return Err(invalid("invalid schema fields", errors));
    }
    let version = match req.version {
        Some(v) if v > 0 => v,
        Some(v) => return Err(ReportError::BadRequest(format!("version {v} must be 1 or more"))),
        None => schemas::latest_version(db, project, &req.schema_name).await?.unwrap_or(0) + 1,
    };
    let draft = SchemaVersion {
        project: project.to_string(),
        schema_name: req.schema_name,
        version,
        status: "draft".into(),
        description: req.description,
        fields: req.fields,
        created_at: String::new(),
        published_at: None,
    };
    schemas::save_draft(db, &draft).await?;
    schemas::get(db, project, &draft.schema_name, version)
        .await?
        .ok_or_else(|| ReportError::Internal("saved schema draft is missing".into()))
}

/// draft -> published (immutable from now on).
pub async fn publish_schema(svc: &DatasetService, project: &str, name: &str, version: i64) -> Result<SchemaVersion, ReportError> {
    let published = transition(svc, project, name, version, "draft", "published").await?;
    let marked = crate::dal::calculations::mark_drafts_for_review(&svc.stores().db, project, name, version).await?;
    if marked > 0 {
        tracing::info!(project, schema = name, version, marked, "calculation drafts marked for review");
    }
    Ok(published)
}

/// published -> retired (new records with this version are refused; old records stay).
pub async fn retire_schema(svc: &DatasetService, project: &str, name: &str, version: i64) -> Result<SchemaVersion, ReportError> {
    transition(svc, project, name, version, "published", "retired").await
}

async fn transition(svc: &DatasetService, project: &str, name: &str, version: i64, from: &str, to: &str) -> Result<SchemaVersion, ReportError> {
    let db = &svc.stores().db;
    let current = schemas::get(db, project, name, version)
        .await?
        .ok_or_else(|| ReportError::not_found(format!("schema {project}:{name} v{version}")))?;
    if current.status != from {
        return Err(ReportError::Conflict(format!(
            "schema {project}:{name} v{version} is {}, expected {from}",
            current.status
        )));
    }
    if !schemas::set_status(db, project, name, version, from, to).await? {
        return Err(ReportError::Conflict(format!("schema {project}:{name} v{version} changed during the request")));
    }
    schemas::get(db, project, name, version)
        .await?
        .ok_or_else(|| ReportError::Internal("schema version is missing".into()))
}

fn payload_key(payload: &Value) -> String {
    hex::encode(Sha256::digest(serde_json::to_vec(payload).unwrap_or_default()))
}

/// Validates the whole request, then writes it. Nothing is written when one record fails.
pub async fn ingest(
    svc: &DatasetService,
    project: &str,
    schema_name: &str,
    req: IngestRequest,
    fixture: Option<String>,
) -> Result<IngestResponse, ReportError> {
    let db = &svc.stores().db;
    if req.project.as_deref().is_some_and(|p| p != project) || req.schema_name.as_deref().is_some_and(|s| s != schema_name) {
        return Err(ReportError::BadRequest("the envelope project or schema does not match the path".into()));
    }
    if req.records.is_empty() || req.records.len() > MAX_BATCH {
        return Err(ReportError::BadRequest(format!("send 1 to {MAX_BATCH} records per request")));
    }
    catalog::active_project(db, project).await?;
    let schema = schemas::get(db, project, schema_name, req.schema_version)
        .await?
        .ok_or_else(|| ReportError::not_found(format!("schema {project}:{schema_name} v{}", req.schema_version)))?;
    if schema.status != "published" {
        return Err(ReportError::Conflict(format!(
            "schema {project}:{schema_name} v{} is {}; only published versions accept records",
            req.schema_version, schema.status
        )));
    }
    let mut failures = Vec::new();
    for (index, r) in req.records.iter().enumerate() {
        let mut violations = validate_payload(&schema.fields, &r.payload).err().unwrap_or_default();
        if let Some(t) = &r.event_time {
            if chrono::DateTime::parse_from_rfc3339(t).is_err() {
                violations.push(ValidationError::definition("event_time", "must be an RFC 3339 time"));
            }
        }
        if !violations.is_empty() {
            failures.push(RecordFailure { index, violations });
        }
    }
    if !failures.is_empty() {
        let mut flat = Vec::new();
        for f in &failures {
            for v in &f.violations {
                let mut v = v.clone();
                v.field_path = format!("records[{}].{}", f.index, v.field_path);
                flat.push(v);
            }
        }
        return Err(invalid(format!("{} of {} records are invalid; nothing was written", failures.len(), req.records.len()), flat));
    }
    let docs: Vec<RecordDoc> = req
        .records
        .into_iter()
        .map(|r| {
            let key = r.idempotency_key.unwrap_or_else(|| payload_key(&r.payload));
            RecordDoc::new(project, schema_name, schema.version, &key, r.event_time, fixture.clone(), r.payload)
        })
        .collect();
    let outcome = svc.stores().docs.insert_records(&docs).await?;
    if outcome.created > 0 {
        let created: std::collections::HashSet<&str> = outcome.created_ids.iter().map(String::as_str).collect();
        let new_docs: Vec<RecordDoc> = docs.into_iter().filter(|d| created.contains(d.id.as_str())).collect();
        svc.records_appended(project, schema_name, &new_docs).await;
    }
    Ok(IngestResponse {
        project: project.to_string(),
        schema_name: schema_name.to_string(),
        schema_version: schema.version,
        outcome,
    })
}
