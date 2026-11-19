//! Temporary question visual render jobs (RPT-13, #54).
//!
//! Jobs are stored only as TTL-bounded CouchDB documents and never create
//! catalog rows in `reports` or `datasets`.

use std::collections::BTreeMap;

use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use utoipa::ToSchema;

use crate::core::error::ReportError;
use crate::dal::{templates, Stores};
use crate::domain::owner::{DEFAULT_MAX_UPLOAD_BYTES, DEFAULT_MAX_UPLOAD_RECORDS};

pub const MIN_RENDER_DIM: u32 = 200;
pub const MAX_RENDER_DIM: u32 = 2400;
pub const DEFAULT_RENDER_WIDTH: u32 = 800;
pub const DEFAULT_RENDER_HEIGHT: u32 = 480;
pub const DEFAULT_RENDER_SCALE: u8 = 2;
pub const DEFAULT_TTL_SECONDS: i64 = 900;
pub const MIN_TTL_SECONDS: i64 = 1;
pub const MAX_TTL_SECONDS: i64 = 86_400;

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct CreateRenderJobInput {
    pub template_id: String,
    pub template_version: i64,
    pub mapping: BTreeMap<String, Vec<String>>,
    #[serde(default)]
    pub config: Value,
    pub rows: Vec<Value>,
    pub originating_scope: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub scale: Option<u8>,
    pub ttl_seconds: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct RenderJob {
    pub job_id: String,
    pub status: String,
    pub template_id: String,
    pub template_version: i64,
    pub visual: String,
    pub mapping: BTreeMap<String, Vec<String>>,
    pub config: Value,
    #[schema(value_type = Vec<Object>)]
    pub rows: Vec<Value>,
    pub originating_scope: String,
    pub width: u32,
    pub height: u32,
    pub scale: u8,
    pub created_at: i64,
    pub expires_at: i64,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct CleanupOutcome {
    pub cleaned: usize,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct DeleteRenderJobOutcome {
    pub deleted: bool,
    pub job_id: String,
}

pub async fn create_job(
    stores: &Stores,
    input: CreateRenderJobInput,
) -> Result<RenderJob, ReportError> {
    if input.template_id.trim().is_empty() || input.template_version < 1 {
        return Err(ReportError::BadRequest(
            "invalid_template: template_id and positive template_version are required".into(),
        ));
    }
    let tpl = templates::get_version(&stores.db, input.template_id.trim(), input.template_version)
        .await?
        .ok_or_else(|| {
            ReportError::not_found(format!(
                "visual template '{} v{}'",
                input.template_id, input.template_version
            ))
        })?;
    if tpl.status != "published" {
        return Err(ReportError::Conflict(format!(
            "visual template {} v{} must be published",
            input.template_id, input.template_version
        )));
    }
    if input.mapping.is_empty() {
        return Err(ReportError::BadRequest(
            "invalid_mapping: mapping must bind at least one slot".into(),
        ));
    }
    for slot in &tpl.slots {
        let count = input
            .mapping
            .get(&slot.slot_name)
            .map(|v| v.len() as i64)
            .unwrap_or(0);
        if slot.is_required && count < slot.min_count {
            return Err(ReportError::BadRequest(format!(
                "slot '{}' requires at least {} field(s)",
                slot.slot_name, slot.min_count
            )));
        }
        if count > slot.max_count {
            return Err(ReportError::BadRequest(format!(
                "slot '{}' allows at most {} field(s)",
                slot.slot_name, slot.max_count
            )));
        }
    }

    if input.rows.is_empty() || input.rows.len() > DEFAULT_MAX_UPLOAD_RECORDS {
        return Err(ReportError::BadRequest(format!(
            "invalid_rows: row count must be between 1 and {DEFAULT_MAX_UPLOAD_RECORDS}"
        )));
    }
    let bytes = serde_json::to_vec(&input.rows)
        .map_err(|e| ReportError::BadRequest(format!("invalid_rows: {e}")))?
        .len();
    if bytes > DEFAULT_MAX_UPLOAD_BYTES {
        return Err(ReportError::BadRequest(format!(
            "payload_too_large: rows exceed {DEFAULT_MAX_UPLOAD_BYTES} bytes"
        )));
    }

    let width = input.width.unwrap_or(DEFAULT_RENDER_WIDTH);
    let height = input.height.unwrap_or(DEFAULT_RENDER_HEIGHT);
    if !(MIN_RENDER_DIM..=MAX_RENDER_DIM).contains(&width)
        || !(MIN_RENDER_DIM..=MAX_RENDER_DIM).contains(&height)
    {
        return Err(ReportError::BadRequest(format!(
            "invalid_dimensions: width and height must be between {MIN_RENDER_DIM} and {MAX_RENDER_DIM}"
        )));
    }
    let scale = input.scale.unwrap_or(DEFAULT_RENDER_SCALE);
    if !matches!(scale, 2 | 3) {
        return Err(ReportError::BadRequest(
            "invalid_scale: scale must be 2 or 3".into(),
        ));
    }
    let ttl = input.ttl_seconds.unwrap_or(DEFAULT_TTL_SECONDS);
    if !(MIN_TTL_SECONDS..=MAX_TTL_SECONDS).contains(&ttl) {
        return Err(ReportError::BadRequest(format!(
            "invalid_ttl: ttl_seconds must be between {MIN_TTL_SECONDS} and {MAX_TTL_SECONDS}"
        )));
    }

    let now = Utc::now().timestamp();
    let job_id = uuid::Uuid::new_v4().to_string();
    let job = RenderJob {
        job_id: job_id.clone(),
        status: "ready".to_string(),
        template_id: tpl.template_id,
        template_version: tpl.version,
        visual: tpl.visual,
        mapping: input.mapping,
        config: input.config,
        rows: input.rows,
        originating_scope: input
            .originating_scope
            .unwrap_or_else(|| "certifications".to_string()),
        width,
        height,
        scale,
        created_at: now,
        expires_at: now + ttl,
    };

    let mut doc = serde_json::to_value(&job)
        .map_err(|e| ReportError::Internal(format!("serialize render_job: {e}")))?;
    doc["_id"] = json!(format!("render-job:{job_id}"));
    doc["type"] = json!("render_job");
    stores.docs.put_render_job(&doc).await?;
    Ok(job)
}

pub async fn get_job(stores: &Stores, job_id: &str) -> Result<RenderJob, ReportError> {
    let now = Utc::now().timestamp();
    let Some(doc) = stores.docs.get_render_job(job_id).await? else {
        return Err(ReportError::not_found(format!("render_job '{job_id}'")));
    };
    let job: RenderJob = serde_json::from_value(doc)
        .map_err(|e| ReportError::Internal(format!("deserialize render_job: {e}")))?;
    if job.expires_at <= now {
        let _ = stores.docs.delete_render_job(job_id).await;
        return Err(ReportError::not_found(format!("render_job '{job_id}'")));
    }
    Ok(job)
}

pub async fn delete_job(
    stores: &Stores,
    job_id: &str,
    confirmed: bool,
) -> Result<DeleteRenderJobOutcome, ReportError> {
    if !confirmed {
        return Err(ReportError::Conflict(
            "save_confirmation_required: pass confirmed=true after durable FSM save".into(),
        ));
    }
    let deleted = stores.docs.delete_render_job(job_id).await?;
    if !deleted {
        return Err(ReportError::not_found(format!("render_job '{job_id}'")));
    }
    Ok(DeleteRenderJobOutcome {
        deleted: true,
        job_id: job_id.to_string(),
    })
}

pub async fn cleanup_expired(
    stores: &Stores,
    now_override: Option<i64>,
) -> Result<CleanupOutcome, ReportError> {
    let now = now_override.unwrap_or_else(|| Utc::now().timestamp());
    let cleaned = stores.docs.cleanup_expired_render_jobs(now).await?;
    Ok(CleanupOutcome { cleaned })
}
