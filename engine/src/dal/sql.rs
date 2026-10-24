//! SQL access for PostgreSQL `asodya_reports` (production) and SQLite (tests).
//!
//! Both use the same queries through the sqlx `Any` driver. The few dialect differences
//! (JSONB and UUID casts, booleans, the current time) come from [`Db`] helper methods.
//! The engine never runs DDL here: `scripts/migrate.sh` owns the PostgreSQL schema.

use std::sync::Once;
use std::time::Duration;

use sqlx::any::{AnyPoolOptions, AnyRow};
use sqlx::{AnyPool, Row};

use crate::core::error::ReportError;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Dialect {
    Postgres,
    Sqlite,
}

pub struct Db {
    pub pool: AnyPool,
    pub dialect: Dialect,
}

/// Tables and columns that the engine reads and writes. The startup check compares them
/// with the live database and stops the engine when one is missing.
pub const REQUIRED_SCHEMA: &[(&str, &[&str])] = &[
    (
        "catalog_projects",
        &[
            "slug", "name", "tagline", "description", "theme", "is_active", "website_url", "repository_url",
            "sort_order", "domain_project_id", "updated_at",
        ],
    ),
    (
        "reports",
        &["project_slug", "slug", "title", "description", "metadata", "visibility", "discoverable", "updated_at"],
    ),
    (
        "datasets",
        &["project_slug", "report_slug", "dataset_id", "data_tier", "calculation_id", "calculation_version", "visibility", "discoverable"],
    ),
    (
        "calculation_versions",
        &[
            "project_slug", "calculation_id", "version", "status", "input_schema", "input_schema_version", "inputs",
            "definition", "needs_review", "created_at", "published_at",
        ],
    ),
    ("user_project_roles", &["user_uuid", "app_name", "is_project_admin"]),
    ("fixture_manifest", &["manifest_id", "entity_type", "entity_id", "created_at"]),
    (
        "resource_grants",
        &["id", "user_uuid", "resource_type", "project_slug", "report_slug", "card_id", "granted_by", "created_at"],
    ),
    (
        "schema_versions",
        &["project_slug", "schema_name", "version", "status", "description", "created_at", "published_at"],
    ),
    (
        "schema_fields",
        &["project_slug", "schema_name", "version", "field_path", "field_type", "is_required", "description"],
    ),
];

static DRIVERS: Once = Once::new();

impl Db {
    /// Opens a lazy pool. No query runs here, so a down database does not stop the process;
    /// [`Db::check_schema`] reports it.
    pub fn connect(url: &str) -> Result<Self, ReportError> {
        DRIVERS.call_once(sqlx::any::install_default_drivers);
        let dialect = if url.starts_with("sqlite:") {
            Dialect::Sqlite
        } else {
            Dialect::Postgres
        };
        let options = AnyPoolOptions::new().acquire_timeout(Duration::from_secs(5));
        // One SQLite connection keeps every test query on the same database file.
        let options = match dialect {
            Dialect::Sqlite => options.max_connections(1).after_connect(|conn, _| {
                Box::pin(async move {
                    sqlx::query("PRAGMA foreign_keys = ON").execute(conn).await?;
                    Ok(())
                })
            }),
            Dialect::Postgres => options.max_connections(16),
        };
        let pool = options
            .connect_lazy(url)
            .map_err(|e| ReportError::Unavailable(format!("database configuration: {e}")))?;
        Ok(Self { pool, dialect })
    }

    /// `$n` as JSON input.
    pub fn json_in(&self, n: usize) -> String {
        match self.dialect {
            Dialect::Postgres => format!("CAST(${n} AS JSONB)"),
            Dialect::Sqlite => format!("${n}"),
        }
    }

    /// `$n` as UUID input.
    pub fn uuid_in(&self, n: usize) -> String {
        match self.dialect {
            Dialect::Postgres => format!("CAST(${n} AS UUID)"),
            Dialect::Sqlite => format!("${n}"),
        }
    }

    /// A JSON, UUID or time column read as text.
    pub fn text(&self, column: &str) -> String {
        format!("CAST({column} AS TEXT)")
    }

    /// A nullable column read as text; NULL becomes ''. The sqlx 0.7 `Any` driver cannot
    /// decode SQL NULL, so every nullable column goes through this (see [`opt_col`]).
    pub fn opt_text(&self, column: &str) -> String {
        format!("COALESCE(CAST({column} AS TEXT), '')")
    }

    /// A boolean column read as an integer (0 or 1).
    pub fn flag(&self, column: &str) -> String {
        format!("CASE WHEN {column} THEN 1 ELSE 0 END")
    }

    pub fn now(&self) -> &'static str {
        match self.dialect {
            Dialect::Postgres => "now()",
            Dialect::Sqlite => "CURRENT_TIMESTAMP",
        }
    }

    pub async fn health(&self) -> bool {
        sqlx::query("SELECT 1").fetch_one(&self.pool).await.is_ok()
    }

    /// Fails when a required table or column is missing. It changes nothing.
    pub async fn check_schema(&self) -> Result<(), ReportError> {
        let mut missing = Vec::new();
        for (table, columns) in REQUIRED_SCHEMA {
            let present = self.columns(table).await?;
            for c in *columns {
                if !present.iter().any(|p| p == c) {
                    missing.push(format!("{table}.{c}"));
                }
            }
        }
        if missing.is_empty() {
            Ok(())
        } else {
            Err(ReportError::Unavailable(format!(
                "the database schema is missing or outdated ({}). Run scripts/migrate.sh, then start the engine again",
                missing.join(", ")
            )))
        }
    }

    async fn columns(&self, table: &str) -> Result<Vec<String>, ReportError> {
        let rows: Vec<AnyRow> = match self.dialect {
            Dialect::Postgres => {
                sqlx::query(
                    "SELECT CAST(column_name AS TEXT) AS name FROM information_schema.columns \
                     WHERE table_schema = current_schema() AND table_name = $1",
                )
                .bind(table)
                .fetch_all(&self.pool)
                .await?
            }
            Dialect::Sqlite => {
                sqlx::query("SELECT name FROM pragma_table_info($1)")
                    .bind(table)
                    .fetch_all(&self.pool)
                    .await?
            }
        };
        rows.iter()
            .map(|r| r.try_get::<String, _>("name").map_err(ReportError::from))
            .collect()
    }

    /// Creates the test schema in a SQLite database. Production never calls this.
    pub async fn create_sqlite_test_schema(&self) -> Result<(), ReportError> {
        if self.dialect != Dialect::Sqlite {
            return Err(ReportError::Internal("the test schema is only for SQLite".into()));
        }
        sqlx::raw_sql(include_str!("../../migrations/sqlite/test_schema.sql"))
            .execute(&self.pool)
            .await?;
        Ok(())
    }
}

/// Reads a text column that holds JSON.
pub fn json_col<T: serde::de::DeserializeOwned + Default>(row: &AnyRow, column: &str) -> Result<T, ReportError> {
    let text: String = row.try_get(column)?;
    if text.trim().is_empty() {
        return Ok(T::default());
    }
    serde_json::from_str(&text).map_err(|e| ReportError::Database(format!("column {column} is not valid JSON: {e}")))
}

/// Reads a column selected with [`Db::opt_text`]: '' is None.
pub fn opt_col(row: &AnyRow, column: &str) -> Result<Option<String>, ReportError> {
    let v: String = row.try_get(column)?;
    Ok(if v.is_empty() { None } else { Some(v) })
}

pub fn flag_col(row: &AnyRow, column: &str) -> Result<bool, ReportError> {
    Ok(row.try_get::<i64, _>(column)? != 0)
}
