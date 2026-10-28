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
const SEPARATOR: &str = "[^a-zA-Z0-9_.%-]";
/// Hostname anchor (`||`), the expression Apple recommends.
const HOST_START: &str = "^[^:]+://+([^:/]+\\.)?";
/// What follows a host in a top-level URL. WHATWG URLs always have a path, so
/// a host is always followed by one of these.
const HOST_END: &str = "[/:?#]";
/// Largest repetition count expanded inline.
const MAX_REPEAT: u32 = 32;

/// The url-filter for a uBO URL pattern, matched case-insensitively.
pub fn url_filter(p: &Pattern) -> Option<String> {
    if p.is_match_all() {
        return Some(".*".into());
    }
    if p.kind == PatternKind::Regex {
        // A regex that reduces to nothing (`/x{0}/`) matches every URL;
        // WebKit rejects an empty url-filter, so say that as `.*`.
        return translate(&p.body)
            .map(|r| if r.is_empty() { ".*".into() } else { r })
            .filter(|r| webkit_accepts(r));
    }
    let mut out = String::new();
    match p.kind {
        PatternKind::Hostname => out.push_str(HOST_START),
        PatternKind::Left => out.push('^'),
        _ => {}
    }
    literal(&p.body, &mut out)?;
    if p.right_anchored {
        out.push('$');
    }
    webkit_accepts(&out).then_some(out)
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
/// Hostnames match themselves and subdomains. Entities (`google.*`) accept any
/// suffix of one or two labels, which is an approximation of uBO's public
/// suffix list: `google.evil.com` also matches. Regex domains match the host
/// with the regex, as uBO tests them against the hostname.
pub fn domain_top_url(m: &DomainMatcher) -> Option<String> {
    top_url(m).filter(|u| webkit_accepts(u))
}

fn top_url(m: &DomainMatcher) -> Option<String> {
    match m {
        DomainMatcher::Hostname(h) => {
            let mut out = HOST_START.to_string();
            literal(h, &mut out)?;
            out.push_str(HOST_END);
            Some(out)
        }
        DomainMatcher::Entity(e) => {
            let mut out = HOST_START.to_string();
            literal(e, &mut out)?;
            out.push_str("\\.([^:/.]+\\.)?[^:/.]+");
            out.push_str(HOST_END);
            Some(out)
        }
        DomainMatcher::Regex(src) => {
            let (anchored, body) = match src.strip_prefix('^') {
                Some(rest) => (true, rest),
                None => (false, src.as_str()),
            };
            let (body, at_end) = match body.strip_suffix('$') {
                Some(rest) if !rest.ends_with('\\') => (rest, true),
                _ => (body, false),
            };
            let inner = translate(body)?;
            let mut out = String::from("^[^:]+://");
            if !anchored {
                out.push_str("[^/:?#]*");
            }
            out.push_str(&inner);
            if !at_end {
                out.push_str("[^/:?#]*");
            }
            out.push_str(HOST_END);
            Some(out)
        }
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

/// Translates a uBO regex body into the WebKit subset. `^` is accepted only
/// as the first character and `$` only as the last.
fn translate(src: &str) -> Option<String> {
    if src.is_empty() || !src.is_ascii() {
        return None;
    }
    let mut p = Translator {
        src: src.as_bytes(),
        pos: 0,
    };
    let out = p.seq(0)?;
    (p.pos == src.len()).then_some(out)
}

struct Translator<'a> {
    src: &'a [u8],
    pos: usize,
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

    /// Parses atoms and quantifiers up to `)` (inside a group) or the end.
    fn seq(&mut self, depth: u32) -> Option<String> {
        let mut out = String::new();
        while let Some(c) = self.peek() {
            if c == b')' {
                return (depth > 0).then_some(out);
            }
            let (atom, quantifiable) = self.atom(depth)?;
            match self.quantifier()? {
                None => out.push_str(&atom),
                Some((min, max)) => {
                    if !quantifiable || min.max(max.unwrap_or(0)) > MAX_REPEAT {
                        return None;
                    }
                    repeat(&atom, min, max, &mut out);
                }
            }
        }
        (depth == 0).then_some(out)
    }

    /// Returns the translated atom and whether a quantifier may follow it.
    fn atom(&mut self, depth: u32) -> Option<(String, bool)> {
        let c = self.next()?;
        Some(match c {
            b'^' if self.pos == 1 => ("^".into(), false),
            b'$' if depth == 0 && self.pos == self.src.len() => ("$".into(), false),
            b'.' => (".".into(), true),
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
                (format!("({inner})"), true)
            }
            b'[' => (self.class()?, true),
            b'\\' => (self.escape()?, true),
            b'|' | b'^' | b'$' | b'*' | b'+' | b'?' | b'{' | b'}' | b']' => return None,
            c => ((c as char).to_string(), true),
        })
    }

    /// `*`, `+`, `?`, or `{n}`/`{n,}`/`{n,m}`. Lazy and possessive forms are
    /// rejected.
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
        if matches!(self.peek(), Some(b'?' | b'+')) {
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
            b'D' => "[^0-9]".into(),
            b'w' => "[a-zA-Z0-9_]".into(),
            b'W' => "[^a-zA-Z0-9_]".into(),
            c @ (b'.' | b'*' | b'+' | b'?' | b'(' | b')' | b'[' | b']' | b'{' | b'}' | b'\\'
            | b'^' | b'$' | b'|') => format!("\\{}", c as char),
            c @ (b'-' | b'/' | b':' | b'=' | b'&' | b'%' | b'_' | b'#' | b',' | b'@' | b'!'
            | b'~' | b'\'' | b'"' | b'<' | b'>' | b';' | b' ') => (c as char).to_string(),
            _ => return None,
        })
    }

    /// Character class body up to `]`. `\d` and `\w` are expanded and the
    /// remaining escapes are passed through.
    fn class(&mut self) -> Option<String> {
        let mut out = String::from("[");
        if self.peek() == Some(b'^') {
            self.pos += 1;
            out.push('^');
        }
        let start = self.pos;
        loop {
            match self.next()? {
                b']' if self.pos - 1 > start => break,
                b']' | b'[' => return None,
                b'\\' => match self.next()? {
                    b'd' => out.push_str("0-9"),
                    b'w' => out.push_str("a-zA-Z0-9_"),
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
        assert_eq!(url_filter(&regex("x{0}")).as_deref(), Some(".*"));
    }

    #[test]
    fn invalid_output_is_dropped() {
        assert_eq!(url_filter(&regex("[z-a]")), None);
        assert_eq!(url_filter(&regex(&"(a{32}){32}".repeat(4))), None);
    }

    #[test]
    fn webkit_accepts_checks_structure() {
        for ok in [
            ".*",
            "^[^:]+://+([^:/]+\\.)?ads\\.com[^a-zA-Z0-9_.%-]",
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
        url_filter(p)
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
            "^[^:]+://+([^:/]+\\.)?ads\\.com[^a-zA-Z0-9_.%-]path"
        );
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
        assert_eq!(filter(&regex("(?:ab)c")).unwrap(), "(ab)c");
        assert_eq!(filter(&regex("(x)?y")).unwrap(), "(x)?y");
        assert_eq!(filter(&regex("(a(b)c)+")).unwrap(), "(a(b)c)+");
    }

    #[test]
    fn regex_constructs_webkit_rejects_are_none() {
        for body in [
            "a|b", "(a|b)c", "\\bfoo", "\\sx", "(?=a)b", "(?!a)b", "(?<=a)b", "(a)\\1", "a+?",
            "a*+", "a{,3}", "a{3,2}", "a{40}", "[a", "a]", "[]a]", "[a[b]", "\\n", "(a", "a)", "{",
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
            domain_top_url(&DomainMatcher::Hostname("example.com".into())).unwrap(),
            "^[^:]+://+([^:/]+\\.)?example\\.com[/:?#]"
        );
    }

    #[test]
    fn domain_entity_top_url() {
        assert_eq!(
            domain_top_url(&DomainMatcher::Entity("google".into())).unwrap(),
            "^[^:]+://+([^:/]+\\.)?google\\.([^:/.]+\\.)?[^:/.]+[/:?#]"
        );
    }

    #[test]
    fn domain_regex_top_url_anchoring() {
        assert_eq!(
            domain_top_url(&DomainMatcher::Regex("^ads\\d+\\.net$".into())).unwrap(),
            "^[^:]+://ads[0-9]+\\.net[/:?#]"
        );
        assert_eq!(
            domain_top_url(&DomainMatcher::Regex("cdn".into())).unwrap(),
            "^[^:]+://[^/:?#]*cdn[^/:?#]*[/:?#]"
        );
        assert_eq!(domain_top_url(&DomainMatcher::Regex("a|b".into())), None);
    }
}
