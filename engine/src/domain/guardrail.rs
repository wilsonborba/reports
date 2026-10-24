//! Schema guardrail: a received payload must match the fields of its published schema
//! version. Missing required fields, wrong types and undeclared fields are rejected before
//! anything reaches the document store.

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::collections::BTreeMap;
use utoipa::ToSchema;

/// Field types that a schema can declare.
pub const FIELD_TYPES: &[&str] = &[
    "string", "integer", "float", "boolean", "date", "datetime", "object", "array",
];

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ValidationViolationType {
    MissingRequiredField,
    TypeMismatch { expected: String, found: String },
    UnknownField,
    SchemaNotFound,
    InvalidRoot,
    InvalidDefinition,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
pub struct ValidationError {
    pub field_path: String,
    pub message: String,
    pub error_type: ValidationViolationType,
}

impl ValidationError {
    pub fn definition(path: &str, message: impl Into<String>) -> Self {
        Self {
            field_path: path.to_string(),
            message: message.into(),
            error_type: ValidationViolationType::InvalidDefinition,
        }
    }
}

/// One declared field. `path` uses dots for nested objects (`input.tokens`) and `[]` for the
/// items of an array of objects (`steps[].name`).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
pub struct SchemaField {
    pub path: String,
    #[serde(rename = "type")]
    pub field_type: String,
    #[serde(default)]
    pub required: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
}

/// Checks a field list before it is stored: known types, valid paths, no duplicates, and a
/// parent of type object (or array for `[]`) for every nested path.
pub fn check_fields(fields: &[SchemaField]) -> Vec<ValidationError> {
    let mut errors = Vec::new();
    let mut seen: BTreeMap<&str, &str> = BTreeMap::new();
    if fields.is_empty() {
        errors.push(ValidationError::definition("$", "a schema needs at least one field"));
    }
    for f in fields {
        if !FIELD_TYPES.contains(&f.field_type.as_str()) {
            errors.push(ValidationError::definition(
                &f.path,
                format!("unknown type '{}' (use {})", f.field_type, FIELD_TYPES.join(", ")),
            ));
        }
        let valid_path = !f.path.is_empty()
            && f.path.split('.').all(|seg| {
                let name = seg.strip_suffix("[]").unwrap_or(seg);
                !name.is_empty() && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
            });
        if !valid_path {
            errors.push(ValidationError::definition(&f.path, "invalid field path"));
        }
        if seen.insert(f.path.as_str(), f.field_type.as_str()).is_some() {
            errors.push(ValidationError::definition(&f.path, "duplicate field path"));
        }
    }
    for f in fields {
        if let Some((parent, _)) = f.path.rsplit_once('.') {
            let (parent_path, needs) = match parent.strip_suffix("[]") {
                Some(p) => (p, "array"),
                None => (parent, "object"),
            };
            if seen.get(parent_path).copied() != Some(needs) {
                errors.push(ValidationError::definition(
                    &f.path,
                    format!("parent '{parent_path}' must be declared with type {needs}"),
                ));
            }
        }
    }
    errors
}

/// Validates one payload against a published field list.
pub fn validate_payload(fields: &[SchemaField], payload: &Value) -> Result<(), Vec<ValidationError>> {
    let Some(root) = payload.as_object() else {
        return Err(vec![ValidationError {
            field_path: "$".into(),
            message: "Payload root must be a JSON object".into(),
            error_type: ValidationViolationType::InvalidRoot,
        }]);
    };
    let mut errors = Vec::new();
    validate_object(root, "", fields, &mut errors);
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

/// Fields directly below `prefix` ("" for the root, "a." or "a[]." for nested ones).
fn children<'a>(fields: &'a [SchemaField], prefix: &str) -> Vec<(&'a str, &'a SchemaField)> {
    fields
        .iter()
        .filter_map(|f| {
            let rest = f.path.strip_prefix(prefix)?;
            (!rest.contains('.')).then_some((rest, f))
        })
        .collect()
}

fn validate_object(obj: &Map<String, Value>, prefix: &str, fields: &[SchemaField], errors: &mut Vec<ValidationError>) {
    let expected = children(fields, prefix);
    for (name, f) in &expected {
        let missing = obj.get(*name).map(Value::is_null).unwrap_or(true);
        if f.required && missing {
            errors.push(ValidationError {
                field_path: f.path.clone(),
                message: format!("Required field '{}' is missing", f.path),
                error_type: ValidationViolationType::MissingRequiredField,
            });
        }
    }
    for (key, value) in obj {
        let path = format!("{prefix}{key}");
        match expected.iter().find(|(name, _)| name == key) {
            None => errors.push(ValidationError {
                field_path: path.clone(),
                message: format!("Undeclared field '{path}' is not defined in the schema"),
                error_type: ValidationViolationType::UnknownField,
            }),
            Some((_, f)) if value.is_null() => {
                let _ = f; // optional null values are allowed; required ones were reported above
            }
            Some((_, f)) => validate_value(value, f, fields, errors),
        }
    }
}

fn validate_value(value: &Value, f: &SchemaField, fields: &[SchemaField], errors: &mut Vec<ValidationError>) {
    let ok = match f.field_type.as_str() {
        "string" => value.is_string(),
        "integer" => value.is_i64() || value.is_u64(),
        "float" => value.is_number(),
        "boolean" => value.is_boolean(),
        "date" => value
            .as_str()
            .map(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d").is_ok())
            .unwrap_or(false),
        "datetime" => value
            .as_str()
            .map(|s| chrono::DateTime::parse_from_rfc3339(s).is_ok())
            .unwrap_or(false),
        "object" => match value.as_object() {
            Some(child) => {
                validate_object(child, &format!("{}.", f.path), fields, errors);
                true
            }
            None => false,
        },
        "array" => match value.as_array() {
            Some(items) => {
                let item_prefix = format!("{}[].", f.path);
                if !children(fields, &item_prefix).is_empty() {
                    for (i, item) in items.iter().enumerate() {
                        match item.as_object() {
                            Some(obj) => validate_object(obj, &item_prefix, fields, errors),
                            None => errors.push(ValidationError {
                                field_path: format!("{}[{}]", f.path, i),
                                message: format!("Items of '{}' must be objects", f.path),
                                error_type: ValidationViolationType::TypeMismatch {
                                    expected: "object".into(),
                                    found: type_name(item).into(),
                                },
                            }),
                        }
                    }
                }
                true
            }
            None => false,
        },
        _ => false,
    };
    if !ok {
        errors.push(ValidationError {
            field_path: f.path.clone(),
            message: format!("Field '{}' must be of type {}", f.path, f.field_type),
            error_type: ValidationViolationType::TypeMismatch {
                expected: f.field_type.clone(),
                found: type_name(value).into(),
            },
        });
    }
}

fn type_name(v: &Value) -> &'static str {
    match v {
        Value::Null => "null",
        Value::Bool(_) => "boolean",
        Value::Number(n) if n.is_i64() || n.is_u64() => "integer",
        Value::Number(_) => "float",
        Value::String(_) => "string",
        Value::Array(_) => "array",
        Value::Object(_) => "object",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// Fields of the cortex_api `TelemetryEvent` model (cortex_api/lib/dal/models.py).
    fn telemetry_fields() -> Vec<SchemaField> {
        let f = |path: &str, t: &str, required: bool| SchemaField {
            path: path.into(),
            field_type: t.into(),
            required,
            description: None,
        };
        vec![
            f("request_id", "string", true),
            f("tier_requested", "integer", true),
            f("tier_executed", "integer", true),
            f("task_type", "string", true),
            f("provider", "string", true),
            f("model", "string", true),
            f("input_tokens", "integer", true),
            f("output_tokens", "integer", true),
            f("total_tokens", "integer", true),
            f("latency_ms", "integer", true),
            f("success", "boolean", true),
            f("error_type", "string", false),
            f("started_at", "datetime", true),
        ]
    }

    fn event() -> Value {
        json!({
            "request_id": "req-0001", "tier_requested": 2, "tier_executed": 2,
            "task_type": "chat", "provider": "ollama", "model": "qwen2.5:7b",
            "input_tokens": 812, "output_tokens": 240, "total_tokens": 1052,
            "latency_ms": 1830, "success": true, "error_type": null,
            "started_at": "2026-10-20T09:15:00+07:00"
        })
    }

    #[test]
    fn valid_telemetry_event_passes() {
        assert!(check_fields(&telemetry_fields()).is_empty());
        assert_eq!(validate_payload(&telemetry_fields(), &event()), Ok(()));
    }

    #[test]
    fn rejects_missing_wrong_type_and_unknown_fields() {
        let mut bad = event();
        bad.as_object_mut().unwrap().remove("model");
        bad["latency_ms"] = json!("slow");
        bad["camera_id"] = json!("x");
        let errors = validate_payload(&telemetry_fields(), &bad).unwrap_err();
        let kinds: Vec<_> = errors.iter().map(|e| (&e.field_path[..], &e.error_type)).collect();
        assert!(kinds.contains(&("model", &ValidationViolationType::MissingRequiredField)));
        assert!(kinds.iter().any(|(p, t)| *p == "latency_ms" && matches!(t, ValidationViolationType::TypeMismatch { .. })));
        assert!(kinds.contains(&("camera_id", &ValidationViolationType::UnknownField)));
    }

    #[test]
    fn nested_objects_and_arrays() {
        let fields = vec![
            SchemaField { path: "job".into(), field_type: "object".into(), required: true, description: None },
            SchemaField { path: "job.status".into(), field_type: "string".into(), required: true, description: None },
            SchemaField { path: "attempts".into(), field_type: "array".into(), required: false, description: None },
            SchemaField { path: "attempts[].at".into(), field_type: "datetime".into(), required: true, description: None },
        ];
        assert!(check_fields(&fields).is_empty());
        assert!(validate_payload(&fields, &json!({"job": {"status": "done"}, "attempts": [{"at": "2026-10-20T00:00:00Z"}]})).is_ok());
        let errors = validate_payload(&fields, &json!({"job": {}, "attempts": [{"at": "yesterday"}]})).unwrap_err();
        assert_eq!(errors.len(), 2, "{errors:?}");
    }

    #[test]
    fn definition_rules() {
        let bad = vec![
            SchemaField { path: "a.b".into(), field_type: "string".into(), required: false, description: None },
            SchemaField { path: "c".into(), field_type: "money".into(), required: false, description: None },
            SchemaField { path: "c".into(), field_type: "string".into(), required: false, description: None },
        ];
        assert_eq!(check_fields(&bad).len(), 3);
    }
}
