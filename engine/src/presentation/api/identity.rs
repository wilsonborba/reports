//! Request identity (see `domain::auth` for the gateway contract) and shared query helpers.

use std::sync::Arc;

use axum::extract::{FromRef, FromRequestParts};
use axum::http::request::Parts;
use axum::http::{header, HeaderMap};

use super::server::AppState;
use crate::core::error::ReportError;
use crate::domain::auth::{Viewer, ViewerScope, SUPER_ADMIN_ACCESS_LEVEL};

/// Header of local operator tools. Browsers never send it.
pub const SERVICE_KEY_HEADER: &str = "x-reports-service-key";

/// Reads the caller from the headers. A wrong service key is an error, not a guest.
pub fn viewer_from_headers(state: &AppState, headers: &HeaderMap) -> Result<Viewer, ReportError> {
    if let Some(presented) = headers.get(SERVICE_KEY_HEADER) {
        let presented = presented.to_str().unwrap_or_default();
        return match state.keys.identify(presented) {
            Some(app) => {
                tracing::info!(app, "request with a service key");
                Ok(Viewer::Service { app: app.to_string() })
            }
            None => Err(ReportError::Forbidden("the service key is not valid".into())),
        };
    }
    let uuid = headers
        .get("x-uuid")
        .and_then(|v| v.to_str().ok())
        .map(str::trim)
        .filter(|v| !v.is_empty());
    match uuid {
        Some(uuid) => {
            if uuid::Uuid::parse_str(uuid).is_err() {
                return Err(ReportError::BadRequest("x-uuid is not a UUID".into()));
            }
            // The gateway sets x-access-level only together with x-uuid, from the session.
            let super_admin = headers.get("x-access-level").and_then(|v| v.to_str().ok()) == Some(SUPER_ADMIN_ACCESS_LEVEL);
            Ok(Viewer::User { uuid: uuid.to_string(), super_admin })
        }
        None => Ok(Viewer::Guest),
    }
}

/// Caller of a session or admin route, with project roles from the database.
/// On a session path behind the gateway the caller is never a guest; a direct local call
/// without identity is a guest and sees only public data.
pub struct Caller(pub ViewerScope);

#[async_trait::async_trait]
impl<S> FromRequestParts<S> for Caller
where
    S: Send + Sync,
    Arc<AppState>: FromRef<S>,
{
    type Rejection = ReportError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let state = Arc::<AppState>::from_ref(state);
        let viewer = viewer_from_headers(&state, &parts.headers)?;
        Ok(Caller(ViewerScope::resolve(&state.stores.db, viewer).await?))
    }
}

/// The caller must be signed in.
pub fn require_session(scope: &ViewerScope) -> Result<(), ReportError> {
    if scope.is_authenticated() {
        Ok(())
    } else {
        Err(ReportError::Unauthorized)
    }
}

/// The caller must administer the project (super admin, service key or project admin).
pub fn require_admin(scope: &ViewerScope, project: &str) -> Result<(), ReportError> {
    require_session(scope)?;
    if scope.can_admin(project) {
        Ok(())
    } else {
        Err(ReportError::Forbidden(format!("administration of project '{project}' needs a project admin")))
    }
}

/// The caller must be a super admin (or a service key).
pub fn require_super_admin(scope: &ViewerScope) -> Result<(), ReportError> {
    require_session(scope)?;
    if scope.is_super_admin() {
        Ok(())
    } else {
        Err(ReportError::Forbidden("this operation needs a super admin".into()))
    }
}

/// Response language: the `lang` parameter, else `Accept-Language`, else English.
pub fn resolve_lang(lang: Option<&str>, headers: &HeaderMap) -> String {
    let pick = |tag: &str| {
        let t = tag.trim().to_lowercase();
        if t.starts_with("th") {
            Some("th")
        } else if t.starts_with("pt") {
            Some("pt-BR")
        } else if t.starts_with("en") {
            Some("en")
        } else {
            None
        }
    };
    if let Some(l) = lang {
        return pick(l).unwrap_or("en").to_string();
    }
    headers
        .get(header::ACCEPT_LANGUAGE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .split(',')
        .find_map(|t| pick(t.split(';').next().unwrap_or("")))
        .unwrap_or("en")
        .to_string()
}

/// Fixture manifest of a sample-data write (`x-reports-fixture`), only for service keys.
pub fn fixture_of(scope: &ViewerScope, headers: &HeaderMap) -> Result<Option<String>, ReportError> {
    let Some(value) = headers.get("x-reports-fixture").and_then(|v| v.to_str().ok()) else {
        return Ok(None);
    };
    if !matches!(scope.viewer, Viewer::Service { .. }) {
        return Err(ReportError::Forbidden("x-reports-fixture needs a service key".into()));
    }
    if !crate::domain::catalog::valid_slug(value) {
        return Err(ReportError::BadRequest("x-reports-fixture is not a valid slug".into()));
    }
    Ok(Some(value.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn language_negotiation() {
        let mut h = HeaderMap::new();
        assert_eq!(resolve_lang(None, &h), "en");
        h.insert(header::ACCEPT_LANGUAGE, "pt-BR,pt;q=0.9,en;q=0.8".parse().unwrap());
        assert_eq!(resolve_lang(None, &h), "pt-BR");
        assert_eq!(resolve_lang(Some("th"), &h), "th");
        assert_eq!(resolve_lang(Some("xx"), &h), "en");
    }
}
