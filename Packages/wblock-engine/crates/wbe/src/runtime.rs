//! Per-page engine for rules Safari cannot enforce natively: procedural
//! cosmetics, `:style`/`:remove` actions, and scriptlets. Queried by the
//! wBlock Scripts extension's native handler for each frame.
//! Cosmetic matching is brave/adblock-rust's. Scriptlets are matched here and
//! returned as calls, because the extension must inject them as files (a
//! script string would be subject to the page's CSP). The lines come from
//! `compile`, which already dropped untrusted `trusted-*` scriptlets.

use crate::ast::{DomainList, DomainMatcher, ParsedLine, Rule};
use adblock::lists::{FilterSet, ParseOptions, RuleTypes};
use adblock::resources::PermissionMask;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

pub struct Engine {
    cosmetic: adblock::Engine,
    scriptlets: Scriptlets,
}

/// Cosmetic actions for one page URL.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct PagePayload {
    /// Selectors to hide with `display: none !important`.
    pub hide: Vec<String>,
    /// JSON-encoded procedural filters and actions.
    pub procedural: Vec<String>,
    /// Scriptlet calls, each `[name, args...]`, in rule order.
    pub scriptlets: Vec<Vec<String>>,
    /// True when a `$generichide` exception applies to the page.
    pub generichide: bool,
}

/// Scriptlet rules keyed by the hostname or entity (`name.*`) they are
/// scoped to; `""` holds generic ones (cosmetic-filtering.js semantics).
#[derive(Debug, Default, Serialize, Deserialize)]
struct Scriptlets {
    calls: Vec<Vec<String>>,
    rules: HashMap<String, Vec<(u32, Vec<DomainMatcher>)>>,
    /// Exceptions: a call index, or `None` for `#@#+js()` (all scriptlets).
    exceptions: HashMap<String, Vec<Option<u32>>>,
}

impl Scriptlets {
    fn add(
        &mut self,
        index: &mut HashMap<Vec<String>, u32>,
        exception: bool,
        domains: DomainList,
        call: Vec<String>,
    ) {
        let id = (!call[0].is_empty()).then(|| {
            *index.entry(call.clone()).or_insert_with(|| {
                self.calls.push(call);
                self.calls.len() as u32 - 1
            })
        });
        let mut keys: Vec<String> = domains
            .include
            .iter()
            .filter_map(|m| match m {
                DomainMatcher::Hostname(h) | DomainMatcher::Entity(h) => Some(key(m, h)),
                // A regex scope cannot be keyed; the rule is not applied.
                DomainMatcher::Regex(_) => None,
            })
            .collect();
        if domains.include.is_empty() {
            keys.push(String::new());
        }
        for k in keys {
            if exception {
                self.exceptions.entry(k).or_default().push(id);
            } else if let Some(id) = id {
                self.rules
                    .entry(k)
                    .or_default()
                    .push((id, domains.exclude.clone()));
            }
        }
    }

    fn lookup(&self, host: &str) -> Vec<Vec<String>> {
        let keys = host_keys(host);
        let mut excepted = HashSet::new();
        for k in &keys {
            for e in self.exceptions.get(k).into_iter().flatten() {
                match e {
                    None => return Vec::new(),
                    Some(id) => excepted.insert(*id),
                };
            }
        }
        let mut ids: Vec<u32> = keys
            .iter()
            .flat_map(|k| self.rules.get(k).into_iter().flatten())
            .filter(|(id, exclude)| {
                !excepted.contains(id) && !exclude.iter().any(|m| scope_matches(m, host))
            })
            .map(|(id, _)| *id)
            .collect();
        ids.sort_unstable();
        ids.dedup();
        ids.into_iter()
            .map(|id| self.calls[id as usize].clone())
            .collect()
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

/// Whether an exclude entry covers `host`. A regex entry counts as covering
/// it, so an exclusion that cannot be judged never widens a rule.
fn scope_matches(m: &DomainMatcher, host: &str) -> bool {
    match m {
        DomainMatcher::Regex(_) => true,
        DomainMatcher::Hostname(_) | DomainMatcher::Entity(_) => {
            let k = match m {
                DomainMatcher::Entity(e) => format!("{e}.*"),
                DomainMatcher::Hostname(h) => h.clone(),
                DomainMatcher::Regex(_) => unreachable!(),
            };
            host_keys(host).contains(&k)
        }
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
        let mut scriptlets = Scriptlets::default();
        let mut index = HashMap::new();
        let mut cosmetic = Vec::new();
        for line in lines {
            match crate::parse_line(line, Default::default()) {
                ParsedLine::Rule(Rule::Scriptlet(r)) => {
                    let call = std::iter::once(r.name).chain(r.args).collect();
                    scriptlets.add(&mut index, r.exception, r.domains, call);
                }
                _ => cosmetic.push(line.as_str()),
            }
        }
        let mut set = FilterSet::new(false);
        set.add_filter_list(
            cosmetic.join("\n"),
            ParseOptions {
                rule_types: RuleTypes::CosmeticOnly,
                permissions: PermissionMask::from_bits(u8::MAX),
                ..Default::default()
            },
        );
        Self {
            cosmetic: adblock::Engine::new_with_filter_set(set),
            scriptlets,
        }
    }

    /// `[adblock-rust engine length: u32 LE][adblock-rust engine][scriptlets JSON]`.
    pub fn serialize(&self) -> Vec<u8> {
        let cosmetic = self.cosmetic.serialize();
        let mut out = (cosmetic.len() as u32).to_le_bytes().to_vec();
        out.extend(cosmetic);
        out.extend(serde_json::to_vec(&self.scriptlets).expect("scriptlets serialize"));
        out
    }

    pub fn deserialize(bytes: &[u8]) -> Result<Self, String> {
        let (len, rest) = bytes.split_first_chunk::<4>().ok_or("engine: truncated")?;
        let len = u32::from_le_bytes(*len) as usize;
        if rest.len() < len {
            return Err("engine: truncated".into());
        }
        let (cosmetic_bytes, scriptlet_bytes) = rest.split_at(len);
        let mut cosmetic = adblock::Engine::new_with_filter_set(FilterSet::new(false));
        cosmetic
            .deserialize(cosmetic_bytes)
            .map_err(|e| format!("engine: {e}"))?;
        let scriptlets =
            serde_json::from_slice(scriptlet_bytes).map_err(|e| format!("engine: {e}"))?;
        Ok(Self {
            cosmetic,
            scriptlets,
        })
    }

    pub fn lookup(&self, url: &str) -> PagePayload {
        let r = self.cosmetic.url_cosmetic_resources(url);
        PagePayload {
            hide: sorted(r.hide_selectors),
            procedural: sorted(r.procedural_actions),
            scriptlets: self.scriptlets.lookup(&host_of(url).to_ascii_lowercase()),
            generichide: r.generichide,
        }
    }
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
    fn invalid_input_is_an_error() {
        assert!(Engine::deserialize(b"junk").is_err());
        assert!(Engine::deserialize(&[]).is_err());
    }
}
