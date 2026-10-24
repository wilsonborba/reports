//! Write rules for catalog entries (projects, reports, datasets).

use crate::core::error::ReportError;
use crate::dal::{DatasetRecord, ProjectRecord, ReportRecord};
use crate::domain::auth::Visibility;
use crate::domain::datasets::spec::{first_double_name, I18nText};
use crate::domain::guardrail::ValidationError;

pub const MAX_NAME_CHARS: usize = 80;
pub const MAX_TAGLINE_CHARS: usize = 140;
pub const MAX_DESCRIPTION_CHARS: usize = 600;
/// Languages of stored texts.
pub const LANGUAGES: &[&str] = &["en", "pt-BR", "th"];

/// Slug of a project, report, dataset or schema: 2 to 48 characters a-z, 0-9, `_` or `-`,
/// starting with a letter.
pub fn valid_slug(slug: &str) -> bool {
    let mut chars = slug.chars();
    matches!(chars.next(), Some(c) if c.is_ascii_lowercase())
        && (2..=48).contains(&slug.len())
        && slug.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '-')
}

/// True for an https URL with a host and no spaces.
pub fn valid_https_url(url: &str) -> bool {
    url.strip_prefix("https://")
        .map(|r| !r.is_empty() && !r.contains(char::is_whitespace))
        .unwrap_or(false)
}

fn check_text(errors: &mut Vec<ValidationError>, field: &str, text: &I18nText, max: usize, single_line: bool) {
    for (lang, value) in text {
        if !LANGUAGES.contains(&lang.as_str()) {
            errors.push(ValidationError::definition(
                field,
                format!("language '{lang}' is not supported (use {})", LANGUAGES.join(", ")),
            ));
        }
        if value.chars().count() > max {
            errors.push(ValidationError::definition(&format!("{field}.{lang}"), format!("more than {max} characters")));
        }
        if single_line && value.contains('\n') {
            errors.push(ValidationError::definition(&format!("{field}.{lang}"), "must be one line"));
        }
    }
}

fn require_en(errors: &mut Vec<ValidationError>, field: &str, text: &I18nText) {
    if text.get("en").map(|s| s.trim().is_empty()).unwrap_or(true) {
        errors.push(ValidationError::definition(&format!("{field}.en"), "is required"));
    }
}

fn finish(errors: Vec<ValidationError>, what: &str) -> Result<(), ReportError> {
    if errors.is_empty() {
        Ok(())
    } else {
        Err(ReportError::Validation { message: format!("invalid {what}"), violations: errors })
    }
}

pub fn validate_project(p: &ProjectRecord) -> Result<(), ReportError> {
    let mut errors = Vec::new();
    if !valid_slug(&p.slug) {
        errors.push(ValidationError::definition("slug", "use 2 to 48 characters a-z, 0-9, _ or -, starting with a letter"));
    }
    require_en(&mut errors, "name", &p.name);
    check_text(&mut errors, "name", &p.name, MAX_NAME_CHARS, true);
    check_text(&mut errors, "tagline", &p.tagline, MAX_TAGLINE_CHARS, true);
    check_text(&mut errors, "description", &p.description, MAX_DESCRIPTION_CHARS, false);
    for (field, url) in [("website_url", &p.website_url), ("repository_url", &p.repository_url)] {
        if let Some(u) = url {
            if !valid_https_url(u) {
                errors.push(ValidationError::definition(field, format!("'{u}' must be an https URL")));
            }
        }
    }
    if let Some(id) = &p.domain_project_id {
        if uuid::Uuid::parse_str(id).is_err() {
            errors.push(ValidationError::definition("domain_project_id", format!("'{id}' is not a UUID")));
        }
    }
    finish(errors, "project")
}

pub fn validate_report(r: &ReportRecord) -> Result<(), ReportError> {
    let mut errors = Vec::new();
    if !valid_slug(&r.slug) {
        errors.push(ValidationError::definition("slug", "use 2 to 48 characters a-z, 0-9, _ or -, starting with a letter"));
    }
    require_en(&mut errors, "title", &r.title);
    check_text(&mut errors, "title", &r.title, MAX_NAME_CHARS, true);
    check_text(&mut errors, "description", &r.description, MAX_DESCRIPTION_CHARS, false);
    if let Some(t) = first_double_name(&r.title) {
        errors.push(ValidationError::definition("title", format!("must be one name, not two joined names: '{t}'")));
    }
    if let Err(ReportError::BadRequest(m)) = Visibility::parse_strict(&r.visibility) {
        errors.push(ValidationError::definition("visibility", m));
    }
    finish(errors, "report")
}

pub fn validate_dataset(d: &DatasetRecord) -> Result<(), ReportError> {
    let mut errors = Vec::new();
    if !valid_slug(&d.dataset_id) {
        errors.push(ValidationError::definition("dataset_id", "use 2 to 48 characters a-z, 0-9, _ or -, starting with a letter"));
    }
    require_en(&mut errors, "spec.title", &d.spec.title);
    check_text(&mut errors, "spec.title", &d.spec.title, MAX_NAME_CHARS, true);
    if let Some(t) = first_double_name(&d.spec.title) {
        errors.push(ValidationError::definition("spec.title", format!("must be one name, not two joined names: '{t}'")));
    }
    if let Err(ReportError::BadRequest(m)) = Visibility::parse_strict(&d.visibility) {
        errors.push(ValidationError::definition("visibility", m));
    }
    if d.spec.source.is_none() && d.spec.calculator.is_none() {
        errors.push(ValidationError::definition("spec.source", "a dataset needs a source schema or a calculator"));
    }
    finish(errors, "dataset")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::themes::ProjectTheme;

    fn project() -> ProjectRecord {
        ProjectRecord {
            slug: "cortex".into(),
            name: [("en".to_string(), "Cortex".to_string()), ("pt-BR".to_string(), "Cortex".to_string())].into(),
            tagline: Default::default(),
            description: [("th".to_string(), "ผู้ช่วย AI".to_string())].into(),
            theme: ProjectTheme::default(),
            is_active: true,
            website_url: Some("https://cortex.asodya.com".into()),
            repository_url: Some("https://github.com/wilsonborba/cortex".into()),
            sort_order: 0,
            domain_project_id: Some("4ef82613-e51e-42fa-9f3e-93809fdff54b".into()),
            updated_at: String::new(),
        }
    }

    #[test]
    fn accepts_en_pt_br_and_th() {
        assert!(validate_project(&project()).is_ok());
    }

    #[test]
    fn rejects_bad_slug_missing_english_and_unknown_language() {
        let mut p = project();
        p.slug = "Bad Slug".into();
        p.name = [("fr".to_string(), "x".to_string())].into();
        p.website_url = Some("http://cortex.asodya.com".into());
        p.domain_project_id = Some("cortex".into());
        match validate_project(&p) {
            Err(ReportError::Validation { violations, .. }) => assert_eq!(violations.len(), 5, "{violations:?}"),
            other => panic!("{other:?}"),
        }
    }
}
