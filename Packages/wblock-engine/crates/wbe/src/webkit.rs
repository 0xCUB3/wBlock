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

/// A rule list as Safari's JSON array text. The compiler writes it directly,
/// so the rules are never held as `WkRule` values.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WebkitJson {
    /// `[...]`, compact.
    json: String,
    rules: usize,
}

impl Default for WebkitJson {
    fn default() -> Self {
        Self {
            json: "[]".into(),
            rules: 0,
        }
    }
}

impl WebkitJson {
    pub fn from_rules(rules: &[WkRule]) -> Self {
        Self {
            json: ascii_only(to_json(rules)),
            rules: rules.len(),
        }
    }

    /// Number of rules in the list.
    pub fn rules(&self) -> usize {
        self.rules
    }

    pub fn as_str(&self) -> &str {
        &self.json
    }

    /// The JSON, without copying it.
    pub fn into_string(self) -> String {
        self.json
    }

    /// `json` is a complete, valid JSON array of `rules` objects.
    pub(crate) fn from_bytes(json: Vec<u8>, rules: usize) -> Self {
        Self {
            json: ascii_only(String::from_utf8(json).expect("JSON is UTF-8")),
            rules,
        }
    }

    /// The rules of `parts`, in order, as one list.
    pub fn join<'a>(parts: impl IntoIterator<Item = &'a WebkitJson>) -> Self {
        let mut json = String::from("[");
        let mut rules = 0;
        for part in parts {
            let items = &part.json[1..part.json.len() - 1];
            if items.is_empty() {
                continue;
            }
            if rules > 0 {
                json.push(',');
            }
            json.push_str(items);
            rules += part.rules;
        }
        json.push(']');
        Self { json, rules }
    }
}

/// `json` with every non-ASCII character written as a `\u` escape, which
/// parses to the same strings. WebKit keeps a rule list's source in its
/// compiled file, as UTF-16 once any character is above U+00FF, so one such
/// character in a selector doubled the stored source (19 MB more for the
/// default lists). Non-ASCII only occurs inside JSON strings.
fn ascii_only(json: String) -> String {
    if json.is_ascii() {
        return json;
    }
    let mut out = String::with_capacity(json.len() + 64);
    let mut units = [0u16; 2];
    for c in json.chars() {
        if c.is_ascii() {
            out.push(c);
            continue;
        }
        for unit in c.encode_utf16(&mut units) {
            use std::fmt::Write;
            write!(out, "\\u{unit:04x}").expect("String writes");
        }
    }
    out
}

/// Anything `to_json` can serialize as Safari's rule list.
pub trait WebkitRules {
    fn to_webkit_json(&self) -> String;
}

impl WebkitRules for [WkRule] {
    fn to_webkit_json(&self) -> String {
        serde_json::to_string(self).expect("WkRule serializes")
    }
}

impl WebkitRules for Vec<WkRule> {
    fn to_webkit_json(&self) -> String {
        self.as_slice().to_webkit_json()
    }
}

impl WebkitRules for WebkitJson {
    fn to_webkit_json(&self) -> String {
        self.json.clone()
    }
}

/// Serialize rules as Safari expects (compact JSON array).
pub fn to_json<T: WebkitRules + ?Sized>(rules: &T) -> String {
    rules.to_webkit_json()
}

#[cfg(test)]
mod tests {
    use crate::{compile, CompileOptions, ListInput};

    #[test]
    fn non_ascii_is_escaped_to_the_same_rules() {
        let text = "пример.рф##.реклама\nexample.com##[title=\"😀\"]";
        let out = compile(
            &[ListInput { text, trusted: false }],
            &CompileOptions { safari: super::SafariVersion::new(18, 0) },
        );
        let json = out.webkit.as_str();
        assert!(json.is_ascii(), "{json}");
        let rules: serde_json::Value = serde_json::from_str(json).unwrap();
        let mut selectors: Vec<&str> = rules
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|r| r["action"]["selector"].as_str())
            .collect();
        selectors.sort();
        assert_eq!(selectors, [".реклама", "[title=\"😀\"]"]);
    }
}
