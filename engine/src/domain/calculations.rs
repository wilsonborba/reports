//! Versioned calculations: draft, validate, publish.
//!
//! A definition may reference only fields of published schema versions, known operators and
//! known output types. Publishing records the exact input schema versions, so an old
//! published version keeps working, and keeps its lineage, after a schema changes.
//! Browsers never send definitions: only published definitions run.

use std::collections::{BTreeMap, BTreeSet, HashMap};

use serde::Deserialize;
use utoipa::ToSchema;

use crate::core::error::ReportError;
use crate::dal::{calculations, catalog, schemas, CalculationVersion, InputRef, SchemaVersion};
use crate::domain::catalog::valid_slug;
use crate::domain::datasets::engine::{CompiledExpr, AGGREGATIONS, BUCKET_UNITS, MAX_WINDOW, NUMERIC_AGGREGATIONS, OPERATORS, WINDOW_AGGREGATIONS};
use crate::domain::datasets::spec::{Condition, DatasetSpec, DerivedSpec};
use crate::domain::datasets::DatasetService;
use crate::domain::guardrail::ValidationError;

/// Largest result a definition may produce.
pub const MAX_RESULT_ROWS: usize = 50_000;
pub const FILTER_TYPES: &[&str] = &["category", "date", "hour", "number"];
pub const OUTPUT_TYPES: &[&str] = &["string", "integer", "float", "percent", "date", "datetime", "hour", "latitude", "longitude"];
pub const CALCULATORS: &[&str] = &["series"];

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct CalculationDraftRequest {
    pub calculation_id: String,
    /// Omit it to create the next version.
    #[serde(default)]
    pub version: Option<i64>,
    /// Version of the source schema. Omit it to use the latest published version.
    #[serde(default)]
    pub input_schema_version: Option<i64>,
    #[schema(value_type = Object)]
    pub definition: DatasetSpec,
}

/// Field name to type (`any` for computed fields of unknown type).
type Fields = BTreeMap<String, String>;

fn err(path: &str, message: impl Into<String>) -> ValidationError {
    ValidationError::definition(path, message)
}

fn is_numeric(t: &str) -> bool {
    matches!(t, "integer" | "float" | "any")
}

fn top_level(schema: &SchemaVersion) -> Fields {
    schema
        .fields
        .iter()
        .filter(|f| !f.path.contains('.'))
        .map(|f| (f.path.clone(), f.field_type.clone()))
        .collect()
}

fn require(errors: &mut Vec<ValidationError>, fields: &Fields, name: &str, path: &str) {
    if !fields.contains_key(name) {
        errors.push(err(path, format!("field '{name}' does not exist here")));
    }
}

fn check_conditions(errors: &mut Vec<ValidationError>, fields: &Fields, conds: &[Condition], path: &str) {
    for (i, c) in conds.iter().enumerate() {
        require(errors, fields, &c.field, &format!("{path}[{i}].field"));
        if !OPERATORS.contains(&c.op.as_str()) {
            errors.push(err(&format!("{path}[{i}].op"), format!("unknown operator '{}'", c.op)));
        }
    }
}

fn check_derived(errors: &mut Vec<ValidationError>, fields: &mut Fields, derived: &[DerivedSpec], path: &str) {
    for (i, d) in derived.iter().enumerate() {
        match (&d.expr, &d.expr_field) {
            (Some(expr), _) => {
                if let Err(e) = CompiledExpr::compile(expr) {
                    errors.push(err(&format!("{path}[{i}].expr"), e.to_string()));
                }
            }
            (None, Some(f)) => require(errors, fields, f, &format!("{path}[{i}].expr_field")),
            (None, None) => errors.push(err(&format!("{path}[{i}]"), "needs expr or expr_field")),
        }
        fields.insert(d.name.clone(), "any".into());
    }
}

/// Latest published version of each schema of a project.
fn latest_published(all: &[SchemaVersion]) -> HashMap<String, &SchemaVersion> {
    let mut out: HashMap<String, &SchemaVersion> = HashMap::new();
    for s in all.iter().filter(|s| s.status == "published") {
        if out.get(&s.schema_name).is_none_or(|old| old.version < s.version) {
            out.insert(s.schema_name.clone(), s);
        }
    }
    out
}

/// Result of a validation: the violations and the exact inputs the definition reads.
pub struct Checked {
    pub errors: Vec<ValidationError>,
    pub input_schema: Option<String>,
    pub input_schema_version: Option<i64>,
    pub inputs: Vec<InputRef>,
}

/// Checks a definition against the published schemas of its project.
pub fn check_definition(def: &DatasetSpec, input_schema_version: Option<i64>, all: &[SchemaVersion]) -> Checked {
    let mut errors = Vec::new();
    let latest = latest_published(all);
    let mut inputs: BTreeSet<InputRef> = BTreeSet::new();
    let mut fields: Fields = Fields::new();
    let mut input_schema = None;
    let mut input_version = None;

    if let Some(c) = &def.calculator {
        let name = c.get("name").and_then(|v| v.as_str()).unwrap_or("");
        if !CALCULATORS.contains(&name) {
            errors.push(err("calculator.name", format!("unknown calculator '{name}' (use {})", CALCULATORS.join(", "))));
        }
    }
    match &def.source {
        Some(source) => {
            let chosen = match input_schema_version {
                Some(v) => all.iter().find(|s| &s.schema_name == source && s.version == v),
                None => latest.get(source).copied(),
            };
            match chosen {
                Some(s) if s.status == "published" => {
                    fields = top_level(s);
                    inputs.insert(InputRef { schema: s.schema_name.clone(), version: s.version });
                    input_schema = Some(s.schema_name.clone());
                    input_version = Some(s.version);
                }
                Some(s) => errors.push(err("source", format!("schema '{source}' v{} is {}, not published", s.version, s.status))),
                None => errors.push(err("source", format!("schema '{source}' has no published version{}", input_schema_version.map(|v| format!(" {v}")).unwrap_or_default()))),
            }
        }
        None if def.calculator.is_none() => errors.push(err("source", "a definition needs a source schema or a calculator")),
        None => {}
    }
    for (i, u) in def.union.iter().enumerate() {
        match latest.get(u) {
            Some(s) => {
                inputs.insert(InputRef { schema: s.schema_name.clone(), version: s.version });
            }
            None => errors.push(err(&format!("union[{i}]"), format!("schema '{u}' has no published version"))),
        }
    }
    for (i, l) in def.lookups.iter().enumerate() {
        let path = format!("lookups[{i}]");
        let Some(s) = latest.get(&l.collection) else {
            errors.push(err(&path, format!("schema '{}' has no published version", l.collection)));
            continue;
        };
        inputs.insert(InputRef { schema: s.schema_name.clone(), version: s.version });
        let theirs = top_level(s);
        for k in &l.key {
            require(&mut errors, &fields, k, &format!("{path}.key"));
        }
        let matches = if l.match_.is_empty() { &l.key } else { &l.match_ };
        if matches.len() != l.key.len() {
            errors.push(err(&format!("{path}.match"), "needs as many fields as key"));
        }
        for m in matches {
            require(&mut errors, &theirs, m, &format!("{path}.match"));
        }
        let copied: Vec<(String, String)> = if l.fields.is_empty() {
            theirs.clone().into_iter().collect()
        } else {
            l.fields
                .iter()
                .map(|f| {
                    require(&mut errors, &theirs, f, &format!("{path}.fields"));
                    (f.clone(), theirs.get(f).cloned().unwrap_or_else(|| "any".into()))
                })
                .collect()
        };
        let prefix = l.prefix.clone().unwrap_or_default();
        for (name, t) in copied {
            fields.insert(format!("{prefix}{name}"), t);
        }
    }
    for (i, b) in def.buckets.iter().enumerate() {
        let path = format!("buckets[{i}]");
        match fields.get(&b.field).map(String::as_str) {
            Some("date" | "datetime" | "any") => {}
            Some(other) => errors.push(err(&format!("{path}.field"), format!("'{}' is {other}, not a date or time", b.field))),
            None => require(&mut errors, &fields, &b.field, &format!("{path}.field")),
        }
        if !BUCKET_UNITS.contains(&b.unit.as_str()) {
            errors.push(err(&format!("{path}.unit"), format!("unknown unit '{}' (use {})", b.unit, BUCKET_UNITS.join(", "))));
        }
        fields.insert(b.name.clone(), "string".into());
    }
    check_derived(&mut errors, &mut fields, &def.row_derived, "row_derived");
    check_conditions(&mut errors, &fields, &def.where_, "where");
    for (i, f) in def.filters.iter().enumerate() {
        if !f.refs_only() {
            require(&mut errors, &fields, &f.field, &format!("filters[{i}].field"));
        }
        if !FILTER_TYPES.contains(&f.filter_type.as_str()) {
            errors.push(err(&format!("filters[{i}].type"), format!("unknown filter type '{}'", f.filter_type)));
        }
    }

    // Stages: every stage reads the outputs of the stage before it.
    let mut current = fields.clone();
    for (si, stage) in def.stages.iter().enumerate() {
        let path = format!("stages[{si}]");
        let mut out = Fields::new();
        for g in &stage.group_by {
            require(&mut errors, &current, g, &format!("{path}.group_by"));
            out.insert(g.clone(), current.get(g).cloned().unwrap_or_else(|| "any".into()));
        }
        for (mi, m) in stage.measures.iter().enumerate() {
            let mp = format!("{path}.measures[{mi}]");
            if !AGGREGATIONS.contains(&m.agg.as_str()) {
                errors.push(err(&format!("{mp}.agg"), format!("unknown aggregation '{}'", m.agg)));
            }
            if let Some(f) = &m.field {
                require(&mut errors, &current, f, &format!("{mp}.field"));
                if let Some(t) = current.get(f) {
                    if NUMERIC_AGGREGATIONS.contains(&m.agg.as_str()) && !is_numeric(t) {
                        errors.push(err(&format!("{mp}.field"), format!("'{}' needs a number, but '{f}' is {t}", m.agg)));
                    }
                }
            } else if m.agg != "count" && m.fields.is_empty() {
                errors.push(err(&format!("{mp}.field"), format!("'{}' needs a field", m.agg)));
            }
            for f in &m.fields {
                require(&mut errors, &current, f, &format!("{mp}.fields"));
            }
            if let Some(by) = &m.by {
                require(&mut errors, &current, by, &format!("{mp}.by"));
            }
            check_conditions(&mut errors, &current, &m.where_, &format!("{mp}.where"));
            out.insert(m.name.clone(), if m.agg == "count" || m.agg == "count_distinct" { "integer" } else { "any" }.into());
        }
        for p in &stage.partition_by {
            require(&mut errors, &out, p, &format!("{path}.partition_by"));
        }
        check_derived(&mut errors, &mut out, &stage.derived, &format!("{path}.derived"));
        for (wi, w) in stage.windows.iter().enumerate() {
            let wp = format!("{path}.windows[{wi}]");
            if !WINDOW_AGGREGATIONS.contains(&w.agg.as_str()) {
                errors.push(err(&format!("{wp}.agg"), format!("unknown window aggregation '{}'", w.agg)));
            }
            if w.size == 0 || w.size > MAX_WINDOW {
                errors.push(err(&format!("{wp}.size"), format!("use 1 to {MAX_WINDOW} rows")));
            }
            require(&mut errors, &out, &w.field, &format!("{wp}.field"));
            require(&mut errors, &out, &w.order_by, &format!("{wp}.order_by"));
            for p in &w.partition_by {
                require(&mut errors, &out, p, &format!("{wp}.partition_by"));
            }
            out.insert(w.name.clone(), "float".into());
        }
        check_conditions(&mut errors, &out, &stage.having, &format!("{path}.having"));
        current = out;
    }
    if let Some(c) = &def.calculator {
        // The series calculator makes its own rows: x plus one column per expression.
        current = Fields::new();
        if let Some(x) = c.get("x").and_then(|x| x.get("name")).and_then(|n| n.as_str()) {
            current.insert(x.into(), "float".into());
        }
        for e in c.get("exprs").and_then(|e| e.as_array()).cloned().unwrap_or_default() {
            if let Some(n) = e.get("name").and_then(|n| n.as_str()) {
                current.insert(n.into(), "float".into());
            }
        }
    }
    check_derived(&mut errors, &mut current, &def.derived, "derived");
    check_conditions(&mut errors, &current, &def.having, "having");
    for (i, s) in def.sort.iter().enumerate() {
        require(&mut errors, &current, &s.field, &format!("sort[{i}].field"));
    }
    if def.fields.is_empty() {
        errors.push(err("fields", "declare at least one output field"));
    }
    for (i, f) in def.fields.iter().enumerate() {
        require(&mut errors, &current, &f.name, &format!("fields[{i}].name"));
        if !OUTPUT_TYPES.contains(&f.field_type.as_str()) {
            errors.push(err(&format!("fields[{i}].type"), format!("unknown output type '{}'", f.field_type)));
        }
        if f.role != "dimension" && f.role != "measure" {
            errors.push(err(&format!("fields[{i}].role"), "use dimension or measure"));
        }
    }
    if def.limit.is_some_and(|l| l > MAX_RESULT_ROWS) {
        errors.push(err("limit", format!("at most {MAX_RESULT_ROWS} rows")));
    }
    Checked { errors, input_schema, input_schema_version: input_version, inputs: inputs.into_iter().collect() }
}

pub async fn save_draft(svc: &DatasetService, project: &str, req: CalculationDraftRequest) -> Result<CalculationVersion, ReportError> {
    let db = &svc.stores().db;
    catalog::active_project(db, project).await?;
    if !valid_slug(&req.calculation_id) {
        return Err(ReportError::BadRequest(format!("calculation id '{}' is not a valid slug", req.calculation_id)));
    }
    let version = match req.version {
        Some(v) if v > 0 => v,
        Some(v) => return Err(ReportError::BadRequest(format!("version {v} must be 1 or more"))),
        None => calculations::latest_version(db, project, &req.calculation_id).await?.unwrap_or(0) + 1,
    };
    let checked = check_definition(&req.definition, req.input_schema_version, &schemas::list(db, project).await?);
    let draft = CalculationVersion {
        project: project.to_string(),
        calculation_id: req.calculation_id.clone(),
        version,
        status: "draft".into(),
        input_schema: checked.input_schema.or(req.definition.source.clone()),
        input_schema_version: checked.input_schema_version.or(req.input_schema_version),
        inputs: checked.inputs,
        definition: req.definition,
        needs_review: false,
        created_at: String::new(),
        published_at: None,
    };
    calculations::save_draft(db, &draft).await?;
    calculations::get(db, project, &req.calculation_id, version)
        .await?
        .ok_or_else(|| ReportError::Internal("saved calculation draft is missing".into()))
}

async fn load(svc: &DatasetService, project: &str, id: &str, version: i64) -> Result<CalculationVersion, ReportError> {
    calculations::get(&svc.stores().db, project, id, version)
        .await?
        .ok_or_else(|| ReportError::not_found(format!("calculation {project}:{id} v{version}")))
}

/// Dry run: the violations a publish would report.
pub async fn validate(svc: &DatasetService, project: &str, id: &str, version: i64) -> Result<Vec<ValidationError>, ReportError> {
    let c = load(svc, project, id, version).await?;
    let all = schemas::list(&svc.stores().db, project).await?;
    Ok(check_definition(&c.definition, c.input_schema_version, &all).errors)
}

pub async fn publish(svc: &DatasetService, project: &str, id: &str, version: i64) -> Result<CalculationVersion, ReportError> {
    let db = &svc.stores().db;
    let mut c = load(svc, project, id, version).await?;
    if c.status != "draft" {
        return Err(ReportError::Conflict(format!("calculation {project}:{id} v{version} is {}, not a draft", c.status)));
    }
    let checked = check_definition(&c.definition, c.input_schema_version, &schemas::list(db, project).await?);
    if !checked.errors.is_empty() {
        return Err(ReportError::Validation { message: format!("calculation {id} v{version} cannot be published"), violations: checked.errors });
    }
    c.input_schema = checked.input_schema;
    c.input_schema_version = checked.input_schema_version;
    c.inputs = checked.inputs;
    if !calculations::publish(db, &c).await? {
        return Err(ReportError::Conflict(format!("calculation {project}:{id} v{version} changed during the request")));
    }
    load(svc, project, id, version).await
}

pub async fn retire(svc: &DatasetService, project: &str, id: &str, version: i64) -> Result<CalculationVersion, ReportError> {
    if !calculations::retire(&svc.stores().db, project, id, version).await? {
        return Err(ReportError::Conflict(format!("calculation {project}:{id} v{version} is not published")));
    }
    load(svc, project, id, version).await
}

/// Checks that the refs of the datasets of a report form no cycle (the new binding included).
pub fn check_ref_cycles(graph: &HashMap<String, Vec<String>>) -> Result<(), ReportError> {
    fn visit(n: &str, g: &HashMap<String, Vec<String>>, stack: &mut Vec<String>, done: &mut BTreeSet<String>) -> Option<Vec<String>> {
        if done.contains(n) {
            return None;
        }
        if let Some(pos) = stack.iter().position(|s| s == n) {
            let mut cycle = stack[pos..].to_vec();
            cycle.push(n.to_string());
            return Some(cycle);
        }
        stack.push(n.to_string());
        for next in g.get(n).into_iter().flatten() {
            if let Some(c) = visit(next, g, stack, done) {
                return Some(c);
            }
        }
        stack.pop();
        done.insert(n.to_string());
        None
    }
    let mut done = BTreeSet::new();
    for n in graph.keys() {
        if let Some(cycle) = visit(n, graph, &mut Vec::new(), &mut done) {
            return Err(ReportError::Validation {
                message: "cyclic dataset references".into(),
                violations: vec![err("spec.refs", format!("cycle: {}", cycle.join(" -> ")))],
            });
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::guardrail::SchemaField;
    use serde_json::json;

    fn schema(name: &str, version: i64, status: &str, fields: &[(&str, &str)]) -> SchemaVersion {
        SchemaVersion {
            project: "autodroid".into(),
            schema_name: name.into(),
            version,
            status: status.into(),
            description: None,
            fields: fields.iter().map(|(p, t)| SchemaField { path: (*p).into(), field_type: (*t).into(), required: true, description: None }).collect(),
            created_at: String::new(),
            published_at: None,
        }
    }

    /// Fields of the autodroid `Job` model (autodroid/lib/domain/models/job_model.py).
    fn job_v1() -> SchemaVersion {
        schema("job", 1, "published", &[("job_type", "string"), ("adapter_name", "string"), ("status", "string"), ("attempt_count", "integer"), ("created_at", "datetime")])
    }

    fn def(v: serde_json::Value) -> DatasetSpec {
        serde_json::from_value(v).unwrap()
    }

    #[test]
    fn valid_definition_records_its_inputs() {
        let d = def(json!({
            "title": {"en": "Failure rate"}, "source": "job",
            "buckets": [{"field": "created_at", "unit": "day", "name": "day"}],
            "stages": [{"group_by": ["day"], "measures": [
                {"name": "jobs", "agg": "count"},
                {"name": "failed", "agg": "count", "where": [{"field": "status", "op": "eq", "value": "failed"}]}
            ], "derived": [{"name": "failure_rate", "expr": "failed / jobs * 100"}],
              "windows": [{"name": "rate_7d", "agg": "avg", "field": "failure_rate", "size": 7, "order_by": "day"}]}],
            "fields": [{"name": "day", "label": {"en": "Day"}, "type": "date", "role": "dimension"},
                       {"name": "rate_7d", "label": {"en": "7-day rate"}, "type": "percent"}]
        }));
        let c = check_definition(&d, None, &[job_v1()]);
        assert!(c.errors.is_empty(), "{:?}", c.errors);
        assert_eq!(c.inputs, vec![InputRef { schema: "job".into(), version: 1 }]);
    }

    #[test]
    fn invalid_bindings_fail_before_publish() {
        let d = def(json!({
            "title": {"en": "x"}, "source": "job",
            "where": [{"field": "status", "op": "like", "value": "x"}],
            "stages": [{"group_by": ["adapter"], "measures": [
                {"name": "s", "agg": "sum", "field": "job_type"},
                {"name": "m", "agg": "median", "field": "attempt_count"}]}],
            "fields": [{"name": "nope", "label": {"en": "x"}, "type": "money"}]
        }));
        let paths: Vec<String> = check_definition(&d, None, &[job_v1()]).errors.into_iter().map(|e| e.field_path).collect();
        for p in ["where[0].op", "stages[0].group_by", "stages[0].measures[0].field", "stages[0].measures[1].agg", "fields[0].name", "fields[0].type"] {
            assert!(paths.iter().any(|x| x == p), "missing {p} in {paths:?}");
        }
    }

    #[test]
    fn a_renamed_field_needs_a_new_compatible_version() {
        let renamed = schema("job", 2, "published", &[("job_kind", "string"), ("status", "string")]);
        let d = def(json!({"title": {"en": "x"}, "source": "job",
            "stages": [{"group_by": ["job_type"], "measures": [{"name": "n", "agg": "count"}]}],
            "fields": [{"name": "n", "label": {"en": "n"}, "type": "integer"}]}));
        // Against the latest version (v2) the old field name fails; pinned to v1 it passes.
        assert!(!check_definition(&d, None, &[job_v1(), renamed.clone()]).errors.is_empty());
        assert!(check_definition(&d, Some(1), &[job_v1(), renamed]).errors.is_empty());
        // A draft schema version is not an input.
        assert!(!check_definition(&d, Some(3), &[schema("job", 3, "draft", &[("job_type", "string")])]).errors.is_empty());
    }

    #[test]
    fn reference_cycles_are_refused() {
        let mut g = HashMap::new();
        g.insert("a".to_string(), vec!["b".to_string()]);
        g.insert("b".to_string(), vec!["c".to_string()]);
        assert!(check_ref_cycles(&g).is_ok());
        g.insert("c".to_string(), vec!["a".to_string()]);
        assert!(check_ref_cycles(&g).is_err());
    }
}
