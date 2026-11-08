//! Per-page engine for rules Safari cannot enforce natively: procedural
//! cosmetics, `:style`/`:remove` actions, and scriptlets. Queried by the
//! wBlock Scripts extension's native handler for each frame.
//! Cosmetic matching is brave/adblock-rust's. Scriptlets are matched here and
//! returned as calls, because the extension must inject them as files (a
//! script string would be subject to the page's CSP). The lines come from
//! `compile`, which already dropped untrusted `trusted-*` scriptlets.

use crate::ast::{CosmeticBody, DomainList, DomainMatcher, ExceptionScope, ParsedLine, Party, Rule};
use adblock::lists::{FilterSet, ParseOptions, RuleTypes};
use adblock::resources::PermissionMask;
use serde::de::DeserializeOwned;
use serde::Serialize;
use std::cmp::Ordering;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::OnceLock;

pub struct Engine {
    cosmetic: adblock::Engine,
    /// Generic hides and every exception, for pages under `$specifichide`.
    generic: adblock::Engine,
    elemhide: adblock::Engine,
    document: adblock::Engine,
    genericblock: adblock::Engine,
    /// Flags the pages with a `$specifichide` exception, via `$generichide`.
    specifichide: adblock::Engine,
    scriptlets: Scriptlets,
    popups: Scriptlets,
    /// Each popup call's rule, required literal, and regex, built on first use.
    popup_rules: OnceLock<Vec<(Option<PopupRule>, String, OnceLock<Option<regex::Regex>>)>>,
}

/// Cosmetic actions for one page URL.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct PagePayload {
    /// Selectors to hide with `display: none !important`.
    pub hide: Vec<String>,
    /// Stylesheets that cannot be expressed as native hide actions.
    pub styles: Vec<String>,
    /// JSON-encoded procedural filters and actions.
    pub procedural: Vec<String>,
    /// Scriptlet calls, each `[name, args...]`, in rule order.
    pub scriptlets: Vec<Vec<String>>,
    /// True when a `$generichide` exception applies to the page.
    pub generichide: bool,
    /// Present only for a popup-target lookup on the opener URL.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub popup_blocked: Option<bool>,
}

/// Scriptlet calls and the rules that select them, read in place. Loading an
/// engine copies these tables and decodes global calls once; a lookup decodes
/// only the remaining entries for its host.
struct Scriptlets {
    /// Entry `i` is call `i`; keys are empty.
    calls: Table,
    /// Keyed by hostname or entity (`name.*`); `""` holds generic ones
    /// (cosmetic-filtering.js semantics). Values: `(call id, exclude)`.
    rules: Table,
    /// Keyed like `rules`. Values: call ids, or `null` for `#@#+js()`.
    exceptions: Table,
    regexes: regex::RegexSet,
    // Global calls are consulted on every page; keep their scopes decoded.
    generic_rules: Vec<(u32, HashSet<String>)>,
    generic_calls: HashMap<u32, Vec<String>>,
}

/// Scriptlet rules as `Engine::build` collects them.
#[derive(Default)]
struct ScriptletRules {
    calls: Vec<Vec<String>>,
    index: HashMap<Vec<String>, u32>,
    rules: BTreeMap<String, Vec<(u32, Vec<DomainMatcher>)>>,
    exceptions: BTreeMap<String, Vec<(Option<u32>, Vec<DomainMatcher>)>>,
    regexes: HashMap<String, regex::Regex>,
}

impl ScriptletRules {
    fn add(&mut self, exception: bool, domains: DomainList, call: Vec<String>) {
        for matcher in domains.include.iter().chain(&domains.exclude) {
            if let DomainMatcher::Regex(pattern) = matcher {
                if !self.regexes.contains_key(pattern) {
                    if let Ok(regex) = regex::Regex::new(pattern) {
                        self.regexes.insert(pattern.clone(), regex);
                    }
                }
            }
        }
        let id = (!call[0].is_empty()).then(|| {
            *self.index.entry(call.clone()).or_insert_with(|| {
                self.calls.push(call);
                self.calls.len() as u32 - 1
            })
        });
        let mut keys: Vec<String> = domains
            .include
            .iter()
            .map(|m| match m {
                DomainMatcher::Hostname(h) | DomainMatcher::Entity(h) => key(m, h),
                DomainMatcher::Regex(r) => format!("/{r}/"),
            })
            .collect();
        if domains.include.is_empty() {
            keys.push(String::new());
        }
        for k in keys {
            if exception {
                self.exceptions.entry(k).or_default().push((id, domains.exclude.clone()));
            } else if let Some(id) = id {
                self.rules
                    .entry(k)
                    .or_default()
                    .push((id, domains.exclude.clone()));
            }
        }
    }

    fn finish(self) -> Scriptlets {
        let rules = Table::encode(self.rules.iter().map(|(k, v)| (k.as_str(), v)));
        let regexes = regex::RegexSet::new(self.regexes.keys()).expect("validated domain regexes");
        let generic_rules = generic_rules(&rules, &regexes);
        let calls = Table::encode(self.calls.iter().map(|call| ("", call)));
        Scriptlets {
            generic_calls: generic_rules.iter().map(|(id, _)| (*id, calls.decode_at(*id as usize))).collect(),
            calls,
            rules,
            exceptions: Table::encode(self.exceptions.iter().map(|(k, v)| (k.as_str(), v))),
            regexes,
            generic_rules,
        }
    }
}

/// Read-only map from byte keys to JSON values, in sorted key order.
/// Layout, u32 LE: `n`, `n + 1` key ends, `n + 1` value ends, key bytes,
/// value bytes. Lookups binary-search the keys in place.
struct Table(Vec<u8>);

impl Table {
    fn encode<'a, V: Serialize + 'a>(entries: impl Iterator<Item = (&'a str, &'a V)>) -> Self {
        let (mut key_ends, mut value_ends) = (vec![0u32], vec![0u32]);
        let (mut keys, mut values) = (Vec::new(), Vec::new());
        for (key, value) in entries {
            keys.extend_from_slice(key.as_bytes());
            values.extend(serde_json::to_vec(value).expect("scriptlet entry serializes"));
            key_ends.push(keys.len() as u32);
            value_ends.push(values.len() as u32);
        }
        let mut bytes = (key_ends.len() as u32 - 1).to_le_bytes().to_vec();
        for end in key_ends.iter().chain(&value_ends) {
            bytes.extend(end.to_le_bytes());
        }
        bytes.extend(keys);
        bytes.extend(values);
        Self(bytes)
    }

    fn parse(bytes: &[u8]) -> Result<Self, String> {
        let malformed = || "engine: malformed scriptlets".to_string();
        let word = |at: usize| {
            bytes
                .get(at..at + 4)
                .map(|w| u32::from_le_bytes(w.try_into().unwrap()) as usize)
        };
        let n = word(0).ok_or_else(malformed)?;
        let header = 4 + 8 * (n + 1);
        if bytes.len() < header {
            return Err(malformed());
        }
        let key_end = |i: usize| word(4 + 4 * i).expect("header checked");
        let value_end = |i: usize| word(4 + 4 * (n + 1) + 4 * i).expect("header checked");
        let ordered = (0..=n)
            .all(|i| i == 0 || (key_end(i - 1) <= key_end(i) && value_end(i - 1) <= value_end(i)));
        if !ordered || key_end(0) != 0 || value_end(0) != 0 {
            return Err(malformed());
        }
        if header + key_end(n) + value_end(n) != bytes.len() {
            return Err(malformed());
        }
        Ok(Self(bytes.to_vec()))
    }

    fn len(&self) -> usize {
        u32::from_le_bytes(self.0[..4].try_into().unwrap()) as usize
    }

    fn word(&self, at: usize) -> usize {
        u32::from_le_bytes(self.0[at..at + 4].try_into().unwrap()) as usize
    }

    fn keys_at(&self) -> usize {
        4 + 8 * (self.len() + 1)
    }

    fn key(&self, i: usize) -> &[u8] {
        let base = self.keys_at();
        &self.0[base + self.word(4 + 4 * i)..base + self.word(4 + 4 * (i + 1))]
    }

    fn value(&self, i: usize) -> &[u8] {
        let n = self.len();
        let base = self.keys_at() + self.word(4 + 4 * n);
        let ends = 4 + 4 * (n + 1);
        &self.0[base + self.word(ends + 4 * i)..base + self.word(ends + 4 * (i + 1))]
    }

    /// The value at `i`, or the default when it does not decode.
    fn decode_at<T: DeserializeOwned + Default>(&self, i: usize) -> T {
        serde_json::from_slice(self.value(i)).unwrap_or_default()
    }

    /// The value for `key`, or the default when there is none.
    fn get<T: DeserializeOwned + Default>(&self, key: &str) -> T {
        let (mut lo, mut hi) = (0, self.len());
        while lo < hi {
            let mid = (lo + hi) / 2;
            match self.key(mid).cmp(key.as_bytes()) {
                Ordering::Less => lo = mid + 1,
                Ordering::Greater => hi = mid,
                Ordering::Equal => return self.decode_at(mid),
            }
        }
        T::default()
    }
}

impl Scriptlets {
    fn call(&self, id: u32) -> Vec<String> {
        self.generic_calls.get(&id).cloned().unwrap_or_else(|| self.calls.decode_at(id as usize))
    }

    /// The `wbe:css` and `wbe:procedural` rule of `id` applies to one site.
    fn page_cosmetic(&self, id: u32) -> bool {
        self.call(id).first().is_some_and(|name| matches!(name.as_str(), "wbe:css" | "wbe:procedural"))
    }

    /// The call ids that apply to `host`, the ids excepted there, and whether
    /// `#@#+js()` applies. `site_cosmetic` false leaves out the site-specific
    /// styles and procedurals (`$specifichide`); generic ones and all other
    /// scriptlets stay.
    fn ids(&self, host: &str, site_cosmetic: bool) -> (Vec<u32>, HashSet<u32>, bool) {
        let mut keys = host_keys(host);
        keys.extend(self.regexes.matches(host).iter().map(|i| format!("/{}/", self.regexes.patterns()[i])));
        let mut excepted = HashSet::new();
        let mut all_scriptlets_excepted = false;
        for k in &keys {
            for (e, exclude) in self.exceptions.get::<Vec<(Option<u32>, Vec<DomainMatcher>)>>(k) {
                if exclude.iter().any(|m| scope_matches(m, &keys, &self.regexes)) { continue; }
                match e {
                    None => all_scriptlets_excepted = true,
                    Some(id) => {
                        excepted.insert(id);
                    }
                }
            }
        }
        let mut ids: Vec<u32> = self.generic_rules.iter()
            .filter(|(_, excluded)| !keys.iter().any(|k| excluded.contains(k)))
            .map(|(id, _)| *id).collect();
        for k in keys.iter().filter(|k| !k.is_empty()) {
            for (id, exclude) in self.rules.get::<Vec<(u32, Vec<DomainMatcher>)>>(k) {
                if !exclude.iter().any(|m| scope_matches(m, &keys, &self.regexes))
                    && (site_cosmetic || !self.page_cosmetic(id))
                {
                    ids.push(id);
                }
            }
        }
        ids.retain(|id| !excepted.contains(id)
            && (!all_scriptlets_excepted || self.call(*id).first().is_some_and(|name| matches!(name.as_str(), "wbe:css" | "wbe:procedural" | "wbe:popup"))));
        ids.sort_unstable();
        ids.dedup();
        (ids, excepted, all_scriptlets_excepted)
    }

    fn lookup(&self, host: &str, site_cosmetic: bool) -> Vec<Vec<String>> {
        let (ids, excepted, all_scriptlets_excepted) = self.ids(host, site_cosmetic);
        let mut calls: Vec<Vec<String>> = ids.into_iter().map(|id| self.call(id)).collect();
        // Pair matched response rules with Safari's player requests and watch mode.
        const REQUEST: &str = "trusted-youtube-player-request";
        let request_excepted = excepted
            .iter()
            .any(|id| self.call(*id).as_slice() == [REQUEST]);
        if matches!(host, "youtube.com" | "www.youtube.com")
            && !all_scriptlets_excepted
            && !request_excepted
            && calls.iter().any(|call| {
                call.len() == 4
                    && matches!(
                        call[0].as_str(),
                        "trusted-replace-fetch-response" | "trusted-replace-xhr-response"
                    )
                    && matches!(call[1].as_str(), "\"adPlacements\"" | "\"adSlots\"")
                    && call[2] == "\"no_ads\""
            })
        {
            if !calls.iter().any(|call| call.as_slice() == [REQUEST]) {
                calls.push(vec![REQUEST.to_string()]);
            }
            let watch = vec![
                "set-constant".to_string(),
                "ytcfg.data_.EXPERIMENT_FLAGS.web_streaming_watch".to_string(),
                "false".to_string(),
            ];
            if !calls.contains(&watch) && !excepted.iter().any(|id| self.call(*id) == watch) {
                calls.push(watch);
            }
        }
        calls
    }
}

fn key(m: &DomainMatcher, h: &str) -> String {
    match m {
        DomainMatcher::Entity(e) => format!("{e}.*"),
        _ => h.to_string(),
    }
}

/// `""`, the host and each parent, and the entity form (`label.*`) of each of
/// those that ends in the host's public suffix.
fn host_keys(host: &str) -> Vec<String> {
    let mut keys = vec![String::new()];
    let suffix = crate::registrable_domain(host)
        .and_then(|r| r.split_once('.'))
        .map(|(_, s)| s);
    let mut rest = host;
    loop {
        keys.push(rest.to_string());
        if let Some(entity) = suffix
            .and_then(|s| rest.strip_suffix(s))
            .filter(|e| e.len() > 1)
        {
            keys.push(format!("{entity}*"));
        }
        match rest.split_once('.') {
            Some((_, parent)) => rest = parent,
            None => break,
        }
    }
    keys
}

// A global rule can exclude thousands of hosts. Index those scopes once instead
// of scanning the complete exclusion list on every page.
fn generic_rules(rules: &Table, regexes: &regex::RegexSet) -> Vec<(u32, HashSet<String>)> {
    rules.get::<Vec<(u32, Vec<DomainMatcher>)>>("").into_iter().map(|(id, exclude)| {
        let keys = exclude.iter().map(|m| match m {
            DomainMatcher::Hostname(h) | DomainMatcher::Entity(h) => key(m, h),
            DomainMatcher::Regex(r) if regexes.patterns().contains(r) => format!("/{r}/"),
            DomainMatcher::Regex(_) => String::new(),
        }).collect();
        (id, keys)
    }).collect()
}

/// Invalid regex exclusions remain conservative and never widen a rule.
fn scope_matches(m: &DomainMatcher, keys: &[String], regexes: &regex::RegexSet) -> bool {
    match m {
        DomainMatcher::Regex(r) => !regexes.patterns().contains(r) || keys.contains(&format!("/{r}/")),
        DomainMatcher::Hostname(h) => keys.contains(h),
        DomainMatcher::Entity(h) => keys.contains(&key(m, h)),
    }
}

fn host_of(url: &str) -> &str {
    let rest = url.split_once("://").map_or(url, |(_, r)| r);
    let end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let host = &rest[..end];
    let host = host.rsplit_once('@').map_or(host, |(_, h)| h);
    host.rsplit_once(':')
        .filter(|(_, p)| p.bytes().all(|b| b.is_ascii_digit()))
        .map_or(host, |(h, _)| h)
}

impl Engine {
    /// `lines` are uBO-syntax cosmetic, procedural, and scriptlet rules.
    pub fn build(lines: &[String]) -> Self {
        let mut scriptlets = ScriptletRules::default();
        let mut popups = ScriptletRules::default();
        let mut cosmetic = Vec::new();
        let mut generic = Vec::new();
        let mut elemhide = Vec::new();
        let mut document = Vec::new();
        let mut genericblock = Vec::new();
        let mut specifichide = Vec::new();
        for line in lines {
            match crate::parse_line(line, Default::default()) {
                ParsedLine::Rule(Rule::Cosmetic(r)) if matches!(r.body, CosmeticBody::Style(_)) => {
                    if let CosmeticBody::Style(css) = r.body {
                        scriptlets.add(r.exception, r.domains, vec!["wbe:css".into(), css]);
                    }
                }
                ParsedLine::Rule(Rule::Cosmetic(r)) if matches!(r.body, CosmeticBody::Procedural(_)) => {
                    if let CosmeticBody::Procedural(selector) = r.body {
                        if let Ok(mut filter) = crate::parse::cosmetic::procedural(&selector) {
                            if let Some(path) = r.matches_path {
                                filter["selector"].as_array_mut().unwrap().insert(0, serde_json::json!({"type":"matches-path", "arg":path}));
                            }
                            scriptlets.add(r.exception, r.domains, vec!["wbe:procedural".into(), filter.to_string()]);
                        }
                    }
                }
                ParsedLine::Rule(Rule::Scriptlet(r)) => {
                    let call = std::iter::once(r.name).chain(r.args).collect();
                    scriptlets.add(r.exception, r.domains, call);
                }
                // `@@...$doc,popup` is both a popup allow and a page exception.
                ParsedLine::Rule(Rule::Network(r)) if r.types.contains(crate::ast::ResourceTypes::POPUP) || r.exception && !r.scope.is_empty() => {
                    if let Some(rule) = popup_rule(&r).ok().filter(|_| r.types.contains(crate::ast::ResourceTypes::POPUP)) {
                        // Network allow rules are candidates, not cosmetic exceptions.
                        // An allow keeps its opener domains: indexed for every
                        // opener, uBO's `@@$popup,domain=datanodes.to` allowed
                        // every popup on every site (#1072). Safari's tab event
                        // names the opener tab, so a frame-only allow can miss.
                        popups.add(false, r.from.clone(), vec!["wbe:popup".into(), serde_json::to_string(&rule).expect("popup rule serializes")]);
                    }
                    if r.scope.contains(ExceptionScope::GHIDE) {
                        cosmetic.push(line.as_str());
                        generic.push(line.as_str());
                    }
                    if r.scope.intersects(
                        ExceptionScope::EHIDE
                            | ExceptionScope::SHIDE
                            | ExceptionScope::DOC
                            | ExceptionScope::GENERICBLOCK,
                    ) {
                        let (pattern, options) = line.rsplit_once('$').unwrap_or((line, ""));
                        let options: Vec<&str> = options
                            .split(',')
                            .filter(|option| {
                                !matches!(
                                    *option,
                                    "elemhide"
                                        | "ehide"
                                        | "specifichide"
                                        | "shide"
                                        | "document"
                                        | "doc"
                                        | "generichide"
                                        | "ghide"
                                        | "genericblock"
                                        | "popup"
                                )
                            })
                            .collect();
                        let filter = format!(
                            "{pattern}$generichide{}",
                            if options.is_empty() {
                                String::new()
                            } else {
                                format!(",{}", options.join(","))
                            }
                        );
                        if r.scope.contains(ExceptionScope::EHIDE) {
                            elemhide.push(filter.clone());
                        }
                        if r.scope.contains(ExceptionScope::SHIDE) { specifichide.push(filter.clone()); }
                        if r.scope.contains(ExceptionScope::GENERICBLOCK) { genericblock.push(filter.clone()); }
                        if r.scope.contains(ExceptionScope::DOC) {
                            document.push(filter);
                        }
                    }
                }
                ParsedLine::Rule(Rule::Cosmetic(r)) => {
                    if r.exception || r.domains.include.is_empty() {
                        generic.push(line.as_str());
                    }
                    cosmetic.push(line.as_str());
                }
                ParsedLine::Rule(Rule::Network(_)) => cosmetic.push(line.as_str()),
                _ => {},
            }
        }
        Self {
            cosmetic: hide_engine(&cosmetic),
            generic: hide_engine(&generic),
            elemhide: exception_engine(&elemhide),
            document: exception_engine(&document),
            genericblock: exception_engine(&genericblock),
            specifichide: exception_engine(&specifichide),
            scriptlets: scriptlets.finish(),
            popups: popups.finish(),
            popup_rules: OnceLock::new(),
        }
    }

    /// Six length-prefixed adblock engines, then the runtime tables, each
    /// length-prefixed.
    pub fn serialize(&self) -> Vec<u8> {
        let mut out = Vec::new();
        for engine in [&self.cosmetic, &self.elemhide, &self.document, &self.genericblock, &self.generic, &self.specifichide] {
            put(&mut out, &engine.serialize());
        }
        for index in [&self.scriptlets, &self.popups] {
            for table in [&index.calls, &index.rules, &index.exceptions] { put(&mut out, &table.0); }
            let patterns: std::collections::BTreeSet<_> = index.regexes.patterns().iter().collect();
            put(&mut out, &serde_json::to_vec(&patterns).expect("regex patterns serialize"));
        }
        out
    }

    pub fn deserialize(bytes: &[u8]) -> Result<Self, String> {
        let mut rest = bytes;
        let cosmetic = read_engine(take(&mut rest)?)?;
        let elemhide = read_engine(take(&mut rest)?)?;
        let document = read_engine(take(&mut rest)?)?;
        let genericblock = read_engine(take(&mut rest)?)?;
        let generic = read_engine(take(&mut rest)?)?;
        let specifichide = read_engine(take(&mut rest)?)?;
        let scriptlets = read_index(&mut rest)?;
        let popups = read_index(&mut rest)?;
        Ok(Self {
            cosmetic,
            generic,
            elemhide,
            document,
            genericblock,
            specifichide,
            scriptlets,
            popups,
            popup_rules: OnceLock::new(),
        })
    }

    /// Normal page URLs return cosmetics and scriptlets. Internal
    /// `wbe-popup-https://opener/path#https://target/` URIs ask the same engine
    /// for a popup verdict while retaining the opener host for native site state.
    pub fn lookup(&self, url: &str) -> PagePayload {
        if let Some((source, target)) = url.strip_prefix("wbe-popup-").and_then(|query| query.split_once('#')) {
            let blocked = !self.document.url_cosmetic_resources(source).generichide
                && self.blocks_popup(source, target);
            return PagePayload { hide: vec![], styles: vec![], procedural: vec![], scriptlets: vec![], generichide: false, popup_blocked: Some(blocked) };
        }
        let specific_off = self.specifichide.url_cosmetic_resources(url).generichide;
        let r = if specific_off {
            self.generic.url_cosmetic_resources(url)
        } else {
            self.cosmetic.url_cosmetic_resources(url)
        };
        let document = self.document.url_cosmetic_resources(url).generichide;
        let elemhide = document || self.elemhide.url_cosmetic_resources(url).generichide;
        let mut scriptlets = if document { Vec::new() } else {
            self.scriptlets.lookup(&host_of(url).to_ascii_lowercase(), !specific_off)
        };
        let mut styles = Vec::new();
        let mut procedural = if elemhide { Vec::new() } else { sorted(r.procedural_actions) };

        scriptlets.retain(|call| {
            if call.first().is_some_and(|name| name == "wbe:css") {
                if !elemhide { styles.push(call[1].clone()); }
                false
            } else if call.first().is_some_and(|name| name == "wbe:procedural") {
                if !elemhide { procedural.push(call[1].clone()); }
                false
            } else { true }
        });
        PagePayload {
            styles,
            popup_blocked: None,
            hide: if elemhide {
                Vec::new()
            } else {
                sorted(r.hide_selectors)
            },
            procedural,
            scriptlets,
            generichide: elemhide || r.generichide,
        }
    }
    fn blocks_popup(&self, source: &str, target: &str) -> bool {
        // As uBO, data: and blob: targets are tested too; about:blank is where
        // every popup starts, before it reaches its URL.
        if !["http://", "https://", "blob:", "data:"].iter().any(|p| target.starts_with(p)) { return false; }
        let host = host_of(source).to_ascii_lowercase();
        let target_host = host_of(target).to_ascii_lowercase();
        let site = |h: &str| crate::registrable_domain(h).map_or_else(|| h.to_string(), str::to_string);
        let third = site(&host) != site(&target_host);
        let genericblock = self.genericblock.url_cosmetic_resources(source).generichide;
        let lowered = target.to_ascii_lowercase();
        let popups = self.popup_rules.get_or_init(|| {
            (0..self.popups.calls.len()).map(|id| {
                let call: Vec<String> = self.popups.calls.decode_at(id);
                let rule = call.get(1).and_then(|rule| serde_json::from_str::<PopupRule>(rule).ok());
                let needle = rule.as_ref().map(|r| required_literal(&r.pattern)).unwrap_or_default();
                (rule, needle, OnceLock::new())
            }).collect()
        });
        let mut block = false;
        let mut allow = false;
        let mut important_block = false;
        let mut important_allow = false;
        for id in self.popups.ids(&host, true).0 {
            let Some((Some(rule), needle, regex)) = popups.get(id as usize) else { continue };
            let party_ok = match rule.party {
                Party::Any => true,
                Party::First => !third,
                Party::Third => third,
                Party::StrictFirst => host == target_host,
                Party::StrictThird => host != target_host,
            };
            // Compiling every candidate's regex took ~160 ms per lookup on
            // the default lists; a literal every match contains rules out
            // nearly all of them first.
            if !party_ok || !lowered.contains(needle.as_str()) { continue; }
            let regex = regex.get_or_init(|| regex::RegexBuilder::new(&rule.pattern).case_insensitive(!rule.match_case).build().ok());
            if !regex.as_ref().is_some_and(|r| r.is_match(target)) { continue; }
            match (rule.allow, rule.important) {
                (false, false) => block |= !(genericblock && rule.generic),
                (true, false) => allow = true,
                (false, true) => important_block = true, (true, true) => important_allow = true,
            }
        }
        !important_allow && (important_block || (block && !allow))
    }

}

/// A popup filter as the runtime matches it, stored as JSON.
#[derive(Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct PopupRule {
    allow: bool,
    generic: bool,
    important: bool,
    match_case: bool,
    party: Party,
    pattern: String,
}

/// The longest literal, lowercased, that every match of `pattern` contains.
/// `pattern` is `url_filter` output, WebKit's subset without alternation;
/// anything this does not follow yields `""`, which every URL contains.
fn required_literal(pattern: &str) -> String {
    let (mut best, mut run) = (String::new(), String::new());
    let mut depth = 0usize;
    let mut chars = pattern.chars();
    while let Some(c) = chars.next() {
        let literal = match c {
            '\\' => match chars.next() {
                Some(e) if e.is_ascii_punctuation() => Some(e),
                Some('d' | 'D' | 'w' | 'W' | 's' | 'S' | 'b' | 'B') => None,
                _ => return String::new(),
            },
            '[' => {
                let mut first = true;
                loop {
                    match chars.next() {
                        Some('\\') => { chars.next(); }
                        Some('^') if first => continue,
                        Some(']') if !first => break,
                        Some('[') | None => return String::new(),
                        _ => {}
                    }
                    first = false;
                }
                None
            }
            '(' => { depth += 1; None }
            ')' => { depth = depth.saturating_sub(1); None }
            '|' => return String::new(),
            // The character before an optional quantifier is not required.
            '*' | '?' => { run.pop(); None }
            '{' => {
                run.pop();
                if !chars.by_ref().any(|c| c == '}') { return String::new(); }
                None
            }
            c if c.is_ascii() && !matches!(c, '.' | '^' | '$' | '+' | '}') => Some(c),
            _ => None,
        };
        match literal {
            Some(c) if depth == 0 => run.push(c.to_ascii_lowercase()),
            _ => {
                if run.len() > best.len() { best = std::mem::take(&mut run); }
                run.clear();
            }
        }
    }
    if run.len() > best.len() { run } else { best }
}

/// Popup matching uses the same URL compiler and source-domain index as the
/// rest of the engine. Unsupported constraints never become broader blocks.
pub(crate) fn popup_rule(r: &crate::ast::NetworkRule) -> Result<PopupRule, String> {
    use crate::ast::NetworkAction;
    if !matches!(r.action, NetworkAction::Block) {
        return Err("popup: unsupported action".into());
    }
    // `domain=` and party are judged against the opener tab, as uBO does
    // when it cannot tell which frame opened the popup.
    let constrained = !r.to.is_empty() || !r.denyallow.is_empty()
        || !r.method.include.is_empty() || !r.method.exclude.is_empty()
        || !r.runtime_only_options.is_empty();
    if constrained && !r.exception { return Err("popup: unsupported destination, method or response constraint".into()); }
    let pattern = crate::compile::regex::url_filter(&r.pattern);
    let pattern = match pattern {
        Some(p) if !constrained => p,
        _ if r.exception => ".*".into(), // conservative allow, never a broader block
        _ => return Err("popup: unsupported URL pattern".into()),
    };
    Ok(PopupRule { pattern, allow: r.exception, important: r.important,
        match_case: r.match_case, party: r.party, generic: r.from.include.is_empty() })
}

fn read_index(rest: &mut &[u8]) -> Result<Scriptlets, String> {
    let calls = Table::parse(take(rest)?)?;
    let rules = Table::parse(take(rest)?)?;
    let exceptions = Table::parse(take(rest)?)?;
    let patterns = serde_json::from_slice::<Vec<String>>(take(rest)?).map_err(|e| e.to_string())?;
    let regexes = regex::RegexSet::new(patterns).map_err(|e| e.to_string())?;
    let generic_rules = generic_rules(&rules, &regexes);
    let generic_calls = generic_rules.iter().map(|(id, _)| (*id, calls.decode_at(*id as usize))).collect();
    Ok(Scriptlets { calls, generic_rules, generic_calls, rules, exceptions, regexes })
}

fn put(out: &mut Vec<u8>, section: &[u8]) {
    out.extend((section.len() as u32).to_le_bytes());
    out.extend(section);
}

/// The next length-prefixed section of `rest`.
fn take<'a>(rest: &mut &'a [u8]) -> Result<&'a [u8], String> {
    let len = rest
        .get(..4)
        .map(|w| u32::from_le_bytes(w.try_into().unwrap()) as usize)
        .ok_or("engine: truncated")?;
    let section = rest.get(4..4 + len).ok_or("engine: truncated")?;
    *rest = &rest[4 + len..];
    Ok(section)
}

fn read_engine(section: &[u8]) -> Result<adblock::Engine, String> {
    let mut engine = adblock::Engine::new_with_filter_set(FilterSet::new(false));
    engine
        .deserialize(section)
        .map_err(|e| format!("engine: {e}"))?;
    Ok(engine)
}

/// Hides and their exceptions. `lines` are cosmetic filters, one per line.
fn hide_engine(lines: &[&str]) -> adblock::Engine {
    let mut set = FilterSet::new(false);
    set.add_filter_list(
        lines.join("\n"),
        ParseOptions {
            rule_types: RuleTypes::All,
            permissions: PermissionMask::from_bits(u8::MAX),
            ..Default::default()
        },
    );
    adblock::Engine::new_with_filter_set(set)
}

fn exception_engine(lines: &[String]) -> adblock::Engine {
    let mut set = FilterSet::new(false);
    set.add_filter_list(lines.join("\n"), ParseOptions::default());
    adblock::Engine::new_with_filter_set(set)
}

fn sorted(set: HashSet<String>) -> Vec<String> {
    let mut v: Vec<String> = set.into_iter().collect();
    v.sort_unstable();
    v
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lines(text: &str) -> Vec<String> {
        text.lines().map(str::to_owned).collect()
    }

    const RULES: &str = "\
example.com##.ad
example.com##.promo:has-text(Sponsored)
example.com##.card:style(opacity: 0.1)
example.com##+js(set-constant, adsEnabled, false)
";

    fn calls(rules: &[&str], url: &str) -> Vec<Vec<String>> {
        let rules: Vec<String> = rules.iter().map(|r| r.to_string()).collect();
        Engine::build(&rules).lookup(url).scriptlets
    }

    fn call(parts: &[&str]) -> Vec<String> {
        parts.iter().map(|p| p.to_string()).collect()
    }

    fn popup_blocked(rules: &str, opener: &str, target: &str) -> bool {
        Engine::build(&lines(rules)).lookup(&format!("wbe-popup-{opener}#{target}")).popup_blocked == Some(true)
    }

    #[test]
    fn scoped_popup_exceptions_stay_on_their_openers() {
        // uBO's lists ship `@@$popup,domain=datanodes.to,3p`. Indexed for every
        // opener, that catch-all allow switched popup blocking off everywhere.
        let rules = "||ads.example^$popup\n@@$popup,domain=datanodes.to,3p\n@@||ads.example/ok^$popup,domain=partner.example\n";
        assert!(popup_blocked(rules, "https://movies.example/watch", "https://ads.example/x"));
        assert!(!popup_blocked(rules, "https://datanodes.to/file", "https://ads.example/x"));
        assert!(!popup_blocked(rules, "https://partner.example/", "https://ads.example/ok"));
        assert!(popup_blocked(rules, "https://movies.example/", "https://ads.example/ok"));
        // An unscoped allow still applies to every opener.
        assert!(!popup_blocked("||ads.example^$popup\n@@||ads.example/ok^$popup\n", "https://movies.example/", "https://ads.example/ok"));
    }

    #[test]
    fn popup_prefilter_literal_is_required_by_every_match() {
        for (pattern, literal) in [
            (r"^[^:]+://+([^:/]+\.)?ads\.example[/:?#]", "ads.example"),
            (r"/pop\.php\?id=[0-9]+", "/pop.php?id="),
            (r"adsx?y{0,3}zzzz", "zzzz"),
            (r"(foo)?barbaz", "barbaz"),
            (r"a|bcdef", ""),
            (r"\x41bc", ""),
        ] {
            assert_eq!(required_literal(pattern), literal, "{pattern}");
        }
    }

    #[test]
    fn blob_and_data_popups_are_checked() {
        // uBO's `|blob:$popup,domain=hqq.tv|waaw.to` and `|data:text$popup,domain=~clker.com`.
        let rules = "|blob:$popup,domain=hqq.tv|waaw.to\n|data:text$popup,domain=~clker.com\n$popup,domain=any.example\n";
        assert!(popup_blocked(rules, "https://hqq.tv/e/1", "blob:https://hqq.tv/abc"));
        assert!(!popup_blocked(rules, "https://other.example/", "blob:https://hqq.tv/abc"));
        assert!(popup_blocked(rules, "https://news.example/", "data:text/html,<p>a#b"));
        assert!(!popup_blocked(rules, "https://clker.com/", "data:text/html,x"));
        assert!(!popup_blocked(rules, "https://any.example/", "about:blank"));
    }

    #[test]
    fn popup_blocks_keep_opener_domains_and_party() {
        // uBO's catch-all for streaming hosts and EasyList's `://ads.` rule,
        // both scoped by the opener tab.
        let text = "$popup,third-party,domain=streamtape.com\n://ads.$popup,domain=~ad.olx.pl\n@@||site.example/ok$popup,1p\n||site.example^$popup\n||gen.example^$popup\n||spec.example^$popup,domain=keep.example\n@@||keep.example^$genericblock\n";
        let out = crate::compile(&[crate::ListInput { text, trusted: false }], &crate::CompileOptions { safari: crate::webkit::SafariVersion::new(18, 0) });
        assert!(out.stats.dropped.is_empty(), "{:?}", out.stats.dropped);
        let engine = Engine::deserialize(&Engine::build(&out.runtime).serialize()).unwrap();
        let blocked = |opener: &str, target: &str| engine.lookup(&format!("wbe-popup-{opener}#{target}")).popup_blocked == Some(true);
        assert!(blocked("https://www.streamtape.com/e/1", "https://pop.example/"));
        assert!(!blocked("https://www.streamtape.com/e/1", "https://cdn.streamtape.com/v"));
        assert!(!blocked("https://other.example/", "https://pop.example/"));
        assert!(blocked("https://news.example/", "https://ads.foo.example/"));
        assert!(!blocked("https://ad.olx.pl/", "https://ads.foo.example/"));
        assert!(!blocked("https://www.site.example/", "https://site.example/ok"));
        assert!(blocked("https://other.example/", "https://site.example/ok"));
        assert!(!blocked("https://keep.example/", "https://gen.example/"));
        assert!(blocked("https://keep.example/", "https://spec.example/"));
    }

    #[test]
    fn document_popup_exception_keeps_both_halves() {
        // uBO's unbreak list ships `@@||awstrack.me/*auth.coindesk.com$doc,popup`.
        let text = "##+js(set, a, 1)\n||awstrack.me^$popup\n@@||awstrack.me/*auth.coindesk.com$doc,popup\n";
        let out = crate::compile(&[crate::ListInput { text, trusted: false }], &crate::CompileOptions { safari: crate::webkit::SafariVersion::new(18, 0) });
        assert!(out.stats.dropped.is_empty(), "{:?}", out.stats.dropped);
        let engine = Engine::deserialize(&Engine::build(&out.runtime).serialize()).unwrap();
        let url = "https://awstrack.me/x?auth.coindesk.com";
        assert!(engine.lookup(url).scriptlets.is_empty());
        assert_eq!(engine.lookup(&format!("wbe-popup-https://news.example/#{url}")).popup_blocked, Some(false));
    }

    #[test]
    fn unsupported_operators_and_headers_are_reported_without_output() {
        for text in ["example.com##div:has-text(Ad):unknown-op(x)", "example.com##div:shadow(.ad:unknown-op(x))",
            "||example.com^$removeheader=location", "example.com##^responseheader(location)",
            "||example.com^$responseheader=set-cookie:ad"] {
            let out = crate::compile(&[crate::ListInput { text, trusted: true }], &crate::CompileOptions { safari: crate::webkit::SafariVersion::new(18, 0) });
            assert_eq!(out.stats.dropped.values().sum::<u64>(), 1, "{text}");
            assert_eq!(out.stats.native_rules, 0, "{text}");
            assert!(out.runtime.is_empty(), "{text}");
        }
    }

    #[test]
    fn procedural_operators_never_fall_back_to_plain_hides() {
        for selector in ["div:matches-media((min-width: 1px))", "img:matches-property(naturalWidth=300)", "div:others()", "button:watch-attr(disabled):remove-attr(disabled)", "section:has(p:has-text(Ad))", "div:shadow(.ad)"] {
            let text = format!("example.com##{selector}");
            let out = crate::compile(&[crate::ListInput { text: &text, trusted: true }], &crate::CompileOptions { safari: crate::webkit::SafariVersion::new(18, 0) });
            assert!(out.stats.dropped.is_empty(), "{selector}: {:?}", out.stats.dropped);
            let engine = Engine::deserialize(&Engine::build(&out.runtime).serialize()).unwrap();
            let page = engine.lookup("https://example.com/");
            assert!(page.hide.is_empty(), "{selector}: {:?}", page.hide);
            assert_eq!(page.procedural.len(), 1, "{selector}");
            assert!(engine.lookup("https://other.com/").procedural.is_empty());
        }
    }

    #[test]
    fn page_exceptions_apply_after_compilation_and_round_trip() {
        let source = "##[data-ad]\nexample.com##.ad\nexample.com##.ad:has-text(Ad)\nexample.com##+js(set-constant, adsEnabled, false)\n";
        for (option, hides, procedural, scripts, generic) in [
            ("elemhide", false, false, true, true),
            ("ehide", false, false, true, true),
            ("document", false, false, false, true),
            ("generichide", true, true, true, true),
            ("ghide", true, true, true, true),
        ] {
            let text = format!("{source}@@||example.com^${option}\n");
            let output = crate::compile(
                &[crate::ListInput {
                    text: &text,
                    trusted: false,
                }],
                &crate::CompileOptions {
                    safari: crate::webkit::SafariVersion {
                        major: 18,
                        minor: 0,
                    },
                },
            );
            assert!(output
                .runtime
                .iter()
                .any(|line| line == &format!("@@||example.com^${option}")));
            let mut runtime = lines(source);
            runtime.extend(output.runtime);
            let engine = Engine::deserialize(&Engine::build(&runtime).serialize()).unwrap();
            let page = engine.lookup("https://example.com/");
            assert_eq!(page.hide.contains(&".ad".to_string()), hides, "{option}");
            assert!(!page.hide.contains(&"[data-ad]".to_string()), "{option}");
            assert_eq!(!page.procedural.is_empty(), procedural, "{option}");
            assert_eq!(!page.scriptlets.is_empty(), scripts, "{option}");
            assert_eq!(page.generichide, generic, "{option}");
            let other = engine.lookup("https://example.org/");
            assert!(!other.generichide, "{option}");
            assert!(other.hide.contains(&"[data-ad]".to_string()), "{option}");
        }
    }

    #[test]
    fn specifichide_exception_reaches_runtime_procedurals() {
        let base = "example.com##div:has-text(ad)\n";
        let page = |text: &str| {
            let output = crate::compile(
                &[crate::ListInput { text, trusted: false }],
                &crate::CompileOptions { safari: crate::webkit::SafariVersion::new(18, 0) },
            );
            Engine::deserialize(&Engine::build(&output.runtime).serialize()).unwrap().lookup("https://example.com/")
        };
        assert_eq!(page(base).procedural.len(), 1);
        assert!(page(&format!("{base}@@||example.com^$specifichide\n")).procedural.is_empty());
    }

    #[test]
    fn specifichide_keeps_generic_cosmetics_and_scriptlets() {
        let rules = "##[data-generic]\n\
             example.com##[data-site]\n\
             example.com##div:has-text(site)\n\
             #$#.g { color: red }\n\
             example.com#$#.s { color: red }\n\
             example.com##+js(set-constant, a, 1)";
        let engine = |text: &str| Engine::deserialize(&Engine::build(&lines(text)).serialize()).unwrap();
        let site = engine(rules).lookup("https://example.com/");
        assert_eq!(site.hide, ["[data-generic]", "[data-site]"]);
        assert_eq!(site.styles.len(), 2);
        assert_eq!(site.procedural.len(), 1);
        let page = engine(&format!("{rules}\n@@||example.com^$specifichide")).lookup("https://example.com/");
        assert_eq!(page.hide, ["[data-generic]"]);
        assert_eq!(page.styles, [".g { color: red }"]);
        assert!(page.procedural.is_empty());
        assert_eq!(page.scriptlets, [call(&["set-constant", "a", "1"])]);
        assert!(!page.generichide);
    }

    #[test]
    fn youtube_request_policy_follows_matching_rules_and_exceptions() {
        let rule = r#"www.youtube.com,example.com##+js(trusted-replace-fetch-response, '"adSlots"', '"no_ads"', get_watch?)"#;
        let url = "https://www.youtube.com/watch?v=video";
        let wanted = call(&["trusted-youtube-player-request"]);
        let watch = call(&[
            "set-constant",
            "ytcfg.data_.EXPERIMENT_FLAGS.web_streaming_watch",
            "false",
        ]);
        let opts = crate::CompileOptions {
            safari: crate::webkit::SafariVersion {
                major: 18,
                minor: 0,
            },
        };
        let engine = Engine::deserialize(&Engine::build(&lines(rule)).serialize()).unwrap();
        assert!(engine.lookup(url).scriptlets.contains(&wanted));
        assert!(engine.lookup(url).scriptlets.contains(&watch));
        let flag_rule = "www.youtube.com##+js(set-constant, ytcfg.data_.EXPERIMENT_FLAGS.web_streaming_watch, false)";
        let flag_exception = flag_rule.replacen("##", "#@#", 1);
        let page = Engine::build(&lines(&format!("{rule}\n{flag_exception}"))).lookup(url);
        assert!(page.scriptlets.contains(&wanted));
        assert!(!page.scriptlets.contains(&watch));
        let page = Engine::build(&lines(&format!(
            "{rule}\n{flag_rule}\nwww.youtube.com##+js(trusted-youtube-player-request)"
        )))
        .lookup(url);
        assert_eq!(page.scriptlets.iter().filter(|c| *c == &wanted).count(), 1);
        assert_eq!(page.scriptlets.iter().filter(|c| *c == &watch).count(), 1);
        assert!(!engine
            .lookup("https://example.com/")
            .scriptlets
            .contains(&wanted));
        assert!(!engine
            .lookup("https://music.youtube.com/")
            .scriptlets
            .contains(&wanted));
        for exception in [
            "www.youtube.com#@#+js()",
            "www.youtube.com#@#+js(trusted-youtube-player-request)",
            r#"www.youtube.com#@#+js(trusted-replace-fetch-response, '"adSlots"', '"no_ads"', get_watch?)"#,
            "@@||youtube.com^$document",
        ] {
            let output = crate::compile(
                &[crate::ListInput {
                    text: &format!("{rule}\n{exception}"),
                    trusted: true,
                }],
                &opts,
            );
            let page = Engine::build(&output.runtime).lookup(url);
            assert!(
                !page.scriptlets.contains(&wanted) && !page.scriptlets.contains(&watch),
                "{exception}"
            );
        }
        for trusted in [false, true] {
            let output = crate::compile(
                &[crate::ListInput {
                    text: rule,
                    trusted,
                }],
                &opts,
            );
            let page = Engine::build(&output.runtime).lookup(url);
            assert_eq!(page.scriptlets.contains(&wanted), trusted);
            assert_eq!(page.scriptlets.contains(&watch), trusted);
        }
    }

    #[test]
    fn adguard_scripts_round_trip_with_exceptions() {
        let rules = [
            "example.com#%#//scriptlet('prevent-canvas')",
            "example.com#%#window.x = 1;",
            "sub.example.com#@%#window.x = 1;",
        ];
        let url = "https://example.com/";
        assert_eq!(
            calls(&rules, url),
            vec![
                call(&["adg:prevent-canvas"]),
                call(&["adg:js", "window.x = 1;"])
            ]
        );
        assert_eq!(
            calls(&rules, "https://sub.example.com/"),
            vec![call(&["adg:prevent-canvas"])]
        );
        // Untrusted lists never reach the runtime with raw JavaScript.
        let mut stats = crate::compile::Stats::default();
        let parsed = crate::compile::parse_list(rules[1], 0, false, &mut stats);
        assert!(parsed.is_empty(), "{parsed:?}");
    }

    #[test]
    fn lookup_returns_matching_actions() {
        let page = Engine::build(&lines(RULES)).lookup("https://www.example.com/watch");
        assert_eq!(page.hide, vec![".ad"]);
        assert_eq!(page.procedural.len(), 2);
        assert_eq!(
            page.scriptlets,
            vec![call(&["set-constant", "adsEnabled", "false"])]
        );
        assert!(!page.generichide);
    }

    #[test]
    fn lookup_other_host_is_empty() {
        let page = Engine::build(&lines(RULES)).lookup("https://example.org/");
        assert!(page.hide.is_empty() && page.procedural.is_empty() && page.scriptlets.is_empty());
    }

    #[test]
    fn round_trip_keeps_payload() {
        let engine = Engine::build(&lines(RULES));
        let reloaded = Engine::deserialize(&engine.serialize()).unwrap();
        for url in ["https://example.com/", "https://example.org/"] {
            assert_eq!(engine.lookup(url), reloaded.lookup(url));
        }
    }

    #[test]
    fn scriptlets_follow_ubo_scoping() {
        let set = call(&["set-constant", "a", "1"]);
        // Entities, subdomains, and generic rules.
        assert_eq!(
            calls(
                &["google.*##+js(set-constant, a, 1)"],
                "https://www.google.co.uk/"
            ),
            [set.clone()]
        );
        assert_eq!(
            calls(
                &["example.com##+js(set-constant, a, 1)"],
                "https://a.b.example.com:8080/x"
            ),
            [set.clone()]
        );
        assert_eq!(
            calls(&["##+js(set-constant, a, 1)"], "https://any.test/"),
            [set.clone()]
        );
        assert!(calls(
            &["example.com##+js(set-constant, a, 1)"],
            "https://notexample.com/"
        )
        .is_empty());
        // Excluded subdomain, exact exception, and `#@#+js()`.
        let scoped = "example.com,~a.example.com##+js(set-constant, a, 1)";
        assert!(calls(&[scoped], "https://a.example.com/").is_empty());
        assert_eq!(calls(&[scoped], "https://b.example.com/"), [set.clone()]);
        let other = "example.com##+js(abort-on-property-read, b)";
        assert_eq!(
            calls(
                &[
                    "example.com##+js(set-constant, a, 1)",
                    other,
                    "example.com#@#+js(set-constant, a, 1)"
                ],
                "https://example.com/"
            ),
            [call(&["abort-on-property-read", "b"])]
        );
        assert!(calls(
            &[other, "sub.example.com#@#+js()"],
            "https://sub.example.com/"
        )
        .is_empty());
        assert_eq!(
            calls(&[other, "sub.example.com#@#+js()"], "https://example.com/").len(),
            1
        );
    }

    #[test]
    fn scriptlet_tables_find_each_host_and_reject_truncation() {
        let rules: Vec<String> = (0..60)
            .map(|i| format!("site{i}.example##+js(set-constant, a{i}, 1)"))
            .collect();
        let bytes = Engine::build(&rules).serialize();
        let engine = Engine::deserialize(&bytes).unwrap();
        for i in 0..60 {
            let name = format!("a{i}");
            let page = engine.lookup(&format!("https://www.site{i}.example/"));
            assert_eq!(page.scriptlets, vec![call(&["set-constant", &name, "1"])]);
        }
        assert!(engine
            .lookup("https://site60.example/")
            .scriptlets
            .is_empty());
        let empty = Engine::deserialize(&Engine::build(&[]).serialize()).unwrap();
        assert!(empty.lookup("https://site1.example/").scriptlets.is_empty());
        assert!(Engine::deserialize(&bytes[..bytes.len() - 1]).is_err());
    }

    #[test]
    fn invalid_input_is_an_error() {
        assert!(Engine::deserialize(b"junk").is_err());
        assert!(Engine::deserialize(&[]).is_err());
    }
    #[test]
    fn adguard_css_exceptions_and_media_survive_compile_and_reload() {
        let text = "example.com#@#+js()\nexample.com#$#.ad { color: red }\nexample.com#@$#.ad { color: red }\nexample.com#$#@media (max-width: 768px) { .ad { margin: 0 !important; } }";
        let output = crate::compile(&[crate::ListInput { text, trusted: true }], &crate::CompileOptions { safari: crate::webkit::SafariVersion::new(18, 0) });
        assert!(output.stats.dropped.is_empty(), "{:?}", output.stats.dropped);
        let engine = Engine::deserialize(&Engine::build(&output.runtime).serialize()).unwrap();
        let page = engine.lookup("https://example.com/");
        assert!(page.procedural.is_empty(), "CSS exception must cancel the style action");
        let payload = serde_json::to_value(page).unwrap();
        assert_eq!(payload["styles"][0], "@media (max-width: 768px) { .ad { margin: 0 !important; } }");
        assert_eq!(serde_json::to_value(engine.lookup("https://other.com/")).unwrap()["styles"], serde_json::json!([]));
    }

    #[test]
    fn scriptlet_regex_domains_and_excluded_exception_domains() {
        let set = call(&["set-constant", "a", "1"]);
        assert_eq!(calls(&[r"/example\.com$/##+js(set, a, 1)"], "https://www.example.com/"), [set.clone()]);
        assert!(calls(&[r"/example\.com$/##+js(set, a, 1)"], "https://other.com/").is_empty());
        let filters = ["example.com##+js(set, a, 1)", "example.com,~keep.example.com#@#+js(set, a, 1)"];
        assert_eq!(calls(&filters, "https://keep.example.com/"), [set]);
        assert!(calls(&filters, "https://example.com/").is_empty());
    }

    #[test]
    fn generic_adguard_styles_survive_scriptlet_exceptions() {
        let text = "#$#.ad { color: red }\nexample.com#@#+js()\nskip.example.com#@$#.ad { color: red }";
        let output = crate::compile(&[crate::ListInput { text, trusted: false }], &crate::CompileOptions { safari: crate::webkit::SafariVersion::new(18, 0) });
        assert!(output.stats.dropped.is_empty());
        let engine = Engine::deserialize(&Engine::build(&output.runtime).serialize()).unwrap();
        assert!(engine.lookup("https://skip.example.com/").styles.is_empty());
        for host in ["example.com", "other.com"] {
            assert_eq!(engine.lookup(&format!("https://{host}/")).styles, [".ad { color: red }"]);
        }
    }

    #[test]
    fn wildcard_scriptlet_scopes_survive_reload() {
        let text = r"*,example.com,~skip.example.com,~/blocked\.net$/##+js(set, a, 1)";
        let output = crate::compile(&[crate::ListInput { text, trusted: true }], &crate::CompileOptions { safari: crate::webkit::SafariVersion::new(18, 0) });
        assert!(output.stats.dropped.is_empty());
        let engine = Engine::deserialize(&Engine::build(&output.runtime).serialize()).unwrap();
        for host in ["example.com", "other.com"] {
            assert_eq!(engine.lookup(&format!("https://{host}/")).scriptlets, [call(&["set-constant", "a", "1"])]);
        }
        for host in ["skip.example.com", "blocked.net"] {
            assert!(engine.lookup(&format!("https://{host}/")).scriptlets.is_empty());
        }
    }

}
