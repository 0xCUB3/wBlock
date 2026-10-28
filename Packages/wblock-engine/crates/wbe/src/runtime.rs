//! Per-page engine for rules Safari cannot enforce natively: procedural
//! cosmetics, `:style`/`:remove` actions, and scriptlets. Queried by the
//! wBlock Scripts extension's native handler for each frame.
//! Wraps brave/adblock-rust (cosmetic matching only). The lines come from
//! `compile`, which already dropped untrusted `trusted-*` scriptlets, so every
//! line is parsed with full permissions.

use adblock::lists::{FilterSet, ParseOptions, RuleTypes};
use adblock::resources::{PermissionMask, Resource};
use serde::Serialize;
use std::collections::HashSet;

pub struct Engine(adblock::Engine);

/// Cosmetic actions for one page URL.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct PagePayload {
    /// Selectors to hide with `display: none !important`.
    pub hide: Vec<String>,
    /// JSON-encoded procedural filters and actions.
    pub procedural: Vec<String>,
    /// Self-contained script that runs the matching scriptlets, or empty.
    /// Run it in an isolated scope; it declares top-level helpers.
    pub scriptlets: String,
    /// True when a `$generichide` exception applies to the page.
    pub generichide: bool,
}

fn load_resources(json: &str) -> Result<Vec<Resource>, String> {
    serde_json::from_str(json).map_err(|e| format!("resources: {e}"))
}

impl Engine {
    /// `lines` are uBO-syntax cosmetic, procedural, and scriptlet rules.
    pub fn build(lines: &[String], resources_json: &str) -> Result<Self, String> {
        let resources = load_resources(resources_json)?;
        let mut set = FilterSet::new(false);
        set.add_filter_list(
            lines.join("\n"),
            ParseOptions {
                rule_types: RuleTypes::CosmeticOnly,
                permissions: PermissionMask::from_bits(u8::MAX),
                ..Default::default()
            },
        );
        let mut engine = adblock::Engine::new_with_filter_set(set);
        engine.use_resources(resources);
        Ok(Self(engine))
    }

    pub fn serialize(&self) -> Vec<u8> {
        self.0.serialize()
    }

    /// Resources are not part of the serialized form and must be supplied again.
    pub fn deserialize(bytes: &[u8], resources_json: &str) -> Result<Self, String> {
        let resources = load_resources(resources_json)?;
        let mut engine = adblock::Engine::new_with_filter_set(FilterSet::new(false));
        engine
            .deserialize(bytes)
            .map_err(|e| format!("engine: {e}"))?;
        engine.use_resources(resources);
        Ok(Self(engine))
    }

    pub fn lookup(&self, url: &str) -> PagePayload {
        let r = self.0.url_cosmetic_resources(url);
        PagePayload {
            hide: sorted(r.hide_selectors),
            procedural: sorted(r.procedural_actions),
            scriptlets: r.injected_script,
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

    const RESOURCES: &str = include_str!("../../../resources/resources.json");

    fn lines(text: &str) -> Vec<String> {
        text.lines().map(str::to_owned).collect()
    }

    const RULES: &str = "\
example.com##.ad
example.com##.promo:has-text(Sponsored)
example.com##.card:style(opacity: 0.1)
example.com##+js(set-constant, adsEnabled, false)
";

    #[test]
    fn lookup_returns_matching_actions() {
        let engine = Engine::build(&lines(RULES), RESOURCES).unwrap();
        let page = engine.lookup("https://www.example.com/watch");
        assert_eq!(page.hide, vec![".ad"]);
        assert_eq!(page.procedural.len(), 2);
        assert!(
            page.scriptlets.contains("setConstantFn("),
            "{}",
            page.scriptlets
        );
        assert!(!page.generichide);
    }

    #[test]
    fn lookup_other_host_is_empty() {
        let engine = Engine::build(&lines(RULES), RESOURCES).unwrap();
        let page = engine.lookup("https://example.org/");
        assert!(page.hide.is_empty());
        assert!(page.procedural.is_empty());
        assert!(page.scriptlets.is_empty());
    }

    #[test]
    fn round_trip_keeps_payload() {
        let engine = Engine::build(&lines(RULES), RESOURCES).unwrap();
        let bytes = engine.serialize();
        let reloaded = Engine::deserialize(&bytes, RESOURCES).unwrap();
        for url in ["https://example.com/", "https://example.org/"] {
            assert_eq!(engine.lookup(url), reloaded.lookup(url));
        }
    }

    #[test]
    fn scriptlets_resolve_with_dependencies() {
        let rules = [
            "example.com##+js(set-constant, a, true)",
            "example.com##+js(json-prune, a b)",
            "example.com##+js(abort-on-property-read, a)",
            "example.com##+js(trusted-set-cookie, name, value)",
        ];
        for rule in rules {
            let engine = Engine::build(&[rule.to_string()], RESOURCES).unwrap();
            let page = engine.lookup("https://example.com/");
            assert!(page.scriptlets.contains("scriptletGlobals"), "{rule}");
            assert!(page.scriptlets.len() > 1000, "{rule}");
        }
    }

    #[test]
    fn invalid_input_is_an_error() {
        assert!(Engine::build(&[], "not json").is_err());
        assert!(Engine::deserialize(b"junk", RESOURCES).is_err());
        assert!(Engine::deserialize(&[], "[]").is_err());
    }
}
