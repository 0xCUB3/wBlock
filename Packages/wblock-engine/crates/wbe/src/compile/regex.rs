//! uBO URL patterns and regexes to WebKit's url-filter regex subset.
//!
//! Plain patterns follow AdGuard's SimpleRegex.swift (`||`, `|`, `*`, `^`).
//! The separator is uBO's (`^` matches anything but a letter, digit, `_`, `-`,
//! `.` or `%`; uBO static-filtering-parser.js). Regex sources are translated
//! into the subset WebKit accepts (SafariRegex.swift and the WebKit compiler:
//! no alternation, `\d`/`\w`/`\b`, `{n}`, lookaround, backreferences). Anything
//! else returns `None`, and the caller drops the rule or widens the exception.

use crate::ast::{DomainMatcher, Pattern, PatternKind};

/// uBO separator class.
pub(crate) const SEPARATOR: &str = "[^a-zA-Z0-9_.%-]";
/// Hostname anchor (`||`), the expression Apple recommends.
const HOST_START: &str = "^[^:]+://+([^:/]+\\.)?";
/// What follows a host in a top-level URL. WHATWG URLs always have a path, so
/// a host is always followed by one of these.
const HOST_END: &str = "[/:?#]";
/// Largest repetition count expanded inline.
const MAX_REPEAT: u32 = 32;
/// Largest repetition of `.` expanded inline. Each extra any-character step
/// after a pattern grows WebKit's DFA: one `der-windows-papst.de/.{32}\?ver`
/// rule took a cookie and annoyance blocker from 335 MB to 1150 MB of compile
/// memory on macOS, and timed out Safari on an iPad 6; 12 adds about 6 MB.
const MAX_ANY_REPEAT: u32 = 12;

/// The url-filters for a uBO URL pattern, matched case-insensitively; a URL
/// matches when any of them does. A trailing `^` also matches the end of the
/// URL in uBO, and WebKit has no alternation, so that end is a second filter.
pub fn url_filter(p: &Pattern) -> Option<Vec<String>> {
    if p.is_match_all() {
        return Some(vec![".*".into()]);
    }
    if p.kind == PatternKind::Regex {
        // A regex that reduces to nothing (`/x{0}/`) matches every URL;
        // WebKit rejects an empty url-filter, so say that as `.*`.
        return translate(&p.body, "")
            .map(|alts| if alts.iter().any(String::is_empty) { vec![".*".into()] } else { alts })
            .and_then(accepted);
    }
    let mut out = String::new();
    let mut body = p.body.as_str();
    match p.kind {
        PatternKind::Hostname => {
            out.push_str(HOST_START);
            // A `^` right after a plain host ends the host, which in a URL is
            // always followed by one of HOST_END. The narrower class makes the
            // ~60k `||host^` blocks of EasyList and AdGuard Base compile 12%
            // faster in WebKit.
            let host = body.split_once('^').filter(|(h, _)| {
                !h.is_empty() && h.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'.')
            });
            if let Some((host, rest)) = host {
                literal(host, &mut out)?;
                out.push_str(HOST_END);
                body = rest;
            }
        }
        PatternKind::Left => out.push('^'),
        _ => {}
    }
    // A trailing `^` also matches the end of the URL (uBO
    // `FilterTrailingSeparator`). WebKit has no alternation, so the separator
    // and the rest of the URL become optional before the end.
    match body.strip_suffix('^') {
        Some(head) => {
            literal(head, &mut out)?;
            out.push('(');
            out.push_str(SEPARATOR);
            out.push_str(if p.right_anchored { ")?$" } else { ".*)?$" });
        }
        None => {
            literal(body, &mut out)?;
            if p.right_anchored {
                out.push('$');
            }
        }
    }
    accepted(vec![out])
}

/// The filters when WebKit accepts every one of them.
fn accepted(filters: Vec<String>) -> Option<Vec<String>> {
    filters.iter().all(|f| webkit_accepts(f)).then_some(filters)
}

/// `f` in the form WebKit compiles faster: an unanchored filter with a wide
/// atom (a class or `.`) and no quantifier gets its first atom repeated in
/// front, so `/[0-9a-f]x` becomes `/*/[0-9a-f]x`. WebKit prefixes an
/// unanchored filter with `.*` and puts every filter whose terms after the
/// last quantifier are fixed into one NFA (CombinedURLFilters::processNFAs).
/// There a wide atom multiplies the DFA states of all the literal filters
/// beside it: EasyList and uBO filters compiled 14% slower and their largest
/// DFA was twice the size. `.*a*a` matches what `.*a` does, and the `a*`
/// gives the filter an NFA of its own, shared only with filters starting the
/// same way.
pub(crate) fn apart(f: String) -> String {
    split_off(&f).unwrap_or(f)
}

fn split_off(f: &str) -> Option<String> {
    let b = f.as_bytes();
    let first = match b.first()? {
        b'\\' => 2,
        b'[' => class_end(b, 0)? + 1,
        b'^' | b'.' | b'(' | b'$' => return None,
        _ => 1,
    };
    let (mut wide, mut i) = (false, 0);
    while i < b.len() {
        match b[i] {
            b'\\' => i += 1,
            b'[' => {
                wide = true;
                i = class_end(b, i)?;
            }
            b'.' => wide = true,
            b'*' | b'+' | b'?' => return None,
            _ => {}
        }
        i += 1;
    }
    wide.then(|| format!("{}*{f}", &f[..first]))
}

/// Longest url-filter emitted. Counted repeats expand, so this also bounds
/// the work a single source rule can cause in WebKit's compiler.
const MAX_FILTER_LEN: usize = 4096;

/// Final check on an emitted url-filter, so one bad rule never reaches
/// Safari (a rule WebKit rejects fails its whole content blocker): non-empty,
/// ASCII, bounded, balanced groups and classes, ascending class ranges, and
/// quantifiers only after something they can repeat.
pub fn webkit_accepts(re: &str) -> bool {
    let b = re.as_bytes();
    if b.is_empty() || b.len() > MAX_FILTER_LEN || !re.is_ascii() {
        return false;
    }
    let (mut depth, mut i, mut can_repeat) = (0usize, 0usize, false);
    while i < b.len() {
        match b[i] {
            b'\\' => {
                if i + 1 >= b.len() {
                    return false;
                }
                i += 1;
                can_repeat = true;
            }
            b'(' => {
                depth += 1;
                can_repeat = false;
            }
            b')' => {
                if depth == 0 {
                    return false;
                }
                depth -= 1;
                can_repeat = true;
            }
            b'[' => {
                let Some(end) = class_end(b, i) else {
                    return false;
                };
                i = end;
                can_repeat = true;
            }
            b']' => return false,
            b'*' | b'+' | b'?' => {
                if !can_repeat {
                    return false;
                }
                can_repeat = false;
            }
            b'^' if i != 0 => return false,
            b'$' if i != b.len() - 1 => return false,
            b'|' | b'{' | b'}' => return false,
            _ => can_repeat = true,
        }
        i += 1;
    }
    depth == 0
}

/// Index of the `]` closing the class that opens at `start`, or `None` when
/// it is unterminated, empty, or has a descending range.
fn class_end(b: &[u8], start: usize) -> Option<usize> {
    let mut i = start + 1;
    if b.get(i) == Some(&b'^') {
        i += 1;
    }
    let first = i;
    let mut prev: Option<u8> = None;
    while i < b.len() {
        let c = match b[i] {
            b']' if i > first => return Some(i),
            b'\\' => {
                i += 1;
                *b.get(i)?
            }
            c => c,
        };
        if c == b'-' && prev.is_some() && b.get(i + 1).is_some_and(|&n| n != b']') {
            let lo = prev?;
            i += 1;
            let hi = match b[i] {
                b'\\' => {
                    i += 1;
                    *b.get(i)?
                }
                h => h,
            };
            if hi < lo {
                return None;
            }
            prev = None;
        } else {
            prev = Some(c);
        }
        i += 1;
    }
    None
}

/// An `if-top-url` regex for a domain option (uBO `$domain=`/`$to=` item).
/// Hostnames match themselves and subdomains. Entities (`google.*`) accept a
/// one-label suffix or `co.`/`com.` plus one label, approximating uBO's public
/// suffix list: `google.de` and `google.co.uk` match, `google.evil.com` does
/// not, and rarer two-label suffixes (`google.ne.jp`) are missed. Regex domains match the host
/// with the regex, as uBO tests them against the hostname.
pub fn domain_top_url(m: &DomainMatcher) -> Option<Vec<String>> {
    accepted(top_url(m)?)
}

/// The `if-top-url` regex for an `if-domain` entry: `*host` matches the host
/// and its subdomains, `host` only itself. WebKit compiles `if-domain` to an
/// unanchored regex (ContentExtensionParser.cpp, `getDomainList`), which also
/// fires on a page whose query holds `http://host/`, and costs more to
/// compile. Returns `None` for non-ASCII input.
pub fn host_top_url(entry: &str) -> Option<String> {
    let (mut out, host) = match entry.strip_prefix('*') {
        Some(host) => (HOST_START.to_string(), host),
        None => ("^[^:]+://+".to_string(), entry),
    };
    literal(host, &mut out)?;
    out.push_str(HOST_END);
    Some(out)
}

fn top_url(m: &DomainMatcher) -> Option<Vec<String>> {
    match m {
        DomainMatcher::Hostname(h) => Some(vec![host_top_url(&format!("*{h}"))?]),
        DomainMatcher::Entity(e) => {
            let mut out = HOST_START.to_string();
            literal(e, &mut out)?;
            // `name.<tld>` or `name.co.<tld>`/`name.com.<tld>`, not `name.evil.com`.
            out.push_str("\\.(com?\\.)?[^:/.]+");
            out.push_str(HOST_END);
            Some(vec![out])
        }
        DomainMatcher::Regex(src) => Some(
            // uBO tests the regex against the hostname, so no character
            // class may run past it.
            translate(src, "/:?#")?
                .iter()
                .map(|alt| {
                    let (anchored, body) = match alt.strip_prefix('^') {
                        Some(rest) => (true, rest),
                        None => (false, alt.as_str()),
                    };
                    let (body, at_end) = match body.strip_suffix('$') {
                        Some(rest) if !rest.ends_with('\\') => (rest, true),
                        _ => (body, false),
                    };
                    let any = "[^/:?#]*";
                    format!(
                        "^[^:]+://{}{body}{}{HOST_END}",
                        if anchored { "" } else { any },
                        if at_end { "" } else { any }
                    )
                })
                .collect(),
        ),
    }
}

/// Literal pattern text with `*` and `^` translated. Escapes regex
/// metacharacters. Returns `None` for non-ASCII input.
fn literal(body: &str, out: &mut String) -> Option<()> {
    for c in body.chars() {
        match c {
            '*' => out.push_str(".*"),
            '^' => out.push_str(SEPARATOR),
            c if c.is_ascii() => {
                if ".+?()[]{}|$\\".contains(c) {
                    out.push('\\');
                }
                out.push(c);
            }
            _ => return None,
        }
    }
    Some(())
}

/// Most url-filters one regex expands to. WebKit has no alternation, so each
/// alternative is a filter of its own, and so another rule.
const MAX_ALTERNATIVES: usize = 16;

/// Translates a uBO regex body into the WebKit subset: one regex per
/// alternative, with anchors left where they fall for `webkit_accepts` to
/// judge. URLs never hold whitespace, so `\S` is any character. Negated
/// classes and `.` never match a character of `exclude`.
fn translate(src: &str, exclude: &'static str) -> Option<Vec<String>> {
    if src.is_empty() || !src.is_ascii() {
        return None;
    }
    let mut p = Translator {
        src: src.as_bytes(),
        pos: 0,
        last_word: false,
        exclude,
    };
    let out = p.seq(0)?;
    (p.pos == src.len()).then_some(out)
}

/// Every alternative of `a` followed by every one of `b`, or `None` past
/// MAX_ALTERNATIVES.
fn product(a: &[String], b: &[String]) -> Option<Vec<String>> {
    (a.len() * b.len() <= MAX_ALTERNATIVES)
        .then(|| a.iter().flat_map(|x| b.iter().map(move |y| format!("{x}{y}"))).collect())
}

/// Whether a translated atom matches only word characters (`\w`).
fn word_only(atom: &str) -> bool {
    let b = atom.as_bytes();
    let word = |c: &u8| c.is_ascii_alphanumeric() || *c == b'_';
    match b {
        [c] => word(c),
        [b'[', inner @ .., b']'] if inner.first() != Some(&b'^') => inner.iter().enumerate().all(|(i, c)| {
            word(c)
                || *c == b'-'
                    && i > 0
                    && inner.get(i + 1).is_some_and(|n| {
                        let p = inner[i - 1];
                        [u8::is_ascii_digit, u8::is_ascii_lowercase, u8::is_ascii_uppercase]
                            .iter()
                            .any(|class| class(&p) && class(n))
                    })
        }),
        _ => false,
    }
}

#[derive(PartialEq)]
enum Atom {
    /// One character or class.
    Char,
    /// A group, parenthesized when quantified.
    Group,
    /// `^`, `$` or `\b`, which take no quantifier.
    Assertion,
}

struct Translator<'a> {
    src: &'a [u8],
    pos: usize,
    /// The last piece matched at least one word character and nothing else.
    last_word: bool,
    /// Characters no wildcard or negated class matches.
    exclude: &'static str,
}

impl Translator<'_> {
    fn peek(&self) -> Option<u8> {
        self.src.get(self.pos).copied()
    }

    fn next(&mut self) -> Option<u8> {
        let c = self.peek()?;
        self.pos += 1;
        Some(c)
    }

    /// The class of every character but `set` and `exclude`.
    fn negated(&self, set: &str) -> String {
        format!("[^{set}{}]", self.exclude)
    }

    /// Any character but `exclude`.
    fn any(&self) -> String {
        if self.exclude.is_empty() { ".".into() } else { self.negated("") }
    }

    /// Parses alternatives up to `)` (inside a group) or the end.
    fn seq(&mut self, depth: u32) -> Option<Vec<String>> {
        let mut done = Vec::new();
        let mut cur = vec![String::new()];
        self.last_word = false;
        while let Some(c) = self.peek() {
            match c {
                b')' if depth > 0 => break,
                b')' => return None,
                b'|' => {
                    self.pos += 1;
                    self.last_word = false;
                    done.append(&mut cur);
                    cur.push(String::new());
                }
                _ => cur = product(&cur, &self.piece(depth)?)?,
            }
        }
        done.append(&mut cur);
        (done.len() <= MAX_ALTERNATIVES).then_some(done)
    }

    /// An atom and its quantifier.
    fn piece(&mut self, depth: u32) -> Option<Vec<String>> {
        let (atom, kind) = self.atom(depth)?;
        let range = self.quantifier()?;
        let word = kind == Atom::Char && word_only(&atom[0]);
        self.last_word = word && range.is_none_or(|(min, _)| min > 0);
        let Some((min, max)) = range else {
            return Some(atom);
        };
        if kind == Atom::Assertion {
            return None;
        }
        if let [one] = atom.as_slice() {
            let limit = if *one == self.any() { MAX_ANY_REPEAT } else { MAX_REPEAT };
            if min.max(max.unwrap_or(0)) > limit {
                return None;
            }
            let one = if kind == Atom::Group { format!("({one})") } else { one.clone() };
            let mut out = String::new();
            repeat(&one, min, max, &mut out);
            return Some(vec![out]);
        }
        // Several alternatives repeat a bounded number of times, each copy
        // past `min` optional.
        let optional: Vec<String> = std::iter::once(String::new()).chain(atom.iter().cloned()).collect();
        let mut out = vec![String::new()];
        for i in 0..max? {
            out = product(&out, if i < min { &atom } else { &optional })?;
        }
        Some(out)
    }

    /// Returns the translated alternatives of an atom and its kind.
    fn atom(&mut self, depth: u32) -> Option<(Vec<String>, Atom)> {
        let c = self.next()?;
        let one = |s: String| Some((vec![s], Atom::Char));
        match c {
            b'^' | b'$' => Some((vec![(c as char).to_string()], Atom::Assertion)),
            b'.' => one(self.any()),
            b'(' => {
                if self.peek() == Some(b'?') {
                    if self.src.get(self.pos + 1) != Some(&b':') {
                        return None;
                    }
                    self.pos += 2;
                }
                let inner = self.seq(depth + 1)?;
                if self.next()? != b')' {
                    return None;
                }
                Some((inner, Atom::Group))
            }
            b'[' => one(self.class()?),
            // `\b` at the end, after a word character: a non-word character
            // or the end of the URL. At the start, before one: the start of
            // the URL or a non-word character.
            b'\\' if self.peek() == Some(b'b') => {
                self.pos += 1;
                let non_word = self.negated("a-zA-Z0-9_");
                let alts = if depth == 0 && self.pos == self.src.len() && self.last_word {
                    vec![non_word, "$".into()]
                } else if self.pos == 2 && self.peek().is_some_and(|n| n.is_ascii_alphanumeric() || n == b'_') {
                    vec!["^".into(), non_word]
                } else {
                    return None;
                };
                Some((alts, Atom::Assertion))
            }
            b'\\' => one(self.escape()?),
            b'|' | b'*' | b'+' | b'?' | b'{' | b'}' | b']' | b')' => None,
            c => one((c as char).to_string()),
        }
    }

    /// `*`, `+`, `?`, or `{n}`/`{n,}`/`{n,m}`. A lazy quantifier matches the
    /// same URLs as the greedy one; possessive forms are rejected.
    fn quantifier(&mut self) -> Option<Option<(u32, Option<u32>)>> {
        let range = match self.peek() {
            Some(b'*') => {
                self.pos += 1;
                (0, None)
            }
            Some(b'+') => {
                self.pos += 1;
                (1, None)
            }
            Some(b'?') => {
                self.pos += 1;
                (0, Some(1))
            }
            Some(b'{') => {
                self.pos += 1;
                self.braces()?
            }
            _ => return Some(None),
        };
        if self.peek() == Some(b'?') {
            self.pos += 1;
        }
        if matches!(self.peek(), Some(b'*' | b'+' | b'?' | b'{')) {
            return None;
        }
        Some(Some(range))
    }

    fn braces(&mut self) -> Option<(u32, Option<u32>)> {
        let min = self.number()?;
        let max = if self.peek() == Some(b',') {
            self.pos += 1;
            if self.peek() == Some(b'}') {
                None
            } else {
                Some(self.number()?)
            }
        } else {
            Some(min)
        };
        if self.next()? != b'}' || max.is_some_and(|m| m < min) {
            return None;
        }
        Some((min, max))
    }

    fn number(&mut self) -> Option<u32> {
        let start = self.pos;
        while matches!(self.peek(), Some(b'0'..=b'9')) {
            self.pos += 1;
        }
        std::str::from_utf8(&self.src[start..self.pos])
            .ok()?
            .parse()
            .ok()
    }

    /// Escape after `\`. WebKit has no `\d` `\w` `\s` `\b`; the class forms
    /// are expanded.
    fn escape(&mut self) -> Option<String> {
        Some(match self.next()? {
            b'd' => "[0-9]".into(),
            b'D' => self.negated("0-9"),
            b'w' => "[a-zA-Z0-9_]".into(),
            b'W' => self.negated("a-zA-Z0-9_"),
            b'S' => self.any(),
            c @ (b'.' | b'*' | b'+' | b'?' | b'(' | b')' | b'[' | b']' | b'{' | b'}' | b'\\'
            | b'^' | b'$' | b'|') => format!("\\{}", c as char),
            c @ (b'-' | b'/' | b':' | b'=' | b'&' | b'%' | b'_' | b'#' | b',' | b'@' | b'!'
            | b'~' | b'\'' | b'"' | b'<' | b'>' | b';' | b' ') => (c as char).to_string(),
            _ => return None,
        })
    }

    /// Character class body up to `]`. `\d` and `\w` are expanded, `\s`
    /// adds nothing a URL holds, `\S` makes the class any character, and the
    /// remaining escapes are passed through.
    fn class(&mut self) -> Option<String> {
        let mut out = String::from("[");
        let negated = self.peek() == Some(b'^');
        if negated {
            self.pos += 1;
            out.push('^');
        }
        let (start, mut any) = (self.pos, false);
        loop {
            match self.next()? {
                b']' if self.pos - 1 > start => break,
                b']' | b'[' => return None,
                b'\\' => match self.next()? {
                    b'd' => out.push_str("0-9"),
                    b'w' => out.push_str("a-zA-Z0-9_"),
                    b's' => {}
                    b'S' => any = true,
                    c @ (b'.' | b'*' | b'+' | b'?' | b'(' | b')' | b'{' | b'}' | b'\\' | b'^'
                    | b'$' | b'|' | b'-' | b'/' | b'[' | b']') => {
                        out.push('\\');
                        out.push(c as char);
                    }
                    c @ (b':' | b'=' | b'&' | b'%' | b'_' | b'#' | b',' | b'@' | b'!' | b'~'
                    | b'\'' | b'"' | b'<' | b'>' | b';' | b' ') => out.push(c as char),
                    _ => return None,
                },
                c => out.push(c as char),
            }
        }
        if any {
            return (!negated).then(|| self.any());
        }
        if negated {
            out.push_str(self.exclude);
        }
        out.push(']');
        Some(out)
    }
}

/// Expands `atom{min,max}` as WebKit has no counted repetition.
fn repeat(atom: &str, min: u32, max: Option<u32>, out: &mut String) {
    match (min, max) {
        (0, None) => out.push_str(&format!("{atom}*")),
        (n, None) => {
            for _ in 1..n {
                out.push_str(atom);
            }
            out.push_str(&format!("{atom}+"));
        }
        (n, Some(m)) => {
            for _ in 0..n {
                out.push_str(atom);
            }
            for _ in n..m {
                out.push_str(&format!("{atom}?"));
            }
        }
    }
}

#[cfg(test)]
mod emitted_filter_tests {
    use super::*;

    fn regex(body: &str) -> Pattern {
        Pattern {
            kind: PatternKind::Regex,
            body: body.into(),
            right_anchored: false,
        }
    }

    #[test]
    fn empty_translation_matches_everything() {
        assert_eq!(url_filter(&regex("x{0}")), Some(vec![".*".into()]));
    }

    #[test]
    fn invalid_output_is_dropped() {
        assert_eq!(url_filter(&regex("[z-a]")), None);
        assert_eq!(url_filter(&regex(&"(a{32}){32}".repeat(4))), None);
    }

    #[test]
    fn wide_unanchored_filters_get_their_own_nfa_and_match_the_same() {
        for (f, want) in [
            ("/[0-9a-f][0-9a-f]x\\.js", "/*/[0-9a-f][0-9a-f]x\\.js"),
            ("[^a-z]ads/", "[^a-z]*[^a-z]ads/"),
            ("\\.com/....js$", "\\.*\\.com/....js$"),
            // Literal, anchored, quantified, or starting with `.` or a group.
            ("/ads/x\\.js", "/ads/x\\.js"),
            ("^https://a\\.com/[0-9]", "^https://a\\.com/[0-9]"),
            ("/a[0-9]+", "/a[0-9]+"),
            ("a.*[0-9]", "a.*[0-9]"),
            (".x[0-9]", ".x[0-9]"),
            ("(ab)[0-9]", "(ab)[0-9]"),
        ] {
            let got = apart(f.into());
            assert_eq!(got, want);
            assert!(webkit_accepts(&got), "{got}");
            let re = |s: &str| ::regex::RegexBuilder::new(s).case_insensitive(true).build().unwrap();
            let (a, b) = (re(f), re(&got));
            for url in [
                "https://x.com/ab1x.js",
                "https://x.com//ab1X.JS",
                "https://x.com/9ads/",
                "https://x.com/?q=1ads/",
                "https://cdn.com/abcd.js",
                "https://cdn.com/abc.js",
                "https://a.com/1",
                "https://a.com/a12",
                "https://a.com/ab7",
            ] {
                assert_eq!(a.is_match(url), b.is_match(url), "{f} {url}");
            }
        }
    }

    #[test]
    fn webkit_accepts_checks_structure() {
        for ok in [
            ".*",
            "^[^:]+://+([^:/]+\\.)?ads\\.com[/:?#]",
            "a[\\]]b",
            "[-a]",
            "x?$",
        ] {
            assert!(webkit_accepts(ok), "{ok}");
        }
        for bad in [
            "", "(a", "a)", "[ab", "[]", "*a", "a**", "a^", "$a", "a|b", "a{2}", "[b-a]", "é",
        ] {
            assert!(!webkit_accepts(bad), "{bad}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn plain(body: &str) -> Pattern {
        Pattern {
            kind: PatternKind::Plain,
            body: body.into(),
            right_anchored: false,
        }
    }

    fn regex(body: &str) -> Pattern {
        Pattern {
            kind: PatternKind::Regex,
            body: body.into(),
            right_anchored: false,
        }
    }

    fn filter(p: &Pattern) -> Option<String> {
        url_filter(p).map(|f| f.join(" "))
    }

    fn top(m: DomainMatcher) -> Option<String> {
        domain_top_url(&m).map(|f| f.join(" "))
    }

    #[test]
    fn hostname_anchor_and_separator() {
        assert_eq!(
            filter(&Pattern {
                kind: PatternKind::Hostname,
                body: "ads.com^path".into(),
                right_anchored: false
            })
            .unwrap(),
            "^[^:]+://+([^:/]+\\.)?ads\\.com[/:?#]path"
        );
    }

    #[test]
    fn trailing_separator_also_matches_the_end() {
        let host = |body: &str, right_anchored| {
            let f = filter(&Pattern { kind: PatternKind::Hostname, body: body.into(), right_anchored }).unwrap();
            assert!(webkit_accepts(&f), "{f}");
            ::regex::Regex::new(&f).unwrap()
        };
        let re = host("cdn.com/ads.js^", false);
        assert!(re.is_match("https://cdn.com/ads.js"));
        assert!(re.is_match("https://cdn.com/ads.js?v=1"));
        assert!(!re.is_match("https://cdn.com/ads.jsx"));
        let re = host("cdn.com/ads.js^", true);
        assert!(re.is_match("https://cdn.com/ads.js"));
        assert!(re.is_match("https://cdn.com/ads.js?"));
        assert!(!re.is_match("https://cdn.com/ads.js?v=1"));
    }

    #[test]
    fn left_and_right_anchors() {
        assert_eq!(
            filter(&Pattern {
                kind: PatternKind::Left,
                body: "https://a.com/x".into(),
                right_anchored: true
            })
            .unwrap(),
            "^https://a\\.com/x$"
        );
    }

    #[test]
    fn plain_pattern_escapes_metacharacters() {
        assert_eq!(
            filter(&plain("a.b+c(d)[e]|f$g\\h")).unwrap(),
            "a\\.b\\+c\\(d\\)\\[e\\]\\|f\\$g\\\\h"
        );
    }

    #[test]
    fn wildcard_is_dot_star_and_match_all_is_dot_star() {
        assert_eq!(filter(&plain("a*b")).unwrap(), "a.*b");
        assert_eq!(filter(&plain("*")).unwrap(), ".*");
        assert_eq!(filter(&plain("")).unwrap(), ".*");
        assert_eq!(
            filter(&Pattern {
                kind: PatternKind::Hostname,
                body: "*".into(),
                right_anchored: false
            })
            .unwrap(),
            ".*"
        );
    }

    fn matches(p: &Pattern, url: &str) -> bool {
        url_filter(p).into_iter().flatten().any(|f| {
            ::regex::RegexBuilder::new(&f).case_insensitive(true).build().unwrap().is_match(url)
        })
    }

    #[test]
    fn trailing_separator_matches_end_of_url() {
        let host = |body: &str, right_anchored| Pattern { kind: PatternKind::Hostname, body: body.into(), right_anchored };
        assert!(matches(&host("ads.example/ok^", false), "https://ads.example/ok"));
        assert!(matches(&host("ads.example/ok^", false), "https://ads.example/ok?x"));
        assert!(!matches(&host("ads.example/ok^", false), "https://ads.example/okay"));
        assert!(matches(&host("ads.example/ok^", true), "https://ads.example/ok"));
        assert!(matches(&host("ads.example/ok^", true), "https://ads.example/ok/"));
        assert!(!matches(&host("ads.example/ok^", true), "https://ads.example/ok/x"));
        assert!(matches(&plain("/ws^"), "wss://loader.example.com/ws"));
    }

    #[test]
    fn non_ascii_pattern_is_none() {
        assert_eq!(filter(&plain("ünï")), None);
    }

    #[test]
    fn regex_digit_word_and_escape_expansion() {
        assert_eq!(filter(&regex("ab\\d+")).unwrap(), "ab[0-9]+");
        assert_eq!(filter(&regex("\\w\\D")).unwrap(), "[a-zA-Z0-9_][^0-9]");
        assert_eq!(filter(&regex("[\\d.]")).unwrap(), "[0-9.]");
        assert_eq!(filter(&regex("a\\.b\\/c\\-d")).unwrap(), "a\\.b/c-d");
    }

    #[test]
    fn regex_counted_repetition_is_expanded() {
        assert_eq!(filter(&regex("a{2}")).unwrap(), "aa");
        assert_eq!(filter(&regex("a{1,3}")).unwrap(), "aa?a?");
        assert_eq!(filter(&regex("a{2,}")).unwrap(), "aa+");
        assert_eq!(filter(&regex("(ab){0,2}c")).unwrap(), "(ab)?(ab)?c");
        assert_eq!(filter(&regex("x{0}y")).unwrap(), "y");
        assert_eq!(filter(&regex("a/.{12}b")).unwrap(), format!("a/{}b", ".".repeat(12)));
        assert_eq!(filter(&regex("a/.{13}b")), None);
        assert_eq!(filter(&regex("a/[a-f0-9]{32}b")).unwrap(), format!("a/{}b", "[a-f0-9]".repeat(32)));
    }

    #[test]
    fn regex_anchors_only_at_ends() {
        assert_eq!(filter(&regex("^a")).unwrap(), "^a");
        assert_eq!(filter(&regex("a$")).unwrap(), "a$");
        assert_eq!(filter(&regex("^a$")).unwrap(), "^a$");
        assert_eq!(filter(&regex("a^")), None);
        assert_eq!(filter(&regex("a$b")), None);
    }

    #[test]
    fn regex_groups_and_non_capturing() {
        assert_eq!(filter(&regex("(?:ab)c")).unwrap(), "abc");
        assert_eq!(filter(&regex("(x)?y")).unwrap(), "(x)?y");
        assert_eq!(filter(&regex("(a(b)c)+")).unwrap(), "(abc)+");
    }

    #[test]
    fn regex_alternation_expands_to_one_filter_each() {
        assert_eq!(filter(&regex("a|b")).unwrap(), "a b");
        assert_eq!(filter(&regex("\\/(?:x|y)\\.js$")).unwrap(), "/x\\.js$ /y\\.js$");
        assert_eq!(filter(&regex("a(?:$|\\?)")).unwrap(), "a$ a\\?");
        assert_eq!(filter(&regex("(?:a|b)?c")).unwrap(), "c ac bc");
        assert_eq!(filter(&regex("x(?:a|b)+")), None);
        assert_eq!(filter(&regex("(a|b)(c|d)(e|f)(g|h)(i|j)")), None);
        let r = regex("^https?:\\/\\/(?:www\\.)?(?:ads|track)\\.(?:com|net)\\/");
        assert!(matches(&r, "https://www.track.net/x"));
        assert!(!matches(&r, "https://www.trackads.net/x"));
    }

    #[test]
    fn regex_word_boundary_lazy_and_non_space() {
        let r = regex("\\/t\\.js\\?site=[a-f0-9]{4}\\b");
        assert!(matches(&r, "https://x.com/t.js?site=abcd"));
        assert!(matches(&r, "https://x.com/t.js?site=abcd&x"));
        assert!(!matches(&r, "https://x.com/t.js?site=abcde"));
        let r = regex("\\bgamatotv\\.info\\/");
        assert!(matches(&r, "https://gamatotv.info/a"));
        assert!(!matches(&r, "https://xgamatotv.info/a"));
        for body in ["a\\b\\/", "\\/\\b", "a\\b|c", "(a\\b)"] {
            assert_eq!(filter(&regex(body)), None, "{body}");
        }
        assert_eq!(filter(&regex("(.+?\\.)?a+?")).unwrap(), "(.+\\.)?a+");
        assert_eq!(filter(&regex("\\/[\\S]{3}\\S[^&\\s]")).unwrap(), "/....[^&]");
    }

    #[test]
    fn regex_constructs_webkit_rejects_are_none() {
        for body in [
            "\\sx", "(?=a)b", "(?!a)b", "(?<=a)b", "(a)\\1", "[^\\S]",
            "a*+", "a+??", "a{,3}", "a{3,2}", "a{40}", "[a", "a]", "[]a]", "[a[b]", "\\n", "(a", "a)", "{",
            "",
        ] {
            assert_eq!(filter(&regex(body)), None, "{body}");
        }
    }

    #[test]
    fn character_classes_pass_through_with_expansions() {
        assert_eq!(filter(&regex("[^a-z\\-]")).unwrap(), "[^a-z\\-]");
        assert_eq!(filter(&regex("[\\w-]")).unwrap(), "[a-zA-Z0-9_-]");
        assert_eq!(filter(&regex("[\\/]")).unwrap(), "[\\/]");
    }

    #[test]
    fn domain_hostname_top_url() {
        assert_eq!(
            top(DomainMatcher::Hostname("example.com".into())).unwrap(),
            "^[^:]+://+([^:/]+\\.)?example\\.com[/:?#]"
        );
    }

    #[test]
    fn if_domain_entries_as_anchored_top_urls() {
        let re = |entry: &str| ::regex::RegexBuilder::new(&host_top_url(entry).unwrap()).case_insensitive(true).build().unwrap();
        let sub = re("*foo.test");
        for url in ["https://foo.test/", "https://a.b.foo.test/x", "http://foo.test:8080/", "https://FOO.test/"] {
            assert!(sub.is_match(url), "{url}");
        }
        for url in ["http://127.0.0.1/?u=http://foo.test/", "https://xfoo.test/", "https://foo.test.evil/"] {
            assert!(!sub.is_match(url), "{url}");
        }
        let exact = re("foo.test");
        assert!(exact.is_match("https://foo.test/"));
        assert!(!exact.is_match("https://a.foo.test/"));
    }

    #[test]
    fn domain_entity_top_url() {
        assert_eq!(
            top(DomainMatcher::Entity("google".into())).unwrap(),
            "^[^:]+://+([^:/]+\\.)?google\\.(com?\\.)?[^:/.]+[/:?#]"
        );
    }

    #[test]
    fn entity_domain_does_not_accept_arbitrary_second_level_suffix() {
        let filter = top(DomainMatcher::Entity("google".into())).unwrap();
        assert!(!filter.contains("([^:/.]+\\.)?[^:/.]"));
        assert!(webkit_accepts(&filter));
    }

    #[test]
    fn domain_regex_top_url_anchoring() {
        assert_eq!(
            top(DomainMatcher::Regex("^ads\\d+\\.net$".into())).unwrap(),
            "^[^:]+://ads[0-9]+\\.net[/:?#]"
        );
        assert_eq!(
            top(DomainMatcher::Regex("cdn".into())).unwrap(),
            "^[^:]+://[^/:?#]*cdn[^/:?#]*[/:?#]"
        );
        // uBO tests the regex against the hostname only.
        for (rx, page) in [("^ads.+\\.net$", "https://adsfoo.com/x.net/"), ("^ads[^x]+\\.net$", "https://adsfoo.com/a.net/"), ("^ads\\D+\\.net$", "https://ads.com?.net/")] {
            let filters = domain_top_url(&DomainMatcher::Regex(rx.into())).unwrap();
            assert!(!filters.iter().any(|f| ::regex::Regex::new(f).unwrap().is_match(page)), "{rx}");
        }
        assert_eq!(
            top(DomainMatcher::Regex("^a$|b".into())).unwrap(),
            "^[^:]+://a[/:?#] ^[^:]+://[^/:?#]*b[^/:?#]*[/:?#]"
        );
    }
}
