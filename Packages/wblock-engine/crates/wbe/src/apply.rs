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
use crate::compile::{compile_rules, parse_list, CompileOptions, CompileOutput, RuleSet, Stats};
use crate::parse::cosmetic::with_domains;
use crate::webkit::{SafariVersion, WebkitJson, WkAction, WkRule, WkTrigger};
use serde::{Deserialize, Serialize};
use std::borrow::Cow;
use std::collections::hash_map::DefaultHasher;
use rustc_hash::{FxHashMap, FxHashSet};
use std::collections::BTreeMap;
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

#[derive(Debug, Clone, Default, Deserialize)]
pub struct CosmeticScope {
    #[serde(flatten)]
    pub sites: SiteScope,
    /// False drops hides that name no site.
    #[serde(default = "yes")]
    pub generic: bool,
}

fn yes() -> bool {
    true
}

#[derive(Debug, Clone, Deserialize)]
pub struct PlanRequest {
    pub safari: (u16, u16),
    /// In compile order.
    pub lists: Vec<ListSpec>,
    pub targets: Vec<TargetSpec>,
    #[serde(default)]
    pub cosmetics: CosmeticScope,
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
    /// `is_plain_block`, which the segment of #925 compiles unscoped.
    plain: bool,
    badfilter: bool,
    /// Affinity types of the enclosing `!#safari_cb_affinity` block.
    affinity: Option<u8>,
}

struct ParsedList {
    rules: Vec<Parsed>,
    has_affinity: bool,
    /// A `!#` directive anywhere keeps the list out of #681 dedupe, as before.
    has_directive: bool,
    stats: Stats,
}

pub struct Plan {
    opts: CompileOptions,
    lists: Vec<ListSpec>,
    parsed: Vec<ParsedList>,
    targets: Vec<TargetSpec>,
    cosmetics: CosmeticScope,
    /// List index -> rule identities a blocker other than this one owns (#681).
    duplicates: Vec<Vec<FxHashSet<u64>>>,
    /// Hash of each list's text, for `fingerprint`.
    text_hashes: Vec<u64>,
}

impl Plan {
    pub fn new(request: PlanRequest) -> Plan {
        let opts = CompileOptions {
            safari: SafariVersion::new(request.safari.0, request.safari.1),
        };
        let parsed = parallel(&request.lists, |index, list| parse(list, index as u32));
        let text_hashes = parallel(&request.lists, |_, list| hash(&list.text));
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

    /// The rules of `list` that blocker `target` compiles, site scope applied.
    /// `included` for every list, materialized in parallel.
    fn included_all(&self, target: usize) -> Vec<Vec<Rule>> {
        let lists: Vec<usize> = (0..self.lists.len()).collect();
        parallel(&lists, |_, &list| self.included(target, list))
    }

    fn included(&self, target: usize, list: usize) -> Vec<Rule> {
        let types = slot_types(self.targets[target].slot);
        let assignment = self.assigned(target, list);
        let parsed = &self.parsed[list];
        if assignment.is_none() && !parsed.has_affinity {
            return Vec::new();
        }
        let scope = &self.lists[list].scope;
        let mut out = Vec::new();
        for p in &parsed.rules {
            let keep = match (parsed.has_affinity, p.affinity, assignment) {
                (true, Some(mask), _) => mask & types != 0,
                (_, _, Some(a)) => {
                    p.shared
                        || a.shard
                            .map_or(true, |(i, n)| p.identity % n as u64 == i as u64)
                }
                _ => false,
            };
            if keep && !self.duplicates[target][list].contains(&p.identity) {
                scoped(self.rule(list, p), scope, &mut out);
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
                    for p in parsed.rules.iter().filter(|p| p.shared) {
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
                for p in parsed.rules.iter().filter(|p| !p.shared) {
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
        let included = self.included_all(target);
        let replicated = self.replicated_exceptions(target, &included);
        self.fingerprint_of(target, extras, &replicated)
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
        for rule in replicated {
            format!("{rule:?}").hash(&mut h);
        }
        for extra in extras {
            (&extra.text, extra.trusted).hash(&mut h);
        }
        h.finish()
    }

    pub fn compile_target(&self, target: usize, extras: &[Extra]) -> TargetOutput {
        let segment_list = self.segment_list(target);
        let mut set = RuleSet::default();
        let mut segment = RuleSet::default();
        let mut admitted = BTreeMap::new();
        let mut seen = FxHashSet::default();
        let mut stats = Stats::default();
        let included = self.included_all(target);
        let replicated = self.replicated_exceptions(target, &included);
        let fingerprint = self.fingerprint_of(target, extras, &replicated);
        for (list, rules) in included.into_iter().enumerate() {
            if rules.is_empty() {
                continue;
            }
            stats.merge(&self.parsed[list].stats);
            let count = admitted.entry(self.lists[list].id.clone()).or_insert(0u64);
            for rule in rules {
                let Some(rule) = self.cosmetic_scoped(rule) else {
                    continue;
                };
                if seen.insert(identity(raw(&rule))) {
                    *count += 1;
                }
                // Segment blocks compile unscoped; the ignore rules scope them.
                if Some(list) == segment_list && is_plain_block(&rule) {
                    continue;
                }
                set.push(Cow::Owned(rule));
            }
        }
        if let Some(list) = segment_list {
            let assignment = self.assigned(target, list).cloned();
            for p in &self.parsed[list].rules {
                let keep = assignment.as_ref().is_some_and(|a| {
                    a.shard
                        .is_none_or(|(i, n)| p.identity % n as u64 == i as u64)
                });
                // A badfilter is segment-wide, whatever its shard.
                let kept = keep && p.plain && !self.duplicates[target][list].contains(&p.identity);
                if p.badfilter || kept {
                    segment.push(Cow::Owned(self.rule(list, p)));
                }
            }
        }
        for rule in replicated {
            if matches!(&rule, Rule::Network(r) if r.badfilter) {
                segment.push(Cow::Owned(rule.clone()));
            }
            set.push(Cow::Owned(rule));
        }
        for (i, extra) in extras.iter().enumerate() {
            let mut extra_stats = Stats::default();
            for rule in parse_list(
                &extra.text,
                (self.lists.len() + i) as u32,
                extra.trusted,
                &mut extra_stats,
            ) {
                if let Some(rule) = self.cosmetic_scoped(rule) {
                    set.push(Cow::Owned(rule));
                }
            }
            stats.merge(&extra_stats);
        }
        let mut output = compile_rules(&set, &self.opts, stats);
        if let Some(list) = segment_list {
            let front = compile_rules(&segment, &self.opts, Stats::default()).webkit;
            let ignores: Vec<WkRule> = self.lists[list]
                .scope
                .exclude
                .iter()
                .filter_map(|site| ignore_rule(site))
                .collect();
            output.webkit = WebkitJson::join([&front, &WebkitJson::from_rules(&ignores), &output.webkit]);
            output.stats.native_rules = output.webkit.rules() as u64;
        }
        TargetOutput {
            output,
            admitted,
            fingerprint,
        }
    }

    /// #925: the largest list of this blocker with excluded sites (and no
    /// #681 duplicates) compiles its plain blocks unconditioned, then one
    /// ignore rule per excluded site. Only one list per blocker can: a second
    /// ignore would cancel the first list's blocks.
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
            })
            .max_by_key(|&l| self.parsed[l].rules.len())
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
    /// its own blocker). Matching errs toward copying, which is harmless.
    fn replicated_exceptions(&self, target: usize, included: &[Vec<Rule>]) -> Vec<Rule> {
        let mut patterns = FxHashSet::default();
        let mut bare_hosts = FxHashSet::default();
        for rules in included {
            for rule in rules {
                if let Rule::Network(r) = rule {
                    if let Some(key) = PatternKey::of(r).filter(|_| !r.exception) {
                        if key.bare {
                            bare_hosts.insert(key.host.clone().unwrap_or_default());
                        }
                        patterns.insert(key.pattern);
                    }
                }
            }
        }
        let mut sorted: Vec<&String> = patterns.iter().collect();
        sorted.sort_unstable();
        let mut seen = FxHashSet::default();
        let mut out = Vec::new();
        for list in 0..self.lists.len() {
            if self.assigned(target, list).is_some() {
                continue;
            }
            let mut scoped_rules = Vec::new();
            for p in self.parsed[list].rules.iter().filter(|p| p.shared) {
                scoped(self.rule(list, p), &self.lists[list].scope, &mut scoped_rules);
            }
            for rule in scoped_rules {
                match &rule {
                    Rule::Cosmetic(r) if r.exception => {
                        if seen.insert(identity(&r.raw)) {
                            if let Some(rule) = self.cosmetic_scoped(rule) {
                                out.push(rule);
                            }
                        }
                    }
                    Rule::Network(r) if r.exception || r.badfilter => {
                        let matches = PatternKey::of(r).is_none_or(|key| {
                            key.host.is_none() || key.cancels(&patterns, &bare_hosts, &sorted)
                        });
                        if matches && seen.insert(identity(&r.raw)) {
                            out.push(rule);
                        }
                    }
                    _ => {}
                }
            }
        }
        out
    }
}

/// `body(i, item)` for every item on all cores, results in order.
fn parallel<T: Sync, R: Send>(items: &[T], body: impl Fn(usize, &T) -> R + Sync) -> Vec<R> {
    let threads = std::thread::available_parallelism()
        .map_or(4, |n| n.get())
        .min(items.len().max(1));
    let chunk = items.len().div_ceil(threads.max(1)).max(1);
    std::thread::scope(|scope| {
        let handles: Vec<_> = items
            .chunks(chunk)
            .enumerate()
            .map(|(c, part)| {
                let body = &body;
                scope.spawn(move || {
                    part.iter()
                        .enumerate()
                        .map(|(i, item)| body(c * chunk + i, item))
                        .collect::<Vec<R>>()
                })
            })
            .collect();
        handles
            .into_iter()
            .flat_map(|h| h.join().expect("parse thread"))
            .collect()
    })
}

fn parse(list: &ListSpec, index: u32) -> ParsedList {
    let mut stats = Stats::default();
    let mut rules = Vec::new();
    let mut affinity: Option<u8> = None;
    let mut has_affinity = false;
    let mut has_directive = false;
    // Lines are parsed one at a time so affinity blocks can be tracked.
    for (n, line) in list.text.lines().enumerate() {
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
        let parsed_line = parse_list(line, index, list.trusted, &mut line_stats);
        for (position, rule) in parsed_line.iter().enumerate() {
            rules.push(Parsed {
                offset,
                line: n as u32 + 1,
                index: position as u32,
                identity: identity_in_scope(raw(rule), &list.scope),
                shared: is_shared(rule),
                plain: is_plain_block(rule),
                badfilter: matches!(rule, Rule::Network(r) if r.badfilter),
                affinity,
            });
        }
        stats.merge(&line_stats);
    }
    rules.shrink_to_fit();
    ParsedList {
        rules,
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
    if let Some((at, _)) = crate::parse::cosmetic::find_marker(raw) {
        let (domains, rest) = raw.split_at(at);
        return if domains.contains('/') {
            hash(raw)
        } else {
            hash(&(domains.to_ascii_lowercase() + rest))
        };
    }
    let body = raw.strip_prefix("@@").unwrap_or(raw);
    let dollar = body.find('$').unwrap_or(body.len());
    let (pattern, options) = body.split_at(dollar);
    let case_sensitive = options
        .split(',')
        .any(|o| o.trim_start_matches('$') == "match-case");
    if pattern.starts_with('/') || case_sensitive {
        hash(raw)
    } else {
        hash(&(raw[..raw.len() - body.len()].to_string() + &pattern.to_ascii_lowercase() + options))
    }
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
/// excluded subdomain of its scope (#767).
fn scoped(rule: Rule, scope: &SiteScope, out: &mut Vec<Rule>) {
    if scope.is_empty() {
        out.push(rule);
        return;
    }
    match rule {
        Rule::Network(mut r) => {
            let Some(restricted) = restrict(&r.from, scope) else {
                return;
            };
            let companion = (!restricted.uncovered.is_empty() && !r.exception && !r.badfilter)
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
            out.push(Rule::Network(r));
            out.extend(companion.map(|r| Rule::Network(Box::new(r))));
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
/// unless a regex), and the host of a `||host` pattern without wildcards.
struct PatternKey {
    pattern: String,
    host: Option<String>,
    /// `||host^`, `||host`, `||host^|` or `||host/`: the whole host.
    bare: bool,
}

impl PatternKey {
    fn of(rule: &NetworkRule) -> Option<PatternKey> {
        if matches!(rule.action, NetworkAction::RemoveParam(_))
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
        if pattern.is_empty() {
            return None;
        }
        let host = pattern
            .strip_prefix("||")
            .filter(|_| !pattern.contains('*'))
            .map(|rest| {
                let end = rest.find(['^', '/', '$', '|', '?']).unwrap_or(rest.len());
                rest[..end].to_string()
            });
        let host = host.filter(|h| h.contains('.'));
        let bare = host
            .as_ref()
            .is_some_and(|h| matches!(&pattern[2 + h.len()..], "" | "^" | "^|" | "/"));
        Some(PatternKey {
            pattern,
            host,
            bare,
        })
    }

    fn cancels(
        &self,
        patterns: &FxHashSet<String>,
        bare_hosts: &FxHashSet<String>,
        sorted: &[&String],
    ) -> bool {
        if patterns.contains(&self.pattern) {
            return true;
        }
        let Some(host) = &self.host else { return false };
        // A whole-host block on this host or a parent domain covers the URL.
        let labels: Vec<&str> = host.split('.').collect();
        for start in 0..labels.len().saturating_sub(1) {
            if bare_hosts.contains(&labels[start..].join(".")) {
                return true;
            }
        }
        let key = self.pattern.trim_end_matches(['^', '|']);
        if key.len() < 4 {
            return false;
        }
        // A block whose pattern is a prefix of the exception matches the same URLs.
        if (4..=key.len()).any(|end| key.is_char_boundary(end) && patterns.contains(&key[..end])) {
            return true;
        }
        // An exception whose pattern is a prefix of a block is broader than it.
        let at = sorted.partition_point(|p| p.as_str() < key);
        sorted.get(at).is_some_and(|p| p.starts_with(key))
    }
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
            let kept: Vec<String> = plan
                .included(0, 0)
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
        let included: Vec<_> = (0..2).map(|list| plan.included(0, list)).collect();
        assert_eq!(plan.replicated_exceptions(0, &included).len(), 2);
        assert!(!output.contains("other\\\\.test"), "{output}");
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
    fn real_lists_plan(config: &str) -> Plan {
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
        let lists: Vec<Value> = paths
            .iter()
            .enumerate()
            .map(|(index, path)| {
                let mut list = json!({"id": path.file_name().unwrap().to_string_lossy(), "text": std::fs::read_to_string(path).unwrap()});
                if scoped && index % 3 == 0 {
                    list["scope"] = json!({"exclude": ["example.com", "shop.*"]});
                } else if scoped && index % 5 == 4 {
                    list["scope"] = json!({"only": ["news.example.com", "example.*"]});
                }
                list
            })
            .collect();
        let mut blockers: Vec<Vec<Value>> = vec![Vec::new(); 5];
        for index in 0..lists.len() {
            let primary = index % 5;
            if sharded && index % 4 == 0 {
                blockers[primary].push(json!({"list": index, "shard": [0, 2]}));
                blockers[(primary + 1) % 5].push(json!({"list": index, "shard": [1, 2]}));
            } else {
                blockers[primary].push(json!({"list": index}));
            }
        }
        let targets: Vec<Value> = blockers
            .into_iter()
            .enumerate()
            .map(|(slot, lists)| json!({"slot": slot + 1, "lists": lists}))
            .collect();
        let cosmetics = if scoped {
            json!({"exclude": ["news.example.com"]})
        } else {
            json!({})
        };
        plan(json!(lists), json!(targets), cosmetics)
    }

    #[test]
    #[ignore]
    fn benchmark_real_lists() {
        let start = std::time::Instant::now();
        let plan = real_lists_plan("plain");
        println!("Plan::new {:?}", start.elapsed());
        // WBE_BENCH_TARGET=n compiles only that blocker, to attribute peak memory.
        let only: Option<usize> = std::env::var("WBE_BENCH_TARGET").ok().and_then(|v| v.parse().ok());
        for target in (0..5).filter(|t| only.is_none_or(|o| o == *t)) {
            let start = std::time::Instant::now();
            let output = plan.compile_target(target, &[]);
            println!(
                "target {target}: {:?}, {} rules",
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
            let plan = real_lists_plan(config);
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

