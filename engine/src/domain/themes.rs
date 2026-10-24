//! Project theme tokens (colors) and their checks. Writers send them through the infra
//! API, so an admin can change colors without a code change.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

/// Number of chart series colors (categorical slots in fixed order).
pub const SERIES_COUNT: usize = 8;

/// Colors of one project in one mode (light or dark). Every value is `#RRGGBB`.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
pub struct ThemeTokens {
    pub canvas: String,
    pub surface: String,
    pub surface_alt: String,
    pub border: String,
    pub text_primary: String,
    pub text_muted: String,
    pub accent: String,
    pub on_accent: String,
    pub positive: String,
    pub warning: String,
    pub negative: String,
    pub info: String,
    pub caution: String,
    /// Chart series colors, slot 1 to 8, used in this order.
    pub series: Vec<String>,
    /// Gray for the folded "Other" category.
    pub other: String,
}

/// Light and dark tokens of a project, as the catalog API sends them.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, ToSchema)]
pub struct ProjectTheme {
    pub light: Option<ThemeTokens>,
    pub dark: Option<ThemeTokens>,
}

/// One row of `project_themes`.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
pub struct ThemeRecord {
    pub project: String,
    /// `light` or `dark`.
    pub mode: String,
    pub tokens: ThemeTokens,
    #[serde(default)]
    pub updated_at: String,
}

fn rgb(hex: &str) -> Option<(f64, f64, f64)> {
    let h = hex.strip_prefix('#')?;
    if h.len() != 6 || !h.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    let v = |i: usize| {
        u8::from_str_radix(&h[i..i + 2], 16)
            .ok()
            .map(|x| x as f64 / 255.0)
    };
    Some((v(0)?, v(2)?, v(4)?))
}

fn luminance(hex: &str) -> Option<f64> {
    let (r, g, b) = rgb(hex)?;
    let f = |c: f64| {
        if c <= 0.03928 {
            c / 12.92
        } else {
            ((c + 0.055) / 1.055).powf(2.4)
        }
    };
    Some(0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b))
}

/// WCAG contrast ratio of two colors (1 to 21). None when a color is not `#RRGGBB`.
pub fn contrast(a: &str, b: &str) -> Option<f64> {
    let (x, y) = (luminance(a)?, luminance(b)?);
    let (hi, lo) = if x > y { (x, y) } else { (y, x) };
    Some((hi + 0.05) / (lo + 0.05))
}

/// Result of the theme checks. Errors stop the write; warnings are returned but accepted.
#[derive(Debug, Default)]
pub struct ThemeCheck {
    pub errors: Vec<String>,
    pub warnings: Vec<String>,
}

/// Canonical Asodya theme used when a catalog project has not stored its own tokens.
pub fn asodya_theme(project: &str) -> ProjectTheme {
    let (accent, on_accent, series) = match project {
        "certifications" => (
            "#FFFFFF",
            "#111111",
            vec![
                "#FFFFFF", "#D1D5DB", "#9CA3AF", "#6B7280", "#4B5563", "#374151", "#1F2937",
                "#111111",
            ],
        ),
        "cortex" => (
            "#F5F5F7",
            "#141416",
            vec![
                "#F5F5F7", "#D1D5DB", "#9CA3AF", "#6B7280", "#4B5563", "#374151", "#1F2937",
                "#111111",
            ],
        ),
        "autodroid" | "fsm" => (
            "#0F766E",
            "#FFFFFF",
            vec![
                "#14B8A6", "#0F766E", "#155E75", "#38BDF8", "#67E8F9", "#A5F3FC", "#0E7490",
                "#164E63",
            ],
        ),
        _ => (
            "#8C52FF",
            "#FFFFFF",
            vec![
                "#8C52FF", "#6EFF00", "#A78BFA", "#C4B5FD", "#7C3AED", "#22C55E", "#14B8A6",
                "#38BDF8",
            ],
        ),
    };
    let dark = ThemeTokens {
        canvas: "#0B0C10".into(),
        surface: "#12151E".into(),
        surface_alt: "#1A1E2B".into(),
        border: "#272D3D".into(),
        text_primary: "#F5F5F7".into(),
        text_muted: "#B6BBC8".into(),
        accent: accent.into(),
        on_accent: on_accent.into(),
        positive: "#6EFF00".into(),
        warning: "#F9DF4E".into(),
        negative: "#FF6B6B".into(),
        info: "#38BDF8".into(),
        caution: "#FB923C".into(),
        series: series.into_iter().map(String::from).collect(),
        other: "#64748B".into(),
    };
    ProjectTheme {
        light: Some(dark.clone()),
        dark: Some(dark),
    }
}

/// Checks the theme. Text contrast is a hard rule; accent contrast on the card is a warning,
/// because brand colors such as yellow fills carry dark text and stay readable.
pub fn validate_theme(t: &ThemeRecord) -> ThemeCheck {
    let mut errors = Vec::new();
    if t.mode != "light" && t.mode != "dark" {
        errors.push(format!("mode '{}': use light or dark", t.mode));
    }
    let k = &t.tokens;
    let named = [
        ("canvas", &k.canvas),
        ("surface", &k.surface),
        ("surface_alt", &k.surface_alt),
        ("border", &k.border),
        ("text_primary", &k.text_primary),
        ("text_muted", &k.text_muted),
        ("accent", &k.accent),
        ("on_accent", &k.on_accent),
        ("positive", &k.positive),
        ("warning", &k.warning),
        ("negative", &k.negative),
        ("info", &k.info),
        ("caution", &k.caution),
        ("other", &k.other),
    ];
    for (name, value) in named {
        if rgb(value).is_none() {
            errors.push(format!("{name} '{value}': use #RRGGBB"));
        }
    }
    if k.series.len() != SERIES_COUNT {
        errors.push(format!(
            "series: exactly {SERIES_COUNT} colors, got {}",
            k.series.len()
        ));
    }
    for (i, c) in k.series.iter().enumerate() {
        if rgb(c).is_none() {
            errors.push(format!("series[{i}] '{c}': use #RRGGBB"));
        }
    }
    let low = |a: &str, b: &str, min: f64| contrast(a, b).filter(|r| *r < min);
    for (name, a, b) in [
        ("text_primary on surface", &k.text_primary, &k.surface),
        ("text_primary on canvas", &k.text_primary, &k.canvas),
        ("on_accent on accent", &k.on_accent, &k.accent),
    ] {
        if let Some(r) = low(a, b, 4.5) {
            errors.push(format!("{name}: contrast {r:.2}:1, needs 4.5:1"));
        }
    }
    let mut warnings = Vec::new();
    if let Some(r) = low(&k.accent, &k.surface, 3.0) {
        warnings.push(format!("accent on surface: contrast {r:.2}:1 is below 3:1; use the accent as a fill with on_accent text, not as thin lines"));
    }
    if let Some(r) = low(&k.text_muted, &k.surface, 3.0) {
        warnings.push(format!(
            "text_muted on surface: contrast {r:.2}:1 is below 3:1"
        ));
    }
    ThemeCheck { errors, warnings }
}

#[cfg(test)]
mod tests {
    use super::*;

    pub(super) fn tokens() -> ThemeTokens {
        ThemeTokens {
            canvas: "#FFFFFF".into(),
            surface: "#F7F7F7".into(),
            surface_alt: "#EDEDED".into(),
            border: "#DCDCDC".into(),
            text_primary: "#111111".into(),
            text_muted: "#616161".into(),
            accent: "#111111".into(),
            on_accent: "#FFFFFF".into(),
            positive: "#16A34A".into(),
            warning: "#EAB308".into(),
            negative: "#DC2626".into(),
            info: "#2563EB".into(),
            caution: "#EA580C".into(),
            series: [
                "#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6",
                "#e34948",
            ]
            .map(String::from)
            .to_vec(),
            other: "#A8A8A8".into(),
        }
    }

    #[test]
    fn contrast_matches_wcag() {
        assert!((contrast("#000000", "#FFFFFF").unwrap() - 21.0).abs() < 0.01);
        assert!((contrast("#777777", "#FFFFFF").unwrap() - 4.48).abs() < 0.01);
        assert_eq!(contrast("#FFF", "#000000"), None);
    }

    #[test]
    fn valid_theme_passes_and_each_rule_fails() {
        let ok = ThemeRecord {
            project: "demo".into(),
            mode: "light".into(),
            tokens: tokens(),
            updated_at: String::new(),
        };
        assert!(
            validate_theme(&ok).errors.is_empty(),
            "{:?}",
            validate_theme(&ok)
        );
        let mut bad = ok.clone();
        bad.mode = "dim".into();
        bad.tokens.canvas = "white".into();
        bad.tokens.series.pop();
        bad.tokens.text_primary = "#DDDDDD".into();
        bad.tokens.on_accent = "#222222".into();
        let errors = validate_theme(&bad).errors;
        assert!(errors.iter().any(|e| e.starts_with("mode")));
        assert!(errors.iter().any(|e| e.starts_with("canvas")));
        assert!(errors.iter().any(|e| e.starts_with("series:")));
        assert!(errors
            .iter()
            .any(|e| e.starts_with("text_primary on surface")));
        assert!(errors.iter().any(|e| e.starts_with("on_accent on accent")));
    }
}

#[cfg(test)]
mod warning_tests {
    use super::*;

    #[test]
    fn yellow_accent_is_a_warning_not_an_error() {
        let mut t = super::tests::tokens();
        t.accent = "#F9DF4E".into();
        t.on_accent = "#111213".into();
        let check = validate_theme(&ThemeRecord {
            project: "p".into(),
            mode: "light".into(),
            tokens: t,
            updated_at: String::new(),
        });
        assert!(check.errors.is_empty(), "{:?}", check.errors);
        assert_eq!(check.warnings.len(), 1);
    }
}
