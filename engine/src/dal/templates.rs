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

/// Catalog items 1 to 23 (Comparison of categories, Part 5 full catalog).
pub fn comparison_catalog_templates() -> Vec<VisualTemplateVersion> {
    let specs: &[(&str, &str, &str, &str, i64, i64)] = &[
        (
            "vertical_bar",
            "Vertical Bar",
            "Barras Verticais",
            "แผนภูมิแท่งแนวตั้ง",
            1,
            1,
        ),
        (
            "horizontal_bar",
            "Horizontal Bar",
            "Barras Horizontais",
            "แผนภูมิแท่งแนวนอน",
            1,
            1,
        ),
        (
            "ranking_bar",
            "Ranking Bar",
            "Ranking de Barras",
            "แผนภูมิแท่งจัดอันดับ",
            1,
            1,
        ),
        (
            "grouped_bar",
            "Grouped Bar",
            "Barras Agrupadas",
            "แผนภูมิแท่งจัดกลุ่ม",
            1,
            4,
        ),
        (
            "stacked_bar",
            "Stacked Bar",
            "Barras Empilhadas",
            "แผนภูมิแท่งซ้อน",
            1,
            4,
        ),
        (
            "stacked_bar_100",
            "100% Stacked Bar",
            "Barras Empilhadas 100%",
            "แผนภูมิแท่งซ้อน 100%",
            2,
            4,
        ),
        (
            "diverging_bar",
            "Diverging Bar",
            "Barras Divergentes",
            "แผนภูมิแท่งแยกทิศทาง",
            1,
            1,
        ),
        (
            "floating_bar",
            "Floating Bar",
            "Barras Flutuantes",
            "แผนภูมิแท่งช่วงค่า",
            2,
            2,
        ),
        ("lollipop", "Lollipop", "Pirulito", "แผนภูมิโลลิป็อป", 1, 1),
        (
            "dot_plot",
            "Dot Plot (Cleveland)",
            "Grafico de Pontos",
            "แผนภูมิจุด",
            1,
            1,
        ),
        ("dumbbell", "Dumbbell", "Halteres", "แผนภูมิดัมเบล", 2, 2),
        (
            "slope",
            "Slope Chart",
            "Grafico de Inclinacao",
            "แผนภูมิความชัน",
            2,
            2,
        ),
        ("bullet", "Bullet Chart", "Grafico Bala", "แผนภูมิบุลเล็ต", 2, 2),
        (
            "utilization_bar",
            "Utilization Bar",
            "Barra de Utilizacao",
            "แถบแสดงการใช้งาน",
            1,
            1,
        ),
        ("pictogram", "Pictogram", "Pictograma", "แผนภูมิรูปภาพ", 1, 1),
        (
            "radial_bar",
            "Radial Bar",
            "Barra Radial",
            "แผนภูมิแท่งรัศมี",
            1,
            1,
        ),
        (
            "circular_bar",
            "Circular Bar Plot",
            "Barras Circulares",
            "แผนภูมิแท่งวงกลม",
            1,
            1,
        ),
        ("radar", "Radar / Spider", "Radar", "แผนภูมิเรดาร์", 2, 6),
        (
            "parallel_coordinates",
            "Parallel Coordinates",
            "Coordenadas Paralelas",
            "พิกัดขนาน",
            2,
            6,
        ),
        (
            "marimekko",
            "Marimekko",
            "Marimekko",
            "แผนภูมิมาริเม็กโกะ",
            2,
            2,
        ),
        ("waterfall", "Waterfall", "Cascata", "แผนภูมิน้ำตก", 1, 1),
        ("pareto", "Pareto", "Pareto", "แผนภูมิพาเรโต", 1, 1),
        (
            "small_multiples",
            "Small Multiples",
            "Pequenos Multiplos",
            "แผนภูมิย่อยหลายชุด",
            1,
            4,
        ),
    ];

    specs
        .iter()
        .map(|&(id, en, pt, th, min_m, max_m)| {
            let mut title = I18nText::default();
            title.insert("en".to_string(), en.to_string());
            title.insert("pt-BR".to_string(), pt.to_string());
            title.insert("th".to_string(), th.to_string());
            let max_dims = if id == "stacked_bar" { 2 } else { 1 };
            VisualTemplateVersion {
                template_id: id.to_string(),
                version: 1,
                kind: "chart".to_string(),
                status: "draft".to_string(),
                visual: id.to_string(),
                title,
                slots: vec![
                    TemplateSlot {
                        slot_name: "category".to_string(),
                        role: "dimension".to_string(),
                        is_required: true,
                        min_count: 1,
                        max_count: max_dims,
                        accepted_types: vec!["string".to_string()],
                    },
                    TemplateSlot {
                        slot_name: "value".to_string(),
                        role: "measure".to_string(),
                        is_required: true,
                        min_count: min_m,
                        max_count: max_m,
                        accepted_types: vec![
                            "integer".to_string(),
                            "float".to_string(),
                            "percent".to_string(),
                        ],
                    },
                ],
                options: vec![TemplateOption {
                    option_name: "sort".to_string(),
                    value_type: "enum".to_string(),
                    default_value: if id == "ranking_bar" || id == "pareto" {
                        "desc".to_string()
                    } else {
                        "none".to_string()
                    },
                    allowed_values: vec!["none".to_string(), "asc".to_string(), "desc".to_string()],
                }],
                published_at: None,
            }
        })
        .collect()
}

/// Idempotently saves and publishes all 23 comparison catalog templates.
pub async fn seed_comparison_templates(db: &Db) -> Result<(), ReportError> {
    for tpl in comparison_catalog_templates() {
        if get_version(db, &tpl.template_id, tpl.version)
            .await?
            .is_none()
        {
            save_draft(db, &tpl).await?;
            publish(db, &tpl.template_id, tpl.version).await?;
        }
    }
    Ok(())
}

/// Catalog items 24 to 43 (Change over time, Part 5 full catalog).
pub fn time_catalog_templates() -> Vec<VisualTemplateVersion> {
    let specs: &[(&str, &str, &str, &str, i64, i64)] = &[
        ("line", "Line Chart", "Grafico de Linha", "แผนภูมิเส้น", 1, 4),
        (
            "step_line",
            "Step Line",
            "Linha em Degraus",
            "แผนภูมิเส้นขั้นบันได",
            1,
            4,
        ),
        ("area", "Area Chart", "Grafico de Area", "แผนภูมิพื้นที่", 1, 4),
        (
            "stacked_area",
            "Stacked Area",
            "Area Empilhada",
            "แผนภูมิพื้นที่ซ้อน",
            2,
            4,
        ),
        (
            "stacked_area_100",
            "100% Stacked Area",
            "Area Empilhada 100%",
            "แผนภูมิพื้นที่ซ้อน 100%",
            2,
            4,
        ),
        (
            "streamgraph",
            "Streamgraph",
            "Streamgraph",
            "สตรีมกราฟ",
            2,
            4,
        ),
        ("sparkline", "Sparkline", "Minigrafico", "สปาร์กไลน์", 1, 1),
        (
            "bump_chart",
            "Bump Chart",
            "Grafico de Ranking Temporal",
            "แผนภูมิอันดับตามเวลา",
            1,
            4,
        ),
        (
            "candlestick",
            "Candlestick / OHLC",
            "Candlestick",
            "แผนภูมิแท่งเทียน",
            2,
            4,
        ),
        (
            "range_band",
            "Range Band",
            "Faixa de Intervalo",
            "แถบช่วงความเชื่อมั่น",
            2,
            2,
        ),
        (
            "combo",
            "Combo Bar + Line",
            "Combinado Barras e Linha",
            "แผนภูมิผสมแท่งและเส้น",
            2,
            2,
        ),
        (
            "annotated_line",
            "Annotated Line",
            "Linha Anotada",
            "แผนภูมิเส้นพร้อมคำอธิบาย",
            1,
            4,
        ),
        ("timeline", "Timeline", "Linha do Tempo", "ไทม์ไลน์", 1, 2),
        (
            "gantt",
            "Gantt Chart",
            "Grafico de Gantt",
            "แผนภูมิแกนต์",
            2,
            2,
        ),
        (
            "calendar_heatmap",
            "Calendar Heatmap",
            "Mapa de Calor de Calendario",
            "แผนที่ความร้อนปฏิทิน",
            1,
            1,
        ),
        (
            "horizon",
            "Horizon Chart",
            "Grafico de Horizonte",
            "แผนภูมิฮอไรซัน",
            1,
            2,
        ),
        (
            "control_chart",
            "Control Chart (SPC)",
            "Carta de Controle",
            "แผนภูมิควบคุม",
            1,
            1,
        ),
        (
            "burndown",
            "Burndown / Burnup",
            "Burndown",
            "แผนภูมิเบิร์นดาวน์",
            1,
            2,
        ),
        (
            "cycle_plot",
            "Cycle Plot",
            "Grafico de Ciclo",
            "แผนภูมิวงรอบเวลา",
            1,
            2,
        ),
        (
            "curve",
            "Continuous Curve",
            "Curva Continua",
            "เส้นโค้งต่อเนื่อง",
            1,
            2,
        ),
    ];

    specs
        .iter()
        .map(|&(id, en, pt, th, min_m, max_m)| {
            let mut title = I18nText::default();
            title.insert("en".to_string(), en.to_string());
            title.insert("pt-BR".to_string(), pt.to_string());
            title.insert("th".to_string(), th.to_string());
            VisualTemplateVersion {
                template_id: id.to_string(),
                version: 1,
                kind: "chart".to_string(),
                status: "draft".to_string(),
                visual: id.to_string(),
                title,
                slots: vec![
                    TemplateSlot {
                        slot_name: "time".to_string(),
                        role: "dimension".to_string(),
                        is_required: true,
                        min_count: 1,
                        max_count: 1,
                        accepted_types: vec![
                            "date".to_string(),
                            "datetime".to_string(),
                            "integer".to_string(),
                            "float".to_string(),
                        ],
                    },
                    TemplateSlot {
                        slot_name: "value".to_string(),
                        role: "measure".to_string(),
                        is_required: true,
                        min_count: min_m,
                        max_count: max_m,
                        accepted_types: vec![
                            "integer".to_string(),
                            "float".to_string(),
                            "percent".to_string(),
                        ],
                    },
                ],
                options: vec![],
                published_at: None,
            }
        })
        .collect()
}

/// Idempotently saves and publishes all 20 change-over-time catalog templates.
pub async fn seed_time_templates(db: &Db) -> Result<(), ReportError> {
    for tpl in time_catalog_templates() {
        if get_version(db, &tpl.template_id, tpl.version)
            .await?
            .is_none()
        {
            save_draft(db, &tpl).await?;
            publish(db, &tpl.template_id, tpl.version).await?;
        }
    }
    Ok(())
}

/// Catalog templates for part-of-a-whole visuals (catalog items 44 to 54).
pub fn part_whole_catalog_templates() -> Vec<VisualTemplateVersion> {
    let specs: &[(&str, &str, &str, &str, i64, i64, i64, i64)] = &[
        (
            "donut",
            "Donut Chart",
            "Grafico de Rosca",
            "แผนภูมิโดนัท",
            1,
            1,
            1,
            1,
        ),
        (
            "pie",
            "Pie Chart",
            "Grafico de Pizza",
            "แผนภูมิวงกลม",
            1,
            1,
            1,
            1,
        ),
        ("gauge", "Gauge", "Medidor Circular", "มาตรวัด", 0, 1, 1, 2),
        (
            "meter",
            "Meter",
            "Barra de Progresso",
            "แถบวัดระดับ",
            0,
            1,
            1,
            2,
        ),
        (
            "treemap",
            "Treemap",
            "Mapa de Arvore",
            "แผนภูมิสี่เหลี่ยมซ้อน",
            1,
            3,
            1,
            1,
        ),
        (
            "sunburst",
            "Sunburst",
            "Explosao Solar",
            "แผนภูมิรัศมีซ้อน",
            1,
            3,
            1,
            1,
        ),
        (
            "icicle",
            "Icicle Chart",
            "Grafico de Cascata Hierarquica",
            "แผนภูมิแท่งลำดับชั้น",
            1,
            3,
            1,
            1,
        ),
        (
            "circle_packing",
            "Circle Packing",
            "Empacotamento de Circulos",
            "แผนภูมิวงกลมซ้อน",
            1,
            3,
            1,
            1,
        ),
        (
            "waffle",
            "Waffle Chart",
            "Grafico de Waffle",
            "แผนภูมิวัฟเฟิล",
            1,
            1,
            1,
            1,
        ),
        (
            "nightingale_rose",
            "Nightingale Rose",
            "Rosa de Nightingale",
            "แผนภูมิกลีบกุหลาบ",
            1,
            1,
            1,
            1,
        ),
        (
            "funnel",
            "Funnel Chart",
            "Grafico de Funil",
            "แผนภูมิกรวย",
            1,
            1,
            1,
            1,
        ),
    ];

    specs
        .iter()
        .map(|&(id, en, pt, th, min_d, max_d, min_m, max_m)| {
            let mut title = I18nText::default();
            title.insert("en".to_string(), en.to_string());
            title.insert("pt-BR".to_string(), pt.to_string());
            title.insert("th".to_string(), th.to_string());
            let mut slots = vec![
                TemplateSlot {
                    slot_name: "category".to_string(),
                    role: "dimension".to_string(),
                    is_required: min_d > 0,
                    min_count: min_d,
                    max_count: max_d,
                    accepted_types: vec![
                        "string".to_string(),
                        "enum".to_string(),
                        "boolean".to_string(),
                    ],
                },
                TemplateSlot {
                    slot_name: "value".to_string(),
                    role: "measure".to_string(),
                    is_required: true,
                    min_count: min_m,
                    max_count: max_m,
                    accepted_types: vec![
                        "integer".to_string(),
                        "float".to_string(),
                        "percent".to_string(),
                    ],
                },
            ];
            if matches!(id, "treemap" | "sunburst" | "icicle" | "circle_packing") {
                slots.insert(
                    0,
                    TemplateSlot {
                        slot_name: "parent".to_string(),
                        role: "dimension".to_string(),
                        is_required: false,
                        min_count: 0,
                        max_count: 1,
                        accepted_types: vec!["string".to_string(), "enum".to_string()],
                    },
                );
            }
            VisualTemplateVersion {
                template_id: id.to_string(),
                version: 1,
                kind: "chart".to_string(),
                status: "draft".to_string(),
                visual: id.to_string(),
                title,
                slots,
                options: vec![],
                published_at: None,
            }
        })
        .collect()
}

/// Idempotently saves and publishes all 11 part-of-a-whole catalog templates.
pub async fn seed_part_whole_templates(db: &Db) -> Result<(), ReportError> {
    for tpl in part_whole_catalog_templates() {
        if get_version(db, &tpl.template_id, tpl.version)
            .await?
            .is_none()
        {
            save_draft(db, &tpl).await?;
            publish(db, &tpl.template_id, tpl.version).await?;
        }
    }
    Ok(())
}

type CatalogSpec = (
    &'static str,
    &'static str,
    &'static str,
    &'static str,
    i64,
    i64,
    i64,
    i64,
);

/// Catalog templates for distribution visuals (catalog items 55 to 64).
pub fn distribution_catalog_templates() -> Vec<VisualTemplateVersion> {
    let specs: &[CatalogSpec] = &[
        (
            "histogram",
            "Histogram",
            "Histograma",
            "ฮิสโทแกรม",
            0,
            1,
            1,
            1,
        ),
        (
            "box_plot",
            "Box Plot",
            "Grafico de Caixa",
            "แผนภูมิกล่อง",
            1,
            1,
            1,
            1,
        ),
        (
            "violin",
            "Violin Plot",
            "Grafico de Violino",
            "แผนภูมิไวโอลิน",
            1,
            1,
            1,
            1,
        ),
        (
            "density",
            "Density Plot",
            "Grafico de Densidade",
            "แผนภูมิความหนาแน่น",
            0,
            1,
            1,
            1,
        ),
        (
            "ridgeline",
            "Ridgeline Plot",
            "Grafico de Cristas",
            "แผนภูมิสันเขา",
            1,
            1,
            1,
            1,
        ),
        (
            "strip",
            "Strip Plot",
            "Grafico de Pontos em Faixa",
            "แผนภูมิจุดตามกลุ่ม",
            1,
            1,
            1,
            1,
        ),
        (
            "ecdf",
            "ECDF Plot",
            "Distribuicao Cumulativa Empirica",
            "ฟังก์ชันแจกแจงสะสมเชิงประจักษ์",
            0,
            1,
            1,
            1,
        ),
        (
            "qq_plot",
            "Q-Q Plot",
            "Grafico Q-Q",
            "แผนภูมิควอนไทล์",
            0,
            1,
            1,
            1,
        ),
        (
            "population_pyramid",
            "Population Pyramid",
            "Piramide Etaria",
            "พีระมิดประชากร",
            1,
            1,
            1,
            2,
        ),
        (
            "raincloud",
            "Raincloud Plot",
            "Grafico Nuvem de Chuva",
            "แผนภูมิเมฆฝน",
            1,
            1,
            1,
            1,
        ),
    ];

    specs
        .iter()
        .map(|&(id, en, pt, th, min_d, max_d, min_m, max_m)| {
            let mut title = I18nText::default();
            title.insert("en".to_string(), en.to_string());
            title.insert("pt-BR".to_string(), pt.to_string());
            title.insert("th".to_string(), th.to_string());
            VisualTemplateVersion {
                template_id: id.to_string(),
                version: 1,
                kind: "chart".to_string(),
                status: "draft".to_string(),
                visual: id.to_string(),
                title,
                slots: vec![
                    TemplateSlot {
                        slot_name: "category".to_string(),
                        role: "dimension".to_string(),
                        is_required: min_d > 0,
                        min_count: min_d,
                        max_count: max_d,
                        accepted_types: vec![
                            "string".to_string(),
                            "enum".to_string(),
                            "integer".to_string(),
                            "float".to_string(),
                        ],
                    },
                    TemplateSlot {
                        slot_name: "value".to_string(),
                        role: "measure".to_string(),
                        is_required: true,
                        min_count: min_m,
                        max_count: max_m,
                        accepted_types: vec![
                            "integer".to_string(),
                            "float".to_string(),
                            "percent".to_string(),
                        ],
                    },
                ],
                options: vec![],
                published_at: None,
            }
        })
        .collect()
}

/// Idempotently saves and publishes all 10 distribution catalog templates.
pub async fn seed_distribution_templates(db: &Db) -> Result<(), ReportError> {
    for tpl in distribution_catalog_templates() {
        if get_version(db, &tpl.template_id, tpl.version)
            .await?
            .is_none()
        {
            save_draft(db, &tpl).await?;
            publish(db, &tpl.template_id, tpl.version).await?;
        }
    }
    Ok(())
}
