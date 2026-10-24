//! Keys of local operator tools (`x-reports-service-key`). Each key has a name
//! (REPORTS_API_KEYS); REPORTS_SERVICE_API_KEY is one more key with the name `service`.
//! A removed name revokes only that tool.

use std::collections::BTreeMap;

use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;

/// Name of the service key in the logs.
pub const LEGACY_KEY_NAME: &str = "service";

/// Accepted keys. The ring keeps only SHA-256 digests, and the check compares digests in
/// constant time, so neither the content nor the length of a key leaks through timing.
#[derive(Clone, Default)]
pub struct ServiceKeyRing {
    entries: Vec<(String, [u8; 32])>,
}

fn digest(key: &str) -> [u8; 32] {
    Sha256::digest(key.as_bytes()).into()
}

impl ServiceKeyRing {
    /// The legacy key plus the named keys. Empty keys are ignored.
    pub fn new(legacy_key: &str, named: &BTreeMap<String, String>) -> Self {
        let mut entries = Vec::new();
        if !legacy_key.is_empty() {
            entries.push((LEGACY_KEY_NAME.to_string(), digest(legacy_key)));
        }
        for (name, key) in named {
            if !key.is_empty() {
                entries.push((name.clone(), digest(key)));
            }
        }
        Self { entries }
    }

    /// Name of the app that owns `presented`, or None for an unknown key.
    /// Every entry is checked, also after a match, so the time does not show the position.
    pub fn identify(&self, presented: &str) -> Option<&str> {
        let candidate = digest(presented);
        let mut found = None;
        for (name, known) in &self.entries {
            if bool::from(known.ct_eq(&candidate)) && found.is_none() {
                found = Some(name.as_str());
            }
        }
        found
    }

    /// Names of the accepted apps (for the start-up log; never the keys).
    pub fn names(&self) -> Vec<&str> {
        self.entries.iter().map(|(n, _)| n.as_str()).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_named_and_legacy_keys_only() {
        let named = BTreeMap::from([
            ("fixtures".to_string(), "k-fixtures".to_string()),
            ("cortex-producer".to_string(), "k-cortex".to_string()),
            ("empty".to_string(), String::new()),
        ]);
        let ring = ServiceKeyRing::new("legacy-key", &named);
        assert_eq!(ring.identify("legacy-key"), Some(LEGACY_KEY_NAME));
        assert_eq!(ring.identify("k-fixtures"), Some("fixtures"));
        assert_eq!(ring.identify("k-cortex"), Some("cortex-producer"));
        assert_eq!(ring.identify("k-fixture"), None);
        assert_eq!(ring.identify(""), None, "an empty key never matches");
        assert_eq!(
            ring.names(),
            vec!["service", "cortex-producer", "fixtures"]
        );
    }
}
