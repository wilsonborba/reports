//! Received records in CouchDB `reports_documents`.
//!
//! Each record keeps its project, schema name and version, event time, receive time and
//! idempotency key. The document ID comes from the idempotency key, so a producer retry
//! never creates a second record. `scripts/migrate.sh` creates the database and its
//! indexes; the engine only checks that the database exists.

use std::collections::HashMap;
use std::sync::RwLock;
use std::time::Duration;

use async_trait::async_trait;
use reqwest::{Client, StatusCode};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use crate::core::error::ReportError;

pub const RECORD_TYPE: &str = "record";
/// Records per `_find` page.
const PAGE_SIZE: usize = 5000;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RecordDoc {
    #[serde(rename = "_id")]
    pub id: String,
    #[serde(rename = "type")]
    pub doc_type: String,
    pub project: String,
    pub schema_name: String,
    pub schema_version: i64,
    /// Time of the source event (RFC 3339), when the producer sends one.
    #[serde(default)]
    pub event_time: Option<String>,
    pub received_at: String,
    pub idempotency_key: String,
    /// Fixture manifest that owns the record (sample data only).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fixture: Option<String>,
    pub payload: Value,
}

impl RecordDoc {
    pub fn new(
        project: &str,
        schema_name: &str,
        schema_version: i64,
        idempotency_key: &str,
        event_time: Option<String>,
        fixture: Option<String>,
        payload: Value,
    ) -> Self {
        Self {
            id: record_id(project, schema_name, idempotency_key),
            doc_type: RECORD_TYPE.to_string(),
            project: project.to_string(),
            schema_name: schema_name.to_string(),
            schema_version,
            event_time,
            received_at: chrono::Utc::now().to_rfc3339(),
            idempotency_key: idempotency_key.to_string(),
            fixture,
            payload,
        }
    }
}

/// Document ID of a record: stable for the same project, schema and idempotency key.
pub fn record_id(project: &str, schema_name: &str, idempotency_key: &str) -> String {
    let digest = Sha256::digest(format!("{project}\u{1f}{schema_name}\u{1f}{idempotency_key}").as_bytes());
    format!("rec:{project}:{schema_name}:{}", &hex::encode(digest)[..32])
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, utoipa::ToSchema)]
pub struct InsertOutcome {
    /// New records.
    pub created: usize,
    /// Records whose idempotency key was already stored (not written again).
    pub duplicates: usize,
    /// Document IDs of the new records (in-process use: append them to loaded copies).
    #[serde(skip)]
    pub created_ids: Vec<String>,
}

#[async_trait]
pub trait DocumentStore: Send + Sync {
    /// Writes records. All are durable when this returns Ok.
    async fn insert_records(&self, records: &[RecordDoc]) -> Result<InsertOutcome, ReportError>;
    /// Every record of one schema of a project (all versions), at most `max` records.
    async fn load_records(&self, project: &str, schema_name: &str, max: usize) -> Result<Vec<RecordDoc>, ReportError>;
    /// Stores a durable result snapshot (`type: snapshot`). The ID must be new.
    async fn put_snapshot(&self, snapshot: &Value) -> Result<(), ReportError>;
    /// Snapshots of one dataset, newest first.
    async fn list_snapshots(&self, project: &str, report: &str, dataset: &str, max: usize) -> Result<Vec<Value>, ReportError>;
    /// Deletes every record owned by a fixture manifest. Returns the number deleted.
    async fn delete_fixture_records(&self, fixture: &str) -> Result<usize, ReportError>;
    /// Fails when the store or its database is not available.
    async fn check_ready(&self) -> Result<(), ReportError>;
    async fn health(&self) -> bool {
        self.check_ready().await.is_ok()
    }
}

// --- CouchDB ----------------------------------------------------------------

pub struct CouchDocuments {
    client: Client,
    base_url: String,
    database: String,
    user: Option<String>,
    password: Option<String>,
}

impl CouchDocuments {
    pub fn new(base_url: &str, database: &str, user: Option<String>, password: Option<String>) -> Result<Self, ReportError> {
        Ok(Self {
            client: Client::builder()
                .timeout(Duration::from_secs(15))
                .build()
                .map_err(|e| ReportError::Internal(format!("CouchDB client: {e}")))?,
            base_url: base_url.trim_end_matches('/').to_string(),
            database: database.to_string(),
            user,
            password,
        })
    }

    fn url(&self, path: &str) -> String {
        format!("{}/{}{}", self.base_url, self.database, path)
    }

    fn auth(&self, request: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        match (&self.user, &self.password) {
            (Some(user), Some(password)) => request.basic_auth(user, Some(password)),
            _ => request,
        }
    }

    async fn send(&self, request: reqwest::RequestBuilder) -> Result<reqwest::Response, ReportError> {
        self.auth(request)
            .send()
            .await
            .map_err(|e| ReportError::Unavailable(format!("CouchDB: {}", e.without_url())))
    }

    async fn find(&self, selector: Value, fields: Option<Value>, max: usize) -> Result<Vec<Value>, ReportError> {
        let mut out = Vec::new();
        let mut bookmark: Option<String> = None;
        loop {
            let mut body = json!({ "selector": selector, "limit": PAGE_SIZE });
            if let Some(f) = &fields {
                body["fields"] = f.clone();
            }
            if let Some(b) = &bookmark {
                body["bookmark"] = json!(b);
            }
            let response = self.send(self.client.post(self.url("/_find")).json(&body)).await?;
            if !response.status().is_success() {
                return Err(ReportError::Unavailable(format!("CouchDB _find returned {}", response.status())));
            }
            let page: Value = response
                .json()
                .await
                .map_err(|e| ReportError::Unavailable(format!("CouchDB _find body: {e}")))?;
            let docs = page["docs"].as_array().cloned().unwrap_or_default();
            let n = docs.len();
            out.extend(docs);
            if out.len() > max {
                return Err(ReportError::BadRequest(format!(
                    "the calculation would read more than {max} records; narrow the source"
                )));
            }
            bookmark = page["bookmark"].as_str().map(str::to_string);
            if n < PAGE_SIZE || bookmark.is_none() {
                return Ok(out);
            }
        }
    }
}

#[async_trait]
impl DocumentStore for CouchDocuments {
    async fn insert_records(&self, records: &[RecordDoc]) -> Result<InsertOutcome, ReportError> {
        let mut outcome = InsertOutcome::default();
        for chunk in records.chunks(1000) {
            let body = json!({ "docs": chunk });
            let response = self.send(self.client.post(self.url("/_bulk_docs")).json(&body)).await?;
            if response.status() != StatusCode::CREATED && response.status() != StatusCode::ACCEPTED {
                return Err(ReportError::Unavailable(format!("CouchDB _bulk_docs returned {}", response.status())));
            }
            let results: Vec<Value> = response
                .json()
                .await
                .map_err(|e| ReportError::Unavailable(format!("CouchDB _bulk_docs body: {e}")))?;
            for r in results {
                match r.get("error").and_then(Value::as_str) {
                    None => {
                        outcome.created += 1;
                        if let Some(id) = r.get("id").and_then(Value::as_str) {
                            outcome.created_ids.push(id.to_string());
                        }
                    }
                    Some("conflict") => outcome.duplicates += 1,
                    Some(other) => {
                        return Err(ReportError::Unavailable(format!(
                            "CouchDB refused record {}: {other}",
                            r.get("id").and_then(Value::as_str).unwrap_or("?")
                        )))
                    }
                }
            }
        }
        Ok(outcome)
    }

    async fn load_records(&self, project: &str, schema_name: &str, max: usize) -> Result<Vec<RecordDoc>, ReportError> {
        let selector = json!({ "type": RECORD_TYPE, "project": project, "schema_name": schema_name });
        let docs = self.find(selector, None, max).await?;
        docs.into_iter()
            .map(|d| serde_json::from_value(d).map_err(|e| ReportError::Database(format!("CouchDB record: {e}"))))
            .collect()
    }

    async fn put_snapshot(&self, snapshot: &Value) -> Result<(), ReportError> {
        let response = self.send(self.client.post(self.url("")).json(snapshot)).await?;
        if response.status().is_success() {
            Ok(())
        } else {
            Err(ReportError::Unavailable(format!("CouchDB snapshot write returned {}", response.status())))
        }
    }

    async fn list_snapshots(&self, project: &str, report: &str, dataset: &str, max: usize) -> Result<Vec<Value>, ReportError> {
        let selector = json!({ "type": "snapshot", "project": project, "report": report, "dataset_id": dataset });
        let mut docs = self.find(selector, None, usize::MAX).await?;
        docs.sort_by(|a, b| b["created_at"].as_str().cmp(&a["created_at"].as_str()));
        docs.truncate(max);
        Ok(docs)
    }

    async fn delete_fixture_records(&self, fixture: &str) -> Result<usize, ReportError> {
        let selector = json!({ "type": RECORD_TYPE, "fixture": fixture });
        let docs = self.find(selector, Some(json!(["_id", "_rev"])), usize::MAX).await?;
        let deletions: Vec<Value> = docs
            .iter()
            .map(|d| json!({ "_id": d["_id"], "_rev": d["_rev"], "_deleted": true }))
            .collect();
        let mut deleted = 0;
        for chunk in deletions.chunks(1000) {
            let response = self
                .send(self.client.post(self.url("/_bulk_docs")).json(&json!({ "docs": chunk })))
                .await?;
            if !response.status().is_success() {
                return Err(ReportError::Unavailable(format!("CouchDB delete returned {}", response.status())));
            }
            let results: Vec<Value> = response
                .json()
                .await
                .map_err(|e| ReportError::Unavailable(format!("CouchDB delete body: {e}")))?;
            deleted += results.iter().filter(|r| r.get("error").is_none()).count();
        }
        Ok(deleted)
    }

    async fn check_ready(&self) -> Result<(), ReportError> {
        let response = self.send(self.client.get(self.url(""))).await?;
        match response.status() {
            s if s.is_success() => Ok(()),
            StatusCode::NOT_FOUND => Err(ReportError::Unavailable(format!(
                "CouchDB database '{}' does not exist. Run scripts/migrate.sh",
                self.database
            ))),
            s => Err(ReportError::Unavailable(format!("CouchDB returned {s}"))),
        }
    }
}

// --- in-process store for tests ---------------------------------------------

/// Test double with the same idempotency rule as CouchDB. Not used in production.
#[derive(Default)]
pub struct MemoryDocuments {
    docs: RwLock<HashMap<String, RecordDoc>>,
    snapshots: RwLock<Vec<Value>>,
    /// When true, every call fails like an unreachable CouchDB.
    pub offline: std::sync::atomic::AtomicBool,
}

impl MemoryDocuments {
    fn ensure_online(&self) -> Result<(), ReportError> {
        if self.offline.load(std::sync::atomic::Ordering::SeqCst) {
            Err(ReportError::Unavailable("CouchDB: connection refused (test)".into()))
        } else {
            Ok(())
        }
    }

    pub fn len(&self) -> usize {
        self.docs.read().unwrap().len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

#[async_trait]
impl DocumentStore for MemoryDocuments {
    async fn insert_records(&self, records: &[RecordDoc]) -> Result<InsertOutcome, ReportError> {
        self.ensure_online()?;
        let mut docs = self.docs.write().unwrap();
        let mut outcome = InsertOutcome::default();
        for r in records {
            if docs.contains_key(&r.id) {
                outcome.duplicates += 1;
            } else {
                docs.insert(r.id.clone(), r.clone());
                outcome.created += 1;
                outcome.created_ids.push(r.id.clone());
            }
        }
        Ok(outcome)
    }

    async fn load_records(&self, project: &str, schema_name: &str, max: usize) -> Result<Vec<RecordDoc>, ReportError> {
        self.ensure_online()?;
        let mut out: Vec<RecordDoc> = self
            .docs
            .read()
            .unwrap()
            .values()
            .filter(|d| d.project == project && d.schema_name == schema_name)
            .cloned()
            .collect();
        if out.len() > max {
            return Err(ReportError::BadRequest(format!(
                "the calculation would read more than {max} records; narrow the source"
            )));
        }
        out.sort_by(|a, b| a.id.cmp(&b.id));
        Ok(out)
    }

    async fn put_snapshot(&self, snapshot: &Value) -> Result<(), ReportError> {
        self.ensure_online()?;
        self.snapshots.write().unwrap().push(snapshot.clone());
        Ok(())
    }

    async fn list_snapshots(&self, project: &str, report: &str, dataset: &str, max: usize) -> Result<Vec<Value>, ReportError> {
        self.ensure_online()?;
        let mut out: Vec<Value> = self
            .snapshots
            .read()
            .unwrap()
            .iter()
            .filter(|s| s["project"] == project && s["report"] == report && s["dataset_id"] == dataset)
            .cloned()
            .collect();
        out.sort_by(|a, b| b["created_at"].as_str().cmp(&a["created_at"].as_str()));
        out.truncate(max);
        Ok(out)
    }

    async fn delete_fixture_records(&self, fixture: &str) -> Result<usize, ReportError> {
        self.ensure_online()?;
        let mut docs = self.docs.write().unwrap();
        let before = docs.len();
        docs.retain(|_, d| d.fixture.as_deref() != Some(fixture));
        Ok(before - docs.len())
    }

    async fn check_ready(&self) -> Result<(), ReportError> {
        self.ensure_online()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn record_id_is_stable_and_scoped() {
        let a = record_id("cortex", "telemetry_event", "req-1");
        assert_eq!(a, record_id("cortex", "telemetry_event", "req-1"));
        assert_ne!(a, record_id("cortex", "telemetry_event", "req-2"));
        assert_ne!(a, record_id("autodroid", "telemetry_event", "req-1"));
        assert!(a.starts_with("rec:cortex:telemetry_event:"));
    }
}
