//! Cosmetic hides and exceptions to Safari `css-display-none` rules.
//!
//! Model: uBO's cosmetic-filtering.js. A filter's key is its selector plus its
//! `:matches-path()` argument. On a page, every exception applicable to the page
//! removes its key from every hide applicable to the page, generic or specific.
//! Exceptions are resolved here when each page they touch can be expressed
//! natively. Otherwise every hide and exception with that key goes to `runtime`.

use super::{CompileOptions, Stats, Tier, Tiered};
use crate::ast::{CosmeticBody, CosmeticRule, DomainMatcher};
use crate::webkit::{SafariVersion, WkAction, WkResourceType, WkRule, WkTrigger};
use std::collections::{BTreeMap, BTreeSet, HashSet};

/// Selectors per emitted rule. AdGuard's Compiler uses the same limit
/// (`MAX_SELECTORS_PER_RULE`).
const GROUP_SIZE: usize = 250;

/// Host part of an `if-top-url` pattern that matches any host.
const ANY_HOST: &str = r"[^\/]+";

type Key = (String, Option<String>);

pub(super) fn compile(
    rules: &[CosmeticRule],
    opts: &CompileOptions,
    out: &mut Vec<Tiered>,
    runtime: &mut Vec<String>,
    stats: &mut Stats,
) {
    let safari = opts.safari;
    let mut hides: BTreeMap<Key, Vec<Entry>> = BTreeMap::new();
    let mut exceptions: BTreeMap<Key, Vec<Entry>> = BTreeMap::new();
    let mut runtime_lines = BTreeSet::new();
    for rule in rules {
        match &rule.body {
            CosmeticBody::Procedural(_) => {
                runtime_lines.insert(rule.raw.as_str());
            }
            CosmeticBody::Hide(selector) => match verdict(selector, safari) {
                Verdict::Invalid => stats.drop("invalid cosmetic selector"),
                verdict => {
                    let scope = if verdict == Verdict::Native {
                        Scope::of(rule)
                    } else {
                        None
                    };
                    let key = (selector.clone(), rule.matches_path.clone());
                    let map = if rule.exception {
                        &mut exceptions
                    } else {
                        &mut hides
                    };
                    map.entry(key).or_default().push(Entry { rule, scope });
                }
            },
        }
    }

    let keys: BTreeSet<&Key> = hides.keys().chain(exceptions.keys()).collect();
    let mut resolved: Vec<(&Key, Vec<(Tier, Trigger)>)> = Vec::new();
    for key in keys {
        let hs = hides.get(key).map(Vec::as_slice).unwrap_or_default();
        let es = exceptions.get(key).map(Vec::as_slice).unwrap_or_default();
        match resolve(hs, es, safari) {
            Some(triggers) => resolved.push((key, triggers)),
            None => {
                for entry in hs.iter().chain(es) {
                    runtime_lines.insert(entry.rule.raw.as_str());
                }
            }
        }
    }

    // A selector hidden on every page makes its domain-specific copies redundant.
    let universal: HashSet<&str> = resolved
        .iter()
        .filter(|(key, _)| key.1.is_none())
        .filter(|(_, ts)| ts.contains(&(Tier::GenericHide, Trigger::Generic)))
        .map(|(key, _)| key.0.as_str())
        .collect();

    let mut groups: BTreeMap<(Tier, Trigger), BTreeSet<&str>> = BTreeMap::new();
    for (key, triggers) in &resolved {
        for (tier, trigger) in triggers {
            let redundant = *tier == Tier::SpecificHide
                && key.1.is_none()
                && universal.contains(key.0.as_str());
            if !redundant {
                groups
                    .entry((*tier, trigger.clone()))
                    .or_default()
                    .insert(key.0.as_str());
            }
        }
    }
    for ((tier, trigger), selectors) in groups {
        let selectors: Vec<&str> = selectors.into_iter().collect();
        for chunk in selectors.chunks(GROUP_SIZE) {
            out.push(Tiered {
                tier,
                rule: WkRule {
                    trigger: trigger.to_trigger(),
                    action: WkAction::CssDisplayNone {
                        selector: chunk.join(", "),
                    },
                },
            });
        }
    }

    runtime.extend(runtime_lines.into_iter().map(str::to_string));
}

/// A hide or exception that reached the compiler. `scope: None` means the
/// rule needs the runtime (regex domain, entity exclusion, or a selector Safari
/// cannot take).
struct Entry<'a> {
    rule: &'a CosmeticRule,
    scope: Option<Scope>,
}

/// Domain and path conditions of a rule, split by kind.
#[derive(Clone, Default)]
struct Scope {
    hosts: Vec<String>,
    entities: Vec<String>,
    excludes: Vec<String>,
    path: Option<String>,
}

impl Scope {
    fn of(rule: &CosmeticRule) -> Option<Self> {
        let mut scope = Scope {
            path: rule.matches_path.clone(),
            ..Self::default()
        };
        for matcher in &rule.domains.include {
            match matcher {
                DomainMatcher::Hostname(h) => scope.hosts.push(h.clone()),
                DomainMatcher::Entity(e) => scope.entities.push(e.clone()),
                DomainMatcher::Regex(_) => return None,
            }
        }
        for matcher in &rule.domains.exclude {
            match matcher {
                DomainMatcher::Hostname(h) => scope.excludes.push(h.clone()),
                _ => return None,
            }
        }
        Some(scope)
    }

    fn is_generic(&self) -> bool {
        self.hosts.is_empty() && self.entities.is_empty()
    }
}

/// One Safari trigger. `Generic` and `Unless` apply to every page, so they
/// are generic hides. The rest are specific.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
enum Trigger {
    Generic,
    Unless(Vec<String>),
    IfDomain(Vec<String>),
    TopUrl(Vec<String>),
}

impl Trigger {
    fn to_trigger(&self) -> WkTrigger {
        let mut trigger = WkTrigger {
            url_filter: ".*".into(),
            ..WkTrigger::default()
        };
        match self {
            Trigger::Generic => return trigger,
            Trigger::Unless(d) => trigger.unless_domain = Some(d.clone()),
            Trigger::IfDomain(d) => trigger.if_domain = Some(d.clone()),
            Trigger::TopUrl(r) => trigger.if_top_url = Some(r.clone()),
        }
        // A scoped hide only needs checking when a document loads, not on
        // every subresource (wBlock #873).
        trigger.resource_type = Some(vec![WkResourceType::Document]);
        trigger
    }
}

/// Resolves the hides and exceptions of one key. Returns the triggers the
/// hides keep, or `None` when the key must go to the runtime.
fn resolve(
    hides: &[Entry],
    exceptions: &[Entry],
    safari: SafariVersion,
) -> Option<Vec<(Tier, Trigger)>> {
    let mut excepted_hosts: Vec<&str> = Vec::new();
    let mut global = false;
    for exception in exceptions {
        let scope = exception.scope.as_ref()?;
        if !scope.entities.is_empty() || !scope.excludes.is_empty() {
            return None;
        }
        if scope.hosts.is_empty() {
            global = true;
        }
        excepted_hosts.extend(scope.hosts.iter().map(String::as_str));
    }
    if global {
        return Some(Vec::new());
    }

    let mut triggers = Vec::new();
    for hide in hides {
        let mut scope = hide.scope.clone()?;
        if !excepted_hosts.is_empty() {
            if scope.is_generic() {
                scope
                    .excludes
                    .extend(excepted_hosts.iter().map(|h| h.to_string()));
            } else {
                if !scope.entities.is_empty() {
                    return None;
                }
                let had_hosts = !scope.hosts.is_empty();
                for host in &scope.hosts {
                    if excepted_hosts.iter().any(|x| within(host, x)) {
                        continue;
                    }
                    if excepted_hosts.iter().any(|x| within(x, host)) {
                        // Pages under the excepted host would need an unless-domain
                        // on a domain-specific trigger, which Safari cannot combine.
                        return None;
                    }
                }
                scope
                    .hosts
                    .retain(|host| !excepted_hosts.iter().any(|x| within(host, x)));
                if had_hosts && scope.hosts.is_empty() {
                    continue;
                }
            }
        }
        triggers.extend(scope_triggers(&scope, safari)?);
    }
    Some(triggers)
}

/// `child` is `parent` or one of its subdomains.
fn within(child: &str, parent: &str) -> bool {
    child == parent || child.strip_suffix(parent).is_some_and(|p| p.ends_with('.'))
}

/// The triggers that express a scope natively, or `None` if Safari cannot.
fn scope_triggers(scope: &Scope, safari: SafariVersion) -> Option<Vec<(Tier, Trigger)>> {
    let needs_top_url = scope.path.is_some() || !scope.entities.is_empty();
    if needs_top_url && !safari.at_least(16, 4) {
        return None;
    }
    if scope.is_generic() {
        let trigger = match (&scope.path, scope.excludes.is_empty()) {
            (None, true) => Trigger::Generic,
            (None, false) => Trigger::Unless(domains(&scope.excludes)),
            (Some(path), true) => Trigger::TopUrl(url_regexes(ANY_HOST, Some(path.as_str()))?),
            (Some(_), false) => return None,
        };
        return Some(vec![(Tier::GenericHide, trigger)]);
    }
    if !scope.excludes.is_empty() {
        return None;
    }
    let mut out = Vec::new();
    match &scope.path {
        None if !scope.hosts.is_empty() => {
            out.push((Tier::SpecificHide, Trigger::IfDomain(domains(&scope.hosts))));
        }
        None => {}
        Some(path) => {
            for host in &scope.hosts {
                let regexes = url_regexes(&host_regex(host)?, Some(path.as_str()))?;
                out.push((Tier::SpecificHide, Trigger::TopUrl(regexes)));
            }
        }
    }
    for entity in &scope.entities {
        let regexes = url_regexes(&entity_regex(entity)?, scope.path.as_deref())?;
        out.push((Tier::SpecificHide, Trigger::TopUrl(regexes)));
    }
    Some(out)
}

fn domains(hosts: &[String]) -> Vec<String> {
    let mut out: Vec<String> = hosts.iter().map(|h| format!("*{h}")).collect();
    out.sort();
    out.dedup();
    out
}

/// Host part of a URL pattern matching `host` and its subdomains.
fn host_regex(host: &str) -> Option<String> {
    Some(format!(r"([^\/:]+\.)?{}", escape(host)?))
}

/// Host part matching `example.*`: the label, then a single-label suffix or
/// `co.`/`com.` followed by one more label (`co.uk`, `com.au`). Longer public
/// suffixes are not matched.
fn entity_regex(entity: &str) -> Option<String> {
    Some(format!(
        r"([^\/:]+\.)?{}\.(com?\.)?[^\/:.]+",
        escape(entity)?
    ))
}

/// Full `if-top-url` patterns for a host part, optionally with a
/// `:matches-path()` argument. uBO tests the argument against
/// `pathname + search`, case-insensitively and unanchored, so the path is
/// matched after the host and before any fragment.
fn url_regexes(host: &str, path: Option<&str>) -> Option<Vec<String>> {
    let mut out = url_regex_candidates(host, path)?;
    out.retain(|r| super::regex::webkit_accepts(r));
    (!out.is_empty()).then_some(out)
}

fn url_regex_candidates(host: &str, path: Option<&str>) -> Option<Vec<String>> {
    let head = format!(r"^[^:]+:\/\/{host}");
    let Some(path) = path else {
        return Some(vec![format!(r"{head}([:\/?#].*)?$")]);
    };
    let arg = plain_path(path)?;
    let mut out = vec![format!(r"{head}(:[^\/#]*)?\/[^#]*{arg}[^#]*")];
    if path.starts_with('/') {
        // The argument may start at the pathname's leading slash.
        out.push(format!(r"{head}(:[^\/#]*)?{arg}[^#]*"));
    }
    Some(out)
}

/// uBO's `regexFromString` for a plain `:matches-path()` argument, in the
/// url-filter subset Safari accepts. Regex arguments and characters that
/// would need other escaping go to the runtime.
fn plain_path(path: &str) -> Option<String> {
    if path.starts_with('/') && path.len() > 1 && path.ends_with('/') {
        return None;
    }
    let mut out = String::new();
    for c in path.chars() {
        match c {
            c if c.is_ascii_alphanumeric() || "-_%=&~,;:'\"<>@!# ".contains(c) => out.push(c),
            '/' | '.' | '?' | '+' | '*' => {
                out.push('\\');
                out.push(c);
            }
            _ => return None,
        }
    }
    Some(out)
}

/// Escapes a hostname or entity label for a url-filter regex.
fn escape(label: &str) -> Option<String> {
    let mut out = String::new();
    for c in label.chars() {
        match c {
            c if c.is_ascii_alphanumeric() || c == '-' => out.push(c),
            '.' => out.push_str(r"\."),
            _ => return None,
        }
    }
    Some(out)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Verdict {
    /// Plain CSS that this Safari accepts.
    Native,
    /// Valid CSS that this Safari rejects. A JS runtime can still apply it.
    NeedsJs,
    /// Not CSS, or not a selector WebKit knows. Dropped.
    Invalid,
}

/// Checks a selector with the same parser brave/adblock-rust uses for its
/// `css-validation` feature. A selector that only the permissive dialect
/// accepts (`:lang()`, `:dir()`) is valid for JS, so it needs the runtime.
/// Version gates follow AdGuard's CosmeticRule (`:has()` 16.4, `:is()` 14).
fn verdict(selector: &str, safari: SafariVersion) -> Verdict {
    if css::canonical(selector, css::Dialect::Permissive).is_none() {
        return Verdict::Invalid;
    }
    let Some(canonical) = css::canonical(selector, css::Dialect::Webkit) else {
        return Verdict::NeedsJs;
    };
    let gated = (canonical.contains(":has(") && !safari.at_least(16, 4))
        || (canonical.contains(":is(") && !safari.at_least(14, 0))
        || (canonical.contains(":where(") && !safari.at_least(14, 0))
        || (canonical.contains(":focus-visible") && !safari.at_least(15, 4));
    if gated {
        Verdict::NeedsJs
    } else {
        Verdict::Native
    }
}

mod css {
    use cssparser::{CowRcStr, ParseError, ParserInput, SourceLocation, ToCss};
    use precomputed_hash::PrecomputedHash;
    use selectors::parser::{ParseRelative, SelectorList, SelectorParseErrorKind};
    use std::fmt::{self, Write};
    use std::hash::{DefaultHasher, Hash, Hasher};

    #[derive(Clone, Copy, PartialEq, Eq)]
    pub(super) enum Dialect {
        /// Pseudo-classes WebKit's content-blocker parser knows.
        Webkit,
        /// Also pseudo-classes that only JS engines know.
        Permissive,
    }

    /// Canonical CSS text if `selector` parses in `dialect`.
    pub(super) fn canonical(selector: &str, dialect: Dialect) -> Option<String> {
        let mut input = ParserInput::new(selector);
        let mut parser = cssparser::Parser::new(&mut input);
        let list =
            SelectorList::<Impl>::parse(&DialectParser(dialect), &mut parser, ParseRelative::No)
                .ok()?;
        parser.expect_exhausted().ok()?;
        let mut out = String::new();
        list.to_css(&mut out).ok()?;
        Some(out)
    }

    /// Pseudo-classes that WebKit understands, excluding the tree-structural
    /// ones the selectors crate parses itself (`:not`, `:is`, `:has`, `:nth-*`).
    const CLASSES: &[&str] = &[
        "-webkit-any-link",
        "-webkit-autofill",
        "active",
        "any-link",
        "checked",
        "default",
        "defined",
        "disabled",
        "empty",
        "enabled",
        "first-child",
        "first-of-type",
        "focus",
        "focus-visible",
        "focus-within",
        "fullscreen",
        "hover",
        "in-range",
        "indeterminate",
        "invalid",
        "last-child",
        "last-of-type",
        "link",
        "only-child",
        "only-of-type",
        "optional",
        "out-of-range",
        "placeholder-shown",
        "read-only",
        "read-write",
        "required",
        "root",
        "scope",
        "target",
        "valid",
        "visited",
    ];

    /// Pseudo-classes JS engines accept and WebKit's content blocker may not.
    const JS_CLASSES: &[&str] = &[
        "blank", "current", "future", "modal", "open", "past", "playing", "paused",
    ];
    /// Functional pseudo-classes JS engines accept; their arguments are not checked.
    const JS_FUNCTIONAL: &[&str] = &["dir", "lang", "matches"];

    const ELEMENTS: &[&str] = &[
        "after",
        "before",
        "first-letter",
        "first-line",
        "placeholder",
        "selection",
    ];

    struct DialectParser(Dialect);

    impl<'i> selectors::parser::Parser<'i> for DialectParser {
        type Impl = Impl;
        type Error = SelectorParseErrorKind<'i>;

        fn parse_is_and_where(&self) -> bool {
            true
        }

        fn parse_has(&self) -> bool {
            true
        }

        fn parse_non_ts_pseudo_class(
            &self,
            location: SourceLocation,
            name: CowRcStr<'i>,
        ) -> Result<PseudoClass, ParseError<'i, Self::Error>> {
            let known = CLASSES.contains(&name.as_ref())
                || (self.0 == Dialect::Permissive && JS_CLASSES.contains(&name.as_ref()));
            if known {
                Ok(PseudoClass(name.to_string()))
            } else {
                Err(location.new_custom_error(
                    SelectorParseErrorKind::UnsupportedPseudoClassOrElement(name),
                ))
            }
        }

        fn parse_non_ts_functional_pseudo_class<'t>(
            &self,
            name: CowRcStr<'i>,
            arguments: &mut cssparser::Parser<'i, 't>,
            _after_part: bool,
        ) -> Result<PseudoClass, ParseError<'i, Self::Error>> {
            if self.0 != Dialect::Permissive || !JS_FUNCTIONAL.contains(&name.as_ref()) {
                return Err(arguments.new_custom_error(
                    SelectorParseErrorKind::UnsupportedPseudoClassOrElement(name),
                ));
            }
            while arguments.next_including_whitespace().is_ok() {}
            Ok(PseudoClass(name.to_string()))
        }

        fn parse_pseudo_element(
            &self,
            location: SourceLocation,
            name: CowRcStr<'i>,
        ) -> Result<PseudoElement, ParseError<'i, Self::Error>> {
            if ELEMENTS.contains(&name.as_ref()) {
                Ok(PseudoElement(name.to_string()))
            } else {
                Err(location.new_custom_error(
                    SelectorParseErrorKind::UnsupportedPseudoClassOrElement(name),
                ))
            }
        }
    }

    /// Selector parsing only needs the syntax, so every string type is a
    /// plain string.
    #[derive(Debug, Clone, PartialEq, Eq, Hash, Default)]
    pub(super) struct Ident(String);

    impl From<&str> for Ident {
        fn from(s: &str) -> Self {
            Ident(s.to_string())
        }
    }

    impl ToCss for Ident {
        fn to_css<W: Write>(&self, dest: &mut W) -> fmt::Result {
            dest.write_str(&self.0)
        }
    }

    impl PrecomputedHash for Ident {
        fn precomputed_hash(&self) -> u32 {
            let mut hasher = DefaultHasher::new();
            self.0.hash(&mut hasher);
            hasher.finish() as u32
        }
    }

    #[derive(Debug, Clone, PartialEq, Eq)]
    pub(super) struct Impl;

    impl selectors::parser::SelectorImpl for Impl {
        type ExtraMatchingData<'a> = ();
        type AttrValue = Ident;
        type Identifier = Ident;
        type LocalName = Ident;
        type NamespaceUrl = Ident;
        type NamespacePrefix = Ident;
        type BorrowedNamespaceUrl = Ident;
        type BorrowedLocalName = Ident;
        type NonTSPseudoClass = PseudoClass;
        type PseudoElement = PseudoElement;
    }

    #[derive(Debug, Clone, PartialEq, Eq)]
    pub(super) struct PseudoClass(String);

    impl selectors::parser::NonTSPseudoClass for PseudoClass {
        type Impl = Impl;

        fn is_active_or_hover(&self) -> bool {
            self.0 == "active" || self.0 == "hover"
        }

        fn is_user_action_state(&self) -> bool {
            self.is_active_or_hover() || self.0 == "focus"
        }
    }

    impl ToCss for PseudoClass {
        fn to_css<W: Write>(&self, dest: &mut W) -> fmt::Result {
            write!(dest, ":{}", self.0)
        }
    }

    #[derive(Debug, Clone, PartialEq, Eq)]
    pub(super) struct PseudoElement(String);

    impl selectors::parser::PseudoElement for PseudoElement {
        type Impl = Impl;
    }

    impl ToCss for PseudoElement {
        fn to_css<W: Write>(&self, dest: &mut W) -> fmt::Result {
            write!(dest, "::{}", self.0)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ast::{CosmeticBody, CosmeticRule, DomainList, DomainMatcher, SourceRef};
    use crate::webkit::to_json;
    use std::path::Path;
    use std::process::Command;
    use std::time::Instant;

    /// Test-side builder for cosmetic rules.
    #[derive(Clone)]
    struct R {
        exception: bool,
        body: CosmeticBody,
        include: Vec<String>,
        exclude: Vec<String>,
        path: Option<String>,
    }

    fn hide(selector: &str) -> R {
        R::new(false, CosmeticBody::Hide(selector.into()))
    }

    fn exc(selector: &str) -> R {
        R::new(true, CosmeticBody::Hide(selector.into()))
    }

    fn proc_(text: &str) -> R {
        R::new(false, CosmeticBody::Procedural(text.into()))
    }

    fn proc_exc(text: &str) -> R {
        R::new(true, CosmeticBody::Procedural(text.into()))
    }

    impl R {
        fn new(exception: bool, body: CosmeticBody) -> Self {
            R {
                exception,
                body,
                include: vec![],
                exclude: vec![],
                path: None,
            }
        }
        fn on(mut self, domain: &str) -> Self {
            self.include.push(domain.into());
            self
        }
        fn off(mut self, domain: &str) -> Self {
            self.exclude.push(domain.into());
            self
        }
        fn path(mut self, path: &str) -> Self {
            self.path = Some(path.into());
            self
        }
        fn build(&self) -> CosmeticRule {
            let matcher = |d: &str| {
                if let Some(e) = d.strip_suffix(".*") {
                    DomainMatcher::Entity(e.into())
                } else if d.starts_with('/') {
                    DomainMatcher::Regex(d.trim_matches('/').into())
                } else {
                    DomainMatcher::Hostname(d.into())
                }
            };
            let domains = DomainList {
                include: self.include.iter().map(|d| matcher(d)).collect(),
                exclude: self.exclude.iter().map(|d| matcher(d)).collect(),
            };
            let marker = if self.exception { "#@#" } else { "##" };
            let body = match &self.body {
                CosmeticBody::Hide(s) => s.clone(),
                CosmeticBody::Procedural(s) => s.clone(),
            };
            let raw_domains: Vec<String> = self
                .include
                .iter()
                .cloned()
                .chain(self.exclude.iter().map(|d| format!("~{d}")))
                .collect();
            let raw = format!("{}{marker}{body}", raw_domains.join(","));
            CosmeticRule {
                source: SourceRef { list: 0, line: 1 },
                raw,
                exception: self.exception,
                domains,
                matches_path: self.path.clone(),
                body: self.body.clone(),
            }
        }
    }

    fn safari(major: u16, minor: u16) -> CompileOptions {
        CompileOptions {
            safari: SafariVersion::new(major, minor),
        }
    }

    /// Compiles at Safari 17.0 and returns the JSON plus runtime lines.
    fn run(rules: &[R]) -> (String, Vec<String>) {
        run_at(rules, safari(17, 0))
    }

    fn run_at(rules: &[R], opts: CompileOptions) -> (String, Vec<String>) {
        let rules: Vec<CosmeticRule> = rules.iter().map(R::build).collect();
        let mut out = Vec::new();
        let mut runtime = Vec::new();
        let mut stats = Stats::default();
        compile(&rules, &opts, &mut out, &mut runtime, &mut stats);
        let webkit: Vec<WkRule> = out.into_iter().map(|t| t.rule).collect();
        (to_json(&webkit), runtime)
    }

    fn json(rules: &[R]) -> String {
        run(rules).0
    }

    fn assert_runtime(rules: &[R], expected: &[&str]) {
        let (json, runtime) = run(rules);
        assert_eq!(json, "[]");
        assert_eq!(runtime, expected);
    }

    #[test]
    fn generic_hide_is_one_rule() {
        assert_eq!(
            json(&[hide(".ad")]),
            r#"[{"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".ad"}}]"#
        );
    }

    #[test]
    fn generic_hides_are_sorted_and_deduped() {
        assert_eq!(
            json(&[hide(".b"), hide(".a"), hide(".b")]),
            r#"[{"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".a, .b"}}]"#
        );
    }

    #[test]
    fn generic_hides_are_chunked_at_250() {
        let rules: Vec<R> = (0..251).map(|i| hide(&format!(".a{i:03}"))).collect();
        let (out, _) = run(&rules);
        let parsed: Vec<WkRule> = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed.len(), 2);
        let count = |r: &WkRule| match &r.action {
            WkAction::CssDisplayNone { selector } => selector.split(", ").count(),
            _ => 0,
        };
        assert_eq!(count(&parsed[0]), 250);
        assert_eq!(count(&parsed[1]), 1);
    }

    #[test]
    fn domain_hide_uses_if_domain_with_subdomains() {
        assert_eq!(
            json(&[hide(".ad").on("example.com")]),
            r#"[{"trigger":{"url-filter":".*","resource-type":["document"],"if-domain":["*example.com"]},"action":{"type":"css-display-none","selector":".ad"}}]"#
        );
    }

    #[test]
    fn same_domain_set_shares_one_rule() {
        assert_eq!(
            json(&[hide(".b").on("example.com"), hide(".a").on("example.com")]),
            r#"[{"trigger":{"url-filter":".*","resource-type":["document"],"if-domain":["*example.com"]},"action":{"type":"css-display-none","selector":".a, .b"}}]"#
        );
    }

    #[test]
    fn different_domain_sets_get_separate_rules() {
        assert_eq!(
            json(&[hide(".a").on("example.com"), hide(".a").on("example.org")]),
            concat!(
                r#"[{"trigger":{"url-filter":".*","resource-type":["document"],"if-domain":["*example.com"]},"action":{"type":"css-display-none","selector":".a"}},"#,
                r#"{"trigger":{"url-filter":".*","resource-type":["document"],"if-domain":["*example.org"]},"action":{"type":"css-display-none","selector":".a"}}]"#
            )
        );
    }

    #[test]
    fn multiple_include_domains_share_if_domain_list() {
        assert_eq!(
            json(&[hide(".a").on("example.org").on("example.com")]),
            r#"[{"trigger":{"url-filter":".*","resource-type":["document"],"if-domain":["*example.com","*example.org"]},"action":{"type":"css-display-none","selector":".a"}}]"#
        );
    }

    #[test]
    fn exclude_only_hide_is_unless_domain_generic() {
        assert_eq!(
            json(&[hide(".a").off("example.com")]),
            r#"[{"trigger":{"url-filter":".*","resource-type":["document"],"unless-domain":["*example.com"]},"action":{"type":"css-display-none","selector":".a"}}]"#
        );
    }

    #[test]
    fn include_and_exclude_go_to_runtime() {
        assert_runtime(
            &[hide(".a").on("example.com").off("sub.example.com")],
            &["example.com,~sub.example.com##.a"],
        );
    }

    #[test]
    fn entity_hide_uses_if_top_url() {
        assert_eq!(
            json(&[hide(".a").on("example.*")]),
            concat!(
                r#"[{"trigger":{"url-filter":".*","resource-type":["document"],"if-top-url":["^[^:]+:\\/\\/([^\\/:]+\\.)?example\\.(com?\\.)?[^\\/:.]+([:\\/?#].*)?$"]},"#,
                r#""action":{"type":"css-display-none","selector":".a"}}]"#
            )
        );
    }

    #[test]
    fn entity_hide_is_runtime_below_16_4() {
        let (json, runtime) = run_at(&[hide(".a").on("example.*")], safari(16, 0));
        assert_eq!(json, "[]");
        assert_eq!(runtime, vec!["example.*##.a"]);
    }

    #[test]
    fn entity_exclude_goes_to_runtime() {
        assert_runtime(&[hide(".a").off("example.*")], &["~example.*##.a"]);
    }

    #[test]
    fn regex_domain_goes_to_runtime() {
        assert_runtime(&[hide(".a").on("/ex.*le/")], &["/ex.*le/##.a"]);
    }

    #[test]
    fn procedural_goes_to_runtime() {
        assert_runtime(&[proc_(r#"div:has-text(ad)"#)], &["##div:has-text(ad)"]);
    }

    #[test]
    fn procedural_exception_goes_to_runtime() {
        assert_runtime(&[proc_exc("div:has-text(ad)")], &["#@#div:has-text(ad)"]);
    }

    #[test]
    fn has_selector_is_native_at_16_4() {
        let (out, runtime) = run_at(&[hide("div:has(> a)")], safari(16, 4));
        assert!(runtime.is_empty());
        assert_eq!(
            out,
            r#"[{"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":"div:has(> a)"}}]"#
        );
    }

    #[test]
    fn has_selector_goes_to_runtime_below_16_4() {
        let (out, runtime) = run_at(&[hide("div:has(> a)")], safari(16, 0));
        assert_eq!(out, "[]");
        assert_eq!(runtime, vec!["##div:has(> a)"]);
    }

    #[test]
    fn is_selector_needs_14() {
        let (out, _) = run_at(&[hide(":is(.a, .b)")], safari(14, 0));
        assert!(out.contains(":is(.a, .b)"));
        let (out, runtime) = run_at(&[hide(":is(.a, .b)")], safari(13, 1));
        assert_eq!(out, "[]");
        assert_eq!(runtime, vec!["##:is(.a, .b)"]);
    }

    #[test]
    fn where_selector_needs_14() {
        let (out, runtime) = run_at(&[hide(":where(.a)")], safari(13, 0));
        assert_eq!(out, "[]");
        assert_eq!(runtime, vec!["##:where(.a)"]);
    }

    #[test]
    fn focus_visible_needs_15_4() {
        let (out, runtime) = run_at(&[hide("a:focus-visible")], safari(15, 0));
        assert_eq!(out, "[]");
        assert_eq!(runtime, vec!["##a:focus-visible"]);
    }

    #[test]
    fn unknown_pseudo_class_is_dropped() {
        let (out, runtime) = run(&[hide("a:frobnicate")]);
        assert_eq!(out, "[]");
        assert!(runtime.is_empty());
    }

    #[test]
    fn js_only_selector_goes_to_runtime() {
        let (out, runtime) = run(&[hide("div:lang(en)"), hide("dialog:modal")]);
        assert_eq!(out, "[]");
        assert_eq!(runtime, vec!["##dialog:modal", "##div:lang(en)"]);
    }

    #[test]
    fn unknown_functional_pseudo_class_is_dropped() {
        let (out, runtime) = run(&[hide("a:frobnicate(x)")]);
        assert_eq!(out, "[]");
        assert!(runtime.is_empty());
    }

    #[test]
    fn invalid_selector_is_dropped() {
        let (out, runtime) = run(&[hide("div[")]);
        assert_eq!(out, "[]");
        assert!(runtime.is_empty());
    }

    #[test]
    fn invalid_selector_does_not_poison_group() {
        assert_eq!(
            json(&[hide(".a"), hide("div["), hide(".b")]),
            r#"[{"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".a, .b"}}]"#
        );
    }

    #[test]
    fn before_pseudo_element_is_native() {
        assert!(json(&[hide("a::before")]).contains("a::before"));
    }

    #[test]
    fn generic_exception_removes_generic_hide() {
        assert_eq!(
            json(&[hide(".a"), hide(".b"), exc(".a")]),
            json(&[hide(".b")])
        );
    }

    #[test]
    fn generic_exception_removes_specific_hide_too() {
        assert_eq!(json(&[hide(".a").on("example.com"), exc(".a")]), "[]");
    }

    #[test]
    fn domain_exception_excludes_generic_hide_on_domain_and_subdomains() {
        assert_eq!(
            json(&[hide(".a"), exc(".a").on("example.com")]),
            r#"[{"trigger":{"url-filter":".*","resource-type":["document"],"unless-domain":["*example.com"]},"action":{"type":"css-display-none","selector":".a"}}]"#
        );
    }

    #[test]
    fn domain_exception_merges_with_generic_exclude() {
        assert_eq!(
            json(&[hide(".a").off("x.org"), exc(".a").on("example.com")]),
            r#"[{"trigger":{"url-filter":".*","resource-type":["document"],"unless-domain":["*example.com","*x.org"]},"action":{"type":"css-display-none","selector":".a"}}]"#
        );
    }

    #[test]
    fn domain_exception_removes_same_domain_specific_hide() {
        assert_eq!(
            json(&[hide(".a").on("example.com"), exc(".a").on("example.com")]),
            "[]"
        );
    }

    #[test]
    fn domain_exception_removes_subdomain_specific_hide() {
        assert_eq!(
            json(&[
                hide(".a").on("sub.example.com"),
                exc(".a").on("example.com")
            ]),
            "[]"
        );
    }

    #[test]
    fn domain_exception_keeps_unrelated_specific_hide() {
        assert_eq!(
            json(&[hide(".a").on("example.org"), exc(".a").on("example.com")]),
            json(&[hide(".a").on("example.org")])
        );
    }

    #[test]
    fn exception_for_parent_of_excepted_host_goes_to_runtime() {
        // example.com keeps .a, sub.example.com must not get it. Safari cannot
        // express that without if-domain plus unless-domain.
        assert_runtime(
            &[
                hide(".a").on("example.com"),
                exc(".a").on("sub.example.com"),
            ],
            &["example.com##.a", "sub.example.com#@#.a"],
        );
    }

    #[test]
    fn exception_for_subdomain_unless_domain_on_generic_hide() {
        assert_eq!(
            json(&[hide(".a"), exc(".a").on("sub.example.com"), hide(".b")]),
            concat!(
                r#"[{"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".b"}},"#,
                r#"{"trigger":{"url-filter":".*","resource-type":["document"],"unless-domain":["*sub.example.com"]},"action":{"type":"css-display-none","selector":".a"}}]"#
            )
        );
    }

    #[test]
    fn exception_with_excludes_goes_to_runtime() {
        assert_runtime(
            &[hide(".a"), exc(".a").off("x.com")],
            &["##.a", "~x.com#@#.a"],
        );
    }

    #[test]
    fn exception_with_entity_goes_to_runtime() {
        assert_runtime(
            &[hide(".a").on("example.com"), exc(".a").on("example.*")],
            &["example.*#@#.a", "example.com##.a"],
        );
    }

    #[test]
    fn exception_for_runtime_hide_goes_to_runtime() {
        // Safari rejects :has below 16.4, so the hide is runtime. The generic
        // exception must follow it to runtime.
        let (out, runtime) = run_at(&[hide("div:has(a)"), exc("div:has(a)")], safari(16, 0));
        assert_eq!(out, "[]");
        assert_eq!(runtime, vec!["##div:has(a)", "#@#div:has(a)"]);
    }

    #[test]
    fn exception_with_excludes_on_other_selector_stays_native() {
        assert_eq!(
            json(&[hide(".a"), exc(".b").off("x.com")]),
            json(&[hide(".a")])
        );
    }

    #[test]
    fn unconditional_hide_drops_redundant_specific_copies() {
        assert_eq!(
            json(&[
                hide(".a"),
                hide(".a").on("example.com"),
                hide(".b").on("example.com")
            ]),
            concat!(
                r#"[{"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".a"}},"#,
                r#"{"trigger":{"url-filter":".*","resource-type":["document"],"if-domain":["*example.com"]},"action":{"type":"css-display-none","selector":".b"}}]"#
            )
        );
    }

    #[test]
    fn generic_and_specific_are_in_separate_tiers() {
        let rules = [hide(".a").on("example.com"), hide(".b")];
        let rules: Vec<CosmeticRule> = rules.iter().map(R::build).collect();
        let mut out = Vec::new();
        let mut runtime = Vec::new();
        let mut stats = Stats::default();
        compile(&rules, &safari(17, 0), &mut out, &mut runtime, &mut stats);
        let tiers: Vec<Tier> = out.iter().map(|t| t.tier).collect();
        assert_eq!(tiers, vec![Tier::GenericHide, Tier::SpecificHide]);
    }

    #[test]
    fn matches_path_generic_is_top_url_generic_tier() {
        let rules = [hide(".a").path("/news")];
        let rules: Vec<CosmeticRule> = rules.iter().map(R::build).collect();
        let mut out = Vec::new();
        let mut runtime = Vec::new();
        let mut stats = Stats::default();
        compile(&rules, &safari(17, 0), &mut out, &mut runtime, &mut stats);
        assert_eq!(out[0].tier, Tier::GenericHide);
    }

    #[test]
    fn matches_path_generic_uses_if_top_url() {
        assert_eq!(
            json(&[hide(".a").path("/news")]),
            concat!(
                r#"[{"trigger":{"url-filter":".*","resource-type":["document"],"if-top-url":["^[^:]+:\\/\\/[^\\/]+(:[^\\/#]*)?\\/[^#]*\\/news[^#]*","^[^:]+:\\/\\/[^\\/]+(:[^\\/#]*)?\\/news[^#]*"]},"#,
                r#""action":{"type":"css-display-none","selector":".a"}}]"#
            )
        );
    }

    #[test]
    fn matches_path_with_domain_is_one_top_url_condition() {
        assert_eq!(
            json(&[hide(".a").on("example.com").path("news")]),
            concat!(
                r#"[{"trigger":{"url-filter":".*","resource-type":["document"],"if-top-url":["^[^:]+:\\/\\/([^\\/:]+\\.)?example\\.com(:[^\\/#]*)?\\/[^#]*news[^#]*"]},"#,
                r#""action":{"type":"css-display-none","selector":".a"}}]"#
            )
        );
    }

    #[test]
    fn matches_path_below_16_4_goes_to_runtime() {
        let (out, runtime) = run_at(&[hide(".a").path("/news")], safari(16, 0));
        assert_eq!(out, "[]");
        assert_eq!(runtime, vec!["##.a"]);
    }

    #[test]
    fn matches_path_with_exclude_goes_to_runtime() {
        assert_runtime(&[hide(".a").off("x.com").path("/news")], &["~x.com##.a"]);
    }

    #[test]
    fn matches_path_regex_goes_to_runtime() {
        assert_runtime(&[hide(".a").path("/n\\d+/")], &["##.a"]);
    }

    #[test]
    fn matches_path_exception_only_cancels_same_path() {
        assert_eq!(
            json(&[hide(".a").path("/news"), exc(".a")]),
            json(&[hide(".a").path("/news")])
        );
        assert_eq!(
            json(&[hide(".a").path("/news"), exc(".a").path("/news")]),
            "[]"
        );
    }

    #[test]
    fn matches_path_exception_with_domain_goes_to_runtime() {
        assert_runtime(
            &[
                hide(".a").path("/news"),
                exc(".a").path("/news").on("example.com"),
            ],
            &["##.a", "example.com#@#.a"],
        );
    }

    #[test]
    fn exception_and_hide_key_on_matches_path() {
        // A plain exception does not cancel a path-restricted hide's key.
        let (out, _) = run(&[hide(".a").path("/x"), exc(".a").on("example.com")]);
        assert!(out.contains("if-top-url"));
    }

    #[test]
    fn non_ascii_domain_goes_to_runtime() {
        assert_runtime(
            &[hide(".a").on("ex\u{e4}mple.com").path("/x")],
            &["ex\u{e4}mple.com##.a"],
        );
    }

    #[test]
    fn duplicate_runtime_lines_are_deduped() {
        assert_runtime(
            &[proc_("p:has-text(a)"), proc_("p:has-text(a)")],
            &["##p:has-text(a)"],
        );
    }

    #[test]
    fn exception_without_hide_is_a_no_op() {
        assert_eq!(json(&[exc(".a").on("example.com")]), "[]");
    }

    #[test]
    fn entity_and_host_share_selector_in_both_triggers() {
        assert_eq!(
            json(&[hide(".a").on("example.com").on("example.*")]),
            concat!(
                r#"[{"trigger":{"url-filter":".*","resource-type":["document"],"if-domain":["*example.com"]},"action":{"type":"css-display-none","selector":".a"}},"#,
                r#"{"trigger":{"url-filter":".*","resource-type":["document"],"if-top-url":["^[^:]+:\\/\\/([^\\/:]+\\.)?example\\.(com?\\.)?[^\\/:.]+([:\\/?#].*)?$"]},"action":{"type":"css-display-none","selector":".a"}}]"#
            )
        );
    }

    #[test]
    fn exception_removes_one_selector_only() {
        assert_eq!(
            json(&[
                hide(".a").on("example.com"),
                hide(".b").on("example.com"),
                exc(".a").on("example.com")
            ]),
            json(&[hide(".b").on("example.com")])
        );
    }

    #[test]
    fn exception_is_resolved_after_chunking_is_stable() {
        let mut rules: Vec<R> = (0..300).map(|i| hide(&format!(".x{i:03}"))).collect();
        rules.push(exc(".x000"));
        let (out, _) = run(&rules);
        let parsed: Vec<WkRule> = serde_json::from_str(&out).unwrap();
        let total: usize = parsed
            .iter()
            .map(|r| match &r.action {
                WkAction::CssDisplayNone { selector } => selector.split(", ").count(),
                _ => 0,
            })
            .sum();
        assert_eq!(total, 299);
    }

    #[test]
    fn selector_with_escape_is_valid() {
        assert!(json(&[hide(r".a\:b")]).contains(r#"".a\\:b""#));
    }

    #[test]
    fn attribute_selector_is_valid() {
        assert!(json(&[hide(r#"a[href^="http"]"#)]).contains(r#"a[href^=\"http\"]"#));
    }

    #[test]
    fn empty_selector_is_dropped() {
        assert_eq!(run(&[hide("")]).0, "[]");
    }

    /// Test-only stand-in for the line parser: splits EasyList cosmetic lines
    /// into rules. Lines it does not understand are skipped.
    fn easylist_cosmetics(text: &str) -> Vec<CosmeticRule> {
        const PROCEDURAL: &[&str] = &[
            ":-abp-",
            ":has-text(",
            ":contains(",
            ":upward(",
            ":xpath(",
            ":matches-css",
            ":min-text-length(",
            ":others(",
            ":matches-attr(",
            ":matches-prop",
            ":nth-ancestor(",
            ":if(",
            ":if-not(",
            ":watch-attr(",
            ":style(",
            ":remove(",
            ":remove-attr(",
            ":remove-class(",
        ];
        let mut rules = Vec::new();
        for (i, line) in text.lines().enumerate() {
            if line.is_empty() || line.starts_with('!') || line.starts_with('[') {
                continue;
            }
            let Some((at, marker)) = ["#@#", "#?#", "##"]
                .iter()
                .filter_map(|m| line.find(m).map(|at| (at, *m)))
                .min()
            else {
                continue;
            };
            let (domains, mut body) = (&line[..at], &line[at + marker.len()..]);
            if body.is_empty()
                || body.starts_with(['+', '^'])
                || body.contains('{')
                || domains.contains(['[', '$'])
            {
                continue;
            }
            if !line.is_ascii() {
                continue;
            }
            let mut include = Vec::new();
            let mut exclude = Vec::new();
            let mut skip = false;
            for d in domains.split(',').filter(|d| !d.is_empty()) {
                let (list, name) = match d.strip_prefix('~') {
                    Some(name) => (&mut exclude, name),
                    None => (&mut include, d),
                };
                if name.starts_with('/') {
                    skip = true;
                    break;
                }
                list.push(match name.strip_suffix(".*") {
                    Some(e) => DomainMatcher::Entity(e.to_lowercase()),
                    None => DomainMatcher::Hostname(name.to_lowercase()),
                });
            }
            if skip {
                continue;
            }
            let mut matches_path = None;
            if let Some(start) = body.find(":matches-path(") {
                let arg_start = start + ":matches-path(".len();
                let Some(len) = body[arg_start..].find(')') else {
                    continue;
                };
                matches_path = Some(body[arg_start..arg_start + len].to_string());
                body = &body[..start];
            }
            let procedural = marker == "#?#" || PROCEDURAL.iter().any(|p| body.contains(p));
            let body = if procedural {
                CosmeticBody::Procedural(body.to_string())
            } else {
                CosmeticBody::Hide(body.to_string())
            };
            rules.push(CosmeticRule {
                source: SourceRef {
                    list: 0,
                    line: i as u32 + 1,
                },
                raw: line.to_string(),
                exception: marker == "#@#",
                domains: DomainList { include, exclude },
                matches_path,
                body,
            });
        }
        rules
    }

    #[test]
    fn easylist_cosmetics_compile_and_webkit_accepts() {
        let list = Path::new("/tmp/research/bench/easylist.txt");
        let wk = Path::new("/tmp/research/bench/wk");
        if !list.exists() || !wk.exists() {
            return;
        }
        let text = std::fs::read_to_string(list).unwrap();
        let rules = easylist_cosmetics(&text);
        let opts = safari(26, 0);

        let mut out = Vec::new();
        let mut runtime = Vec::new();
        let mut stats = Stats::default();
        let started = Instant::now();
        compile(&rules, &opts, &mut out, &mut runtime, &mut stats);
        let elapsed = started.elapsed();

        let webkit: Vec<WkRule> = out.into_iter().map(|t| t.rule).collect();
        let selectors: usize = webkit
            .iter()
            .map(|r| match &r.action {
                WkAction::CssDisplayNone { selector } => selector.split(", ").count(),
                _ => 0,
            })
            .sum();
        let dropped: u64 = stats.dropped.values().sum();
        eprintln!(
            "easylist cosmetic lines: {}; native selectors: {} in {} rules; runtime lines: {}; dropped: {}; compile: {:?}",
            rules.len(),
            selectors,
            webkit.len(),
            runtime.len(),
            dropped,
            elapsed
        );
        if !cfg!(debug_assertions) {
            assert!(elapsed.as_millis() < 100, "compile took {elapsed:?}");
        }

        let path = std::env::temp_dir().join("wbe-cosmetic-easylist.json");
        std::fs::write(&path, to_json(&webkit)).unwrap();
        let output = Command::new(wk).arg(&path).output().unwrap();
        let stdout = String::from_utf8_lossy(&output.stdout);
        assert!(output.status.success(), "{stdout}");
        assert!(stdout.trim_end().ends_with(" ok"), "{stdout}");
    }
}
