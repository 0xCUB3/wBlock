//! Network filter lines. Mirrors uBO's `AstFilterParser` (`parseNet`,
//! `parseNetPattern`, `parseNetOptions`, `validateNet`, `indexOfNetAnchor`) in
//! src/js/static-filtering-parser.js, and the option interpretation in
//! `FilterCompiler.process` in src/js/static-net-filtering.js.

use crate::ast::{
    DomainList, DomainMatcher, ExceptionScope, MethodList, NetworkAction, NetworkRule, ParsedLine,
    Party, Pattern, PatternKind, ResourceTypes, Rule, SourceRef,
};

/// uBO option names and synonyms (`nodeTypeFromOptionName`). `_` is handled
/// separately because uBO accepts any run of underscores as a no-op.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Opt {
    P1,
    P3,
    Strict1p,
    Strict3p,
    All,
    Badfilter,
    Cname,
    Csp,
    Css,
    Denyallow,
    Doc,
    Ehide,
    Empty,
    Font,
    Frame,
    From,
    Genericblock,
    Ghide,
    Image,
    Important,
    InlineFont,
    InlineScript,
    Ipaddress,
    MatchCase,
    Media,
    Method,
    Mp4,
    Noop,
    Object,
    Other,
    Permissions,
    Ping,
    Popunder,
    Popup,
    Reason,
    Redirect,
    RedirectRule,
    Removeparam,
    Replace,
    Requestheader,
    Responseheader,
    Script,
    Shide,
    To,
    Top,
    Urlskip,
    Urltransform,
    Xhr,
    Webrtc,
    Websocket,
}

const OPTION_NAMES: &[(&str, Opt)] = &[
    ("1p", Opt::P1),
    ("first-party", Opt::P1),
    ("strict1p", Opt::Strict1p),
    ("strict-first-party", Opt::Strict1p),
    ("3p", Opt::P3),
    ("third-party", Opt::P3),
    ("strict3p", Opt::Strict3p),
    ("strict-third-party", Opt::Strict3p),
    ("all", Opt::All),
    ("badfilter", Opt::Badfilter),
    ("cname", Opt::Cname),
    ("csp", Opt::Csp),
    ("css", Opt::Css),
    ("stylesheet", Opt::Css),
    ("denyallow", Opt::Denyallow),
    ("doc", Opt::Doc),
    ("document", Opt::Doc),
    ("ehide", Opt::Ehide),
    ("elemhide", Opt::Ehide),
    ("empty", Opt::Empty),
    ("font", Opt::Font),
    ("frame", Opt::Frame),
    ("subdocument", Opt::Frame),
    ("from", Opt::From),
    ("domain", Opt::From),
    ("genericblock", Opt::Genericblock),
    ("ghide", Opt::Ghide),
    ("generichide", Opt::Ghide),
    ("image", Opt::Image),
    ("important", Opt::Important),
    ("inline-font", Opt::InlineFont),
    ("inline-script", Opt::InlineScript),
    ("ipaddress", Opt::Ipaddress),
    ("match-case", Opt::MatchCase),
    ("media", Opt::Media),
    ("method", Opt::Method),
    ("mp4", Opt::Mp4),
    ("_", Opt::Noop),
    ("object", Opt::Object),
    ("object-subrequest", Opt::Object),
    ("other", Opt::Other),
    ("permissions", Opt::Permissions),
    ("ping", Opt::Ping),
    ("beacon", Opt::Ping),
    ("popunder", Opt::Popunder),
    ("popup", Opt::Popup),
    ("reason", Opt::Reason),
    ("redirect", Opt::Redirect),
    ("rewrite", Opt::Redirect),
    ("redirect-rule", Opt::RedirectRule),
    ("removeparam", Opt::Removeparam),
    ("queryprune", Opt::Removeparam),
    ("replace", Opt::Replace),
    ("requestheader", Opt::Requestheader),
    ("responseheader", Opt::Responseheader),
    ("header", Opt::Responseheader),
    ("script", Opt::Script),
    ("shide", Opt::Shide),
    ("specifichide", Opt::Shide),
    ("to", Opt::To),
    ("top", Opt::Top),
    ("urlskip", Opt::Urlskip),
    ("uritransform", Opt::Urltransform),
    ("xhr", Opt::Xhr),
    ("xmlhttprequest", Opt::Xhr),
    ("webrtc", Opt::Webrtc),
    ("websocket", Opt::Websocket),
];

/// uBO `redirect-resources.js` aliases, alias to canonical resource name.
const REDIRECT_ALIASES: &[(&str, &str)] = &[
    ("1x1-transparent.gif", "1x1.gif"),
    ("2x2-transparent.png", "2x2.png"),
    ("3x2-transparent.png", "3x2.png"),
    ("32x32-transparent.png", "32x32.png"),
    ("amazon-adsystem.com/aax2/amzn_ads.js", "amazon_ads.js"),
    ("ampproject.org/v0.js", "ampproject_v0.js"),
    ("static.chartbeat.com/chartbeat.js", "chartbeat.js"),
    (
        "doubleclick.net/instream/ad_status.js",
        "doubleclick_instream_ad_status.js",
    ),
    (
        "google-analytics.com/cx/api.js",
        "google-analytics_cx_api.js",
    ),
    ("google-analytics.com/ga.js", "google-analytics_ga.js"),
    (
        "google-analytics.com/inpage_linkid.js",
        "google-analytics_inpage_linkid.js",
    ),
    ("google-ima3", "google-ima.js"),
    ("google-ima3-dai", "google-ima.js"),
    ("widgets.outbrain.com/outbrain.js", "outbrain-widget.js"),
    ("silent-noeval.js", "noeval-silent.js"),
    ("fuckadblock.js-3.2.0", "fuckadblock.js"),
    ("noopmp3-0.1s", "noop-0.1s.mp3"),
    ("abp-resource:blank-mp3", "noop-0.1s.mp3"),
    ("noopmp4-1s", "noop-1s.mp4"),
    ("abp-resource:blank-mp4", "noop-1s.mp4"),
    ("noopframe", "noop.html"),
    ("noopjs", "noop.js"),
    ("abp-resource:blank-js", "noop.js"),
    ("noopjson", "noop.json"),
    ("nooptext", "noop.txt"),
    ("noopvast-2.0", "noop-vast2.xml"),
    ("noopvast-3.0", "noop-vast3.xml"),
    ("noopvast-4.0", "noop-vast4.xml"),
    ("noop-vmap1.0.xml", "noop-vmap1.xml"),
    ("noopvmap-1.0", "noop-vmap1.xml"),
    ("popads.net.js", "popads.js"),
    ("prevent-popads-net.js", "popads.js"),
    (
        "scorecardresearch.com/beacon.js",
        "scorecardresearch-beacon.js",
    ),
    ("ligatus.com/ligatus.js", "ligatus-angular-tag.js"),
    ("hd-vid-prime.com/prime.js", "hd-vid-prime.js"),
];

const NETWORK_TYPES: ResourceTypes = ResourceTypes::from_bits_retain(0xFBF);
/// uBO `allTypesBits`: network types plus popup, main document, inline-*.
const ALL_TYPES: ResourceTypes =
    ResourceTypes::from_bits_retain(0xFBF | (1 << 6) | (1 << 12) | (1 << 15) | (1 << 16));

/// Options whose value is a plain request-type match.
fn type_of(opt: Opt) -> Option<ResourceTypes> {
    Some(match opt {
        Opt::Css => ResourceTypes::CSS,
        Opt::Font => ResourceTypes::FONT,
        Opt::Image => ResourceTypes::IMAGE,
        Opt::Media | Opt::Mp4 => ResourceTypes::MEDIA,
        Opt::Other => ResourceTypes::OTHER,
        Opt::Script => ResourceTypes::SCRIPT,
        Opt::Xhr => ResourceTypes::XHR,
        Opt::Ping => ResourceTypes::PING,
        Opt::Websocket => ResourceTypes::WEBSOCKET,
        Opt::Object => ResourceTypes::OBJECT,
        Opt::Frame => ResourceTypes::FRAME,
        Opt::Doc => ResourceTypes::DOC,
        Opt::Popup => ResourceTypes::POPUP,
        Opt::Popunder => ResourceTypes::POPUNDER,
        Opt::InlineFont => ResourceTypes::INLINE_FONT,
        Opt::InlineScript => ResourceTypes::INLINE_SCRIPT,
        _ => return None,
    })
}

/// One option as uBO's `parseNetOption` sees it.
#[derive(Debug)]
struct NetOpt {
    opt: Opt,
    neg: bool,
    /// Value after `=`, arguments unescaped. `None` when the option has no `=`.
    value: Option<String>,
}

/// Line-level facts uBO computes once (`hasWhitespace`, `hasUppercase`,
/// `hasUnicode`). They are taken from the whole trimmed line, comment included.
struct LineFlags {
    has_ws: bool,
    has_upper: bool,
    has_unicode: bool,
}

pub(super) fn parse(line: &str, source: SourceRef) -> ParsedLine {
    match parse_rule(line, source) {
        Ok(rule) => ParsedLine::Rule(Rule::Network(rule)),
        Err(other) => other,
    }
}

fn invalid(reason: &str) -> ParsedLine {
    ParsedLine::Invalid {
        reason: reason.to_string(),
    }
}

fn unsupported(reason: &str) -> ParsedLine {
    ParsedLine::Unsupported {
        reason: reason.to_string(),
    }
}

fn parse_rule(line: &str, source: SourceRef) -> Result<NetworkRule, ParsedLine> {
    let flags = LineFlags {
        has_ws: line.chars().any(char::is_whitespace),
        has_upper: line.bytes().any(|b| b.is_ascii_uppercase()),
        has_unicode: !line.is_ascii(),
    };
    if let Some(host) = fast_hosts(line) {
        let pattern = Pattern {
            kind: PatternKind::Hostname,
            body: host.into(),
            right_anchored: false,
        };
        return Ok(NetworkRule {
            source,
            raw: line.into(),
            pattern,
            ..Default::default()
        });
    }
    let head = strip_inline_comment(line, flags.has_ws).trim_end();
    if head.is_empty() || head.starts_with('#') {
        return Err(ParsedLine::Ignored);
    }
    let anchor =
        index_of_net_anchor(head).ok_or_else(|| unsupported("HTML filtering is not supported"))?;
    let exception = head.starts_with("@@");
    let has_options = anchor < head.len();
    let opts = if has_options {
        parse_options(&head[anchor + 1..]).map_err(|e| invalid(&e))?
    } else {
        Vec::new()
    };
    let pattern_src = &head[if exception { 2 } else { 0 }..anchor];
    let pattern = parse_pattern(pattern_src, has_options, exception, &flags)?;
    if !has_options && pattern.body.chars().count() <= 1 {
        return Err(invalid("pattern is too short without options"));
    }
    validate(&opts, exception, pattern.kind == PatternKind::Regex).map_err(invalid)?;
    let hostname_only = pattern.kind == PatternKind::Hostname && !has_options;
    if pattern.kind != PatternKind::Regex && !hostname_only && pattern.body.len() > 1024 {
        return Err(unsupported("pattern is longer than 1024 characters"));
    }
    build(source, line, exception, pattern, &opts)
}

/// Fast path of uBO `parse` for `127.0.0.1 host` and `0.0.0.0 host` lines.
/// Unlike the general hosts path it does not check for localhost-style names.
fn fast_hosts(line: &str) -> Option<&str> {
    let host = line
        .strip_prefix("127.0.0.1 ")
        .or_else(|| line.strip_prefix("0.0.0.0 "))?;
    let mut labels = host.split('.').peekable();
    let mut count = 0;
    while let Some(label) = labels.next() {
        count += 1;
        let b = label.as_bytes();
        let ok = if labels.peek().is_some() {
            b.first().is_some_and(|&c| is_alnum_lower(c))
                && b[1..]
                    .iter()
                    .all(|&c| is_alnum_lower(c) || c == b'_' || c == b'-')
        } else {
            b.last().is_some_and(|c| c.is_ascii_lowercase())
                && b.iter().all(|&c| is_alnum_lower(c) || c == b'-')
        };
        if !ok {
            return None;
        }
    }
    (count >= 2).then_some(host)
}

/// Strips a trailing ` # comment` (uBO `reInlineComment`).
fn strip_inline_comment(line: &str, has_ws: bool) -> &str {
    if !has_ws {
        return line;
    }
    let b = line.as_bytes();
    for i in 1..b.len() {
        if b[i] == b'#' && b[i - 1].is_ascii_whitespace() {
            let mut start = i - 1;
            while start > 0 && b[start - 1].is_ascii_whitespace() {
                start -= 1;
            }
            return &line[..start];
        }
    }
    line
}

/// uBO `indexOfNetAnchor`: the `$` that starts the option list, `None` for
/// HTML filtering (`$$`).
fn index_of_net_anchor(s: &str) -> Option<usize> {
    let Some(mut j) = s.rfind('$') else {
        return Some(s.len());
    };
    let mut html = false;
    loop {
        if j >= 1 && s.as_bytes()[j - 1] == b'$' {
            html = true;
        }
        if starts_with_option_name(&s[j + 1..]) {
            return Some(j);
        }
        if j == 0 {
            break;
        }
        match s[..j].rfind('$') {
            Some(k) => j = k,
            None => break,
        }
    }
    if html {
        None
    } else {
        Some(s.len())
    }
}

/// `^~?(name)\b` over uBO's option-name table.
fn starts_with_option_name(t: &str) -> bool {
    let t = t.strip_prefix('~').unwrap_or(t);
    OPTION_NAMES.iter().any(|(name, _)| {
        t.starts_with(name) && !t.as_bytes().get(name.len()).is_some_and(|&c| is_word(c))
    })
}

/// uBO `parseNetOptions`. `s` is the text after the `$`.
fn parse_options(s: &str) -> Result<Vec<NetOpt>, String> {
    let b = s.as_bytes();
    let n = b.len();
    let mut out: Vec<NetOpt> = Vec::new();
    let mut i = 0;
    loop {
        // uBO `reNetOption`: ^(~?)([134a-z_-]+)(=?)
        let neg = b.get(i) == Some(&b'~');
        let name_beg = i + neg as usize;
        let mut j = name_beg;
        while j < n && matches!(b[j], b'1' | b'3' | b'4' | b'a'..=b'z' | b'_' | b'-') {
            j += 1;
        }
        if j == name_beg {
            return Err(format!("unknown option at `{}`", &s[i..]));
        }
        let name = &s[name_beg..j];
        let opt = lookup_option(name).ok_or_else(|| format!("unknown option `{name}`"))?;
        if opt != Opt::Noop && out.iter().any(|o| o.opt == opt) {
            return Err(format!("duplicate option `{name}`"));
        }
        let assigned = b.get(j) == Some(&b'=');
        let (value, end) = if assigned {
            let (value, end) = read_value(s, j + 1);
            if value.is_empty() {
                return Err(format!("empty value for `{name}`"));
            }
            (Some(value), end)
        } else {
            (None, j)
        };
        out.push(NetOpt { opt, neg, value });
        if end == n {
            return Ok(out);
        }
        i = end + 1;
        if i == n {
            return Err("trailing option separator".into());
        }
    }
}

fn lookup_option(name: &str) -> Option<Opt> {
    if let Some((_, opt)) = OPTION_NAMES.iter().find(|(n, _)| *n == name) {
        return Some(*opt);
    }
    name.bytes().all(|c| c == b'_').then_some(Opt::Noop)
}

/// uBO `parseNetOption` value handling with `ArglistParser` semantics. A
/// value is quoted when a matching unescaped quote is followed by `,` or the
/// end. Unquoted values end at the first `,` that starts an option-looking tail.
fn read_value(s: &str, start: usize) -> (String, usize) {
    let b = s.as_bytes();
    let n = b.len();
    let beg = start
        + b[start..]
            .iter()
            .take_while(|c| c.is_ascii_whitespace())
            .count();
    if let Some(&q) = b.get(beg).filter(|&&c| matches!(c, b'"' | b'\'' | b'`')) {
        let (close, transform) = scan_separator(s, beg + 1, q as char);
        let after = close
            + 1
            + b.get(close + 1..).map_or(0, |t| {
                t.iter().take_while(|c| c.is_ascii_whitespace()).count()
            });
        if close < n && (after >= n || b[after] == b',') {
            let raw = &s[beg + 1..close];
            let value = if transform {
                normalize_arg(raw, q as char)
            } else {
                raw.to_string()
            };
            return (value, close + 1);
        }
    }
    let end = end_of_net_option(s, start);
    let (_, transform) = scan_separator(s, beg, ',');
    let raw = &s[beg..end];
    let value = if transform {
        normalize_arg(raw, ',')
    } else {
        raw.to_string()
    };
    (value, end)
}

/// uBO `ArglistParser.indexOfNextArgSeparator`: first `sep` from `from` that
/// is not backslash-escaped. Also reports whether an escaped `sep` was seen.
fn scan_separator(s: &str, from: usize, sep: char) -> (usize, bool) {
    let mut transform = false;
    let mut pos = from;
    while pos < s.len() {
        let Some(k) = s[pos..].find(sep) else {
            break;
        };
        let p = pos + k;
        if trailing_backslashes(&s[..p]).is_multiple_of(2) {
            return (p, transform);
        }
        transform = true;
        pos = p + 1;
    }
    (s.len(), transform)
}

fn trailing_backslashes(s: &str) -> usize {
    s.bytes().rev().take_while(|&c| c == b'\\').count()
}

/// uBO `ArglistParser.normalizeArg`: drops one backslash before each escaped
/// `sep`.
fn normalize_arg(s: &str, sep: char) -> String {
    let mut out = String::with_capacity(s.len());
    let mut run = 0usize;
    for c in s.chars() {
        if c == sep {
            if run % 2 == 1 {
                out.pop();
            }
            run = 0;
        } else if c == '\\' {
            run += 1;
        } else {
            run = 0;
        }
        out.push(c);
    }
    out
}

/// uBO `endOfNetOption`: the first `,` followed by something that parses as
/// another option, or the end of the string.
fn end_of_net_option(s: &str, from: usize) -> usize {
    let b = s.as_bytes();
    (from..b.len())
        .find(|&i| b[i] == b',' && is_option_tail(&b[i + 1..]))
        .unwrap_or(b.len())
}

/// Matches uBO's `,(?:~?[13a-z-]+(?:=.*?)?|_+)(?:,|$)` after the comma.
fn is_option_tail(b: &[u8]) -> bool {
    let start = (b.first() == Some(&b'~')) as usize;
    let mut i = start;
    while i < b.len() && matches!(b[i], b'1' | b'3' | b'a'..=b'z' | b'-') {
        i += 1;
    }
    if i > start && (i == b.len() || matches!(b[i], b'=' | b',')) {
        return true;
    }
    let underscores = b.iter().take_while(|&&c| c == b'_').count();
    underscores > 0 && (underscores == b.len() || b[underscores] == b',')
}

/// `$redirect=` value to resource token: trimmed, leading `%` and `:priority`
/// removed (uBO `parseRedirectValue`).
fn redirect_token(v: &str) -> &str {
    let t = v.trim();
    let t = t.strip_prefix('%').unwrap_or(t);
    if let Some(pos) = t.rfind(':') {
        let tail = &t[pos + 1..];
        let digits = tail.strip_prefix('-').unwrap_or(tail);
        if !digits.is_empty() && digits.bytes().all(|c| c.is_ascii_digit()) {
            return &t[..pos];
        }
    }
    t
}

fn canonical_resource(token: &str) -> String {
    REDIRECT_ALIASES
        .iter()
        .find(|(alias, _)| *alias == token)
        .map_or(token, |(_, name)| *name)
        .to_string()
}

fn value_of(opts: &[NetOpt], opt: Opt) -> &str {
    opts.iter()
        .find(|o| o.opt == opt)
        .and_then(|o| o.value.as_deref())
        .unwrap_or("")
}

fn validate(opts: &[NetOpt], exception: bool, is_regex: bool) -> Result<(), &'static str> {
    let is_badfilter = opts.iter().any(|o| o.opt == Opt::Badfilter);
    let has_from = opts.iter().any(|o| o.opt == Opt::From);
    let mut modifier: Option<Opt> = None;
    let (mut abstract_n, mut behavior_n, mut doc_n, mut request_n, mut unredirect_n) =
        (0, 0, 0, 0, 0);
    for o in opts {
        let (neg, hv) = (o.neg, o.value.is_some());
        let v = o.value.as_deref().unwrap_or("");
        match o.opt {
            Opt::All => {
                if neg || hv || modifier.is_some() {
                    return Err("$all takes no value and cannot follow a modifier");
                }
            }
            Opt::P1 | Opt::P3 => {
                if hv {
                    return Err("party option takes no value");
                }
            }
            Opt::Badfilter | Opt::Noop => {
                if neg || hv {
                    return Err("option takes no value and cannot be negated");
                }
            }
            Opt::Css
            | Opt::Font
            | Opt::Image
            | Opt::Media
            | Opt::Other
            | Opt::Script
            | Opt::Xhr => {
                if hv {
                    return Err("request type takes no value");
                }
                request_n += 1;
            }
            Opt::Cname => {
                if !exception || neg || hv {
                    return Err("$cname is only valid on exceptions without a value");
                }
                modifier = Some(o.opt);
            }
            Opt::Csp | Opt::Permissions => {
                let bad_report = if o.opt == Opt::Csp {
                    has_report_directive(v, &["report-to", "report-uri"])
                } else {
                    has_report_directive(v, &["report-to"])
                };
                if modifier.is_some() || (!hv && !exception) || bad_report {
                    return Err("invalid $csp or $permissions combination");
                }
                modifier = Some(o.opt);
            }
            Opt::Denyallow => {
                if neg || !hv || !has_from {
                    return Err("$denyallow needs $from and a value");
                }
            }
            Opt::Doc | Opt::Frame | Opt::Object => {
                if hv {
                    return Err("document type takes no value");
                }
                doc_n += 1;
            }
            Opt::Ehide | Opt::Ghide | Opt::Shide => {
                if neg || hv || modifier.is_some() {
                    return Err("document-level option cannot be negated or combined");
                }
                behavior_n += 1;
                unredirect_n += 1;
            }
            Opt::Empty | Opt::Mp4 => {
                if neg || hv || modifier.is_some() {
                    return Err("$empty and $mp4 cannot be negated, valued, or combined");
                }
                modifier = Some(o.opt);
            }
            Opt::From | Opt::Method | Opt::To | Opt::Top => {
                if neg || !hv {
                    return Err("option needs a value and cannot be negated");
                }
            }
            Opt::Genericblock => {
                if !exception || neg || hv {
                    return Err("$genericblock is only valid on exceptions");
                }
            }
            Opt::Important => {
                if exception || neg || hv {
                    return Err("$important is only valid on blocking rules");
                }
            }
            Opt::InlineFont | Opt::InlineScript => {
                if hv {
                    return Err("inline type takes no value");
                }
                modifier = Some(o.opt);
                unredirect_n += 1;
            }
            Opt::Ipaddress => {
                let slashed = v.len() >= 3 && v.starts_with('/') && v.ends_with('/');
                if slashed && !regex_is_valid(v) {
                    return Err("invalid $ipaddress regular expression");
                }
            }
            Opt::MatchCase => {
                if !is_regex {
                    return Err("$match-case is only valid on regular expression patterns");
                }
            }
            Opt::Ping | Opt::Websocket => {
                if hv {
                    return Err("request type takes no value");
                }
                request_n += 1;
                if !neg {
                    unredirect_n += 1;
                }
            }
            Opt::Popunder | Opt::Popup => {
                if hv {
                    return Err("popup type takes no value");
                }
                abstract_n += 1;
                unredirect_n += 1;
            }
            Opt::Reason => {
                if !hv {
                    return Err("$reason needs a value");
                }
            }
            Opt::Redirect | Opt::RedirectRule | Opt::Replace | Opt::Urlskip | Opt::Urltransform => {
                if neg || (!exception && !hv) || modifier.is_some() {
                    return Err("invalid redirect or header rewrite combination");
                }
                modifier = Some(o.opt);
            }
            Opt::Removeparam => {
                if neg || modifier.is_some() {
                    return Err("invalid $removeparam combination");
                }
                modifier = Some(o.opt);
            }
            Opt::Requestheader | Opt::Responseheader => {
                if neg || !hv {
                    return Err("header option needs a value and cannot be negated");
                }
            }
            Opt::Strict1p | Opt::Strict3p => {
                if neg || hv {
                    return Err("strict party option takes no value");
                }
            }
            Opt::Webrtc => return Err("$webrtc is not supported"),
        }
    }
    let skip_checks = exception || is_badfilter;
    match modifier {
        Some(Opt::Cname | Opt::Csp | Opt::Permissions) => {
            if abstract_n + behavior_n + request_n > 0 {
                return Err("$csp, $permissions and $cname cannot combine with request types");
            }
        }
        Some(Opt::InlineFont | Opt::InlineScript) => {
            if behavior_n > 0 {
                return Err("inline type cannot combine with document-level options");
            }
        }
        Some(Opt::Empty) => {
            if abstract_n + behavior_n > 0 {
                return Err("$empty cannot combine with popup or document-level options");
            }
        }
        Some(Opt::Mp4) => {
            if abstract_n + behavior_n + doc_n + request_n > 0 {
                return Err("$mp4 cannot combine with other types");
            }
        }
        Some(Opt::Redirect | Opt::RedirectRule) => {
            if abstract_n + behavior_n + unredirect_n > 0 {
                return Err("$redirect cannot combine with popup or document-level options");
            }
        }
        Some(Opt::Replace) => {
            if abstract_n + behavior_n + unredirect_n > 0 {
                return Err("$replace cannot combine with popup or document-level options");
            }
            if !skip_checks && !valid_replace(value_of(opts, Opt::Replace)) {
                return Err("invalid $replace value");
            }
        }
        Some(Opt::Urlskip) => {
            if abstract_n + behavior_n + unredirect_n > 0 {
                return Err("$urlskip cannot combine with popup or document-level options");
            }
            if !skip_checks && value_of(opts, Opt::Urlskip).len() < 2 {
                return Err("$urlskip value is too short");
            }
        }
        Some(Opt::Urltransform) => {
            if abstract_n + behavior_n + unredirect_n > 0 {
                return Err("$uritransform cannot combine with popup or document-level options");
            }
            let v = value_of(opts, Opt::Urltransform);
            if !skip_checks && !v.is_empty() && !valid_replace_by_regex(v) {
                return Err("invalid $uritransform value");
            }
        }
        Some(Opt::Removeparam) if abstract_n + behavior_n > 0 => {
            return Err("$removeparam cannot combine with popup or document-level options");
        }
        _ => {}
    }
    Ok(())
}

/// uBO `(?:^|[;,])\s*report-(to|uri)\b`, case-insensitive.
fn has_report_directive(v: &str, names: &[&str]) -> bool {
    let lower = v.to_ascii_lowercase();
    let b = lower.as_bytes();
    let mut starts = vec![0usize];
    starts.extend(
        b.iter()
            .enumerate()
            .filter(|(_, c)| matches!(c, b';' | b','))
            .map(|(i, _)| i + 1),
    );
    starts.into_iter().any(|p| {
        let q = p + b.get(p..).map_or(0, |t| {
            t.iter().take_while(|c| c.is_ascii_whitespace()).count()
        });
        names.iter().any(|name| {
            lower[q.min(lower.len())..].starts_with(name)
                && !b.get(q + name.len()).is_some_and(|&c| is_word(c))
        })
    })
}

/// uBO `parseReplaceByRegexValue`: `/pattern/replacement/flags` with both
/// closing slashes present. Returns the pattern and the flags.
fn replace_regex_parts(v: &str) -> Option<(&str, &str)> {
    if !v.starts_with('/') {
        return None;
    }
    let (p_end, _) = scan_separator(v, 1, '/');
    if p_end >= v.len() {
        return None;
    }
    let (r_end, _) = scan_separator(v, p_end + 1, '/');
    if r_end >= v.len() {
        return None;
    }
    Some((&v[1..p_end], &v[r_end + 1..]))
}

/// `$uritransform` value: an empty pattern is allowed.
fn valid_replace_by_regex(v: &str) -> bool {
    match replace_regex_parts(v) {
        Some((pattern, flags)) => {
            flags.bytes().all(|c| b"dgimsuvy".contains(&c))
                && (pattern.is_empty() || regex_is_valid(pattern))
        }
        None => false,
    }
}

/// uBO `parseReplaceValue`: a regex replacement with a non-empty pattern, or
/// a `json:`/`jsonl:` query (JSONPath syntax is not validated here).
fn valid_replace(v: &str) -> bool {
    if v.starts_with('/') {
        return replace_regex_parts(v).is_some_and(|(pattern, _)| !pattern.is_empty())
            && valid_replace_by_regex(v);
    }
    v.starts_with("json:") || v.starts_with("jsonl:")
}

fn parse_pattern(
    p: &str,
    has_options: bool,
    exception: bool,
    f: &LineFlags,
) -> Result<Pattern, ParsedLine> {
    if p.is_empty() {
        return Ok(Pattern {
            kind: PatternKind::Plain,
            body: "*".into(),
            right_anchored: false,
        });
    }
    // Hosts file entry: `<ip-like prefix> host`.
    if f.has_ws && !exception && !has_options {
        if let Some(host) = hosts_host(p) {
            if is_hosts_redirect(host) || !is_hostname_ascii(host) {
                return Err(ParsedLine::Ignored);
            }
            return Ok(Pattern {
                kind: PatternKind::Hostname,
                body: host.into(),
                right_anchored: false,
            });
        }
    }
    let b = p.as_bytes();
    if p.len() > 2 && b[0] == b'/' && b[b.len() - 1] == b'/' {
        let source = &p[1..p.len() - 1];
        if !regex_is_valid(source) {
            return Err(invalid("invalid regular expression"));
        }
        return Ok(Pattern {
            kind: PatternKind::Regex,
            body: source.into(),
            right_anchored: false,
        });
    }

    let has_wild = p.contains('*');
    let mut rest = p;
    let mut kind = PatternKind::Plain;
    if let Some(r) = rest.strip_prefix("||") {
        if r.as_bytes().first().is_some_and(|&c| is_token(c)) {
            kind = PatternKind::Hostname;
        }
        rest = r;
    } else if let Some(r) = rest.strip_prefix('|') {
        if r.as_bytes().first().is_some_and(|&c| is_token(c)) {
            kind = PatternKind::Left;
        }
        rest = r;
    }
    let mut right_anchored = false;
    if let Some(r) = rest.strip_suffix('|') {
        right_anchored = !r.ends_with('*');
        rest = r;
    }
    if has_wild {
        // Leading wildcards before a non-alphanumeric character are dropped.
        // A run that cannot be taken whole gives back one star (regex backtracking).
        let l = rest.bytes().take_while(|&c| c == b'*').count();
        if l > 0 {
            let next_ok = rest[l..]
                .chars()
                .next()
                .is_some_and(is_leading_wildcard_stop);
            let strip = if next_ok { l } else { l.saturating_sub(1) };
            rest = &rest[strip..];
        }
    }
    if let Some(j) = rest.rfind('^') {
        if j >= 1 && rest.as_bytes()[j - 1] == b'*' && rest[j + 1..].bytes().all(|c| c == b'*') {
            rest = &rest[..j];
        }
    }
    if has_wild {
        let l = rest.bytes().rev().take_while(|&c| c == b'*').count();
        if l > 0 {
            let before = &rest[..rest.len() - l];
            let alnum = before.bytes().rev().take_while(|&c| is_token(c)).count();
            let strip = if alnum >= 7 || (!before.is_empty() && alnum == 0) {
                l
            } else {
                l.saturating_sub(1)
            };
            rest = &rest[..rest.len() - strip];
        }
    }

    if f.has_ws && rest.chars().any(char::is_whitespace) {
        return Err(invalid("pattern contains whitespace"));
    }
    let needs_normalization = rest.is_empty() || f.has_upper || f.has_unicode;
    let body = if needs_normalization {
        normalize_pattern(rest, f.has_unicode)?
    } else {
        rest.to_string()
    };
    if !has_options && is_hostname_ascii(&body) {
        kind = PatternKind::Hostname;
    }
    Ok(Pattern {
        kind,
        body,
        right_anchored,
    })
}

/// uBO `isTokenCharCode`: `%`, digits, letters.
fn is_token(c: u8) -> bool {
    c == b'%' || c.is_ascii_alphanumeric()
}

/// Characters that end a leading-wildcard run (`[^%0-9A-Za-z -]`).
fn is_leading_wildcard_stop(c: char) -> bool {
    (c as u32) < 0xA0 && c != '%' && !c.is_ascii_alphanumeric()
}

/// Hosts prefix: `^[\w%.:[\]-]+\s+`. Returns the host after it.
fn hosts_host(p: &str) -> Option<&str> {
    let b = p.as_bytes();
    let class = b
        .iter()
        .take_while(|&&c| is_word(c) || matches!(c, b'%' | b'.' | b':' | b'[' | b']' | b'-'))
        .count();
    let ws = b[class..]
        .iter()
        .take_while(|c| c.is_ascii_whitespace())
        .count();
    (class > 0 && ws > 0).then(|| &p[class + ws..])
}

/// uBO `reHostsRedirect`, unanchored: names that mark a localhost entry.
fn is_hosts_redirect(h: &str) -> bool {
    let b = h.as_bytes();
    let term = |i: usize| i >= b.len() || !(is_word(b[i]) || matches!(b[i], b'.' | b'-'));
    (0..b.len()).any(|i| {
        let r = &b[i..];
        if r.starts_with(b"0.0.0.0") {
            return term(i + 7);
        }
        if r.starts_with(b"broadcasthost") {
            return term(i + 13);
        }
        if r.starts_with(b"localhost") {
            let plain = term(i + 9);
            return plain || (r[9..].starts_with(b".localdomain") && term(i + 21));
        }
        if r.starts_with(b"local") {
            return term(i + 5);
        }
        if r.starts_with(b"ip6-") {
            let w = r[4..].iter().take_while(|&&c| is_word(c)).count();
            return w > 0 && term(i + 4 + w);
        }
        false
    })
}

/// uBO `reHostnameAscii`: lowercase labels, last label at least two characters.
fn is_hostname_ascii(s: &str) -> bool {
    let mut labels = s.split('.').peekable();
    while let Some(label) = labels.next() {
        let b = label.as_bytes();
        let Some((&first, rest)) = b.split_first() else {
            return false;
        };
        let ok = if labels.peek().is_some() {
            is_alnum_lower(first)
                && rest
                    .iter()
                    .all(|&c| is_alnum_lower(c) || c == b'_' || c == b'-')
        } else {
            !rest.is_empty()
                && is_alnum_lower(*rest.last().unwrap_or(&0))
                && is_alnum_lower(first)
                && rest[..rest.len() - 1]
                    .iter()
                    .all(|&c| is_alnum_lower(c) || c == b'-')
        };
        if !ok {
            return false;
        }
    }
    true
}

fn is_alnum_lower(c: u8) -> bool {
    c.is_ascii_digit() || c.is_ascii_lowercase()
}

fn is_word(c: u8) -> bool {
    c.is_ascii_alphanumeric() || c == b'_'
}

/// uBO `normalizePattern`: lowercase, punycode hostname labels, percent-encode
/// the rest. Fails on control and invisible characters.
fn normalize_pattern(s: &str, unicode: bool) -> Result<String, ParsedLine> {
    if s.is_empty() {
        return Ok("*".into());
    }
    if s.chars().any(is_invalid_pattern_char) {
        return Err(invalid("pattern contains a control or invisible character"));
    }
    let lower = s.to_lowercase();
    if !unicode {
        return Ok(lower);
    }
    let split = lower.find(is_hostname_excluded).unwrap_or(lower.len());
    let (host, tail) = lower.split_at(split);
    let mut out = String::with_capacity(lower.len() + 16);
    for (i, label) in host.split('.').enumerate() {
        if i > 0 {
            out.push('.');
        }
        if label.is_ascii() {
            out.push_str(label);
        } else {
            let wild = if label.starts_with('-') {
                format!("*{label}")
            } else {
                label.to_string()
            };
            out.push_str(&punycode_label(&wild).unwrap_or_else(|| wild.clone()));
        }
    }
    for c in tail.chars() {
        if c.is_ascii() {
            out.push(c);
        } else {
            let mut buf = [0u8; 4];
            for byte in c.encode_utf8(&mut buf).bytes() {
                out.push_str(&format!("%{byte:02x}"));
            }
        }
    }
    Ok(out)
}

/// IDNA of a label, keeping `*` literal (uBO swaps it for a placeholder).
fn punycode_label(s: &str) -> Option<String> {
    let ascii = idna::domain_to_ascii(&s.replace('*', "__asterisk__")).ok()?;
    Some(ascii.replace("__asterisk__", "*"))
}

/// uBO `reBadHostnameChars`-free characters that end a pattern's hostname
/// part (`reHostnamePatternPart` negated).
fn is_hostname_excluded(c: char) -> bool {
    let u = c as u32;
    u <= 0x24
        || (0x26..=0x29).contains(&u)
        || u == 0x2B
        || u == 0x2C
        || u == 0x2F
        || (0x3A..=0x40).contains(&u)
        || (0x5B..=0x5E).contains(&u)
        || u == 0x60
        || (0x7B..=0x7F).contains(&u)
}

/// uBO `reHasInvalidChar`.
fn is_invalid_pattern_char(c: char) -> bool {
    let u = c as u32;
    u <= 0x1F
        || (0x7F..=0x9F).contains(&u)
        || matches!(u, 0xAD | 0x61C | 0x2028 | 0x2029 | 0xFEFF)
        || (0x200B..=0x200F).contains(&u)
        || (0xFFF9..=0xFFFC).contains(&u)
}

/// Structural check of a JavaScript regex source (uBO compiles them with
/// `new RegExp`). Balanced groups and classes, no dangling quantifier, no
/// trailing backslash. Does not check ranges or backreferences.
fn regex_is_valid(src: &str) -> bool {
    let b = src.as_bytes();
    let n = b.len();
    let mut i = 0;
    let mut depth = 0usize;
    let mut quantifiable = false;
    while i < n {
        match b[i] {
            b'\\' => {
                if i + 1 >= n {
                    return false;
                }
                i += 2;
                quantifiable = true;
            }
            b'[' => {
                i += 1;
                if b.get(i) == Some(&b'^') {
                    i += 1;
                }
                loop {
                    match b.get(i) {
                        None => return false,
                        Some(b'\\') => i += 2,
                        Some(b']') => {
                            i += 1;
                            break;
                        }
                        Some(_) => i += 1,
                    }
                }
                quantifiable = true;
            }
            b'(' => {
                depth += 1;
                i += 1;
                quantifiable = false;
                if b.get(i) == Some(&b'?') {
                    match b.get(i + 1) {
                        Some(b':' | b'=' | b'!') => i += 2,
                        Some(b'<') if matches!(b.get(i + 2), Some(b'=' | b'!')) => i += 3,
                        Some(b'<') => match b[i + 2..].iter().position(|&c| c == b'>') {
                            Some(k) => i += 2 + k + 1,
                            None => return false,
                        },
                        _ => return false,
                    }
                }
            }
            b')' => {
                if depth == 0 {
                    return false;
                }
                depth -= 1;
                i += 1;
                quantifiable = true;
            }
            b'|' => {
                i += 1;
                quantifiable = false;
            }
            b'*' | b'+' | b'?' => {
                if !quantifiable {
                    return false;
                }
                i += 1;
                if b.get(i) == Some(&b'?') {
                    i += 1;
                }
                quantifiable = false;
            }
            b'{' => match quantifier_end(b, i) {
                Some(end) => {
                    if !quantifiable {
                        return false;
                    }
                    i = end;
                    if b.get(i) == Some(&b'?') {
                        i += 1;
                    }
                    quantifiable = false;
                }
                None => {
                    i += 1;
                    quantifiable = true;
                }
            },
            b'^' | b'$' => {
                i += 1;
                quantifiable = false;
            }
            _ => {
                i += 1;
                quantifiable = true;
            }
        }
    }
    depth == 0
}

/// End index of a `{n}`, `{n,}` or `{n,m}` quantifier starting at `i`.
fn quantifier_end(b: &[u8], i: usize) -> Option<usize> {
    let digits = |mut j: usize| {
        let start = j;
        while b.get(j).is_some_and(u8::is_ascii_digit) {
            j += 1;
        }
        (j > start).then_some(j)
    };
    let mut j = digits(i + 1)?;
    if b.get(j) == Some(&b',') {
        j = digits(j + 1).unwrap_or(j + 1);
    }
    (b.get(j) == Some(&b'}')).then_some(j + 1)
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum DomainMode {
    /// `$from`, `$to`, `$top`: entities, negation and `/regex/` allowed.
    Net,
    /// `$denyallow`: plain hostnames only.
    Deny,
}

/// uBO `parseDomainList` plus `normalizeDomainValue`. Each entry is
/// `(negated, matcher)`.
fn parse_domains(value: &str, mode: DomainMode) -> Result<Vec<(bool, DomainMatcher)>, String> {
    let b = value.as_bytes();
    let n = b.len();
    let mut out = Vec::new();
    let mut beg = 0;
    loop {
        let mut p = beg;
        let neg = b.get(p) == Some(&b'~');
        if neg {
            if mode == DomainMode::Deny {
                return Err("negated domain in $denyallow".into());
            }
            p += 1;
        }
        let entry_end;
        let matcher = if mode == DomainMode::Net && b.get(p) == Some(&b'/') {
            let (close, _) = scan_separator(value, p + 1, '/');
            if close >= n {
                return Err("unterminated regex domain".into());
            }
            entry_end = close + 1;
            // uBO turns escaped `\|` into `|` before compiling the regex.
            let raw = value[p..entry_end].replace("\\|", "|");
            let source = &raw[1..raw.len() - 1];
            if source.is_empty() || !regex_is_valid(source) {
                return Err("invalid regex domain".into());
            }
            DomainMatcher::Regex(source.into())
        } else {
            let end = value[p..].find('|').map_or(n, |k| p + k);
            entry_end = end;
            let text = &value[p..end];
            if text.is_empty() {
                return Err("empty domain".into());
            }
            let hostname = normalize_hostname(text, mode == DomainMode::Net)
                .ok_or_else(|| format!("invalid domain `{text}`"))?;
            match hostname.strip_suffix(".*") {
                Some(label) if mode == DomainMode::Net => DomainMatcher::Entity(label.into()),
                _ => DomainMatcher::Hostname(hostname),
            }
        };
        out.push((neg, matcher));
        if entry_end == n {
            return Ok(out);
        }
        if b[entry_end] != b'|' || entry_end + 1 == n {
            return Err("bad domain separator".into());
        }
        beg = entry_end + 1;
    }
}

/// uBO `normalizeHostnameValue`: lowercase, punycode, wildcard rules. `net`
/// enables entity (`google.*`) wildcards.
fn normalize_hostname(s: &str, net: bool) -> Option<String> {
    if is_hostname_ascii(s) {
        return Some(s.into());
    }
    if s.bytes().any(|c| {
        matches!(c, 0x00..=0x24 | 0x26..=0x29 | 0x2B | 0x2C | 0x2F | 0x3B..=0x40 | 0x5C | 0x5E | 0x60 | 0x7B..=0x7F)
    }) {
        return None;
    }
    if s.contains('*') {
        if !net || s.len() == 1 {
            return None;
        }
        if is_plain_entity(s) {
            return Some(s.into());
        }
        let prefix = s.strip_suffix(".*")?;
        if prefix.is_empty() || prefix.contains('*') {
            return None;
        }
    }
    let hn = if s.is_ascii() {
        s.to_ascii_lowercase()
    } else {
        punycode_label(s)?
    };
    if hn.is_empty() || hn == "_" || hn.starts_with('.') || hn.ends_with('.') {
        return None;
    }
    Some(hn)
}

/// uBO `rePlainEntity`: `^(?:label\.)+\*$`.
fn is_plain_entity(s: &str) -> bool {
    let Some(prefix) = s.strip_suffix(".*") else {
        return false;
    };
    prefix.split('.').all(|label| {
        let b = label.as_bytes();
        b.first().is_some_and(|&c| is_alnum_lower(c))
            && b[1..]
                .iter()
                .all(|&c| is_alnum_lower(c) || c == b'_' || c == b'-')
    })
}

fn domain_list(entries: Vec<(bool, DomainMatcher)>) -> DomainList {
    let mut list = DomainList::default();
    for (neg, matcher) in entries {
        if neg {
            list.exclude.push(matcher);
        } else {
            list.include.push(matcher);
        }
    }
    list
}

fn method_list(v: &str) -> MethodList {
    const METHODS: [&str; 8] = [
        "connect", "delete", "get", "head", "options", "patch", "post", "put",
    ];
    let mut list = MethodList::default();
    for item in v.split('|') {
        let (neg, name) = match item.strip_prefix('~') {
            Some(rest) => (true, rest),
            None => (false, item),
        };
        let lower = name.to_ascii_lowercase();
        if !(name == lower || name == lower.to_ascii_uppercase()) {
            continue;
        }
        let Some(method) = METHODS.iter().find(|&&m| m == lower) else {
            continue;
        };
        if neg {
            list.exclude.push((*method).into());
        } else {
            list.include.push((*method).into());
        }
    }
    let excluded = list.exclude.clone();
    list.include.retain(|m| !excluded.contains(m));
    list
}

fn build(
    source: SourceRef,
    line: &str,
    exception: bool,
    pattern: Pattern,
    opts: &[NetOpt],
) -> Result<NetworkRule, ParsedLine> {
    let mut rule = NetworkRule {
        source,
        raw: line.into(),
        exception,
        pattern,
        ..Default::default()
    };
    let mut types = ResourceTypes::empty();
    let mut neg_types = ResourceTypes::empty();
    let mut scope = ExceptionScope::empty();
    let mut action: Option<NetworkAction> = None;
    let mut header = None;
    let mut runtime = Vec::new();
    let (mut first, mut third) = (false, false);
    let mut strict = 0i8;
    for o in opts {
        let v = o.value.as_deref();
        if let Some(t) = type_of(o.opt) {
            if o.neg {
                neg_types |= t;
            } else {
                types |= t;
            }
        }
        match o.opt {
            Opt::All => types |= ALL_TYPES,
            Opt::P1 if o.neg => third = true,
            Opt::P1 => first = true,
            Opt::P3 if o.neg => first = true,
            Opt::P3 => third = true,
            Opt::Strict1p => strict = if strict == -1 { 0 } else { 1 },
            Opt::Strict3p => strict = if strict == 1 { 0 } else { -1 },
            Opt::Doc if exception && !o.neg => scope |= ExceptionScope::DOC,
            Opt::Ehide => scope |= ExceptionScope::EHIDE,
            Opt::Ghide => scope |= ExceptionScope::GHIDE,
            Opt::Shide => scope |= ExceptionScope::SHIDE,
            Opt::Genericblock => scope |= ExceptionScope::GENERICBLOCK,
            Opt::Badfilter => rule.badfilter = true,
            Opt::Important => rule.important = true,
            Opt::MatchCase => rule.match_case = true,
            Opt::Redirect | Opt::RedirectRule => {
                action = Some(NetworkAction::Redirect {
                    resource: canonical_resource(redirect_token(v.unwrap_or(""))),
                    rule_only: exception || o.opt == Opt::RedirectRule,
                });
            }
            Opt::Empty => {
                action = Some(NetworkAction::Redirect {
                    resource: "empty".into(),
                    rule_only: exception,
                });
            }
            Opt::Mp4 => {
                action = Some(NetworkAction::Redirect {
                    resource: canonical_resource("noopmp4-1s"),
                    rule_only: exception,
                });
            }
            Opt::Removeparam => action = Some(NetworkAction::RemoveParam(v.map(Into::into))),
            Opt::Csp => action = Some(NetworkAction::Csp(v.map(Into::into))),
            Opt::Permissions => action = Some(NetworkAction::Permissions(v.map(Into::into))),
            Opt::Replace | Opt::Urlskip | Opt::Urltransform => {
                let option = match o.opt {
                    Opt::Replace => "replace",
                    Opt::Urlskip => "urlskip",
                    _ => "uritransform",
                };
                action = Some(NetworkAction::Other {
                    option: option.into(),
                    value: v.map(Into::into),
                });
            }
            Opt::Requestheader => header = Some(v),
            Opt::Responseheader => runtime.push(with_value("responseheader", v)),
            Opt::Ipaddress => runtime.push(with_value("ipaddress", v)),
            Opt::Cname => runtime.push("cname".into()),
            Opt::Top => {
                parse_domains(v.unwrap_or(""), DomainMode::Net).map_err(|e| invalid(&e))?;
                runtime.push(with_value("top", v));
            }
            Opt::From => {
                let entries =
                    parse_domains(v.unwrap_or(""), DomainMode::Net).map_err(|e| invalid(&e))?;
                rule.from = domain_list(entries);
            }
            Opt::To => {
                let entries =
                    parse_domains(v.unwrap_or(""), DomainMode::Net).map_err(|e| invalid(&e))?;
                rule.to = domain_list(entries);
            }
            Opt::Denyallow => {
                let entries =
                    parse_domains(v.unwrap_or(""), DomainMode::Deny).map_err(|e| invalid(&e))?;
                rule.denyallow = entries
                    .into_iter()
                    .filter_map(|(_, m)| match m {
                        DomainMatcher::Hostname(h) => Some(h),
                        _ => None,
                    })
                    .collect();
            }
            Opt::Method => rule.method = method_list(v.unwrap_or("")),
            _ => {}
        }
    }
    if let Some(v) = header {
        if action.is_none() {
            action = Some(NetworkAction::Other {
                option: "requestheader".into(),
                value: v.map(Into::into),
            });
        } else {
            runtime.push(with_value("requestheader", v));
        }
    }

    // uBO: `~type` only removes bits when some type is already present.
    if !types.is_empty() || !scope.is_empty() {
        types &= !neg_types | NETWORK_TYPES;
    }
    if matches!(
        action,
        Some(NetworkAction::Csp(_) | NetworkAction::Permissions(_))
    ) && types.is_empty()
        && scope.is_empty()
    {
        types = ResourceTypes::DOC | ResourceTypes::FRAME;
    }
    if scope == ExceptionScope::GENERICBLOCK && types.is_empty() {
        return Err(unsupported("$genericblock without a request type"));
    }
    if !exception && types.is_empty() && !scope.is_empty() {
        return Err(unsupported(
            "document-level option on a blocking rule never matches a request",
        ));
    }

    rule.party = match (strict, first, third) {
        (1, _, _) => Party::StrictFirst,
        (-1, _, _) => Party::StrictThird,
        (_, true, false) => Party::First,
        (_, false, true) => Party::Third,
        _ => Party::Any,
    };
    rule.types = types;
    rule.negated_types = neg_types;
    rule.scope = scope;
    rule.action = action.unwrap_or_default();
    rule.runtime_only_options = runtime;
    Ok(rule)
}

fn with_value(name: &str, v: Option<&str>) -> String {
    match v {
        Some(v) => format!("{name}={v}"),
        None => name.into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn describe(line: &str) -> String {
        match parse(line, SourceRef::default()) {
            ParsedLine::Ignored => "ignored".into(),
            ParsedLine::Unsupported { .. } => "unsupported".into(),
            ParsedLine::Invalid { reason } => format!("invalid: {reason}"),
            ParsedLine::Rule(Rule::Network(r)) => summary(&r),
            other => format!("{other:?}"),
        }
    }

    fn summary(r: &NetworkRule) -> String {
        let mut out = String::new();
        if r.exception {
            out.push_str("@@");
        }
        match r.pattern.kind {
            PatternKind::Hostname => out.push_str("||"),
            PatternKind::Left => out.push('|'),
            _ => {}
        }
        if r.pattern.kind == PatternKind::Regex {
            out.push_str(&format!("/{}/", r.pattern.body));
        } else {
            out.push_str(&r.pattern.body);
        }
        if r.pattern.right_anchored {
            out.push('|');
        }
        let mut opts: Vec<String> = Vec::new();
        let names = [
            (ResourceTypes::SCRIPT, "script"),
            (ResourceTypes::IMAGE, "image"),
            (ResourceTypes::CSS, "css"),
            (ResourceTypes::OBJECT, "object"),
            (ResourceTypes::XHR, "xhr"),
            (ResourceTypes::FRAME, "frame"),
            (ResourceTypes::DOC, "doc"),
            (ResourceTypes::FONT, "font"),
            (ResourceTypes::MEDIA, "media"),
            (ResourceTypes::PING, "ping"),
            (ResourceTypes::WEBSOCKET, "websocket"),
            (ResourceTypes::OTHER, "other"),
            (ResourceTypes::POPUP, "popup"),
            (ResourceTypes::POPUNDER, "popunder"),
            (ResourceTypes::INLINE_FONT, "inline-font"),
            (ResourceTypes::INLINE_SCRIPT, "inline-script"),
        ];
        let list = |bits: ResourceTypes, prefix: &str| -> Vec<String> {
            names
                .iter()
                .filter(|(t, _)| bits.contains(*t))
                .map(|(_, n)| format!("{prefix}{n}"))
                .collect()
        };
        opts.extend(list(r.types, ""));
        opts.extend(list(r.negated_types, "~"));
        match r.party {
            Party::Any => {}
            Party::First => opts.push("1p".into()),
            Party::Third => opts.push("3p".into()),
            Party::StrictFirst => opts.push("strict1p".into()),
            Party::StrictThird => opts.push("strict3p".into()),
        }
        let scope = [
            (ExceptionScope::DOC, "doc"),
            (ExceptionScope::EHIDE, "ehide"),
            (ExceptionScope::GHIDE, "ghide"),
            (ExceptionScope::SHIDE, "shide"),
            (ExceptionScope::GENERICBLOCK, "genericblock"),
        ];
        for (flag, name) in scope {
            if r.scope.contains(flag) {
                opts.push(format!("scope:{name}"));
            }
        }
        match &r.action {
            NetworkAction::Block => {}
            NetworkAction::Redirect {
                resource,
                rule_only,
            } => {
                let kind = if *rule_only {
                    "redirect-rule"
                } else {
                    "redirect"
                };
                opts.push(format!("{kind}={resource}"));
            }
            NetworkAction::RemoveParam(v) => opts.push(opt_value("removeparam", v)),
            NetworkAction::Csp(v) => opts.push(opt_value("csp", v)),
            NetworkAction::Permissions(v) => opts.push(opt_value("permissions", v)),
            NetworkAction::Other { option, value } => opts.push(opt_value(option, value)),
        }
        if r.important {
            opts.push("important".into());
        }
        if r.badfilter {
            opts.push("badfilter".into());
        }
        if r.match_case {
            opts.push("match-case".into());
        }
        if !r.from.is_empty() {
            opts.push(format!("from={}", domains(&r.from)));
        }
        if !r.to.is_empty() {
            opts.push(format!("to={}", domains(&r.to)));
        }
        if !r.denyallow.is_empty() {
            opts.push(format!("denyallow={}", r.denyallow.join("|")));
        }
        if !r.method.include.is_empty() || !r.method.exclude.is_empty() {
            let mut m: Vec<String> = r.method.include.clone();
            m.extend(r.method.exclude.iter().map(|x| format!("~{x}")));
            opts.push(format!("method={}", m.join("|")));
        }
        opts.extend(r.runtime_only_options.iter().map(|o| format!("rt:{o}")));
        if !opts.is_empty() {
            out.push_str(" $");
            out.push_str(&opts.join(","));
        }
        out
    }

    fn opt_value(name: &str, v: &Option<String>) -> String {
        match v {
            Some(v) => format!("{name}={v}"),
            None => name.into(),
        }
    }

    fn domains(list: &DomainList) -> String {
        let one = |m: &DomainMatcher| match m {
            DomainMatcher::Hostname(h) => h.clone(),
            DomainMatcher::Entity(e) => format!("{e}.*"),
            DomainMatcher::Regex(r) => format!("/{r}/"),
        };
        let mut parts: Vec<String> = list.include.iter().map(one).collect();
        parts.extend(list.exclude.iter().map(|m| format!("~{}", one(m))));
        parts.join("|")
    }

    /// True for lines with a cosmetic, scriptlet or HTML marker (`##`, `#@#`,
    /// `#?#`, `#$#`, `#%#`, ...), which the cosmetic parser owns.
    fn has_cosmetic_marker(line: &str) -> bool {
        let b = line.as_bytes();
        (0..b.len()).any(|i| {
            if b[i] != b'#' {
                return false;
            }
            let mut j = i + 1;
            if b.get(j) == Some(&b'@') {
                j += 1;
            }
            if matches!(b.get(j), Some(b'$' | b'?' | b'%')) {
                j += 1;
            }
            b.get(j) == Some(&b'#')
        })
    }

    /// (line, expected `describe` output). Expectations follow uBO's parser.
    const CASES: &[(&str, &str)] = &[
        // Patterns and anchors
        ("||example.com^", "||example.com^"),
        ("||example.com/path/to/resource", "||example.com/path/to/resource"),
        ("||example.com^|", "||example.com^|"),
        ("||example.com|", "||example.com|"),
        ("|https://example.com/ads", "|https://example.com/ads"),
        ("example.com/ads|", "example.com/ads|"),
        ("|example.com", "||example.com"),
        ("|example.com/", "|example.com/"),
        ("||ads.example.com^*", "||ads.example.com^"),
        ("*/ads/*", "/ads/"),
        ("||*.example.com^", ".example.com^"),
        ("foo*", "foo*"),
        ("foo.bar*", "foo.bar*"),
        ("abcdefgh*", "||abcdefgh"),
        ("ad**", "ad*"),
        ("/ads/**", "/ads/"),
        ("||example.com^|$image", "||example.com^| $image"),
        ("Example.com", "||example.com"),
        ("||Example.com^$domain=Foo.COM", "||example.com^ $from=foo.com"),
        ("||exämple.com^", "||xn--exmple-cua.com^"),
        ("||example.com/ü", "||example.com/%c3%bc"),
        ("*$image", "* $image"),
        ("@@$~document", "@@* $~doc"),
        ("foo bar", "||bar"),
        ("||foo bar^", "invalid: pattern contains whitespace"),
        ("*", "invalid: pattern is too short without options"),
        ("@@", "invalid: pattern is too short without options"),
        // Regex patterns
        ("/banner[0-9]+/", "/banner[0-9]+/"),
        ("/banner[0-9]+/$image,script", "/banner[0-9]+/ $script,image"),
        ("/^ads?\\.js$/", "/^ads?\\.js$/"),
        ("/a$b/$image", "/a$b/ $image"),
        ("/abc/$match-case", "/abc/ $match-case"),
        ("/a(/", "invalid: invalid regular expression"),
        ("/a)/", "invalid: invalid regular expression"),
        ("/[a/", "invalid: invalid regular expression"),
        ("/a**/", "invalid: invalid regular expression"),
        ("/\\/", "invalid: invalid regular expression"),
        ("/a$image/", "invalid: trailing option separator"),
        ("||example.com^$match-case", "invalid: $match-case is only valid on regular expression patterns"),
        // Hosts-file lines
        ("0.0.0.0 ads.example.com", "||ads.example.com"),
        ("127.0.0.1 ads.example.com", "||ads.example.com"),
        ("::1 ads.example.com", "||ads.example.com"),
        ("0.0.0.0 ads.example.com # comment", "||ads.example.com"),
        ("ads.example.com # comment", "||ads.example.com"),
        ("127.0.0.1 localhost", "ignored"),
        ("::1 localhost", "ignored"),
        ("0.0.0.0 0.0.0.0", "ignored"),
        ("255.255.255.255 broadcasthost", "ignored"),
        ("127.0.0.1 local", "ignored"),
        ("0.0.0.0 Ads.example.com", "ignored"),
        ("127.0.0.1 localhost.localdomain", "||localhost.localdomain"),
        ("# just a comment", "ignored"),
        // Request types and aliases
        ("||example.com^$script", "||example.com^ $script"),
        ("||example.com^$image", "||example.com^ $image"),
        ("||example.com^$stylesheet", "||example.com^ $css"),
        ("||example.com^$css", "||example.com^ $css"),
        ("||example.com^$font", "||example.com^ $font"),
        ("||example.com^$media", "||example.com^ $media"),
        ("||example.com^$object-subrequest", "||example.com^ $object"),
        ("||example.com^$object", "||example.com^ $object"),
        ("||example.com^$other", "||example.com^ $other"),
        ("||example.com^$xmlhttprequest", "||example.com^ $xhr"),
        ("||example.com^$xhr", "||example.com^ $xhr"),
        ("||example.com^$subdocument", "||example.com^ $frame"),
        ("||example.com^$frame", "||example.com^ $frame"),
        ("||example.com^$beacon", "||example.com^ $ping"),
        ("||example.com^$ping", "||example.com^ $ping"),
        ("||example.com^$websocket", "||example.com^ $websocket"),
        ("||example.com^$document", "||example.com^ $doc"),
        ("||example.com^$doc", "||example.com^ $doc"),
        ("||example.com^$popup", "||example.com^ $popup"),
        ("||example.com^$popunder", "||example.com^ $popunder"),
        ("||example.com^$inline-font", "||example.com^ $inline-font"),
        ("||example.com^$inline-script", "||example.com^ $inline-script"),
        ("||example.com^$~script", "||example.com^ $~script"),
        ("||example.com^$script,~image", "||example.com^ $script,~image"),
        ("||example.com^$~script,image", "||example.com^ $image,~script"),
        ("||example.com^$~stylesheet", "||example.com^ $~css"),
        ("||example.com^$~doc", "||example.com^ $~doc"),
        ("||example.com^$subdocument,xmlhttprequest,websocket,beacon,object-subrequest,other,stylesheet",
            "||example.com^ $css,object,xhr,frame,ping,websocket,other"),
        ("||example.com^$all", "||example.com^ $script,image,css,object,xhr,frame,doc,font,media,ping,websocket,other,popup,inline-font,inline-script"),
        ("||example.com^$mp4", "||example.com^ $media,redirect=noop-1s.mp4"),
        ("||example.com^$mp4,media", "invalid: $mp4 cannot combine with other types"),
        // Party
        ("||example.com^$third-party", "||example.com^ $3p"),
        ("||example.com^$3p", "||example.com^ $3p"),
        ("||example.com^$first-party", "||example.com^ $1p"),
        ("||example.com^$1p", "||example.com^ $1p"),
        ("||example.com^$~third-party", "||example.com^ $1p"),
        ("||example.com^$~1p", "||example.com^ $3p"),
        ("||example.com^$1p,3p", "||example.com^"),
        ("||example.com^$strict1p", "||example.com^ $strict1p"),
        ("||example.com^$strict-third-party", "||example.com^ $strict3p"),
        ("||example.com^$~1p,strict3p", "||example.com^ $strict3p"),
        ("||example.com^$strict1p,3p", "||example.com^ $strict1p"),
        ("||example.com^$third-party,3p", "invalid: duplicate option `3p`"),
        // Flags and no-ops
        ("||example.com^$important", "||example.com^ $important"),
        ("@@||example.com^$important", "invalid: $important is only valid on blocking rules"),
        ("||example.com^$badfilter", "||example.com^ $badfilter"),
        ("||example.com^$_", "||example.com^"),
        ("||example.com^$_,image", "||example.com^ $image"),
        ("||example.com^$reason=blah", "||example.com^"),
        ("||example.com^$reason", "invalid: $reason needs a value"),
        ("||example.com^$webrtc", "invalid: $webrtc is not supported"),
        ("||example.com^$foo", "||example.com^$foo"),
        ("||example.com^$image,", "invalid: trailing option separator"),
        ("||example.com^$image,image", "invalid: duplicate option `image`"),
        ("||example.com^$image,Image", "invalid: unknown option at `Image`"),
        // Domains
        ("||example.com^$domain=a.com|~b.com|google.*", "||example.com^ $from=a.com|google.*|~b.com"),
        ("||example.com^$from=/re\\.x/|~c.org", "||example.com^ $from=/re\\.x/|~c.org"),
        ("||example.com^$domain=a.com,image", "||example.com^ $image,from=a.com"),
        ("||example.com^$domain=~/foo\\.com/|a.com", "||example.com^ $from=a.com|~/foo\\.com/"),
        ("||example.com^$domain=google.*|~google.de", "||example.com^ $from=google.*|~google.de"),
        ("||example.com^$to=a.com|~b.com", "||example.com^ $to=a.com|~b.com"),
        ("||example.com^$from=a.com,to=b.com", "||example.com^ $from=a.com,to=b.com"),
        ("||example.com^$domain=*.example.com", "invalid: invalid domain `*.example.com`"),
        ("||example.com^$domain=a.com||b.com", "invalid: empty domain"),
        ("||example.com^$domain=|a.com", "invalid: empty domain"),
        ("||example.com^$domain=a.com|", "invalid: bad domain separator"),
        ("||example.com^$domain=~", "invalid: empty domain"),
        ("||example.com^$denyallow=a.com", "invalid: $denyallow needs $from and a value"),
        ("||example.com^$domain=c.com,denyallow=a.com|b.com", "||example.com^ $from=c.com,denyallow=a.com|b.com"),
        ("||example.com^$domain=c.com,denyallow=a.com|~b.com", "invalid: negated domain in $denyallow"),
        ("||example.com^$domain=c.com,denyallow=*.a.com", "invalid: invalid domain `*.a.com`"),
        // Method
        ("||example.com^$method=get|~post", "||example.com^ $method=get|~post"),
        ("||example.com^$method=get|post,image", "||example.com^ $image,method=get|post"),
        // Redirects
        ("||example.com^$redirect=googlesyndication.com/adsbygoogle.js", "||example.com^ $redirect=googlesyndication.com/adsbygoogle.js"),
        ("||example.com^$redirect=noopjs", "||example.com^ $redirect=noop.js"),
        ("||example.com^$redirect=\"noopjs\"", "||example.com^ $redirect=noop.js"),
        ("||example.com^$rewrite=noopjs", "||example.com^ $redirect=noop.js"),
        ("||example.com^$redirect=%1x1.gif:10", "||example.com^ $redirect=1x1.gif"),
        ("||example.com^$redirect-rule=noopjs", "||example.com^ $redirect-rule=noop.js"),
        ("||example.com^$redirect-rule=noopmp4-1s", "||example.com^ $redirect-rule=noop-1s.mp4"),
        ("||example.com^$empty", "||example.com^ $redirect=empty"),
        ("||example.com^$empty,image", "||example.com^ $image,redirect=empty"),
        ("||example.com^$redirect", "invalid: invalid redirect or header rewrite combination"),
        ("||example.com^$redirect=noopjs,redirect-rule=noopjs", "invalid: invalid redirect or header rewrite combination"),
        ("||example.com^$inline-script,redirect=noopjs", "invalid: invalid redirect or header rewrite combination"),
        ("||example.com^$redirect=noopjs,inline-script", "||example.com^ $inline-script,redirect=noop.js"),
        ("||example.com^$all,redirect=noopjs", "||example.com^ $script,image,css,object,xhr,frame,doc,font,media,ping,websocket,other,popup,inline-font,inline-script,redirect=noop.js"),
        ("||example.com^$redirect=noopjs,all", "invalid: $all takes no value and cannot follow a modifier"),
        ("@@||example.com^$redirect=noopjs", "@@||example.com^ $redirect-rule=noop.js"),
        ("@@||example.com^$redirect=noopjs,cname", "@@||example.com^ $redirect-rule=noop.js,rt:cname"),
        // removeparam
        ("||example.com^$removeparam=utm_source", "||example.com^ $removeparam=utm_source"),
        ("||example.com^$removeparam", "||example.com^ $removeparam"),
        ("||example.com^$queryprune=utm_source", "||example.com^ $removeparam=utm_source"),
        ("@@||example.com^$removeparam", "@@||example.com^ $removeparam"),
        ("||example.com^$removeparam=/a,b/", "||example.com^ $removeparam=/a,b/"),
        ("||example.com^$removeparam=\"a,b\"", "||example.com^ $removeparam=a,b"),
        ("||example.com^$removeparam=~utm_source", "||example.com^ $removeparam=~utm_source"),
        ("||example.com^$removeparam=a\\,b", "invalid: unknown option `b`"),
        ("||example.com^$removeparam=a,image", "||example.com^ $image,removeparam=a"),
        // csp and permissions
        ("||example.com^$csp=script-src 'none'", "||example.com^ $frame,doc,csp=script-src 'none'"),
        ("@@||example.com^$csp", "@@||example.com^ $frame,doc,csp"),
        ("||example.com^$csp", "invalid: invalid $csp or $permissions combination"),
        ("||example.com^$csp=report-to x", "invalid: invalid $csp or $permissions combination"),
        ("||example.com^$csp=report-uri /x", "invalid: invalid $csp or $permissions combination"),
        ("||example.com^$csp=a,report-uri=/x", "invalid: unknown option `report-uri`"),
        ("||example.com^$document,csp=a", "||example.com^ $doc,csp=a"),
        ("||example.com^$image,csp=a", "invalid: $csp, $permissions and $cname cannot combine with request types"),
        ("@@||example.com^$csp=a,script", "invalid: $csp, $permissions and $cname cannot combine with request types"),
        ("||example.com^$permissions=camera=()", "||example.com^ $frame,doc,permissions=camera=()"),
        // replace, urlskip, uritransform, requestheader
        ("||example.com^$replace=/foo/bar/i", "||example.com^ $replace=/foo/bar/i"),
        ("||example.com^$replace=/foo/bar", "invalid: invalid $replace value"),
        ("||example.com^$urlskip=a", "invalid: $urlskip value is too short"),
        ("@@||example.com^$urlskip=a", "@@||example.com^ $urlskip=a"),
        ("||example.com^$uritransform=/a/b/g", "||example.com^ $uritransform=/a/b/g"),
        ("||example.com^$uritransform=x", "invalid: invalid $uritransform value"),
        ("||example.com^$requestheader=user-agent:x", "||example.com^ $requestheader=user-agent:x"),
        ("||example.com^$requestheader=user-agent:x,replace=/a/b/", "||example.com^ $replace=/a/b/,rt:requestheader=user-agent:x"),
        // Runtime-only options
        ("@@||example.com^$cname", "@@||example.com^ $rt:cname"),
        ("||example.com^$cname,image", "invalid: $cname is only valid on exceptions without a value"),
        ("||example.com^$ipaddress=1.2.3.4", "||example.com^ $rt:ipaddress=1.2.3.4"),
        ("||example.com^$header=set-cookie:foo", "||example.com^ $rt:responseheader=set-cookie:foo"),
        ("||example.com^$responseheader", "invalid: header option needs a value and cannot be negated"),
        // Exceptions and document scopes
        ("@@||example.com^$document", "@@||example.com^ $doc,scope:doc"),
        ("@@||example.com^$elemhide", "@@||example.com^ $scope:ehide"),
        ("@@||example.com^$elemhide,script", "@@||example.com^ $script,scope:ehide"),
        ("@@||example.com^$generichide", "@@||example.com^ $scope:ghide"),
        ("@@||example.com^$specifichide", "@@||example.com^ $scope:shide"),
        ("@@||example.com^$doc,elemhide", "@@||example.com^ $doc,scope:doc,scope:ehide"),
        ("@@||example.com^$genericblock", "unsupported"),
        ("@@||example.com^$genericblock,script", "@@||example.com^ $script,scope:genericblock"),
        ("||example.com^$genericblock", "invalid: $genericblock is only valid on exceptions"),
        ("||example.com^$elemhide", "unsupported"),
        // Lines that are not options
        ("||example.com^$domain=a.com$image", "||example.com^$domain=a.com $image"),
        ("||example.com^$$script", "||example.com^$ $script"),
    ];

    fn check(cases: &[(&str, &str)]) {
        let failures: Vec<String> = cases
            .iter()
            .filter_map(|(line, want)| {
                let got = describe(line);
                (got != *want).then(|| format!("{line}\n    want: {want}\n    got:  {got}"))
            })
            .collect();
        assert!(
            failures.is_empty(),
            "{} case(s) failed:\n{}",
            failures.len(),
            failures.join("\n")
        );
    }

    #[test]
    fn table_cases() {
        assert!(CASES.len() >= 80);
        check(CASES);
    }

    #[test]
    fn raw_and_source_pass_through() {
        let source = SourceRef { list: 3, line: 17 };
        let line = "||example.com^$image,domain=a.com";
        let ParsedLine::Rule(Rule::Network(rule)) = parse(line, source) else {
            panic!("expected a network rule");
        };
        assert_eq!(rule.raw, line);
        assert_eq!(rule.source, source);
    }

    #[test]
    fn pattern_kinds_and_anchors() {
        let rule = |line: &str| match parse(line, SourceRef::default()) {
            ParsedLine::Rule(Rule::Network(r)) => r,
            other => panic!("{line}: {other:?}"),
        };
        assert_eq!(rule("|https://a.com/").pattern.kind, PatternKind::Left);
        assert_eq!(rule("||a.com/x").pattern.kind, PatternKind::Hostname);
        assert_eq!(rule("a.com/x").pattern.kind, PatternKind::Plain);
        assert_eq!(rule("/x+/").pattern.kind, PatternKind::Regex);
        assert!(rule("a.com/x|").pattern.right_anchored);
        assert!(!rule("a.com/x|*").pattern.right_anchored);
        assert!(rule("||a.com^$image").pattern.body.ends_with('^'));
        assert!(rule("@@||a.com^").exception);
        assert!(rule("@@||a.com^").pattern.body == "a.com^");
    }

    #[test]
    fn network_action_defaults_to_block() {
        let ParsedLine::Rule(Rule::Network(r)) = parse("||a.com^$image", SourceRef::default())
        else {
            panic!("expected rule");
        };
        assert_eq!(r.action, NetworkAction::Block);
        assert_eq!(r.types, ResourceTypes::IMAGE);
        assert!(r.negated_types.is_empty());
    }

    fn read_list(name: &str) -> Option<String> {
        let dir = std::env::var("WBE_FILTER_LISTS").unwrap_or_else(|_| "/tmp/wbe-lists".into());
        std::fs::read_to_string(format!("{dir}/{name}")).ok()
    }

    #[test]
    fn full_lists_parse_and_count_invalid() {
        let mut total = 0usize;
        let mut invalid = std::collections::BTreeMap::<String, (usize, String)>::new();
        let mut parse_ms = [0f64; 2];
        for (slot, name) in ["easylist.txt", "ubo-filters.txt"].iter().enumerate() {
            let Some(text) = read_list(name) else {
                eprintln!("skipping {name}: not found (set WBE_FILTER_LISTS)");
                continue;
            };
            let lines: Vec<&str> = text
                .lines()
                .map(str::trim)
                .filter(|l| {
                    !(l.is_empty()
                        || l.starts_with('!')
                        || l.starts_with('[')
                        || has_cosmetic_marker(l))
                })
                .collect();
            let start = std::time::Instant::now();
            let results: Vec<ParsedLine> = lines
                .iter()
                .map(|l| parse(l, SourceRef::default()))
                .collect();
            parse_ms[slot] = start.elapsed().as_secs_f64() * 1000.0;
            for (line, result) in lines.iter().zip(results) {
                total += 1;
                if let ParsedLine::Invalid { reason } = result {
                    invalid.entry(reason).or_insert((0, line.to_string())).0 += 1;
                }
            }
        }
        let invalid_total: usize = invalid.values().map(|(n, _)| n).sum();
        println!("network lines: {total}, invalid: {invalid_total}, parse time ms: easylist {:.1}, ubo {:.1}", parse_ms[0], parse_ms[1]);
        for (reason, (n, example)) in &invalid {
            println!("  invalid x{n}: {reason}\n    e.g. {example}");
        }
        assert!(
            invalid_total * 1000 <= total.max(1),
            "too many invalid lines"
        );
        #[cfg(not(debug_assertions))]
        assert!(
            parse_ms[0] < 50.0,
            "EasyList parse took {:.1} ms",
            parse_ms[0]
        );
    }
}
