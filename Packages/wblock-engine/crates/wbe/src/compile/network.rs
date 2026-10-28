//! uBO network rules to WebKit rules.
//!
//! Blocks are dropped when a condition cannot be expressed, so they never
//! block more than uBO does. Exceptions drop the condition instead, which
//! makes them wider and can only under-block. Each rule's tier follows
//! `compile/mod.rs`; exceptions use ignore-previous-rules.

use super::regex::{domain_top_url, url_filter};
use super::{CompileOptions, Stats, Tier, Tiered};
use crate::ast::{
    DomainList, DomainMatcher, ExceptionScope, NetworkAction, NetworkRule, Party, Pattern,
    PatternKind, ResourceTypes, SourceRef,
};
use crate::webkit::{
    SafariVersion, WkAction, WkLoadContext, WkLoadType, WkResourceType, WkRule, WkTrigger,
};
use rustc_hash::{FxHashMap, FxHashSet};
use std::collections::HashSet;

/// uBO's default for a rule without `$type`: every type except the main
/// document, popups and inline resources (static-net-filtering.js,
/// `typeNameToTypeValue`).
const DEFAULT_TYPES: ResourceTypes = ResourceTypes::all().difference(
    ResourceTypes::DOC
        .union(ResourceTypes::POPUP)
        .union(ResourceTypes::POPUNDER)
        .union(ResourceTypes::INLINE_SCRIPT)
        .union(ResourceTypes::INLINE_FONT),
);

pub(super) fn compile(
    rules: &[NetworkRule],
    opts: &CompileOptions,
    out: &mut Vec<Tiered>,
    stats: &mut Stats,
) {
    let bad: Vec<NetworkRule> = rules
        .iter()
        .filter(|r| r.badfilter)
        .map(unlabeled)
        .collect();
    let bad_bodies: HashSet<&str> = bad.iter().map(|b| b.pattern.body.as_str()).collect();
    let strict = StrictHosts::new(rules);
    let start = out.len();
    for rule in rules {
        if rule.badfilter {
            continue;
        }
        if !bad_bodies.is_empty()
            && bad_bodies.contains(rule.pattern.body.as_str())
            && bad.contains(&unlabeled(rule))
        {
            continue;
        }
        if let Err(reason) = compile_rule(rule, opts.safari, &strict, out) {
            stats.drop(&reason);
        }
    }
    dedupe_and_merge(out, start);
}

/// A rule with its provenance and `$badfilter` flag cleared, for comparing
/// filters. uBO cancels a filter only when its compiled form is identical
/// (static-net-filtering.js, `freeze`); there is no domain-subset matching.
fn unlabeled(r: &NetworkRule) -> NetworkRule {
    let mut r = r.clone();
    r.source = SourceRef::default();
    r.raw.clear();
    r.badfilter = false;
    r
}

fn compile_rule(
    r: &NetworkRule,
    v: SafariVersion,
    strict: &StrictHosts,
    out: &mut Vec<Tiered>,
) -> Result<(), String> {
    match &r.action {
        NetworkAction::Block
        | NetworkAction::Redirect {
            rule_only: false, ..
        } => {}
        NetworkAction::Redirect {
            rule_only: true, ..
        } => {
            return Err("dnr:redirect-rule".into());
        }
        NetworkAction::RemoveParam(_) => return Err("dnr:removeparam".into()),
        NetworkAction::Csp(_) => return Err("dnr:csp".into()),
        NetworkAction::Permissions(_) => return Err("dnr:permissions".into()),
        NetworkAction::Other { option, .. } => return Err(format!("dnr:{option}")),
    }
    if !r.scope.is_empty() {
        return if r.exception {
            compile_scope(r, v, out)
        } else {
            Err("dnr:scope-on-block".into())
        };
    }
    let exception = r.exception;
    // `@@...$cname` only exempts a request from CNAME uncloaking; it never
    // allows one (static-net-filtering.js), so it has nothing to lift here.
    if exception && r.runtime_only_options.iter().any(|o| o == "cname") {
        return Err("dnr:cname-exception".into());
    }
    if !exception && !r.runtime_only_options.is_empty() {
        return Err("dnr:runtime-option".into());
    }
    if !exception && (!r.method.include.is_empty() || !r.method.exclude.is_empty()) {
        return Err("dnr:method".into());
    }
    if !exception && !r.denyallow.is_empty() {
        return Err("dnr:denyallow".into());
    }
    let party = party(r.party, exception)?;
    let urls = urls(r, exception)?;
    let conds = domain_conds(&r.from, v, exception)?;
    let types = effective_types(r);
    // uBO also strict-blocks top-level navigation for an untyped filter whose
    // match ends at the hostname (traffic.js, `shouldStrictBlock`), so such a
    // block is one trigger over every type, documents included. An exception
    // takes that form only where it must lift such a block: on a page load,
    // ignore-previous-rules also cancels the page's cosmetic hides.
    let untyped = r.types.is_empty()
        && r.negated_types.is_empty()
        && host_only(&r.pattern).is_some_and(|h| !exception || strict.related(&h));
    let type_triggers = if untyped {
        vec![(Vec::new(), None)]
    } else {
        type_triggers(types, v)
    };
    if type_triggers.is_empty() {
        // An exception without a type WebKit can match cancels nothing.
        return if exception {
            Ok(())
        } else {
            Err(type_drop_reason(types, v))
        };
    }
    let (action, tier) = if exception {
        (WkAction::IgnorePreviousRules, Tier::Exception)
    } else if r.important {
        (WkAction::Block, Tier::ImportantBlock)
    } else {
        (WkAction::Block, Tier::Block)
    };
    for url in &urls {
        for (types, context) in &type_triggers {
            for cond in &conds {
                let mut trigger = WkTrigger {
                    url_filter: url.clone(),
                    url_filter_is_case_sensitive: r.match_case.then_some(true),
                    resource_type: (!types.is_empty()).then(|| types.clone()),
                    load_type: party.map(|p| vec![p]),
                    load_context: context.map(|c| vec![c]),
                    ..Default::default()
                };
                if let Some(cond) = cond {
                    cond.apply(&mut trigger);
                }
                out.push(Tiered {
                    tier,
                    rule: WkRule {
                        trigger,
                        action: action.clone(),
                    },
                });
            }
        }
    }
    Ok(())
}

/// `@@...$document`, `$generichide`, `$elemhide`, `$specifichide`: one
/// ignore-previous-rules over every type, conditioned on the page URL.
/// `$specifichide` is widened to `$elemhide`, which also cancels generic
/// hides.
fn compile_scope(r: &NetworkRule, v: SafariVersion, out: &mut Vec<Tiered>) -> Result<(), String> {
    let remaining = r.scope.difference(ExceptionScope::GENERICBLOCK);
    let tier = if remaining.contains(ExceptionScope::DOC) {
        Tier::DocumentException
    } else if remaining.intersects(ExceptionScope::EHIDE | ExceptionScope::SHIDE) {
        Tier::ElemHideException
    } else if remaining.contains(ExceptionScope::GHIDE) {
        Tier::GenericHideException
    } else {
        // uBO maps `$genericblock` to an unsupported type that matches nothing.
        return Err("dnr:genericblock".into());
    };
    let conds = match page_cond(&r.pattern, v) {
        Some(cond) => vec![Some(cond)],
        None => domain_conds(&r.from, v, true)?,
    };
    for cond in conds {
        let mut trigger = WkTrigger {
            url_filter: ".*".into(),
            ..Default::default()
        };
        if let Some(cond) = cond {
            cond.apply(&mut trigger);
        }
        out.push(Tiered {
            tier,
            rule: WkRule {
                trigger,
                action: WkAction::IgnorePreviousRules,
            },
        });
    }
    Ok(())
}

/// The page condition of a scope exception: a host-only pattern becomes
/// if-domain, anything else if-top-url. `None` means no condition, which
/// widens the exception.
fn page_cond(p: &Pattern, v: SafariVersion) -> Option<Cond> {
    if p.is_match_all() {
        return None;
    }
    if let Some(host) = host_only(p) {
        return Some(Cond::IfDomain(vec![format!("*{host}")]));
    }
    if !v.at_least(15, 0) {
        return None;
    }
    Some(Cond::IfTopUrl(vec![url_filter(p)?]))
}

/// Hosts of untyped `||host^` blocks and all their parents, so an exception
/// can tell whether it lifts one.
struct StrictHosts {
    hosts: FxHashSet<String>,
    parents: FxHashSet<String>,
}

impl StrictHosts {
    fn new(rules: &[NetworkRule]) -> Self {
        let mut hosts = FxHashSet::default();
        let mut parents = FxHashSet::default();
        for r in rules {
            if r.exception || !r.types.is_empty() || !r.negated_types.is_empty() {
                continue;
            }
            if let Some(h) = host_only(&r.pattern) {
                for (i, _) in h.match_indices('.') {
                    parents.insert(h[i + 1..].to_string());
                }
                hosts.insert(h);
            }
        }
        Self { hosts, parents }
    }

    /// A block on `host`, a parent of it, or a subdomain of it.
    fn related(&self, host: &str) -> bool {
        self.parents.contains(host)
            || std::iter::once(host)
                .chain(host.match_indices('.').map(|(i, _)| &host[i + 1..]))
                .any(|h| self.hosts.contains(h))
    }
}

/// The lowercase hostname of a `||host^` pattern with nothing after the host.
fn host_only(p: &Pattern) -> Option<String> {
    if p.kind != PatternKind::Hostname || p.right_anchored {
        return None;
    }
    let body = p.body.to_ascii_lowercase();
    let end = body
        .find(|c: char| !(c.is_ascii_alphanumeric() || c == '-' || c == '.'))
        .unwrap_or(body.len());
    let (host, rest) = body.split_at(end);
    // A body cut at `*` (`||google.*^`) leaves a trailing dot: not a host.
    (!host.is_empty() && !host.ends_with('.') && (rest.is_empty() || rest == "^"))
        .then(|| host.to_string())
}

fn party(p: Party, exception: bool) -> Result<Option<WkLoadType>, String> {
    Ok(match p {
        Party::Any => None,
        Party::First => Some(WkLoadType::FirstParty),
        Party::Third => Some(WkLoadType::ThirdParty),
        // Strict parties are subsets of first/third, so an exception may use
        // the wider one. A block cannot.
        Party::StrictFirst if exception => Some(WkLoadType::FirstParty),
        Party::StrictThird if exception => Some(WkLoadType::ThirdParty),
        Party::StrictFirst | Party::StrictThird => return Err("dnr:strict-party".into()),
    })
}

/// The url-filters for a rule. `$to=` with a match-all pattern becomes one
/// filter per target hostname. Other `$to=` uses are dropped for blocks and
/// ignored for exceptions.
fn urls(r: &NetworkRule, exception: bool) -> Result<Vec<String>, String> {
    let pattern = match url_filter(&r.pattern) {
        Some(u) => u,
        None if exception => ".*".into(),
        None => return Err("dnr:url-filter".into()),
    };
    if r.to.is_empty() || exception {
        return Ok(vec![pattern]);
    }
    if !r.to.exclude.is_empty() || !r.pattern.is_match_all() {
        return Err("dnr:to".into());
    }
    r.to.include
        .iter()
        .map(|m| match m {
            DomainMatcher::Hostname(h) => url_filter(&Pattern {
                kind: PatternKind::Hostname,
                body: format!("{h}^"),
                ..Default::default()
            })
            .ok_or_else(|| "dnr:to".to_string()),
            _ => Err("dnr:to".into()),
        })
        .collect()
}

/// One condition per trigger. Each alternative is a separate trigger, which
/// makes a mixed include list (hostnames and entities) a union. `None` means
/// no condition. For an exception, anything inexpressible is removed.
fn domain_conds(
    list: &DomainList,
    v: SafariVersion,
    exception: bool,
) -> Result<Vec<Option<Cond>>, String> {
    let top = v.at_least(15, 0);
    let split = |items: &[DomainMatcher]| {
        let (mut hosts, mut tops, mut all) = (Vec::new(), Vec::new(), true);
        for m in items {
            match m {
                DomainMatcher::Hostname(h) => hosts.push(format!("*{h}")),
                _ => match domain_top_url(m) {
                    Some(u) if top => tops.push(u),
                    _ => all = false,
                },
            }
        }
        (hosts, tops, all)
    };
    let (inc_hosts, inc_tops, inc_ok) = split(&list.include);
    if !inc_ok {
        // Dropping an include item would narrow the exception, so the
        // exception takes no domain condition at all.
        return if exception {
            Ok(vec![None])
        } else {
            Err("dnr:domain".into())
        };
    }
    if !inc_hosts.is_empty() || !inc_tops.is_empty() {
        if !list.exclude.is_empty() && !exception {
            return Err("dnr:domain".into());
        }
        let mut alts = Vec::new();
        if !inc_hosts.is_empty() {
            alts.push(Some(Cond::IfDomain(inc_hosts)));
        }
        if !inc_tops.is_empty() {
            alts.push(Some(Cond::IfTopUrl(inc_tops)));
        }
        return Ok(alts);
    }
    let (exc_hosts, exc_tops, exc_ok) = split(&list.exclude);
    if !exc_ok && !exception {
        return Err("dnr:domain".into());
    }
    Ok(match (exc_hosts.is_empty(), exc_tops.is_empty()) {
        (true, true) => vec![None],
        (false, true) => vec![Some(Cond::UnlessDomain(exc_hosts))],
        (true, false) => vec![Some(Cond::UnlessTopUrl(exc_tops))],
        // WebKit allows one domain condition per trigger.
        (false, false) if exception => vec![Some(Cond::UnlessDomain(exc_hosts))],
        (false, false) => return Err("dnr:domain".into()),
    })
}

/// A domain condition for one WebKit trigger. Only one is allowed per trigger.
#[derive(Debug, Clone)]
enum Cond {
    IfDomain(Vec<String>),
    UnlessDomain(Vec<String>),
    IfTopUrl(Vec<String>),
    UnlessTopUrl(Vec<String>),
}

impl Cond {
    fn apply(&self, t: &mut WkTrigger) {
        match self {
            Cond::IfDomain(d) => t.if_domain = Some(d.clone()),
            Cond::UnlessDomain(d) => t.unless_domain = Some(d.clone()),
            Cond::IfTopUrl(u) => t.if_top_url = Some(u.clone()),
            Cond::UnlessTopUrl(u) => t.unless_top_url = Some(u.clone()),
        }
    }
}

/// uBO's types for a rule. Negated types are removed from the positive set,
/// or from the default set if none is given.
fn effective_types(r: &NetworkRule) -> ResourceTypes {
    let base = if r.types.is_empty() {
        DEFAULT_TYPES
    } else {
        r.types
    };
    base.difference(r.negated_types)
}

/// A WebKit resource-type list and the load-context it needs. A trigger with
/// a context cannot share resource types with one without: `load-context`
/// applies to the whole trigger, and `child-frame` also matches subresources
/// inside child frames.
fn type_triggers(
    types: ResourceTypes,
    v: SafariVersion,
) -> Vec<(Vec<WkResourceType>, Option<WkLoadContext>)> {
    let modern = v.at_least(15, 0);
    let mut plain = Vec::new();
    if types.contains(ResourceTypes::IMAGE) {
        plain.push(WkResourceType::Image);
    }
    if types.contains(ResourceTypes::CSS) {
        plain.push(WkResourceType::StyleSheet);
    }
    if types.contains(ResourceTypes::SCRIPT) {
        plain.push(WkResourceType::Script);
    }
    if types.contains(ResourceTypes::FONT) {
        plain.push(WkResourceType::Font);
    }
    if types.contains(ResourceTypes::MEDIA) {
        plain.push(WkResourceType::Media);
    }
    if types.contains(ResourceTypes::PING) && v.at_least(14, 0) {
        plain.push(WkResourceType::Ping);
    }
    if types.contains(ResourceTypes::XHR) {
        plain.push(if modern {
            WkResourceType::Fetch
        } else {
            WkResourceType::Raw
        });
    }
    if types.intersects(ResourceTypes::OTHER | ResourceTypes::OBJECT) {
        plain.push(if modern {
            WkResourceType::Other
        } else {
            WkResourceType::Raw
        });
    }
    if types.contains(ResourceTypes::WEBSOCKET) {
        plain.push(if modern {
            WkResourceType::Websocket
        } else {
            WkResourceType::Raw
        });
    }
    // Before Safari 15 `document` also matches subframes, so documents cannot
    // be targeted safely and are not emitted.
    let (doc, frame) = (
        types.contains(ResourceTypes::DOC),
        types.contains(ResourceTypes::FRAME),
    );
    let mut triggers = Vec::new();
    if modern {
        if doc && frame {
            plain.push(WkResourceType::Document);
        } else if doc {
            triggers.push((
                vec![WkResourceType::Document],
                Some(WkLoadContext::TopFrame),
            ));
        } else if frame {
            triggers.push((
                vec![WkResourceType::Document],
                Some(WkLoadContext::ChildFrame),
            ));
        }
    }
    plain.sort();
    plain.dedup();
    if !plain.is_empty() {
        triggers.insert(0, (plain, None));
    }
    triggers
}

fn type_drop_reason(types: ResourceTypes, v: SafariVersion) -> String {
    if types.intersects(ResourceTypes::POPUP | ResourceTypes::POPUNDER) {
        "dnr:popup".into()
    } else if types.intersects(ResourceTypes::DOC | ResourceTypes::FRAME) && !v.at_least(15, 0) {
        "dnr:document-needs-safari-15".into()
    } else {
        "dnr:type".into()
    }
}

/// Drops exact duplicates. Rules that differ only in an `if-domain` list are
/// merged into one rule with the union, which is exact for `if-domain`. The
/// tier is part of the key, so the merge never changes precedence.
fn dedupe_and_merge(out: &mut Vec<Tiered>, start: usize) {
    let tail = out.split_off(start);
    let mut first_seen = vec![false; tail.len()];
    {
        let mut seen: FxHashSet<(Tier, &WkRule)> = FxHashSet::default();
        for (keep, t) in first_seen.iter_mut().zip(&tail) {
            *keep = seen.insert((t.tier, &t.rule));
        }
    }
    let mut kept: Vec<Tiered> = Vec::with_capacity(tail.len());
    let mut merged: FxHashMap<(Tier, WkRule), usize> = FxHashMap::default();
    for (t, keep) in tail.into_iter().zip(first_seen) {
        if !keep {
            continue;
        }
        if t.rule.trigger.if_domain.is_some() {
            let mut base = t.rule.clone();
            base.trigger.if_domain = None;
            if let Some(&i) = merged.get(&(t.tier, base.clone())) {
                let list = kept[i].rule.trigger.if_domain.get_or_insert_with(Vec::new);
                for d in t.rule.trigger.if_domain.unwrap_or_default() {
                    if !list.contains(&d) {
                        list.push(d);
                    }
                }
                continue;
            }
            merged.insert((t.tier, base), kept.len());
        }
        kept.push(t);
    }
    out.extend(kept);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ast::{MethodList, NetworkRule, ResourceTypes as RT};
    use crate::webkit::to_json;

    const V15: SafariVersion = SafariVersion::new(15, 4);
    const V14: SafariVersion = SafariVersion::new(14, 0);
    const V13: SafariVersion = SafariVersion::new(13, 0);
    const V26: SafariVersion = SafariVersion::new(26, 0);

    /// Parses the pattern forms used in these tests: `||host^path`, `|left`,
    /// `plain`, `/regex/`, and a trailing `|`.
    fn pat(s: &str) -> Pattern {
        let mut body = s;
        let right_anchored = body.len() > 1 && body.ends_with('|') && !body.starts_with("/");
        if right_anchored {
            body = &body[..body.len() - 1];
        }
        let (kind, body) = if let Some(rest) = body.strip_prefix("||") {
            (PatternKind::Hostname, rest)
        } else if let Some(rest) = body.strip_prefix('|') {
            (PatternKind::Left, rest)
        } else if body.len() > 2 && body.starts_with('/') && body.ends_with('/') {
            (PatternKind::Regex, &body[1..body.len() - 1])
        } else {
            (PatternKind::Plain, body)
        };
        Pattern {
            kind,
            body: body.to_string(),
            right_anchored,
        }
    }

    /// A block from uBO text. Options after `$` are not parsed: tests set
    /// them on the struct.
    fn net(s: &str) -> NetworkRule {
        let s = s.trim_start_matches("@@");
        let pattern = match s.rfind('$') {
            Some(i) if !s.ends_with('/') => &s[..i],
            _ => s,
        };
        NetworkRule {
            pattern: pat(pattern),
            raw: s.into(),
            ..Default::default()
        }
    }

    fn exc(s: &str) -> NetworkRule {
        NetworkRule {
            exception: true,
            ..net(s)
        }
    }

    fn hosts(v: &[&str]) -> Vec<DomainMatcher> {
        v.iter()
            .map(|h| DomainMatcher::Hostname(h.to_string()))
            .collect()
    }

    fn list(include: &[&str], exclude: &[&str]) -> DomainList {
        DomainList {
            include: hosts(include),
            exclude: hosts(exclude),
        }
    }

    fn run(rules: &[NetworkRule], v: SafariVersion) -> (Vec<Tiered>, Stats) {
        let mut out = Vec::new();
        let mut stats = Stats::default();
        compile(rules, &CompileOptions { safari: v }, &mut out, &mut stats);
        (out, stats)
    }

    fn json(out: &[Tiered]) -> String {
        let rules: Vec<WkRule> = out.iter().map(|t| t.rule.clone()).collect();
        to_json(&rules)
    }

    fn tiers(out: &[Tiered]) -> Vec<Tier> {
        out.iter().map(|t| t.tier).collect()
    }

    /// Asserts the JSON and the drop count, and returns the rules for other
    /// checks.
    fn check(rules: &[NetworkRule], v: SafariVersion, expect: &str) -> Vec<Tiered> {
        let (out, stats) = run(rules, v);
        assert_eq!(json(&out), expect);
        assert!(
            stats.dropped.is_empty(),
            "unexpected drops: {:?}",
            stats.dropped
        );
        out
    }

    fn drop_reason(rules: &[NetworkRule], v: SafariVersion) -> Vec<String> {
        let (out, stats) = run(rules, v);
        assert!(out.is_empty(), "expected no output, got {}", json(&out));
        stats.dropped.keys().cloned().collect()
    }

    #[test]
    fn plain_host_block_is_one_untyped_rule() {
        // uBO strict-blocks navigation to the host too, so documents are in.
        check(
            &[net("||ads.example.com^")],
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?ads\\.example\\.com[^a-zA-Z0-9_.%-]"},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn host_exception_is_untyped_only_next_to_a_host_block() {
        let lone = check(
            &[exc("@@||cdn.x.com^")],
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?cdn\\.x\\.com[^a-zA-Z0-9_.%-]","resource-type":["image","style-sheet","script","font","media","ping","fetch","websocket","other"]},"action":{"type":"ignore-previous-rules"}},{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?cdn\\.x\\.com[^a-zA-Z0-9_.%-]","resource-type":["document"],"load-context":["child-frame"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
        assert_eq!(lone.len(), 2);
        for block in ["||x.com^", "||cdn.x.com^", "||a.cdn.x.com^"] {
            let (out, _) = run(&[net(block), exc("@@||cdn.x.com^")], V15);
            assert!(
                out.iter().all(|t| t.rule.trigger.resource_type.is_none()),
                "{block}"
            );
        }
    }

    #[test]
    fn path_block_default_types() {
        check(
            &[net("||ads.example.com/x")],
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?ads\\.example\\.com/x","resource-type":["image","style-sheet","script","font","media","ping","fetch","websocket","other"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?ads\\.example\\.com/x","resource-type":["document"],"load-context":["child-frame"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn default_types_on_safari_14_use_raw_and_no_documents() {
        check(
            &[net("||ads.com/x")],
            V14,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?ads\\.com/x","resource-type":["image","style-sheet","script","font","raw","media","ping"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn explicit_script_type() {
        check(
            &[NetworkRule {
                types: RT::SCRIPT,
                ..net("||cdn.com/ads.js")
            }],
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?cdn\\.com/ads\\.js","resource-type":["script"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn xhr_maps_to_fetch_on_15_and_raw_before() {
        let rule = NetworkRule {
            types: RT::XHR,
            ..net("||t.com^")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?t\\.com[^a-zA-Z0-9_.%-]","resource-type":["fetch"]},"action":{"type":"block"}}]"#,
        );
        check(
            std::slice::from_ref(&rule),
            V13,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?t\\.com[^a-zA-Z0-9_.%-]","resource-type":["raw"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn object_and_other_share_one_type_and_websocket_is_gated() {
        let rule = NetworkRule {
            types: RT::OBJECT | RT::OTHER | RT::WEBSOCKET,
            ..net("||t.com^")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?t\\.com[^a-zA-Z0-9_.%-]","resource-type":["websocket","other"]},"action":{"type":"block"}}]"#,
        );
        check(
            std::slice::from_ref(&rule),
            V14,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?t\\.com[^a-zA-Z0-9_.%-]","resource-type":["raw"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn ping_needs_safari_14() {
        let rule = NetworkRule {
            types: RT::PING,
            ..net("||t.com^")
        };
        check(
            std::slice::from_ref(&rule),
            V14,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?t\\.com[^a-zA-Z0-9_.%-]","resource-type":["ping"]},"action":{"type":"block"}}]"#,
        );
        assert_eq!(drop_reason(std::slice::from_ref(&rule), V13), ["dnr:type"]);
    }

    #[test]
    fn subdocument_block_uses_child_frame() {
        let rule = NetworkRule {
            types: RT::FRAME,
            ..net("||frames.com^")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?frames\\.com[^a-zA-Z0-9_.%-]","resource-type":["document"],"load-context":["child-frame"]},"action":{"type":"block"}}]"#,
        );
        assert_eq!(
            drop_reason(std::slice::from_ref(&rule), V14),
            ["dnr:document-needs-safari-15"]
        );
    }

    #[test]
    fn document_block_uses_top_frame() {
        let rule = NetworkRule {
            types: RT::DOC,
            ..net("||top.com^")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?top\\.com[^a-zA-Z0-9_.%-]","resource-type":["document"],"load-context":["top-frame"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn document_and_frame_together_need_no_context() {
        let rule = NetworkRule {
            types: RT::DOC | RT::FRAME | RT::SCRIPT,
            ..net("||x.com^")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?x\\.com[^a-zA-Z0-9_.%-]","resource-type":["document","script"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn all_types_keeps_documents_and_drops_popups() {
        let rule = NetworkRule {
            types: RT::all(),
            ..net("||x.com^")
        };
        let (out, _) = run(std::slice::from_ref(&rule), V15);
        assert_eq!(out.len(), 1, "{}", json(&out));
        assert!(json(&out).contains(r#""document","#) || json(&out).contains(r#""document"]"#));
        assert!(!json(&out).contains("popup"));
    }

    #[test]
    fn negated_types_come_off_the_default() {
        let rule = NetworkRule {
            negated_types: RT::IMAGE,
            ..net("||x.com^")
        };
        let (out, _) = run(std::slice::from_ref(&rule), V15);
        assert!(!json(&out).contains("image"));
        assert!(json(&out).contains("script"));
    }

    #[test]
    fn popup_only_block_is_dropped() {
        assert_eq!(
            drop_reason(
                &[NetworkRule {
                    types: RT::POPUP,
                    ..net("||x.com^")
                }],
                V15
            ),
            ["dnr:popup"]
        );
    }

    #[test]
    fn popup_exception_is_a_no_op() {
        let (out, stats) = run(
            &[NetworkRule {
                types: RT::POPUP,
                ..exc("@@||x.com^")
            }],
            V15,
        );
        assert!(out.is_empty());
        assert!(stats.dropped.is_empty());
    }

    #[test]
    fn third_party_and_first_party_load_type() {
        let third = NetworkRule {
            party: Party::Third,
            ..net("||t.com/x")
        };
        let first = NetworkRule {
            party: Party::First,
            types: RT::SCRIPT,
            ..net("||t.com^")
        };
        check(
            &[third, first],
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?t\\.com/x","resource-type":["image","style-sheet","script","font","media","ping","fetch","websocket","other"],"load-type":["third-party"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?t\\.com/x","resource-type":["document"],"load-type":["third-party"],"load-context":["child-frame"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?t\\.com[^a-zA-Z0-9_.%-]","resource-type":["script"],"load-type":["first-party"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn strict_party_blocks_are_dropped_and_exceptions_widen() {
        let strict = NetworkRule {
            party: Party::StrictThird,
            types: RT::SCRIPT,
            ..net("||t.com^")
        };
        assert_eq!(
            drop_reason(std::slice::from_ref(&strict), V15),
            ["dnr:strict-party"]
        );
        let widened = NetworkRule {
            party: Party::StrictThird,
            types: RT::SCRIPT,
            ..exc("@@||t.com^")
        };
        check(
            std::slice::from_ref(&widened),
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?t\\.com[^a-zA-Z0-9_.%-]","resource-type":["script"],"load-type":["third-party"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
    }

    #[test]
    fn match_case_sets_case_sensitive_flag() {
        check(
            &[NetworkRule {
                match_case: true,
                types: RT::SCRIPT,
                ..net("/Ads[0-9]+\\.js/")
            }],
            V15,
            r#"[{"trigger":{"url-filter":"Ads[0-9]+\\.js","url-filter-is-case-sensitive":true,"resource-type":["script"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn important_block_uses_its_own_tier() {
        let rule = NetworkRule {
            important: true,
            types: RT::SCRIPT,
            ..net("||x.com^")
        };
        let out = check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?x\\.com[^a-zA-Z0-9_.%-]","resource-type":["script"]},"action":{"type":"block"}}]"#,
        );
        assert_eq!(tiers(&out), [Tier::ImportantBlock]);
    }

    #[test]
    fn exception_is_ignore_previous_at_exception_tier() {
        let out = check(
            &[NetworkRule {
                types: RT::SCRIPT,
                ..exc("@@||x.com^")
            }],
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?x\\.com[^a-zA-Z0-9_.%-]","resource-type":["script"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
        assert_eq!(tiers(&out), [Tier::Exception]);
    }

    #[test]
    fn exception_with_no_types_uses_default_set() {
        let out = check(
            &[exc("@@||x.com/x")],
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?x\\.com/x","resource-type":["image","style-sheet","script","font","media","ping","fetch","websocket","other"]},"action":{"type":"ignore-previous-rules"}},{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?x\\.com/x","resource-type":["document"],"load-context":["child-frame"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
        assert_eq!(tiers(&out), [Tier::Exception, Tier::Exception]);
    }

    #[test]
    fn redirect_block_is_native_and_rule_only_is_dropped() {
        let native = NetworkRule {
            action: NetworkAction::Redirect {
                resource: "noop.js".into(),
                rule_only: false,
            },
            types: RT::SCRIPT,
            ..net("||x.com^")
        };
        check(
            std::slice::from_ref(&native),
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?x\\.com[^a-zA-Z0-9_.%-]","resource-type":["script"]},"action":{"type":"block"}}]"#,
        );
        let rule_only = NetworkRule {
            action: NetworkAction::Redirect {
                resource: "noop.js".into(),
                rule_only: true,
            },
            ..net("||x.com^")
        };
        assert_eq!(
            drop_reason(std::slice::from_ref(&rule_only), V15),
            ["dnr:redirect-rule"]
        );
    }

    #[test]
    fn non_native_actions_are_dropped_including_exceptions() {
        let cases = [
            (
                NetworkAction::RemoveParam(Some("utm_source".into())),
                "dnr:removeparam",
            ),
            (
                NetworkAction::Csp(Some("script-src 'none'".into())),
                "dnr:csp",
            ),
            (
                NetworkAction::Permissions(Some("camera=()".into())),
                "dnr:permissions",
            ),
            (
                NetworkAction::Other {
                    option: "urlskip".into(),
                    value: Some("x".into()),
                },
                "dnr:urlskip",
            ),
        ];
        for (action, reason) in cases {
            let block = NetworkRule {
                action: action.clone(),
                ..net("||x.com^")
            };
            let except = NetworkRule {
                action,
                ..exc("@@||x.com^")
            };
            assert_eq!(drop_reason(std::slice::from_ref(&block), V15), [reason]);
            assert_eq!(drop_reason(std::slice::from_ref(&except), V15), [reason]);
        }
    }

    #[test]
    fn domain_include_becomes_if_domain_with_subdomains() {
        check(
            &[NetworkRule {
                from: list(&["a.com", "b.org"], &[]),
                types: RT::SCRIPT,
                ..net("||t.com^")
            }],
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?t\\.com[^a-zA-Z0-9_.%-]","resource-type":["script"],"if-domain":["*a.com","*b.org"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn domain_exclude_becomes_unless_domain() {
        check(
            &[NetworkRule {
                from: list(&[], &["a.com"]),
                types: RT::SCRIPT,
                ..net("||t.com^")
            }],
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?t\\.com[^a-zA-Z0-9_.%-]","resource-type":["script"],"unless-domain":["*a.com"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn include_plus_exclude_drops_block_and_widens_exception() {
        let block = NetworkRule {
            from: list(&["a.com"], &["b.a.com"]),
            types: RT::SCRIPT,
            ..net("||t.com^")
        };
        assert_eq!(
            drop_reason(std::slice::from_ref(&block), V15),
            ["dnr:domain"]
        );
        let except = NetworkRule {
            from: list(&["a.com"], &["b.a.com"]),
            types: RT::SCRIPT,
            ..exc("@@||t.com^")
        };
        check(
            std::slice::from_ref(&except),
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?t\\.com[^a-zA-Z0-9_.%-]","resource-type":["script"],"if-domain":["*a.com"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
    }

    #[test]
    fn entity_domain_uses_if_top_url() {
        let rule = NetworkRule {
            from: DomainList {
                include: vec![DomainMatcher::Entity("google".into())],
                exclude: vec![],
            },
            types: RT::SCRIPT,
            ..net("||t.com^")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?t\\.com[^a-zA-Z0-9_.%-]","resource-type":["script"],"if-top-url":["^[^:]+://+([^:/]+\\.)?google\\.([^:/.]+\\.)?[^:/.]+[/:?#]"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn mixed_include_splits_into_two_triggers() {
        let rule = NetworkRule {
            from: DomainList {
                include: vec![
                    DomainMatcher::Hostname("a.com".into()),
                    DomainMatcher::Entity("google".into()),
                ],
                exclude: vec![],
            },
            types: RT::SCRIPT,
            ..net("||t.com^")
        };
        let (out, _) = run(std::slice::from_ref(&rule), V15);
        assert_eq!(out.len(), 2);
        assert!(json(&out).contains(r#""if-domain":["*a.com"]"#));
        assert!(json(&out).contains(r#""if-top-url":["#));
    }

    #[test]
    fn entity_domains_are_gated_by_version() {
        let rule = NetworkRule {
            from: DomainList {
                include: vec![DomainMatcher::Entity("google".into())],
                exclude: vec![],
            },
            types: RT::SCRIPT,
            ..net("||t.com^")
        };
        assert_eq!(
            drop_reason(std::slice::from_ref(&rule), V14),
            ["dnr:domain"]
        );
    }

    #[test]
    fn regex_domain_include_uses_if_top_url() {
        let rule = NetworkRule {
            from: DomainList {
                include: vec![DomainMatcher::Regex("^ads\\d+".into())],
                exclude: vec![],
            },
            types: RT::SCRIPT,
            ..net("||t.com^")
        };
        let (out, stats) = run(std::slice::from_ref(&rule), V15);
        assert!(stats.dropped.is_empty());
        assert!(
            json(&out).contains(r#""if-top-url":["^[^:]+://ads[0-9]+[^/:?#]*[/:?#]"]"#),
            "{}",
            json(&out)
        );
    }

    #[test]
    fn regex_domain_that_cannot_translate_drops_the_block() {
        let rule = NetworkRule {
            from: DomainList {
                include: vec![DomainMatcher::Regex("a|b".into())],
                exclude: vec![],
            },
            types: RT::SCRIPT,
            ..net("||t.com^")
        };
        assert_eq!(
            drop_reason(std::slice::from_ref(&rule), V15),
            ["dnr:domain"]
        );
    }

    #[test]
    fn exception_with_unconvertible_domain_widens_to_no_condition() {
        let rule = NetworkRule {
            from: DomainList {
                include: vec![DomainMatcher::Regex("a|b".into())],
                exclude: vec![],
            },
            types: RT::SCRIPT,
            ..exc("@@||t.com^")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?t\\.com[^a-zA-Z0-9_.%-]","resource-type":["script"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
    }

    #[test]
    fn to_hostnames_fold_into_url_filters() {
        let rule = NetworkRule {
            to: DomainList {
                include: hosts(&["tracker.com", "t2.net"]),
                exclude: vec![],
            },
            types: RT::SCRIPT,
            ..net("*")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?tracker\\.com[^a-zA-Z0-9_.%-]","resource-type":["script"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?t2\\.net[^a-zA-Z0-9_.%-]","resource-type":["script"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn to_with_a_specific_pattern_is_dropped_for_blocks() {
        let rule = NetworkRule {
            to: list(&["tracker.com"], &[]),
            ..net("/ads/")
        };
        assert_eq!(drop_reason(std::slice::from_ref(&rule), V15), ["dnr:to"]);
        let except = NetworkRule {
            to: list(&["tracker.com"], &[]),
            types: RT::SCRIPT,
            ..exc("@@/ads/")
        };
        check(
            std::slice::from_ref(&except),
            V15,
            r#"[{"trigger":{"url-filter":"ads","resource-type":["script"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
    }

    #[test]
    fn denyallow_method_and_runtime_options_drop_blocks() {
        let deny = NetworkRule {
            denyallow: vec!["cdn.com".into()],
            ..net("||x.com^")
        };
        assert_eq!(
            drop_reason(std::slice::from_ref(&deny), V15),
            ["dnr:denyallow"]
        );
        let method = NetworkRule {
            method: MethodList {
                include: vec!["POST".into()],
                exclude: vec![],
            },
            ..net("||x.com^")
        };
        assert_eq!(
            drop_reason(std::slice::from_ref(&method), V15),
            ["dnr:method"]
        );
        let runtime = NetworkRule {
            runtime_only_options: vec!["cname".into()],
            ..net("||x.com^")
        };
        assert_eq!(
            drop_reason(std::slice::from_ref(&runtime), V15),
            ["dnr:runtime-option"]
        );
    }

    #[test]
    fn exceptions_ignore_denyallow_method_and_runtime_options() {
        let rules = [
            NetworkRule {
                denyallow: vec!["cdn.com".into()],
                types: RT::SCRIPT,
                ..exc("@@||x.com^")
            },
            NetworkRule {
                method: MethodList {
                    include: vec!["POST".into()],
                    exclude: vec![],
                },
                types: RT::SCRIPT,
                ..exc("@@||x.com^")
            },
            NetworkRule {
                runtime_only_options: vec!["ipaddress".into()],
                types: RT::SCRIPT,
                ..exc("@@||x.com^")
            },
        ];
        let (out, stats) = run(&rules, V15);
        assert!(stats.dropped.is_empty());
        // The three exceptions differ only in options that are ignored, so
        // they collapse to one rule.
        assert_eq!(out.len(), 1);
    }

    #[test]
    fn cname_exception_lifts_nothing() {
        let cname = NetworkRule {
            runtime_only_options: vec!["cname".into()],
            ..exc("@@||google.*^")
        };
        let (out, stats) = run(&[net("||mail-ads.google.com^"), cname], V15);
        assert_eq!(out.len(), 1);
        assert_eq!(stats.dropped.get("dnr:cname-exception"), Some(&1));
    }

    #[test]
    fn host_only_pattern_as_page_condition_for_document_exception() {
        let rule = NetworkRule {
            scope: ExceptionScope::DOC,
            ..exc("@@||example.org^$document")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":".*","if-domain":["*example.org"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
        let out = run(std::slice::from_ref(&rule), V15).0;
        assert_eq!(tiers(&out), [Tier::DocumentException]);
    }

    #[test]
    fn document_exception_without_pattern_matches_everything() {
        let rule = NetworkRule {
            scope: ExceptionScope::DOC,
            ..exc("@@$document")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":".*"},"action":{"type":"ignore-previous-rules"}}]"#,
        );
    }

    #[test]
    fn document_exception_with_path_uses_if_top_url() {
        let rule = NetworkRule {
            scope: ExceptionScope::DOC,
            ..exc("@@||example.org/news^$document")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":".*","if-top-url":["^[^:]+://+([^:/]+\\.)?example\\.org/news[^a-zA-Z0-9_.%-]"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
    }

    #[test]
    fn generichide_exception_uses_generic_hide_tier() {
        let rule = NetworkRule {
            scope: ExceptionScope::GHIDE,
            ..exc("@@||example.org^$generichide")
        };
        let out = check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":".*","if-domain":["*example.org"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
        assert_eq!(tiers(&out), [Tier::GenericHideException]);
    }

    #[test]
    fn elemhide_and_specifichide_use_elemhide_tier() {
        for scope in [ExceptionScope::EHIDE, ExceptionScope::SHIDE] {
            let rule = NetworkRule {
                scope,
                ..exc("@@||example.org^$elemhide")
            };
            let (out, _) = run(std::slice::from_ref(&rule), V15);
            assert_eq!(tiers(&out), [Tier::ElemHideException]);
        }
    }

    #[test]
    fn page_exception_with_regex_pattern_on_safari_14_widens() {
        let rule = NetworkRule {
            scope: ExceptionScope::GHIDE,
            ..exc("@@/news/$generichide")
        };
        check(
            std::slice::from_ref(&rule),
            V14,
            r#"[{"trigger":{"url-filter":".*"},"action":{"type":"ignore-previous-rules"}}]"#,
        );
    }

    #[test]
    fn genericblock_and_scoped_blocks_are_dropped() {
        let genericblock = NetworkRule {
            scope: ExceptionScope::GENERICBLOCK,
            ..exc("@@||x.com^$genericblock")
        };
        assert_eq!(
            drop_reason(std::slice::from_ref(&genericblock), V15),
            ["dnr:genericblock"]
        );
        let scoped = NetworkRule {
            scope: ExceptionScope::GHIDE,
            ..net("||x.com^$generichide")
        };
        assert_eq!(
            drop_reason(std::slice::from_ref(&scoped), V15),
            ["dnr:scope-on-block"]
        );
    }

    #[test]
    fn badfilter_cancels_identical_filter_only() {
        let block = NetworkRule {
            types: RT::SCRIPT,
            ..net("||ads.com^")
        };
        let bad = NetworkRule {
            badfilter: true,
            types: RT::SCRIPT,
            ..net("||ads.com^")
        };
        let rules = [
            NetworkRule {
                types: RT::SCRIPT,
                ..net("||ads.com^")
            },
            bad.clone(),
            block,
        ];
        let (out, stats) = run(&rules, V15);
        assert!(out.is_empty());
        assert!(stats.dropped.is_empty());
        let other = NetworkRule {
            types: RT::IMAGE,
            ..net("||ads.com^")
        };
        let (out, _) = run(&[other, bad], V15);
        assert_eq!(out.len(), 1);
    }

    #[test]
    fn badfilter_is_global_and_respects_exception_flag() {
        let bad = NetworkRule {
            badfilter: true,
            types: RT::SCRIPT,
            ..exc("@@||ads.com^")
        };
        let rules = [
            NetworkRule {
                types: RT::SCRIPT,
                ..net("||ads.com^")
            },
            NetworkRule {
                types: RT::SCRIPT,
                ..exc("@@||ads.com^")
            },
            bad,
        ];
        let (out, _) = run(&rules, V15);
        assert_eq!(out.len(), 1);
        assert_eq!(tiers(&out), [Tier::Block]);
    }

    #[test]
    fn identical_rules_are_deduplicated() {
        let rule = NetworkRule {
            types: RT::SCRIPT,
            ..net("||x.com^")
        };
        let (out, _) = run(&[rule.clone(), rule], V15);
        assert_eq!(out.len(), 1);
    }

    #[test]
    fn blocks_differing_only_in_if_domain_are_merged() {
        let a = NetworkRule {
            from: list(&["a.com"], &[]),
            types: RT::SCRIPT,
            ..net("||t.com^")
        };
        let b = NetworkRule {
            from: list(&["b.com"], &[]),
            types: RT::SCRIPT,
            ..net("||t.com^")
        };
        check(
            &[a, b],
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?t\\.com[^a-zA-Z0-9_.%-]","resource-type":["script"],"if-domain":["*a.com","*b.com"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn merge_keeps_tiers_apart() {
        let block = NetworkRule {
            from: list(&["a.com"], &[]),
            types: RT::SCRIPT,
            ..net("||t.com^")
        };
        let except = NetworkRule {
            from: list(&["b.com"], &[]),
            types: RT::SCRIPT,
            ..exc("@@||t.com^")
        };
        let (out, _) = run(&[block, except], V15);
        assert_eq!(tiers(&out), [Tier::Block, Tier::Exception]);
    }

    #[test]
    fn unsupported_action_and_no_types_on_block_report_reasons() {
        assert_eq!(
            drop_reason(
                &[NetworkRule {
                    types: RT::WEBRTC,
                    ..net("||x.com^")
                }],
                V15
            ),
            ["dnr:type"]
        );
        assert_eq!(
            drop_reason(
                &[NetworkRule {
                    types: RT::FRAME,
                    ..net("||x.com^")
                }],
                V13
            ),
            ["dnr:document-needs-safari-15"]
        );
    }

    #[test]
    fn match_all_pattern_with_no_conditions_is_every_request() {
        check(
            &[NetworkRule {
                types: RT::IMAGE,
                ..net("*")
            }],
            V15,
            r#"[{"trigger":{"url-filter":".*","resource-type":["image"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn left_anchor_and_right_anchor_patterns() {
        check(
            &[NetworkRule {
                types: RT::IMAGE,
                ..net("|https://cdn.com/a.gif|")
            }],
            V15,
            r#"[{"trigger":{"url-filter":"^https://cdn\\.com/a\\.gif$","resource-type":["image"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn separator_and_wildcard_patterns() {
        check(
            &[NetworkRule {
                types: RT::IMAGE,
                ..net("banner^*.gif")
            }],
            V15,
            r#"[{"trigger":{"url-filter":"banner[^a-zA-Z0-9_.%-].*\\.gif","resource-type":["image"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn untranslatable_regex_drops_block_and_widens_exception() {
        let block = NetworkRule {
            types: RT::SCRIPT,
            ..net("/a\\d+|b/")
        };
        assert_eq!(
            drop_reason(std::slice::from_ref(&block), V15),
            ["dnr:url-filter"]
        );
        let except = NetworkRule {
            types: RT::SCRIPT,
            ..exc("@@/a\\d+|b/")
        };
        check(
            std::slice::from_ref(&except),
            V15,
            r#"[{"trigger":{"url-filter":".*","resource-type":["script"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
    }

    #[test]
    fn regex_pattern_translates_digit_class() {
        check(
            &[NetworkRule {
                types: RT::SCRIPT,
                ..net("/ads\\d{2}\\.js/")
            }],
            V15,
            r#"[{"trigger":{"url-filter":"ads[0-9][0-9]\\.js","resource-type":["script"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn tiers_follow_block_important_and_exception_order() {
        let rules = [
            net("||x.com/a"),
            NetworkRule {
                important: true,
                ..net("||y.com/a")
            },
            exc("@@||x.com/ok^"),
        ];
        let (out, _) = run(&rules, V15);
        assert_eq!(
            tiers(&out),
            [
                Tier::Block,
                Tier::Block,
                Tier::ImportantBlock,
                Tier::ImportantBlock,
                Tier::Exception,
                Tier::Exception
            ]
        );
    }

    #[test]
    fn same_rule_on_safari_26_matches_15() {
        let rule = NetworkRule {
            types: RT::SCRIPT,
            ..net("||x.com^")
        };
        let (a, _) = run(std::slice::from_ref(&rule), V15);
        let (b, _) = run(std::slice::from_ref(&rule), V26);
        assert_eq!(json(&a), json(&b));
    }

    #[test]
    fn entity_exclude_on_block_uses_unless_top_url() {
        let rule = NetworkRule {
            from: DomainList {
                include: vec![],
                exclude: vec![DomainMatcher::Entity("google".into())],
            },
            types: RT::SCRIPT,
            ..net("||t.com^")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?t\\.com[^a-zA-Z0-9_.%-]","resource-type":["script"],"unless-top-url":["^[^:]+://+([^:/]+\\.)?google\\.([^:/.]+\\.)?[^:/.]+[/:?#]"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn exception_with_left_anchor_and_match_case() {
        let rule = NetworkRule {
            match_case: true,
            types: RT::IMAGE,
            ..exc("@@|https://cdn.net/ok.gif")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":"^https://cdn\\.net/ok\\.gif","url-filter-is-case-sensitive":true,"resource-type":["image"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
    }

    #[test]
    fn exception_to_redirect_is_ignore_previous() {
        let rule = NetworkRule {
            action: NetworkAction::Redirect {
                resource: "noop.js".into(),
                rule_only: false,
            },
            types: RT::SCRIPT,
            ..exc("@@||x.com^")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?x\\.com[^a-zA-Z0-9_.%-]","resource-type":["script"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
    }

    #[test]
    fn exception_with_denyallow_drops_only_the_option() {
        let rule = NetworkRule {
            denyallow: vec!["cdn.com".into()],
            types: RT::IMAGE,
            ..exc("@@||x.com^")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?x\\.com[^a-zA-Z0-9_.%-]","resource-type":["image"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
    }

    #[test]
    fn exception_to_a_block_domain_with_exclude_widens_to_include() {
        let rule = NetworkRule {
            from: list(&["a.com"], &["b.a.com"]),
            types: RT::IMAGE,
            ..exc("@@||x.com^")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?x\\.com[^a-zA-Z0-9_.%-]","resource-type":["image"],"if-domain":["*a.com"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
    }

    #[test]
    fn subdocument_exception_on_safari_14_is_a_no_op() {
        let rule = NetworkRule {
            types: RT::FRAME,
            ..exc("@@||x.com^")
        };
        let (out, stats) = run(std::slice::from_ref(&rule), V14);
        assert!(out.is_empty());
        assert!(stats.dropped.is_empty());
    }

    #[test]
    fn ping_default_block_on_safari_13_skips_ping() {
        let rule = NetworkRule {
            types: RT::PING | RT::IMAGE,
            ..net("||x.com^")
        };
        check(
            std::slice::from_ref(&rule),
            V13,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?x\\.com[^a-zA-Z0-9_.%-]","resource-type":["image"]},"action":{"type":"block"}}]"#,
        );
    }

    #[test]
    fn important_exception_ordering_against_block() {
        let rules = [
            NetworkRule {
                types: RT::SCRIPT,
                ..net("||x.com^")
            },
            NetworkRule {
                types: RT::SCRIPT,
                ..exc("@@||x.com/ok^")
            },
            NetworkRule {
                types: RT::SCRIPT,
                important: true,
                ..net("||x.com/bad^")
            },
        ];
        let out = check(
            &rules,
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?x\\.com[^a-zA-Z0-9_.%-]","resource-type":["script"]},"action":{"type":"block"}},{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?x\\.com/ok[^a-zA-Z0-9_.%-]","resource-type":["script"]},"action":{"type":"ignore-previous-rules"}},{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?x\\.com/bad[^a-zA-Z0-9_.%-]","resource-type":["script"]},"action":{"type":"block"}}]"#,
        );
        assert_eq!(
            tiers(&out),
            [Tier::Block, Tier::Exception, Tier::ImportantBlock]
        );
    }

    #[test]
    fn document_block_on_safari_14_is_dropped() {
        let rule = NetworkRule {
            types: RT::DOC,
            ..net("||x.com^")
        };
        assert_eq!(
            drop_reason(std::slice::from_ref(&rule), V14),
            ["dnr:document-needs-safari-15"]
        );
    }

    #[test]
    fn third_party_exception_keeps_load_type() {
        let rule = NetworkRule {
            party: Party::Third,
            types: RT::IMAGE,
            ..exc("@@||x.com^")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?x\\.com[^a-zA-Z0-9_.%-]","resource-type":["image"],"load-type":["third-party"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
    }

    #[test]
    fn exception_with_negated_type_drops_it_from_default() {
        let rule = NetworkRule {
            negated_types: RT::FRAME | RT::XHR,
            ..exc("@@||x.com^")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?x\\.com[^a-zA-Z0-9_.%-]","resource-type":["image","style-sheet","script","font","media","ping","websocket","other"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
    }

    #[test]
    fn all_types_exception_keeps_documents_in_one_trigger() {
        let rule = NetworkRule {
            types: RT::all(),
            ..exc("@@||x.com^")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?x\\.com[^a-zA-Z0-9_.%-]","resource-type":["document","image","style-sheet","script","font","media","ping","fetch","websocket","other"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
    }

    #[test]
    fn document_exception_with_domain_list_uses_if_domain() {
        let rule = NetworkRule {
            scope: ExceptionScope::DOC,
            from: list(&["news.com"], &[]),
            ..exc("@@$document")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":".*","if-domain":["*news.com"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
    }

    #[test]
    fn generichide_exception_with_entity_uses_if_top_url() {
        let rule = NetworkRule {
            scope: ExceptionScope::GHIDE,
            from: DomainList {
                include: vec![DomainMatcher::Entity("google".into())],
                exclude: vec![],
            },
            ..exc("@@$generichide")
        };
        check(
            std::slice::from_ref(&rule),
            V15,
            r#"[{"trigger":{"url-filter":".*","if-top-url":["^[^:]+://+([^:/]+\\.)?google\\.([^:/.]+\\.)?[^:/.]+[/:?#]"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
    }

    #[test]
    fn badfilter_leaves_unrelated_exception_in_place() {
        let rules = [
            NetworkRule {
                types: RT::SCRIPT,
                ..exc("@@||x.com^")
            },
            NetworkRule {
                types: RT::SCRIPT,
                badfilter: true,
                ..net("||x.com^")
            },
        ];
        check(
            &rules,
            V15,
            r#"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?x\\.com[^a-zA-Z0-9_.%-]","resource-type":["script"]},"action":{"type":"ignore-previous-rules"}}]"#,
        );
    }

    /// Shapes covering every url-filter, top-url and domain form the compiler
    /// emits, in both block and exception forms.
    fn corpus() -> Vec<NetworkRule> {
        let patterns = [
            "||ads.com^",
            "||ads.com/x^*.js|",
            "|https://cdn.net/a.gif",
            "/banner\\d{2,4}\\.js/",
            "/^(?:ab|cd)$/",
            "ads^",
            "*",
            "||xn--bcher-kva.example^",
            "/a{3}[\\w.-]+(\\/x)?$/",
            "/a|b/",
        ];
        let types = [
            RT::empty(),
            RT::SCRIPT,
            RT::DOC,
            RT::FRAME,
            RT::POPUP,
            RT::IMAGE
                | RT::CSS
                | RT::FONT
                | RT::MEDIA
                | RT::PING
                | RT::XHR
                | RT::OTHER
                | RT::OBJECT
                | RT::WEBSOCKET,
            RT::all(),
        ];
        let domains = [
            DomainList::default(),
            list(&["a.com", "b.org"], &[]),
            list(&[], &["a.com"]),
            list(&["a.com"], &["b.a.com"]),
            DomainList {
                include: vec![DomainMatcher::Entity("google".into())],
                exclude: vec![],
            },
            DomainList {
                include: vec![DomainMatcher::Regex("^ads\\d+".into())],
                exclude: vec![],
            },
            DomainList {
                include: vec![],
                exclude: vec![
                    DomainMatcher::Entity("google".into()),
                    DomainMatcher::Regex("cdn$".into()),
                ],
            },
            DomainList {
                include: vec![
                    DomainMatcher::Hostname("a.com".into()),
                    DomainMatcher::Entity("google".into()),
                ],
                exclude: vec![],
            },
        ];
        let mut out = Vec::new();
        for p in patterns {
            for t in &types {
                for d in &domains {
                    for party in [Party::Any, Party::First, Party::Third, Party::StrictFirst] {
                        for exception in [false, true] {
                            for match_case in [false, true] {
                                out.push(NetworkRule {
                                    exception,
                                    match_case,
                                    party,
                                    types: *t,
                                    from: d.clone(),
                                    ..net(p)
                                });
                            }
                        }
                    }
                    for scope in [
                        ExceptionScope::DOC,
                        ExceptionScope::GHIDE,
                        ExceptionScope::EHIDE,
                        ExceptionScope::SHIDE,
                    ] {
                        out.push(NetworkRule {
                            exception: true,
                            scope,
                            from: d.clone(),
                            ..net(p)
                        });
                    }
                }
            }
        }
        out.push(NetworkRule {
            to: list(&["tracker.com"], &[]),
            ..net("*")
        });
        out.push(NetworkRule {
            to: list(&["tracker.com", "t2.net"], &[]),
            types: RT::SCRIPT,
            ..net("*")
        });
        out
    }

    /// Every trigger the corpus produces at every Safari version we gate on is
    /// accepted by the real WebKit compiler (`/tmp/research/bench/wk`). Skipped
    /// when the binary is missing.
    #[test]
    fn webkit_accepts_every_generated_trigger() {
        const WK: &str = "/tmp/research/bench/wk";
        if !std::path::Path::new(WK).exists() {
            eprintln!("skipping: {WK} not found");
            return;
        }
        let mut seen = std::collections::BTreeSet::new();
        for rule in corpus() {
            for v in [V13, V14, V15, V26] {
                for t in run(std::slice::from_ref(&rule), v).0 {
                    seen.insert(to_json(std::slice::from_ref(&t.rule)));
                }
            }
        }
        let body = format!(
            "[{}]",
            seen.iter()
                .map(|r| &r[1..r.len() - 1])
                .collect::<Vec<_>>()
                .join(",")
        );
        let path = std::env::temp_dir().join(format!("wbe-network-wk-{}.json", std::process::id()));
        std::fs::write(&path, body).expect("write rules");
        let output = std::process::Command::new(WK)
            .arg(&path)
            .output()
            .expect("run wk");
        std::fs::remove_file(&path).ok();
        let stdout = String::from_utf8_lossy(&output.stdout);
        assert!(
            stdout.trim_end().ends_with(" ok"),
            "{} distinct rules: {stdout}",
            seen.len()
        );
    }

    #[cfg(not(debug_assertions))]
    #[test]
    fn seventy_five_thousand_rules_compile_quickly() {
        let rules: Vec<NetworkRule> = (0..75_000u32)
            .map(|i| {
                let host = format!("h{}.example", i % 30_000);
                NetworkRule {
                    types: if i % 3 == 0 { RT::SCRIPT } else { RT::empty() },
                    from: if i % 5 == 0 {
                        list(&["site.com"], &[])
                    } else {
                        DomainList::default()
                    },
                    exception: i % 11 == 0,
                    ..net(&format!("||{host}^"))
                }
            })
            .collect();
        let start = std::time::Instant::now();
        let (out, _) = run(&rules, V15);
        let elapsed = start.elapsed();
        assert!(!out.is_empty());
        assert!(elapsed.as_millis() < 100, "75k rules took {elapsed:?}");
    }
}
