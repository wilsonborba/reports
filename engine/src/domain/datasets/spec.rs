use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use utoipa::ToSchema;

/// Localized text stored as `{"en": "...", "pt-BR": "...", "th": "..."}`.
pub type I18nText = HashMap<String, String>;

/// Provenance of the data behind a report or dataset.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum DataTier {
    Real,
    Hybrid,
    #[default]
    Sample,
}

impl DataTier {
    /// Aggregates contributing dataset tiers into a single report tier.
    /// Returns the common tier when all agree; returns Hybrid when mixed.
    pub fn aggregate(tiers: impl IntoIterator<Item = DataTier>) -> Self {
        let mut iter = tiers.into_iter();
        let first = match iter.next() {
            Some(t) => t,
            None => return DataTier::Sample,
        };
        for t in iter {
            if t != first {
                return DataTier::Hybrid;
            }
        }
        first
    }
}

/// Resolves a localized text for `lang`, falling back to English, then to any value.
pub fn resolve_text(text: &I18nText, lang: &str) -> String {
    let filled = |k: &str| text.get(k).filter(|v| !v.trim().is_empty());
    filled(lang)
        .or_else(|| {
            if lang.starts_with("pt") {
                filled("pt-BR").or_else(|| filled("pt"))
            } else {
                None
            }
        })
        .or_else(|| filled("en"))
        .or_else(|| text.values().find(|v| !v.trim().is_empty()))
        .cloned()
        .unwrap_or_default()
}

/// True when a title holds one name only: it does not join two names with
/// `&`, ` and ` or the Thai conjunction `และ`.
pub fn is_single_name(text: &str) -> bool {
    let lower = text.to_lowercase();
    !(lower.contains('&') || lower.contains(" and ") || text.contains("และ"))
}

/// Checks every language of a title. Returns the first title that joins two names.
pub fn first_double_name(text: &I18nText) -> Option<String> {
    let mut langs: Vec<&String> = text.keys().collect();
    langs.sort();
    langs
        .into_iter()
        .map(|l| &text[l])
        .find(|t| !is_single_name(t))
        .cloned()
}

/// Backend-only calculation definition of one dataset.
/// It is stored in `datasets.spec` and never sent to the client.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DatasetSpec {
    pub title: I18nText,
    #[serde(default)]
    pub description: I18nText,
    #[serde(default)]
    pub equation: Option<String>,
    /// Schema name of the received records in the same project. Optional when a calculator
    /// generates the rows.
    #[serde(default)]
    pub source: Option<String>,
    /// More schemas whose records are added to the source rows (same field names).
    #[serde(default)]
    pub union: Vec<String>,
    #[serde(default)]
    pub lookups: Vec<LookupSpec>,
    /// Time buckets added to every source row after the lookups (before `row_derived`).
    #[serde(default)]
    pub buckets: Vec<BucketSpec>,
    /// Row-level expressions evaluated on every source row after the lookups.
    #[serde(default)]
    pub row_derived: Vec<DerivedSpec>,
    #[serde(default, rename = "where")]
    pub where_: Vec<Condition>,
    /// Source or lookup fields that the client can filter.
    #[serde(default)]
    pub filters: Vec<FilterSpec>,
    #[serde(default)]
    pub stages: Vec<StageSpec>,
    /// Expressions evaluated on the final rows (after all stages).
    #[serde(default)]
    pub derived: Vec<DerivedSpec>,
    #[serde(default)]
    pub having: Vec<Condition>,
    #[serde(default)]
    pub calculator: Option<Value>,
    #[serde(default)]
    pub params: HashMap<String, f64>,
    #[serde(default)]
    pub refs: HashMap<String, RefSpec>,
    #[serde(default)]
    pub sort: Vec<SortSpec>,
    #[serde(default)]
    pub limit: Option<usize>,
    pub fields: Vec<FieldSpec>,
    #[serde(default)]
    pub value_labels: HashMap<String, HashMap<String, I18nText>>,
    /// Calculate this public dataset again right after new records arrive (high-traffic KPI).
    #[serde(default)]
    pub warm: bool,
}

/// Truncates a date or RFC 3339 time field to a bucket.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BucketSpec {
    /// Source field with a date (`YYYY-MM-DD`) or an RFC 3339 time.
    pub field: String,
    /// hour, day, week (ISO, starts Monday) or month
    pub unit: String,
    /// Name of the new field.
    pub name: String,
    /// Shift times to this UTC offset (minutes) before truncation. Without it the offset
    /// written in the value is kept.
    #[serde(default)]
    pub utc_offset_minutes: Option<i32>,
}

/// Trailing window over the rows of a stage, ordered by `order_by`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WindowSpec {
    pub name: String,
    /// avg, sum, min or max
    pub agg: String,
    pub field: String,
    /// Rows in the window, the current row included (1 to 366).
    pub size: usize,
    pub order_by: String,
    #[serde(default)]
    pub partition_by: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FilterSpec {
    pub field: String,
    pub label: I18nText,
    /// category, date, hour or number
    #[serde(rename = "type")]
    pub filter_type: String,
    /// `refs`: the filter applies only to the referenced datasets, not to the own rows
    /// (for datasets built from parameters and references).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scope: Option<String>,
}

impl FilterSpec {
    pub fn refs_only(&self) -> bool {
        self.scope.as_deref() == Some("refs")
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LookupSpec {
    pub collection: String,
    /// Fields of the source row.
    pub key: Vec<String>,
    /// Fields of the lookup row that must equal `key` (same order). Defaults to `key`.
    #[serde(default, rename = "match")]
    pub match_: Vec<String>,
    /// Fields copied from the lookup row. Empty copies every field.
    #[serde(default)]
    pub fields: Vec<String>,
    /// Optional prefix for the copied field names, for example `from_`.
    #[serde(default)]
    pub prefix: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DerivedSpec {
    pub name: String,
    #[serde(default)]
    pub expr: Option<String>,
    /// Name of a row field that holds the expression (one formula per row).
    #[serde(default)]
    pub expr_field: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Condition {
    pub field: String,
    /// eq, ne, in, not_in, between, gt, gte, lt, lte, ends_with, starts_with
    pub op: String,
    #[serde(default)]
    pub value: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct StageSpec {
    #[serde(default)]
    pub group_by: Vec<String>,
    #[serde(default)]
    pub measures: Vec<MeasureSpec>,
    #[serde(default)]
    pub derived: Vec<DerivedSpec>,
    /// Partition for `psum_`, `pmin_` and `pmax_` variables in `derived`.
    #[serde(default)]
    pub partition_by: Vec<String>,
    #[serde(default)]
    pub having: Vec<Condition>,
    /// Moving windows over the rows of this stage (after `derived`, before `having`).
    #[serde(default)]
    pub windows: Vec<WindowSpec>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MeasureSpec {
    pub name: String,
    /// sum, avg, min, max, count, count_distinct, argmax, argmin, top, top_share, first, sum_top
    pub agg: String,
    #[serde(default)]
    pub field: Option<String>,
    /// Composite key for count_distinct.
    #[serde(default)]
    pub fields: Vec<String>,
    /// Ordering field for argmax and argmin, weight field for top and top_share.
    #[serde(default)]
    pub by: Option<String>,
    /// Only rows that match these conditions enter the measure.
    #[serde(default, rename = "where")]
    pub where_: Vec<Condition>,
    /// Number of largest values for sum_top.
    #[serde(default)]
    pub n: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RefSpec {
    pub dataset: String,
    pub field: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SortSpec {
    pub field: String,
    #[serde(default)]
    pub desc: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FieldSpec {
    pub name: String,
    pub label: I18nText,
    /// string, integer, float, percent, date, datetime, hour, latitude, longitude
    #[serde(rename = "type")]
    pub field_type: String,
    /// dimension or measure
    #[serde(default = "default_role")]
    pub role: String,
    #[serde(default)]
    pub unit: Option<String>,
    #[serde(default)]
    pub decimals: Option<u32>,
}

fn default_role() -> String {
    "measure".to_string()
}

/// Client filter parameter parsed from `f.<field>=a,b`, `f.<field>.from=` and `f.<field>.to=`.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub enum FilterParam {
    In {
        field: String,
        values: Vec<String>,
    },
    Range {
        field: String,
        from: Option<String>,
        to: Option<String>,
    },
}

impl FilterParam {
    pub fn field(&self) -> &str {
        match self {
            FilterParam::In { field, .. } | FilterParam::Range { field, .. } => field,
        }
    }

    /// Parses query parameters. Keys without the `f.` prefix are ignored.
    pub fn parse_query(query: &HashMap<String, String>) -> Vec<FilterParam> {
        let mut ranges: HashMap<String, (Option<String>, Option<String>)> = HashMap::new();
        let mut out = Vec::new();
        let mut keys: Vec<&String> = query.keys().collect();
        keys.sort();
        for key in keys {
            let Some(rest) = key.strip_prefix("f.") else {
                continue;
            };
            let value = query[key].clone();
            if let Some(field) = rest.strip_suffix(".from") {
                ranges.entry(field.to_string()).or_default().0 = Some(value);
            } else if let Some(field) = rest.strip_suffix(".to") {
                ranges.entry(field.to_string()).or_default().1 = Some(value);
            } else {
                let values: Vec<String> = value
                    .split(',')
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .collect();
                if !values.is_empty() {
                    out.push(FilterParam::In {
                        field: rest.to_string(),
                        values,
                    });
                }
            }
        }
        let mut range_fields: Vec<_> = ranges.into_iter().collect();
        range_fields.sort_by(|a, b| a.0.cmp(&b.0));
        for (field, (from, to)) in range_fields {
            out.push(FilterParam::Range { field, from, to });
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolve_text_falls_back_to_english() {
        let t: I18nText = [("en".to_string(), "Tokens".to_string())].into();
        assert_eq!(resolve_text(&t, "th"), "Tokens");
        let all: I18nText = [
            ("en".to_string(), "Tokens".to_string()),
            ("pt-BR".to_string(), "Tokens por dia".to_string()),
            ("th".to_string(), "โทเค็น".to_string()),
        ]
        .into();
        assert_eq!(resolve_text(&all, "th"), "โทเค็น");
        assert_eq!(resolve_text(&all, "pt-BR"), "Tokens por dia");
    }

    #[test]
    fn single_name_rule() {
        assert!(is_single_name("Token Usage"));
        assert!(is_single_name("Latency"));
        assert!(!is_single_name("Tokens & Latency"));
        assert!(!is_single_name("Tokens and Latency"));
        assert!(!is_single_name("โทเค็นและเวลา"));
    }

    #[test]
    fn parses_filter_query() {
        let q: HashMap<String, String> = [
            ("f.provider".to_string(), "ollama, openai".to_string()),
            ("f.date.from".to_string(), "2026-09-26".to_string()),
            ("lang".to_string(), "th".to_string()),
        ]
        .into();
        let f = FilterParam::parse_query(&q);
        assert_eq!(
            f[0],
            FilterParam::In {
                field: "provider".into(),
                values: vec!["ollama".into(), "openai".into()]
            }
        );
        assert_eq!(
            f[1],
            FilterParam::Range {
                field: "date".into(),
                from: Some("2026-09-26".into()),
                to: None
            }
        );
    }

    #[test]
    fn aggregate_data_tier_rule() {
        // Empty defaults to sample
        assert_eq!(DataTier::aggregate(vec![]), DataTier::Sample);
        // All agree -> common tier
        assert_eq!(DataTier::aggregate(vec![DataTier::Real, DataTier::Real]), DataTier::Real);
        assert_eq!(DataTier::aggregate(vec![DataTier::Sample, DataTier::Sample]), DataTier::Sample);
        assert_eq!(DataTier::aggregate(vec![DataTier::Hybrid, DataTier::Hybrid]), DataTier::Hybrid);
        // Mixed -> Hybrid regardless of order
        assert_eq!(DataTier::aggregate(vec![DataTier::Real, DataTier::Sample]), DataTier::Hybrid);
        assert_eq!(DataTier::aggregate(vec![DataTier::Sample, DataTier::Real]), DataTier::Hybrid);
        assert_eq!(DataTier::aggregate(vec![DataTier::Real, DataTier::Hybrid]), DataTier::Hybrid);
    }
}
