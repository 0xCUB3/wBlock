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
mod network;
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
    /// Blocks with no page domains, which `$genericblock` lifts.
    GenericBlock = 2,
    /// `$genericblock`: cancels the generic blocks before it on the page's
    /// subresources, leaving its hides and the blocks after it in place.
    GenericBlockException = 3,
    Block = 4,
    Exception = 5,
    /// `$important` with `$denyallow`: the block, then its exclusions.
    ImportantDenyallowBlock = 6,
    /// The exclusions of an important `$denyallow` block. Each cancels only
    /// the blocks before it, so they sit ahead of every other important block.
    ImportantDenyallowException = 7,
    ImportantBlock = 8,
    /// AdGuard `$important` exceptions override important blocks.
    ImportantException = 9,
    /// `@@...$document`: cancels everything on the page.
    DocumentException = 10,
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
}

#[derive(Debug)]
pub(super) struct DomainSpan {
    /// `arena[start..head]` ends before the `if-domain` key and
    /// `arena[tail..end]` starts after its array.
    head: usize,
    tail: usize,
    domains: Vec<String>,
}

pub(crate) use network::{surviving, Context as NetworkContext};

/// Counts the bytes written to it.
struct Count(usize);

impl std::io::Write for Count {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        self.0 += buf.len();
        Ok(buf.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

/// Tiers in output order.
const TIERS: [Tier; 11] = [
    Tier::GenericHide,
    Tier::HideException,
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
                out.extend_from_slice(&arena[entry.start..span.head]);
                out.extend_from_slice(b",\"if-domain\":");
                serde_json::to_writer(&mut *out, &span.domains).expect("domains serialize");
                out.extend_from_slice(&arena[span.tail..entry.end]);
            }
        }
    }

    /// The bytes `render` writes for `entry`.
    fn rendered_len(&self, entry: &Entry) -> usize {
        match &entry.domain {
            None => entry.end - entry.start,
            Some(span) => {
                let mut domains = Count(0);
                serde_json::to_writer(&mut domains, &span.domains).expect("domains serialize");
                (span.head - entry.start)
                    + b",\"if-domain\":".len()
                    + domains.0
                    + (entry.end - span.tail)
            }
        }
    }

    pub(crate) fn push_rule(&mut self, tier: Tier, rule: &WkRule) {
        let arena = self.arena();
        let bytes = &mut self.arenas[arena];
        let start = bytes.len();
        serde_json::to_writer(&mut *bytes, rule).expect("WkRule serializes");
        let end = bytes.len();
        self.entries.push(Entry {
            tier,
            arena: arena as u32,
            start,
            end,
            domain: None,
        });
    }

    /// Everything emitted, in tier order; within a tier, emission order.
    fn into_webkit(self) -> WebkitJson {
        // Sized up front so the output is never copied to grow.
        let size = self
            .entries
            .iter()
            .map(|e| self.rendered_len(e) + 1)
            .sum::<usize>()
            + 2;
        let mut json = Vec::with_capacity(size);
        json.push(b'[');
        let mut first = true;
        for tier in TIERS {
            for entry in self.entries.iter().filter(|e| e.tier == tier) {
                if !first {
                    json.push(b',');
                }
                first = false;
                self.render(entry, &mut json);
            }
        }
        json.push(b']');
        WebkitJson::from_bytes(json, self.entries.len())
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
    )
}

/// Compiles one blocker. Its network rules come in `units` groups: `unit(i)`
/// returns group `i` and is called once, from any thread. `ctx` covers every
/// network rule. Groups compile in parallel and are written in order, while
/// the cosmetic and scriptlet rules compile alongside them.
pub(crate) fn compile_blocker<U>(
    ctx: &network::Context,
    units: usize,
    unit: U,
    others: Others,
    opts: &CompileOptions,
    mut stats: Stats,
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
    stats.merge(&network_stats);
    for t in &tiered {
        emitted.push_rule(t.tier, &t.rule);
    }
    runtime.extend(page_exceptions);
    for s in others.scriptlets {
        runtime.push(s.raw);
    }
    stats.runtime_rules = runtime.len() as u64;

    let webkit = emitted.into_webkit();
    stats.native_rules = webkit.rules() as u64;
    CompileOutput {
        webkit,
        runtime,
        stats,
    }
}
