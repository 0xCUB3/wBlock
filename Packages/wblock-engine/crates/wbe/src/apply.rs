//! One wBlock apply: every selected list parsed once and spread over the
//! content blockers. What used to be text passes in the app happens here on
//! parsed rules:
//!
//! - per-list site scope (#653, #767) and the global cosmetic scope (#899),
//! - `!#safari_cb_affinity` routing and shards of lists too big for one blocker,
//! - one copy of a rule shared by blockers with the same exceptions (#681),
//! - exceptions copied into the blockers whose blocks they cancel (#836),
//! - a large excluded list's plain blocks ahead of one ignore rule (#925),
//! - per-list counts of the rules each blocker admitted.
//!
//! `Plan::new` does the shared work; `Plan::compile_target` builds one
//! blocker's output and may run for several blockers at once.

use crate::ast::{
    DomainList, DomainMatcher, NetworkAction, NetworkRule, Party, ResourceTypes, Rule,
};
use crate::compile::{
    compile_blocker, parallel_indices, parse_list, CompileOptions, CompileOutput,
    surviving, NetworkContext, Others, Stats,
};
use crate::compile::prune::Seen;
use crate::compile::regex::domain_top_url;
use crate::parse::{cosmetic::with_domains, restate};
use crate::webkit::{SafariVersion, WebkitJson, WkAction, WkRule, WkTrigger};
use serde::{Deserialize, Serialize};
use std::collections::hash_map::DefaultHasher;
use rustc_hash::{FxHashMap, FxHashSet};
use std::collections::BTreeMap;
use std::ops::Range;
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::hash::{Hash, Hasher};

#[derive(Debug, Clone, Default, Deserialize)]
pub struct SiteScope {
    /// Sites the list must not apply to (`name.*` for every ending).
    #[serde(default)]
    pub exclude: Vec<String>,
    /// When set, the only sites the list applies to.
    #[serde(default)]
    pub only: Option<Vec<String>>,
}

impl SiteScope {
    fn is_empty(&self) -> bool {
        self.exclude.is_empty() && self.only.is_none()
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct ListSpec {
    pub id: String,
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub path: Option<String>,
    #[serde(default)]
    pub trusted: bool,
    #[serde(default)]
    pub scope: SiteScope,
}

#[derive(Debug, Clone, Deserialize)]
pub struct TargetList {
    pub list: usize,
    /// `[index, count]` when the list is split over blockers.
    #[serde(default)]
    pub shard: Option<(u32, u32)>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct TargetSpec {
    /// wBlock's blocker slot (1...5), which decides its affinity types.
    pub slot: u8,
    pub lists: Vec<TargetList>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct CosmeticScope {
    #[serde(flatten)]
    pub sites: SiteScope,
    /// False drops hides that name no site.
    pub generic: bool,
}

impl Default for CosmeticScope {
    fn default() -> Self {
        CosmeticScope { sites: SiteScope::default(), generic: true }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct PlanRequest {
    pub safari: (u16, u16),
    /// In compile order.
    pub lists: Vec<ListSpec>,
    pub targets: Vec<TargetSpec>,
    #[serde(default)]
    pub cosmetics: CosmeticScope,
    #[serde(default)]
    pub limits: Limits,
}

/// Extra text one blocker compiles after its lists (zapper rules, wBlock's
/// compatibility rules, redirect carve-outs).
#[derive(Debug, Clone, Deserialize)]
pub struct Extra {
    pub text: String,
    #[serde(default)]
    pub trusted: bool,
    /// Every blocker of the plan is given this text. Its blocks that
    /// exceptions can reach then compile in the wide blocker alone (`Wide`).
    #[serde(default)]
    pub every_blocker: bool,
}

#[derive(Debug, Serialize)]
pub struct TargetOutput {
    #[serde(skip)]
    pub output: CompileOutput,
    /// List id -> rules this blocker admitted from it (first copies only).
    pub admitted: BTreeMap<String, u64>,
    /// `Plan::fingerprint` of these arguments.
    #[serde(skip)]
    pub fingerprint: u64,
}

/// One rule of a list, kept as a pointer to its line. The rule itself is
/// parsed again when a blocker needs it (`Plan::rule`), so the plan holds
/// the list text and these records instead of every parsed rule.
#[derive(Clone, Copy)]
struct Parsed {
    /// Byte offset of the line in the list's text.
    offset: usize,
    /// 1-based line number, the rule's `source.line`.
    line: u32,
    /// Position of the rule among those its line parses to.
    index: u32,
    identity: u64,
    /// Exceptions and `$badfilter` stay in every shard and drive #681.
    shared: bool,
    /// A network rule, so the network pass can skip the other kinds unparsed.
    network: bool,
    /// A network rule a blocker's `NetworkContext` holds, so its scan parses it.
    in_context: bool,
    /// `is_plain_block`, which the segment of #925 compiles unscoped.
    plain: bool,
    /// What decides the rule's blocker.
    route: Route,
    /// Affinity types of the enclosing `!#safari_cb_affinity` block.
    affinity: Option<u8>,
}

struct ParsedList {
    /// The records in line order, in the chunks they were parsed in.
    chunks: Vec<Vec<Parsed>>,
    has_affinity: bool,
    /// A `!#` directive anywhere keeps the list out of #681 dedupe, as before.
    has_directive: bool,
    stats: Stats,
}

impl ParsedList {
    fn records(&self) -> impl Iterator<Item = &Parsed> + '_ {
        self.chunks.iter().flatten()
    }

    fn count(&self) -> usize {
        self.chunks.iter().map(Vec::len).sum()
    }
}

/// What `parse` reads from a list, so a list's records can be reused by any
/// plan with the same key. The text is hashed and its length kept beside the
/// hash; the records' offsets point into that text.
#[derive(Clone, Copy, PartialEq, Eq)]
struct ParseKey {
    text: u64,
    len: usize,
    trusted: bool,
    scope: u64,
    version: u32,
}

impl ParseKey {
    fn of(list: &ListSpec, text: u64) -> ParseKey {
        ParseKey {
            text,
            len: list.text.len(),
            trusted: list.trusted,
            scope: hash(&(&list.scope.exclude, &list.scope.only)),
            version: crate::OUTPUT_VERSION,
        }
    }
}

/// Parsed lists kept between plans. A plan keeps only the entries of its own
/// lists, so the cache holds one apply's lists and a changed list is parsed
/// again alone. The app clears it on phones after each apply.
#[derive(Default)]
pub struct ParseCache(Mutex<Vec<(ParseKey, Arc<ParsedList>)>>);

/// The cache `Plan::new` uses.
static PARSE_CACHE: ParseCache = ParseCache(Mutex::new(Vec::new()));

impl ParseCache {
    fn entries(&self) -> MutexGuard<'_, Vec<(ParseKey, Arc<ParsedList>)>> {
        self.0.lock().unwrap_or_else(PoisonError::into_inner)
    }

    fn parsed(&self, key: ParseKey, list: &ListSpec) -> Arc<ParsedList> {
        if let Some((_, hit)) = self.entries().iter().find(|(k, _)| *k == key) {
            return hit.clone();
        }
        let parsed = Arc::new(parse(list));
        let mut entries = self.entries();
        if !entries.iter().any(|(k, _)| *k == key) {
            entries.push((key, parsed.clone()));
        }
        parsed
    }

    fn keep(&self, keys: &[ParseKey]) {
        self.entries().retain(|(k, _)| keys.contains(k));
    }

    /// Drops every entry. Plans in use keep the lists they already parsed.
    pub fn clear(&self) {
        self.entries().clear();
    }
}

/// Empties the process-wide parse cache.
pub fn clear_parse_cache() {
    PARSE_CACHE.clear();
}

/// Records per network unit: the granularity at which rules are parsed and
/// compiled, so a unit's rules are the only ones held at once.
const UNIT_RECORDS: usize = 2048;

/// A run of records of one chunk of one list.
struct Unit {
    list: usize,
    chunk: usize,
    range: Range<usize>,
}

/// A `fmt::Write` that hashes the text it is given.
struct HashText<'a>(&'a mut DefaultHasher);

impl std::fmt::Write for HashText<'_> {
    fn write_str(&mut self, text: &str) -> std::fmt::Result {
        self.0.write(text.as_bytes());
        Ok(())
    }
}

/// What one list adds to a blocker, gathered by `Plan::scan` in one pass over
/// the list's rules, which are then dropped.
#[derive(Default)]
struct ListScan {
    /// Whether the blocker takes any rule of the list. A list it takes none
    /// from adds no stats and no admission counts.
    takes: bool,
    /// Admission identities of the kept rules, in order.
    admitted: Vec<u64>,
    /// The whole-set facts of the kept network rules.
    ctx: NetworkContext,
    /// Cosmetic and scriptlet rules kept, in order.
    others: Others,
}

impl ListScan {
    /// Adds `part`, the scan of a later range of the same list.
    fn absorb(&mut self, part: ListScan) {
        self.takes |= part.takes;
        self.admitted.extend(part.admitted);
        self.ctx.merge(part.ctx);
        self.others.cosmetic.extend(part.others.cosmetic);
        self.others.scriptlets.extend(part.others.scriptlets);
    }
}

pub struct Plan {
    opts: CompileOptions,
    lists: Vec<ListSpec>,
    parsed: Vec<Arc<ParsedList>>,
    targets: Vec<TargetSpec>,
    cosmetics: CosmeticScope,
    limits: Limits,
    /// List index -> rule identities a blocker other than this one owns (#681).
    duplicates: Vec<Vec<FxHashSet<u64>>>,
    /// Hash of each list's text, for `fingerprint`.
    text_hashes: Vec<u64>,
    /// Where the blocks exceptions can reach go, when they go to one blocker.
    wide: Option<Wide>,
    capacity: Option<Capacity>,
}

/// A packing that exceeds the limits: the budgets, and each slot's measured
/// size in target order.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Capacity {
    pub rules: usize,
    pub bytes: usize,
    pub slots: Vec<Slot>,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
pub struct Slot {
    pub rules: usize,
    pub bytes: usize,
}

impl Capacity {
    pub fn message(&self) -> String {
        format!("selection exceeds content blocker budgets after bounded repacking ({} rules, {} bytes per slot); measured slots: {}",
            self.rules, self.bytes,
            self.slots.iter().map(|s| format!("{} rules/{} bytes", s.rules, s.bytes)).collect::<Vec<_>>().join(", "))
    }
}

/// What one blocker may hold. The wide blocker gains rules from every list,
/// so a plan has one only while its measured output stays within these.
#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(default)]
pub struct Limits {
    /// Safari's rule limit per content blocker. 0 for a blocker built outside
    /// the shared plan: every blocker then keeps its own lists' blocks.
    pub rules: usize,
    /// The app's budget for a blocker's JSON.
    pub bytes: usize,
}

impl Default for Limits {
    fn default() -> Self {
        Limits { rules: 150_000, bytes: 19_000_000 }
    }
}

/// Where a plan's blocks go. Safari applies an exception only in its own
/// blocker, so each blocker keeps a copy of every exception that can match a
/// load one of its blocks matches (#836, `prune`), and an exception with a
/// wildcard is one more automaton WebKit runs over every URL. The wide
/// blocker takes the blocks exceptions can reach (`Route`) from every list.
/// The other blocks go to the fewest blockers that have room for them, the
/// wide one among them: each blocker with a block still keeps the exceptions
/// not anchored at a host.
#[derive(Debug, Hash)]
struct Wide {
    target: usize,
    /// The sites (`Route::Site`) the plan's host exceptions name, sorted.
    excepted: Vec<u64>,
    /// Per list: whether some blocker compiles it.
    selected: Vec<bool>,
    /// The part (of 2^32) of the blocks no exception reaches that the wide
    /// blocker holds too.
    own: u64,
    /// The blockers that hold the rest of them.
    rest: Vec<usize>,
    /// Cumulative hash-space boundaries after measured repacking. Empty
    /// during the fixed-occupancy probe: movable blocks have no holder.
    shares: Option<Vec<(usize, u64)>>,
}

impl Wide {
    /// Whether the block at `p` goes to the wide blocker: one that is not
    /// anchored at a host, or one on a site an exception names.
    fn takes(&self, p: &Parsed) -> bool {
        self.takes_route(p.route, p.shared)
    }

    /// `takes`, for a rule with this route; `shared` for an exception.
    fn takes_route(&self, route: Route, shared: bool) -> bool {
        match route {
            Route::Wide => true,
            Route::Site(site) => !shared && self.excepted.binary_search(&site).is_ok(),
            Route::Identity => false,
        }
    }

    /// The blocker that holds a block with this route and identity.
    fn holder(&self, route: Route, identity: u64) -> usize {
        if self.takes_route(route, false) {
            return self.target;
        }
        if let Some(shares) = &self.shares {
            return shares.iter().find(|(_, end)| identity >> 32 < *end)
                .map_or(usize::MAX, |(target, _)| *target);
        }
        if self.rest.is_empty() || identity >> 32 < self.own {
            return self.target;
        }
        self.rest[(identity % self.rest.len() as u64) as usize]
    }
}

/// What a blocker's JSON comes to, estimated from the rule lines it is
/// compiled from: rules per line, then JSON bytes per line and per byte of
/// it. The most measured over the default lists and a 28-list selection, for
/// exceptions, the blocks the wide blocker takes, and the other blocks.
#[derive(Clone, Copy, Default)]
struct Size {
    rules: f64,
    bytes: f64,
}

impl Size {
    fn of(output: &CompileOutput) -> Self {
        Self { rules: output.webkit.rules() as f64, bytes: output.webkit.as_str().len() as f64 }
    }

    fn within(self, limits: &Limits) -> bool {
        self.rules <= limits.rules as f64 && self.bytes <= limits.bytes as f64
    }

    const SHARED: (f64, f64, f64) = (1.5, 100.0, 8.5);
    const TAKEN: (f64, f64, f64) = (1.7, 100.0, 3.0);
    const REST: (f64, f64, f64) = (1.0, 100.0, 1.5);
    /// The part of a limit an estimate may fill. The estimate is calibrated on
    /// two setups; measured output decides whether the allocation is usable.
    const ROOM: f64 = 0.7;

    fn add(&mut self, line: &str, (rules, each, bytes): (f64, f64, f64)) {
        self.rules += rules;
        self.bytes += each + bytes * line.len() as f64;
    }

    fn plus(self, other: Size, part: f64) -> Size {
        Size { rules: self.rules + other.rules * part, bytes: self.bytes + other.bytes * part }
    }

    fn fits(self, limits: &Limits) -> bool {
        self.rules <= limits.rules as f64 * Size::ROOM && self.bytes <= limits.bytes as f64 * Size::ROOM
    }
}

impl Plan {
    pub fn new(request: PlanRequest) -> Plan {
        Plan::with_cache(request, &PARSE_CACHE)
    }

    /// `new`, taking each list's parse from `cache` when the cache has it.
    pub fn with_cache(request: PlanRequest, cache: &ParseCache) -> Plan {
        let opts = CompileOptions {
            safari: SafariVersion::new(request.safari.0, request.safari.1),
        };
        let text_hashes = parallel_indices(request.lists.len(), |i| hash(&request.lists[i].text));
        let keys: Vec<ParseKey> = request
            .lists
            .iter()
            .zip(&text_hashes)
            .map(|(list, &text)| ParseKey::of(list, text))
            .collect();
        let parsed = parallel_indices(request.lists.len(), |i| cache.parsed(keys[i], &request.lists[i]));
        cache.keep(&keys);
        let mut plan = Plan {
            opts,
            lists: request.lists,
            parsed,
            targets: request.targets,
            cosmetics: request.cosmetics,
            limits: request.limits,
            duplicates: Vec::new(),
            text_hashes,
            wide: None,
            capacity: None,
        };
        plan.wide = plan.wide();
        plan.duplicates = plan.duplicate_rules();
        plan.capacity = plan.pack().err();
        plan
    }

    /// The measured packing when it exceeds the limits, else None. The plan is
    /// still usable: callers decide whether to reject it, and no rule is
    /// truncated or discarded to satisfy a budget.
    pub fn capacity(&self) -> Option<&Capacity> {
        self.capacity.as_ref()
    }

    /// Verifies the measured list packing. Callers must reject a failed plan.
    pub fn check_capacity(&self) -> Result<(), String> {
        self.capacity.as_ref().map_or(Ok(()), |capacity| Err(capacity.message()))
    }

    /// Extras are supplied after planning, so their final output needs its own
    /// check too. The caller's byte budget must reserve its finalization extras.
    pub fn check_output(&self, output: &CompileOutput) -> Result<(), String> {
        let size = Size::of(output);
        if self.limits.rules == 0 || size.within(&self.limits) {
            Ok(())
        } else {
            Err(format!("content blocker capacity exceeded: {} rules, {} bytes (budgets: {} rules, {} bytes)",
                size.rules, size.bytes, self.limits.rules, self.limits.bytes))
        }
    }

    fn sizes(&self) -> Vec<Size> {
        (0..self.targets.len()).map(|t| Size::of(&self.compile_target(t, &[]).output)).collect()
    }

    /// Estimates choose the initial packing, never whether it can ship. If it
    /// overflows, measure fixed occupancy (including affinity outside the shared
    /// pool), then distribute movable blocks into the remaining capacity.
    fn pack(&mut self) -> Result<(), Capacity> {
        if self.limits.rules == 0 {
            return Ok(());
        }
        let mut sizes = self.sizes();
        if sizes.iter().all(|s| s.within(&self.limits)) {
            return Ok(());
        }
        if let Some(wide) = &mut self.wide {
            wide.shares = Some(Vec::new());
            self.duplicates = self.duplicate_rules();
            let fixed = self.sizes();
            let mut movable = Size::default();
            for (size, base) in sizes.iter().zip(&fixed) {
                movable.rules += (size.rules - base.rules).max(0.0);
                movable.bytes += (size.bytes - base.bytes).max(0.0);
            }
            // Every attempt uses all supplied slots. Correct measured density
            // after each attempt; the bounded loop also covers indivisible rules
            // and hash skew near a hard limit without an endless retry.
            for _ in 0..8 {
                if fixed.iter().any(|s| !s.within(&self.limits)) {
                    break;
                }
                let weights: Vec<f64> = fixed.iter().map(|base| {
                    let rules = (self.limits.rules as f64 - base.rules) / movable.rules.max(1.0);
                    let bytes = (self.limits.bytes as f64 - base.bytes) / movable.bytes.max(1.0);
                    rules.min(bytes).max(0.0)
                }).collect();
                let total: f64 = weights.iter().sum();
                if total == 0.0 { break; }
                let mut end = 0.0;
                let mut shares: Vec<_> = weights.iter().enumerate().map(|(t, weight)| {
                    end += weight / total;
                    (t, (end * (1u64 << 32) as f64).round() as u64)
                }).collect();
                // The final interval always includes the top of hash space.
                shares.last_mut().unwrap().1 = 1u64 << 32;
                if self.wide.as_ref().unwrap().shares.as_ref() == Some(&shares) {
                    break;
                }
                self.wide.as_mut().unwrap().shares = Some(shares);
                self.duplicates = self.duplicate_rules();
                sizes = self.sizes();
                if sizes.iter().all(|s| s.within(&self.limits)) {
                    return Ok(());
                }
                // Use the largest observed cost per unit of hash space. Pruned
                // exceptions and segment optimizations can change with routing.
                for ((size, base), weight) in sizes.iter().zip(&fixed).zip(weights) {
                    if weight > 0.0 {
                        movable.rules = movable.rules.max((size.rules - base.rules) * total / weight);
                        movable.bytes = movable.bytes.max((size.bytes - base.bytes) * total / weight);
                    }
                }
            }
        }
        // The original shard assignments can split blocks the wide optimization
        // keeps together. Compile that valid fallback before declaring failure.
        self.wide = None;
        self.duplicates = self.duplicate_rules();
        sizes = self.sizes();
        if sizes.iter().all(|s| s.within(&self.limits)) {
            return Ok(());
        }
        Err(Capacity {
            rules: self.limits.rules,
            bytes: self.limits.bytes,
            slots: sizes.iter().map(|s| Slot { rules: s.rules as usize, bytes: s.bytes as usize }).collect(),
        })
    }

    /// The rule a record stands for, parsed again from its line exactly as
    /// `parse` did.
    fn rule(&self, list: usize, p: &Parsed) -> Rule {
        let spec = &self.lists[list];
        let mut rules = parse_list(self.line(list, p), list as u32, spec.trusted, &mut Stats::default());
        let mut rule = rules.swap_remove(p.index as usize);
        set_line(&mut rule, p.line);
        rule
    }

    /// The line of the rule at `p`.
    fn line(&self, list: usize, p: &Parsed) -> &str {
        self.lists[list].text[p.offset..].lines().next().unwrap_or_default()
    }

    pub fn target_count(&self) -> usize {
        self.targets.len()
    }

    fn assigned(&self, target: usize, list: usize) -> Option<&TargetList> {
        self.targets[target].lists.iter().find(|l| l.list == list)
    }

    /// The wide blocker: the first of those with the fewest rules assigned.
    /// None for a single blocker or for a zero rule limit. Measured output
    /// decides whether this optimization fits, not the estimate.
    fn wide(&self) -> Option<Wide> {
        // Nothing fits a zero limit, not even a plan with no exceptions.
        if self.limits.rules == 0 {
            return None;
        }
        let load = |t: &TargetSpec| -> usize {
            t.lists.iter().map(|a| self.parsed[a.list].count() / a.shard.map_or(1, |(_, n)| n as usize)).sum()
        };
        // In steps of 16,384 rules, so that an update moving two blockers'
        // sizes past each other seldom moves the wide blocker, which would
        // change every blocker's output.
        let target = (0..self.targets.len()).min_by_key(|&t| load(&self.targets[t]) >> 14).filter(|_| self.targets.len() > 1)?;
        let mut excepted: Vec<u64> = self
            .parsed
            .iter()
            .flat_map(|list| list.records())
            .filter_map(|p| match p.route {
                Route::Site(site) if p.shared => Some(site),
                _ => None,
            })
            .collect();
        excepted.sort_unstable();
        excepted.dedup();
        let selected = (0..self.lists.len()).map(|l| self.targets.iter().any(|t| t.lists.iter().any(|a| a.list == l))).collect();
        let mut wide = Wide { target, excepted, selected, own: 0, rest: Vec::new(), shares: None };
        // The wide blocker holds every exception of the plan and the blocks
        // it takes. A blocker of the rest keeps the exceptions that are not
        // anchored at a site, whose blocks are all in the wide one.
        let (mut taken, mut kept, mut rest) = (Size::default(), Size::default(), Size::default());
        for (l, parsed) in self.parsed.iter().enumerate() {
            let placed = parsed.records().filter(|p| p.network && wide.selected[l] && !(parsed.has_affinity && p.affinity.is_some()));
            for p in placed {
                let line = self.line(l, p);
                if p.shared {
                    taken.add(line, Size::SHARED);
                    if !matches!(p.route, Route::Site(_)) {
                        kept.add(line, Size::SHARED);
                    }
                } else if wide.takes(p) {
                    taken.add(line, Size::TAKEN);
                } else {
                    rest.add(line, Size::REST);
                }
            }
        }
        // The fewest blockers the rest fits, the wide one's part of it
        // leaving every blocker as full as the others, in 64ths so that an
        // update seldom moves a block.
        let others: Vec<usize> = (0..self.targets.len()).filter(|&t| t != target).collect();
        for count in 0..=others.len() {
            let part = match count {
                0 => 1.0,
                _ if rest.bytes == 0.0 => 0.0,
                n => {
                    let even = (rest.bytes + n as f64 * (kept.bytes - taken.bytes)) / ((n + 1) as f64 * rest.bytes);
                    (even.clamp(0.0, 1.0) * 64.0).round() / 64.0
                }
            };
            let fits = taken.plus(rest, part).fits(&self.limits)
                && (count == 0 || kept.plus(rest, (1.0 - part) / count as f64).fits(&self.limits));
            if fits || count == others.len() {
                wide.own = (part * (1u64 << 32) as f64) as u64;
                wide.rest = others[..count].to_vec();
                break;
            }
        }
        Some(wide)
    }

    /// Whether blocker `target` holds the rule at `p` of `list`: its affinity
    /// types, the blocker the plan's blocks go to, or else its shard.
    fn holds(&self, target: usize, list: usize, p: &Parsed) -> bool {
        if let (true, Some(mask)) = (self.parsed[list].has_affinity, p.affinity) {
            return mask & slot_types(self.targets[target].slot) != 0;
        }
        // A block goes where the plan's blocks go, whatever its list's blockers.
        if let Some(wide) = self.wide.as_ref().filter(|_| p.network && !p.shared) {
            return target == wide.holder(p.route, p.identity) && wide.selected[list];
        }
        self.assigned(target, list).is_some_and(|a| p.shared || a.shard.map_or(true, |(i, n)| p.identity % n as u64 == i as u64))
    }

    /// Whether blocker `target` keeps the rule at `p` of `list`: it holds the
    /// rule, and it is no #681 duplicate of another blocker's.
    fn keeps(&self, target: usize, list: usize, p: &Parsed) -> bool {
        self.holds(target, list, p) && !self.duplicates[target][list].contains(&p.identity)
    }

    /// One pass over records `range` of `list` for blocker `target`, which
    /// keeps what the compile needs from them and drops the rules themselves.
    /// The #925 segment's blocks count too: an exception must see their hosts.
    fn scan(&self, target: usize, unit: &Unit) -> ListScan {
        let list = unit.list;
        let scope = &self.lists[list].scope;
        let mut out = ListScan::default();
        for p in &self.parsed[list].chunks[unit.chunk][unit.range.clone()] {
            if !self.keeps(target, list, p) {
                continue;
            }
            // Unscoped, the rule is kept as it is, and only its identity counts.
            if p.network && !p.in_context && scope.is_empty() {
                out.takes = true;
                out.admitted.push(p.identity);
                continue;
            }
            let mut rules = Vec::new();
            scoped(self.rule(list, p), scope, &mut rules);
            out.takes |= !rules.is_empty();
            for rule in rules {
                let Some(rule) = self.cosmetic_scoped(rule) else {
                    continue;
                };
                out.admitted.push(identity(raw(&rule)));
                match rule {
                    Rule::Network(r) => out.ctx.add(&r),
                    Rule::Cosmetic(r) => out.others.cosmetic.push(r),
                    Rule::Scriptlet(r) => out.others.scriptlets.push(r),
                }
            }
        }
        out
    }

    /// The record ranges every blocker's passes work on, in list order.
    fn record_units(&self) -> Vec<Unit> {
        let mut units = Vec::new();
        for (list, parsed) in self.parsed.iter().enumerate() {
            for (chunk, records) in parsed.chunks.iter().enumerate() {
                for start in (0..records.len()).step_by(UNIT_RECORDS) {
                    let range = start..(start + UNIT_RECORDS).min(records.len());
                    units.push(Unit { list, chunk, range });
                }
            }
        }
        units
    }

    /// `scan` for every list, the record ranges in parallel and merged per list.
    fn scans(&self, target: usize) -> Vec<ListScan> {
        let units = self.record_units();
        let parts = parallel_indices(units.len(), |u| (units[u].list, self.scan(target, &units[u])));
        let mut lists: Vec<ListScan> = (0..self.lists.len()).map(|_| ListScan::default()).collect();
        for (list, part) in parts {
            lists[list].absorb(part);
        }
        lists
    }

    /// The network rules `scan` adds to the blocker's set from records `range`
    /// of `list`, in order. Parsed again, so a unit can be compiled on its own.
    /// A rule `ctx`'s `$badfilter` rules cancel is dropped before its scope
    /// changes it.
    fn network_unit(
        &self,
        ctx: &NetworkContext,
        target: usize,
        unit: &Unit,
        segment: Option<usize>,
    ) -> Vec<NetworkRule> {
        let list = unit.list;
        let scope = &self.lists[list].scope;
        let mut out = Vec::new();
        for p in self.parsed[list].chunks[unit.chunk][unit.range.clone()].iter().filter(|p| p.network) {
            if !self.keeps(target, list, p) {
                continue;
            }
            // Badfilters cancel a rule before the list's scope narrows it.
            let mut rules = Vec::new();
            match self.rule(list, p) {
                Rule::Network(r) => {
                    for r in surviving(ctx, *r) {
                        scoped(Rule::Network(Box::new(r)), scope, &mut rules);
                    }
                }
                rule => scoped(rule, scope, &mut rules),
            }
            for rule in rules {
                if Some(list) == segment && is_plain_block(&rule) {
                    continue;
                }
                if let Rule::Network(r) = rule {
                    out.push(*r);
                }
            }
        }
        out
    }

    /// #681: a rule several blockers would compile goes to the first, list
    /// order, among blockers whose exceptions are the same.
    fn duplicate_rules(&self) -> Vec<Vec<FxHashSet<u64>>> {
        let mut duplicates =
            vec![vec![FxHashSet::default(); self.lists.len()]; self.targets.len()];
        let contexts: Vec<u64> = (0..self.targets.len())
            .map(|t| {
                let mut exceptions: Vec<u64> = Vec::new();
                for list in 0..self.lists.len() {
                    let parsed = &self.parsed[list];
                    let types = slot_types(self.targets[t].slot);
                    let assigned = self.assigned(t, list).is_some();
                    for p in parsed.records().filter(|p| p.shared) {
                        let included = match (parsed.has_affinity, p.affinity) {
                            (true, Some(mask)) => mask & types != 0,
                            _ => assigned,
                        };
                        if included {
                            exceptions.push(p.identity);
                        }
                    }
                }
                exceptions.sort_unstable();
                exceptions.dedup();
                hash(&exceptions)
            })
            .collect();
        let mut owner: FxHashMap<(u64, u64), usize> = FxHashMap::default();
        for list in 0..self.lists.len() {
            let parsed = &self.parsed[list];
            if parsed.has_affinity || parsed.has_directive {
                continue;
            }
            for t in 0..self.targets.len() {
                for p in parsed.records().filter(|p| !p.shared && self.holds(t, list, p)) {
                    match owner.get(&(contexts[t], p.identity)) {
                        Some(&first) if first != t => {
                            // Swift crossTargetDuplicateRules removes only the losing target's copy.
                            duplicates[t][list].insert(p.identity);
                        }
                        Some(_) => {}
                        None => {
                            owner.insert((contexts[t], p.identity), t);
                        }
                    }
                }
            }
        }
        duplicates
    }

    /// One blocker's output, with its admitted counts.
    /// Changes whenever `compile_target(target, extras)` could: its own lists'
    /// text, scope and shards, the #681 rules other blockers own, the #836
    /// exceptions copied in, and the shared options. A list feeding only other
    /// blockers changes it only through those copies, so callers can reuse a
    /// blocker's last output when it is unchanged.
    pub fn fingerprint(&self, target: usize, extras: &[Extra]) -> u64 {
        self.fingerprinted(target, extras).0
    }

    /// The fingerprint of `target`'s output, and the rules that other blockers'
    /// exceptions copy into it, which the output is compiled from.
    fn fingerprinted(&self, target: usize, extras: &[Extra]) -> (u64, Vec<Rule>) {
        let replicated = self.replicated(target);
        (self.fingerprint_of(target, extras, &replicated), replicated)
    }

    fn fingerprint_of(&self, target: usize, extras: &[Extra], replicated: &[Rule]) -> u64 {
        let mut h = DefaultHasher::new();
        crate::OUTPUT_VERSION.hash(&mut h);
        format!("{:?}{:?}", self.opts, self.cosmetics).hash(&mut h);
        // Which blocks this blocker holds follows from the wide blocker.
        self.wide.hash(&mut h);
        self.targets[target].slot.hash(&mut h);
        self.segment_list(target).hash(&mut h);
        for (list, spec) in self.lists.iter().enumerate() {
            let assignment = self.assigned(target, list);
            // A blocker holds blocks from every list some blocker compiles.
            let gains = self.wide.as_ref().is_some_and(|w| w.selected[list]);
            let whole = assignment.is_some() || self.parsed[list].has_affinity;
            if whole || gains {
                if whole {
                    self.text_hashes[list].hash(&mut h);
                } else {
                    for p in self.parsed[list].records().filter(|p| !p.shared && self.holds(target, list, p)) {
                        self.line(list, p).hash(&mut h);
                    }
                }
                (list, spec.trusted, &spec.id).hash(&mut h);
                format!("{:?}", spec.scope).hash(&mut h);
                assignment.map(|a| a.shard).hash(&mut h);
                let owned = &self.duplicates[target][list];
                let sum = owned
                    .iter()
                    .fold(0u64, |acc, id| acc.wrapping_add(hash(id)));
                (owned.len(), sum).hash(&mut h);
            }
        }
        // The rule's Debug text, hashed as it is written: the same bytes as
        // `format!("{rule:?}").hash`, without a string per rule.
        for rule in replicated {
            let mut text = HashText(&mut h);
            std::fmt::Write::write_fmt(&mut text, format_args!("{rule:?}")).expect("hash");
            h.write_u8(0xff);
        }
        for extra in extras {
            (&extra.text, extra.trusted, extra.every_blocker).hash(&mut h);
        }
        h.finish()
    }

    pub fn compile_target(&self, target: usize, extras: &[Extra]) -> TargetOutput {
        self.compile_unless(target, extras, None)
            .expect("nothing known, so the blocker compiles")
    }

    /// `compile_target`, except that when `known` is this blocker's fingerprint
    /// for these arguments, nothing is compiled and the result is None.
    pub fn compile_unless(&self, target: usize, extras: &[Extra], known: Option<u64>) -> Option<TargetOutput> {
        let (fingerprint, replicated) = self.fingerprinted(target, extras);
        if known == Some(fingerprint) {
            return None;
        }
        let segment_list = self.segment_list(target);
        let scans = self.scans(target);

        let mut stats = Stats::default();
        let mut admitted = BTreeMap::new();
        let mut seen = FxHashSet::default();
        let mut ctx = NetworkContext::default();
        let mut others = Others::default();
        // Network rules come in units: one range of records per list, then the
        // replicated and extra rules.
        for (list, scan) in scans.into_iter().enumerate() {
            if scan.takes {
                stats.merge(&self.parsed[list].stats);
                let count = admitted.entry(self.lists[list].id.clone()).or_insert(0u64);
                for id in scan.admitted {
                    if seen.insert(id) {
                        *count += 1;
                    }
                }
            }
            ctx.merge(scan.ctx);
            others.cosmetic.extend(scan.others.cosmetic);
            others.scriptlets.extend(scan.others.scriptlets);
        }
        let units = self.record_units();
        let mut tail = Vec::new();
        for rule in replicated {
            match rule {
                Rule::Network(r) => {
                    ctx.add(&r);
                    tail.push(*r);
                }
                Rule::Cosmetic(r) => others.cosmetic.push(r),
                Rule::Scriptlet(r) => others.scriptlets.push(r),
            }
        }
        for (i, extra) in extras.iter().enumerate() {
            let mut extra_stats = Stats::default();
            for rule in parse_list(
                &extra.text,
                (self.lists.len() + i) as u32,
                extra.trusted,
                &mut extra_stats,
            ) {
                // The blocker that holds a block compiles it from its own copy.
                let placed = self.wide.as_ref().filter(|_| extra.every_blocker && matches!(rule, Rule::Network(_)) && !is_shared(&rule));
                if placed.is_some_and(|w| w.holder(Route::of(&rule), identity(raw(&rule))) != target) {
                    continue;
                }
                match self.cosmetic_scoped(rule) {
                    Some(Rule::Network(r)) => {
                        ctx.add(&r);
                        tail.push(*r);
                    }
                    Some(Rule::Cosmetic(r)) => others.cosmetic.push(r),
                    Some(Rule::Scriptlet(r)) => others.scriptlets.push(r),
                    None => {}
                }
            }
            stats.merge(&extra_stats);
        }
        // The rules are held through the compile; spare capacity would be too.
        others.cosmetic.shrink_to_fit();
        others.scriptlets.shrink_to_fit();
        // The ignore rules also cancel the hides before them, so the segment is
        // kept only where no hide can fire on one of its excluded sites.
        let segment_list = segment_list.filter(|&list| {
            let sites = &self.lists[list].scope.exclude;
            !others.cosmetic.iter().any(|r| !r.exception && sites.iter().any(|s| may_fire(&r.domains, s)))
        });
        // #925: the segment's blocks lead the network rules, then one ignore
        // rule per excluded site; the exceptions after them can lift those
        // blocks. Hides and their exceptions come before all of them.
        let mut seen = Seen::default();
        let front = segment_list.map(|list| {
            // The blocker's context, so every `$badfilter` it holds applies.
            let segment = |_| {
                let plain = self.parsed[list].records().filter(|p| p.plain && self.keeps(target, list, p));
                plain.filter_map(|p| match self.rule(list, p) {
                    Rule::Network(r) => Some(*r),
                    _ => None,
                })
                .collect()
            };
            let front = compile_blocker(&ctx, 1, segment, Others::default(), &self.opts, Stats::default(), &mut seen, &WebkitJson::default()).webkit;
            let ignores: Vec<WkRule> = self.lists[list]
                .scope
                .exclude
                .iter()
                .filter_map(|site| ignore_rule(site))
                .collect();
            WebkitJson::join([&front, &WebkitJson::from_rules(&ignores)])
        });
        let tail = Mutex::new(Some(tail));
        let output = compile_blocker(
            &ctx,
            units.len() + 1,
            |unit| match units.get(unit) {
                Some(unit) => self.network_unit(&ctx, target, unit, segment_list),
                None => tail.lock().expect("tail lock").take().expect("tail unit once"),
            },
            others,
            &self.opts,
            stats,
            &mut seen,
            &front.unwrap_or_default(),
        );
        Some(TargetOutput {
            output,
            admitted,
            fingerprint,
        })
    }

    /// #925: the largest list of this blocker with excluded sites, plain
    /// blocks, and no #681 duplicates compiles its plain blocks unconditioned,
    /// then one ignore rule per excluded site. Only one list per blocker can: a
    /// second ignore would cancel the first list's blocks.
    fn segment_list(&self, target: usize) -> Option<usize> {
        (0..self.lists.len())
            .filter(|&l| {
                let scope = &self.lists[l].scope;
                !scope.exclude.is_empty()
                    && scope.exclude.iter().all(|s| ignore_rule(s).is_some())
                    && scope.only.is_none()
                    && !self.parsed[l].has_affinity
                    && self.duplicates[target][l].is_empty()
                    && self.parsed[l].records().any(|p| p.plain && self.keeps(target, l, p))
            })
            .max_by_key(|&l| self.parsed[l].count())
    }

    fn cosmetic_scoped(&self, mut rule: Rule) -> Option<Rule> {
        let Rule::Cosmetic(r) = &mut rule else {
            return Some(rule);
        };
        if !self.cosmetics.generic && !r.exception && r.domains.include.is_empty() {
            return None;
        }
        if self.cosmetics.sites.is_empty() {
            return Some(rule);
        }
        let restricted = restrict(&r.domains, &self.cosmetics.sites)?;
        narrow(&mut r.domains, &mut r.raw, restricted);
        Some(rule)
    }

    /// #836: the exceptions and `$badfilter`s this blocker does not hold, since
    /// Safari applies an exception only in its own blocker. Every blocker gets
    /// every one of them, held or copied, as a host exception can lift a block
    /// naming no host (`/ads.`, `||ads`); `prune` drops those no earlier rule
    /// can match. Affinity still decides where a rule is held.
    fn replicated(&self, target: usize) -> Vec<Rule> {
        let units = self.record_units();
        // Records are read per range, in parallel; the `seen` check that makes
        // each rule count once runs after, in order.
        let candidates = parallel_indices(units.len(), |u| {
            let Unit { list, chunk, range } = &units[u];
            let (list, chunk) = (*list, *chunk);
            let mut found: Vec<(u64, Rule)> = Vec::new();
            for p in self.parsed[list].chunks[chunk][range.clone()]
                .iter()
                .filter(|p| p.shared && !self.holds(target, list, p))
            {
                let mut scoped_rules = Vec::new();
                scoped(self.rule(list, p), &self.lists[list].scope, &mut scoped_rules);
                for rule in scoped_rules {
                    match &rule {
                        Rule::Cosmetic(r) if r.exception => found.push((identity(&r.raw), rule)),
                        Rule::Network(r) if r.exception || r.badfilter => found.push((identity(&r.raw), rule)),
                        _ => {}
                    }
                }
            }
            found
        });
        let mut seen = FxHashSet::default();
        let mut out = Vec::new();
        for (id, rule) in candidates.into_iter().flatten() {
            if !seen.insert(id) {
                continue;
            }
            match rule {
                Rule::Cosmetic(_) => {
                    if let Some(rule) = self.cosmetic_scoped(rule) {
                        out.push(rule);
                    }
                }
                rule => out.push(rule),
            }
        }
        out
    }
}

/// Bytes of list text one thread parses at a time. Chunks end at line ends.
const PARSE_CHUNK: usize = 1 << 20;

/// The records of `list`. Each rule is parsed again from its line when a
/// blocker needs it (`Plan::rule`), with the list's index, so the index is not
/// needed here.
fn parse(list: &ListSpec) -> ParsedList {
    parse_chunked(list, PARSE_CHUNK)
}

/// `parse` with chunks of about `chunk_bytes`, parsed in parallel. The records,
/// line numbers, and stats are the same whatever the chunk size.
fn parse_chunked(list: &ListSpec, chunk_bytes: usize) -> ParsedList {
    let text = list.text.as_str();
    let spans = line_spans(text, chunk_bytes);
    // An affinity block's types carry from one line to the next, so each span
    // starts in the block the lines before it leave open.
    let mut open = None;
    let opens: Vec<Option<u8>> = spans
        .iter()
        .map(|(range, _)| {
            let start = open;
            if text.contains(AFFINITY) {
                open = text[range.clone()].lines().filter_map(affinity_directive).last().unwrap_or(open);
            }
            start
        })
        .collect();
    let parse = |i: usize| parse_lines(list, spans[i].0.clone(), spans[i].1, opens[i]);
    let parts = if spans.len() == 1 { vec![parse(0)] } else { parallel_indices(spans.len(), parse) };
    let mut merged = ParsedList {
        chunks: Vec::with_capacity(parts.len()),
        has_affinity: false,
        has_directive: false,
        stats: Stats::default(),
    };
    for part in parts {
        merged.has_affinity |= part.has_affinity;
        merged.has_directive |= part.has_directive;
        merged.stats.merge(&part.stats);
        merged.chunks.extend(part.chunks);
    }
    merged
}

/// Byte ranges of `text` of about `chunk_bytes` each, ending after a newline,
/// with the number of lines before each.
fn line_spans(text: &str, chunk_bytes: usize) -> Vec<(Range<usize>, u32)> {
    let bytes = text.as_bytes();
    let mut spans = Vec::new();
    let (mut start, mut lines_before) = (0, 0u32);
    loop {
        let end = if bytes.len() - start <= chunk_bytes {
            bytes.len()
        } else {
            memchr::memchr(b'\n', &bytes[start + chunk_bytes..])
                .map_or(bytes.len(), |at| start + chunk_bytes + at + 1)
        };
        spans.push((start..end, lines_before));
        lines_before += bytes[start..end].iter().filter(|&&b| b == b'\n').count() as u32;
        start = end;
        if start == bytes.len() {
            return spans;
        }
    }
}

/// The records of the lines of `list.text` in `span`, whose first line is
/// number `lines_before + 1` and in the affinity block `affinity`.
fn parse_lines(list: &ListSpec, span: Range<usize>, lines_before: u32, mut affinity: Option<u8>) -> ParsedList {
    let text = &list.text[span];
    let mut stats = Stats::default();
    // Sized up front: growing it would leave the old buffers behind.
    let mut rules = Vec::with_capacity(text.lines().count());
    let mut has_affinity = false;
    let mut has_directive = false;
    // Lines are parsed one at a time so affinity blocks can be tracked.
    for (n, line) in text.lines().enumerate() {
        if let Some(types) = affinity_directive(line) {
            has_affinity = true;
            affinity = types;
            continue;
        }
        if line.trim().starts_with("!#") {
            has_directive = true;
        }
        let mut line_stats = Stats::default();
        let offset = line.as_ptr() as usize - list.text.as_ptr() as usize;
        let parsed_line = parse_list(line, 0, list.trusted, &mut line_stats);
        for (position, rule) in parsed_line.iter().enumerate() {
            rules.push(Parsed {
                offset,
                line: lines_before + n as u32 + 1,
                index: position as u32,
                identity: identity_in_scope(raw(rule), &list.scope),
                shared: is_shared(rule),
                network: matches!(rule, Rule::Network(_)),
                in_context: matches!(rule, Rule::Network(r) if NetworkContext::holds(r)),
                plain: is_plain_block(rule),
                route: Route::of(rule),
                affinity,
            });
        }
        stats.merge(&line_stats);
    }
    // Capacity past the records would stay in the cache.
    rules.shrink_to_fit();
    ParsedList {
        chunks: vec![rules],
        has_affinity,
        has_directive,
        stats,
    }
}

fn set_line(rule: &mut Rule, line: u32) {
    match rule {
        Rule::Network(r) => r.source.line = line,
        Rule::Cosmetic(r) => r.source.line = line,
        Rule::Scriptlet(r) => r.source.line = line,
    }
}

const AFFINITY: &str = "!#safari_cb_affinity";

/// The affinity types a `!#safari_cb_affinity(...)` line opens, when `line` is one.
fn affinity_directive(line: &str) -> Option<Option<u8>> {
    let rest = line.trim().strip_prefix(AFFINITY)?;
    Some(rest.strip_prefix('(').and_then(|r| r.strip_suffix(')')).and_then(affinity_mask))
}

/// AdGuard's content blocker types: general, privacy, social, other, custom, security.
fn affinity_mask(names: &str) -> Option<u8> {
    let mask = names.split(',').fold(0u8, |mask, name| {
        mask | match name.trim() {
            "general" => 1,
            "privacy" => 2,
            "social" => 4,
            "other" => 8,
            "custom" => 16,
            "security" => 32,
            "all" => 63,
            _ => 0,
        }
    });
    (mask != 0).then_some(mask)
}

/// The affinity types of a wBlock blocker slot.
fn slot_types(slot: u8) -> u8 {
    match slot {
        1 => 1,
        2 => 2,
        3 => 4 | 32,
        4 => 8,
        5 => 16,
        _ => 8,
    }
}

fn raw(rule: &Rule) -> &str {
    match rule {
        Rule::Network(r) => &r.raw,
        Rule::Cosmetic(r) => &r.raw,
        Rule::Scriptlet(r) => &r.raw,
    }
}

fn is_shared(rule: &Rule) -> bool {
    match rule {
        Rule::Network(r) => r.exception || r.badfilter,
        Rule::Cosmetic(r) => r.exception,
        Rule::Scriptlet(r) => r.exception,
    }
}

fn hash<T: Hash + ?Sized>(value: &T) -> u64 {
    let mut hasher = DefaultHasher::new();
    value.hash(&mut hasher);
    hasher.finish()
}

/// Identity of a rule line: hostnames and non-regex patterns compare
/// case-insensitively (wBlock's `FilterRuleAnalysis.ruleIdentity`).
fn identity(raw: &str) -> u64 {
    let raw = raw.trim();
    let (head, lower, tail) = if let Some((at, _)) = crate::parse::cosmetic::find_marker(raw) {
        let (domains, rest) = raw.split_at(at);
        if domains.contains('/') {
            return hash(raw);
        }
        ("", domains, rest)
    } else {
        let body = raw.strip_prefix("@@").unwrap_or(raw);
        let dollar = body.find('$').unwrap_or(body.len());
        let (pattern, options) = body.split_at(dollar);
        let case_sensitive = options
            .split(',')
            .any(|o| o.trim_start_matches('$') == "match-case");
        if pattern.starts_with('/') || case_sensitive {
            return hash(raw);
        }
        (&raw[..raw.len() - body.len()], pattern, options)
    };
    // `hash` of `head + lower.to_ascii_lowercase() + tail`, without building it.
    let mut hasher = DefaultHasher::new();
    hasher.write(head.as_bytes());
    let mut buf = [0u8; 64];
    for chunk in lower.as_bytes().chunks(buf.len()) {
        let buf = &mut buf[..chunk.len()];
        buf.copy_from_slice(chunk);
        buf.make_ascii_lowercase();
        hasher.write(buf);
    }
    hasher.write(tail.as_bytes());
    hasher.write_u8(0xff);
    hasher.finish()
}

/// Lists with different site scopes compile one rule differently, so the
/// scope is part of the identity used for #681 and shards.
fn identity_in_scope(raw: &str, scope: &SiteScope) -> u64 {
    let id = identity(raw);
    if scope.is_empty() {
        id
    } else {
        hash(&(id, &scope.exclude, &scope.only))
    }
}

/// A site as a domain matcher: `name.*` is an entity.
fn matcher(site: &str) -> DomainMatcher {
    match site.strip_suffix(".*") {
        Some(name) => DomainMatcher::Entity(name.to_string()),
        None => DomainMatcher::Hostname(site.to_string()),
    }
}

/// `None` for a regex or ancestor, which name no site to narrow.
fn site(m: &DomainMatcher) -> Option<String> {
    matches!(m, DomainMatcher::Hostname(_) | DomainMatcher::Entity(_)).then(|| m.text())
}

/// Whether `host` matches everything `site` does. `name.*` covers each
/// `name.<ending>` and its subdomains; a plain host never covers a pattern.
fn covers(host: &str, site: &str) -> bool {
    if host == site || site.ends_with(&format!(".{host}")) {
        return true;
    }
    let Some(name) = host.strip_suffix(".*") else {
        return false;
    };
    let name = format!(".{name}.");
    let dotted = format!(".{site}");
    if site.ends_with(".*") {
        dotted.ends_with(&format!("{name}*"))
    } else {
        dotted
            .find(&name)
            .is_some_and(|at| at + name.len() < dotted.len())
    }
}

/// Whether a hide on `domains` can fire on the excluded site `excluded`. An
/// entry this cannot read (a regex) counts as overlapping.
fn may_fire(domains: &DomainList, excluded: &str) -> bool {
    if domains.exclude.iter().filter_map(site).any(|e| covers(&e, excluded)) {
        return false;
    }
    domains.include.is_empty()
        || domains.include.iter().any(|m| match site(m) {
            Some(host) => covers(&host, excluded) || covers(excluded, &host),
            None => true,
        })
}

struct Restricted {
    list: DomainList,
    /// Excluded sites that are subdomains of a kept include; the include still
    /// matches them, so they need their own handling (#767).
    uncovered: Vec<DomainMatcher>,
}

/// Narrows a domain list so it never matches an excluded site, and (with
/// `only`) matches nothing outside the selected sites. `None` when nothing is
/// left. wBlock's FilterListSiteExclusion.restrictDomainList.
fn restrict(domains: &DomainList, scope: &SiteScope) -> Option<Restricted> {
    let positives: Vec<String> = domains.include.iter().filter_map(site).collect();
    let regex_includes: Vec<DomainMatcher> = domains
        .include
        .iter()
        .filter(|m| site(m).is_none())
        .cloned()
        .collect();
    let negated: Vec<String> = domains.exclude.iter().filter_map(site).collect();
    if let Some(only) = &scope.only {
        let mut intersection: Vec<String> = Vec::new();
        for s in only {
            if positives.is_empty() && regex_includes.is_empty() {
                intersection.push(s.clone());
            }
            for host in &positives {
                if covers(host, s) {
                    intersection.push(s.clone());
                } else if covers(s, host) {
                    intersection.push(host.clone());
                }
            }
        }
        intersection.sort();
        intersection.dedup();
        if intersection.is_empty() {
            return None;
        }
        let narrowed = DomainList {
            include: intersection.iter().map(|s| matcher(s)).collect(),
            exclude: domains.exclude.clone(),
        };
        let mut exclude = scope.exclude.clone();
        exclude.extend(negated);
        return restrict(
            &narrowed,
            &SiteScope {
                exclude,
                only: None,
            },
        );
    }
    if positives.is_empty() && regex_includes.is_empty() {
        let mut list = domains.clone();
        for s in &scope.exclude {
            if !negated.iter().any(|n| covers(n, s)) {
                list.exclude.push(matcher(s));
            }
        }
        return Some(Restricted {
            list,
            uncovered: Vec::new(),
        });
    }
    let kept: Vec<String> = positives
        .iter()
        .filter(|h| !scope.exclude.iter().any(|s| covers(s, h)))
        .cloned()
        .collect();
    if kept.is_empty() && regex_includes.is_empty() {
        return None;
    }
    let uncovered = scope
        .exclude
        .iter()
        .filter(|s| {
            kept.iter().any(|h| h != *s && covers(h, s)) && !negated.iter().any(|n| covers(n, s))
        })
        .map(|s| matcher(s))
        .collect();
    let mut include: Vec<DomainMatcher> = kept.iter().map(|s| matcher(s)).collect();
    include.extend(regex_includes);
    Some(Restricted {
        list: DomainList {
            include,
            exclude: domains.exclude.clone(),
        },
        uncovered,
    })
}

/// Gives a cosmetic or scriptlet rule its narrowed domains, in `raw` too so
/// the runtime engine applies the same scope as Safari.
fn narrow(domains: &mut DomainList, raw: &mut String, restricted: Restricted) {
    *domains = restricted.list;
    domains.exclude.extend(restricted.uncovered);
    *raw = with_domains(raw, domains);
}

/// Applies a list's site scope to one rule: zero rules when it no longer
/// applies anywhere, two when a block needs a companion exception for an
/// excluded subdomain of its scope (#767). A `$badfilter` names a filter, not
/// pages, so it stays as written and cancels the filter in any list's scope.
fn scoped(rule: Rule, scope: &SiteScope, out: &mut Vec<Rule>) {
    if scope.is_empty() || matches!(&rule, Rule::Network(r) if r.badfilter) {
        out.push(rule);
        return;
    }
    match rule {
        Rule::Network(mut r) => {
            let Some(restricted) = restrict(&r.from, scope) else {
                return;
            };
            let companion = (!restricted.uncovered.is_empty() && !r.exception)
                .then(|| NetworkRule {
                    exception: true,
                    important: false,
                    from: DomainList {
                        include: restricted.uncovered,
                        exclude: Vec::new(),
                    },
                    ..r.as_ref().clone()
                });
            r.from = restricted.list;
            // An important block would outrank its companion; the user's
            // exclusion wins over `important`.
            r.important &= companion.is_none();
            for mut r in std::iter::once(*r).chain(companion) {
                r.raw = restate(&r);
                out.push(Rule::Network(Box::new(r)));
            }
        }
        Rule::Cosmetic(mut r) => {
            let Some(restricted) = restrict(&r.domains, scope) else {
                return;
            };
            narrow(&mut r.domains, &mut r.raw, restricted);
            out.push(Rule::Cosmetic(r));
        }
        Rule::Scriptlet(mut r) => {
            let Some(restricted) = restrict(&r.domains, scope) else {
                return;
            };
            narrow(&mut r.domains, &mut r.raw, restricted);
            out.push(Rule::Scriptlet(r));
        }
    }
}

/// A block Safari enforces natively with no positive page domain, which an
/// ignore rule placed after it can cancel for excluded sites (#925).
/// What decides the blocker of a rule (`Wide`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Route {
    /// The list's assignment and the rule's identity.
    Identity,
    /// A block or exception anchored at a whole host, with the hash of the
    /// host's registrable domain. A block goes to the wide blocker when an
    /// exception names its site.
    Site(u64),
    /// A block not anchored at a whole host (`/ads/`, `||ads`, `||google.*^`),
    /// which can match a load that any exception matches.
    Wide,
}

impl Route {
    fn of(rule: &Rule) -> Route {
        let Rule::Network(r) = rule else {
            return Route::Identity;
        };
        // A page exception (`$document`, `$generichide`) names its page, not
        // the loads it lifts.
        if r.badfilter || !r.scope.is_empty() {
            return Route::Identity;
        }
        // `prune::anchor` reads the compiled filter the same way.
        let host = crate::compile::split_host(&r.pattern).filter(|(_, rest)| {
            rest.starts_with(['^', '/', ':', '?']) || rest.is_empty() && r.pattern.right_anchored
        });
        // A public suffix (`||com/ads.js`) is every site under it.
        match host.as_ref().and_then(|(host, _)| crate::registrable_domain(host)) {
            Some(site) => Route::Site(hash(site)),
            None if r.exception => Route::Identity,
            None => Route::Wide,
        }
    }
}

fn is_plain_block(rule: &Rule) -> bool {
    const NATIVE: ResourceTypes = ResourceTypes::SCRIPT
        .union(ResourceTypes::IMAGE)
        .union(ResourceTypes::CSS)
        .union(ResourceTypes::XHR)
        .union(ResourceTypes::FRAME)
        .union(ResourceTypes::PING)
        .union(ResourceTypes::MEDIA)
        .union(ResourceTypes::FONT)
        .union(ResourceTypes::WEBSOCKET)
        .union(ResourceTypes::OTHER)
        .union(ResourceTypes::DOC);
    let Rule::Network(r) = rule else { return false };
    !r.exception
        && !r.badfilter
        && !r.important
        && r.action == NetworkAction::Block
        && r.from.include.is_empty()
        && r.to.is_empty()
        && r.denyallow.is_empty()
        && r.method.include.is_empty()
        && r.method.exclude.is_empty()
        && r.runtime_only_options.is_empty()
        && r.scope.is_empty()
        && matches!(r.party, Party::Any | Party::First | Party::Third)
        && NATIVE.contains(r.types)
        && NATIVE.contains(r.negated_types)
}

/// The ignore rule that lifts a #925 segment on an excluded site. `None` when
/// an entity has no top-URL form.
fn ignore_rule(site: &str) -> Option<WkRule> {
    let mut trigger = WkTrigger {
        url_filter: ".*".into(),
        ..Default::default()
    };
    match site.strip_suffix(".*") {
        Some(name) => {
            trigger.if_top_url = Some(domain_top_url(&DomainMatcher::Entity(name.into()))?);
        }
        None => trigger.if_domain = Some(vec![format!("*{site}")]),
    }
    Some(WkRule {
        trigger,
        action: WkAction::IgnorePreviousRules,
    })
}

impl Stats {
    pub(crate) fn merge(&mut self, other: &Stats) {
        self.lines += other.lines;
        self.rules += other.rules;
        for (reason, n) in &other.dropped {
            *self.dropped.entry(reason.clone()).or_default() += n;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{json, Value};
    use std::collections::HashSet;

    /// The rules blocker `target` keeps from `list`, site scope applied.
    fn included(plan: &Plan, target: usize, list: usize) -> Vec<Rule> {
        let scope = &plan.lists[list].scope;
        let mut out = Vec::new();
        for p in plan.parsed[list].records() {
            if plan.keeps(target, list, p) {
                scoped(plan.rule(list, p), scope, &mut out);
            }
        }
        out
    }

    fn plan(lists: Value, targets: Value, cosmetics: Value) -> Plan {
        Plan::new(serde_json::from_value(json!({"safari": [18, 0], "lists": lists, "targets": targets, "cosmetics": cosmetics})).unwrap())
    }

    /// `plan`, for blockers Safari would limit to `rules` rules each.
    fn plan_within(rules: usize, lists: Value, targets: Value) -> Plan {
        let limits = json!({"rules": rules});
        Plan::new(serde_json::from_value(json!({"safari": [18, 0], "lists": lists, "targets": targets, "limits": limits})).unwrap())
    }

    fn rules(plan: &Plan, target: usize) -> Vec<Value> {
        serde_json::from_str(&crate::webkit::to_json(
            &plan.compile_target(target, &[]).output.webkit,
        ))
        .unwrap()
    }

    fn two_lists(left: &str, right: &str) -> Plan {
        plan(
            json!([{ "id":"left", "text":left }, { "id":"right", "text":right }]),
            json!([{ "slot":1, "lists":[{"list":0}] }, { "slot":2, "lists":[{"list":1}] }]),
            json!({}),
        )
    }

    fn two_list_request(left: &str, right: &str, scope: Value) -> PlanRequest {
        serde_json::from_value(json!({
            "safari": [18, 0],
            "lists": [{ "id": "left", "text": left, "scope": scope }, { "id": "right", "text": right }],
            "targets": [{ "slot": 1, "lists": [{"list": 0}, {"list": 1}] }],
        }))
        .unwrap()
    }

    #[test]
    fn parse_cache_reparses_only_changed_lists() {
        let cache = ParseCache::default();
        let first = Plan::with_cache(two_list_request("||a.example^", "||b.example^", json!({})), &cache);
        let changed = "||c.example^\n||d.example^";
        let second = Plan::with_cache(two_list_request("||a.example^", changed, json!({})), &cache);
        assert!(Arc::ptr_eq(&first.parsed[0], &second.parsed[0]));
        assert!(!Arc::ptr_eq(&first.parsed[1], &second.parsed[1]));
        // The new entry replaces the old one: the cache holds one plan's lists.
        assert_eq!(cache.entries().len(), 2);
        let fresh = Plan::new(two_list_request("||a.example^", changed, json!({})));
        assert_eq!(rules(&second, 0), rules(&fresh, 0));
        // A site scope changes what the records hold, so it is part of the key.
        let scoped = Plan::with_cache(
            two_list_request("||a.example^", changed, json!({"exclude": ["a.example"]})),
            &cache,
        );
        assert!(!Arc::ptr_eq(&second.parsed[0], &scoped.parsed[0]));
        cache.clear();
        assert!(cache.entries().is_empty());
    }

    #[test]
    fn chunked_parse_matches_one_piece() {
        let text: String = (0..300)
            .map(|i| match i % 4 {
                _ if i % 50 == 7 => format!("!#safari_cb_affinity{}\n", ["(privacy)", "", "(general,social)"][i % 3]),
                0 => format!("||ad{i}.example^$third-party\n"),
                1 => format!("! comment {i}\n"),
                2 => format!("@@||ad{}.example^\r\n", i - 2),
                _ => format!("example.com##.ad-{i}\n"),
            })
            .collect();
        let list = ListSpec {
            id: "chunks".into(),
            text,
            path: None,
            trusted: false,
            scope: SiteScope::default(),
        };
        let records = |parsed: &ParsedList| -> Vec<(usize, u32, u32, u64, bool, bool, Option<u8>)> {
            parsed
                .records()
                .map(|p| (p.offset, p.line, p.index, p.identity, p.shared, p.network, p.affinity))
                .collect()
        };
        let whole = parse_chunked(&list, usize::MAX);
        for chunk in [1, 64, 1000] {
            let chunked = parse_chunked(&list, chunk);
            assert!(chunked.chunks.len() > 1, "chunk {chunk} gives one chunk");
            assert_eq!(records(&chunked), records(&whole), "chunk {chunk}");
            assert_eq!(chunked.has_affinity, whole.has_affinity);
            assert_eq!(chunked.stats.lines, whole.stats.lines);
            assert_eq!(chunked.stats.rules, whole.stats.rules);
        }
    }

    #[test]
    fn cross_blocker_cosmetic_exception() {
        let plan = two_lists("##.consent-dialog", "example.com#@#.consent-dialog");
        let output = rules(&plan, 0);
        assert!(
            output.iter().any(|r| r["trigger"]["unless-domain"]
                .to_string()
                .contains("example.com")),
            "{output:?}"
        );
    }

    #[test]
    fn cross_blocker_wildcard_exception() {
        let plan = two_lists("||cdn.example^", "@@*$script,domain=example.com");
        assert!(rules(&plan, 0)
            .iter()
            .any(|r| r["action"]["type"] == "ignore-previous-rules"));
    }

    #[test]
    fn cross_blocker_badfilter() {
        let plan = two_lists("||cdn.example^", "||cdn.example^$badfilter");
        assert!(rules(&plan, 0).is_empty());
    }

    #[test]
    fn excluded_segment_respects_badfilter() {
        let plan = plan(
            json!([{ "id":"list", "text":"||cdn.example^\n||cdn.example^$badfilter", "scope":{"exclude":["other.com"]} }]),
            json!([{ "slot":1, "lists":[{"list":0}] }]),
            json!({}),
        );
        assert!(!rules(&plan, 0)
            .iter()
            .any(|r| r["action"]["type"] == "block"));
    }

    #[test]
    fn badfilter_cancels_across_site_scopes() {
        // uBO's own filters `$badfilter` rules of other lists; a site scope on
        // either list must not keep the filter alive.
        let scopes = [json!({}), json!({"exclude":["other.com"]}), json!({"only":["news.com"]})];
        for block_scope in &scopes {
            for bad_scope in &scopes {
                for targets in [json!([{"slot":1,"lists":[{"list":0},{"list":1}]}]),
                                json!([{"slot":1,"lists":[{"list":0}]}, {"slot":2,"lists":[{"list":1}]}])] {
                    let plan = plan(
                        json!([{"id":"a", "text":"||cdn.example^\n||keep.example^", "scope":block_scope},
                               {"id":"b", "text":"||cdn.example^$badfilter", "scope":bad_scope}]),
                        targets,
                        json!({}),
                    );
                    let rules = rules(&plan, 0);
                    assert!(!rules.iter().any(|r| r["trigger"]["url-filter"].as_str().unwrap().contains("cdn")),
                        "{block_scope} {bad_scope}: {rules:?}");
                }
            }
        }
    }

    #[test]
    fn fingerprint_follows_only_what_a_blocker_compiles() {
        let make = |a: &str, b: &str| {
            plan(
                json!([{"id":"a", "text":a}, {"id":"b", "text":b}]),
                json!([{"slot":1,"lists":[{"list":0}]}, {"slot":2,"lists":[{"list":1}]}]),
                json!({}),
            )
        };
        let base = make("##.a", "##.b");
        let fp = |p: &Plan, t| {
            let fingerprint = p.fingerprint(t, &[]);
            assert_eq!(fingerprint, p.compile_target(t, &[]).fingerprint);
            fingerprint
        };
        // Another blocker's list changing leaves this one alone...
        let other = make("##.a", "##.b\n##.c");
        assert_eq!(fp(&base, 0), fp(&other, 0));
        assert_ne!(fp(&base, 1), fp(&other, 1));
        // ...unless it brings an exception this blocker copies (#836).
        let exception = make("##.a", "##.b\n#@#.a");
        assert_ne!(fp(&base, 0), fp(&exception, 0));
        // ...or a block, which goes to the blocker that holds the plan's.
        let block = make("##.a", "##.b\n||b.example^");
        assert_ne!(rules(&base, 0), rules(&block, 0));
        assert_ne!(fp(&base, 0), fp(&block, 0));
        // ...or takes over a rule this blocker compiled (#681): the first
        // list in compile order owns a rule both have.
        let make_reversed = |first: &str| {
            plan(
                json!([{"id":"b", "text":first}, {"id":"a", "text":"##.a\n##.x"}]),
                json!([{"slot":1,"lists":[{"list":1}]}, {"slot":2,"lists":[{"list":0}]}]),
                json!({}),
            )
        };
        let (before, after) = (make_reversed("##.b"), make_reversed("##.b\n##.a"));
        assert_ne!(rules(&before, 0), rules(&after, 0));
        assert_ne!(fp(&before, 0), fp(&after, 0));
    }

    #[test]
    fn duplicate_owner_survives_multiple_targets() {
        let plan = plan(
            json!([{ "id":"same", "text":"||example.com^" }]),
            json!([
                {"slot":1,"lists":[{"list":0}]}, {"slot":2,"lists":[{"list":0}]}
            ]),
            json!({}),
        );
        assert_eq!(rules(&plan, 0).len(), 1);
        assert!(rules(&plan, 1).is_empty());
    }

    #[test]
    fn admission_counts_first_copy_and_preserves_runtime_rules() {
        let plan = plan(
            json!([
                {"id":"first", "text":"||ads.example^\nexample.com##+js(set, foo, bar)"},
                {"id":"second", "text":"||ads.example^\n||other.example^"}
            ]),
            json!([{"slot":1,"lists":[{"list":0},{"list":1}]}]),
            json!({}),
        );
        let output = plan.compile_target(0, &[]);
        assert_eq!(output.admitted["first"], 2);
        assert_eq!(output.admitted["second"], 1);
        assert!(output
            .output
            .runtime
            .iter()
            .any(|rule| rule.contains("+js(set, foo, bar)")));
    }

    #[test]
    fn affinity_lists_are_not_cross_target_deduplicated() {
        let plan = plan(
            json!([{"id":"affinity", "text":"!#safari_cb_affinity(social)\n||ads.example^"}]),
            json!([{"slot":3,"lists":[]},{"slot":3,"lists":[]}]),
            json!({}),
        );
        assert_eq!(rules(&plan, 0).len(), 1);
        assert_eq!(rules(&plan, 1).len(), 1);
    }

    #[test]
    fn exclusion_segment_and_other_rules_are_ordered() {
        let plan = plan(
            json!([
                {"id":"excluded", "text":"||tracker.net^\n||scoped.net^$domain=news.org", "scope":{"exclude":["example.com", "shop.*"]}},
                {"id":"other", "text":"||other.net^"}
            ]),
            json!([{"slot":1,"lists":[{"list":0},{"list":1}]}]),
            json!({}),
        );
        let rules = rules(&plan, 0);
        assert_eq!(rules[0]["action"]["type"], "block");
        assert_eq!(rules[1]["action"]["type"], "ignore-previous-rules");
        assert!(rules[1]["trigger"]["if-domain"].is_array());
        assert!(rules[2]["trigger"]["if-top-url"].is_array());
        assert!(rules[3..].iter().any(|rule| rule["trigger"]["url-filter"]
            .as_str()
            .unwrap()
            .contains("other")));
        assert_eq!(plan.compile_target(0, &[]).admitted["excluded"], 2);
    }

    /// WebKit applies a hide matching any load to the page, so a hide
    /// exception covers every load of its page; it may then cancel nothing
    /// but hides, so every block of the blocker (the #925 segment, extras,
    /// copied rules, generic blocks) comes after it.
    #[test]
    fn hide_exceptions_cover_every_load_and_precede_every_block() {
        let plan = plan(
            json!([
                {"id":"excluded", "text":"||tracker.net^\n/banner.", "scope":{"exclude":["shop.example"]}},
                {"id":"own", "text":"/ads.js\n##.ad\n@@||site.example^$generichide\n@@||site.example^$genericblock\n@@||page.example^$elemhide"},
                {"id":"other", "text":"@@||cdn.example/ads.js"}
            ]),
            json!([{"slot":1,"lists":[{"list":0},{"list":1}]},{"slot":2,"lists":[{"list":2}]}]),
            json!({}),
        );
        let extra = Extra { text: "||extra.example^\n/extra-ad.".into(), trusted: true, every_blocker: false };
        let output = plan.compile_target(0, &[extra]).output.webkit;
        let rules: Vec<Value> = serde_json::from_str(output.as_str()).unwrap();
        let hide_exception = |r: &Value| {
            r["action"]["type"] == "ignore-previous-rules"
                && r["trigger"]["url-filter"] == ".*"
                && ["site", "page"].iter().any(|h| r["trigger"]["if-top-url"].to_string().contains(h))
                && r["trigger"]["resource-type"].is_null()
                && r["trigger"]["if-domain"].is_null()
        };
        let last = rules.iter().rposition(|r| hide_exception(r)).expect("typeless hide exceptions");
        let pages: String = rules.iter().filter(|r| hide_exception(r)).map(|r| r["trigger"]["if-top-url"].to_string()).collect();
        assert!(pages.contains("site") && pages.contains("page"), "{rules:?}");
        let first_block = rules.iter().position(|r| r["action"]["type"] == "block").unwrap();
        assert!(last < first_block, "{rules:?}");
        assert!(rules[..first_block].iter().all(|r| hide_exception(r) || r["action"]["type"] == "css-display-none"));
        for text in ["tracker", "banner", "extra", "cdn\\\\.example", "ads\\\\.js"] {
            assert!(output.as_str().contains(text), "{text}: {rules:?}");
        }
    }

    /// A list without plain blocks has nothing for an ignore rule to lift, so
    /// the segment goes to a list that has some.
    #[test]
    fn segment_needs_plain_blocks() {
        let plan = plan(
            json!([
                {"id":"big", "text":"||a.net^$badfilter\n||b.net^$popup\n||c.net^$domain=x.org", "scope":{"exclude":["skip.org"]}},
                {"id":"small", "text":"||d.net^", "scope":{"exclude":["other.org"]}}
            ]),
            json!([{"slot":1,"lists":[{"list":0},{"list":1}]}]),
            json!({}),
        );
        let ignores: Vec<Value> = rules(&plan, 0).into_iter().filter(|r| r["action"]["type"] == "ignore-previous-rules").collect();
        assert!(!ignores.is_empty());
        assert!(ignores.iter().all(|r| r.to_string().contains("other.org")), "{ignores:?}");
    }

    #[test]
    fn selected_scope_and_cosmetic_preferences() {
        let selected = plan(
            json!([{ "id":"list", "text":"||tracker.net^$domain=example.com\nexample.com##.specific\nother.org##.gone", "scope":{"only":["sub.example.com"]}}, {"id":"generic", "text":"##.generic"}]),
            json!([{"slot":1,"lists":[{"list":0},{"list":1}]}]),
            json!({"generic":false}),
        );
        let output = selected.compile_target(0, &[]);
        let json = crate::webkit::to_json(&output.output.webkit);
        assert!(json.contains("sub\\\\.example\\\\.com"));
        assert!(!json.contains("other.org"));
        assert!(!json.contains(".generic"));
        // Site hides are the runtime's, narrowed to the list's sites.
        assert_eq!(output.output.runtime, ["sub.example.com##.specific"]);

        // #899 reaches runtime rules too.
        let scoped = plan(
            json!([{"id":"list", "text":"example.com##div:has-text(Ad)"}]),
            json!([{"slot":1,"lists":[{"list":0}]}]),
            json!({"exclude": ["sub.example.com"]}),
        );
        let runtime = scoped.compile_target(0, &[]).output.runtime;
        assert!(
            runtime.contains(&"example.com,~sub.example.com##div:has-text(Ad)".to_string()),
            "{runtime:?}"
        );
    }

    /// The runtime engine reads popup rules and page exceptions from their raw
    /// lines, so a list's site scope has to reach those lines too.
    #[test]
    fn site_scope_reaches_runtime_network_rules() {
        let text = "||pop.net^$popup\n||only.net^$popup,domain=a.org|b.org\n||imp.net^$popup,important,domain=imp.org\n@@||page.org^$elemhide\n@@$popup,domain=c.org";
        let engine = |scope: Value| {
            let plan = plan(json!([{"id":"list", "text":text, "scope":scope}, {"id":"other", "text":"||c.net^$popup"}]), json!([{"slot":1,"lists":[{"list":0},{"list":1}]}]), json!({}));
            crate::runtime::Engine::build(&plan.compile_target(0, &[]).output.runtime)
        };
        let blocked = |e: &crate::runtime::Engine, opener: &str, target: &str| {
            e.lookup(&format!("wbe-popup-https://{opener}/#https://{target}/x")).popup_blocked == Some(true)
        };
        let elemhide = |e: &crate::runtime::Engine, page: &str| e.lookup(&format!("https://{page}/")).generichide;
        let excluded = engine(json!({"exclude":["example.org", "a.org", "page.org", "c.org", "sub.imp.org"]}));
        assert!(blocked(&excluded, "imp.org", "imp.net"));
        assert!(!blocked(&excluded, "sub.imp.org", "imp.net"));
        assert!(blocked(&excluded, "news.org", "pop.net"));
        assert!(!blocked(&excluded, "example.org", "pop.net"));
        assert!(!blocked(&excluded, "a.org", "only.net"));
        assert!(blocked(&excluded, "b.org", "only.net"));
        assert!(!elemhide(&excluded, "page.org"));
        assert!(blocked(&excluded, "c.org", "c.net"));

        let only = engine(json!({"only":["example.org", "b.org", "page.org"]}));
        assert!(blocked(&only, "example.org", "pop.net"));
        assert!(!blocked(&only, "news.org", "pop.net"));
        assert!(!blocked(&only, "a.org", "only.net"));
        assert!(blocked(&only, "b.org", "only.net"));
        assert!(elemhide(&only, "page.org"));
        assert!(blocked(&only, "c.org", "c.net"));

        let elsewhere = engine(json!({"only":["example.org"]}));
        assert!(!elemhide(&elsewhere, "page.org"));
    }

    #[test]
    fn selected_scope_discards_disjoint_rules_and_supports_entities() {
        let plan = plan(
            json!([{ "id":"list", "text":"||tracker.net^$domain=example.com\nother.org##.gone", "scope":{"only":["example.*"]}}]),
            json!([{"slot":1,"lists":[{"list":0}]}]),
            json!({}),
        );
        let output = crate::webkit::to_json(&plan.compile_target(0, &[]).output.webkit);
        assert!(output.contains("example"), "{output}");
        assert!(!output.contains("gone"), "{output}");
    }

    #[test]
    fn site_scope_cases() {
        // (rule, exclude, only, expected substring or None when dropped)
        let cases: [(&str, &[&str], Option<&[&str]>, Option<&str>); 9] = [
            ("##.ad", &[], Some(&["amazon.*"]), Some("amazon.*##.ad")), // #1032
            (
                "amazon.*##.ad",
                &[],
                Some(&["amazon.it"]),
                Some("amazon.it##.ad"),
            ), // #1031
            (
                "amazon.it,ebay.it##.ad",
                &[],
                Some(&["amazon.*"]),
                Some("amazon.it##.ad"),
            ),
            (
                "amazon.it,ebay.it##.ad",
                &["amazon.*"],
                None,
                Some("ebay.it##.ad"),
            ),
            ("##.ad", &["amazon.*"], None, Some("~amazon.*##.ad")),
            ("~example.com##.ad", &[], Some(&["example.com"]), None),
            ("other.test##.ad", &[], Some(&["example.com"]), None),
            (
                "example.com##+js(set, a, 1)",
                &[],
                Some(&["news.example.com"]),
                Some("news.example.com##+js(set, a, 1)"),
            ),
            (
                "amazon.it##.ad",
                &["notamazon.*", "amazon.it.example.com"],
                None,
                Some("amazon.it##.ad"),
            ),
        ];
        for (rule, exclude, only, expected) in cases {
            let scope = match only {
                Some(only) => json!({"exclude": exclude, "only": only}),
                None => json!({"exclude": exclude}),
            };
            let plan = plan(
                json!([{"id":"list", "text": rule, "scope": scope}]),
                json!([{"slot":1,"lists":[{"list":0}]}]),
                json!({}),
            );
            let kept: Vec<String> = included(&plan, 0, 0)
                .iter()
                .map(|r| raw(r).to_string())
                .collect();
            match expected {
                Some(expected) => assert!(kept.iter().any(|r| r == expected), "{rule}: {kept:?}"),
                None => assert!(kept.is_empty(), "{rule}: {kept:?}"),
            }
        }
    }

    #[test]
    fn replication_matches_both_prefix_directions() {
        let plan = plan(
            json!([
                {"id":"blocks", "text":"||one.test/path\n||two.test/path/deep"},
                {"id":"exceptions", "text":"@@||one.test/path/deep\n@@||two.test/path\n@@||other.test^"}
            ]),
            json!([{"slot":1,"lists":[{"list":0}]},{"slot":2,"lists":[{"list":1}]}]),
            json!({}),
        );
        let output = crate::webkit::to_json(&plan.compile_target(0, &[]).output.webkit);
        let ignores = output.matches("ignore-previous-rules").count();
        assert!(output.contains("one\\\\.test/path/deep") && ignores == 4, "{output}");
        assert!(!output.contains("other\\\\.test"), "{output}");
    }

    #[test]
    fn segment_blocks_honor_badfilters_of_other_lists() {
        let plan = plan(
            json!([
                { "id":"big", "text":"||cdn.example^\n||keep.example^", "scope":{"exclude":["other.org"]}},
                { "id":"fix", "text":"||cdn.example^$badfilter"}
            ]),
            json!([{"slot":1,"lists":[{"list":0},{"list":1}]}]),
            json!({}),
        );
        let out = crate::webkit::to_json(&plan.compile_target(0, &[]).output.webkit);
        assert!(out.contains("keep") && !out.contains("cdn"), "{out}");
    }

    #[test]
    fn segment_block_survives_cosmetic_exception() {
        let plan = plan(
            json!([{ "id":"list", "text":"||cdn.example^\n@@||example.com^$generichide", "scope":{"exclude":["other.org"]}}]),
            json!([{"slot":1,"lists":[{"list":0}]}]),
            json!({}),
        );
        let rules = rules(&plan, 0);
        let block = rules
            .iter()
            .position(|r| r["action"]["type"] == "block")
            .unwrap();
        for r in &rules[block + 1..] {
            if r["action"]["type"] == "ignore-previous-rules"
                && r["trigger"]["if-domain"]
                    .to_string()
                    .contains("example.com")
            {
                assert_eq!(
                    r["trigger"]["resource-type"],
                    json!(["document"]),
                    "{rules:?}"
                );
            }
        }
    }

    #[test]
    fn exception_lifts_segment_navigation_block() {
        // The segment's untyped `||host^` blocks navigation to the host, so an
        // exception for the host must take the untyped form that lifts it.
        let plan = plan(
            json!([{"id":"a", "text":"||cdn.example^", "scope":{"exclude":["other.com"]}},
                   {"id":"b", "text":"@@||cdn.example^"}]),
            json!([{"slot":1,"lists":[{"list":0},{"list":1}]}]),
            json!({}),
        );
        let rules = rules(&plan, 0);
        assert!(rules.iter().any(|r| r["action"]["type"] == "ignore-previous-rules"
            && r["trigger"]["resource-type"].is_null()
            && r["trigger"]["url-filter"].as_str().unwrap().contains("cdn")), "{rules:?}");
    }

    #[test]
    fn important_block_honors_excluded_subdomain() {
        let plan = plan(
            json!([{ "id":"list", "text":"||cdn.example^$script,domain=example.com,important", "scope":{"exclude":["shop.example.com"]}}]),
            json!([{"slot":1,"lists":[{"list":0}]}]),
            json!({}),
        );
        let rules = rules(&plan, 0);
        let exception = rules.iter().rposition(|r| {
            r["action"]["type"] == "ignore-previous-rules"
                && r["trigger"]["if-top-url"]
                    .to_string()
                    .contains("shop\\\\.example\\\\.com")
        });
        let block = rules.iter().rposition(|r| r["action"]["type"] == "block");
        assert!(exception > block, "{rules:?}");
    }

    #[test]
    fn scoped_parent_gets_subdomain_companion() {
        let plan = plan(
            json!([{ "id":"list", "text":"||tracker.net^$domain=example.com", "scope":{"exclude":["sub.example.com"]}}]),
            json!([{"slot":1,"lists":[{"list":0}]}]),
            json!({}),
        );
        let rules = rules(&plan, 0);
        assert!(rules
            .iter()
            .any(|rule| rule["action"]["type"] == "ignore-previous-rules"
                && rule["trigger"]["if-top-url"]
                    .to_string()
                    .contains("sub\\\\.example\\\\.com")));
    }

    #[test]
    fn affinity_routes_social_and_security_to_slot_three() {
        let plan = plan(
            json!([{ "id":"list", "text":"!#safari_cb_affinity(social)\n||social.test^\n!#safari_cb_affinity(security)\n||security.test^\n!#safari_cb_affinity(privacy)\n||privacy.test^" }]),
            json!([{"slot":3,"lists":[]},{"slot":2,"lists":[]}]),
            json!({}),
        );
        let social = crate::webkit::to_json(&plan.compile_target(0, &[]).output.webkit);
        assert!(
            social.contains("social") && social.contains("security") && !social.contains("privacy")
        );
        assert!(
            crate::webkit::to_json(&plan.compile_target(1, &[]).output.webkit).contains("privacy")
        );
    }

    #[test]
    fn distinct_exception_contexts_keep_both_hides() {
        let plan = plan(
            json!([{ "id":"left", "text":"##.ad\n#@#.other" }, {"id":"right", "text":"##.ad"}]),
            json!([{"slot":1,"lists":[{"list":0}]},{"slot":2,"lists":[{"list":1}]}]),
            json!({}),
        );
        for t in 0..2 {
            assert!(rules(&plan, t).iter().any(|rule| rule["action"]["type"] == "css-display-none"));
        }
    }

    fn actions(plan: &Plan, target: usize) -> Vec<String> {
        rules(plan, target).iter().map(|rule| rule["action"]["type"].as_str().unwrap().to_owned()).collect()
    }

    /// The blocks an exception can reach go to one blocker with it: those not
    /// anchored at a host and those on the site the exception names. The
    /// other blocker then needs no copy of the exception.
    #[test]
    fn blocks_exceptions_reach_share_one_blocker() {
        // Room in the wide blocker for what it takes and no more.
        let plan = plan_within(
            11,
            json!([{ "id":"left", "text":"||plain.example^\n@@||cdn.ads.example/ok.js" },
                   { "id":"right", "text":"||ads.example^\n/banner.\n||other.example^\n||com/track.js" }]),
            json!([{"slot":1,"lists":[{"list":0}]},{"slot":2,"lists":[{"list":1}]}]),
        );
        let filters = |t| rules(&plan, t).iter().map(|rule| rule["trigger"]["url-filter"].as_str().unwrap().to_owned()).collect::<Vec<_>>().join(" ");
        let (wide, other) = (filters(0), filters(1));
        for taken in ["ads\\.example[", "banner", "com/track", "ok\\.js"] {
            assert!(wide.contains(taken) && !other.contains(taken), "{taken}: {wide} / {other}");
        }
        // The two blocks no exception reaches: wherever there is room.
        for rest in ["plain", "other"] {
            assert!(wide.contains(rest) != other.contains(rest), "{rest}: {wide} / {other}");
        }
        assert!(actions(&plan, 1).iter().all(|action| action == "block"));
        // A list whose blocks moved is still counted where they went.
        let admitted = |t: usize| plan.compile_target(t, &[]).admitted.values().sum::<u64>();
        assert_eq!(admitted(0) + admitted(1), 6);
    }

    fn packing_request(affinity: usize, ordinary: usize, bytes: usize, limit: usize) -> PlanRequest {
        let fixed: String = (0..affinity).map(|i| format!("||fixed{i}.example^\n")).collect();
        let moving: String = (0..ordinary).map(|i| format!("||host{i}.example/download/{}^$document\n", "a".repeat(200))).collect();
        serde_json::from_value(json!({
            "safari": [18, 0], "limits": {"rules": limit, "bytes": bytes},
            "lists": [
                {"id": "fixed", "text": format!("!#safari_cb_affinity(security)\n{fixed}")},
                {"id": "moving", "text": moving},
                {"id": "exceptions", "text": "@@||host1.example/download/$document\n@@/download/*allowed$document\n||host1.example/download/$document,badfilter"}
            ],
            "targets": (0..5).map(|t| json!({"slot": t + 1, "lists": [
                {"list": 0, "shard": [t, 5]}, {"list": 1, "shard": [t, 5]}, {"list": 2}
            ]})).collect::<Vec<_>>()
        })).unwrap()
    }

    fn union(plan: &Plan) -> HashSet<String> {
        (0..plan.target_count()).flat_map(|t| rules(plan, t)).map(|r| r.to_string()).collect()
    }

    #[test]
    fn measured_bytes_repack_and_preserve_union_and_exceptions() {
        let mut request = packing_request(0, 300, 75_000, 150_000);
        request.lists[1].scope.exclude.push("bypass.example".into());
        let mut reference = request.clone();
        reference.limits.rules = 0;
        let reference = Plan::new(reference);
        let mut packed = Plan::new(request);
        packed.check_capacity().unwrap();
        let actual = union(&packed);
        assert!(actual.iter().any(|rule| rule.contains("ignore-previous-rules")));
        assert_eq!(actual, union(&reference));
        assert!((0..5).all(|t| packed.check_output(&packed.compile_target(t, &[]).output).is_ok()));
        // Recreate the estimator's allocation to show the failure this protects.
        packed.wide = packed.wide();
        packed.duplicates = packed.duplicate_rules();
        assert!(packed.sizes().iter().any(|s| !s.within(&packed.limits)));
    }

    #[test]
    fn fixed_affinity_occupancy_reduces_shared_capacity() {
        let mut request = packing_request(100, 400, 1_000_000, 150);
        request.lists[1].text = (0..400).map(|i| format!("||moving{i}.example^\n")).collect();
        let mut reference = request.clone();
        reference.limits.rules = 0;
        let reference = Plan::new(reference);
        let mut packed = Plan::new(request);
        packed.check_capacity().unwrap();
        assert_eq!(union(&packed), union(&reference));
        for t in 0..5 {
            let output = packed.compile_target(t, &[]);
            packed.check_output(&output.output).unwrap();
            assert_eq!(rules(&packed, t).iter().filter(|r| r.to_string().contains("fixed")).count(), if t == 2 {100} else {0});
        }
        packed.wide = packed.wide();
        packed.duplicates = packed.duplicate_rules();
        assert!(packed.sizes()[2].rules > 150.0);
    }

    #[test]
    fn affinity_outside_shared_pool_and_impossible_selections() {
        // Ordinary rules initially occupy slot 1, with fixed security in slot 3.
        let packed = Plan::new(packing_request(100, 10, 1_000_000, 150));
        packed.check_capacity().unwrap();
        assert_eq!(rules(&packed, 2).iter().filter(|r| r.to_string().contains("fixed")).count(), 100);
        // The retry is finite and reports failure, retaining every fixed rule.
        let impossible = Plan::new(packing_request(151, 10, 1_000_000, 150));
        assert!(impossible.check_capacity().is_err());
        assert!(impossible.compile_target(2, &[]).output.webkit.rules() >= 151);
        let impossible = Plan::new(packing_request(0, 400, 1_000_000, 100));
        assert!(impossible.check_capacity().is_err());
        let impossible = Plan::new(packing_request(0, 400, 100, 150));
        assert!(impossible.check_capacity().is_err());
    }

    /// Each blocker with a block keeps the exceptions not anchored at a host,
    /// so the blocks go to the fewest blockers that have room for them.
    #[test]
    fn blocks_go_to_the_fewest_blockers_with_room() {
        let text: String = (0..300).map(|i| format!("||host{i}.example^\n")).collect::<String>() + "@@/allowed/*/ok.js\n/wide/\n";
        let lists = json!([{ "id":"list", "text":text }]);
        let targets = json!((0..5).map(|t| json!({"slot": t + 1, "lists": [{"list": 0, "shard": [t, 5]}]})).collect::<Vec<_>>());
        let held = |plan: &Plan| -> Vec<usize> {
            (0..5).map(|t| actions(plan, t).iter().filter(|action| *action == "block").count()).collect()
        };
        // All of them fit one blocker, the only one with the exception then.
        // `/wide/` is a block for frames and one for the other loads.
        let one = plan(lists.clone(), targets.clone(), json!({}));
        assert_eq!(held(&one), [302, 0, 0, 0, 0]);
        assert!((1..5).all(|t| actions(&one, t).is_empty()));
        // Room for 170 rules each: two blockers, as full as each other.
        let two = plan_within(243, lists.clone(), targets.clone());
        let counts = held(&two);
        assert_eq!(counts.iter().sum::<usize>(), 302);
        assert!(counts[..2].iter().all(|c| (130..170).contains(c)) && counts[2..] == [0, 0, 0], "{counts:?}");
        // The block not anchored at a host is in the wide blocker alone.
        assert!(serde_json::to_string(&rules(&two, 0)).unwrap().contains("wide"));
        assert!(!serde_json::to_string(&rules(&two, 1)).unwrap().contains("wide"));
        // Too little room anywhere: every blocker takes its part.
        let all = plan_within(60, lists, targets);
        assert!(held(&all).iter().all(|&c| c > 30), "{:?}", held(&all));
    }

    /// What a URL costs in Safari follows the automata of each blocker
    /// (`regex::automaton_prefix`), and before the wide blocker every blocker
    /// held one per wildcard exception of the plan. Three lists of the usual
    /// shapes in three blockers: each wildcard filter is in one blocker.
    #[test]
    fn a_wildcard_filter_is_an_automaton_in_one_blocker() {
        let lines = |make: &dyn Fn(usize) -> String| (0..40).map(make).collect::<String>();
        let ads = lines(&|i| format!("||ads{i}.example^\n||cdn{i}.example/ad/*/banner.\n/ads{i}/*/pixel.\n@@||ads{i}.example/ok/*.js$domain=news{i}.example\n"));
        let privacy = lines(&|i| format!("||track{i}.example^\n||ads{i}.example/t/*.gif\n@@||track{i}.example/sdk/*/core.js\n@@||cdn{i}.example/ad/*/banner.png\n"));
        let unbreak = lines(&|i| format!("||log{i}.example^$third-party\n||log{i}.example/v*/beacon\n")) + "@@/player/*/ads.js$domain=video.example\n";
        let plan = plan(
            json!([{"id":"ads", "text":ads}, {"id":"privacy", "text":privacy}, {"id":"unbreak", "text":unbreak}]),
            json!([{"slot":1,"lists":[{"list":0}]}, {"slot":2,"lists":[{"list":1}]}, {"slot":3,"lists":[{"list":2}]}]),
            json!({}),
        );
        let shared = ["^[a-z]+://([a-z0-9._-]+\\.)?", ".*", ""];
        let automata = |t| -> FxHashSet<String> {
            let rules = rules(&plan, t);
            let prefixes = rules.iter().map(|r| crate::compile::regex::automaton_prefix(r["trigger"]["url-filter"].as_str().unwrap()));
            prefixes.filter(|p| !shared.contains(&p.as_str())).collect()
        };
        let per_blocker: Vec<FxHashSet<String>> = (0..3).map(automata).collect();
        let all: FxHashSet<&String> = per_blocker.iter().flatten().collect();
        // 40 each of `cdn/ad/*` (a block and its exception), `/ads/*`,
        // `ads/ok/*`, `track/sdk/*` and `log/v*`, and the one exception not
        // anchored at a host. The bare `||ads1.example^` covers `ads1/t/*`.
        assert_eq!(all.len(), 201);
        let counts: Vec<usize> = per_blocker.iter().map(FxHashSet::len).collect();
        // The first blocker is the wide one, and with room for every block it
        // holds them all, so no exception has a copy.
        assert_eq!(counts, [201, 0, 0]);
    }

    /// Text given to every blocker compiles each of its blocks in the one
    /// blocker that holds it; its exceptions stay in each.
    #[test]
    fn text_for_every_blocker_keeps_wide_blocks_in_one() {
        let plan = plan(
            json!([{ "id":"left", "text":"||left.example^" }, { "id":"right", "text":"||right.example^" }]),
            json!([{"slot":1,"lists":[{"list":0}]},{"slot":2,"lists":[{"list":1}]}]),
            json!({}),
        );
        let text = "/pagead.js$script\n||extra.example^\n@@||right.example/ok.js";
        let compiled = |t, every_blocker| {
            let extra = Extra { text: text.into(), trusted: true, every_blocker };
            plan.compile_target(t, &[extra]).output.webkit.into_string()
        };
        assert!(compiled(0, true).contains("pagead") && compiled(1, false).contains("pagead"));
        // The other blocker has no block left for the exception to lift.
        let other = compiled(1, true);
        assert!(!other.contains("pagead") && !other.contains("extra") && !other.contains("ok"), "{other}");
    }

    /// Without room in the wide blocker, every blocker keeps its own lists.
    #[test]
    fn no_wide_blocker_past_the_limits() {
        let mut request: PlanRequest = serde_json::from_value(json!({
            "safari": [18, 0],
            "lists": [{ "id":"left", "text":"||plain.example^" }, { "id":"right", "text":"/banner." }],
            "targets": [{"slot":1,"lists":[{"list":0}]},{"slot":2,"lists":[{"list":1}]}],
        }))
        .unwrap();
        request.limits.rules = 1;
        let plan = Plan::new(request.clone());
        assert!(serde_json::to_string(&rules(&plan, 0)).unwrap().contains("plain"));
        assert!(serde_json::to_string(&rules(&plan, 1)).unwrap().contains("banner"));
        // A zero limit marks a blocker built outside the plan, even when no
        // block would go to the wide blocker.
        request.lists[1].text = "||other.example^".into();
        request.limits.rules = 0;
        let plan = Plan::new(request);
        assert!(serde_json::to_string(&rules(&plan, 0)).unwrap().contains("plain"));
        assert!(serde_json::to_string(&rules(&plan, 1)).unwrap().contains("other"));
    }

    #[test]
    fn shards_share_exceptions_and_partition_blocks() {
        let text = (0..50)
            .map(|index| format!("||host{index}.example^"))
            .collect::<Vec<_>>()
            .join("\n")
            + "\n@@/allowed/";
        let plan = plan_within(
            40,
            json!([{ "id":"list", "text":text }]),
            json!([
                {"slot":1,"lists":[{"list":0,"shard":[0,2]}]}, {"slot":2,"lists":[{"list":0,"shard":[1,2]}]}
            ]),
        );
        let left = rules(&plan, 0);
        let right = rules(&plan, 1);
        for part in [&left, &right] {
            assert!(part
                .iter()
                .any(|rule| rule["action"]["type"] == "ignore-previous-rules"));
        }
        let blocks = |rules: &[Value]| {
            rules
                .iter()
                .filter(|rule| rule["action"]["type"] == "block")
                .map(|rule| rule["trigger"]["url-filter"].to_string())
                .collect::<HashSet<_>>()
        };
        let (left, right) = (blocks(&left), blocks(&right));
        assert!(left.is_disjoint(&right));
        assert_eq!(left.len() + right.len(), 50);
    }

    /// A page exception's pattern names the page, not the requests it lifts,
    /// so it reaches every blocker whatever their blocks' hosts.
    #[test]
    fn replicates_page_exceptions_into_every_blocker() {
        let plan = plan(
            json!([
                {"id":"blocks", "text":"/ads.js\n##.ad"},
                {"id":"exceptions", "text":"@@||site.com^$document\n@@||page.com^$elemhide"}
            ]),
            json!([{"slot":1,"lists":[{"list":0}]},{"slot":2,"lists":[{"list":1}]}]),
            json!({}),
        );
        let left = crate::webkit::to_json(&plan.compile_target(0, &[]).output.webkit);
        assert!(left.contains("site\\\\.com[") && left.contains("page\\\\.com["), "{left}");
    }

    #[test]
    fn replicates_matching_network_exceptions_only() {
        let plan = plan(
            json!([
                {"id":"blocks", "text":"||example.com^\n||prefix.test/path"},
                {"id":"exceptions", "text":"@@||sub.example.com^\n@@||prefix.test/path/more^\n@@||unrelated.test^"}
            ]),
            json!([{"slot":1,"lists":[{"list":0}]},{"slot":2,"lists":[{"list":1}]}]),
            json!({}),
        );
        let left = crate::webkit::to_json(&plan.compile_target(0, &[]).output.webkit);
        assert!(left.contains("sub") && left.contains("example"), "{left}");
        assert!(left.contains("more"), "{left}");
        assert!(!left.contains("unrelated"));
        assert!(rules(&plan, 1)
            .iter()
            .all(|rule| rule["action"]["type"] == "ignore-previous-rules"));
    }

    /// A host exception lifts a generic block of another blocker that names
    /// no host (EasyList's `/adserver.` and uBO Quick Fixes' exception).
    #[test]
    fn replicates_host_exceptions_over_generic_blocks() {
        let plan = plan(
            json!([
                {"id":"easylist", "text":"/adserver.$~stylesheet,~xmlhttprequest,domain=~konograma.com"},
                {"id":"quick-fixes", "text":"@@||kupuvamsamo.online/adserver.js$domain=seirsanduk.com"}
            ]),
            json!([{"slot":1,"lists":[{"list":0}]},{"slot":2,"lists":[{"list":1}]}]),
            json!({}),
        );
        assert!(rules(&plan, 0).iter().any(|r| r["action"]["type"] == "ignore-previous-rules"
            && r["trigger"]["url-filter"].as_str().unwrap().contains("kupuvamsamo")));
    }

    /// The rules of each blocker of `plan` compiled with `extras`, in WebKit's order.
    fn compiled_blockers(plan: &Plan, extras: &[Extra]) -> Vec<Vec<Value>> {
        (0..plan.target_count())
            .map(|t| serde_json::from_str(&crate::webkit::to_json(&plan.compile_target(t, extras).output.webkit)).unwrap())
            .collect()
    }

    fn host_of(url: &str) -> &str {
        url.split("://").nth(1).unwrap().split(['/', ':', '?']).next().unwrap()
    }

    /// Whether an if-domain entry names `host`: `*host` also matches its subdomains.
    fn names(domain: &str, host: &str) -> bool {
        match domain.strip_prefix('*') {
            Some(base) => host == base || host.ends_with(&format!(".{base}")),
            None => host == domain,
        }
    }

    /// Whether a WebKit trigger matches a load of `url` on the page `top`.
    fn list_of<'a>(trigger: &'a Value, key: &str) -> Option<Vec<&'a str>> {
        trigger[key].as_array().map(|items| items.iter().map(|v| v.as_str().unwrap()).collect())
    }

    /// A compiled pattern, built once per pattern: the differential test
    /// evaluates the same few hundred thousand triggers.
    fn regex(pattern: &str, case_insensitive: bool) -> ::regex::Regex {
        thread_local! {
            static CACHE: std::cell::RefCell<std::collections::HashMap<(String, bool), ::regex::Regex>> = Default::default();
        }
        CACHE.with(|cache| {
            cache
                .borrow_mut()
                .entry((pattern.to_owned(), case_insensitive))
                .or_insert_with(|| ::regex::RegexBuilder::new(pattern).case_insensitive(case_insensitive).build().unwrap())
                .clone()
        })
    }

    fn matches(trigger: &Value, url: &str, top: &str, resource: &str, child_frame: bool) -> bool {
        let (host, top_host) = (host_of(url), host_of(top));
        let site = |h: &str| crate::registrable_domain(h).unwrap_or(h).to_owned();
        let load = || if site(host) == site(top_host) { "first-party" } else { "third-party" };
        let context = if child_frame { "child-frame" } else { "top-frame" };
        let filter = trigger["url-filter"].as_str().unwrap();
        let case_sensitive = trigger["url-filter-is-case-sensitive"] == true;
        let page_matches = |u: &str| regex(u, false).is_match(top);
        regex(filter, !case_sensitive).is_match(url)
            && list_of(trigger, "resource-type").is_none_or(|t| t.contains(&resource))
            && list_of(trigger, "load-type").is_none_or(|t| t.contains(&load()))
            && list_of(trigger, "load-context").is_none_or(|c| c.contains(&context))
            && list_of(trigger, "if-domain").is_none_or(|d| d.iter().any(|d| names(d, top_host)))
            && list_of(trigger, "unless-domain").is_none_or(|d| !d.iter().any(|d| names(d, top_host)))
            && list_of(trigger, "if-top-url").is_none_or(|u| u.iter().any(|u| page_matches(u)))
            && list_of(trigger, "unless-top-url").is_none_or(|u| !u.iter().any(|u| page_matches(u)))
    }

    /// What the blockers do to one load. Safari applies each blocker's rules
    /// in order: `block` blocks, `ignore-previous-rules` cancels what its
    /// blocker did before it, and `css-display-none` hides. A load is blocked
    /// when some blocker ends blocked; `hidden` unions the hides.
    #[derive(Debug, Default, PartialEq)]
    struct Verdict {
        blocked: bool,
        hidden: std::collections::BTreeSet<String>,
    }

    fn judge(blockers: &[Vec<Value>], url: &str, top: &str, resource: &str, child_frame: bool) -> Verdict {
        let mut out = Verdict::default();
        for rules in blockers {
            let (mut blocked, mut hidden) = (false, std::collections::BTreeSet::new());
            for rule in rules.iter().filter(|rule| matches(&rule["trigger"], url, top, resource, child_frame)) {
                match rule["action"]["type"].as_str().unwrap() {
                    "block" => blocked = true,
                    "ignore-previous-rules" => {
                        blocked = false;
                        hidden.clear();
                    }
                    "css-display-none" => {
                        hidden.insert(rule["action"]["selector"].as_str().unwrap().to_owned());
                    }
                    other => panic!("unexpected action {other}"),
                }
            }
            out.blocked |= blocked;
            out.hidden.extend(hidden);
        }
        out
    }

    /// `judge` for the blockers of `plan`, with no extra text.
    fn verdict(plan: &Plan, url: &str, top: &str, resource: &str, child_frame: bool) -> Verdict {
        judge(&compiled_blockers(plan, &[]), url, top, resource, child_frame)
    }

    fn request_with(lists: Value, targets: Value, rules: usize) -> PlanRequest {
        serde_json::from_value(json!({
            "safari": [26, 0], "lists": lists, "targets": targets, "limits": { "rules": rules }
        }))
        .unwrap()
    }

    /// The review's two lists: `/allowme/` blocks, and an exception in
    /// `privacy` lifts `allow.js`. `rules` is the blocker limit.
    fn affinity_request(rules: usize, targets: Value) -> PlanRequest {
        serde_json::from_value(json!({
            "safari": [26, 0],
            "lists": [
                { "id": "block", "text": "/allowme/" },
                { "id": "except", "text": "!#safari_cb_affinity(privacy)\n@@/allowme/allow" }
            ],
            "targets": targets,
            "limits": { "rules": rules, "bytes": 10000 }
        }))
        .unwrap()
    }

    const PAGE: &str = "https://site.example/";
    const ALLOW: &str = "https://x.example/allowme/allow.js";
    const OTHER: &str = "https://x.example/allowme/other.js";

    #[test]
    fn affinity_exception_reaches_the_blocker_holding_its_block() {
        let fixture = json!([
            { "slot": 1, "lists": [{ "list": 1, "shard": [0, 2] }] },
            { "slot": 2, "lists": [{ "list": 0 }, { "list": 1, "shard": [1, 2] }] }
        ]);
        let split = json!([
            { "slot": 1, "lists": [{ "list": 0 }, { "list": 1, "shard": [0, 2] }] },
            { "slot": 2, "lists": [{ "list": 1, "shard": [1, 2] }] }
        ]);
        let whole = json!([
            { "slot": 1, "lists": [{ "list": 0 }] },
            { "slot": 2, "lists": [{ "list": 1 }] }
        ]);
        for (rules, targets) in [(999, fixture), (0, split), (0, whole)] {
            let plan = Plan::new(affinity_request(rules, targets));
            assert!(!verdict(&plan, ALLOW, PAGE, "script", false).blocked, "limit {rules}: allow.js");
            assert!(verdict(&plan, OTHER, PAGE, "script", false).blocked, "limit {rules}: other.js");
        }
    }

    #[test]
    fn packed_plan_matches_reference_verdicts() {
        // The exceptions are privacy-only, yet every blocker is assigned them.
        let mut packing = packing_request(0, 300, 75_000, 150);
        let mut oracle = packing.clone();
        oracle.limits.rules = 0;
        oracle.targets = vec![serde_json::from_value(json!({"slot": 1, "lists": [{"list": 0}, {"list": 1}, {"list": 2}]})).unwrap()];
        // The exceptions are privacy-only, yet every blocker is assigned them.
        packing.lists[2].text = format!("!#safari_cb_affinity(privacy)\n{}", packing.lists[2].text);
        let mut reference = packing.clone();
        reference.limits.rules = 0;
        let (packed, reference, oracle) = (Plan::new(packing), Plan::new(reference), Plan::new(oracle));
        packed.check_capacity().unwrap();
        // A top-level document is its own page, which the page exceptions name.
        let download = format!("https://host{{}}.example/download/{}/file", "a".repeat(200));
        for i in 0..3 {
            let url = download.replace("{}", &i.to_string());
            let got = verdict(&packed, &url, &url, "document", false);
            assert_eq!(got, verdict(&reference, &url, &url, "document", false), "host{i} against limits 0");
            assert_eq!(got, verdict(&oracle, &url, &url, "document", false), "host{i} against one blocker");
        }
        assert!(!verdict(&oracle, &download.replace("{}", "1"), &download.replace("{}", "1"), "document", false).blocked);
        assert!(verdict(&oracle, &download.replace("{}", "0"), &download.replace("{}", "0"), "document", false).blocked);
    }

    /// xorshift64 with a seed, so a failing case can be rerun from its number.
    struct Xorshift(u64);

    impl Xorshift {
        fn below(&mut self, n: usize) -> usize {
            self.0 ^= self.0 << 13;
            self.0 ^= self.0 >> 7;
            self.0 ^= self.0 << 17;
            (self.0 % n as u64) as usize
        }
    }

    /// Two to five lists of host, path, exception and badfilter rules. Runs of
    /// lines get a random affinity, and the second text is the same lists with
    /// the affinity lines stripped: the oracle's text.
    fn random_lists(rng: &mut Xorshift) -> (Vec<String>, Vec<String>) {
        const NAMES: [&str; 6] = ["general", "privacy", "social", "other", "custom", "security"];
        let (mut with, mut without) = (Vec::new(), Vec::new());
        for _ in 0..2 + rng.below(4) {
            let (mut text, mut plain) = (String::new(), String::new());
            for _ in 0..5 + rng.below(36) {
                if rng.below(3) == 0 {
                    // Affinity 0 is none: the directive with no types.
                    let mask = if rng.below(3) == 0 { 0 } else { 1 + rng.below(63) };
                    let types: Vec<&str> = (0..6).filter(|b| mask >> b & 1 == 1).map(|b| NAMES[b]).collect();
                    text += &if types.is_empty() {
                        "!#safari_cb_affinity\n".to_string()
                    } else {
                        format!("!#safari_cb_affinity({})\n", types.join(","))
                    };
                }
                let i = rng.below(6);
                let line = match rng.below(5) {
                    0 => format!("||h{i}.example^"),
                    1 => format!("/p{i}/"),
                    2 => format!("@@||h{i}.example^"),
                    3 => format!("@@/p{i}/ok"),
                    _ => format!("||h{i}.example^$badfilter"),
                };
                text += &format!("{line}\n");
                plain += &format!("{line}\n");
            }
            with.push(text);
            without.push(plain);
        }
        (with, without)
    }

    /// Five blockers (slots 1 to 5). Each list is whole in a random set of them,
    /// or sharded over distinct ones, so every list reaches some blocker.
    fn random_targets(rng: &mut Xorshift, lists: usize) -> Value {
        let mut held: Vec<Vec<Value>> = vec![Vec::new(); 5];
        for list in 0..lists {
            if rng.below(2) == 0 {
                let mut any = false;
                for target in &mut held {
                    if rng.below(2) == 0 {
                        target.push(json!({ "list": list }));
                        any = true;
                    }
                }
                if !any {
                    held[rng.below(5)].push(json!({ "list": list }));
                }
            } else {
                let mut order: Vec<usize> = (0..5).collect();
                for i in (1..5).rev() {
                    order.swap(i, rng.below(i + 1));
                }
                let count = 2 + rng.below(2);
                for shard in 0..count {
                    held[order[shard]].push(json!({ "list": list, "shard": [shard, count] }));
                }
            }
        }
        Value::Array(held.into_iter().enumerate().map(|(t, lists)| json!({ "slot": t + 1, "lists": lists })).collect())
    }

    /// Affinity plans against their oracle, one blocker with the same lists
    /// and no affinity. Wherever the plan's capacity check passes, every load
    /// gets the oracle's verdict.
    #[test]
    fn affinity_plans_match_the_one_blocker_oracle() {
        let urls: Vec<String> = (0..6)
            .map(|i| format!("https://h{i}.example/a.js"))
            .chain((0..6).flat_map(|i| ["a", "ok"].map(|file| format!("https://cdn.example/p{i}/{file}.js"))))
            .collect();
        let pages = ["https://site.example/", "https://h0.example/"];
        let (mut checked, mut blocked) = (0, 0);
        for seed in 1..=300u64 {
            let mut rng = Xorshift(seed.wrapping_mul(0x9E37_79B9_7F4A_7C15) | 1);
            let (with, without) = random_lists(&mut rng);
            let targets = random_targets(&mut rng, with.len());
            let lists = |texts: &[String]| -> Value {
                Value::Array(texts.iter().enumerate().map(|(i, text)| json!({ "id": format!("list{i}"), "text": text })).collect())
            };
            let all: Value = Value::Array((0..with.len()).map(|i| json!({ "list": i })).collect());
            let oracle = Plan::new(request_with(lists(&without), json!([{ "slot": 1, "lists": all }]), 0));
            let oracle_blockers = compiled_blockers(&oracle, &[]);
            let oracle_rules = oracle_blockers[0].len();
            let zero = Plan::new(request_with(lists(&with), targets.clone(), 0));
            let limited = Plan::new(request_with(lists(&with), targets, (oracle_rules * 2 / 5).max(1)));
            for plan in [&zero, &limited] {
                if plan.check_capacity().is_err() {
                    continue;
                }
                checked += 1;
                let plan_blockers = compiled_blockers(plan, &[]);
                for url in &urls {
                    for page in pages {
                        for (resource, child) in [("script", false), ("document", true)] {
                            let got = judge(&plan_blockers, url, page, resource, child);
                            let want = judge(&oracle_blockers, url, page, resource, child);
                            blocked += want.blocked as usize;
                            assert_eq!(got, want, "seed {seed}: {url} on {page} as {resource} (child frame {child})\n{with:?}");
                        }
                    }
                }
            }
        }
        assert!(checked >= 300 && blocked > 0, "{checked} plans checked, {blocked} blocked loads");
    }

    /// Mixed hostname and entity exclusions on a block and its exception
    /// reach the blocks of both lists: every block is kept.
    #[test]
    fn mixed_exclusions_keep_every_block() {
        let excluded = json!({ "exclude": ["www.a.com", "google.*", "b.co.uk"] });
        let request: PlanRequest = serde_json::from_value(json!({
            "safari": [26, 0],
            "lists": [
                { "id": "seg", "text": "/one/\n/two/\n/three/\n/six/", "scope": excluded },
                { "id": "rest", "text": "/four/\n/five/\n@@/four/ok", "scope": excluded }
            ],
            "targets": [{ "slot": 1, "lists": [{ "list": 0 }, { "list": 1 }] }]
        }))
        .unwrap();
        let mut reference = request.clone();
        reference.limits.rules = 0;
        assert_eq!(union(&Plan::new(request.clone())), union(&Plan::new(reference)));
        let plan = Plan::new(request);
        let news = "https://news.example/";
        let excluded_pages = ["https://www.a.com/", "https://www.google.de/", "https://b.co.uk/"];
        for path in ["one", "two", "three", "four", "five", "six"] {
            let url = format!("https://cdn.example/{path}/a.js");
            assert!(verdict(&plan, &url, news, "script", false).blocked, "{path} on news");
            for page in excluded_pages {
                assert!(!verdict(&plan, &url, page, "script", false).blocked, "{path} on {page}");
            }
        }
        for page in [news, excluded_pages[0], excluded_pages[1], excluded_pages[2]] {
            assert!(!verdict(&plan, "https://cdn.example/four/ok.js", page, "script", false).blocked, "four/ok on {page}");
        }
    }

    /// An exception with mixed exclusions lifts its block everywhere except
    /// on the sites it excludes, hostnames and entities alike.
    #[test]
    fn mixed_exclusion_exception_lifts_only_off_its_sites() {
        let exception = plan(
            json!([{ "id": "list", "text": "||t.example/ok.js$script\n@@||t.example/ok.js$script,domain=~a.example|~google.*" }]),
            json!([{ "slot": 1, "lists": [{ "list": 0 }] }]),
            json!({}),
        );
        let blocked = |page: &str| verdict(&exception, "https://t.example/ok.js", page, "script", false).blocked;
        assert!(!blocked("https://news.example/"));
        assert!(blocked("https://a.example/"));
        assert!(blocked("https://www.google.de/"));
        // A block with both kinds of exclusion carries the merged condition, and
        // an unconditioned exception still lifts it everywhere.
        let merged = plan(
            json!([{ "id": "list", "text": "||t.example/ok.js$script,domain=~a.example|~google.*\n@@||t.example/ok.js$script" }]),
            json!([{ "slot": 1, "lists": [{ "list": 0 }] }]),
            json!({}),
        );
        for page in ["https://news.example/", "https://a.example/", "https://www.google.de/"] {
            assert!(!verdict(&merged, "https://t.example/ok.js", page, "script", false).blocked, "{page}");
        }
    }

    /// A segment's ignore rule cancels the hides before it. The hide of a list
    /// that does not exclude the site must survive, and so must the block of
    /// the other list.
    fn check_unrelated_hides(plan: &Plan, extras: &[Extra], hide: &str) {
        let blockers = compiled_blockers(plan, extras);
        let (a, news) = ("https://www.a.com/", "https://news.example/");
        let hidden = |page: &str| judge(&blockers, page, page, "document", false).hidden;
        assert!(hidden(a).contains(hide) && !hidden(a).contains(".own"), "{:?}", hidden(a));
        assert!(hidden(news).contains(hide) && hidden(news).contains(".own"), "{:?}", hidden(news));
        for path in ["one", "two", "three"] {
            let url = format!("https://cdn.example/{path}/a.js");
            let blocked = |page: &str| judge(&blockers, &url, page, "script", false).blocked;
            assert_eq!(blocked(a), path == "three", "{path} on {a}");
            assert!(blocked(news), "{path} on {news}");
        }
    }

    fn excluded_segment_plan(plainlist: &str) -> Plan {
        Plan::new(
            serde_json::from_value(json!({
                "safari": [26, 0],
                "lists": [
                    { "id": "scoped", "text": "/one/\n/two/\n##.own", "scope": { "exclude": ["www.a.com"] } },
                    { "id": "plainlist", "text": plainlist }
                ],
                "targets": [{ "slot": 1, "lists": [{ "list": 0 }, { "list": 1 }] }]
            }))
            .unwrap(),
        )
    }

    #[test]
    fn segment_ignore_spares_unrelated_hides() {
        check_unrelated_hides(&excluded_segment_plan("##.unrelated\n/three/"), &[], ".unrelated");
    }

    #[test]
    fn segment_ignore_spares_extra_hides() {
        let extra = Extra { text: "##.zapped".into(), trusted: true, every_blocker: false };
        check_unrelated_hides(&excluded_segment_plan("/three/"), &[extra], ".zapped");
    }

    #[test]
    fn webkit_accepts_combined_fixture() {
        let executable = std::path::Path::new("/tmp/research/bench/wk");
        if !executable.exists() {
            return;
        }
        let plan = plan(
            json!([{ "id":"list", "text":"||tracker.net^\nexample.com##.advert\n@@||allow.net^", "scope":{"exclude":["example.com", "shop.*"]}}]),
            json!([{"slot":1,"lists":[{"list":0}]}]),
            json!({}),
        );
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../target/apply-webkit-fixture.json");
        std::fs::write(
            &path,
            crate::webkit::to_json(&plan.compile_target(0, &[]).output.webkit),
        )
        .unwrap();
        let output = std::process::Command::new(executable)
            .arg(&path)
            .output()
            .unwrap();
        assert!(
            output.status.success() && String::from_utf8_lossy(&output.stdout).contains("ok"),
            "{} {}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }

    /// The real lists in `WBE_BENCH_LISTS` (default /tmp/wbprof/container),
    /// spread over five blockers as lists % 5. `"scoped"` adds site scopes and
    /// a cosmetic scope; `"sharded"` splits every fourth list over two
    /// blockers, so shards and cross-blocker duplicates are covered too.
    fn real_lists_plan(config: &str, change: Option<&str>) -> Plan {
        let scoped = config == "scoped";
        let sharded = config == "sharded";
        let dir = std::env::var("WBE_BENCH_LISTS").unwrap_or("/tmp/wbprof/container".into());
        let mut paths: Vec<_> = std::fs::read_dir(&dir)
            .unwrap()
            .map(|entry| entry.unwrap().path())
            .filter(|path| {
                let name = path.file_name().unwrap().to_string_lossy();
                name.ends_with(".txt")
                    && !name.starts_with("diff-baseline-")
                    && !name.starts_with("temp_")
                    && !name.ends_with(".advanced.txt")
            })
            .collect();
        paths.sort();
        // Built directly, not through JSON, which would copy every list's text.
        let lists: Vec<ListSpec> = paths
            .iter()
            .enumerate()
            .map(|(index, path)| {
                let scope = if scoped && index % 3 == 0 {
                    SiteScope {
                        exclude: vec!["example.com".into(), "shop.*".into()],
                        only: None,
                    }
                } else if scoped && index % 5 == 4 {
                    SiteScope {
                        exclude: Vec::new(),
                        only: Some(vec!["news.example.com".into(), "example.*".into()]),
                    }
                } else {
                    SiteScope::default()
                };
                let name = path.file_name().unwrap().to_string_lossy().into_owned();
                // An apply after an edit: `change` names a list that gains a rule.
                let mut text = std::fs::read_to_string(path).unwrap();
                if change.is_some_and(|c| name.contains(c)) {
                    text.push_str("\n||round.example^\n");
                }
                ListSpec {
                    id: name,
                    text,
                    path: None,
                    trusted: false,
                    scope,
                }
            })
            .collect();
        let mut blockers: Vec<Vec<TargetList>> = vec![Vec::new(); 5];
        for index in 0..lists.len() {
            let primary = index % 5;
            if sharded && index % 4 == 0 {
                blockers[primary].push(TargetList { list: index, shard: Some((0, 2)) });
                blockers[(primary + 1) % 5].push(TargetList { list: index, shard: Some((1, 2)) });
            } else {
                blockers[primary].push(TargetList { list: index, shard: None });
            }
        }
        let targets: Vec<TargetSpec> = blockers
            .into_iter()
            .enumerate()
            .map(|(slot, lists)| TargetSpec { slot: slot as u8 + 1, lists })
            .collect();
        let cosmetics = CosmeticScope {
            sites: SiteScope {
                exclude: if scoped { vec!["news.example.com".into()] } else { Vec::new() },
                only: None,
            },
            generic: true,
        };
        Plan::new(PlanRequest {
            safari: (18, 0),
            lists,
            targets,
            cosmetics,
            limits: Limits::default(),
        })
    }

    /// Times an apply's phases: `Plan::new` (with the real lists read from
    /// `WBE_BENCH_LISTS`), then each blocker's fingerprint and compile.
    /// Run twice with WBE_BENCH_CHANGE to see an apply after one edit.
    #[test]
    #[ignore]
    fn benchmark_real_lists() {
        let start = std::time::Instant::now();
        let _first = real_lists_plan("plain", None);
        println!("Plan::new (first apply) {:?}", start.elapsed());
        // WBE_BENCH_CHANGE=<name fragment> makes the second apply see one list edited.
        let change = std::env::var("WBE_BENCH_CHANGE").ok();
        let start = std::time::Instant::now();
        let plan = real_lists_plan("plain", change.as_deref());
        println!("Plan::new (next apply, change {change:?}) {:?}", start.elapsed());
        // WBE_BENCH_TARGET=n compiles only that blocker, to attribute peak memory.
        let only: Option<usize> = std::env::var("WBE_BENCH_TARGET").ok().and_then(|v| v.parse().ok());
        for target in (0..5).filter(|t| only.is_none_or(|o| o == *t)) {
            let start = std::time::Instant::now();
            plan.fingerprint(target, &[]);
            let fingerprint = start.elapsed();
            let start = std::time::Instant::now();
            let output = plan.compile_target(target, &[]);
            println!(
                "target {target}: fingerprint {fingerprint:?}, compile {:?}, {} rules",
                start.elapsed(),
                output.output.webkit.rules()
            );
        }
    }

    /// Writes every output of every blocker for the real lists, so a
    /// refactor can be diffed byte for byte. Folder: `WBE_DUMP_DIR`.
    #[test]
    #[ignore]
    fn dump_real_list_outputs() {
        let dir = std::path::PathBuf::from(
            std::env::var("WBE_DUMP_DIR").unwrap_or("/tmp/wbe-mem-baseline".into()),
        );
        std::fs::create_dir_all(&dir).unwrap();
        let extra = Extra {
            text: "example.com##.wbe-extra\n||extra-check.example^\n@@||extra-check.example/ok^$image\nexample.com##+js(set, wbe, 1)\n".into(),
            trusted: false,
            every_blocker: false,
        };
        let cases = [
            ("plain", "plain", Vec::new()),
            ("plain-extra", "plain", vec![extra]),
            ("scoped", "scoped", Vec::new()),
            ("sharded", "sharded", Vec::new()),
        ];
        for (name, config, extras) in cases {
            let plan = real_lists_plan(config, None);
            let mut fingerprints = String::new();
            for target in 0..plan.target_count() {
                let output = plan.compile_target(target, &extras);
                assert_eq!(output.fingerprint, plan.fingerprint(target, &extras));
                fingerprints += &format!("t{target} {}\n", output.fingerprint);
                let base = dir.join(format!("{name}-t{target}"));
                let write = |suffix: &str, text: String| {
                    std::fs::write(format!("{}.{suffix}", base.display()), text).unwrap()
                };
                write("webkit.json", crate::webkit::to_json(&output.output.webkit));
                write(
                    "runtime.json",
                    serde_json::to_string(&output.output.runtime).unwrap(),
                );
                write("admitted.json", serde_json::to_string(&output.admitted).unwrap());
                write("stats.json", serde_json::to_string(&output.output.stats).unwrap());
            }
            std::fs::write(dir.join(format!("{name}-fingerprints.txt")), fingerprints).unwrap();
        }
    }
}

