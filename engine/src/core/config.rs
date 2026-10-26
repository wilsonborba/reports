//! Runtime settings. Secrets come from `.env` (database password, CouchDB password,
//! Redis password, service keys). Non-secret behavior has its defaults here.

use std::collections::BTreeMap;

/// Default listen address: only local processes (the api_for_apps gateway) reach the engine.
pub const DEFAULT_HOST: &str = "127.0.0.1";
pub const DEFAULT_PORT: u16 = 8109;

/// Lifetime of a cached dataset result in Redis (seconds).
pub const DEFAULT_RESULT_TTL_SECS: u64 = 3600;
/// Lifetime of a compute-gate lock in Redis (seconds).
pub const DEFAULT_GATE_TTL_SECS: u64 = 60;
/// Most records that one calculation may read from the document store.
pub const DEFAULT_MAX_SCAN_ROWS: usize = 200_000;
/// Rows held by the in-process collection cache (all collections together).
pub const DEFAULT_ROW_CACHE_ROWS: usize = 500_000;

#[derive(Debug, Clone)]
pub struct Settings {
    pub server_host: String,
    pub server_port: u16,
    pub environment: String,
    /// PostgreSQL `asodya_reports` in production (`postgres://...`), SQLite in tests (`sqlite:...`).
    pub database_url: String,
    pub couchdb_url: String,
    pub couchdb_database: String,
    pub couchdb_user: Option<String>,
    pub couchdb_password: Option<String>,
    pub redis_url: String,
    pub redis_namespace: String,
    /// Key of local operator tools (`x-reports-service-key`), env REPORTS_SERVICE_API_KEY.
    pub service_api_key: String,
    /// Named app keys, env REPORTS_API_KEYS (JSON object: app name to key).
    pub api_keys: BTreeMap<String, String>,
    pub result_ttl_secs: u64,
    pub gate_ttl_secs: u64,
    pub max_scan_rows: usize,
    pub row_cache_rows: usize,
    /// domain_api itself (server to server).
    pub domain_api_url: String,
    /// domain_api through the gateway (browser image links).
    pub domain_public_url: String,
    pub domain_cache_ttl_secs: u64,
    pub domain_timeout_ms: u64,
    /// Browser used only for bounded previews of the original Flutter renderer.
    pub embed_chrome_binary: String,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            server_host: env_or("SERVER_HOST", DEFAULT_HOST),
            server_port: parse_env("SERVER_PORT").unwrap_or(DEFAULT_PORT),
            environment: env_or("APP_ENV", "development"),
            database_url: first_env(&["DATABASE_URL"])
                .map(|u| u.replace("\\/", "/"))
                .unwrap_or_else(|| "postgres://reports_user@192.168.1.107:5432/asodya_reports".into()),
            couchdb_url: env_or("COUCHDB_URL", "http://192.168.1.107:5984"),
            couchdb_database: env_or("COUCHDB_DATABASE", "reports_documents"),
            couchdb_user: first_env(&["COUCHDB_USER"]),
            couchdb_password: first_env(&["COUCHDB_PASSWORD"]),
            redis_url: normalize_redis_url(env_or("REDIS_URL", "redis://192.168.1.107:6379/6")),
            redis_namespace: env_or("REDIS_NAMESPACE", "reports:"),
            service_api_key: env_or("REPORTS_SERVICE_API_KEY", ""),
            api_keys: json_env("REPORTS_API_KEYS"),
            result_ttl_secs: parse_env("RESULT_CACHE_TTL_SECS").unwrap_or(DEFAULT_RESULT_TTL_SECS),
            gate_ttl_secs: parse_env("COMPUTE_GATE_TTL_SECS").unwrap_or(DEFAULT_GATE_TTL_SECS),
            max_scan_rows: parse_env("MAX_SCAN_ROWS").unwrap_or(DEFAULT_MAX_SCAN_ROWS),
            row_cache_rows: parse_env("ROW_CACHE_ROWS").unwrap_or(DEFAULT_ROW_CACHE_ROWS),
            domain_api_url: env_or("DOMAIN_API_URL", "http://localhost:8104"),
            domain_public_url: env_or("DOMAIN_PUBLIC_URL", "https://api.asodya.com/apps/domain/v1"),
            domain_cache_ttl_secs: parse_env("DOMAIN_CACHE_TTL_SECS").unwrap_or(600),
            domain_timeout_ms: parse_env("DOMAIN_TIMEOUT_MS").unwrap_or(3000),
            embed_chrome_binary: env_or("REPORTS_CHROME_BINARY", "/usr/bin/google-chrome"),
        }
    }
}

impl Settings {
    pub fn is_production(&self) -> bool {
        !matches!(self.environment.as_str(), "development" | "dev" | "local" | "test")
    }
}

fn env_or(name: &str, default: &str) -> String {
    first_env(&[name]).unwrap_or_else(|| default.to_string())
}

fn parse_env<T: std::str::FromStr>(name: &str) -> Option<T> {
    first_env(&[name]).and_then(|v| v.trim().parse().ok())
}

fn first_env(names: &[&str]) -> Option<String> {
    names.iter().find_map(|name| {
        std::env::var(name)
            .ok()
            .filter(|value| !value.trim().is_empty())
    })
}

/// The Rust Redis client handles the password-only URL form consistently across the
/// installed Redis and Valkey versions.
fn normalize_redis_url(url: String) -> String {
    let url = url.replace("\\/", "/");
    url.strip_prefix("redis://default:")
        .map(|password_and_host| format!("redis://:{password_and_host}"))
        .unwrap_or(url)
}

/// Reads a JSON object from an environment variable. Invalid JSON gives an empty value and
/// an error in the log (never the value itself).
pub fn json_env<T: serde::de::DeserializeOwned + Default>(name: &str) -> T {
    match std::env::var(name) {
        Ok(raw) if !raw.trim().is_empty() => serde_json::from_str(&raw).unwrap_or_else(|e| {
            tracing::error!("{} is not valid JSON ({}); the engine ignores it", name, e);
            T::default()
        }),
        _ => T::default(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redis_password_only_form() {
        assert_eq!(
            normalize_redis_url("redis://default:pw@10.0.0.1:6379/6".into()),
            "redis://:pw@10.0.0.1:6379/6"
        );
        assert_eq!(normalize_redis_url("redis:\\/\\/h:6379".into()), "redis://h:6379");
    }

    #[test]
    fn production_flag() {
        let mut s = Settings { environment: "production".into(), ..Default::default() };
        assert!(s.is_production());
        s.environment = "test".into();
        assert!(!s.is_production());
    }
}
