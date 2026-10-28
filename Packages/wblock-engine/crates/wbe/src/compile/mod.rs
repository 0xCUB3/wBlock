//! Rules to Safari JSON.
//!
//! Output order matters: WebKit applies rules top to bottom and
//! `ignore-previous-rules` only cancels earlier matches. Each sub-compiler
//! tags its rules with a `Tier`; the final list is a stable sort by tier.
//! The tier order is the precedence policy proven in scripts/proofs.
//! Because `ignore-previous-rules` cancels every earlier match, page-level
//! cosmetic exceptions sit right after the hides they cancel and before any
//! network rule.

mod cosmetic;
mod network;
pub mod regex;

use crate::ast::{CosmeticRule, NetworkRule, ParsedLine, Rule, ScriptletRule, SourceRef};
use crate::webkit::{SafariVersion, WkRule};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub enum Tier {
    GenericHide = 0,
    /// `$generichide`: cancels generic hides only.
    GenericHideException = 1,
    SpecificHide = 2,
    /// `$elemhide` (and `$specifichide`, widened): cancels all hides.
    ElemHideException = 3,
    Block = 4,
    Exception = 5,
    ImportantBlock = 6,
    /// `@@...$document`: cancels everything on the page.
    DocumentException = 7,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompileOptions {
    pub safari: SafariVersion,
}

pub struct ListInput<'a> {
    pub text: &'a str,
    /// Trusted lists may use `trusted-*` scriptlets (uBO: its own lists and
    /// the user's rules).
    pub trusted: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Stats {
    pub lines: u64,
    pub rules: u64,
    pub native_rules: u64,
    pub runtime_rules: u64,
    /// Reason -> count, for rules neither native nor runtime.
    pub dropped: BTreeMap<String, u64>,
}

impl Stats {
    pub fn drop(&mut self, reason: &str) {
        *self.dropped.entry(reason.to_string()).or_default() += 1;
    }
}

#[derive(Debug, Clone, Default)]
pub struct CompileOutput {
    pub webkit: Vec<WkRule>,
    /// Normalized uBO lines for `runtime::Engine`, one per rule.
    pub runtime: Vec<String>,
    pub stats: Stats,
}

pub(crate) struct Tiered {
    pub tier: Tier,
    pub rule: WkRule,
}

/// Parsed rules, split by kind, ready for `compile_rules`.
#[derive(Debug, Clone, Default)]
pub struct RuleSet {
    pub network: Vec<NetworkRule>,
    pub cosmetic: Vec<CosmeticRule>,
    pub scriptlets: Vec<ScriptletRule>,
}

impl RuleSet {
    pub fn push(&mut self, rule: Rule) {
        match rule {
            Rule::Network(r) => self.network.push(r),
            Rule::Cosmetic(r) => self.cosmetic.push(r),
            Rule::Scriptlet(r) => self.scriptlets.push(r),
        }
    }
}

/// Parses one list. Untrusted lists lose `trusted-*` scriptlets, as in uBO.
pub fn parse_list(text: &str, list: u32, trusted: bool, stats: &mut Stats) -> Vec<Rule> {
    let mut rules = Vec::new();
    for (i, line) in text.lines().enumerate() {
        stats.lines += 1;
        let normalized = crate::normalize::adguard_to_ubo(line);
        let source = SourceRef { list, line: i as u32 + 1 };
        match crate::parse_line(&normalized, source) {
            ParsedLine::Ignored => {}
            ParsedLine::Unsupported { reason } | ParsedLine::Invalid { reason } => stats.drop(&reason),
            ParsedLine::Rule(Rule::Scriptlet(r)) if !trusted && r.name.starts_with("trusted-") => {
                stats.drop("untrusted trusted-* scriptlet")
            }
            ParsedLine::Rule(rule) => {
                stats.rules += 1;
                rules.push(rule);
            }
        }
    }
    rules
}

pub fn compile(inputs: &[ListInput], opts: &CompileOptions) -> CompileOutput {
    let mut stats = Stats::default();
    let mut set = RuleSet::default();
    for (list, input) in inputs.iter().enumerate() {
        for rule in parse_list(input.text, list as u32, input.trusted, &mut stats) {
            set.push(rule);
        }
    }
    compile_rules(&set, opts, stats)
}

/// Compiles parsed rules. `stats` carries what parsing counted.
pub fn compile_rules(set: &RuleSet, opts: &CompileOptions, mut stats: Stats) -> CompileOutput {
    let mut tiered = Vec::new();
    let mut runtime = Vec::new();
    network::compile(&set.network, opts, &mut tiered, &mut stats);
    cosmetic::compile(&set.cosmetic, opts, &mut tiered, &mut runtime, &mut stats);
    for s in &set.scriptlets {
        runtime.push(s.raw.clone());
    }
    stats.runtime_rules = runtime.len() as u64;

    tiered.sort_by_key(|t| t.tier);
    let webkit: Vec<WkRule> = tiered.into_iter().map(|t| t.rule).collect();
    stats.native_rules = webkit.len() as u64;
    CompileOutput {
        webkit,
        runtime,
        stats,
    }
}
