//! Who calls the engine and what the caller may read.
//!
//! Identity rules (api_for_apps gateway contract):
//! - On a public path the gateway checks no session and sends no identity, so every caller
//!   is a guest. Public handlers never read identity headers.
//! - On a session path the gateway checks the `sid` cookie, removes any client `x-uuid`,
//!   and sends the real `x-uuid` plus `x-access-level` from the session.
//! - `x-access-level: 1` (super admin) counts only together with `x-uuid`.
//! - `x-project-admin` is never trusted: the gateway does not set it from real data.
//!   Project admins come from `user_project_roles` in the Reports database.
//! - Local operator tools use `x-reports-service-key` (never sent by browsers).

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::core::error::ReportError;
use crate::dal::{catalog, grants, Db, Grant};

pub mod service_keys;

pub use service_keys::ServiceKeyRing;

/// Gateway access level of a super admin.
pub const SUPER_ADMIN_ACCESS_LEVEL: &str = "1";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Viewer {
    Guest,
    User { uuid: String, super_admin: bool },
    /// Local operator tool with a valid service key (full access).
    Service { app: String },
}

/// Who may read a report or a card.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum Visibility {
    Public,
    SignedIn,
    Restricted,
}

impl Visibility {
    /// Parses a stored value. An unknown value is restricted (deny by default).
    pub fn parse(text: &str) -> Visibility {
        match text {
            "public" => Visibility::Public,
            "signed_in" => Visibility::SignedIn,
            _ => Visibility::Restricted,
        }
    }

    /// Strict parse for writes: an unknown value is an error.
    pub fn parse_strict(text: &str) -> Result<Visibility, ReportError> {
        match text {
            "public" => Ok(Visibility::Public),
            "signed_in" => Ok(Visibility::SignedIn),
            "restricted" => Ok(Visibility::Restricted),
            other => Err(ReportError::BadRequest(format!(
                "visibility '{other}' is not valid (use public, signed_in or restricted)"
            ))),
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Visibility::Public => "public",
            Visibility::SignedIn => "signed_in",
            Visibility::Restricted => "restricted",
        }
    }

    /// The stricter of two levels (a report level applies to every card in it).
    pub fn stricter(self, other: Visibility) -> Visibility {
        self.max(other)
    }
}

/// The caller of one request with the project roles from the database.
#[derive(Debug, Clone)]
pub struct ViewerScope {
    pub viewer: Viewer,
    /// Projects where `user_project_roles` marks the user as admin.
    pub admin_projects: Vec<String>,
    /// Read grants of the user for restricted reports and cards.
    pub grants: Vec<Grant>,
}

impl ViewerScope {
    pub fn guest() -> Self {
        Self { viewer: Viewer::Guest, admin_projects: Vec::new(), grants: Vec::new() }
    }

    /// Loads the project roles and grants of a user. Guests and service callers need no query.
    pub async fn resolve(db: &Db, viewer: Viewer) -> Result<Self, ReportError> {
        let (admin_projects, grants) = match &viewer {
            Viewer::User { uuid, .. } => (catalog::admin_projects(db, uuid).await?, grants::for_user(db, uuid).await?),
            _ => (Vec::new(), Vec::new()),
        };
        Ok(Self { viewer, admin_projects, grants })
    }

    pub fn is_authenticated(&self) -> bool {
        !matches!(self.viewer, Viewer::Guest)
    }

    pub fn is_super_admin(&self) -> bool {
        matches!(self.viewer, Viewer::Service { .. } | Viewer::User { super_admin: true, .. })
    }

    pub fn user_uuid(&self) -> Option<&str> {
        match &self.viewer {
            Viewer::User { uuid, .. } => Some(uuid),
            _ => None,
        }
    }

    pub fn can_admin(&self, project: &str) -> bool {
        self.is_super_admin() || self.admin_projects.iter().any(|p| p == project)
    }

    /// Read access to data with this effective visibility in this project (no grants).
    pub fn can_read(&self, project: &str, visibility: Visibility) -> bool {
        match visibility {
            Visibility::Public => true,
            Visibility::SignedIn => self.is_authenticated(),
            Visibility::Restricted => self.can_admin(project),
        }
    }

    /// Read access to one report (`card` None) or one card, with the user's grants.
    /// A report grant opens every card of the report; a card grant opens only that card.
    pub fn can_read_resource(&self, project: &str, report: &str, card: Option<&str>, visibility: Visibility) -> bool {
        self.can_read(project, visibility)
            || (visibility == Visibility::Restricted
                && self.is_authenticated()
                && self.grants.iter().any(|g| g.covers(project, report, card)))
    }

    /// True when the user has a grant on the report or on any card of it.
    pub fn has_grant_in(&self, project: &str, report: &str) -> bool {
        self.grants.iter().any(|g| g.project == project && g.report == report)
    }

    /// The error for a denied read: 401 for a guest (login may help), 403 for a session.
    pub fn denied(&self, what: &str) -> ReportError {
        if self.is_authenticated() {
            ReportError::Forbidden(format!("access to {what} is limited"))
        } else {
            ReportError::Unauthorized
        }
    }

    pub fn role(&self) -> &'static str {
        match &self.viewer {
            Viewer::Guest => "guest",
            Viewer::Service { .. } => "service",
            Viewer::User { super_admin: true, .. } => "super_admin",
            Viewer::User { .. } if !self.admin_projects.is_empty() => "project_admin",
            Viewer::User { .. } => "viewer",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn user(super_admin: bool, admin_of: &[&str]) -> ViewerScope {
        ViewerScope {
            viewer: Viewer::User { uuid: "7c6f3a1e-0000-4000-8000-000000000001".into(), super_admin },
            admin_projects: admin_of.iter().map(|s| s.to_string()).collect(),
            grants: Vec::new(),
        }
    }

    #[test]
    fn access_matrix() {
        let guest = ViewerScope::guest();
        let viewer = user(false, &[]);
        let cortex_admin = user(false, &["cortex"]);
        let super_admin = user(true, &[]);
        use Visibility::*;
        assert!(guest.can_read("cortex", Public));
        assert!(!guest.can_read("cortex", SignedIn));
        assert!(!guest.can_read("cortex", Restricted));
        assert!(viewer.can_read("cortex", SignedIn));
        assert!(!viewer.can_read("cortex", Restricted));
        assert!(cortex_admin.can_read("cortex", Restricted));
        assert!(!cortex_admin.can_read("fsm", Restricted));
        assert!(super_admin.can_read("fsm", Restricted));
    }

    #[test]
    fn unknown_visibility_is_restricted_and_stricter_wins() {
        assert_eq!(Visibility::parse("internal"), Visibility::Restricted);
        assert!(Visibility::parse_strict("internal").is_err());
        assert_eq!(Visibility::Public.stricter(Visibility::SignedIn), Visibility::SignedIn);
        assert_eq!(Visibility::Restricted.stricter(Visibility::Public), Visibility::Restricted);
    }

    #[test]
    fn denied_is_401_for_guests_and_403_for_sessions() {
        assert!(matches!(ViewerScope::guest().denied("x"), ReportError::Unauthorized));
        assert!(matches!(user(false, &[]).denied("x"), ReportError::Forbidden(_)));
    }

    #[test]
    fn grants_open_only_their_resource() {
        let mut viewer = user(false, &[]);
        viewer.grants = vec![Grant {
            id: "g1".into(),
            user_uuid: "u".into(),
            resource_type: "card".into(),
            project: "cortex".into(),
            report: "token-usage".into(),
            card_id: Some("errors-by-type".into()),
            granted_by: None,
            created_at: String::new(),
        }];
        use Visibility::Restricted;
        assert!(viewer.can_read_resource("cortex", "token-usage", Some("errors-by-type"), Restricted));
        assert!(!viewer.can_read_resource("cortex", "token-usage", Some("latency-by-model"), Restricted));
        assert!(!viewer.can_read_resource("cortex", "token-usage", None, Restricted), "a card grant is not a report grant");
        assert!(!viewer.can_read_resource("fsm", "token-usage", Some("errors-by-type"), Restricted));
        viewer.grants[0].card_id = None;
        assert!(viewer.can_read_resource("cortex", "token-usage", Some("latency-by-model"), Restricted));
        // A guest never uses grants.
        let mut guest = ViewerScope::guest();
        guest.grants = viewer.grants.clone();
        assert!(!guest.can_read_resource("cortex", "token-usage", None, Restricted));
    }
}
