use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::Row;

use crate::core::error::ReportError;
use crate::dal::calculations::{self, CalculationVersion, InputRef};
use crate::dal::catalog::{self, DatasetRecord, ReportMetadata, ReportRecord};
use crate::dal::documents::RecordDoc;
use crate::dal::Stores;
use crate::domain::auth::{Audience, ControlAuthority, ViewerScope};
use crate::domain::datasets::service::DatasetService;
use crate::domain::datasets::spec::{DataTier, DatasetSpec, FieldSpec, I18nText};
use std::collections::BTreeSet;

pub const DEFAULT_MAX_UPLOAD_BYTES: usize = 1_048_576;
pub const DEFAULT_MAX_UPLOAD_RECORDS: usize = 1000;

#[derive(Debug, Clone, Serialize)]
pub struct OwnerItemSummary {
    pub id: String,
    pub project: String,
    pub report_slug: String,
    pub dataset_id: String,
    pub source_app: String,
    pub template_id: String,
    pub template_version: i64,
    pub audience: String,
    pub control_authority: String,
    pub etag: String,
    pub embed_url: String,
    pub reference_count: i64,
    pub row_count: usize,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct OwnerItemDetail {
    pub item: OwnerItemSummary,
    pub mapping: Value,
    pub config: Value,
    pub rows: Vec<Value>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CreateOwnerItemInput {
    pub title: Option<String>,
    pub source_app: Option<String>,
    pub template_id: String,
    pub template_version: i64,
    pub audience: Option<String>,
    pub mapping: Value,
    #[serde(default)]
    pub config: Value,
    pub rows: Vec<Value>,
    pub idempotency_key: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ReplaceDatasetInput {
    pub mapping: Option<Value>,
    pub config: Option<Value>,
    pub rows: Vec<Value>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct PatchOwnerItemInput {
    pub audience: Option<String>,
    pub visibility: Option<String>,
    pub config: Option<Value>,
    pub mapping: Option<Value>,
}

#[derive(Debug, Clone, Serialize)]
pub struct DeleteOwnerItemOutcome {
    pub deleted: bool,
    pub requires_confirmation: bool,
    pub reference_count: i64,
    pub message: String,
}

fn new_id() -> String {
    uuid::Uuid::new_v4().to_string()
}

fn now_secs() -> i64 {
    Utc::now().timestamp()
}

fn validate_mapping_and_rows(
    mapping: &Value,
    rows: &[Value],
    max_bytes: usize,
    max_records: usize,
) -> Result<(), ReportError> {
    let map_obj = mapping.as_object().ok_or_else(|| {
        ReportError::BadRequest("invalid_mapping: mapping must be a JSON object".into())
    })?;
    if map_obj.is_empty() {
        return Err(ReportError::BadRequest(
            "invalid_mapping: mapping must bind at least one template slot".into(),
        ));
    }
    for (slot, field) in map_obj {
        if slot.trim().is_empty() || field.as_str().map(str::trim).unwrap_or("").is_empty() {
            return Err(ReportError::BadRequest(format!(
                "invalid_mapping: slot '{slot}' must bind to a non-empty field name"
            )));
        }
    }
    if rows.len() > max_records {
        return Err(ReportError::BadRequest(format!(
            "payload_too_many_records: {} records exceeds limit of {max_records}",
            rows.len()
        )));
    }
    let parsed_size = serde_json::to_vec(&json!({ "mapping": mapping, "rows": rows }))
        .map(|v| v.len())
        .unwrap_or(0);
    if parsed_size > max_bytes {
        return Err(ReportError::BadRequest(format!(
            "payload_too_large: parsed payload {parsed_size} bytes exceeds limit of {max_bytes}"
        )));
    }
    for (idx, r) in rows.iter().enumerate() {
        if !r.is_object() {
            return Err(ReportError::BadRequest(format!(
                "invalid_row: row {idx} must be a JSON object"
            )));
        }
    }
    Ok(())
}

async fn upload_limits(stores: &Stores) -> (usize, usize) {
    let max_bytes = sqlx::query_scalar::<_, String>(
        "SELECT property_value FROM setting_properties WHERE setting_key = 'max_upload_bytes' LIMIT 1",
    )
    .fetch_optional(&stores.db.pool)
    .await
    .ok()
    .flatten()
    .and_then(|s| s.parse::<usize>().ok())
    .filter(|&v| v > 0)
    .unwrap_or(DEFAULT_MAX_UPLOAD_BYTES);

    let max_records = sqlx::query_scalar::<_, String>(
        "SELECT property_value FROM setting_properties WHERE setting_key = 'max_upload_records' LIMIT 1",
    )
    .fetch_optional(&stores.db.pool)
    .await
    .ok()
    .flatten()
    .and_then(|s| s.parse::<usize>().ok())
    .filter(|&v| v > 0)
    .unwrap_or(DEFAULT_MAX_UPLOAD_RECORDS);

    (max_bytes, max_records)
}

fn require_owner_user(scope: &ViewerScope) -> Result<&str, ReportError> {
    scope.user_uuid().ok_or(ReportError::Unauthorized)
}

fn map_summary(row: &sqlx::any::AnyRow, row_count: usize) -> Result<OwnerItemSummary, ReportError> {
    let id: String = row.try_get("id")?;
    let project: String = row.try_get("project_slug")?;
    let report_slug: String = row.try_get("report_slug")?;
    let dataset_id: String = row.try_get("dataset_id")?;
    Ok(OwnerItemSummary {
        embed_url: format!("/projects/{project}/showcase/{report_slug}/cards/{dataset_id}/embed"),
        id,
        project,
        report_slug,
        dataset_id,
        source_app: row.try_get("source_app")?,
        template_id: row.try_get("template_id")?,
        template_version: row.try_get("template_version")?,
        audience: row.try_get("audience")?,
        control_authority: row.try_get("control_authority")?,
        etag: row.try_get("etag")?,
        reference_count: row.try_get("reference_count")?,
        row_count,
        created_at: row.try_get("created_at")?,
        updated_at: row.try_get("updated_at")?,
    })
}

fn owner_fields(mapping: &Value, rows: &[Value]) -> Vec<FieldSpec> {
    let mut seen = BTreeSet::new();
    let mut fields = Vec::new();
    let sample = rows.first();
    if let Some(obj) = mapping.as_object() {
        for col_val in obj.values() {
            if let Some(col) = col_val.as_str().map(str::trim).filter(|s| !s.is_empty()) {
                if !seen.insert(col.to_string()) {
                    continue;
                }
                let is_num = sample
                    .and_then(|r| r.get(col))
                    .is_some_and(|v| v.is_number());
                fields.push(FieldSpec {
                    name: col.to_string(),
                    label: I18nText::from([("en".into(), col.to_string())]),
                    field_type: if is_num { "float" } else { "string" }.to_string(),
                    role: if is_num { "measure" } else { "dimension" }.to_string(),
                    unit: None,
                    decimals: None,
                    missing_means: "no_data".to_string(),
                    denominator_field: None,
                    denominator_text: None,
                });
            }
        }
    }
    fields
}

#[allow(clippy::too_many_arguments)]
async fn publish_owner_dataset(
    stores: &Stores,
    project: &str,
    item_id: &str,
    report_slug: &str,
    dataset_id: &str,
    title: &str,
    source_app: &str,
    owner_id: &str,
    audience: Audience,
    mapping: &Value,
    rows: &[Value],
) -> Result<(), ReportError> {
    let calc_id = format!("owner-calc-{item_id}");
    let prev_ver: i64 = sqlx::query_scalar(
        "SELECT COALESCE(MAX(version), 0) FROM calculation_versions WHERE project_slug = $1 AND calculation_id = $2",
    )
    .bind(project)
    .bind(&calc_id)
    .fetch_one(&stores.db.pool)
    .await?;
    let version = prev_ver + 1;
    let row_schema = format!("owner-rows-{item_id}-v{version}");

    let row_docs: Vec<RecordDoc> = rows
        .iter()
        .enumerate()
        .map(|(idx, row)| {
            RecordDoc::new(
                project,
                &row_schema,
                1,
                &format!("owner-row:{item_id}:v{version}:{idx}"),
                None,
                None,
                row.clone(),
            )
        })
        .collect();
    if !row_docs.is_empty() {
        stores.docs.insert_records(&row_docs).await?;
    }

    let spec = DatasetSpec {
        title: I18nText::from([("en".into(), title.to_string())]),
        source: Some(row_schema.clone()),
        fields: owner_fields(mapping, rows),
        ..Default::default()
    };
    let calc = CalculationVersion {
        project: project.to_string(),
        calculation_id: calc_id.clone(),
        version,
        status: "draft".to_string(),
        input_schema: Some(row_schema.clone()),
        input_schema_version: Some(1),
        inputs: vec![InputRef {
            schema: row_schema,
            version: 1,
        }],
        definition: spec.clone(),
        needs_review: false,
        created_at: String::new(),
        published_at: None,
    };
    calculations::save_draft(&stores.db, &calc).await?;
    calculations::publish(&stores.db, &calc).await?;

    let dataset_rec = DatasetRecord {
        project: project.to_string(),
        report_slug: report_slug.to_string(),
        dataset_id: dataset_id.to_string(),
        data_tier: DataTier::Real,
        calculation_id: calc_id,
        calculation_version: version,
        spec,
        visibility: audience.to_visibility().as_str().to_string(),
        discoverable: false,
        source_app: source_app.to_string(),
        owner_id: owner_id.to_string(),
        control_authority: ControlAuthority::UserOwned.as_str().to_string(),
        audience: audience.as_str().to_string(),
    };
    catalog::upsert_dataset(&stores.db, &dataset_rec).await?;
    Ok(())
}

pub async fn create_item(
    stores: &Stores,
    datasets: &DatasetService,
    scope: &ViewerScope,
    project: &str,
    input: CreateOwnerItemInput,
    header_idemp: Option<&str>,
) -> Result<(OwnerItemDetail, bool), ReportError> {
    let owner_id = require_owner_user(scope)?;
    catalog::active_project(&stores.db, project).await?;

    if input.template_id.trim().is_empty() || input.template_version < 1 {
        return Err(ReportError::BadRequest(
            "invalid_template: template_id and positive template_version are required".into(),
        ));
    }

    let idemp = header_idemp
        .or(input.idempotency_key.as_deref())
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or("")
        .to_string();

    if !idemp.is_empty() {
        if let Some(existing) = sqlx::query(
            "SELECT id, project_slug, report_slug, dataset_id, owner_id, source_app, template_id, template_version,
                    audience, control_authority, couch_doc_id, etag, reference_count, created_at, updated_at
             FROM user_chart_items
             WHERE owner_id = $1 AND idempotency_key = $2",
        )
        .bind(owner_id)
        .bind(&idemp)
        .fetch_optional(&stores.db.pool)
        .await?
        {
            let id: String = existing.try_get("id")?;
            let detail = get_item(stores, scope, &id, None, None).await?;
            return Ok((detail, false));
        }
    }

    let audience = match input.audience.as_deref() {
        Some(raw) => Audience::parse_strict(raw)?,
        None => Audience::Personal,
    };

    let (max_bytes, max_records) = upload_limits(stores).await;
    validate_mapping_and_rows(&input.mapping, &input.rows, max_bytes, max_records)?;

    let item_id = new_id();
    let report_slug = format!(
        "user-{}-{}",
        &owner_id[..owner_id.len().min(8)],
        &item_id[..8]
    );
    let dataset_id = "primary".to_string();
    let doc_id = format!("owner-item:{item_id}");
    let etag = format!("\"{}\"", new_id());
    let ts = now_secs();
    let source_app = input
        .source_app
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or("annotations")
        .to_string();

    let payload = json!({
        "mapping": input.mapping,
        "config": input.config,
        "rows": input.rows,
    });
    let rec = RecordDoc::new(project, "owner-chart-v1", 1, &doc_id, None, None, payload);
    let actual_doc_id = rec.id.clone();
    stores.docs.insert_records(&[rec]).await?;

    let title = input
        .title
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or("User Chart")
        .to_string();

    let rep = ReportRecord {
        project: project.to_string(),
        slug: report_slug.clone(),
        title: I18nText::from([("en".into(), title.clone())]),
        description: I18nText::default(),
        metadata: ReportMetadata::default(),
        visibility: audience.to_visibility().as_str().to_string(),
        discoverable: false,
        updated_at: String::new(),
        source_app: source_app.clone(),
        owner_id: owner_id.to_string(),
        control_authority: ControlAuthority::UserOwned.as_str().to_string(),
        audience: audience.as_str().to_string(),
    };
    catalog::upsert_report(&stores.db, &rep).await?;
    publish_owner_dataset(
        stores,
        project,
        &item_id,
        &report_slug,
        &dataset_id,
        &title,
        &source_app,
        owner_id,
        audience,
        &input.mapping,
        &input.rows,
    )
    .await?;

    sqlx::query(
        "INSERT INTO user_chart_items(
            id, project_slug, report_slug, dataset_id, owner_id, source_app, template_id, template_version,
            audience, control_authority, couch_doc_id, etag, idempotency_key, reference_count, created_at, updated_at
         ) VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9, 'user_owned', $10, $11, $12, 0, $13, $13)",
    )
    .bind(&item_id)
    .bind(project)
    .bind(&report_slug)
    .bind(&dataset_id)
    .bind(owner_id)
    .bind(&source_app)
    .bind(input.template_id.trim())
    .bind(input.template_version)
    .bind(audience.as_str())
    .bind(&actual_doc_id)
    .bind(&etag)
    .bind(&idemp)
    .bind(ts)
    .execute(&stores.db.pool)
    .await?;

    datasets.catalog_changed(project).await;
    let detail = get_item(stores, scope, &item_id, Some(project), Some(&report_slug)).await?;
    Ok((detail, true))
}

pub async fn get_item(
    stores: &Stores,
    scope: &ViewerScope,
    item_id: &str,
    project_slug: Option<&str>,
    report_slug: Option<&str>,
) -> Result<OwnerItemDetail, ReportError> {
    let caller = require_owner_user(scope)?;
    let row = match (project_slug, report_slug) {
        (Some(proj), Some(rep)) => {
            sqlx::query(
                "SELECT id, project_slug, report_slug, dataset_id, owner_id, source_app, template_id, template_version,
                        audience, control_authority, couch_doc_id, etag, reference_count, created_at, updated_at
                 FROM user_chart_items
                 WHERE (id = $1) OR (dataset_id = $1 AND project_slug = $2 AND report_slug = $3)
                 ORDER BY CASE WHEN owner_id = $4 THEN 0 ELSE 1 END, id ASC
                 LIMIT 1",
            )
            .bind(item_id)
            .bind(proj)
            .bind(rep)
            .bind(caller)
            .fetch_optional(&stores.db.pool)
            .await?
        }
        _ => {
            sqlx::query(
                "SELECT id, project_slug, report_slug, dataset_id, owner_id, source_app, template_id, template_version,
                        audience, control_authority, couch_doc_id, etag, reference_count, created_at, updated_at
                 FROM user_chart_items
                 WHERE id = $1",
            )
            .bind(item_id)
            .fetch_optional(&stores.db.pool)
            .await?
        }
    }
    .ok_or_else(|| ReportError::NotFound("item not found".into()))?;

    let owner_id: String = row.try_get("owner_id")?;
    let project: String = row.try_get("project_slug")?;
    if owner_id != caller && !scope.can_admin(&project) {
        return Err(ReportError::Forbidden(
            "only the owner may access this item".into(),
        ));
    }

    let doc_id: String = row.try_get("couch_doc_id")?;
    let docs = stores
        .docs
        .load_records(&project, "owner-chart-v1", 5000)
        .await?;
    let doc = docs
        .into_iter()
        .find(|d| d.id == doc_id)
        .ok_or_else(|| ReportError::NotFound("item payload not found".into()))?;

    let rows = doc.payload["rows"].as_array().cloned().unwrap_or_default();
    let item = map_summary(&row, rows.len())?;
    Ok(OwnerItemDetail {
        item,
        mapping: doc.payload["mapping"].clone(),
        config: doc.payload["config"].clone(),
        rows,
    })
}

pub async fn replace_dataset(
    stores: &Stores,
    datasets: &DatasetService,
    scope: &ViewerScope,
    item_id: &str,
    if_match: Option<&str>,
    input: ReplaceDatasetInput,
) -> Result<OwnerItemDetail, ReportError> {
    let detail = get_item(stores, scope, item_id, None, None).await?;
    let expected = if_match.map(str::trim).unwrap_or("");
    if expected.is_empty() || expected != detail.item.etag {
        return Err(ReportError::Conflict(
            "precondition_failed: If-Match header must match current ETag".into(),
        ));
    }
    let authority = ControlAuthority::parse(&detail.item.control_authority);
    if !scope.can_publish_owned(
        &detail.item.project,
        scope.user_uuid().unwrap_or(""),
        authority,
    ) {
        return Err(ReportError::Forbidden(
            "app-controlled items cannot be replaced by normal users".into(),
        ));
    }

    let mapping = input.mapping.unwrap_or(detail.mapping);
    let config = input.config.unwrap_or(detail.config);
    let (max_bytes, max_records) = upload_limits(stores).await;
    validate_mapping_and_rows(&mapping, &input.rows, max_bytes, max_records)?;

    let new_doc_key = format!("owner-item:{item_id}:{}", new_id());
    let new_etag = format!("\"{}\"", new_id());
    let ts = now_secs();
    let rec = RecordDoc::new(
        &detail.item.project,
        "owner-chart-v1",
        1,
        &new_doc_key,
        None,
        None,
        json!({
            "mapping": mapping,
            "config": config,
            "rows": input.rows,
        }),
    );
    let new_doc_id = rec.id.clone();
    stores.docs.insert_records(&[rec]).await?;

    sqlx::query(
        "UPDATE user_chart_items SET couch_doc_id = $1, etag = $2, updated_at = $3 WHERE id = $4",
    )
    .bind(&new_doc_id)
    .bind(&new_etag)
    .bind(ts)
    .bind(item_id)
    .execute(&stores.db.pool)
    .await?;

    let owner_id = require_owner_user(scope)?.to_string();
    let audience = Audience::parse(&detail.item.audience);
    publish_owner_dataset(
        stores,
        &detail.item.project,
        item_id,
        &detail.item.report_slug,
        &detail.item.dataset_id,
        &detail.item.report_slug,
        &detail.item.source_app,
        &owner_id,
        audience,
        &mapping,
        &input.rows,
    )
    .await?;

    datasets
        .invalidate_visibility_change(&detail.item.project, &detail.item.report_slug)
        .await;
    get_item(stores, scope, item_id, None, None).await
}

pub async fn patch_item(
    stores: &Stores,
    datasets: &DatasetService,
    scope: &ViewerScope,
    item_id: &str,
    input: PatchOwnerItemInput,
) -> Result<OwnerItemDetail, ReportError> {
    let detail = get_item(stores, scope, item_id, None, None).await?;
    let caller = require_owner_user(scope)?;
    let authority = ControlAuthority::parse(&detail.item.control_authority);
    if !scope.can_publish_owned(&detail.item.project, caller, authority) {
        return Err(ReportError::Forbidden(
            "only the owner of a user-owned item may change visibility or settings".into(),
        ));
    }

    let new_audience = match input.audience.as_deref().or(input.visibility.as_deref()) {
        Some(raw) => Audience::parse_strict(raw)?,
        None => Audience::parse(&detail.item.audience),
    };
    let new_etag = format!("\"{}\"", new_id());
    let ts = now_secs();

    if input.config.is_some() || input.mapping.is_some() {
        let mapping = input.mapping.unwrap_or(detail.mapping);
        let config = input.config.unwrap_or(detail.config);
        let (max_bytes, max_records) = upload_limits(stores).await;
        validate_mapping_and_rows(&mapping, &detail.rows, max_bytes, max_records)?;
        let new_doc_key = format!("owner-item:{item_id}:{}", new_id());
        let rec = RecordDoc::new(
            &detail.item.project,
            "owner-chart-v1",
            1,
            &new_doc_key,
            None,
            None,
            json!({
                "mapping": mapping,
                "config": config,
                "rows": detail.rows,
            }),
        );
        let new_doc_id = rec.id.clone();
        stores.docs.insert_records(&[rec]).await?;
        sqlx::query("UPDATE user_chart_items SET couch_doc_id = $1 WHERE id = $2")
            .bind(&new_doc_id)
            .bind(item_id)
            .execute(&stores.db.pool)
            .await?;
    }

    sqlx::query(
        "UPDATE user_chart_items SET audience = $1, etag = $2, updated_at = $3 WHERE id = $4",
    )
    .bind(new_audience.as_str())
    .bind(&new_etag)
    .bind(ts)
    .bind(item_id)
    .execute(&stores.db.pool)
    .await?;

    sqlx::query(
        "UPDATE reports SET visibility = $1, audience = $2 WHERE project_slug = $3 AND slug = $4",
    )
    .bind(new_audience.to_visibility().as_str())
    .bind(new_audience.as_str())
    .bind(&detail.item.project)
    .bind(&detail.item.report_slug)
    .execute(&stores.db.pool)
    .await?;

    sqlx::query(
        "UPDATE datasets SET visibility = $1, audience = $2 WHERE project_slug = $3 AND report_slug = $4",
    )
    .bind(new_audience.to_visibility().as_str())
    .bind(new_audience.as_str())
    .bind(&detail.item.project)
    .bind(&detail.item.report_slug)
    .execute(&stores.db.pool)
    .await?;

    datasets
        .invalidate_visibility_change(&detail.item.project, &detail.item.report_slug)
        .await;
    get_item(stores, scope, item_id, None, None).await
}

pub async fn delete_item(
    stores: &Stores,
    datasets: &DatasetService,
    scope: &ViewerScope,
    item_id: &str,
    confirm_reuse: bool,
) -> Result<DeleteOwnerItemOutcome, ReportError> {
    let detail = get_item(stores, scope, item_id, None, None).await?;
    let caller = require_owner_user(scope)?;
    let authority = ControlAuthority::parse(&detail.item.control_authority);
    if !scope.can_publish_owned(&detail.item.project, caller, authority) {
        return Err(ReportError::Forbidden(
            "only the owner of a user-owned item may delete it".into(),
        ));
    }

    if detail.item.reference_count > 0 && !confirm_reuse {
        return Ok(DeleteOwnerItemOutcome {
            deleted: false,
            requires_confirmation: true,
            reference_count: detail.item.reference_count,
            message: format!(
                "Item is referenced by {} note(s); pass confirm=true to delete",
                detail.item.reference_count
            ),
        });
    }

    sqlx::query("DELETE FROM user_chart_items WHERE id = $1")
        .bind(item_id)
        .execute(&stores.db.pool)
        .await?;
    catalog::delete_dataset(
        &stores.db,
        &detail.item.project,
        &detail.item.report_slug,
        &detail.item.dataset_id,
    )
    .await?;
    catalog::delete_report(&stores.db, &detail.item.project, &detail.item.report_slug).await?;

    datasets
        .invalidate_visibility_change(&detail.item.project, &detail.item.report_slug)
        .await;

    Ok(DeleteOwnerItemOutcome {
        deleted: true,
        requires_confirmation: false,
        reference_count: detail.item.reference_count,
        message: "Item deleted".into(),
    })
}
