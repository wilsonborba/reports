//! Normalized catalog text, theme colors and ordered report metadata.
use super::{catalog::ReportMetadata, sql::Db};
use crate::{
    core::error::ReportError,
    domain::{datasets::spec::I18nText, themes::ProjectTheme},
};
use serde_json::{Map, Value};
use sqlx::{Any, AnyConnection, Row, Transaction};

pub async fn texts(
    db: &Db,
    project: &str,
    report: Option<&str>,
    kind: &str,
) -> Result<I18nText, ReportError> {
    let rows = match report {
        Some(r) => {
            sqlx::query("SELECT lang,text FROM report_texts WHERE project_slug=$1 AND report_slug=$2 AND text_key=$3")
                .bind(project)
                .bind(r)
                .bind(kind)
                .fetch_all(&db.pool)
                .await?
        }
        None => {
            sqlx::query("SELECT lang,text FROM project_texts WHERE project_slug=$1 AND text_key=$2")
                .bind(project)
                .bind(kind)
                .fetch_all(&db.pool)
                .await?
        }
    };
    rows.iter()
        .map(|r| Ok((r.try_get("lang")?, r.try_get("text")?)))
        .collect()
}
pub async fn write_texts(
    tx: &mut Transaction<'_, Any>,
    project: &str,
    report: Option<&str>,
    kind: &str,
    text: &I18nText,
) -> Result<(), ReportError> {
    match report {
        Some(r) => {
            sqlx::query(
                "DELETE FROM report_texts WHERE project_slug=$1 AND report_slug=$2 AND text_key=$3",
            )
            .bind(project)
            .bind(r)
            .bind(kind)
            .execute(&mut **tx)
            .await?;
            for (lang, value) in text {
                sqlx::query(
                    "INSERT INTO report_texts(project_slug,report_slug,text_key,lang,text) VALUES($1,$2,$3,$4,$5)",
                )
                .bind(project)
                .bind(r)
                .bind(kind)
                .bind(lang)
                .bind(value)
                .execute(&mut **tx)
                .await?;
            }
        }
        None => {
            sqlx::query("DELETE FROM project_texts WHERE project_slug=$1 AND text_key=$2")
                .bind(project)
                .bind(kind)
                .execute(&mut **tx)
                .await?;
            for (lang, value) in text {
                sqlx::query("INSERT INTO project_texts(project_slug,text_key,lang,text) VALUES($1,$2,$3,$4)")
                    .bind(project)
                    .bind(kind)
                    .bind(lang)
                    .bind(value)
                    .execute(&mut **tx)
                    .await?;
            }
        }
    }
    Ok(())
}
pub async fn theme(db: &Db, project: &str) -> Result<ProjectTheme, ReportError> {
    let modes =
        sqlx::query("SELECT mode FROM project_theme_modes WHERE project_slug=$1 ORDER BY mode")
            .bind(project)
            .fetch_all(&db.pool)
            .await?;
    let rows=sqlx::query("SELECT mode,token,CAST(position AS BIGINT) AS position,color FROM project_theme_colors WHERE project_slug=$1 ORDER BY position").bind(project).fetch_all(&db.pool).await?;
    let mut theme = Map::new();
    for mode in modes {
        let mode: String = mode.try_get("mode")?;
        let mut tokens = Map::new();
        let mut series = Vec::new();
        for row in &rows {
            if row.try_get::<String, _>("mode")? != mode {
                continue;
            }
            let token: String = row.try_get("token")?;
            let color: String = row.try_get("color")?;
            if token == "series" {
                series.push(Value::String(color));
            } else {
                tokens.insert(token, Value::String(color));
            }
        }
        tokens.insert("series".into(), Value::Array(series));
        theme.insert(mode, Value::Object(tokens));
    }
    serde_json::from_value(Value::Object(theme)).map_err(|e| ReportError::Database(e.to_string()))
}
pub async fn write_theme(
    tx: &mut Transaction<'_, Any>,
    project: &str,
    theme: &ProjectTheme,
) -> Result<(), ReportError> {
    sqlx::query("DELETE FROM project_theme_modes WHERE project_slug=$1")
        .bind(project)
        .execute(&mut **tx)
        .await?;
    let v = serde_json::to_value(theme).map_err(|e| ReportError::Internal(e.to_string()))?;
    for mode in ["light", "dark"] {
        let Some(tokens) = v[mode].as_object() else {
            continue;
        };
        sqlx::query("INSERT INTO project_theme_modes(project_slug,mode) VALUES($1,$2)")
            .bind(project)
            .bind(mode)
            .execute(&mut **tx)
            .await?;
        for (token, v) in tokens {
            let colors = if let Some(a) = v.as_array() {
                a.clone()
            } else {
                vec![v.clone()]
            };
            for (i, color) in colors.iter().enumerate() {
                sqlx::query(
                    "INSERT INTO project_theme_colors(project_slug,mode,token,position,color) VALUES($1,$2,$3,$4,$5)",
                )
                .bind(project)
                .bind(mode)
                .bind(token)
                .bind(i as i64)
                .bind(color.as_str().ok_or_else(|| ReportError::Internal("theme color must be text".into()))?)
                .execute(&mut **tx)
                .await?;
            }
        }
    }
    Ok(())
}
pub async fn metadata(
    db: &Db,
    project: &str,
    report: &str,
    sort_order: i64,
    collection: Option<String>,
    field: Option<String>,
) -> Result<ReportMetadata, ReportError> {
    let rows = sqlx::query(
        "SELECT kind,value FROM report_ordered_items WHERE project_slug=$1 AND report_slug=$2 ORDER BY position",
    )
    .bind(project)
    .bind(report)
    .fetch_all(&db.pool)
    .await?;
    let mut m = ReportMetadata {
        sort_order,
        period_source: collection
            .zip(field)
            .map(|(collection, field)| super::catalog::PeriodSource { collection, field }),
        ..Default::default()
    };
    for r in rows {
        let kind: String = r.try_get("kind")?;
        let value: String = r.try_get("value")?;
        if kind == "tag" {
            m.tags.push(value)
        } else {
            m.card_order.push(value)
        }
    }
    Ok(m)
}
pub async fn write_items(
    conn: &mut AnyConnection,
    project: &str,
    report: &str,
    m: &ReportMetadata,
) -> Result<(), ReportError> {
    sqlx::query("DELETE FROM report_ordered_items WHERE project_slug=$1 AND report_slug=$2")
        .bind(project)
        .bind(report)
        .execute(&mut *conn)
        .await?;
    for (kind, items) in [("tag", &m.tags), ("card", &m.card_order)] {
        for (i, v) in items.iter().enumerate() {
            sqlx::query(
                "INSERT INTO report_ordered_items(project_slug,report_slug,kind,position,value) VALUES($1,$2,$3,$4,$5)",
            )
            .bind(project)
            .bind(report)
            .bind(kind)
            .bind(i as i64)
            .bind(v)
            .execute(&mut *conn)
            .await?;
        }
    }
    Ok(())
}
