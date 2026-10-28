//! Parsed filter rules. The parser keeps every detail of the source line
//! (domains as strings, option arguments verbatim) because the compiler needs
//! them; nothing here is hashed or lossy.
//!
//! Semantics follow uBlock Origin's static filtering parser
//! (src/js/static-filtering-parser.js). AdGuard syntax is accepted only to the
//! extent uBO accepts it, after `normalize::adguard_to_ubo`.

use bitflags::bitflags;
use serde::{Deserialize, Serialize};

/// Where a rule came from: index of the list in the compile input and the
/// 1-based line number inside that list.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub struct SourceRef {
    pub list: u32,
    pub line: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Rule {
    Network(NetworkRule),
    Cosmetic(CosmeticRule),
    Scriptlet(ScriptletRule),
}

/// Result of parsing one line.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ParsedLine {
    /// Blank line, comment, `[Adblock Plus ...]` header, or preprocessor
    /// directive (directives are evaluated before the engine sees the text).
    Ignored,
    Rule(Rule),
    /// Valid syntax that cannot be enforced in Safari (HTML filtering `##^`,
    /// `$replace`, raw `#%#` JavaScript, ...). Counted, never compiled.
    Unsupported { reason: String },
    /// Malformed line.
    Invalid { reason: String },
}

// ---------------------------------------------------------------------------
// Domains
// ---------------------------------------------------------------------------

/// One entry of `$domain=`/`$from=`/`$to=`/`$denyallow=` or of the hostname
/// list before a cosmetic marker.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "snake_case")]
pub enum DomainMatcher {
    /// Lowercased, punycode-encoded hostname. Matches itself and subdomains.
    Hostname(String),
    /// `google.*`: the label before the public suffix, any suffix.
    Entity(String),
    /// `/regex/` (uBO extension), source without slashes.
    Regex(String),
}

/// Include and exclude lists. Empty `include` means "everywhere".
#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct DomainList {
    pub include: Vec<DomainMatcher>,
    pub exclude: Vec<DomainMatcher>,
}

impl DomainList {
    pub fn is_empty(&self) -> bool {
        self.include.is_empty() && self.exclude.is_empty()
    }
}

// ---------------------------------------------------------------------------
// Network rules
// ---------------------------------------------------------------------------

bitflags! {
    /// Request types, uBO names. `DOC` is the main document; `FRAME` is a
    /// subdocument.
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
    pub struct ResourceTypes: u32 {
        const SCRIPT        = 1 << 0;
        const IMAGE         = 1 << 1;
        const CSS           = 1 << 2;
        const OBJECT        = 1 << 3;
        const XHR           = 1 << 4;
        const FRAME         = 1 << 5;
        const DOC           = 1 << 6;
        const FONT          = 1 << 7;
        const MEDIA         = 1 << 8;
        const PING          = 1 << 9;
        const WEBSOCKET     = 1 << 10;
        const OTHER         = 1 << 11;
        const POPUP         = 1 << 12;
        const POPUNDER      = 1 << 13;
        const WEBRTC        = 1 << 14;
        const INLINE_SCRIPT = 1 << 15;
        const INLINE_FONT   = 1 << 16;
    }
}

bitflags! {
    /// Document-level exception scopes: `@@...$document`, `$elemhide`,
    /// `$generichide`, `$specifichide`, `$genericblock`. Only meaningful on
    /// exceptions.
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
    pub struct ExceptionScope: u8 {
        const DOC          = 1 << 0;
        const EHIDE        = 1 << 1;
        const GHIDE        = 1 << 2;
        const SHIDE        = 1 << 3;
        const GENERICBLOCK = 1 << 4;
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum Party {
    #[default]
    Any,
    First,
    Third,
    StrictFirst,
    StrictThird,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum PatternKind {
    /// `||host^path`: anchored at a hostname label boundary.
    Hostname,
    /// `|https://`: anchored at the start of the URL.
    Left,
    /// No anchor at the start.
    #[default]
    Plain,
    /// `/regex/`, body is the regex source without slashes.
    Regex,
}

/// The URL pattern. `body` keeps `*` (any) and `^` (separator) verbatim and
/// excludes the `||`/`|` prefix and the trailing `|`.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub struct Pattern {
    pub kind: PatternKind,
    pub body: String,
    /// Trailing `|`.
    pub right_anchored: bool,
}

impl Pattern {
    /// Matches every URL (`*`, empty, or `|http*`-style generic patterns are
    /// not collapsed here; only literally empty or `*` bodies).
    pub fn is_match_all(&self) -> bool {
        self.kind != PatternKind::Regex
            && !self.right_anchored
            && (self.body.is_empty() || self.body == "*")
    }
}

/// What the rule does when it matches. Exceptions keep the action they
/// except (`@@||x^$removeparam=y` is an exception to a RemoveParam action).
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(tag = "type", content = "value", rename_all = "snake_case")]
pub enum NetworkAction {
    #[default]
    Block,
    /// `$redirect=` (or `$empty`/`$mp4` aliases). `rule_only` for
    /// `$redirect-rule`. Resource name normalized to uBO's canonical name.
    Redirect { resource: String, rule_only: bool },
    /// `$removeparam`, `None` = remove all parameters.
    RemoveParam(Option<String>),
    /// `$csp`, `None` only on exceptions (except all CSP rules).
    Csp(Option<String>),
    Permissions(Option<String>),
    /// `$urlskip=`, `$uritransform=`, `$replace=`, `$header=`/`$responseheader=`,
    /// `$requestheader=`. Kept verbatim; not enforceable natively.
    Other { option: String, value: Option<String> },
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub struct MethodList {
    pub include: Vec<String>,
    pub exclude: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct NetworkRule {
    pub source: SourceRef,
    /// The line as written (after AdGuard normalization), for provenance
    /// and debugging.
    pub raw: String,
    pub exception: bool,
    pub important: bool,
    pub badfilter: bool,
    pub match_case: bool,
    pub pattern: Pattern,
    pub party: Party,
    /// Types the rule applies to. Empty means uBO's default: every type
    /// except `DOC`, `POPUP`, `POPUNDER` (and `INLINE_*`).
    pub types: ResourceTypes,
    /// `~type` options.
    pub negated_types: ResourceTypes,
    /// `$domain=` / `$from=`.
    pub from: DomainList,
    /// `$to=`.
    pub to: DomainList,
    /// `$denyallow=`, hostnames only.
    pub denyallow: Vec<String>,
    pub method: MethodList,
    pub scope: ExceptionScope,
    pub action: NetworkAction,
    /// Options the parser recognised but that need DNS or headers
    /// (`$cname`, `$ipaddress`, `$header`, ...). A rule with any of these is
    /// not compiled natively.
    pub runtime_only_options: Vec<String>,
}

// ---------------------------------------------------------------------------
// Cosmetic rules
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(tag = "type", content = "value", rename_all = "snake_case")]
pub enum CosmeticBody {
    /// A selector that is plain CSS (may use `:has()`, `:is()`, `:not()`).
    /// Whether a given Safari version accepts it is the compiler's call.
    Hide(String),
    /// Uses uBO procedural operators (`:has-text`, `:upward`, `:xpath`,
    /// `:matches-css`, `:min-text-length`, `:watch-attr`, `:others`,
    /// `:matches-attr`, `:matches-media`, `:matches-prop`, `:-abp-*`), or an
    /// action (`:remove()`, `:style()`, `:remove-attr()`, `:remove-class()`).
    /// Kept as the normalized uBO selector text.
    Procedural(String),
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CosmeticRule {
    pub source: SourceRef,
    pub raw: String,
    pub exception: bool,
    pub domains: DomainList,
    /// `:matches-path()` prefix argument, already removed from `body`.
    pub matches_path: Option<String>,
    pub body: CosmeticBody,
}

/// `##+js(name, args...)`. `name` is uBO's canonical scriptlet name (aliases
/// and AdGuard names resolved). Exception with empty `name` (`#@#+js()`)
/// disables all scriptlets on the listed domains.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ScriptletRule {
    pub source: SourceRef,
    pub raw: String,
    pub exception: bool,
    pub domains: DomainList,
    pub name: String,
    pub args: Vec<String>,
}
