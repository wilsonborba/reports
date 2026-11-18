//! Rows for the declared components of calculation definitions.
//! JSON exists only in memory at the API boundary. Scalar SQL values have explicit types.
use crate::core::error::ReportError;
use serde_json::{Map, Value};
use sqlx::{Any, AnyConnection, Row, Transaction};
use std::{collections::HashMap, future::Future, pin::Pin};

pub struct Shape {
    pub table: &'static str,
    pub mode: &'static str,
    pub scalar: bool,
    pub dynamic: bool,
    pub optional: bool,
    pub fields: &'static [(&'static str, &'static str)],
    pub children: &'static [(&'static str, Shape)],
}
type Task<'a, T> = Pin<Box<dyn Future<Output = Result<T, ReportError>> + Send + 'a>>;
pub struct Key<'a> {
    pub project: &'a str,
    pub calculation: &'a str,
    pub version: i64,
}

fn scalar_text(v: &Value) -> Result<Option<String>, ReportError> {
    Ok(match v {
        Value::Null => None,
        Value::String(s) => Some(s.clone()),
        Value::Number(n) => Some(n.to_string()),
        Value::Bool(b) => Some(b.to_string()),
        _ => return Err(ReportError::Internal("expected a scalar relational value".into())),
    })
}
fn scalar_value(v: &str, kind: &str) -> Result<Value, ReportError> {
    match kind.trim_end_matches('?') {
        "s" | "string" => Ok(Value::String(v.into())),
        "n" | "number" | "b" | "bool" => serde_json::from_str(v).map_err(|e| ReportError::Database(e.to_string())),
        _ => Ok(Value::Null),
    }
}
fn insert<'a>(
    conn: &'a mut AnyConnection,
    key: &'a Key<'a>,
    shape: &'static Shape,
    row: String,
    parent: String,
    position: i64,
    map_key: String,
    value: &'a Value,
) -> Task<'a, ()> {
    Box::pin(async move {
        let mut names = vec![
            "project_slug".to_string(),
            "calculation_id".into(),
            "version".into(),
            "row_key".into(),
            "parent_key".into(),
            "position".into(),
            "map_key".into(),
        ];
        let mut values = Vec::new();
        for (field, _) in shape.fields {
            names.push(format!("\"{field}\""));
            values.push(scalar_text(if shape.scalar { value } else { &value[*field] })?);
        }
        let slots = (1..=names.len())
            .map(|i| {
                if i > 7 {
                    let n = 8 + (i - 8) * 2;
                    let expr = format!("CASE WHEN ${} THEN NULL ELSE ${n} END", n + 1);
                    if shape.fields[i - 8].1.starts_with('n') {
                        format!("CAST(({expr}) AS NUMERIC)")
                    } else {
                        expr
                    }
                } else {
                    format!("${i}")
                }
            })
            .collect::<Vec<_>>()
            .join(",");
        let sql = format!("INSERT INTO {} ({}) VALUES ({slots})", shape.table, names.join(","));
        let mut q = sqlx::query(&sql)
            .bind(key.project)
            .bind(key.calculation)
            .bind(key.version)
            .bind(&row)
            .bind(&parent)
            .bind(position)
            .bind(&map_key);
        for v in values {
            let missing = v.is_none();
            q = q.bind(v.unwrap_or_default()).bind(missing);
        }
        q.execute(&mut *conn).await?;
        for (field, child) in shape.children {
            let v = if *field == "*" { value } else { &value[*field] };
            let base = format!("{row}/{field}");
            save(conn, key, child, base, &row, v).await?;
        }
        Ok(())
    })
}
fn save<'a>(
    conn: &'a mut AnyConnection,
    key: &'a Key<'a>,
    shape: &'static Shape,
    base: String,
    parent: &'a str,
    value: &'a Value,
) -> Task<'a, ()> {
    Box::pin(async move {
        if value.is_null() && shape.optional {
            return Ok(());
        }
        if shape.dynamic {
            return save_dynamic(conn, key, shape, &base, parent, value).await;
        }
        match shape.mode {
            "list" => {
                if let Some(a) = value.as_array() {
                    for (i, v) in a.iter().enumerate() {
                        insert(conn, key, shape, format!("{base}/{i}"), parent.into(), i as i64, String::new(), v)
                            .await?;
                    }
                }
            }
            "map" => {
                if let Some(m) = value.as_object() {
                    for (i, (k, v)) in m.iter().enumerate() {
                        insert(conn, key, shape, format!("{base}/{i}"), parent.into(), i as i64, k.clone(), v).await?;
                    }
                }
            }
            _ => insert(conn, key, shape, base, parent.into(), 0, String::new(), value).await?,
        }
        Ok(())
    })
}
// Arbitrary Value fields occur only in unvalidated drafts and condition operands.
// Container identity and each scalar are rows; no serialized object or list is stored.
fn save_dynamic<'a>(
    conn: &'a mut AnyConnection,
    key: &'a Key<'a>,
    shape: &'static Shape,
    base: &'a str,
    parent: &'a str,
    value: &'a Value,
) -> Task<'a, ()> {
    Box::pin(async move {
        let mut pending = vec![(base.to_string(), String::new(), 0i64, String::new(), value)];
        while let Some((path, node_parent, pos, name, v)) = pending.pop() {
            let kind = match v {
                Value::Object(_) => "object",
                Value::Array(_) => "array",
                Value::Null => "null",
                Value::String(_) => "string",
                Value::Number(_) => "number",
                Value::Bool(_) => "bool",
            };
            let sql=format!("INSERT INTO {} (project_slug,calculation_id,version,row_key,parent_key,position,map_key,node_kind,scalar_value,node_parent_key) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,CASE WHEN $11 THEN NULL ELSE $9 END,NULLIF($10,''))",shape.table);
            let text = if v.is_object() || v.is_array() { None } else { scalar_text(v)? };
            sqlx::query(&sql)
                .bind(key.project)
                .bind(key.calculation)
                .bind(key.version)
                .bind(&path)
                .bind(parent)
                .bind(pos)
                .bind(name)
                .bind(kind)
                .bind(text.clone().unwrap_or_default())
                .bind(node_parent)
                .bind(text.is_none())
                .execute(&mut *conn)
                .await?;
            match v {
                Value::Array(a) => {
                    for (i, v) in a.iter().enumerate().rev() {
                        pending.push((format!("{path}/{i}"), path.clone(), i as i64, String::new(), v));
                    }
                }
                Value::Object(m) => {
                    for (i, (k, v)) in m.iter().enumerate().rev() {
                        pending.push((format!("{path}/{i}"), path.clone(), i as i64, k.clone(), v));
                    }
                }
                _ => {}
            }
        }
        Ok(())
    })
}

pub async fn write(tx: &mut Transaction<'_, Any>, key: &Key<'_>, value: &Value) -> Result<(), ReportError> {
    let shape = &super::calculation_shape::DEFINITION;
    let sql = format!("DELETE FROM {} WHERE project_slug=$1 AND calculation_id=$2 AND version=$3", shape.table);
    sqlx::query(&sql).bind(key.project).bind(key.calculation).bind(key.version).execute(&mut **tx).await?;
    save(&mut **tx, key, shape, "root".into(), "", value).await
}

#[derive(Clone)]
struct Stored {
    key: String,
    parent: String,
    position: i64,
    name: String,
    fields: HashMap<String, Option<String>>,
    kind: String,
    node_parent: String,
}
fn load<'a>(
    conn: &'a mut AnyConnection,
    key: &'a Key<'a>,
    shape: &'static Shape,
) -> Task<'a, HashMap<&'static str, Vec<Stored>>> {
    Box::pin(async move {
        let extra = if shape.dynamic {
            ",node_kind,COALESCE(scalar_value,'') AS scalar_value,COALESCE(node_parent_key,'') AS node_parent_key"
                .into()
        } else {
            shape.fields.iter().map(|(f,_)|format!(",COALESCE(CAST(\"{f}\" AS TEXT),'') AS \"{f}\",CASE WHEN \"{f}\" IS NULL THEN 1 ELSE 0 END AS \"{f}_null\" ")).collect::<String>()
        };
        let sql=format!("SELECT row_key,parent_key,CAST(position AS BIGINT) AS position,map_key{extra} FROM {} WHERE project_slug=$1 AND calculation_id=$2 AND version=$3 ORDER BY position",shape.table);
        let rows =
            sqlx::query(&sql).bind(key.project).bind(key.calculation).bind(key.version).fetch_all(&mut *conn).await?;
        let mut stored = Vec::new();
        for r in rows {
            let mut fields = HashMap::new();
            for (f, _) in shape.fields {
                let missing: i64 = r.try_get(format!("{f}_null").as_str())?;
                fields.insert(f.to_string(), if missing == 1 { None } else { Some(r.try_get(*f)?) });
            }
            if shape.dynamic {
                fields.insert("value".into(), Some(r.try_get("scalar_value")?));
            }
            stored.push(Stored {
                key: r.try_get("row_key")?,
                parent: r.try_get("parent_key")?,
                position: r.try_get("position")?,
                name: r.try_get("map_key")?,
                fields,
                kind: if shape.dynamic { r.try_get("node_kind")? } else { String::new() },
                node_parent: if shape.dynamic { r.try_get("node_parent_key")? } else { String::new() },
            });
        }
        let mut all = HashMap::from([(shape.table, stored)]);
        for (_, child) in shape.children {
            all.extend(load(conn, key, child).await?);
        }
        Ok(all)
    })
}
fn dynamic(rows: &[Stored], row: &Stored) -> Result<Value, ReportError> {
    let mut children = rows.iter().filter(|r| r.node_parent == row.key).collect::<Vec<_>>();
    children.sort_by_key(|r| r.position);
    Ok(match row.kind.as_str() {
        "object" => Value::Object(
            children
                .into_iter()
                .map(|r| Ok((r.name.clone(), dynamic(rows, r)?)))
                .collect::<Result<Map<_, _>, ReportError>>()?,
        ),
        "array" => Value::Array(children.into_iter().map(|r| dynamic(rows, r)).collect::<Result<_, _>>()?),
        "null" => Value::Null,
        k => scalar_value(row.fields["value"].as_deref().unwrap_or(""), k)?,
    })
}
fn decode(shape: &'static Shape, all: &HashMap<&'static str, Vec<Stored>>, parent: &str) -> Result<Value, ReportError> {
    let rows = &all[shape.table];
    if shape.dynamic {
        return rows
            .iter()
            .find(|r| r.parent == parent && r.node_parent.is_empty())
            .map(|r| dynamic(rows, r))
            .transpose()
            .map(|v| v.unwrap_or(Value::Null));
    }
    let selected = rows.iter().filter(|r| r.parent == parent).collect::<Vec<_>>();
    let object = |row: &Stored| -> Result<Value, ReportError> {
        if shape.scalar {
            return row.fields["value"]
                .as_deref()
                .map(|s| scalar_value(s, shape.fields[0].1))
                .transpose()
                .map(|v| v.unwrap_or(Value::Null));
        }
        let mut value = Map::new();
        for (f, k) in shape.fields {
            value.insert(
                (*f).into(),
                row.fields[*f].as_deref().map(|s| scalar_value(s, k)).transpose()?.unwrap_or(Value::Null),
            );
        }
        for (f, child) in shape.children {
            let v = decode(child, all, &row.key)?;
            if *f == "*" {
                return Ok(v);
            }
            value.insert((*f).into(), v);
        }
        Ok(Value::Object(value))
    };
    match shape.mode {
        "list" => selected.into_iter().map(object).collect::<Result<Vec<_>, _>>().map(Value::Array),
        "map" => selected
            .into_iter()
            .map(|r| Ok((r.name.clone(), object(r)?)))
            .collect::<Result<Map<_, _>, ReportError>>()
            .map(Value::Object),
        _ => selected.first().map(|r| object(r)).transpose().map(|v| v.unwrap_or(Value::Null)),
    }
}
pub async fn read(db: &super::sql::Db, key: &Key<'_>) -> Result<Value, ReportError> {
    let mut tx = db.pool.begin().await?;
    if db.dialect == super::sql::Dialect::Postgres {
        sqlx::query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY").execute(&mut *tx).await?;
    }
    let shape = &super::calculation_shape::DEFINITION;
    let all = load(&mut tx, key, shape).await?;
    let result = decode(shape, &all, "")?;
    tx.commit().await?;
    Ok(result)
}
