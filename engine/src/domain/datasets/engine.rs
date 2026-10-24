//! Generic dataset calculation engine.
//!
//! The engine turns stored documents into dataset rows with lookups, row
//! expressions, conditions, client filters, grouping stages, derived
//! expressions and named calculators. It never decides how the data is shown.

use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};

use evalexpr::{
    build_operator_tree, ContextWithMutableVariables, DefaultNumericTypes, HashMapContext, Node,
    Value as EvalValue,
};
use serde_json::{Map, Number, Value};

use super::spec::{
    BucketSpec, Condition, DatasetSpec, DerivedSpec, FilterParam, LookupSpec, MeasureSpec, StageSpec,
    WindowSpec,
};

/// Aggregations of a measure.
pub const AGGREGATIONS: &[&str] = &[
    "sum", "avg", "min", "max", "count", "count_distinct", "argmax", "argmin", "top", "top_share", "first", "sum_top",
];
/// Aggregations that need a numeric field.
pub const NUMERIC_AGGREGATIONS: &[&str] = &["sum", "avg", "min", "max", "sum_top"];
/// Condition operators.
pub const OPERATORS: &[&str] = &[
    "eq", "ne", "in", "not_in", "between", "gt", "gte", "lt", "lte", "ends_with", "starts_with",
];
pub const BUCKET_UNITS: &[&str] = &["hour", "day", "week", "month"];
pub const WINDOW_AGGREGATIONS: &[&str] = &["avg", "sum", "min", "max"];
pub const MAX_WINDOW: usize = 366;

pub type Row = Map<String, Value>;

/// Returns the records of a lookup schema by name.
pub type LookupLoader<'a> = dyn Fn(&str) -> Result<std::sync::Arc<Vec<Row>>, EngineError> + 'a;

#[derive(Debug, thiserror::Error, PartialEq)]
pub enum EngineError {
    #[error("Invalid dataset specification: {0}")]
    Spec(String),
    #[error("Invalid filter: {0}")]
    Filter(String),
    #[error("Expression error in '{expr}': {message}")]
    Expression { expr: String, message: String },
}

// ---------------------------------------------------------------------------
// Value helpers
// ---------------------------------------------------------------------------

/// Numeric value of a JSON value (numbers and numeric strings).
pub fn as_f64(v: &Value) -> Option<f64> {
    match v {
        Value::Number(n) => n.as_f64(),
        Value::String(s) => s.trim().parse::<f64>().ok(),
        Value::Bool(b) => Some(if *b { 1.0 } else { 0.0 }),
        _ => None,
    }
}

/// Stable text key of a JSON value, used for grouping and category filters.
pub fn key_of(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        Value::Number(n) => {
            if let Some(i) = n.as_i64() {
                i.to_string()
            } else {
                let f = n.as_f64().unwrap_or(0.0);
                if f.fract() == 0.0 && f.abs() < 1e15 {
                    format!("{}", f as i64)
                } else {
                    f.to_string()
                }
            }
        }
        Value::Bool(b) => b.to_string(),
        Value::Null => String::new(),
        other => other.to_string(),
    }
}

/// Compares two JSON values: numerically when both are numbers, else as text.
pub fn compare_values(a: &Value, b: &Value) -> Ordering {
    match (as_f64(a), as_f64(b)) {
        (Some(x), Some(y)) => x.partial_cmp(&y).unwrap_or(Ordering::Equal),
        _ => key_of(a).cmp(&key_of(b)),
    }
}

fn number(f: f64) -> Value {
    if f.is_finite() {
        Number::from_f64(f)
            .map(Value::Number)
            .unwrap_or(Value::Null)
    } else {
        Value::Null
    }
}

fn field<'a>(row: &'a Row, name: &str) -> &'a Value {
    row.get(name).unwrap_or(&Value::Null)
}

// ---------------------------------------------------------------------------
// Conditions and filters
// ---------------------------------------------------------------------------

pub fn matches_condition(row: &Row, c: &Condition) -> Result<bool, EngineError> {
    let v = field(row, &c.field);
    let ok = match c.op.as_str() {
        "eq" => compare_values(v, &c.value) == Ordering::Equal,
        "ne" => compare_values(v, &c.value) != Ordering::Equal,
        "in" | "not_in" => {
            let list = c.value.as_array().ok_or_else(|| {
                EngineError::Spec(format!("condition '{}' needs a list value", c.op))
            })?;
            let key = key_of(v);
            let found = list.iter().any(|x| key_of(x) == key);
            if c.op == "in" {
                found
            } else {
                !found
            }
        }
        "between" => {
            let list = c.value.as_array().filter(|l| l.len() == 2).ok_or_else(|| {
                EngineError::Spec("condition 'between' needs [from, to]".to_string())
            })?;
            !v.is_null()
                && compare_values(v, &list[0]) != Ordering::Less
                && compare_values(v, &list[1]) != Ordering::Greater
        }
        "gt" => !v.is_null() && compare_values(v, &c.value) == Ordering::Greater,
        "gte" => !v.is_null() && compare_values(v, &c.value) != Ordering::Less,
        "lt" => !v.is_null() && compare_values(v, &c.value) == Ordering::Less,
        "lte" => !v.is_null() && compare_values(v, &c.value) != Ordering::Greater,
        "ends_with" => key_of(v).ends_with(&key_of(&c.value)),
        "starts_with" => key_of(v).starts_with(&key_of(&c.value)),
        other => {
            return Err(EngineError::Spec(format!(
                "unknown condition operator '{}'",
                other
            )))
        }
    };
    Ok(ok)
}

pub fn matches_all(row: &Row, conditions: &[Condition]) -> Result<bool, EngineError> {
    for c in conditions {
        if !matches_condition(row, c)? {
            return Ok(false);
        }
    }
    Ok(true)
}

pub fn matches_filter(row: &Row, f: &FilterParam) -> bool {
    match f {
        FilterParam::In {
            field: name,
            values,
        } => {
            let key = key_of(field(row, name));
            values.contains(&key)
        }
        FilterParam::Range {
            field: name,
            from,
            to,
        } => {
            let v = field(row, name);
            if v.is_null() {
                return false;
            }
            if let Some(from) = from {
                if compare_values(v, &typed_like(v, from)) == Ordering::Less {
                    return false;
                }
            }
            if let Some(to) = to {
                if compare_values(v, &typed_like(v, to)) == Ordering::Greater {
                    return false;
                }
            }
            true
        }
    }
}

/// Converts a filter text to the same JSON kind as the row value.
fn typed_like(sample: &Value, text: &str) -> Value {
    match sample {
        Value::Number(_) => text
            .parse::<f64>()
            .map(number)
            .unwrap_or(Value::String(text.to_string())),
        _ => Value::String(text.to_string()),
    }
}

// ---------------------------------------------------------------------------
// Expressions
// ---------------------------------------------------------------------------

pub struct CompiledExpr {
    text: String,
    node: Node<DefaultNumericTypes>,
    idents: Vec<String>,
}

impl CompiledExpr {
    pub fn compile(text: &str) -> Result<Self, EngineError> {
        let node = build_operator_tree::<DefaultNumericTypes>(text).map_err(|e| {
            EngineError::Expression {
                expr: text.to_string(),
                message: e.to_string(),
            }
        })?;
        let idents = node
            .iter_variable_identifiers()
            .map(|s| s.to_string())
            .collect::<HashSet<_>>()
            .into_iter()
            .collect();
        Ok(Self {
            text: text.to_string(),
            node,
            idents,
        })
    }

    /// Evaluates the expression. `lookup` returns the value of a variable.
    pub fn eval(&self, lookup: &dyn Fn(&str) -> Option<Value>) -> Result<Value, EngineError> {
        let mut ctx = HashMapContext::<DefaultNumericTypes>::new();
        for id in &self.idents {
            let v = lookup(id).unwrap_or(Value::Null);
            let ev = match &v {
                Value::Number(n) => EvalValue::Float(n.as_f64().unwrap_or(0.0)),
                Value::String(s) => EvalValue::String(s.clone()),
                Value::Bool(b) => EvalValue::Boolean(*b),
                _ => EvalValue::Empty,
            };
            ctx.set_value(id.clone(), ev)
                .map_err(|e| self.err(e.to_string()))?;
        }
        let out = self
            .node
            .eval_with_context(&ctx)
            .map_err(|e| self.err(e.to_string()))?;
        Ok(match out {
            EvalValue::Float(f) => number(f),
            EvalValue::Int(i) => Value::Number(i.into()),
            EvalValue::String(s) => Value::String(s),
            EvalValue::Boolean(b) => Value::Bool(b),
            _ => Value::Null,
        })
    }

    fn err(&self, message: String) -> EngineError {
        EngineError::Expression {
            expr: self.text.clone(),
            message,
        }
    }
}

/// Aggregates of every numeric field over a set of rows: `sum_`, `min_`, `max_` (with a prefix).
fn numeric_aggregates<'a>(
    rows: impl Iterator<Item = &'a Row>,
    prefix: &str,
    out: &mut HashMap<String, f64>,
) {
    let mut count = 0usize;
    for row in rows {
        count += 1;
        for (k, v) in row {
            if let Value::Number(n) = v {
                let f = n.as_f64().unwrap_or(0.0);
                *out.entry(format!("{prefix}sum_{k}")).or_insert(0.0) += f;
                let min = out
                    .entry(format!("{prefix}min_{k}"))
                    .or_insert(f64::INFINITY);
                if f < *min {
                    *min = f;
                }
                let max = out
                    .entry(format!("{prefix}max_{k}"))
                    .or_insert(f64::NEG_INFINITY);
                if f > *max {
                    *max = f;
                }
            }
        }
    }
    out.insert(format!("{prefix}rows"), count as f64);
}

/// Applies derived expressions to rows in order. Later expressions can use earlier results.
pub fn apply_derived(
    rows: &mut [Row],
    derived: &[DerivedSpec],
    partition_by: &[String],
    scalars: &HashMap<String, f64>,
) -> Result<(), EngineError> {
    let mut cache: HashMap<String, CompiledExpr> = HashMap::new();
    for d in derived {
        let needs_globals = d.expr_field.is_some()
            || d.expr
                .as_deref()
                .map(|e| {
                    e.contains("sum_")
                        || e.contains("min_")
                        || e.contains("max_")
                        || e.contains("rows")
                })
                .unwrap_or(false);
        let mut globals = HashMap::new();
        let mut partitions: HashMap<String, HashMap<String, f64>> = HashMap::new();
        if needs_globals {
            numeric_aggregates(rows.iter(), "", &mut globals);
            if !partition_by.is_empty() {
                let mut groups: HashMap<String, Vec<&Row>> = HashMap::new();
                for r in rows.iter() {
                    groups
                        .entry(partition_key(r, partition_by))
                        .or_default()
                        .push(r);
                }
                for (k, members) in groups {
                    let mut agg = HashMap::new();
                    numeric_aggregates(members.into_iter(), "p", &mut agg);
                    partitions.insert(k, agg);
                }
            }
        }
        let fixed = match &d.expr {
            Some(e) => Some(CompiledExpr::compile(e)?),
            None => None,
        };
        for row in rows.iter_mut() {
            let text_expr;
            let expr: &CompiledExpr = match (&fixed, &d.expr_field) {
                (Some(c), _) => c,
                (None, Some(fieldname)) => {
                    let text = key_of(field(row, fieldname));
                    if text.is_empty() {
                        row.insert(d.name.clone(), Value::Null);
                        continue;
                    }
                    if !cache.contains_key(&text) {
                        cache.insert(text.clone(), CompiledExpr::compile(&text)?);
                    }
                    text_expr = cache.get(&text).unwrap();
                    text_expr
                }
                _ => {
                    return Err(EngineError::Spec(format!(
                        "derived '{}' needs expr or expr_field",
                        d.name
                    )))
                }
            };
            let part = if partition_by.is_empty() {
                None
            } else {
                partitions.get(&partition_key(row, partition_by))
            };
            let value = {
                let row_ref: &Row = row;
                expr.eval(&|id: &str| {
                    if let Some(v) = row_ref.get(id) {
                        return Some(v.clone());
                    }
                    if let Some(f) = scalars.get(id) {
                        return Some(number(*f));
                    }
                    if let Some(p) = part.and_then(|p| p.get(id)) {
                        return Some(number(*p));
                    }
                    globals.get(id).map(|f| number(*f))
                })?
            };
            row.insert(d.name.clone(), value);
        }
    }
    Ok(())
}

fn partition_key(row: &Row, fields: &[String]) -> String {
    fields
        .iter()
        .map(|f| key_of(field(row, f)))
        .collect::<Vec<_>>()
        .join("\u{1f}")
}

// ---------------------------------------------------------------------------
// Lookups and row expressions
// ---------------------------------------------------------------------------

/// Adds lookup fields to every row. Rows without a match keep their own fields.
pub fn apply_lookup(rows: &mut [Row], spec: &LookupSpec, lookup_rows: &[Row]) {
    let match_fields: &[String] = if spec.match_.is_empty() {
        &spec.key
    } else {
        &spec.match_
    };
    let mut index: HashMap<String, &Row> = HashMap::new();
    for r in lookup_rows {
        index.entry(partition_key(r, match_fields)).or_insert(r);
    }
    for row in rows.iter_mut() {
        if let Some(found) = index.get(&partition_key(row, &spec.key)) {
            let prefix = spec.prefix.as_deref().unwrap_or("");
            if spec.fields.is_empty() {
                for (k, v) in found.iter() {
                    if !match_fields.contains(k) {
                        row.insert(format!("{prefix}{k}"), v.clone());
                    }
                }
            } else {
                for f in &spec.fields {
                    row.insert(
                        format!("{prefix}{f}"),
                        found.get(f).cloned().unwrap_or(Value::Null),
                    );
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Grouping
// ---------------------------------------------------------------------------

enum Acc {
    Sum(f64),
    Avg(f64, u64),
    Min(Option<f64>),
    Max(Option<f64>),
    Count(u64),
    Distinct(HashSet<String>),
    Arg {
        best: Option<(Value, Value)>,
        max: bool,
    },
    Top(HashMap<String, (f64, Value)>, bool),
    First(Option<Value>),
    SumTop(Vec<f64>, usize),
}

impl Acc {
    fn new(m: &MeasureSpec) -> Result<Self, EngineError> {
        Ok(match m.agg.as_str() {
            "sum" => Acc::Sum(0.0),
            "avg" => Acc::Avg(0.0, 0),
            "min" => Acc::Min(None),
            "max" => Acc::Max(None),
            "count" => Acc::Count(0),
            "count_distinct" => Acc::Distinct(HashSet::new()),
            "argmax" => Acc::Arg {
                best: None,
                max: true,
            },
            "argmin" => Acc::Arg {
                best: None,
                max: false,
            },
            "top" => Acc::Top(HashMap::new(), false),
            "top_share" => Acc::Top(HashMap::new(), true),
            "first" => Acc::First(None),
            "sum_top" => Acc::SumTop(Vec::new(), m.n.unwrap_or(10)),
            other => {
                return Err(EngineError::Spec(format!(
                    "unknown aggregation '{}' in measure '{}'",
                    other, m.name
                )))
            }
        })
    }

    fn add(&mut self, m: &MeasureSpec, row: &Row) {
        let fv = m.field.as_deref().map(|f| field(row, f));
        match self {
            Acc::Sum(s) => {
                if let Some(x) = fv.and_then(as_f64) {
                    *s += x;
                }
            }
            Acc::Avg(s, n) => {
                if let Some(x) = fv.and_then(as_f64) {
                    *s += x;
                    *n += 1;
                }
            }
            Acc::Min(cur) => {
                if let Some(x) = fv.and_then(as_f64) {
                    *cur = Some(cur.map_or(x, |c| c.min(x)));
                }
            }
            Acc::Max(cur) => {
                if let Some(x) = fv.and_then(as_f64) {
                    *cur = Some(cur.map_or(x, |c| c.max(x)));
                }
            }
            Acc::Count(n) => {
                if fv.is_none_or(|v| !v.is_null()) {
                    *n += 1;
                }
            }
            Acc::Distinct(set) => {
                let key = if m.fields.is_empty() {
                    key_of(fv.unwrap_or(&Value::Null))
                } else {
                    partition_key(row, &m.fields)
                };
                set.insert(key);
            }
            Acc::Arg { best, max } => {
                let by =
                    m.by.as_deref()
                        .map(|b| field(row, b).clone())
                        .unwrap_or(Value::Null);
                if by.is_null() {
                    return;
                }
                let better = match best {
                    None => true,
                    Some((cur, _)) => {
                        let ord = compare_values(&by, cur);
                        if *max {
                            ord == Ordering::Greater
                        } else {
                            ord == Ordering::Less
                        }
                    }
                };
                if better {
                    *best = Some((by, fv.cloned().unwrap_or(Value::Null)));
                }
            }
            Acc::Top(map, _) => {
                let cat = fv.cloned().unwrap_or(Value::Null);
                let w =
                    m.by.as_deref()
                        .map(|b| as_f64(field(row, b)).unwrap_or(0.0))
                        .unwrap_or(1.0);
                let e = map.entry(key_of(&cat)).or_insert((0.0, cat));
                e.0 += w;
            }
            Acc::First(cur) => {
                if cur.is_none() {
                    *cur = fv.cloned();
                }
            }
            Acc::SumTop(values, _) => {
                if let Some(x) = fv.and_then(as_f64) {
                    values.push(x);
                }
            }
        }
    }

    fn finish(&self) -> Value {
        match self {
            Acc::Sum(s) => number(*s),
            Acc::Avg(s, n) => {
                if *n == 0 {
                    Value::Null
                } else {
                    number(*s / *n as f64)
                }
            }
            Acc::Min(v) | Acc::Max(v) => v.map(number).unwrap_or(Value::Null),
            Acc::Count(n) => Value::Number((*n).into()),
            Acc::Distinct(set) => Value::Number((set.len() as u64).into()),
            Acc::Arg { best, .. } => best.as_ref().map(|(_, v)| v.clone()).unwrap_or(Value::Null),
            Acc::Top(map, share) => {
                let total: f64 = map.values().map(|(w, _)| *w).sum();
                let best = map.values().max_by(|a, b| {
                    a.0.partial_cmp(&b.0)
                        .unwrap_or(Ordering::Equal)
                        .then_with(|| key_of(&b.1).cmp(&key_of(&a.1)))
                });
                match (best, share) {
                    (None, _) => Value::Null,
                    (Some((_, cat)), false) => cat.clone(),
                    (Some((w, _)), true) => {
                        if total > 0.0 {
                            number(w / total * 100.0)
                        } else {
                            Value::Null
                        }
                    }
                }
            }
            Acc::First(v) => v.clone().unwrap_or(Value::Null),
            Acc::SumTop(values, n) => {
                let mut sorted = values.clone();
                sorted.sort_by(|a, b| b.partial_cmp(a).unwrap_or(Ordering::Equal));
                number(sorted.iter().take(*n).sum())
            }
        }
    }
}

/// Runs one grouping stage.
pub fn run_stage<'a>(
    rows: impl Iterator<Item = &'a Row>,
    stage: &StageSpec,
    scalars: &HashMap<String, f64>,
) -> Result<Vec<Row>, EngineError> {
    let mut order: Vec<String> = Vec::new();
    let mut groups: HashMap<String, (Row, Vec<Acc>)> = HashMap::new();
    for row in rows {
        let key = partition_key(row, &stage.group_by);
        if !groups.contains_key(&key) {
            let mut dims = Row::new();
            for g in &stage.group_by {
                dims.insert(g.clone(), field(row, g).clone());
            }
            let accs = stage
                .measures
                .iter()
                .map(Acc::new)
                .collect::<Result<Vec<_>, _>>()?;
            groups.insert(key.clone(), (dims, accs));
            order.push(key.clone());
        }
        let (_, accs) = groups.get_mut(&key).unwrap();
        for (m, acc) in stage.measures.iter().zip(accs.iter_mut()) {
            if m.where_.is_empty() || matches_all(row, &m.where_)? {
                acc.add(m, row);
            }
        }
    }
    // A stage without grouping always returns one row, also when there is no input.
    if stage.group_by.is_empty() && groups.is_empty() {
        let accs = stage
            .measures
            .iter()
            .map(Acc::new)
            .collect::<Result<Vec<_>, _>>()?;
        groups.insert(String::new(), (Row::new(), accs));
        order.push(String::new());
    }
    let mut out = Vec::with_capacity(order.len());
    for key in order {
        let (mut dims, accs) = groups.remove(&key).unwrap();
        for (m, acc) in stage.measures.iter().zip(accs.iter()) {
            dims.insert(m.name.clone(), acc.finish());
        }
        out.push(dims);
    }
    apply_derived(&mut out, &stage.derived, &stage.partition_by, scalars)?;
    for w in &stage.windows {
        apply_window(&mut out, w)?;
    }
    if !stage.having.is_empty() {
        let mut kept = Vec::with_capacity(out.len());
        for r in out {
            if matches_all(&r, &stage.having)? {
                kept.push(r);
            }
        }
        out = kept;
    }
    Ok(out)
}

// ---------------------------------------------------------------------------
// Calculators
// ---------------------------------------------------------------------------

/// `series`: generates rows over an x range and evaluates one formula per series.
/// `{"name":"series","x":{"name":"k","from":0,"to":140,"step":2},"exprs":[{"name":"q","expr":"..."}]}`
pub fn calc_series(cfg: &Value, scalars: &HashMap<String, f64>) -> Result<Vec<Row>, EngineError> {
    let x = cfg
        .get("x")
        .ok_or_else(|| EngineError::Spec("series needs 'x'".into()))?;
    let xname = x
        .get("name")
        .and_then(Value::as_str)
        .unwrap_or("x")
        .to_string();
    let from = x.get("from").and_then(Value::as_f64).unwrap_or(0.0);
    let to = x
        .get("to")
        .and_then(Value::as_f64)
        .ok_or_else(|| EngineError::Spec("series needs x.to".into()))?;
    let step = x.get("step").and_then(Value::as_f64).unwrap_or(1.0);
    if step <= 0.0 || (to - from) / step > 10_000.0 {
        return Err(EngineError::Spec("series step is not valid".into()));
    }
    let exprs = cfg
        .get("exprs")
        .and_then(Value::as_array)
        .ok_or_else(|| EngineError::Spec("series needs 'exprs'".into()))?
        .iter()
        .map(|e| {
            let name = e
                .get("name")
                .and_then(Value::as_str)
                .unwrap_or("y")
                .to_string();
            let text = e.get("expr").and_then(Value::as_str).unwrap_or("0");
            CompiledExpr::compile(text).map(|c| (name, c))
        })
        .collect::<Result<Vec<_>, _>>()?;
    let mut rows = Vec::new();
    let n = ((to - from) / step).round() as usize;
    for i in 0..=n {
        let xv = from + step * i as f64;
        let mut row = Row::new();
        row.insert(xname.clone(), number((xv * 1e9).round() / 1e9));
        for (name, expr) in &exprs {
            let v = expr.eval(&|id: &str| {
                if id == xname {
                    return Some(number(xv));
                }
                row.get(id)
                    .cloned()
                    .or_else(|| scalars.get(id).map(|f| number(*f)))
            })?;
            row.insert(name.clone(), v);
        }
        rows.push(row);
    }
    Ok(rows)
}

// ---------------------------------------------------------------------------
// Time buckets and moving windows
// ---------------------------------------------------------------------------

/// Bucket label of one value: `YYYY-MM-DDTHH:00` (hour), `YYYY-MM-DD` (day and the Monday of
/// an ISO week) or `YYYY-MM` (month). None for a value that is not a date or time.
pub fn bucket_of(v: &Value, unit: &str, utc_offset_minutes: Option<i32>) -> Option<String> {
    use chrono::{Datelike, Duration, FixedOffset, NaiveDate, Timelike};
    let text = v.as_str()?;
    let (date, hour) = match chrono::DateTime::parse_from_rfc3339(text) {
        Ok(t) => {
            let t = match utc_offset_minutes {
                Some(m) => t.with_timezone(&FixedOffset::east_opt(m * 60)?),
                None => t,
            };
            (t.date_naive(), Some(t.hour()))
        }
        Err(_) => (NaiveDate::parse_from_str(text.get(..10)?, "%Y-%m-%d").ok()?, None),
    };
    Some(match unit {
        "hour" => format!("{}T{:02}:00", date.format("%Y-%m-%d"), hour?),
        "day" => date.format("%Y-%m-%d").to_string(),
        "week" => (date - Duration::days(date.weekday().num_days_from_monday() as i64))
            .format("%Y-%m-%d")
            .to_string(),
        "month" => format!("{:04}-{:02}", date.year(), date.month()),
        _ => return None,
    })
}

pub fn apply_bucket(rows: &mut [Row], b: &BucketSpec) -> Result<(), EngineError> {
    if !BUCKET_UNITS.contains(&b.unit.as_str()) {
        return Err(EngineError::Spec(format!("unknown bucket unit '{}'", b.unit)));
    }
    for r in rows.iter_mut() {
        let label = r.get(&b.field).and_then(|v| bucket_of(v, &b.unit, b.utc_offset_minutes));
        r.insert(b.name.clone(), label.map(Value::String).unwrap_or(Value::Null));
    }
    Ok(())
}

/// Trailing window per partition. Rows keep their order; nulls do not enter the window.
pub fn apply_window(rows: &mut [Row], w: &WindowSpec) -> Result<(), EngineError> {
    if !WINDOW_AGGREGATIONS.contains(&w.agg.as_str()) {
        return Err(EngineError::Spec(format!("unknown window aggregation '{}'", w.agg)));
    }
    if w.size == 0 || w.size > MAX_WINDOW {
        return Err(EngineError::Spec(format!("window size must be 1 to {MAX_WINDOW}")));
    }
    let mut order: Vec<usize> = (0..rows.len()).collect();
    order.sort_by(|&a, &b| {
        partition_key(&rows[a], &w.partition_by)
            .cmp(&partition_key(&rows[b], &w.partition_by))
            .then_with(|| compare_values(field(&rows[a], &w.order_by), field(&rows[b], &w.order_by)))
    });
    let mut results = vec![Value::Null; rows.len()];
    let mut start = 0;
    while start < order.len() {
        let key = partition_key(&rows[order[start]], &w.partition_by);
        let mut end = start;
        while end < order.len() && partition_key(&rows[order[end]], &w.partition_by) == key {
            end += 1;
        }
        for i in start..end {
            let from = if i + 1 >= start + w.size { i + 1 - w.size } else { start };
            let values: Vec<f64> = order[from..=i].iter().filter_map(|&r| as_f64(field(&rows[r], &w.field))).collect();
            let v = if values.is_empty() {
                f64::NAN
            } else {
                match w.agg.as_str() {
                    "avg" => values.iter().sum::<f64>() / values.len() as f64,
                    "sum" => values.iter().sum(),
                    "min" => values.iter().copied().fold(f64::INFINITY, f64::min),
                    _ => values.iter().copied().fold(f64::NEG_INFINITY, f64::max),
                }
            };
            results[order[i]] = number(v);
        }
        start = end;
    }
    for (r, v) in rows.iter_mut().zip(results) {
        r.insert(w.name.clone(), v);
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Pipeline
// ---------------------------------------------------------------------------

/// Applies the static conditions and the client filters.
pub fn select_rows<'a>(
    base: &'a [Row],
    spec: &DatasetSpec,
    filters: &[FilterParam],
) -> Result<Vec<&'a Row>, EngineError> {
    let mut out = Vec::new();
    for r in base {
        if !matches_all(r, &spec.where_)? {
            continue;
        }
        if filters.iter().all(|f| matches_filter(r, f)) {
            out.push(r);
        }
    }
    Ok(out)
}

/// Runs calculator or stages, final derived expressions, having, sort and limit.
/// `base` holds the source rows after lookups and row expressions.
pub fn compute_rows(
    base: &[Row],
    spec: &DatasetSpec,
    filters: &[FilterParam],
    scalars: &HashMap<String, f64>,
) -> Result<Vec<Row>, EngineError> {
    let calc_name = spec
        .calculator
        .as_ref()
        .and_then(|c| c.get("name"))
        .and_then(Value::as_str);
    let mut rows: Vec<Row> = match calc_name {
        Some("series") => calc_series(spec.calculator.as_ref().unwrap(), scalars)?,
        Some(other) => return Err(EngineError::Spec(format!("unknown calculator '{}'", other))),
        None => {
            let selected = select_rows(base, spec, filters)?;
            if spec.stages.is_empty() {
                selected.into_iter().cloned().collect()
            } else {
                let mut current = run_stage(selected.into_iter(), &spec.stages[0], scalars)?;
                for stage in &spec.stages[1..] {
                    current = run_stage(current.iter(), stage, scalars)?;
                }
                current
            }
        }
    };
    apply_derived(&mut rows, &spec.derived, &[], scalars)?;
    if !spec.having.is_empty() {
        let mut kept = Vec::with_capacity(rows.len());
        for r in rows {
            if matches_all(&r, &spec.having)? {
                kept.push(r);
            }
        }
        rows = kept;
    }
    if !spec.sort.is_empty() {
        rows.sort_by(|a, b| {
            for s in &spec.sort {
                let ord = compare_values(field(a, &s.field), field(b, &s.field));
                let ord = if s.desc { ord.reverse() } else { ord };
                if ord != Ordering::Equal {
                    return ord;
                }
            }
            Ordering::Equal
        });
    }
    if let Some(limit) = spec.limit {
        rows.truncate(limit);
    }
    Ok(rows)
}

/// Applies lookups and row expressions to the raw source rows.
pub fn prepare_base(
    source: &[Row],
    spec: &DatasetSpec,
    lookup_rows: &LookupLoader<'_>,
    scalars: &HashMap<String, f64>,
) -> Result<Vec<Row>, EngineError> {
    let mut rows: Vec<Row> = source.to_vec();
    for l in &spec.lookups {
        let lr = lookup_rows(&l.collection)?;
        apply_lookup(&mut rows, l, &lr);
    }
    for b in &spec.buckets {
        apply_bucket(&mut rows, b)?;
    }
    apply_derived(&mut rows, &spec.row_derived, &[], scalars)?;
    Ok(rows)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn rows(v: Value) -> Vec<Row> {
        v.as_array()
            .unwrap()
            .iter()
            .map(|r| r.as_object().unwrap().clone())
            .collect()
    }

    fn spec(v: Value) -> DatasetSpec {
        serde_json::from_value(v).unwrap()
    }

    fn sample() -> Vec<Row> {
        rows(json!([
            {"date": "2026-09-26", "hour": 7, "provider": "ollama", "task": "chat", "tokens": 10},
            {"date": "2026-09-26", "hour": 7, "provider": "ollama", "task": "code", "tokens": 5},
            {"date": "2026-09-27", "hour": 7, "provider": "openai", "task": "chat", "tokens": 20},
            {"date": "2026-09-27", "hour": 8, "provider": "openai", "task": "embed", "tokens": 5},
            {"date": "2026-09-27", "hour": 8, "provider": "ollama", "task": "chat", "tokens": 10}
        ]))
    }

    #[test]
    fn groups_with_measures_and_share() {
        let s = spec(json!({
            "title": {"en": "t"}, "fields": [],
            "stages": [{"group_by": ["provider"], "measures": [
                {"name": "volume", "agg": "sum", "field": "tokens"},
                {"name": "days", "agg": "count_distinct", "field": "date"},
                {"name": "chat", "agg": "sum", "field": "tokens", "where": [{"field": "task", "op": "eq", "value": "chat"}]}
            ], "derived": [{"name": "share", "expr": "volume / sum_volume * 100"}]}],
            "sort": [{"field": "volume", "desc": true}]
        }));
        let mut data = sample();
        data.push(
            rows(
                json!([{"date": "2026-09-28", "hour": 9, "provider": "openai", "task": "code", "tokens": 15}]),
            )
            .remove(0),
        );
        let out = compute_rows(&data, &s, &[], &HashMap::new()).unwrap();
        assert_eq!(out.len(), 2);
        assert_eq!(out[0]["provider"], json!("openai"));
        assert_eq!(out[0]["volume"], json!(40.0));
        assert_eq!(out[1]["days"], json!(2));
        assert_eq!(out[1]["chat"], json!(20.0));
        assert!((out[0]["share"].as_f64().unwrap() - 40.0 / 65.0 * 100.0).abs() < 1e-9);
    }

    #[test]
    fn empty_group_by_gives_one_row_even_without_data() {
        let s = spec(json!({"title": {"en": "t"}, "fields": [],
            "stages": [{"measures": [{"name": "total", "agg": "sum", "field": "tokens"},
                                      {"name": "hours", "agg": "count_distinct", "fields": ["date", "hour"]}]}]}));
        let out = compute_rows(&sample(), &s, &[], &HashMap::new()).unwrap();
        assert_eq!(out[0]["total"], json!(50.0));
        assert_eq!(out[0]["hours"], json!(3));
        let none = compute_rows(&[], &s, &[], &HashMap::new()).unwrap();
        assert_eq!(none.len(), 1);
        assert_eq!(none[0]["total"], json!(0.0));
    }

    #[test]
    fn client_filters_in_and_range() {
        let s = spec(json!({"title": {"en": "t"}, "fields": [],
            "stages": [{"measures": [{"name": "total", "agg": "sum", "field": "tokens"}]}]}));
        let f = vec![
            FilterParam::In {
                field: "task".into(),
                values: vec!["chat".into()],
            },
            FilterParam::Range {
                field: "date".into(),
                from: Some("2026-09-27".into()),
                to: None,
            },
        ];
        let out = compute_rows(&sample(), &s, &f, &HashMap::new()).unwrap();
        assert_eq!(out[0]["total"], json!(30.0));
        let h = vec![FilterParam::Range {
            field: "hour".into(),
            from: Some("8".into()),
            to: Some("8".into()),
        }];
        let out = compute_rows(&sample(), &s, &h, &HashMap::new()).unwrap();
        assert_eq!(out[0]["total"], json!(15.0));
    }

    #[test]
    fn second_stage_with_argmax_and_partition() {
        let s = spec(json!({"title": {"en": "t"}, "fields": [], "stages": [
            {"group_by": ["hour"], "measures": [{"name": "vol", "agg": "sum", "field": "tokens"},
                                                  {"name": "days", "agg": "count_distinct", "field": "date"}],
             "derived": [{"name": "avg", "expr": "vol / days"}]},
            {"measures": [{"name": "peak_hour", "agg": "argmax", "field": "hour", "by": "avg"},
                          {"name": "peak", "agg": "max", "field": "avg"}]}
        ]}));
        let out = compute_rows(&sample(), &s, &[], &HashMap::new()).unwrap();
        assert_eq!(out[0]["peak_hour"], json!(7));
        assert_eq!(out[0]["peak"], json!(17.5));

        let p = spec(json!({"title": {"en": "t"}, "fields": [], "stages": [
            {"group_by": ["provider", "task"], "measures": [{"name": "vol", "agg": "sum", "field": "tokens"}],
             "partition_by": ["provider"], "derived": [{"name": "share", "expr": "vol / psum_vol * 100"}]}],
            "sort": [{"field": "provider"}, {"field": "task"}]}));
        let out = compute_rows(&sample(), &p, &[], &HashMap::new()).unwrap();
        assert_eq!(out[0]["share"], json!(80.0)); // ollama chat 20 of 25
        assert_eq!(out[1]["share"], json!(20.0)); // ollama code 5 of 25
    }

    #[test]
    fn top_and_top_share() {
        let s = spec(
            json!({"title": {"en": "t"}, "fields": [], "stages": [{"group_by": ["provider"], "measures": [
            {"name": "dominant", "agg": "top", "field": "task", "by": "tokens"},
            {"name": "dominant_share", "agg": "top_share", "field": "task", "by": "tokens"}]}],
            "sort": [{"field": "provider"}]}),
        );
        let out = compute_rows(&sample(), &s, &[], &HashMap::new()).unwrap();
        assert_eq!(out[0]["dominant"], json!("chat"));
        assert_eq!(out[0]["dominant_share"], json!(80.0));
    }

    #[test]
    fn lookups_row_derived_refs_and_expr_field() {
        let mut base = sample();
        let tiers = rows(json!([{"provider": "ollama", "tier": "local"}, {"provider": "openai", "tier": "cloud"}]));
        let l: LookupSpec =
            serde_json::from_value(json!({"collection": "c", "key": ["provider"]})).unwrap();
        apply_lookup(&mut base, &l, &tiers);
        assert_eq!(base[0]["tier"], json!("local"));
        let lp: LookupSpec = serde_json::from_value(
            json!({"collection": "c", "key": ["provider"], "fields": ["tier"], "prefix": "from_"}),
        )
        .unwrap();
        apply_lookup(&mut base, &lp, &tiers);
        assert_eq!(base[2]["from_tier"], json!("cloud"));

        let s = spec(json!({"title": {"en": "t"}, "fields": [],
            "row_derived": [{"name": "period", "expr": "if(hour < 8, \"am\", \"pm\")"}]}));
        let mut b2 = sample();
        apply_derived(&mut b2, &s.row_derived, &[], &HashMap::new()).unwrap();
        assert_eq!(b2[3]["period"], json!("pm"));

        let m = rows(json!([{"model": "u", "f": "rate * base / math::exp(1)", "rate": 60, "base": 30}]));
        let mut mm = m.clone();
        let d: Vec<DerivedSpec> =
            serde_json::from_value(json!([{"name": "q", "expr_field": "f"}])).unwrap();
        apply_derived(&mut mm, &d, &[], &HashMap::new()).unwrap();
        let q = mm[0]["q"].as_f64().unwrap();
        assert!((q - 662.18).abs() < 0.01);

        let mut scal = HashMap::new();
        scal.insert("window_hours".to_string(), 201.0);
        let r = spec(json!({"title": {"en": "t"}, "fields": [],
            "stages": [{"measures": [{"name": "total", "agg": "sum", "field": "tokens"}],
                        "derived": [{"name": "per_24h", "expr": "total / (window_hours / 24)"}]}]}));
        let out = compute_rows(&sample(), &r, &[], &scal).unwrap();
        assert!((out[0]["per_24h"].as_f64().unwrap() - 50.0 / (201.0 / 24.0)).abs() < 1e-9);
    }

    #[test]
    fn series_calculator() {
        let mut scal = HashMap::new();
        scal.insert("rate".into(), 60.0);
        scal.insert("cap".into(), 140.0);
        let cfg = json!({"name": "series", "x": {"name": "k", "from": 0, "to": 140, "step": 70},
                         "exprs": [{"name": "q", "expr": "k * rate * (1 - k / cap)"}]});
        let out = calc_series(&cfg, &scal).unwrap();
        assert_eq!(out.len(), 3);
        assert_eq!(out[1]["q"], json!(2100.0));
    }

    #[test]
    fn sum_top_adds_the_largest_values() {
        let s = spec(json!({"title": {"en": "t"}, "fields": [], "stages": [
            {"group_by": ["provider"], "measures": [{"name": "vol", "agg": "sum", "field": "tokens"}]},
            {"measures": [{"name": "top1", "agg": "sum_top", "field": "vol", "n": 1},
                          {"name": "all", "agg": "sum", "field": "vol"}]}]}));
        let out = compute_rows(&sample(), &s, &[], &HashMap::new()).unwrap();
        assert_eq!(out[0]["top1"], json!(25.0));
        assert_eq!(out[0]["all"], json!(50.0));
    }

    #[test]
    fn unknown_operator_is_an_error() {
        let s = spec(
            json!({"title": {"en": "t"}, "fields": [], "where": [{"field": "x", "op": "like", "value": 1}]}),
        );
        assert!(compute_rows(&sample(), &s, &[], &HashMap::new()).is_err());
    }

    #[test]
    fn time_buckets_keep_or_shift_the_offset() {
        let t = json!("2026-10-20T23:30:00+07:00");
        assert_eq!(bucket_of(&t, "hour", None).as_deref(), Some("2026-10-20T23:00"));
        assert_eq!(bucket_of(&t, "day", None).as_deref(), Some("2026-10-20"));
        // The same instant in UTC is still the 20th, 16:30.
        assert_eq!(bucket_of(&t, "hour", Some(0)).as_deref(), Some("2026-10-20T16:00"));
        // 23:30 at +07:00 is the next day at +09:00.
        assert_eq!(bucket_of(&t, "day", Some(540)).as_deref(), Some("2026-10-21"));
        // ISO week starts on Monday (2026-10-19); a plain date works for day, week and month.
        assert_eq!(bucket_of(&json!("2026-10-25"), "week", None).as_deref(), Some("2026-10-19"));
        assert_eq!(bucket_of(&json!("2026-10-25"), "month", None).as_deref(), Some("2026-10"));
        assert_eq!(bucket_of(&json!("2026-10-25"), "hour", None), None, "a date has no hour");
        assert_eq!(bucket_of(&json!("yesterday"), "day", None), None);
    }

    #[test]
    fn moving_window_per_partition_with_nulls_and_empty_groups() {
        let mut r = rows(json!([
            {"p": "ollama", "d": 3, "v": 30}, {"p": "ollama", "d": 1, "v": 10}, {"p": "ollama", "d": 2, "v": null},
            {"p": "openai", "d": 1, "v": 5}
        ]));
        let w: WindowSpec = serde_json::from_value(json!({"name": "m", "agg": "avg", "field": "v", "size": 2, "order_by": "d", "partition_by": ["p"]})).unwrap();
        apply_window(&mut r, &w).unwrap();
        // Order kept; d=2 sees (10, null) = 10; d=3 sees (null, 30) = 30; openai alone = 5.
        assert_eq!(r[0]["m"], json!(30.0));
        assert_eq!(r[1]["m"], json!(10.0));
        assert_eq!(r[2]["m"], json!(10.0));
        assert_eq!(r[3]["m"], json!(5.0));
        let bad: WindowSpec = serde_json::from_value(json!({"name": "m", "agg": "median", "field": "v", "size": 2, "order_by": "d"})).unwrap();
        assert!(apply_window(&mut r, &bad).is_err());
    }

    #[test]
    fn division_by_zero_and_empty_input_give_null_not_infinity() {
        let s = spec(json!({"title": {"en": "t"}, "fields": [],
            "stages": [{"measures": [{"name": "n", "agg": "count"}, {"name": "ok", "agg": "count",
                "where": [{"field": "task", "op": "eq", "value": "none"}]}],
                "derived": [{"name": "rate", "expr": "ok / n * 100"}]}]}));
        let out = compute_rows(&[], &s, &[], &HashMap::new()).unwrap();
        assert_eq!(out[0]["n"], json!(0));
        assert_eq!(out[0]["rate"], Value::Null, "0 / 0 is null");
    }
}

