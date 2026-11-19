//! Normalized, versioned visual templates and card visual bindings (RPT-8, #52).

use std::collections::{BTreeMap, HashMap};

use serde::{Deserialize, Serialize};
use sqlx::Row;
use utoipa::ToSchema;

use super::sql::{flag_col, opt_col, Db};
use crate::core::error::ReportError;
use crate::domain::datasets::spec::{resolve_text, I18nText};

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct TemplateSlot {
    pub slot_name: String,
    /// dimension, measure, series, label, value, node_id, parent_id, edge_source, edge_target, group
    pub role: String,
    pub is_required: bool,
    pub min_count: i64,
    pub max_count: i64,
    pub accepted_types: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct TemplateOption {
    pub option_name: String,
    /// bool, int, float, text, enum
    pub value_type: String,
    #[serde(default)]
    pub default_value: String,
    #[serde(default)]
    pub allowed_values: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct VisualTemplateVersion {
    pub template_id: String,
    pub version: i64,
    /// chart or diagram
    pub kind: String,
    /// draft, published or retired
    #[serde(default = "default_draft")]
    pub status: String,
    pub visual: String,
    #[serde(default)]
    pub title: I18nText,
    #[serde(default)]
    pub slots: Vec<TemplateSlot>,
    #[serde(default)]
    pub options: Vec<TemplateOption>,
    #[serde(default)]
    pub published_at: Option<String>,
}

fn default_draft() -> String {
    "draft".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct TemplateDiscoveryItem {
    pub template_id: String,
    pub version: i64,
    pub kind: String,
    pub visual: String,
    pub title: String,
    pub slots: Vec<TemplateSlot>,
    pub options: Vec<TemplateOption>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema, PartialEq, Eq)]
pub struct CardVisualBinding {
    pub template: String,
    pub version: i64,
    pub mapping: BTreeMap<String, Vec<String>>,
    #[serde(default)]
    pub options: BTreeMap<String, String>,
}

pub async fn get_version(
    db: &Db,
    template_id: &str,
    version: i64,
) -> Result<Option<VisualTemplateVersion>, ReportError> {
    let sql = format!(
        "SELECT t.template_id, t.kind, CAST(v.version AS BIGINT) AS version, v.status, v.visual, {} AS published_at
         FROM visual_template_versions v
         JOIN visual_templates t ON t.template_id = v.template_id
         WHERE v.template_id = $1 AND v.version = $2",
        db.opt_text("v.published_at")
    );
    let Some(row) = sqlx::query(&sql)
        .bind(template_id)
        .bind(version)
        .fetch_optional(&db.pool)
        .await?
    else {
        return Ok(None);
    };

    let kind: String = row.try_get("kind")?;
    let status: String = row.try_get("status")?;
    let visual: String = row.try_get("visual")?;
    let published_at: Option<String> = opt_col(&row, "published_at")?;

    let title_rows = sqlx::query(
        "SELECT lang, text FROM localized_texts
         WHERE owner_kind = 'visual_template' AND owner_key = $1 AND text_key = 'title'",
    )
    .bind(format!("{template_id}:v{version}"))
    .fetch_all(&db.pool)
    .await?;
    let mut title = HashMap::new();
    for tr in title_rows {
        title.insert(tr.try_get("lang")?, tr.try_get("text")?);
    }

    let slot_sql = format!(
        "SELECT slot_name, role, {} AS req, CAST(min_count AS BIGINT) AS min_count, CAST(max_count AS BIGINT) AS max_count
         FROM visual_template_slots
         WHERE template_id = $1 AND version = $2
         ORDER BY slot_name",
        db.flag("is_required")
    );
    let slot_rows = sqlx::query(&slot_sql)
        .bind(template_id)
        .bind(version)
        .fetch_all(&db.pool)
        .await?;
    let mut slots = Vec::with_capacity(slot_rows.len());
    for sr in slot_rows {
        let slot_name: String = sr.try_get("slot_name")?;
        let type_rows = sqlx::query(
            "SELECT field_type FROM visual_template_slot_types
             WHERE template_id = $1 AND version = $2 AND slot_name = $3
             ORDER BY field_type",
        )
        .bind(template_id)
        .bind(version)
        .bind(&slot_name)
        .fetch_all(&db.pool)
        .await?;
        let accepted_types = type_rows
            .iter()
            .map(|r| r.try_get::<String, _>("field_type"))
            .collect::<Result<Vec<_>, _>>()?;
        slots.push(TemplateSlot {
            slot_name,
            role: sr.try_get("role")?,
            is_required: flag_col(&sr, "req")?,
            min_count: sr.try_get("min_count")?,
            max_count: sr.try_get("max_count")?,
            accepted_types,
        });
    }

    let opt_rows = sqlx::query(
        "SELECT option_name, value_type, default_value
         FROM visual_template_options
         WHERE template_id = $1 AND version = $2
         ORDER BY option_name",
    )
    .bind(template_id)
    .bind(version)
    .fetch_all(&db.pool)
    .await?;
    let mut options = Vec::with_capacity(opt_rows.len());
    for or in opt_rows {
        let option_name: String = or.try_get("option_name")?;
        let val_rows = sqlx::query(
            "SELECT allowed_value FROM visual_template_option_values
             WHERE template_id = $1 AND version = $2 AND option_name = $3
             ORDER BY allowed_value",
        )
        .bind(template_id)
        .bind(version)
        .bind(&option_name)
        .fetch_all(&db.pool)
        .await?;
        let allowed_values = val_rows
            .iter()
            .map(|r| r.try_get::<String, _>("allowed_value"))
            .collect::<Result<Vec<_>, _>>()?;
        options.push(TemplateOption {
            option_name,
            value_type: or.try_get("value_type")?,
            default_value: or.try_get("default_value")?,
            allowed_values,
        });
    }

    Ok(Some(VisualTemplateVersion {
        template_id: template_id.to_string(),
        version,
        kind,
        status,
        visual,
        title,
        slots,
        options,
        published_at,
    }))
}

pub async fn save_draft(db: &Db, t: &VisualTemplateVersion) -> Result<(), ReportError> {
    if t.template_id.trim().is_empty() || t.version < 1 || t.visual.trim().is_empty() {
        return Err(ReportError::BadRequest(
            "template_id, positive version, and visual are required".into(),
        ));
    }
    if !matches!(t.kind.as_str(), "chart" | "diagram") {
        return Err(ReportError::BadRequest(
            "kind must be 'chart' or 'diagram'".into(),
        ));
    }
    if let Some(existing) = get_version(db, &t.template_id, t.version).await? {
        if existing.status != "draft" {
            return Err(ReportError::Conflict(format!(
                "visual template {} v{} is {} and cannot change; create version {}",
                t.template_id,
                t.version,
                existing.status,
                t.version + 1
            )));
        }
    }

    let mut tx = db.pool.begin().await?;
    sqlx::query(
        "INSERT INTO visual_templates(template_id, kind) VALUES ($1, $2)
         ON CONFLICT(template_id) DO NOTHING",
    )
    .bind(&t.template_id)
    .bind(&t.kind)
    .execute(&mut *tx)
    .await?;

    let done = sqlx::query(
        "INSERT INTO visual_template_versions(template_id, version, status, visual)
         VALUES ($1, $2, 'draft', $3)
         ON CONFLICT(template_id, version) DO UPDATE SET visual = EXCLUDED.visual
         WHERE visual_template_versions.status = 'draft'",
    )
    .bind(&t.template_id)
    .bind(t.version)
    .bind(&t.visual)
    .execute(&mut *tx)
    .await?;
    if done.rows_affected() == 0 {
        return Err(ReportError::Conflict(
            "visual template version is no longer a draft".into(),
        ));
    }

    sqlx::query("DELETE FROM visual_template_slots WHERE template_id = $1 AND version = $2")
        .bind(&t.template_id)
        .bind(t.version)
        .execute(&mut *tx)
        .await?;
    for s in &t.slots {
        sqlx::query(
            "INSERT INTO visual_template_slots(template_id, version, slot_name, role, is_required, min_count, max_count)
             VALUES ($1, $2, $3, $4, $5, $6, $7)",
        )
        .bind(&t.template_id)
        .bind(t.version)
        .bind(&s.slot_name)
        .bind(&s.role)
        .bind(s.is_required)
        .bind(s.min_count)
        .bind(s.max_count)
        .execute(&mut *tx)
        .await?;
        for ft in &s.accepted_types {
            sqlx::query(
                "INSERT INTO visual_template_slot_types(template_id, version, slot_name, field_type)
                 VALUES ($1, $2, $3, $4)",
            )
            .bind(&t.template_id)
            .bind(t.version)
            .bind(&s.slot_name)
            .bind(ft)
            .execute(&mut *tx)
            .await?;
        }
    }

    sqlx::query("DELETE FROM visual_template_options WHERE template_id = $1 AND version = $2")
        .bind(&t.template_id)
        .bind(t.version)
        .execute(&mut *tx)
        .await?;
    for o in &t.options {
        sqlx::query(
            "INSERT INTO visual_template_options(template_id, version, option_name, value_type, default_value)
             VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(&t.template_id)
        .bind(t.version)
        .bind(&o.option_name)
        .bind(&o.value_type)
        .bind(&o.default_value)
        .execute(&mut *tx)
        .await?;
        for av in &o.allowed_values {
            sqlx::query(
                "INSERT INTO visual_template_option_values(template_id, version, option_name, allowed_value)
                 VALUES ($1, $2, $3, $4)",
            )
            .bind(&t.template_id)
            .bind(t.version)
            .bind(&o.option_name)
            .bind(av)
            .execute(&mut *tx)
            .await?;
        }
    }

    let owner_key = format!("{}:v{}", t.template_id, t.version);
    sqlx::query(
        "DELETE FROM localized_texts WHERE owner_kind = 'visual_template' AND owner_key = $1 AND text_key = 'title'",
    )
    .bind(&owner_key)
    .execute(&mut *tx)
    .await?;
    for (lang, text) in &t.title {
        sqlx::query(
            "INSERT INTO localized_texts(owner_kind, owner_key, text_key, lang, text)
             VALUES ('visual_template', $1, 'title', $2, $3)",
        )
        .bind(&owner_key)
        .bind(lang)
        .bind(text)
        .execute(&mut *tx)
        .await?;
    }

    tx.commit().await?;
    Ok(())
}

pub async fn publish(db: &Db, template_id: &str, version: i64) -> Result<bool, ReportError> {
    let sql = format!(
        "UPDATE visual_template_versions SET status = 'published', published_at = {}
         WHERE template_id = $1 AND version = $2 AND status = 'draft'",
        db.now()
    );
    let done = sqlx::query(&sql)
        .bind(template_id)
        .bind(version)
        .execute(&db.pool)
        .await?;
    Ok(done.rows_affected() > 0)
}

pub async fn list_published(
    db: &Db,
    kind: Option<&str>,
    lang: &str,
) -> Result<Vec<TemplateDiscoveryItem>, ReportError> {
    let rows = match kind {
        Some(k) => {
            sqlx::query(
                "SELECT v.template_id, CAST(v.version AS BIGINT) AS version
                 FROM visual_template_versions v
                 JOIN visual_templates t ON t.template_id = v.template_id
                 WHERE v.status = 'published' AND t.kind = $1
                 ORDER BY v.template_id, v.version",
            )
            .bind(k)
            .fetch_all(&db.pool)
            .await?
        }
        None => {
            sqlx::query(
                "SELECT template_id, CAST(version AS BIGINT) AS version
                 FROM visual_template_versions
                 WHERE status = 'published'
                 ORDER BY template_id, version",
            )
            .fetch_all(&db.pool)
            .await?
        }
    };
    let mut out = Vec::with_capacity(rows.len());
    for r in rows {
        let tid: String = r.try_get("template_id")?;
        let ver: i64 = r.try_get("version")?;
        if let Some(full) = get_version(db, &tid, ver).await? {
            let title = if full.title.is_empty() {
                full.template_id.clone()
            } else {
                resolve_text(&full.title, lang)
            };
            out.push(TemplateDiscoveryItem {
                template_id: full.template_id,
                version: full.version,
                kind: full.kind,
                visual: full.visual,
                title,
                slots: full.slots,
                options: full.options,
            });
        }
    }
    Ok(out)
}

pub async fn bind_card_visual(
    db: &Db,
    project: &str,
    report: &str,
    card_id: &str,
    binding: &CardVisualBinding,
) -> Result<(), ReportError> {
    let tpl = get_version(db, &binding.template, binding.version)
        .await?
        .ok_or_else(|| {
            ReportError::not_found(format!(
                "visual template '{} v{}'",
                binding.template, binding.version
            ))
        })?;
    if tpl.status != "published" {
        return Err(ReportError::Conflict(format!(
            "visual template {} v{} must be published before binding",
            binding.template, binding.version
        )));
    }
    for slot in &tpl.slots {
        let count = binding
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

    let mut tx = db.pool.begin().await?;
    sqlx::query(
        "INSERT INTO report_card_visuals(project_slug, report_slug, card_id, template_id, template_version)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT(project_slug, report_slug, card_id) DO UPDATE
         SET template_id = EXCLUDED.template_id, template_version = EXCLUDED.template_version",
    )
    .bind(project)
    .bind(report)
    .bind(card_id)
    .bind(&binding.template)
    .bind(binding.version)
    .execute(&mut *tx)
    .await?;

    sqlx::query(
        "DELETE FROM report_card_visual_fields WHERE project_slug = $1 AND report_slug = $2 AND card_id = $3",
    )
    .bind(project)
    .bind(report)
    .bind(card_id)
    .execute(&mut *tx)
    .await?;
    for (slot_name, fields) in &binding.mapping {
        for (pos, field_name) in fields.iter().enumerate() {
            sqlx::query(
                "INSERT INTO report_card_visual_fields(project_slug, report_slug, card_id, slot_name, position, field_name)
                 VALUES ($1, $2, $3, $4, $5, $6)",
            )
            .bind(project)
            .bind(report)
            .bind(card_id)
            .bind(slot_name)
            .bind(pos as i64)
            .bind(field_name)
            .execute(&mut *tx)
            .await?;
        }
    }

    sqlx::query(
        "DELETE FROM report_card_visual_options WHERE project_slug = $1 AND report_slug = $2 AND card_id = $3",
    )
    .bind(project)
    .bind(report)
    .bind(card_id)
    .execute(&mut *tx)
    .await?;
    for (opt_name, val) in &binding.options {
        sqlx::query(
            "INSERT INTO report_card_visual_options(project_slug, report_slug, card_id, option_name, value)
             VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(project)
        .bind(report)
        .bind(card_id)
        .bind(opt_name)
        .bind(val)
        .execute(&mut *tx)
        .await?;
    }

    tx.commit().await?;
    Ok(())
}

pub async fn get_card_visual(
    db: &Db,
    project: &str,
    report: &str,
    card_id: &str,
) -> Result<Option<CardVisualBinding>, ReportError> {
    let Some(row) = sqlx::query(
        "SELECT template_id, CAST(template_version AS BIGINT) AS template_version
         FROM report_card_visuals
         WHERE project_slug = $1 AND report_slug = $2 AND card_id = $3",
    )
    .bind(project)
    .bind(report)
    .bind(card_id)
    .fetch_optional(&db.pool)
    .await?
    else {
        return Ok(None);
    };

    let template: String = row.try_get("template_id")?;
    let version: i64 = row.try_get("template_version")?;

    let field_rows = sqlx::query(
        "SELECT slot_name, field_name FROM report_card_visual_fields
         WHERE project_slug = $1 AND report_slug = $2 AND card_id = $3
         ORDER BY slot_name, position",
    )
    .bind(project)
    .bind(report)
    .bind(card_id)
    .fetch_all(&db.pool)
    .await?;
    let mut mapping: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for fr in field_rows {
        let slot: String = fr.try_get("slot_name")?;
        let field: String = fr.try_get("field_name")?;
        mapping.entry(slot).or_default().push(field);
    }

    let opt_rows = sqlx::query(
        "SELECT option_name, value FROM report_card_visual_options
         WHERE project_slug = $1 AND report_slug = $2 AND card_id = $3
         ORDER BY option_name",
    )
    .bind(project)
    .bind(report)
    .bind(card_id)
    .fetch_all(&db.pool)
    .await?;
    let mut options = BTreeMap::new();
    for or in opt_rows {
        options.insert(or.try_get("option_name")?, or.try_get("value")?);
    }

    Ok(Some(CardVisualBinding {
        template,
        version,
        mapping,
        options,
    }))
}
