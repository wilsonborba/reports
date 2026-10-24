//! Dataset service: loads received records from the document store, runs the calculation
//! engine, and caches results in Redis.
//!
//! Cache rules:
//! - The result key holds project, report, dataset, a hash of the definition, the filters,
//!   the language and the access class, so a new definition or another audience never
//!   reads an old entry.
//! - Every result is tagged with the schemas it reads. A successful ingestion into a schema
//!   deletes only the results tagged with that schema.
//! - Equivalent cold requests run one calculation: an in-process single flight plus a Redis
//!   lock for other engine processes. The lock is released on error and expires anyway.

use std::collections::hash_map::DefaultHasher;
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::hash::{Hash, Hasher};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use utoipa::ToSchema;

use super::engine::{self, compare_values, key_of, EngineError, Row};
use super::spec::{resolve_text, DataTier, DatasetSpec, FilterParam};
use crate::core::error::ReportError;
use crate::dal::{catalog, DatasetRecord, LockState, Stores};

/// Boxed future for the recursive reference resolution.
type BoxFuture<'a, T> = std::pin::Pin<Box<dyn std::future::Future<Output = T> + Send + 'a>>;

/// Maximum number of options sent for one category filter.
const MAX_FILTER_OPTIONS: usize = 500;
/// Maximum depth of dataset references.
const MAX_REF_DEPTH: usize = 4;
/// How long a request waits for another process that computes the same result.
const LOCK_WAIT: Duration = Duration::from_secs(10);

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct FieldInfo {
    pub name: String,
    pub label: String,
    #[serde(rename = "type")]
    pub field_type: String,
    pub role: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub unit: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub decimals: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct FilterOption {
    #[schema(value_type = Object)]
    pub value: Value,
    pub label: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct FilterInfo {
    pub field: String,
    pub label: String,
    /// category, date, hour or number
    #[serde(rename = "type")]
    pub filter_type: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub options: Vec<FilterOption>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[schema(value_type = Option<Object>)]
    pub min: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[schema(value_type = Option<Object>)]
    pub max: Option<Value>,
}

/// Description of a dataset. It contains data descriptions only, never layout.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct DatasetDescriptor {
    pub dataset_id: String,
    pub title: String,
    pub description: String,
    pub equation: Option<String>,
    pub data_tier: DataTier,
    pub fields: Vec<FieldInfo>,
    pub filters: Vec<FilterInfo>,
    pub can_view: bool,
    pub visibility: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct DatasetPage {
    #[serde(flatten)]
    pub descriptor: DatasetDescriptor,
    pub language: String,
    #[schema(value_type = Vec<Object>)]
    pub rows: Vec<Row>,
    pub offset: usize,
    pub limit: usize,
    pub total_rows: usize,
    #[schema(value_type = Object)]
    pub applied_filters: BTreeMap<String, Value>,
    pub lineage: Lineage,
}

/// Who may read a cached result. Session and guest results never share a key.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AccessClass {
    Public,
    Gated,
}

impl AccessClass {
    fn tag(self) -> &'static str {
        match self {
            AccessClass::Public => "pub",
            AccessClass::Gated => "gated",
        }
    }
}

/// Counters for the logs and the health endpoint.
#[derive(Debug, Default, Clone, Serialize, ToSchema)]
pub struct CacheCounters {
    pub hits: u64,
    pub misses: u64,
    pub calculations: u64,
}

/// In-process copy of the records of one schema (cleared by ingestion through this process).
struct CollectionEntry {
    generation: u64,
    rows: Arc<Vec<Row>>,
    watermark: Watermark,
    /// First and last value per field, computed once per loaded copy.
    periods: HashMap<String, Option<(Value, Value)>>,
}

/// State of the source records that a result read.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, ToSchema)]
pub struct Watermark {
    pub records: usize,
    /// Latest receive time of those records (RFC 3339).
    pub last_received_at: Option<String>,
}

/// Where a result comes from: the definition version, its input versions, the state of the
/// source records and the filters. Historical output stays traceable to its versions.
#[derive(Debug, Clone, Default, Serialize, Deserialize, ToSchema)]
pub struct Lineage {
    pub calculation_id: String,
    pub calculation_version: i64,
    pub inputs: Vec<crate::dal::InputRef>,
    /// Watermark per input schema.
    pub source_watermark: BTreeMap<String, Watermark>,
    #[schema(value_type = Object)]
    pub filters: Value,
    pub calculated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct CachedResult {
    rows: Vec<Row>,
    lineage: Lineage,
}

/// One schema copy held in memory.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct LoadedCollection {
    pub project: String,
    pub schema: String,
    pub rows: usize,
    pub watermark: Watermark,
}

/// Longest calculation time.
pub const CALCULATION_TIMEOUT: Duration = Duration::from_secs(15);

pub struct DatasetService {
    stores: Stores,
    result_ttl: u64,
    gate_ttl: u64,
    max_scan_rows: usize,
    max_cached_rows: usize,
    domain_ttl: u64,
    collections: Mutex<HashMap<String, CollectionEntry>>,
    generations: Mutex<HashMap<String, u64>>,
    flights: Mutex<HashMap<String, Arc<tokio::sync::Mutex<()>>>>,
    counters: Mutex<CacheCounters>,
}

fn engine_err(e: EngineError) -> ReportError {
    match e {
        EngineError::Filter(m) => ReportError::BadRequest(m),
        other => ReportError::BadRequest(other.to_string()),
    }
}

fn hash_of<T: Hash>(v: &T) -> String {
    let mut h = DefaultHasher::new();
    v.hash(&mut h);
    format!("{:016x}", h.finish())
}

fn round_to(v: &Value, decimals: u32) -> Value {
    match v.as_f64() {
        Some(f) if matches!(v, Value::Number(_)) => {
            let p = 10f64.powi(decimals as i32);
            serde_json::Number::from_f64((f * p).round() / p)
                .map(Value::Number)
                .unwrap_or(Value::Null)
        }
        _ => v.clone(),
    }
}

/// Schemas that a definition reads (source, unions and lookups).
pub fn dependencies(spec: &DatasetSpec) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    out.extend(spec.source.iter().cloned());
    out.extend(spec.union.iter().cloned());
    out.extend(spec.lookups.iter().map(|l| l.collection.clone()));
    out
}

/// Tag of the cache entries that read one schema of a project.
pub fn schema_tag(project: &str, schema: &str) -> String {
    format!("schema:{project}:{schema}")
}

impl DatasetService {
    pub fn new(stores: Stores, settings: &crate::core::config::Settings) -> Self {
        Self {
            stores,
            result_ttl: settings.result_ttl_secs,
            gate_ttl: settings.gate_ttl_secs,
            max_scan_rows: settings.max_scan_rows,
            max_cached_rows: settings.row_cache_rows,
            domain_ttl: settings.domain_cache_ttl_secs,
            collections: Mutex::new(HashMap::new()),
            generations: Mutex::new(HashMap::new()),
            flights: Mutex::new(HashMap::new()),
            counters: Mutex::new(CacheCounters::default()),
        }
    }

    pub fn stores(&self) -> &Stores {
        &self.stores
    }

    /// Lifetime of fresh Domain details in Redis.
    pub fn domain_ttl(&self) -> u64 {
        self.domain_ttl
    }

    pub fn result_ttl(&self) -> u64 {
        self.result_ttl
    }

    pub fn counters(&self) -> CacheCounters {
        self.counters.lock().unwrap().clone()
    }

    fn count(&self, f: impl FnOnce(&mut CacheCounters)) {
        f(&mut self.counters.lock().unwrap());
    }

    /// The records of a schema changed in an unknown way (for example a fixture delete):
    /// drops the in-process copy and every cached result that reads this schema.
    pub async fn records_changed(&self, project: &str, schema: &str) {
        let key = format!("{project}/{schema}");
        *self.generations.lock().unwrap().entry(key.clone()).or_insert(0) += 1;
        self.collections.lock().unwrap().remove(&key);
        let removed = self.stores.cache.invalidate_tag(&schema_tag(project, schema)).await;
        tracing::info!(project, schema, removed, "cache invalidated after a records change");
    }

    /// New records were stored: appends them to the loaded copy (no CouchDB reload) and
    /// invalidates only the cached entries that read this schema.
    pub async fn records_appended(&self, project: &str, schema: &str, new_docs: &[crate::dal::RecordDoc]) {
        let key = format!("{project}/{schema}");
        // A new generation: a CouchDB load that started before this ingestion cannot store
        // its older copy any more.
        let generation = {
            let mut g = self.generations.lock().unwrap();
            let v = g.entry(key.clone()).or_insert(0);
            *v += 1;
            *v
        };
        let appended = {
            let mut collections = self.collections.lock().unwrap();
            match collections.get_mut(&key) {
                Some(entry) => {
                    entry.generation = generation;
                    let mut rows = entry.rows.as_ref().clone();
                    rows.extend(new_docs.iter().filter_map(|d| d.payload.as_object().cloned()));
                    entry.watermark.records = rows.len();
                    entry.watermark.last_received_at = entry
                        .watermark
                        .last_received_at
                        .clone()
                        .into_iter()
                        .chain(new_docs.iter().map(|d| d.received_at.clone()))
                        .max();
                    entry.rows = Arc::new(rows);
                    entry.periods.clear();
                    true
                }
                None => false,
            }
        };
        let removed = self.stores.cache.invalidate_tag(&schema_tag(project, schema)).await;
        tracing::info!(project, schema, added = new_docs.len(), appended, removed, "records stored; dependent cache invalidated");
    }

    /// Called after a catalog change of a project (visibility, cards): drops its cached statistics.
    pub async fn catalog_changed(&self, project: &str) {
        self.stores.cache.invalidate_tag(&format!("catalog:{project}")).await;
    }

    /// Loaded collections with their size and watermark (admin operations view).
    pub fn loaded_collections(&self) -> Vec<LoadedCollection> {
        let collections = self.collections.lock().unwrap();
        let mut out: Vec<LoadedCollection> = collections
            .iter()
            .map(|(k, e)| {
                let (project, schema) = k.split_once('/').unwrap_or((k, ""));
                LoadedCollection { project: project.into(), schema: schema.into(), rows: e.rows.len(), watermark: e.watermark.clone() }
            })
            .collect();
        out.sort_by(|a, b| a.project.cmp(&b.project).then(a.schema.cmp(&b.schema)));
        out
    }

    /// Calculations that run now.
    pub fn running_calculations(&self) -> usize {
        self.flights.lock().unwrap().len()
    }

    /// Called after a definition change of a dataset: results of the old definition are
    /// unreachable through the definition hash; this also clears the descriptor cache tag.
    pub async fn definition_changed(&self, project: &str, report: &str, dataset_id: &str) {
        self.stores
            .cache
            .invalidate_tag(&format!("dataset:{project}:{report}:{dataset_id}"))
            .await;
    }

    /// Payload rows of one schema, from the in-process copy or the document store.
    pub async fn collection(&self, project: &str, schema: &str) -> Result<Arc<Vec<Row>>, ReportError> {
        Ok(self.collection_with_watermark(project, schema).await?.0)
    }

    async fn collection_with_watermark(&self, project: &str, schema: &str) -> Result<(Arc<Vec<Row>>, Watermark), ReportError> {
        let key = format!("{project}/{schema}");
        let generation = self.generations.lock().unwrap().get(&key).copied().unwrap_or(0);
        if let Some(entry) = self.collections.lock().unwrap().get(&key) {
            if entry.generation == generation {
                return Ok((entry.rows.clone(), entry.watermark.clone()));
            }
        }
        let records = self.stores.docs.load_records(project, schema, self.max_scan_rows).await?;
        let watermark = Watermark {
            records: records.len(),
            last_received_at: records.iter().map(|r| r.received_at.clone()).max(),
        };
        let rows: Vec<Row> = records
            .into_iter()
            .filter_map(|r| r.payload.as_object().cloned())
            .collect();
        let rows = Arc::new(rows);
        let mut cache = self.collections.lock().unwrap();
        if self.generations.lock().unwrap().get(&key).copied().unwrap_or(0) != generation {
            // Records arrived while this copy loaded: use it once, do not keep it.
            return Ok((rows, watermark));
        }
        let used: usize = cache.values().map(|e| e.rows.len()).sum();
        if used + rows.len() > self.max_cached_rows {
            cache.clear();
        }
        cache.insert(key, CollectionEntry { generation, rows: rows.clone(), watermark: watermark.clone(), periods: HashMap::new() });
        Ok((rows, watermark))
    }

    /// Watermarks of every schema that a definition reads.
    async fn watermarks(&self, project: &str, spec: &DatasetSpec) -> Result<BTreeMap<String, Watermark>, ReportError> {
        let mut out = BTreeMap::new();
        for s in dependencies(spec) {
            out.insert(s.clone(), self.collection_with_watermark(project, &s).await?.1);
        }
        Ok(out)
    }

    /// Source rows after unions, lookups and row expressions.
    async fn base(&self, project: &str, spec: &DatasetSpec) -> Result<Arc<Vec<Row>>, ReportError> {
        let Some(source) = spec.source.as_deref() else {
            return Ok(Arc::new(Vec::new()));
        };
        let mut raw: Vec<Row> = self.collection(project, source).await?.as_ref().clone();
        for extra in &spec.union {
            raw.extend(self.collection(project, extra).await?.iter().cloned());
        }
        if spec.lookups.is_empty() && spec.row_derived.is_empty() && spec.buckets.is_empty() {
            return Ok(Arc::new(raw));
        }
        let mut lookups: HashMap<String, Arc<Vec<Row>>> = HashMap::new();
        for l in &spec.lookups {
            if !lookups.contains_key(&l.collection) {
                lookups.insert(l.collection.clone(), self.collection(project, &l.collection).await?);
            }
        }
        let spec = spec.clone();
        let rows = tokio::task::spawn_blocking(move || {
            let loader = |name: &str| {
                lookups
                    .get(name)
                    .cloned()
                    .ok_or_else(|| EngineError::Spec(format!("unknown lookup '{name}'")))
            };
            engine::prepare_base(&raw, &spec, &loader, &spec.params)
        })
        .await
        .map_err(|e| ReportError::Internal(e.to_string()))?
        .map_err(engine_err)?;
        Ok(Arc::new(rows))
    }

    /// Checks that every client filter targets a declared filter field.
    pub fn validate_filters(spec: &DatasetSpec, filters: &[FilterParam]) -> Result<(), ReportError> {
        for f in filters {
            if !spec.filters.iter().any(|s| s.field == f.field()) {
                return Err(ReportError::BadRequest(format!(
                    "field '{}' is not filterable in this dataset",
                    f.field()
                )));
            }
        }
        Ok(())
    }

    /// Params plus the values of referenced single-row datasets of the same report.
    fn scalars<'a>(
        &'a self,
        project: &'a str,
        report: &'a str,
        spec: &'a DatasetSpec,
        filters: &'a [FilterParam],
        depth: usize,
    ) -> BoxFuture<'a, Result<HashMap<String, f64>, ReportError>> {
        Box::pin(async move {
            let mut out = spec.params.clone();
            if spec.refs.is_empty() {
                return Ok(out);
            }
            if depth >= MAX_REF_DEPTH {
                return Err(ReportError::BadRequest("dataset references are too deep".into()));
            }
            for (var, r) in &spec.refs {
                let target = catalog::get_dataset(&self.stores.db, project, report, &r.dataset)
                    .await?
                    .ok_or_else(|| ReportError::not_found(format!("referenced dataset '{}'", r.dataset)))?;
                let usable: Vec<FilterParam> = filters
                    .iter()
                    .filter(|f| target.spec.filters.iter().any(|s| s.field == f.field()))
                    .cloned()
                    .collect();
                let rows = self.rows(project, report, &target.spec, &usable, depth + 1).await?;
                let value = rows
                    .first()
                    .and_then(|row| row.get(&r.field))
                    .and_then(engine::as_f64)
                    .unwrap_or(f64::NAN);
                out.insert(var.clone(), value);
            }
            Ok(out)
        })
    }

    /// Calculated rows of a definition before projection and paging.
    fn rows<'a>(
        &'a self,
        project: &'a str,
        report: &'a str,
        spec: &'a DatasetSpec,
        filters: &'a [FilterParam],
        depth: usize,
    ) -> BoxFuture<'a, Result<Vec<Row>, ReportError>> {
        Box::pin(async move {
            let scalars = self.scalars(project, report, spec, filters, depth).await?;
            let base = self.base(project, spec).await?;
            let own: Vec<FilterParam> = filters
                .iter()
                .filter(|f| spec.filters.iter().any(|s| s.field == f.field() && !s.refs_only()))
                .cloned()
                .collect();
            let spec = spec.clone();
            let work = tokio::task::spawn_blocking(move || engine::compute_rows(&base, &spec, &own, &scalars));
            let rows = tokio::time::timeout(CALCULATION_TIMEOUT, work)
                .await
                .map_err(|_| ReportError::BadRequest(format!("the calculation took more than {}s; narrow the filters", CALCULATION_TIMEOUT.as_secs())))?
                .map_err(|e| ReportError::Internal(e.to_string()))?
                .map_err(engine_err)?;
            if rows.len() > crate::domain::calculations::MAX_RESULT_ROWS {
                return Err(ReportError::BadRequest(format!(
                    "the result has {} rows, more than {}; add a limit or a grouping",
                    rows.len(),
                    crate::domain::calculations::MAX_RESULT_ROWS
                )));
            }
            Ok(rows)
        })
    }

    /// Localized description with filter options. Gated callers get the same descriptor;
    /// the access layer removes protected parts before it leaves the engine.
    pub async fn describe(&self, record: &DatasetRecord, lang: &str) -> Result<DatasetDescriptor, ReportError> {
        let key = format!(
            "desc:v1:{}:{}:{}:{}:{}:{}",
            record.project, record.report_slug, record.dataset_id, record.calculation_id, record.calculation_version, lang
        );
        if let Some(hit) = self.stores.cache.get(&key).await.and_then(|t| serde_json::from_str::<DatasetDescriptor>(&t).ok()) {
            return Ok(hit);
        }
        let built = self.build_descriptor(record, lang).await?;
        if let Ok(text) = serde_json::to_string(&built) {
            self.stores.cache.set(&key, &text, self.result_ttl).await;
            for schema in dependencies(&record.spec) {
                self.stores.cache.tag(&schema_tag(&record.project, &schema), &key, self.result_ttl).await;
            }
            self.stores
                .cache
                .tag(&format!("dataset:{}:{}:{}", record.project, record.report_slug, record.dataset_id), &key, self.result_ttl)
                .await;
        }
        Ok(built)
    }

    async fn build_descriptor(&self, record: &DatasetRecord, lang: &str) -> Result<DatasetDescriptor, ReportError> {
        let spec = &record.spec;
        let fields = spec
            .fields
            .iter()
            .map(|f| FieldInfo {
                name: f.name.clone(),
                label: resolve_text(&f.label, lang),
                field_type: f.field_type.clone(),
                role: f.role.clone(),
                unit: f.unit.clone(),
                decimals: f.decimals,
            })
            .collect();
        let mut filters = Vec::new();
        if spec.filters.iter().any(|f| !f.refs_only()) {
            let base = self.base(&record.project, spec).await?;
            for fs in spec.filters.iter().filter(|f| !f.refs_only()) {
                let mut info = FilterInfo {
                    field: fs.field.clone(),
                    label: resolve_text(&fs.label, lang),
                    filter_type: fs.filter_type.clone(),
                    options: Vec::new(),
                    min: None,
                    max: None,
                };
                let mut values: Vec<&Value> = Vec::new();
                for r in base.iter() {
                    if engine::matches_all(r, &spec.where_).map_err(engine_err)? {
                        if let Some(v) = r.get(&fs.field).filter(|v| !v.is_null()) {
                            values.push(v);
                        }
                    }
                }
                if fs.filter_type == "category" {
                    let mut seen = BTreeMap::new();
                    for v in values {
                        seen.entry(key_of(v)).or_insert_with(|| v.clone());
                        if seen.len() > MAX_FILTER_OPTIONS {
                            break;
                        }
                    }
                    let mut opts: Vec<Value> = seen.into_values().collect();
                    opts.sort_by(compare_values);
                    info.options = opts
                        .into_iter()
                        .map(|v| FilterOption { label: value_label(spec, &fs.field, &v, lang), value: v })
                        .collect();
                } else {
                    info.min = values.iter().copied().min_by(|a, b| compare_values(a, b)).cloned();
                    info.max = values.iter().copied().max_by(|a, b| compare_values(a, b)).cloned();
                }
                filters.push(info);
            }
        }
        Ok(DatasetDescriptor {
            dataset_id: record.dataset_id.clone(),
            title: resolve_text(&spec.title, lang),
            description: resolve_text(&spec.description, lang),
            equation: spec.equation.clone(),
            data_tier: record.data_tier,
            fields,
            filters,
            can_view: true,
            visibility: record.visibility.clone(),
        })
    }

    /// One page of calculated rows.
    #[allow(clippy::too_many_arguments)]
    pub async fn page(
        &self,
        record: &DatasetRecord,
        filters: &[FilterParam],
        lang: &str,
        offset: usize,
        limit: usize,
        class: AccessClass,
    ) -> Result<DatasetPage, ReportError> {
        Self::validate_filters(&record.spec, filters)?;
        let CachedResult { rows, lineage } = self.cached_rows(record, filters, lang, class).await?;
        let total_rows = rows.len();
        let page_rows: Vec<Row> = rows.into_iter().skip(offset).take(limit).collect();
        let mut applied = BTreeMap::new();
        for f in filters {
            let v = match f {
                FilterParam::In { values, .. } => serde_json::json!(values),
                FilterParam::Range { from, to, .. } => serde_json::json!({"from": from, "to": to}),
            };
            applied.insert(f.field().to_string(), v);
        }
        Ok(DatasetPage {
            descriptor: self.describe(record, lang).await?,
            language: lang.to_string(),
            rows: page_rows,
            offset,
            limit,
            total_rows,
            applied_filters: applied,
            lineage,
        })
    }

    /// Published versions never change, so the calculation version identifies the definition.
    fn result_key(record: &DatasetRecord, filters: &[FilterParam], lang: &str, class: AccessClass) -> String {
        let filters = serde_json::to_string(filters).unwrap_or_default();
        format!(
            "result:v2:{}:{}:{}:{}:{}:{}:{}:{}",
            record.project,
            record.report_slug,
            record.dataset_id,
            record.calculation_id,
            record.calculation_version,
            lang,
            hash_of(&filters),
            class.tag()
        )
    }

    /// Calculated, projected rows: from Redis, or calculated once and stored.
    async fn cached_rows(
        &self,
        record: &DatasetRecord,
        filters: &[FilterParam],
        lang: &str,
        class: AccessClass,
    ) -> Result<CachedResult, ReportError> {
        let key = Self::result_key(record, filters, lang, class);
        if let Some(rows) = self.read_cache(&key).await {
            return Ok(rows);
        }
        // In-process single flight: one calculation per key in this process.
        let flight = self
            .flights
            .lock()
            .unwrap()
            .entry(key.clone())
            .or_insert_with(|| Arc::new(tokio::sync::Mutex::new(())))
            .clone();
        let _local = flight.lock().await;
        if let Some(rows) = self.read_cache(&key).await {
            return Ok(rows);
        }
        // Cross-process gate: wait briefly for another engine that computes the same key.
        let token = uuid::Uuid::new_v4().to_string();
        let mut state = self.stores.cache.try_lock(&key, &token, self.gate_ttl).await;
        let started = Instant::now();
        while state == LockState::Busy && started.elapsed() < LOCK_WAIT {
            tokio::time::sleep(Duration::from_millis(200)).await;
            if let Some(rows) = self.read_cache(&key).await {
                return Ok(rows);
            }
            state = self.stores.cache.try_lock(&key, &token, self.gate_ttl).await;
        }
        let result = self.calculate_and_store(record, filters, lang, &key).await;
        if state == LockState::Acquired {
            self.stores.cache.unlock(&key, &token).await;
        }
        self.flights.lock().unwrap().remove(&key);
        result
    }

    async fn read_cache(&self, key: &str) -> Option<CachedResult> {
        match self.stores.cache.get(key).await {
            Some(text) => match serde_json::from_str::<CachedResult>(&text) {
                Ok(rows) => {
                    self.count(|c| c.hits += 1);
                    tracing::debug!(key, "cache hit");
                    Some(rows)
                }
                Err(_) => None,
            },
            None => {
                self.count(|c| c.misses += 1);
                None
            }
        }
    }

    async fn calculate_and_store(
        &self,
        record: &DatasetRecord,
        filters: &[FilterParam],
        lang: &str,
        key: &str,
    ) -> Result<CachedResult, ReportError> {
        let started = Instant::now();
        let source_watermark = self.watermarks(&record.project, &record.spec).await?;
        let calculated = self.rows(&record.project, &record.report_slug, &record.spec, filters, 0).await?;
        let projected = project_rows(&record.spec, calculated, lang);
        let inputs = crate::dal::calculations::get(&self.stores.db, &record.project, &record.calculation_id, record.calculation_version)
            .await?
            .map(|c| c.inputs)
            .unwrap_or_default();
        let result = CachedResult {
            rows: projected,
            lineage: Lineage {
                calculation_id: record.calculation_id.clone(),
                calculation_version: record.calculation_version,
                inputs,
                source_watermark,
                filters: serde_json::to_value(filters).unwrap_or(Value::Null),
                calculated_at: chrono::Utc::now().to_rfc3339(),
            },
        };
        self.count(|c| c.calculations += 1);
        tracing::info!(
            project = %record.project,
            report = %record.report_slug,
            dataset = %record.dataset_id,
            rows = result.rows.len(),
            ms = started.elapsed().as_millis() as u64,
            "dataset calculated"
        );
        if let Ok(text) = serde_json::to_string(&result) {
            self.stores.cache.set(key, &text, self.result_ttl).await;
            for schema in dependencies(&record.spec) {
                self.stores.cache.tag(&schema_tag(&record.project, &schema), key, self.result_ttl).await;
            }
            self.stores
                .cache
                .tag(
                    &format!("dataset:{}:{}:{}", record.project, record.report_slug, record.dataset_id),
                    key,
                    self.result_ttl,
                )
                .await;
        }
        Ok(result)
    }

    /// First and last value of a field in one schema.
    pub async fn period(&self, project: &str, schema: &str, field: &str) -> Result<Option<(Value, Value)>, ReportError> {
        let rows = self.collection(project, schema).await?;
        let key = format!("{project}/{schema}");
        if let Some(hit) = self.collections.lock().unwrap().get(&key).and_then(|e| e.periods.get(field).cloned()) {
            return Ok(hit);
        }
        let found = Self::scan_period(&rows, field);
        if let Some(e) = self.collections.lock().unwrap().get_mut(&key) {
            e.periods.insert(field.to_string(), found.clone());
        }
        Ok(found)
    }

    fn scan_period(rows: &[Row], field: &str) -> Option<(Value, Value)> {
        let mut min: Option<&Value> = None;
        let mut max: Option<&Value> = None;
        for r in rows.iter() {
            if let Some(v) = r.get(field).filter(|v| !v.is_null()) {
                if min.is_none_or(|m| compare_values(v, m).is_lt()) {
                    min = Some(v);
                }
                if max.is_none_or(|m| compare_values(v, m).is_gt()) {
                    max = Some(v);
                }
            }
        }
        min.zip(max).map(|(a, b)| (a.clone(), b.clone()))
    }
}

fn value_label(spec: &DatasetSpec, field: &str, v: &Value, lang: &str) -> String {
    spec.value_labels
        .get(field)
        .and_then(|m| m.get(&key_of(v)))
        .map(|t| resolve_text(t, lang))
        .unwrap_or_else(|| key_of(v))
}

/// Projects calculated rows on the declared fields, rounds numbers and applies value labels.
fn project_rows(spec: &DatasetSpec, rows: Vec<Row>, lang: &str) -> Vec<Row> {
    if spec.fields.is_empty() {
        return rows;
    }
    rows.into_iter()
        .map(|r| {
            let mut out = Row::new();
            for f in &spec.fields {
                let mut v = r.get(&f.name).cloned().unwrap_or(Value::Null);
                if let Some(d) = f.decimals {
                    v = round_to(&v, d);
                }
                if spec.value_labels.contains_key(&f.name) && !v.is_null() {
                    v = Value::String(value_label(spec, &f.name, &v, lang));
                }
                out.insert(f.name.clone(), v);
            }
            out
        })
        .collect()
}
