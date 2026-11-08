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
use crate::parse::{cosmetic::with_domains, restate};
use crate::webkit::{SafariVersion, WebkitJson, WkAction, WkRule, WkTrigger};
use serde::{Deserialize, Serialize};
use std::collections::hash_map::DefaultHasher;
use rustc_hash::{FxHashMap, FxHashSet};
use std::borrow::Cow;
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
    /// Keep each list's patterns in the cache for later plans, so a plan
    /// fingerprints its blockers without parsing their rules again. It costs
    /// memory for as long as the cache holds the list, so a phone leaves it off.
    #[serde(default)]
    pub retain: bool,
}

/// Extra text one blocker compiles after its lists (zapper rules, wBlock's
/// compatibility rules, redirect carve-outs).
#[derive(Debug, Clone, Deserialize)]
pub struct Extra {
    pub text: String,
    #[serde(default)]
    pub trusted: bool,
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
    /// An exception rule, which `shared` also covers with `$badfilter`.
    exception: bool,
    /// A network rule, so the network pass can skip the other kinds unparsed.
    network: bool,
    /// A network rule a blocker's `NetworkContext` holds, so its scan parses it.
    in_context: bool,
    /// `is_plain_block`, which the segment of #925 compiles unscoped.
    plain: bool,
    /// Affinity types of the enclosing `!#safari_cb_affinity` block.
    affinity: Option<u8>,
}

struct ParsedList {
    /// The records in line order, in the chunks they were parsed in.
    chunks: Vec<Vec<Parsed>>,
    /// The patterns of the records, per chunk, when the list keeps them.
    patterns: Option<Vec<PatternChunk>>,
    has_affinity: bool,
    /// A `!#` directive anywhere keeps the list out of #681 dedupe, as before.
    has_directive: bool,
    stats: Stats,
}

/// The patterns of one chunk's records: `text` holds them back to back, and
/// `spans` gives each record's (start, length) in it, length 0 for none.
#[derive(Default)]
struct PatternChunk {
    text: String,
    spans: Vec<(u32, u32)>,
}

impl ParsedList {
    fn records(&self) -> impl Iterator<Item = &Parsed> + '_ {
        self.chunks.iter().flatten()
    }

    /// Record `i` of `chunk`'s pattern, when the list keeps patterns: `Some(None)`
    /// for a record with none.
    fn stored_pattern(&self, chunk: usize, i: usize) -> Option<Option<&str>> {
        let kept = self.patterns.as_ref()?.get(chunk)?;
        let (start, len) = kept.spans[i];
        Some((len > 0).then(|| &kept.text[start as usize..(start + len) as usize]))
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
    retain: bool,
}

impl ParseKey {
    fn of(list: &ListSpec, text: u64, retain: bool) -> ParseKey {
        ParseKey {
            text,
            len: list.text.len(),
            trusted: list.trusted,
            scope: hash(&(&list.scope.exclude, &list.scope.only)),
            version: crate::OUTPUT_VERSION,
            retain,
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
        let parsed = Arc::new(parse(list, key.retain));
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
    /// List index -> rule identities a blocker other than this one owns (#681).
    duplicates: Vec<Vec<FxHashSet<u64>>>,
    /// Hash of each list's text, for `fingerprint`.
    text_hashes: Vec<u64>,
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
            .map(|(list, &text)| ParseKey::of(list, text, request.retain))
            .collect();
        let parsed = parallel_indices(request.lists.len(), |i| cache.parsed(keys[i], &request.lists[i]));
        cache.keep(&keys);
        let mut plan = Plan {
            opts,
            lists: request.lists,
            parsed,
            targets: request.targets,
            cosmetics: request.cosmetics,
            duplicates: Vec::new(),
            text_hashes,
        };
        plan.duplicates = plan.duplicate_rules();
        plan
    }

    /// The rule a record stands for, parsed again from its line exactly as
    /// `parse` did.
    fn rule(&self, list: usize, p: &Parsed) -> Rule {
        let spec = &self.lists[list];
        let line = spec.text[p.offset..].lines().next().unwrap_or_default();
        let mut rules = parse_list(line, list as u32, spec.trusted, &mut Stats::default());
        let mut rule = rules.swap_remove(p.index as usize);
        set_line(&mut rule, p.line);
        rule
    }

    pub fn target_count(&self) -> usize {
        self.targets.len()
    }

    fn assigned(&self, target: usize, list: usize) -> Option<&TargetList> {
        self.targets[target].lists.iter().find(|l| l.list == list)
    }

    /// Whether blocker `target` keeps the rule at `p` of `list`: its shard or
    /// affinity types, and no #681 duplicate of another blocker's.
    fn keeps(&self, target: usize, list: usize, p: &Parsed) -> bool {
        let types = slot_types(self.targets[target].slot);
        let assignment = self.assigned(target, list);
        let parsed = &self.parsed[list];
        let keep = match (parsed.has_affinity, p.affinity, assignment) {
            (true, Some(mask), _) => mask & types != 0,
            (_, _, Some(a)) => {
                p.shared || a.shard.map_or(true, |(i, n)| p.identity % n as u64 == i as u64)
            }
            _ => false,
        };
        keep && !self.duplicates[target][list].contains(&p.identity)
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
            for (t, target) in self.targets.iter().enumerate() {
                let Some(assignment) = target.lists.iter().find(|l| l.list == list) else {
                    continue;
                };
                for p in parsed.records().filter(|p| !p.shared) {
                    if let Some((i, n)) = assignment.shard {
                        if p.identity % n as u64 != i as u64 {
                            continue;
                        }
                    }
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
        let own = self.own_patterns(target);
        let replicated = self.replicated(target, own.iter().map(|pattern| pattern.as_ref()));
        (self.fingerprint_of(target, extras, &replicated), replicated)
    }

    /// The patterns `scan` keeps for `target`, from the patterns a list keeps
    /// when it has them and otherwise from its rules.
    fn own_patterns(&self, target: usize) -> Vec<Cow<'_, str>> {
        let units = self.record_units();
        parallel_indices(units.len(), |u| {
            let Unit { list, chunk, range } = &units[u];
            let (list, chunk) = (*list, *chunk);
            let parsed = &self.parsed[list];
            let mut out = Vec::new();
            for i in range.clone() {
                let p = &parsed.chunks[chunk][i];
                if !p.network || p.exception || !self.keeps(target, list, p) {
                    continue;
                }
                match parsed.stored_pattern(chunk, i) {
                    Some(pattern) => out.extend(pattern.map(Cow::Borrowed)),
                    None => {
                        let mut rules = Vec::new();
                        scoped(self.rule(list, p), &self.lists[list].scope, &mut rules);
                        for rule in &rules {
                            if let Rule::Network(r) = rule {
                                if !r.exception {
                                    out.extend(pattern_of(r).map(Cow::Owned));
                                }
                            }
                        }
                    }
                }
            }
            out
        })
        .into_iter()
        .flatten()
        .collect()
    }

    fn fingerprint_of(&self, target: usize, extras: &[Extra], replicated: &[Rule]) -> u64 {
        let mut h = DefaultHasher::new();
        crate::OUTPUT_VERSION.hash(&mut h);
        format!("{:?}{:?}", self.opts, self.cosmetics).hash(&mut h);
        self.targets[target].slot.hash(&mut h);
        self.segment_list(target).hash(&mut h);
        for (list, spec) in self.lists.iter().enumerate() {
            let assignment = self.assigned(target, list);
            if assignment.is_some() || self.parsed[list].has_affinity {
                (list, self.text_hashes[list], spec.trusted, &spec.id).hash(&mut h);
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
            (&extra.text, extra.trusted).hash(&mut h);
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
        let tail = Mutex::new(Some(tail));
        let mut output = compile_blocker(
            &ctx,
            units.len() + 1,
            |unit| match units.get(unit) {
                Some(unit) => self.network_unit(&ctx, target, unit, segment_list),
                None => tail.lock().expect("tail lock").take().expect("tail unit once"),
            },
            others,
            &self.opts,
            stats,
        );
        if let Some(list) = segment_list {
            // The blocker's context, so every `$badfilter` it holds applies.
            let segment = |_| {
                let plain = self.parsed[list].records().filter(|p| p.plain && self.keeps(target, list, p));
                plain.filter_map(|p| match self.rule(list, p) {
                    Rule::Network(r) => Some(*r),
                    _ => None,
                })
                .collect()
            };
            let front = compile_blocker(&ctx, 1, segment, Others::default(), &self.opts, Stats::default()).webkit;
            let ignores: Vec<WkRule> = self.lists[list]
                .scope
                .exclude
                .iter()
                .filter_map(|site| ignore_rule(site))
                .collect();
            output.webkit = WebkitJson::join([&front, &WebkitJson::from_rules(&ignores), &output.webkit]);
            output.stats.native_rules = output.webkit.rules() as u64;
        }
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
        self.targets[target]
            .lists
            .iter()
            .map(|a| a.list)
            .filter(|&l| {
                let scope = &self.lists[l].scope;
                !scope.exclude.is_empty()
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

    /// #836: network exceptions of lists this blocker does not compile, when
    /// they can cancel one of its blocks (Safari applies an exception only in
    /// its own blocker). `own` holds the patterns of the blocker's network
    /// rules (`own_patterns`). Matching errs toward copying, which is harmless.
    fn replicated<'a>(&self, target: usize, own: impl Iterator<Item = &'a str>) -> Vec<Rule> {
        let mut patterns = FxHashSet::default();
        let mut bare_hosts = FxHashSet::default();
        for pattern in own {
            bare_hosts.extend(bare_host(pattern));
            patterns.insert(pattern);
        }
        let mut sorted: Vec<&str> = patterns.iter().copied().collect();
        sorted.sort_unstable();
        let units: Vec<Unit> = self
            .record_units()
            .into_iter()
            .filter(|unit| self.assigned(target, unit.list).is_none())
            .collect();
        // Candidates pass the cancel check per record range, in parallel; the
        // `seen` check that makes each rule count once runs after, in order.
        let candidates = parallel_indices(units.len(), |u| {
            let Unit { list, chunk, range } = &units[u];
            let (list, chunk) = (*list, *chunk);
            let parsed = &self.parsed[list];
            let mut found: Vec<(u64, Rule)> = Vec::new();
            for i in range.clone() {
                let p = &parsed.chunks[chunk][i];
                if !p.shared {
                    continue;
                }
                if let Some(stored) = parsed.stored_pattern(chunk, i).filter(|_| p.network) {
                    // The list keeps patterns, so only a matching rule is parsed.
                    let matches = stored.is_none_or(|pattern| {
                        pattern_host(pattern).is_none() || cancels(pattern, &patterns, &bare_hosts, &sorted)
                    });
                    if matches {
                        found.push((p.identity, self.rule(list, p)));
                    }
                    continue;
                }
                let mut scoped_rules = Vec::new();
                scoped(self.rule(list, p), &self.lists[list].scope, &mut scoped_rules);
                for rule in scoped_rules {
                    match &rule {
                        Rule::Cosmetic(r) if r.exception => {
                            found.push((identity(&r.raw), rule));
                        }
                        Rule::Network(r) if r.exception || r.badfilter => {
                            let matches = pattern_of(r).is_none_or(|pattern| {
                                pattern_host(&pattern).is_none()
                                    || cancels(&pattern, &patterns, &bare_hosts, &sorted)
                            });
                            if matches {
                                found.push((identity(&r.raw), rule));
                            }
                        }
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
/// A list with an affinity block is parsed in one piece, because the block's
/// type carries from one line to the next.
const PARSE_CHUNK: usize = 1 << 20;

/// The records of `list`. Each rule is parsed again from its line when a
/// blocker needs it (`Plan::rule`), with the list's index, so the index is not
/// needed here. `retain` keeps the patterns too (see `PlanRequest::retain`).
fn parse(list: &ListSpec, retain: bool) -> ParsedList {
    parse_chunked(list, PARSE_CHUNK, retain)
}

/// `parse` with chunks of about `chunk_bytes`, parsed in parallel. The records,
/// line numbers, stats, and patterns are the same whatever the chunk size.
fn parse_chunked(list: &ListSpec, chunk_bytes: usize, retain: bool) -> ParsedList {
    let text = list.text.as_str();
    // A site scope changes the rules a list's patterns come from, so only
    // unscoped lists keep them.
    let patterns = retain && list.scope.is_empty();
    let spans = if text.contains(AFFINITY) {
        vec![(0..text.len(), 0)]
    } else {
        line_spans(text, chunk_bytes)
    };
    let parts = if spans.len() == 1 {
        vec![parse_lines(list, spans[0].0.clone(), spans[0].1, patterns)]
    } else {
        parallel_indices(spans.len(), |i| {
            parse_lines(list, spans[i].0.clone(), spans[i].1, patterns)
        })
    };
    let mut merged = ParsedList {
        chunks: Vec::with_capacity(parts.len()),
        patterns: patterns.then(Vec::new),
        has_affinity: false,
        has_directive: false,
        stats: Stats::default(),
    };
    for part in parts {
        merged.has_affinity |= part.has_affinity;
        merged.has_directive |= part.has_directive;
        merged.stats.merge(&part.stats);
        merged.chunks.extend(part.chunks);
        if let (Some(all), Some(kept)) = (&mut merged.patterns, part.patterns) {
            all.extend(kept);
        }
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
/// number `lines_before + 1`. With `patterns`, also their patterns.
fn parse_lines(list: &ListSpec, span: Range<usize>, lines_before: u32, patterns: bool) -> ParsedList {
    let text = &list.text[span];
    let mut stats = Stats::default();
    // Sized up front: growing it would leave the old buffers behind.
    let mut rules = Vec::with_capacity(text.lines().count());
    let mut kept = patterns.then(PatternChunk::default);
    let mut affinity: Option<u8> = None;
    let mut has_affinity = false;
    let mut has_directive = false;
    // Lines are parsed one at a time so affinity blocks can be tracked.
    for (n, line) in text.lines().enumerate() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix(AFFINITY) {
            has_affinity = true;
            affinity = rest
                .strip_prefix('(')
                .and_then(|r| r.strip_suffix(')'))
                .and_then(affinity_mask);
            continue;
        }
        if trimmed.starts_with("!#") {
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
                exception: matches!(rule, Rule::Network(r) if r.exception),
                network: matches!(rule, Rule::Network(_)),
                in_context: matches!(rule, Rule::Network(r) if NetworkContext::holds(r)),
                plain: is_plain_block(rule),
                affinity,
            });
            if let Some(kept) = kept.as_mut() {
                let pattern = match rule {
                    Rule::Network(r) => pattern_of(r),
                    _ => None,
                };
                let start = kept.text.len() as u32;
                let len = pattern.as_deref().map_or(0, str::len) as u32;
                if let Some(pattern) = pattern {
                    kept.text.push_str(&pattern);
                }
                kept.spans.push((start, len));
            }
        }
        stats.merge(&line_stats);
    }
    // Capacity past the records and patterns would stay in the cache.
    rules.shrink_to_fit();
    let patterns = kept.map(|mut kept| {
        kept.text.shrink_to_fit();
        kept.spans.shrink_to_fit();
        vec![kept]
    });
    ParsedList {
        chunks: vec![rules],
        patterns,
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

fn site(m: &DomainMatcher) -> Option<String> {
    match m {
        DomainMatcher::Hostname(h) => Some(h.clone()),
        DomainMatcher::Entity(e) => Some(format!("{e}.*")),
        DomainMatcher::Regex(_) => None,
    }
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
        .filter(|m| matches!(m, DomainMatcher::Regex(_)))
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

/// The ignore rule that lifts a #925 segment on an excluded site.
fn ignore_rule(site: &str) -> Option<WkRule> {
    let mut trigger = WkTrigger {
        url_filter: ".*".into(),
        ..Default::default()
    };
    match site.strip_suffix(".*") {
        Some(name) => {
            let pattern = format!(
                r"^[^:]+://+([^:/]+\.)?{}\.[^/:]+([/:?#].*)?$",
                regex_escape(name)
            );
            trigger.if_top_url = Some(vec![pattern]);
        }
        None => trigger.if_domain = Some(vec![format!("*{site}")]),
    }
    Some(WkRule {
        trigger,
        action: WkAction::IgnorePreviousRules,
    })
}

fn regex_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        if r"\^$.|?*+()[]{}".contains(c) {
            out.push('\\');
        }
        out.push(c);
    }
    out
}

/// A network rule's pattern as #836 compares it (identity form: lowercase
/// unless a regex). None for a rule with no pattern to compare, and for a
/// page exception (`$document`, `$elemhide`, ...), whose pattern is the page.
fn pattern_of(rule: &NetworkRule) -> Option<String> {
    if !rule.scope.is_empty()
        || matches!(rule.action, NetworkAction::RemoveParam(_))
        || matches!(&rule.action, NetworkAction::Other { option, .. } if option == "uritransform")
    {
        return None;
    }
    let raw = rule.raw.trim();
    let body = raw.strip_prefix("@@").unwrap_or(raw);
    let pattern = if body.starts_with('/') {
        let close = body[1..].char_indices().scan(false, |escaped, (i, c)| {
            let hit = !*escaped && c == '/';
            *escaped = !*escaped && c == '\\';
            Some((i, hit))
        });
        let end = close.filter(|(_, hit)| *hit).map(|(i, _)| i + 2).next();
        end.map_or(body, |e| &body[..e]).to_string()
    } else {
        body[..body.find('$').unwrap_or(body.len())].to_ascii_lowercase()
    };
    (!pattern.is_empty()).then_some(pattern)
}

/// The host of a `||host` pattern without wildcards, when the host has a dot.
fn pattern_host(pattern: &str) -> Option<&str> {
    pattern
        .strip_prefix("||")
        .filter(|_| !pattern.contains('*'))
        .map(|rest| &rest[..rest.find(['^', '/', '$', '|', '?']).unwrap_or(rest.len())])
        .filter(|host| host.contains('.'))
}

/// The host of a whole-host pattern: `||host^`, `||host`, `||host^|` or `||host/`.
fn bare_host(pattern: &str) -> Option<&str> {
    let host = pattern_host(pattern)?;
    matches!(&pattern[2 + host.len()..], "" | "^" | "^|" | "/").then_some(host)
}

/// Whether a block with `pattern` is cancelled by an exception with one of
/// `patterns`, which are sorted in `sorted`. `bare_hosts` are the hosts of
/// the whole-host patterns among them.
fn cancels(
    pattern: &str,
    patterns: &FxHashSet<&str>,
    bare_hosts: &FxHashSet<&str>,
    sorted: &[&str],
) -> bool {
    if patterns.contains(pattern) {
        return true;
    }
    let Some(host) = pattern_host(pattern) else { return false };
    // A whole-host block on this host or a parent domain covers the URL:
    // each suffix of two or more labels.
    let mut suffix = host;
    while let Some((_, parent)) = suffix.split_once('.') {
        if bare_hosts.contains(suffix) {
            return true;
        }
        suffix = parent;
    }
    let key = pattern.trim_end_matches(['^', '|']);
    if key.len() < 4 {
        return false;
    }
    // A block whose pattern is a prefix of the exception matches the same URLs.
    if (4..=key.len()).any(|end| key.is_char_boundary(end) && patterns.contains(&key[..end])) {
        return true;
    }
    // An exception whose pattern is a prefix of a block is broader than it.
    let at = sorted.partition_point(|p| *p < key);
    sorted.get(at).is_some_and(|p| p.starts_with(key))
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

    /// Retained patterns must fingerprint and compile exactly as parsed rules
    /// do: exceptions, bare hosts, and scoped lists all take the parse path
    /// or the stored patterns with the same result.
    #[test]
    fn retained_patterns_match_parsed_rules() {
        let left = "||ads.example.com^\n@@||ads.example.com/ok^\n||tracker.net/x\n||bare.org^\n$badfilter,domain=other.com\n";
        let right = "@@||tracker.net^\n||tracker.net/x^$third-party\nexample.com##.x\n@@||bare.org^\n||ads.example.com^$image\n";
        let lists = |retain: bool, scope: Value| {
            let mut request = two_list_request(left, right, scope);
            request.retain = retain;
            request
        };
        for scope in [json!({}), json!({"exclude": ["shop.*"]})] {
            let parsed = Plan::with_cache(lists(false, scope.clone()), &ParseCache::default());
            let kept = Plan::with_cache(lists(true, scope.clone()), &ParseCache::default());
            for target in 0..parsed.target_count() {
                assert_eq!(parsed.fingerprint(target, &[]), kept.fingerprint(target, &[]));
                assert_eq!(rules(&parsed, target), rules(&kept, target));
            }
        }
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
        let records = |parsed: &ParsedList| -> Vec<(usize, u32, u32, u64, bool, bool)> {
            parsed
                .records()
                .map(|p| (p.offset, p.line, p.index, p.identity, p.shared, p.network))
                .collect()
        };
        let patterns = |parsed: &ParsedList| -> Vec<Option<String>> {
            (0..parsed.chunks.len())
                .flat_map(|c| (0..parsed.chunks[c].len()).map(move |i| (c, i)))
                .map(|(c, i)| parsed.stored_pattern(c, i).flatten().map(str::to_owned))
                .collect()
        };
        let whole = parse_chunked(&list, usize::MAX, true);
        for chunk in [1, 64, 1000] {
            let chunked = parse_chunked(&list, chunk, true);
            assert!(chunked.chunks.len() > 1, "chunk {chunk} gives one chunk");
            assert_eq!(records(&chunked), records(&whole), "chunk {chunk}");
            assert_eq!(patterns(&chunked), patterns(&whole), "chunk {chunk}");
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
        let base = make("||a.example^", "||b.example^");
        let fp = |p: &Plan, t| {
            let fingerprint = p.fingerprint(t, &[]);
            assert_eq!(fingerprint, p.compile_target(t, &[]).fingerprint);
            fingerprint
        };
        // Another blocker's list changing leaves this one alone...
        let other = make("||a.example^", "||b.example^\n||c.example^");
        assert_eq!(fp(&base, 0), fp(&other, 0));
        assert_ne!(fp(&base, 1), fp(&other, 1));
        // ...unless it brings an exception this blocker copies (#836).
        let exception = make("||a.example^", "||b.example^\n@@||a.example/ok^");
        assert_ne!(fp(&base, 0), fp(&exception, 0));
        // ...or takes over a rule this blocker compiled (#681): the first
        // list in compile order owns a rule both have.
        let make_reversed = |first: &str| {
            plan(
                json!([{"id":"b", "text":first}, {"id":"a", "text":"||a.example^\n||x.example^"}]),
                json!([{"slot":1,"lists":[{"list":1}]}, {"slot":2,"lists":[{"list":0}]}]),
                json!({}),
            )
        };
        let (before, after) = (
            make_reversed("||b.example^"),
            make_reversed("||b.example^\n||a.example^"),
        );
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
        assert!(json.contains("sub.example.com"));
        assert!(!json.contains("other.org"));
        assert!(!json.contains(".generic"));

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
        assert!(output.contains("deep"), "{output}");
        let own = plan.own_patterns(0);
        assert_eq!(plan.replicated(0, own.iter().map(|p| p.as_ref())).len(), 2);
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
                && r["trigger"]["if-domain"]
                    .to_string()
                    .contains("shop.example.com")
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
                && rule["trigger"]["if-domain"]
                    .to_string()
                    .contains("sub.example.com")));
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
    fn distinct_exception_contexts_keep_both_blocks() {
        let plan = plan(
            json!([{ "id":"left", "text":"||ads.example^\n@@||ads.example^" }, {"id":"right", "text":"||ads.example^"}]),
            json!([{"slot":1,"lists":[{"list":0}]},{"slot":2,"lists":[{"list":1}]}]),
            json!({}),
        );
        assert!(rules(&plan, 0)
            .iter()
            .any(|rule| rule["action"]["type"] == "block"));
        assert!(rules(&plan, 1)
            .iter()
            .any(|rule| rule["action"]["type"] == "block"));
    }

    #[test]
    fn shards_share_exceptions_and_partition_blocks() {
        let text = (0..50)
            .map(|index| format!("||host{index}.example^"))
            .collect::<Vec<_>>()
            .join("\n")
            + "\n@@||allowed.example^";
        let plan = plan(
            json!([{ "id":"list", "text":text }]),
            json!([
                {"slot":1,"lists":[{"list":0,"shard":[0,2]}]}, {"slot":2,"lists":[{"list":0,"shard":[1,2]}]}
            ]),
            json!({}),
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
                {"id":"blocks", "text":"/ads.js\nsite.com##.ad"},
                {"id":"exceptions", "text":"@@||site.com^$document\n@@||page.com^$elemhide"}
            ]),
            json!([{"slot":1,"lists":[{"list":0}]},{"slot":2,"lists":[{"list":1}]}]),
            json!({}),
        );
        let left = crate::webkit::to_json(&plan.compile_target(0, &[]).output.webkit);
        assert!(left.contains("*site.com") && left.contains("*page.com"), "{left}");
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
        // WBE_RETAIN=0 runs the phone path, which keeps no patterns.
        let retain = std::env::var("WBE_RETAIN").map_or(true, |v| v != "0");
        Plan::new(PlanRequest {
            safari: (18, 0),
            lists,
            targets,
            cosmetics,
            retain,
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

