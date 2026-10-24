use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;
use thiserror::Error;

use crate::domain::guardrail::ValidationError;

#[derive(Error, Debug)]
pub enum ReportError {
    /// A durable store (PostgreSQL or CouchDB) did not answer or refused the operation.
    #[error("Storage unavailable: {0}")]
    Unavailable(String),

    #[error("Database error: {0}")]
    Database(String),

    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Bad request: {0}")]
    BadRequest(String),

    /// The payload breaks the registered schema or a definition rule.
    #[error("Validation failed: {message}")]
    Validation {
        message: String,
        violations: Vec<ValidationError>,
    },

    #[error("Conflict: {0}")]
    Conflict(String),

    /// No session: the client may offer a login.
    #[error("A session is required")]
    Unauthorized,

    /// A session exists, but it has no access. The client must not offer a login again.
    #[error("Forbidden: {0}")]
    Forbidden(String),

    #[error("Internal server error: {0}")]
    Internal(String),
}

impl ReportError {
    pub fn not_found(what: impl Into<String>) -> Self {
        ReportError::NotFound(what.into())
    }

    pub fn status(&self) -> StatusCode {
        match self {
            ReportError::Unavailable(_) => StatusCode::SERVICE_UNAVAILABLE,
            ReportError::Database(_) | ReportError::Internal(_) => StatusCode::INTERNAL_SERVER_ERROR,
            ReportError::NotFound(_) => StatusCode::NOT_FOUND,
            ReportError::BadRequest(_) => StatusCode::BAD_REQUEST,
            ReportError::Validation { .. } => StatusCode::UNPROCESSABLE_ENTITY,
            ReportError::Conflict(_) => StatusCode::CONFLICT,
            ReportError::Unauthorized => StatusCode::UNAUTHORIZED,
            ReportError::Forbidden(_) => StatusCode::FORBIDDEN,
        }
    }

    /// Stable machine-readable code of the error.
    pub fn code(&self) -> &'static str {
        match self {
            ReportError::Unavailable(_) => "storage_unavailable",
            ReportError::Database(_) => "database_error",
            ReportError::NotFound(_) => "not_found",
            ReportError::BadRequest(_) => "bad_request",
            ReportError::Validation { .. } => "validation_failed",
            ReportError::Conflict(_) => "conflict",
            ReportError::Unauthorized => "session_required",
            ReportError::Forbidden(_) => "access_denied",
            ReportError::Internal(_) => "internal_error",
        }
    }
}

impl From<sqlx::Error> for ReportError {
    fn from(e: sqlx::Error) -> Self {
        match e {
            sqlx::Error::PoolTimedOut
            | sqlx::Error::PoolClosed
            | sqlx::Error::Io(_)
            | sqlx::Error::Tls(_) => ReportError::Unavailable(format!("PostgreSQL: {e}")),
            other => ReportError::Database(other.to_string()),
        }
    }
}

impl IntoResponse for ReportError {
    fn into_response(self) -> Response {
        let status = self.status();
        // Internal details stay in the log. The client gets the code and a short text.
        let message = match &self {
            ReportError::Database(m) | ReportError::Internal(m) => {
                tracing::error!("{}: {}", self.code(), m);
                "The request failed on the server".to_string()
            }
            ReportError::Unavailable(m) => {
                tracing::error!("storage unavailable: {}", m);
                "A storage service is unavailable".to_string()
            }
            other => other.to_string(),
        };
        let mut body = json!({
            "error": message,
            "code": self.code(),
            "status": status.as_u16(),
        });
        if let ReportError::Validation { violations, .. } = &self {
            body["violations"] = json!(violations);
        }
        (status, Json(body)).into_response()
    }
}
