//! Cosmetic, scriptlet, and HTML-filter lines, after `normalize::adguard_to_ubo`.
//! Follows uBO's static-filtering-parser.js: the marker is the leftmost
//! `#@?(\$\?|\$|%|\?)?#` followed by a character (`reExtAnchor`), domains are a
//! comma list (`parseDomainList`), `+js()` arguments go through `ArglistParser`,
//! and selectors go through `ExtSelectorCompiler`. uBO's CSS parser (csstree)
//! is replaced by a scanner, so selector validation covers less than uBO's.

use crate::ast::{
    CosmeticBody, CosmeticRule, DomainList, DomainMatcher, ParsedLine, Rule, ScriptletRule,
    SourceRef,
};

/// uBO's `reExtAnchor` markers. `$$` and `$@$` (AdGuard HTML filtering) are
/// checked separately in `find_marker`.
const MARKERS: [&str; 10] = [
    "#@$?#", "#$?#", "#@$#", "#$#", "#@%#", "#%#", "#@?#", "#?#", "#@#", "##",
];

/// uBO's `ExtSelectorCompiler` operator tables.
const PROCEDURAL_OPS: [&str; 16] = [
    "has-text",
    "if",
    "if-not",
    "matches-attr",
    "matches-css",
    "matches-css-after",
    "matches-css-before",
    "matches-media",
    "matches-path",
    "matches-prop",
    "min-text-length",
    "others",
    "shadow",
    "upward",
    "watch-attr",
    "xpath",
];
const ACTION_OPS: [&str; 4] = ["remove", "remove-attr", "remove-class", "style"];

/// uBO's scriptlet registry (src/js/resources/*.js): canonical name without
/// `.js`, and its aliases without `.js`.
pub(crate) const SCRIPTLETS: &[(&str, &[&str])] = &[
    (
        "abort-current-script",
        &["abort-current-inline-script", "acis", "acs"],
    ),
    ("abort-on-property-read", &["aopr"]),
    ("abort-on-property-write", &["aopw"]),
    ("abort-on-stack-trace", &["aost"]),
    (
        "adjust-setInterval",
        &["nano-setInterval-booster", "nano-sib"],
    ),
    (
        "adjust-setTimeout",
        &["nano-setTimeout-booster", "nano-stb"],
    ),
    ("alert-buster", &[]),
    ("break-on-call", &[]),
    ("call-nothrow", &[]),
    ("close-window", &["window-close-if"]),
    ("disable-newtab-links", &[]),
    ("edit-element-object", &[]),
    ("edit-inbound-object", &[]),
    ("edit-object-on-getter", &[]),
    ("edit-object-on-setter", &[]),
    ("edit-outbound-object", &[]),
    ("edit-this-object", &[]),
    ("evaldata-prune", &[]),
    ("freeze-element-property", &[]),
    ("href-sanitizer", &["urlskip"]),
    ("json-edit-fetch-request", &[]),
    ("json-edit-fetch-response", &[]),
    ("json-edit-xhr-request", &[]),
    ("json-edit-xhr-response", &[]),
    ("json-edit", &[]),
    ("json-prune-fetch-response", &[]),
    ("json-prune-xhr-response", &[]),
    ("json-prune", &[]),
    ("jsonl-edit-fetch-response", &[]),
    ("jsonl-edit-xhr-response", &[]),
    ("m3u-prune", &[]),
    ("mpegdash-prune", &[]),
    ("multiup", &[]),
    ("noeval-if", &["prevent-eval-if"]),
    ("nowebrtc", &[]),
    ("overlay-buster", &[]),
    (
        "prevent-addEventListener",
        &["addEventListener-defuser", "aeld"],
    ),
    ("prevent-bab", &["bab-defuser", "nobab"]),
    ("prevent-canvas", &[]),
    ("prevent-clipboard-write", &[]),
    ("prevent-dialog", &[]),
    ("prevent-fetch", &["no-fetch-if"]),
    ("prevent-innerHTML", &[]),
    ("prevent-navigation", &[]),
    ("prevent-refresh", &["refresh-defuser"]),
    (
        "prevent-requestAnimationFrame",
        &["no-requestAnimationFrame-if", "norafif"],
    ),
    (
        "prevent-setInterval",
        &["no-setInterval-if", "nosiif", "setInterval-defuser"],
    ),
    (
        "prevent-setTimeout",
        &["no-setTimeout-if", "nostif", "setTimeout-defuser"],
    ),
    (
        "prevent-window-open",
        &["nowoif", "no-window-open-if", "window.open-defuser"],
    ),
    ("prevent-xhr", &["no-xhr-if"]),
    ("proxy-apply-config", &[]),
    ("remove-attr", &["ra"]),
    ("remove-class", &["rc"]),
    ("remove-cookie", &["cookie-remover"]),
    ("remove-node-text", &["rmnt"]),
    ("set-attr", &[]),
    ("set-constant", &["set"]),
    ("set-cookie-reload", &[]),
    ("set-cookie", &[]),
    ("set-local-storage-item", &[]),
    ("set-session-storage-item", &[]),
    ("spoof-css", &[]),
    ("trusted-click-element", &[]),
    ("trusted-create-html", &[]),
    ("trusted-edit-element-object", &[]),
    ("trusted-edit-inbound-element", &[]),
    ("trusted-edit-inbound-object", &[]),
    ("trusted-edit-object-on-getter", &[]),
    ("trusted-edit-object-on-setter", &[]),
    ("trusted-edit-outbound-object", &[]),
    ("trusted-edit-this-object", &[]),
    ("trusted-json-edit-fetch-request", &[]),
    ("trusted-json-edit-fetch-response", &[]),
    ("trusted-json-edit-xhr-request", &[]),
    ("trusted-json-edit-xhr-response", &[]),
    ("trusted-json-edit", &[]),
    ("trusted-jsonl-edit-fetch-response", &[]),
    ("trusted-jsonl-edit-xhr-response", &[]),
    ("trusted-override-element-method", &[]),
    ("trusted-prevent-dom-bypass", &[]),
    ("trusted-prevent-fetch", &[]),
    ("trusted-prevent-xhr", &[]),
    ("trusted-prune-inbound-object", &[]),
    ("trusted-prune-outbound-object", &[]),
    ("trusted-replace-argument", &[]),
    ("trusted-replace-fetch-response", &["trusted-rpfr"]),
    (
        "trusted-replace-node-text",
        &["trusted-rpnt", "replace-node-text", "rpnt"],
    ),
    ("trusted-replace-outbound-text", &[]),
    ("trusted-replace-xhr-response", &[]),
    ("trusted-set-attr", &[]),
    ("trusted-set-constant", &["trusted-set"]),
    ("trusted-set-cookie-reload", &[]),
    ("trusted-set-cookie", &[]),
    ("trusted-set-local-storage-item", &[]),
    ("trusted-set-session-storage-item", &[]),
    ("trusted-suppress-native-method", &[]),
    ("webrtc-if", &[]),
    ("window.name-defuser", &[]),
    ("xml-prune", &[]),
];

/// Scriptlet name as uBO resolves it: the token without `.js`, matched exactly
/// against canonical names and aliases (`reng.aliases` in redirect-engine.js).
pub(crate) fn scriptlet_name(token: &str) -> Option<&'static str> {
    SCRIPTLETS
        .iter()
        .find(|(name, aliases)| *name == token || aliases.contains(&token))
        .map(|(name, _)| *name)
}

/// uBO's comment test (`reCommentLine`): `# ` or `####`, and lines starting
/// with `!` or `[adblock` (the caller handles `!` and `[`).
pub(crate) fn is_comment(line: &str) -> bool {
    if !line.starts_with('#') {
        return false;
    }
    line == "#"
        || line.starts_with("####")
        || line.as_bytes()[1..]
            .first()
            .is_some_and(u8::is_ascii_whitespace)
}

/// `raw` with its domain prefix rewritten to `domains`, so the runtime engine
/// sees the scope a rule was narrowed to.
pub(crate) fn with_domains(raw: &str, domains: &DomainList) -> String {
    let at = find_marker(raw).map_or(0, |(at, _)| at);
    let one = |m: &DomainMatcher| match m {
        DomainMatcher::Hostname(h) => h.clone(),
        DomainMatcher::Entity(e) => format!("{e}.*"),
        DomainMatcher::Regex(r) => format!("/{r}/"),
    };
    let mut parts: Vec<String> = domains.include.iter().map(one).collect();
    parts.extend(domains.exclude.iter().map(|m| format!("~{}", one(m))));
    format!("{}{}", parts.join(","), &raw[at..])
}

/// Leftmost cosmetic marker and its byte offset. The marker needs at least one
/// character after it (uBO's `.{1,2}` in `reExtAnchor`). An HTML marker only
/// counts when the text before it looks like a domain list.
pub(crate) fn find_marker(line: &str) -> Option<(usize, &'static str)> {
    for (i, c) in line.bytes().enumerate() {
        // Markers start with an ASCII byte, so `i` is a char boundary.
        let rest = match c {
            b'#' | b'$' => &line[i..],
            _ => continue,
        };
        if c == b'#' {
            if let Some(m) = MARKERS
                .iter()
                .find(|m| rest.starts_with(**m) && rest.len() > m.len())
            {
                return Some((i, m));
            }
        } else if !line[..i].contains(['/', '|', '^', ' ', '\t']) {
            if let Some(m) = ["$$", "$@$"]
                .into_iter()
                .find(|m| rest.starts_with(*m) && rest.len() > m.len())
            {
                return Some((i, m));
            }
        }
    }
    None
}

/// Parse a cosmetic, scriptlet, or HTML-filter line. Returns `None` when the
/// line has no cosmetic marker (`##`, `#@#`, `#?#`, `#$#`, `#%#`, `##^`, ...),
/// so the caller treats it as a network filter.
pub(super) fn parse(line: &str, source: SourceRef) -> Option<ParsedLine> {
    if is_comment(line) {
        return Some(ParsedLine::Ignored);
    }
    let Some((at, marker)) = find_marker(line) else {
        return line.starts_with('#').then_some(ParsedLine::Ignored);
    };
    let exception = marker.starts_with("#@") || marker.starts_with("$@");
    let domains = match parse_domains(&line[..at]) {
        Ok(domains) => domains,
        Err(reject) => return Some(reject.into()),
    };
    let body = &line[at + marker.len()..];
    match marker {
        "$$" | "$@$" => return Some(unsupported("AdGuard HTML filtering")),
        "#%#" | "#@%#" if body.starts_with("//scriptlet(") => {
            return Some(unsupported("AdGuard scriptlet without a uBO equivalent"));
        }
        "#%#" | "#@%#" => return Some(unsupported("AdGuard JavaScript injection")),
        "#$#" | "#$?#" | "#@$#" | "#@$?#" => {
            return Some(unsupported("AdGuard CSS injection or ABP snippet"));
        }
        _ => {}
    }
    if let Some(inner) = body.strip_prefix("+js(").and_then(|s| s.strip_suffix(')')) {
        return Some(scriptlet(inner, exception, domains, source, line));
    }
    if body.starts_with("^responseheader(") {
        return Some(unsupported("response header filtering"));
    }
    if body.starts_with('^') {
        return Some(unsupported("HTML filtering"));
    }
    let (matches_path, selector) = split_matches_path(body.trim());
    let body = match classify(selector) {
        Ok(Kind::Plain) => CosmeticBody::Hide(selector.to_string()),
        Ok(Kind::Procedural) => {
            // uBO rejects generic procedural and action filters unless
            // `allowGenericProceduralFilters` is set; generic exceptions are fine.
            if domains.include.is_empty() && !exception {
                return Some(invalid("generic procedural or action filter"));
            }
            CosmeticBody::Procedural(selector.to_string())
        }
        Err(reason) => return Some(invalid(reason)),
    };
    Some(ParsedLine::Rule(Rule::Cosmetic(CosmeticRule {
        source,
        raw: line.to_string(),
        exception,
        domains,
        matches_path,
        body,
    })))
}

fn invalid(reason: impl Into<String>) -> ParsedLine {
    ParsedLine::Invalid {
        reason: reason.into(),
    }
}

fn unsupported(reason: impl Into<String>) -> ParsedLine {
    ParsedLine::Unsupported {
        reason: reason.into(),
    }
}

fn scriptlet(
    inner: &str,
    exception: bool,
    domains: DomainList,
    source: SourceRef,
    raw: &str,
) -> ParsedLine {
    let Some((token, args)) = split_args(inner, false) else {
        return invalid("malformed scriptlet arguments");
    };
    let name = if token.is_empty() {
        ""
    } else {
        match scriptlet_name(&token) {
            Some(name) => name,
            None => return unsupported(format!("unknown scriptlet '{token}'")),
        }
    };
    // uBO drops a non-exception with an empty name and only exceptions may
    // leave the name empty (`#@#+js()` disables all scriptlets on the domains).
    if name.is_empty() && (!exception || !args.is_empty()) {
        return invalid("scriptlet without a name");
    }
    if is_youtube_reload_workaround(name, &args) {
        return unsupported("YouTube reload workaround that misfires in Safari");
    }
    ParsedLine::Rule(Rule::Scriptlet(ScriptletRule {
        source,
        raw: raw.to_string(),
        exception,
        domains,
        name: name.to_string(),
        args,
    }))
}

/// uBO's YouTube workaround for server-side ad insertion: it reloads the video
/// with a disguised user agent when it thinks an ad was stitched in, and the
/// inbound-object edits tag the requests for it. In Safari it fires on plain
/// loads too, so every video restarts two or three times before it plays.
fn is_youtube_reload_workaround(name: &str, args: &[String]) -> bool {
    match name {
        "trusted-replace-node-text" => args.iter().any(|a| a.contains("loadVideoById")),
        "trusted-edit-inbound-object" => args.iter().any(|a| a.contains("attestationRequest")),
        _ => false,
    }
}

/// uBO's `ArglistParser`, reading one argument from `s` at `beg`. Arguments
/// are separated by `,`, or by the closing quote when they start with one.
#[derive(Clone, Copy)]
pub(crate) struct Arg {
    pub beg: usize,
    pub end: usize,
    /// Position after the separator (or the end of `s`).
    pub sep_end: usize,
    /// The argument holds escaped separators and needs `normalize_arg`.
    pub transform: bool,
    /// Unquoted while the caller requires quotes.
    pub failed: bool,
    sep: u8,
}

pub(crate) fn next_arg(s: &str, beg: usize, must_quote: bool) -> Arg {
    let b = s.as_bytes();
    let len = b.len();
    let quote_beg = beg + left_ws(&s[beg..]);
    let qc = b.get(quote_beg).copied().unwrap_or(0);
    if matches!(qc, b'"' | b'\'' | b'`') {
        let (arg_end, transform) = scan_separator(b, quote_beg + 1, qc);
        if arg_end != len {
            let mut sep_end = arg_end + 1;
            sep_end += left_ws(&s[sep_end..]);
            if sep_end == len {
                return Arg {
                    beg: quote_beg + 1,
                    end: arg_end,
                    sep_end,
                    transform,
                    failed: false,
                    sep: qc,
                };
            }
            if b[sep_end] == b',' {
                return Arg {
                    beg: quote_beg + 1,
                    end: arg_end,
                    sep_end: sep_end + 1,
                    transform,
                    failed: false,
                    sep: qc,
                };
            }
        }
    }
    let (arg_end, transform) = scan_separator(b, quote_beg, b',');
    let sep_end = if arg_end < len { arg_end + 1 } else { arg_end };
    let end = arg_end - right_ws(&s[..arg_end]);
    Arg {
        beg: quote_beg,
        end,
        sep_end,
        transform,
        failed: must_quote,
        sep: b',',
    }
}

/// Index of the next `sep` not escaped by an odd run of backslashes.
fn scan_separator(b: &[u8], from: usize, sep: u8) -> (usize, bool) {
    let mut at = from;
    let mut transform = false;
    while at < b.len() {
        let Some(pos) = b[at..].iter().position(|&c| c == sep).map(|p| p + at) else {
            return (b.len(), transform);
        };
        let backslashes = b[..pos].iter().rev().take_while(|&&c| c == b'\\').count();
        if backslashes % 2 == 0 {
            return (pos, transform);
        }
        transform = true;
        at = pos + 1;
    }
    (at, transform)
}

/// uBO's `ArglistParser.normalizeArg`: drops one backslash in front of each
/// escaped `sep`.
fn normalize_arg(s: &str, sep: u8) -> String {
    let mut s = s;
    let mut out = String::new();
    while let Some(pos) = s.bytes().rposition(|c| c == sep) {
        out.insert_str(0, &s[pos..]);
        s = &s[..pos];
        let n = s.bytes().rev().take_while(|&c| c == b'\\').count();
        if n > 0 {
            let keep = if n % 2 == 1 { n - 1 } else { n };
            out.insert_str(0, &s[s.len() - n..s.len() - n + keep]);
            s = &s[..s.len() - n];
        }
    }
    s.to_string() + &out
}

fn value(s: &str, arg: Arg) -> String {
    let raw = s.get(arg.beg..arg.end).unwrap_or("");
    if arg.transform {
        normalize_arg(raw, arg.sep)
    } else {
        raw.to_string()
    }
}

/// Token (without `.js`) and arguments of an argument list, as uBO's
/// `getScriptletArgs` returns them. `must_quote` is AdGuard's flavor, where
/// every argument has to be quoted. `None` when an argument is unquoted there.
pub(crate) fn split_args(s: &str, must_quote: bool) -> Option<(String, Vec<String>)> {
    let first = next_arg(s, 0, must_quote);
    if first.failed {
        return None;
    }
    let token = s.get(first.beg..first.end).unwrap_or("");
    let token = token.strip_suffix(".js").unwrap_or(token).to_string();
    let rest = &s[first.sep_end.min(s.len())..];
    let mut args = Vec::new();
    let mut i = 0;
    while i != rest.len() {
        let arg = next_arg(rest, i, must_quote);
        if arg.failed {
            return None;
        }
        args.push(value(rest, arg));
        i = arg.sep_end;
    }
    Some((token, args))
}

fn left_ws(s: &str) -> usize {
    s.len() - s.trim_start().len()
}

fn right_ws(s: &str) -> usize {
    s.len() - s.trim_end().len()
}

/// Why a domain list was rejected: uBO's error or its unsupported-but-valid case.
enum Reject {
    Invalid(String),
    Unsupported(&'static str),
}

impl From<Reject> for ParsedLine {
    fn from(reject: Reject) -> Self {
        match reject {
            Reject::Invalid(reason) => invalid(reason),
            Reject::Unsupported(reason) => unsupported(reason),
        }
    }
}

/// uBO's `parseDomainList` with the ext-list flags: `,` separated, `~` to
/// exclude, `google.*` entities, `/regex/` (and `[$domain=/regex/]`).
fn parse_domains(list: &str) -> Result<DomainList, Reject> {
    let mut out = DomainList::default();
    let mut rest = list;
    if list.is_empty() {
        return Ok(out);
    }
    loop {
        let (entry, next) = take_entry(rest);
        let (negated, matcher) = parse_domain(entry)?;
        if negated {
            out.exclude.push(matcher);
        } else {
            out.include.push(matcher);
        }
        match next {
            Some(r) => rest = r,
            None => return Ok(out.without_unreachable_excludes()),
        }
    }
}

/// One domain-list entry and the rest after its separator. A regex entry runs
/// to a `/` followed by `,` or the end, so it may contain commas.
fn take_entry(s: &str) -> (&str, Option<&str>) {
    let body = s.strip_prefix('~').unwrap_or(s);
    let is_regex = body.starts_with('/') || body.starts_with("[$domain=/");
    let end = if is_regex {
        let close = if body.starts_with('/') { "/" } else { "/]" };
        let from = s.len() - body.len() + if body.starts_with('/') { 1 } else { 10 };
        let mut at = from;
        loop {
            match s[at..].find(close) {
                None => break s.len(),
                Some(p) => {
                    let after = at + p + close.len();
                    if after == s.len() || s.as_bytes()[after] == b',' {
                        break after;
                    }
                    at = after;
                }
            }
        }
    } else {
        s.find(',').unwrap_or(s.len())
    };
    let next = s
        .get(end + 1..)
        .filter(|_| s.as_bytes().get(end) == Some(&b','));
    (&s[..end], next)
}

fn parse_domain(entry: &str) -> Result<(bool, DomainMatcher), Reject> {
    let (negated, p) = match entry.strip_prefix('~') {
        Some(p) => (true, p),
        None => (false, entry),
    };
    if p.is_empty() {
        return Err(Reject::Invalid("empty domain".into()));
    }
    if let Some(re) = p
        .strip_prefix("[$domain=/")
        .and_then(|r| r.strip_suffix("/]"))
    {
        return Ok((negated, DomainMatcher::Regex(re.to_string())));
    }
    if p.starts_with('/') {
        return match p.strip_prefix('/').and_then(|r| r.strip_suffix('/')) {
            Some(re) if !re.is_empty() => Ok((negated, DomainMatcher::Regex(re.to_string()))),
            _ => Err(Reject::Invalid("unterminated domain regex".into())),
        };
    }
    if p.contains(">>") || p.contains('/') {
        let host = p.split(['/', '>']).next().unwrap_or(p);
        return match hostname(host) {
            Some(_) => Err(Reject::Unsupported("domain ancestor or path")),
            None => Err(Reject::Invalid(format!("bad domain '{p}'"))),
        };
    }
    if p == "*" {
        return Err(Reject::Unsupported("wildcard domain"));
    }
    if let Some(entity) = p.strip_suffix(".*") {
        return match hostname(entity) {
            Some(e) => Ok((negated, DomainMatcher::Entity(e))),
            None => Err(Reject::Invalid(format!("bad entity '{p}'"))),
        };
    }
    match hostname(p) {
        Some(h) => Ok((negated, DomainMatcher::Hostname(h))),
        None => Err(Reject::Invalid(format!("bad domain '{p}'"))),
    }
}

/// Lowercase, punycode-encoded hostname, or `None` when uBO would reject it.
fn hostname(s: &str) -> Option<String> {
    let lower = if s.is_ascii() {
        s.to_ascii_lowercase()
    } else {
        idna::domain_to_ascii(s).ok()?
    };
    let valid = !lower.is_empty()
        && lower.split('.').all(|label| {
            !label.is_empty()
                && label
                    .bytes()
                    .all(|c| c.is_ascii_alphanumeric() || c == b'-' || c == b'_')
        });
    valid.then_some(lower)
}

/// `:matches-path(...)` at the start or the end of a selector.
fn split_matches_path(sel: &str) -> (Option<String>, &str) {
    const OP: &str = ":matches-path(";
    if sel.starts_with(OP) {
        if let Ok(close) = find_close(sel.as_bytes(), OP.len() - 1) {
            return (
                Some(sel[OP.len()..close].to_string()),
                sel[close + 1..].trim_start(),
            );
        }
    }
    if sel.ends_with(')') {
        if let Some(at) = sel.rfind(OP) {
            let open = at + OP.len() - 1;
            if find_close(sel.as_bytes(), open) == Ok(sel.len() - 1) {
                return (
                    Some(sel[open + 1..sel.len() - 1].to_string()),
                    sel[..at].trim_end(),
                );
            }
        }
    }
    (None, sel)
}

#[derive(PartialEq, Eq)]
enum Kind {
    Plain,
    Procedural,
}

/// Index of the `)` closing the `(` at `open`, skipping quotes, brackets, and
/// escapes.
fn find_close(b: &[u8], open: usize) -> Result<usize, String> {
    let mut depth = 0usize;
    let mut i = open;
    while i < b.len() {
        match b[i] {
            b'\\' => i += 2,
            // An operator argument is text to uBO, so a stray quote is not an error.
            q @ (b'"' | b'\'') => i = skip_string(b, i, q).unwrap_or(i + 1),
            b'[' => i = skip_bracket(b, i)?,
            b'(' => {
                depth += 1;
                i += 1;
            }
            b')' => {
                depth -= 1;
                if depth == 0 {
                    return Ok(i);
                }
                i += 1;
            }
            _ => i += 1,
        }
    }
    Err("unbalanced parentheses".into())
}

fn skip_string(b: &[u8], start: usize, quote: u8) -> Result<usize, String> {
    let mut i = start + 1;
    while i < b.len() {
        match b[i] {
            b'\\' => i += 2,
            c if c == quote => return Ok(i + 1),
            _ => i += 1,
        }
    }
    Err("unterminated string".into())
}

fn skip_bracket(b: &[u8], start: usize) -> Result<usize, String> {
    let mut i = start + 1;
    while i < b.len() {
        match b[i] {
            b'\\' => i += 2,
            q @ (b'"' | b'\'') => i = skip_string(b, i, q)?,
            b']' => return Ok(i + 1),
            _ => i += 1,
        }
    }
    Err("unterminated attribute selector".into())
}

/// Plain CSS or procedural/action selector, with uBO's validity rules that
/// apply without a CSS parser.
fn classify(sel: &str) -> Result<Kind, String> {
    if sel.is_empty() {
        return Err("empty selector".into());
    }
    if sel.starts_with(['+', '>', '~']) {
        return Err("relative selector at top level".into());
    }
    if sel.ends_with(['+', '>', '~']) {
        return Err("selector ends with a combinator".into());
    }
    let b = sel.as_bytes();
    let mut kind = Kind::Plain;
    let mut pseudo_element = false;
    let mut proc_op = false;
    let mut depth = 0usize;
    let mut i = 0;
    while i < b.len() {
        match b[i] {
            b'\\' => i += 2,
            q @ (b'"' | b'\'') => i = skip_string(b, i, q)?,
            b'[' => i = skip_bracket(b, i)?,
            b'(' => {
                depth += 1;
                i += 1;
            }
            b')' => {
                depth = depth.checked_sub(1).ok_or("unbalanced parentheses")?;
                i += 1;
            }
            b':' if b.get(i + 1) == Some(&b':') => {
                pseudo_element = true;
                i += 2;
            }
            b':' => {
                let start = i + 1;
                let end = start
                    + b[start..]
                        .iter()
                        .take_while(|c| c.is_ascii_alphanumeric() || **c == b'-' || **c == b'_')
                        .count();
                let name = &sel[start..end];
                if name.starts_with("-abp-") || name == "content" {
                    return Err(format!("unsupported operator ':{name}'"));
                }
                let is_action = ACTION_OPS.contains(&name);
                if is_action || PROCEDURAL_OPS.contains(&name) {
                    kind = Kind::Procedural;
                    proc_op |= !is_action;
                    if b.get(end) != Some(&b'(') {
                        return Err(format!("':{name}' needs arguments"));
                    }
                    // Arguments are not selectors, so they are not scanned.
                    let close = find_close(b, end)?;
                    check_args(name, sel[end + 1..close].trim())?;
                    i = close + 1;
                } else {
                    i = end;
                }
            }
            b'.' | b'#' if depth == 0 && b.get(i + 1).is_some_and(u8::is_ascii_digit) => {
                return Err("class or id starts with a digit".into());
            }
            _ => i += 1,
        }
    }
    if depth != 0 {
        return Err("unbalanced parentheses".into());
    }
    // uBO rejects a pseudo-element with a procedural operator, but not with an
    // action such as `:style()` (compileSelector checks ProceduralSelector only).
    if proc_op && pseudo_element {
        return Err("pseudo-element with a procedural operator".into());
    }
    Ok(kind)
}

fn check_args(name: &str, arg: &str) -> Result<(), String> {
    match name {
        "remove" | "others" if !arg.is_empty() => Err(format!(":{name}() takes no argument")),
        "remove" | "others" => Ok(()),
        "min-text-length" => arg
            .parse::<u32>()
            .map(|_| ())
            .map_err(|_| "non-integer :min-text-length".into()),
        _ if arg.is_empty() => Err(format!(":{name}() needs an argument")),
        _ => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ast::Rule;
    use crate::normalize::adguard_to_ubo;

    /// One-line summary of a parse result, for compact table tests.
    fn show(line: &str) -> String {
        let source = SourceRef::default();
        match parse(line, source) {
            None => "network".into(),
            Some(ParsedLine::Ignored) => "ignored".into(),
            Some(ParsedLine::Unsupported { reason }) => format!("unsupported: {reason}"),
            Some(ParsedLine::Invalid { reason }) => format!("invalid: {reason}"),
            Some(ParsedLine::Rule(Rule::Cosmetic(c))) => {
                let mut dom: Vec<String> = c.domains.include.iter().map(matcher).collect();
                dom.extend(c.domains.exclude.iter().map(|m| format!("~{}", matcher(m))));
                let exc = if c.exception { "@" } else { "" };
                let dom = if dom.is_empty() {
                    String::new()
                } else {
                    format!("[{}] ", dom.join(","))
                };
                let mp = c
                    .matches_path
                    .map(|p| format!(" mp={p}"))
                    .unwrap_or_default();
                let body = match c.body {
                    CosmeticBody::Hide(s) => format!("hide {s}"),
                    CosmeticBody::Procedural(s) => format!("proc {s}"),
                };
                format!("{exc}{dom}{body}{mp}")
            }
            Some(ParsedLine::Rule(Rule::Scriptlet(s))) => {
                let exc = if s.exception { "@" } else { "" };
                let mut dom: Vec<String> = s.domains.include.iter().map(matcher).collect();
                dom.extend(s.domains.exclude.iter().map(|m| format!("~{}", matcher(m))));
                let dom = if dom.is_empty() {
                    String::new()
                } else {
                    format!("[{}] ", dom.join(","))
                };
                format!("{exc}{dom}js {}[{}]", s.name, s.args.join(" | "))
            }
            Some(ParsedLine::Rule(Rule::Network(_))) => unreachable!(),
        }
    }

    fn matcher(m: &DomainMatcher) -> String {
        match m {
            DomainMatcher::Hostname(h) => format!("h:{h}"),
            DomainMatcher::Entity(e) => format!("e:{e}"),
            DomainMatcher::Regex(r) => format!("r:{r}"),
        }
    }

    /// Runs every case and reports all mismatches at once.
    fn check(cases: &[(&str, &str)]) {
        let bad: Vec<String> = cases
            .iter()
            .filter_map(|(line, want)| {
                let got = show(line);
                (got != *want).then(|| format!("{line:?}\n   want {want}\n   got  {got}"))
            })
            .collect();
        assert!(
            bad.is_empty(),
            "{} mismatches:\n{}",
            bad.len(),
            bad.join("\n")
        );
    }

    #[test]
    fn youtube_reload_workaround_is_dropped() {
        let dropped = "unsupported: YouTube reload workaround that misfires in Safari";
        check(&[
            (
                r#"www.youtube.com##+js(rpnt, script, /(\(function serverContract\(\)|^if \(window\.ytcsi)/, (()=>{i.loadVideoById(a,u)})();$1, sedCount, 1)"#,
                dropped,
            ),
            (
                r#"www.youtube.com##+js(trusted-edit-inbound-object, JSON.stringify, 0, [?.attestationRequest][?.context.client.userAgent*="yahi"]+={"params":"YAHI"})"#,
                dropped,
            ),
            (
                "www.youtube.com##+js(rpnt, script, /ads/, x)",
                "[h:www.youtube.com] js trusted-replace-node-text[script | /ads/ | x]",
            ),
        ]);
    }

    #[test]
    fn hide_rules_and_domains() {
        check(&[
            ("##.ad-banner", "hide .ad-banner"),
            ("## .ad", "hide .ad"),
            ("example.com##.ad", "[h:example.com] hide .ad"),
            (
                "example.com,~sub.example.com##div.x",
                "[h:example.com,~h:sub.example.com] hide div.x",
            ),
            ("~example.com##.ad", "[~h:example.com] hide .ad"),
            ("#@#.ad", "@hide .ad"),
            ("example.com#@#.ad", "@[h:example.com] hide .ad"),
            ("google.*##.ad", "[e:google] hide .ad"),
            ("/ads\\d+\\.com/##.x", "[r:ads\\d+\\.com] hide .x"),
            ("/a,b/,example.com##.x", "[r:a,b,h:example.com] hide .x"),
            ("EXAMPLE.com##.x", "[h:example.com] hide .x"),
            ("bücher.de##.x", "[h:xn--bcher-kva.de] hide .x"),
            (
                "example.com##.a:has(> .b)",
                "[h:example.com] hide .a:has(> .b)",
            ),
            (
                "example.com##.a:is(.b, .c):not(.d)",
                "[h:example.com] hide .a:is(.b, .c):not(.d)",
            ),
            (
                "example.com##:is(.a, .b) > .c",
                "[h:example.com] hide :is(.a, .b) > .c",
            ),
            (
                "example.com##.a:nth-child(2n+1)",
                "[h:example.com] hide .a:nth-child(2n+1)",
            ),
            (
                "example.com##div::before",
                "[h:example.com] hide div::before",
            ),
            (
                "example.com##a[href=\"x]\"]",
                "[h:example.com] hide a[href=\"x]\"]",
            ),
            (
                "example.com##.a >",
                "invalid: selector ends with a combinator",
            ),
            (
                "example.com##> .a",
                "invalid: relative selector at top level",
            ),
            (
                "example.com##.1abc",
                "invalid: class or id starts with a digit",
            ),
            (
                "example.com##.a[href",
                "invalid: unterminated attribute selector",
            ),
            ("example.com##.a)", "invalid: unbalanced parentheses"),
            ("example.com##.a:not(.b", "invalid: unbalanced parentheses"),
            ("example.com,##.x", "invalid: empty domain"),
            ("a*b.com##.x", "invalid: bad domain 'a*b.com'"),
            ("*##.x", "unsupported: wildcard domain"),
            ("example.com>>##.x", "unsupported: domain ancestor or path"),
            (
                "example.com/path##.x",
                "unsupported: domain ancestor or path",
            ),
            ("##", "ignored"),
        ]);
    }

    #[test]
    fn procedural_rules() {
        check(&[
            (
                "example.com##div:has-text(Sponsored)",
                "[h:example.com] proc div:has-text(Sponsored)",
            ),
            (
                "example.com#?#.a:has-text(x)",
                "[h:example.com] proc .a:has-text(x)",
            ),
            (
                "example.com#@?#.a:has-text(x)",
                "@[h:example.com] proc .a:has-text(x)",
            ),
            (
                "example.com##div:upward(2)",
                "[h:example.com] proc div:upward(2)",
            ),
            (
                "example.com##a:xpath(//a)",
                "[h:example.com] proc a:xpath(//a)",
            ),
            (
                "example.com##div:matches-css(display: none)",
                "[h:example.com] proc div:matches-css(display: none)",
            ),
            (
                "example.com##div:matches-css-before(content: x)",
                "[h:example.com] proc div:matches-css-before(content: x)",
            ),
            (
                "example.com##.a:matches-attr(\"data-x=1\")",
                "[h:example.com] proc .a:matches-attr(\"data-x=1\")",
            ),
            (
                "example.com##.a:watch-attr(class)",
                "[h:example.com] proc .a:watch-attr(class)",
            ),
            (
                "example.com##div:min-text-length(10)",
                "[h:example.com] proc div:min-text-length(10)",
            ),
            (
                "example.com##div:min-text-length(abc)",
                "invalid: non-integer :min-text-length",
            ),
            (
                "example.com##div:others()",
                "[h:example.com] proc div:others()",
            ),
            ("example.com##div:if(.x)", "[h:example.com] proc div:if(.x)"),
            (
                "example.com##div:if-not(.x)",
                "[h:example.com] proc div:if-not(.x)",
            ),
            (
                "example.com##div:not(:has-text(x))",
                "[h:example.com] proc div:not(:has-text(x))",
            ),
            (
                "example.com##.a:remove-class(b)",
                "[h:example.com] proc .a:remove-class(b)",
            ),
            (
                "example.com##.a:remove-attr(b)",
                "[h:example.com] proc .a:remove-attr(b)",
            ),
            (
                "example.com##.ad:remove()",
                "[h:example.com] proc .ad:remove()",
            ),
            (
                "example.com##.ad:remove(x)",
                "invalid: :remove() takes no argument",
            ),
            (
                "example.com##.ad:style(display: none !important)",
                "[h:example.com] proc .ad:style(display: none !important)",
            ),
            (
                "example.com##.a:style()",
                "invalid: :style() needs an argument",
            ),
            (
                "example.com##div:has-text(a)::before",
                "invalid: pseudo-element with a procedural operator",
            ),
            (
                "example.com##div:has-text()",
                "invalid: :has-text() needs an argument",
            ),
            (
                "example.com##div:has-text",
                "invalid: ':has-text' needs arguments",
            ),
            (
                "example.com##div:-abp-has(span)",
                "invalid: unsupported operator ':-abp-has'",
            ),
            (
                "example.com##div:-abp-properties(x)",
                "invalid: unsupported operator ':-abp-properties'",
            ),
            (
                "example.com##div:content(x)",
                "invalid: unsupported operator ':content'",
            ),
            (
                "##div:has-text(Sponsored)",
                "invalid: generic procedural or action filter",
            ),
            (
                "##.ad:remove()",
                "invalid: generic procedural or action filter",
            ),
            ("#@#div:has-text(x)", "@proc div:has-text(x)"),
            (
                "~example.com##div:has-text(x)",
                "invalid: generic procedural or action filter",
            ),
        ]);
    }

    #[test]
    fn matches_path_prefix_and_suffix() {
        check(&[
            (
                "example.com##:matches-path(/search/) .ad",
                "[h:example.com] hide .ad mp=/search/",
            ),
            (
                "example.com##.ad:matches-path(/x)",
                "[h:example.com] hide .ad mp=/x",
            ),
            (
                "example.com##:matches-path(/search/)",
                "invalid: empty selector",
            ),
            (
                "example.com##:matches-path(/^\\/(\\?[a-z]+=\\w+)?$/) div[role] :is(h3, h4)",
                "[h:example.com] hide div[role] :is(h3, h4) mp=/^\\/(\\?[a-z]+=\\w+)?$/",
            ),
        ]);
    }

    #[test]
    fn scriptlets() {
        check(&[
            (
                "example.com##+js(aopr, disableSelection)",
                "[h:example.com] js abort-on-property-read[disableSelection]",
            ),
            (
                "example.com##+js(acs, document.oncontextmenu)",
                "[h:example.com] js abort-current-script[document.oncontextmenu]",
            ),
            (
                "example.com##+js(aopr.js, x)",
                "[h:example.com] js abort-on-property-read[x]",
            ),
            (
                "example.com##+js(set, a, 1)",
                "[h:example.com] js set-constant[a | 1]",
            ),
            (
                "example.com##+js(aost.js)",
                "[h:example.com] js abort-on-stack-trace[]",
            ),
            (
                "example.com##+js(prevent-eval-if.js, x)",
                "[h:example.com] js noeval-if[x]",
            ),
            (
                "example.com##+js(trusted-set-constant, a, b)",
                "[h:example.com] js trusted-set-constant[a | b]",
            ),
            (
                "example.com##+js(aopr, a\\, b)",
                "[h:example.com] js abort-on-property-read[a, b]",
            ),
            (
                "example.com##+js(set-constant, 'a, b', \"c\")",
                "[h:example.com] js set-constant[a, b | c]",
            ),
            (
                "example.com##+js(aopr, , x)",
                "[h:example.com] js abort-on-property-read[ | x]",
            ),
            (
                "example.com##+js(aopr,)",
                "[h:example.com] js abort-on-property-read[]",
            ),
            (
                "example.com##+js(aopr, x,)",
                "[h:example.com] js abort-on-property-read[x]",
            ),
            (
                "example.com##+js(aopr, `x'y`)",
                "[h:example.com] js abort-on-property-read[x'y]",
            ),
            (
                "example.com##+js(aopr,  spaced  )",
                "[h:example.com] js abort-on-property-read[spaced]",
            ),
            (
                "example.com##+js(aopr, \"a\\\"b\")",
                "[h:example.com] js abort-on-property-read[a\"b]",
            ),
            (
                "example.com##+js(nosuch, x)",
                "unsupported: unknown scriptlet 'nosuch'",
            ),
            ("#@#+js()", "@js []"),
            ("example.com#@#+js()", "@[h:example.com] js []"),
            ("#@#+js(aopr)", "@js abort-on-property-read[]"),
            (
                "example.com,~a.example.com#@#+js(aopr)",
                "@[h:example.com,~h:a.example.com] js abort-on-property-read[]",
            ),
            ("##+js()", "invalid: scriptlet without a name"),
            ("##+js(, x)", "invalid: scriptlet without a name"),
            ("##+js(aopr", "invalid: relative selector at top level"),
        ]);
    }

    #[test]
    fn html_and_adguard_markers_are_unsupported() {
        check(&[
            (
                "##^script[tag-content=\"x\"]",
                "unsupported: HTML filtering",
            ),
            (
                "example.com##^responseheader(set-cookie)",
                "unsupported: response header filtering",
            ),
            (
                "example.com$$script[tag-content=\"x\"]",
                "unsupported: AdGuard HTML filtering",
            ),
            (
                "example.com$@$script[tag-content=\"x\"]",
                "unsupported: AdGuard HTML filtering",
            ),
            (
                "example.com#%#var a = 1;",
                "unsupported: AdGuard JavaScript injection",
            ),
            (
                "example.com#@%#var a = 1;",
                "unsupported: AdGuard JavaScript injection",
            ),
            (
                "example.com#%#//scriptlet('nosuch', 'x')",
                "unsupported: AdGuard scriptlet without a uBO equivalent",
            ),
            (
                "example.com#%#//scriptlet('abort-on-property-read', 'x')",
                "unsupported: AdGuard scriptlet without a uBO equivalent",
            ),
            (
                "example.com#$#.pub_728x90 { display: block !important; }",
                "unsupported: AdGuard CSS injection or ABP snippet",
            ),
            (
                "example.com#$?#div { display: none !important; }",
                "unsupported: AdGuard CSS injection or ABP snippet",
            ),
            (
                "example.com#@$#.ad { color: red; }",
                "unsupported: AdGuard CSS injection or ABP snippet",
            ),
            (
                "example.com#$#log 'x'",
                "unsupported: AdGuard CSS injection or ABP snippet",
            ),
        ]);
    }

    #[test]
    fn non_cosmetic_lines() {
        check(&[
            ("||example.com/#foo", "network"),
            ("||example.com^$third-party", "network"),
            (
                "|https://example.com/##x",
                "invalid: bad domain '|https://example.com/'",
            ),
            ("#### Section ##", "ignored"),
            ("# comment ##.x", "ignored"),
            ("#comment", "ignored"),
            ("#", "ignored"),
            ("example.com##", "network"),
        ]);
    }

    #[test]
    fn real_list_lines() {
        check(&[
            (
                "ilovevaldinon.it##+js(acs, document.oncontextmenu)",
                "[h:ilovevaldinon.it] js abort-current-script[document.oncontextmenu]",
            ),
            (
                "discord.com#?#.wrapper__0d616:has-text(Get Reward)",
                "[h:discord.com] proc .wrapper__0d616:has-text(Get Reward)",
            ),
            (
                "gamedev.net#?#.dark\\:border-gray-700:has-text(Advertisement)",
                "[h:gamedev.net] proc .dark\\:border-gray-700:has-text(Advertisement)",
            ),
            (
                "deliveroo.*#?#a[role=\"button\"]:has(p:has-text(Sponsored))",
                "[e:deliveroo] proc a[role=\"button\"]:has(p:has-text(Sponsored))",
            ),
        ]);
    }

    /// Every line of the downloaded lists (see `CORPUS_DIR`) through normalize
    /// and the cosmetic parser. Prints counts per outcome and the wall time.
    /// Skipped when the lists are not on disk.
    #[test]
    fn corpus_counts() {
        use std::collections::BTreeMap;
        use std::time::Instant;

        let dir = std::env::var("WBE_CORPUS_DIR").unwrap_or_else(|_| "/tmp/cosmetic-lists".into());
        let Ok(entries) = std::fs::read_dir(&dir) else {
            eprintln!("corpus_counts: no lists in {dir}, skipped");
            return;
        };
        let mut lines: Vec<String> = Vec::new();
        for entry in entries.flatten() {
            if entry.path().extension().is_some_and(|e| e == "txt") {
                let text = std::fs::read_to_string(entry.path()).unwrap_or_default();
                lines.extend(text.lines().map(str::to_string));
            }
        }
        let source = SourceRef::default();
        let mut counts: BTreeMap<String, usize> = BTreeMap::new();
        let mut invalid_samples: Vec<(String, String)> = Vec::new();
        let started = Instant::now();
        for line in &lines {
            let line = line.trim();
            if line.is_empty() || line.starts_with('!') || line.starts_with('[') {
                *counts.entry("ignored".into()).or_default() += 1;
                continue;
            }
            let normalized = adguard_to_ubo(line);
            let key = match parse(&normalized, source) {
                None => "network".to_string(),
                Some(ParsedLine::Ignored) => "ignored".into(),
                Some(ParsedLine::Rule(Rule::Cosmetic(c))) => match c.body {
                    CosmeticBody::Hide(_) => "hide".into(),
                    CosmeticBody::Procedural(_) => "procedural".into(),
                },
                Some(ParsedLine::Rule(Rule::Scriptlet(_))) => "scriptlet".into(),
                Some(ParsedLine::Rule(Rule::Network(_))) => unreachable!(),
                Some(ParsedLine::Unsupported { reason }) => format!("unsupported: {reason}"),
                Some(ParsedLine::Invalid { reason }) => {
                    if invalid_samples.len() < 400 {
                        invalid_samples.push((reason.clone(), line.to_string()));
                    }
                    format!("invalid: {reason}")
                }
            };
            *counts.entry(key).or_default() += 1;
        }
        let elapsed = started.elapsed();
        println!("corpus: {} lines in {:?}", lines.len(), elapsed);
        for (key, n) in &counts {
            println!("{n:>8}  {key}");
        }
        if let Ok(path) = std::env::var("WBE_INVALID_OUT") {
            let body: String = invalid_samples
                .iter()
                .map(|(r, l)| format!("{r}\t{l}\n"))
                .collect();
            std::fs::write(path, body).unwrap();
        }
        assert!(!counts.is_empty());
    }
}
