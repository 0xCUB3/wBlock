//! Rules to Safari JSON.
//!
//! Output order matters: WebKit applies rules top to bottom and
//! `ignore-previous-rules` only cancels earlier matches. Each sub-compiler
//! tags its rules with a `Tier`; the final list is a stable sort by tier.
//! The tier order is the precedence policy proven in scripts/proofs.
//! Because `ignore-previous-rules` cancels every earlier match, page-level
//! cosmetic exceptions sit right after the hides they cancel and before any
//! network rule.

pub(crate) mod cosmetic;
pub(crate) mod network;
pub(crate) mod prune;
pub mod regex;

use crate::ast::{CosmeticRule, NetworkRule, ParsedLine, Rule, ScriptletRule, SourceRef};
use crate::webkit::{SafariVersion, WebkitJson, WkRule};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub enum Tier {
    /// Hides that name no site. Hides scoped to sites are the runtime's.
    GenericHide = 0,
    /// `$generichide` and `$elemhide`: cancel the native hides.
    HideException = 1,
    /// `$denyallow`: the block, then its exclusions.
    DenyallowBlock = 2,
    /// The exclusions of a `$denyallow` block. Each cancels only the blocks
    /// before it, so they sit ahead of every other block.
    DenyallowException = 3,
    /// Blocks with no page domains, which `$genericblock` lifts.
    GenericBlock = 4,
    /// `$genericblock`: cancels the generic blocks before it on the page's
    /// subresources, leaving its hides and the blocks after it in place.
    GenericBlockException = 5,
    Block = 6,
    Exception = 7,
    /// `$important` with `$denyallow`: the block, then its exclusions.
    ImportantDenyallowBlock = 8,
    /// The exclusions of an important `$denyallow` block, ahead of every
    /// other important block for the same reason.
    ImportantDenyallowException = 9,
    ImportantBlock = 10,
    /// AdGuard `$important` exceptions override important blocks.
    ImportantException = 11,
    /// `@@...$document`: cancels everything on the page.
    DocumentException = 12,
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
    pub webkit: WebkitJson,
    /// Normalized uBO lines for `runtime::Engine`, one per rule.
    pub runtime: Vec<String>,
    pub stats: Stats,
}

pub(crate) struct Tiered {
    pub tier: Tier,
    pub rule: WkRule,
}

/// Safari JSON of the network rules, written as they are compiled. Each unit
/// of work writes its own arena and `entries` locates every rule in one of
/// them. Nothing is held as a `WkRule`, which costs several allocations per
/// rule.
#[derive(Debug, Default)]
pub(crate) struct Emitted {
    arenas: Vec<Vec<u8>>,
    entries: Vec<Entry>,
    /// The blocks anchored at a hostname, for `network::drop_subsumed`.
    anchored: Vec<network::Anchored>,
}

#[derive(Debug)]
pub(super) struct Entry {
    tier: Tier,
    arena: u32,
    /// `arenas[arena][start..end]` is the rule, unless `domain` is set.
    start: usize,
    end: usize,
    /// An `if-domain` rule: its domain list can grow when rules merge.
    domain: Option<Box<DomainSpan>>,
    shape: prune::Shape,
}

#[derive(Debug)]
pub(super) struct DomainSpan {
    /// `arena[start..head]` ends before the `if-domain` key and
    /// `arena[tail..end]` starts after its array.
    head: usize,
    tail: usize,
    domains: Vec<String>,
    /// Written as `if-top-url` regexes (`regex::host_top_url`).
    top: bool,
}

impl DomainSpan {
    /// The condition's key and value, as written.
    fn json(&self) -> (&'static [u8], Vec<u8>) {
        let value = if self.top {
            let urls: Vec<String> = self
                .domains
                .iter()
                .map(|d| regex::host_top_url(d).expect("ASCII domain"))
                .collect();
            serde_json::to_vec(&urls)
        } else {
            serde_json::to_vec(&self.domains)
        };
        let key: &[u8] = if self.top { b",\"if-top-url\":" } else { b",\"if-domain\":" };
        (key, value.expect("domains serialize"))
    }
}

pub(crate) use network::{surviving, Context as NetworkContext};

/// Tiers in output order.
const TIERS: [Tier; 13] = [
    Tier::GenericHide,
    Tier::HideException,
    Tier::DenyallowBlock,
    Tier::DenyallowException,
    Tier::GenericBlock,
    Tier::GenericBlockException,
    Tier::Block,
    Tier::Exception,
    Tier::ImportantDenyallowBlock,
    Tier::ImportantDenyallowException,
    Tier::ImportantBlock,
    Tier::ImportantException,
    Tier::DocumentException,
];

impl Emitted {
    /// Room for `rules` network rules of roughly 500 bytes of JSON each, in
    /// one arena. The reserved bytes are not touched, so they cost nothing.
    fn with_capacity(rules: usize) -> Self {
        Self {
            arenas: vec![Vec::with_capacity(rules * 512)],
            entries: Vec::with_capacity(rules * 2),
            anchored: Vec::new(),
        }
    }

    /// The arena rules are written to now.
    pub(super) fn arena(&mut self) -> usize {
        if self.arenas.is_empty() {
            self.arenas.push(Vec::new());
        }
        self.arenas.len() - 1
    }

    /// `parts` in order, as one output. Arenas move; entries are re-pointed.
    fn absorb(parts: Vec<Emitted>) -> Emitted {
        let rules: usize = parts.iter().map(|p| p.entries.len()).sum();
        let mut out = Emitted {
            arenas: Vec::with_capacity(parts.len()),
            entries: Vec::with_capacity(rules),
            anchored: Vec::new(),
        };
        for part in parts {
            let base = out.arenas.len() as u32;
            let first = out.entries.len();
            out.arenas.extend(part.arenas);
            out.anchored.extend(part.anchored.into_iter().map(|mut a| {
                a.entry += first;
                a
            }));
            out.entries.extend(part.entries.into_iter().map(|mut e| {
                e.arena += base;
                e
            }));
        }
        out
    }

    fn render(&self, entry: &Entry, out: &mut Vec<u8>) {
        let arena = &self.arenas[entry.arena as usize];
        match &entry.domain {
            None => out.extend_from_slice(&arena[entry.start..entry.end]),
            Some(span) => {
                let (key, value) = span.json();
                out.extend_from_slice(&arena[entry.start..span.head]);
                out.extend_from_slice(key);
                out.extend_from_slice(&value);
                out.extend_from_slice(&arena[span.tail..entry.end]);
            }
        }
    }

    /// The bytes `render` writes for `entry`.
    fn rendered_len(&self, entry: &Entry) -> usize {
        match &entry.domain {
            None => entry.end - entry.start,
            Some(span) => {
                let (key, value) = span.json();
                (span.head - entry.start) + key.len() + value.len() + (entry.end - span.tail)
            }
        }
    }

    pub(crate) fn push_rule(&mut self, tier: Tier, rule: &WkRule) {
        let arena = self.arena();
        let bytes = &mut self.arenas[arena];
        let start = bytes.len();
        serde_json::to_writer(&mut *bytes, rule).expect("WkRule serializes");
        let end = bytes.len();
        let ignore = rule.action == crate::webkit::WkAction::IgnorePreviousRules;
        self.entries.push(Entry {
            tier,
            arena: arena as u32,
            start,
            end,
            domain: None,
            shape: prune::Shape::of_trigger(ignore, &rule.trigger),
        });
    }

    /// Everything emitted, in tier order; within a tier, emission order.
    /// `seen` holds the rules that come before these; an ignore that cancels
    /// none of them or of the rules here before it is left out (`prune`).
    /// `network_front` goes after the hides and their exceptions and before
    /// every network tier: a hide exception applies to every load of its
    /// page, so nothing it can cancel may come before it but hides.
    fn into_webkit(mut self, seen: &mut prune::Seen, network_front: &WebkitJson) -> WebkitJson {
        let mut order = Vec::with_capacity(self.entries.len());
        let mut front_at = 0;
        for tier in TIERS {
            if tier == Tier::DenyallowBlock {
                front_at = order.len();
            }
            for (i, entry) in self.entries.iter_mut().enumerate().filter(|(_, e)| e.tier == tier) {
                if let Some(span) = entry.domain.as_deref().filter(|s| s.top) {
                    entry.shape.set_page(prune::Page::If(span.domains.iter().map(|d| prune::domain_host(d)).collect()));
                }
                if tier == Tier::GenericHide {
                    seen.add_hide(&entry.shape);
                } else if !entry.shape.ignore {
                    seen.add(&entry.shape);
                } else if !seen.overlaps(&entry.shape, matches!(tier, Tier::HideException | Tier::DocumentException)) {
                    continue;
                }
                order.push(i);
            }
        }
        // Sized up front so the output is never copied to grow.
        let front = network_front.as_str();
        let front = &front[1..front.len() - 1];
        let size = order.iter().map(|&i| self.rendered_len(&self.entries[i]) + 1).sum::<usize>() + front.len() + 3;
        let mut json = Vec::with_capacity(size);
        json.push(b'[');
        let comma = |json: &mut Vec<u8>| {
            if json.len() > 1 {
                json.push(b',');
            }
        };
        for n in 0..=order.len() {
            if n == front_at && !front.is_empty() {
                comma(&mut json);
                json.extend_from_slice(front.as_bytes());
            }
            if let Some(&i) = order.get(n) {
                comma(&mut json);
                self.render(&self.entries[i], &mut json);
            }
        }
        json.push(b']');
        WebkitJson::from_bytes(json, order.len() + network_front.rules())
    }

    #[cfg(test)]
    pub(crate) fn tiered(&self) -> Vec<Tiered> {
        self.entries
            .iter()
            .map(|entry| {
                let mut json = Vec::new();
                self.render(entry, &mut json);
                Tiered {
                    tier: entry.tier,
                    rule: serde_json::from_slice(&json).expect("rule parses back"),
                }
            })
            .collect()
    }
}

/// `body(i)` for every `i < count`, on all cores, results in order. Indices
/// are handed out one at a time, so uneven items still balance.
pub(crate) fn parallel_indices<R: Send>(count: usize, body: impl Fn(usize) -> R + Sync) -> Vec<R> {
    use std::sync::atomic::{AtomicUsize, Ordering};
    let threads = std::thread::available_parallelism()
        .map_or(4, |n| n.get())
        .min(count.max(1));
    let next = AtomicUsize::new(0);
    let done: Vec<(usize, R)> = std::thread::scope(|scope| {
        let handles: Vec<_> = (0..threads)
            .map(|_| {
                let (body, next) = (&body, &next);
                scope.spawn(move || {
                    let mut done = Vec::new();
                    loop {
                        let i = next.fetch_add(1, Ordering::Relaxed);
                        if i >= count {
                            break done;
                        }
                        done.push((i, body(i)));
                    }
                })
            })
            .collect();
        handles
            .into_iter()
            .flat_map(|h| h.join().expect("worker thread"))
            .collect()
    });
    let mut slots: Vec<Option<R>> = (0..count).map(|_| None).collect();
    for (i, r) in done {
        slots[i] = Some(r);
    }
    slots.into_iter().map(|r| r.expect("every index ran")).collect()
}

/// The cosmetic and scriptlet rules of one blocker, in compile order.
#[derive(Debug, Clone, Default)]
pub struct Others {
    pub cosmetic: Vec<CosmeticRule>,
    pub scriptlets: Vec<ScriptletRule>,
}

/// Parsed rules ready for `compile_rules`, which takes them over.
#[derive(Debug, Clone, Default)]
pub struct RuleSet {
    pub rules: Vec<Rule>,
}

impl RuleSet {
    pub fn push(&mut self, rule: Rule) {
        self.rules.push(rule);
    }
}

/// Parses one list. Untrusted lists lose `trusted-*` scriptlets, as in uBO.
pub fn parse_list(text: &str, list: u32, trusted: bool, stats: &mut Stats) -> Vec<Rule> {
    let mut rules = Vec::new();
    for (i, line) in text.lines().enumerate() {
        stats.lines += 1;
        let normalized = crate::normalize::adguard_to_ubo(line);
        let source = SourceRef {
            list,
            line: i as u32 + 1,
        };
        match crate::parse_line(&normalized, source) {
            ParsedLine::Ignored => {}
            ParsedLine::Unsupported { reason } | ParsedLine::Invalid { reason } => {
                stats.drop(&reason)
            }
            ParsedLine::Rule(Rule::Scriptlet(r))
                if !trusted && crate::parse::cosmetic::is_trusted_only(&r.name) =>
            {
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
        set.rules
            .extend(parse_list(input.text, list as u32, input.trusted, &mut stats));
    }
    compile_rules(set, opts, stats)
}

/// Compiles parsed rules. `stats` carries what parsing counted.
pub fn compile_rules(set: RuleSet, opts: &CompileOptions, stats: Stats) -> CompileOutput {
    let mut network = Vec::new();
    let mut others = Others::default();
    for rule in set.rules {
        match rule {
            Rule::Network(r) => network.push(*r),
            Rule::Cosmetic(r) => others.cosmetic.push(r),
            Rule::Scriptlet(r) => others.scriptlets.push(r),
        }
    }
    let mut ctx = network::Context::default();
    network.iter().for_each(|r| ctx.add(r));
    let network = std::sync::Mutex::new(Some(network));
    compile_blocker(
        &ctx,
        1,
        |_| network.lock().expect("unit lock").take().expect("one unit"),
        others,
        opts,
        stats,
        &mut prune::Seen::default(),
        &WebkitJson::default(),
    )
}

/// Compiles one blocker. Its network rules come in `units` groups: `unit(i)`
/// returns group `i` and is called once, from any thread. `ctx` covers every
/// network rule. Groups compile in parallel and are written in order, while
/// the cosmetic and scriptlet rules compile alongside them. `seen` holds the
/// rules the blocker places before these and gains these (`prune`), and
/// `network_front` is placed ahead of the network rules (`into_webkit`).
pub(crate) fn compile_blocker<U>(
    ctx: &network::Context,
    units: usize,
    unit: U,
    others: Others,
    opts: &CompileOptions,
    mut stats: Stats,
    seen: &mut prune::Seen,
    network_front: &WebkitJson,
) -> CompileOutput
where
    U: Fn(usize) -> Vec<NetworkRule> + Sync,
{
    let mut runtime = Vec::new();
    let mut tiered = Vec::new();
    let cosmetic: Vec<&CosmeticRule> = others.cosmetic.iter().collect();
    let (mut emitted, network_stats, page_exceptions) = std::thread::scope(|scope| {
        let worker = scope.spawn(|| network::compile_units(ctx, units, &unit, opts.safari));
        cosmetic::compile(&cosmetic, opts, &mut tiered, &mut runtime, &mut stats);
        worker.join().expect("network compiler thread")
    });
    // Compiled, the cosmetic rules and hides are not held through the rest.
    drop(cosmetic);
    drop(others.cosmetic);
    stats.merge(&network_stats);
    for t in tiered {
        emitted.push_rule(t.tier, &t.rule);
    }
    runtime.extend(page_exceptions);
    for s in others.scriptlets {
        runtime.push(s.raw);
    }
    stats.runtime_rules = runtime.len() as u64;

    let webkit = emitted.into_webkit(seen, network_front);
    stats.native_rules = webkit.rules() as u64;
    CompileOutput {
        webkit,
        runtime,
        stats,
    }
}
