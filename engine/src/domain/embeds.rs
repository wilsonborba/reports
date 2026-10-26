//! Individual public-card descriptors and small data-backed PNG previews.
use crate::{
    core::error::ReportError,
    domain::{
        auth::ViewerScope,
        datasets::{DatasetPage, DatasetService, FilterParam},
        reports,
    },
};
use serde::Serialize;
use std::collections::{BTreeMap, HashMap};
use utoipa::ToSchema;
#[derive(Serialize, ToSchema)]
pub struct EmbedDescriptor {
    pub title: String,
    pub source_url: String,
    pub embed_url: String,
    pub thumbnail_url: String,
    pub html: String,
    pub width: u32,
    pub height: u32,
}
pub fn item_urls(
    project: &str,
    report: &str,
    dataset: &str,
    query: &HashMap<String, String>,
) -> (String, String, String) {
    let query: BTreeMap<_, _> = query
        .iter()
        .filter(|(k, _)| k.starts_with("f.") || matches!(k.as_str(), "lang" | "visual" | "view"))
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect();
    let encoded = url::form_urlencoded::Serializer::new(String::new())
        .extend_pairs(query)
        .finish();
    let suffix = if encoded.is_empty() {
        String::new()
    } else {
        format!("?{encoded}")
    };
    let p = urlencoding::encode(project);
    let r = urlencoding::encode(report);
    let d = urlencoding::encode(dataset);
    (format!("https://reports.asodya.com/v1/menu/{p}/{r}/{d}{suffix}"),format!("https://reports.asodya.com/v1/embed/{p}/{r}/{d}{suffix}"),format!("https://api.asodya.com/apps/reports/v1/projects/{p}/showcase/{r}/cards/{d}/thumbnail.png{suffix}"))
}
pub async fn public_page(
    svc: &DatasetService,
    project: &str,
    report: &str,
    dataset: &str,
    query: &HashMap<String, String>,
    lang: &str,
) -> Result<DatasetPage, ReportError> {
    reports::dataset_page(
        svc,
        project,
        report,
        dataset,
        &FilterParam::parse_query(query),
        lang,
        0,
        8,
        &ViewerScope::guest(),
    )
    .await
}
pub async fn descriptor(
    svc: &DatasetService,
    project: &str,
    report: &str,
    dataset: &str,
    query: &HashMap<String, String>,
    lang: &str,
) -> Result<EmbedDescriptor, ReportError> {
    let page = public_page(svc, project, report, dataset, query, lang).await?;
    let (source_url, embed_url, thumbnail_url) = item_urls(project, report, dataset, query);
    let html=format!("<iframe src=\"{}\" title=\"{}\" width=\"100%\" height=\"480\" loading=\"lazy\" style=\"border:0\" referrerpolicy=\"strict-origin-when-cross-origin\"></iframe>",escape(&embed_url),escape(&page.descriptor.title));
    Ok(EmbedDescriptor {
        title: page.descriptor.title,
        source_url,
        embed_url,
        thumbnail_url,
        html,
        width: 800,
        height: 480,
    })
}
fn escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}
fn short(s: &str, n: usize) -> String {
    s.chars().take(n).collect()
}
pub fn preview_png(page: &DatasetPage, table: bool, line: bool) -> Result<Vec<u8>, ReportError> {
    let mut svg=format!("<svg xmlns='http://www.w3.org/2000/svg' width='800' height='450'><rect width='800' height='450' fill='#fafafa'/><rect x='24' y='24' width='752' height='402' rx='8' fill='white' stroke='#e4e4e7'/><text x='48' y='65' font-family='Ubuntu Sans' font-size='23' font-weight='bold' fill='#18181b'>{}</text>",escape(&short(&page.descriptor.title,60)));
    let fields = &page.descriptor.fields;
    if table {
        for (index, field) in fields.iter().take(3).enumerate() {
            let x = 48 + index * 235;
            svg+=&format!("<text x='{x}' y='107' font-family='Ubuntu Sans' font-size='15' font-weight='bold' fill='#7c3aed'>{}</text>",escape(&short(&field.label,24)));
        }
        for (row_index, row) in page.rows.iter().take(6).enumerate() {
            let y = 145 + row_index * 36;
            svg += &format!("<path d='M48 {} H750' stroke='#eeeeef'/>", y + 10);
            for (index, field) in fields.iter().take(3).enumerate() {
                let value = row
                    .get(&field.name)
                    .map(|v| {
                        v.as_str()
                            .map(str::to_string)
                            .unwrap_or_else(|| v.to_string())
                    })
                    .unwrap_or_default();
                svg+=&format!("<text x='{}' y='{y}' font-family='Ubuntu Sans' font-size='15' fill='#27272a'>{}</text>",48+index*235,escape(&short(&value,25)));
            }
        }
    } else {
        let numeric = fields.iter().find(|f| {
            page.rows
                .iter()
                .any(|r| r.get(&f.name).and_then(serde_json::Value::as_f64).is_some())
        });
        if let Some(field) = numeric {
            let values: Vec<f64> = page
                .rows
                .iter()
                .take(8)
                .map(|r| {
                    r.get(&field.name)
                        .and_then(serde_json::Value::as_f64)
                        .unwrap_or(0.0)
                })
                .collect();
            let max = values
                .iter()
                .copied()
                .fold(0.0_f64, |a, b| a.max(b.abs()))
                .max(1.0);
            let label = fields.iter().find(|f| f.name != field.name);
            let mut points = vec![];
            for (i, value) in values.iter().enumerate() {
                let x = 65 + i * 85;
                let height = ((*value).max(0.0) / max * 220.0).round() as i64;
                let y = 355 - height;
                points.push(format!("{},{}", x + 24, y));
                if !line {
                    svg+=&format!("<rect x='{x}' y='{y}' width='48' height='{height}' rx='3' fill='#8c52ff'/>");
                }
                svg+=&format!("<text x='{}' y='{}' text-anchor='middle' font-family='Ubuntu Sans' font-size='12' fill='#52525b'>{}</text>",x+24,(y-10).max(105),escape(&short(&value.to_string(),10)));
                if let Some(label) = label {
                    let v = page.rows[i]
                        .get(&label.name)
                        .map(|v| {
                            v.as_str()
                                .map(str::to_string)
                                .unwrap_or_else(|| v.to_string())
                        })
                        .unwrap_or_default();
                    svg+=&format!("<text x='{}' y='380' text-anchor='middle' font-family='Ubuntu Sans' font-size='11' fill='#52525b'>{}</text>",x+24,escape(&short(&v,12)));
                }
            }
            if line {
                svg += &format!(
                    "<polyline points='{}' fill='none' stroke='#7c3aed' stroke-width='4'/>",
                    points.join(" ")
                );
            }
        } else {
            svg+="<text x='48' y='180' font-family='Ubuntu Sans' font-size='20' fill='#71717a'>Open the report to explore this item.</text>";
        }
    }
    svg+=&format!("<text x='48' y='410' font-family='Ubuntu Sans' font-size='11' fill='#71717a'>ASODYA REPORTS · Preview · {} of {} rows</text></svg>",page.rows.len(),page.total_rows);
    let mut options = resvg::usvg::Options::default();
    options.fontdb_mut().load_font_data(
        include_bytes!("../../../ui/assets/fonts/UbuntuSans-Variable.ttf").to_vec(),
    );
    let tree = resvg::usvg::Tree::from_str(&svg, &options)
        .map_err(|_| ReportError::Internal("Could not render preview".into()))?;
    let mut pixmap = resvg::tiny_skia::Pixmap::new(800, 450)
        .ok_or_else(|| ReportError::Internal("Could not allocate preview".into()))?;
    resvg::render(
        &tree,
        resvg::tiny_skia::Transform::identity(),
        &mut pixmap.as_mut(),
    );
    pixmap
        .encode_png()
        .map_err(|_| ReportError::Internal("Could not encode preview".into()))
}
