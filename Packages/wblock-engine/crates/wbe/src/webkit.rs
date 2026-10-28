//! Safari content-blocker JSON (WebKit `ContentExtensionParser.cpp`).
//!
//! Constraints worth knowing (verified against WebKit main and macOS 27):
//! - A trigger may carry at most one of `if-domain`, `unless-domain`,
//!   `if-top-url`, `unless-top-url`, `if-frame-url`, `unless-frame-url`.
//! - `redirect` and `modify-headers` compile but are never applied for
//!   app-extension content blockers (they need web-extension host access), so
//!   they are not emitted.
//! - `request-method` compiles but did not block a `fetch` POST in WKWebView;
//!   not emitted.
//! - `url-filter` is a restricted regex: no `|`, `{}`, `\d`/`\w`/`\b`,
//!   lookaround, or backreferences; `^`/`$` only at the ends.
//! - Rules are evaluated in order; `ignore-previous-rules` cancels earlier
//!   matches only.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct WkRule {
    pub trigger: WkTrigger,
    pub action: WkAction,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub struct WkTrigger {
    #[serde(rename = "url-filter")]
    pub url_filter: String,
    #[serde(
        rename = "url-filter-is-case-sensitive",
        skip_serializing_if = "Option::is_none"
    )]
    pub url_filter_is_case_sensitive: Option<bool>,
    #[serde(rename = "resource-type", skip_serializing_if = "Option::is_none")]
    pub resource_type: Option<Vec<WkResourceType>>,
    #[serde(rename = "load-type", skip_serializing_if = "Option::is_none")]
    pub load_type: Option<Vec<WkLoadType>>,
    #[serde(rename = "load-context", skip_serializing_if = "Option::is_none")]
    pub load_context: Option<Vec<WkLoadContext>>,
    /// Lowercase hostnames; `*` prefix also matches subdomains.
    #[serde(rename = "if-domain", skip_serializing_if = "Option::is_none")]
    pub if_domain: Option<Vec<String>>,
    #[serde(rename = "unless-domain", skip_serializing_if = "Option::is_none")]
    pub unless_domain: Option<Vec<String>>,
    #[serde(rename = "if-top-url", skip_serializing_if = "Option::is_none")]
    pub if_top_url: Option<Vec<String>>,
    #[serde(rename = "unless-top-url", skip_serializing_if = "Option::is_none")]
    pub unless_top_url: Option<Vec<String>>,
    #[serde(rename = "if-frame-url", skip_serializing_if = "Option::is_none")]
    pub if_frame_url: Option<Vec<String>>,
    #[serde(rename = "unless-frame-url", skip_serializing_if = "Option::is_none")]
    pub unless_frame_url: Option<Vec<String>>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, PartialOrd, Ord)]
#[serde(rename_all = "kebab-case")]
pub enum WkResourceType {
    Document,
    Image,
    StyleSheet,
    Script,
    Font,
    Raw,
    SvgDocument,
    Media,
    Popup,
    Ping,
    Fetch,
    Websocket,
    Other,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, PartialOrd, Ord)]
#[serde(rename_all = "kebab-case")]
pub enum WkLoadType {
    FirstParty,
    ThirdParty,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, PartialOrd, Ord)]
#[serde(rename_all = "kebab-case")]
pub enum WkLoadContext {
    TopFrame,
    ChildFrame,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "kebab-case")]
pub enum WkAction {
    Block,
    BlockCookies,
    CssDisplayNone { selector: String },
    IgnorePreviousRules,
    MakeHttps,
}

/// Safari major.minor, e.g. 16.4. Features are gated on it because an older
/// Safari rejects the whole list when one rule uses an unknown field.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub struct SafariVersion {
    pub major: u16,
    pub minor: u16,
}

impl SafariVersion {
    pub const fn new(major: u16, minor: u16) -> Self {
        Self { major, minor }
    }
    pub fn at_least(self, major: u16, minor: u16) -> bool {
        self >= Self::new(major, minor)
    }
}

/// Serialize rules as Safari expects (compact JSON array).
pub fn to_json(rules: &[WkRule]) -> String {
    serde_json::to_string(rules).expect("WkRule serializes")
}
