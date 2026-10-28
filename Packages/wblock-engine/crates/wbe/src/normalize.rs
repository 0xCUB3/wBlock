//! AdGuard and ABP syntax rewritten to uBO syntax, as far as uBO accepts it
//! (static-filtering-parser.js: `translateStyleInjectionFilter`,
//! `ExtSelectorCompiler.compile`, and the AdGuard `//scriptlet` flavor). Lines
//! uBO would drop come back unchanged, and the parser reports them as
//! unsupported.

use std::borrow::Cow;

use crate::parse::cosmetic::{find_marker, is_comment, scriptlet_name, split_args};

/// AdGuard scriptlet names that uBO only knows under another name. Names that
/// are uBO names or aliases already need no entry.
const ADG_RENAMES: &[(&str, &str)] = &[
    ("abp-abort-current-inline-script", "abort-current-script"),
    ("abp-abort-on-property-read", "abort-on-property-read"),
    ("abp-abort-on-property-write", "abort-on-property-write"),
    ("abp-abort-on-stack-trace", "abort-on-stack-trace"),
    ("abp-cookie-remover", "remove-cookie"),
    ("abp-json-prune", "json-prune"),
    ("abp-override-property-read", "set-constant"),
    ("abp-prevent-listener", "prevent-addEventListener"),
    ("sid", "prevent-setInterval"),
    ("std", "prevent-setTimeout"),
    ("ubo-sid", "prevent-setInterval"),
    ("ubo-std", "prevent-setTimeout"),
];

pub fn adguard_to_ubo(line: &str) -> Cow<'_, str> {
    if !line.contains('#') && !line.contains("$$") && !line.contains("$@$") {
        return Cow::Borrowed(line);
    }
    if is_comment(line) {
        return Cow::Borrowed(line);
    }
    let Some((at, marker)) = find_marker(line) else {
        return Cow::Borrowed(line);
    };
    let (domains, body) = (&line[..at], &line[at + marker.len()..]);
    let exception = marker.starts_with("#@") || marker.starts_with("$@");
    let prefix = if exception { "#@#" } else { "##" };
    let rewritten = match marker {
        "$$" | "$@$" => None,
        "#%#" | "#@%#" => body
            .strip_prefix("//scriptlet(")
            .and_then(|s| s.strip_suffix(')'))
            .and_then(adg_scriptlet)
            .map(|js| format!("{domains}{prefix}{js}")),
        "#$#" | "#$?#" | "#@$#" | "#@$?#" => style_injection(body)
            // An exception with an action has no uBO form we can keep.
            .filter(|(_, plain)| !exception || *plain)
            .map(|(sel, _)| format!("{domains}{prefix}{sel}")),
        _ => {
            let ops = rewrite_ops(body, marker.contains('?'));
            if marker.contains('?') || matches!(ops, Cow::Owned(_)) {
                Some(format!("{domains}{prefix}{ops}"))
            } else {
                None
            }
        }
    };
    rewritten.map_or(Cow::Borrowed(line), Cow::Owned)
}

/// uBO's `translateStyleInjectionFilter`: `selector { style }` becomes the
/// uBO selector, with `:remove()` or `:style()` when needed. The flag is true
/// when no action is needed.
fn style_injection(body: &str) -> Option<(String, bool)> {
    let inner = body.strip_suffix('}')?;
    let open = inner.rfind('{')?;
    let selector = inner[..open].trim();
    let style = inner[open + 1..].trim();
    if selector.is_empty() || style.is_empty() || style.contains('}') {
        return None;
    }
    if is_remove_true(style) {
        return Some((format!("{selector}:remove()"), false));
    }
    let compact: String = style.chars().filter(|c| !c.is_whitespace()).collect();
    let compact = compact.strip_suffix(';').unwrap_or(&compact);
    if compact.ends_with("display:none!important") {
        return Some((selector.to_string(), true));
    }
    Some((format!("{selector}:style({style})"), false))
}

/// `remove: true` with optional `;` and spaces (uBO's `^\s*remove:\s*true[; ]*$`).
fn is_remove_true(style: &str) -> bool {
    style
        .trim_start()
        .strip_prefix("remove:")
        .map(str::trim_start)
        .and_then(|s| s.strip_prefix("true"))
        .is_some_and(|s| s.chars().all(|c| c == ';' || c == ' '))
}

/// AdGuard `'name', 'arg', ...` as uBO's `+js()`. Every argument must be
/// quoted, and the name must resolve to a uBO scriptlet.
fn adg_scriptlet(inner: &str) -> Option<String> {
    let (token, args) = split_args(inner, true)?;
    let renamed = ADG_RENAMES
        .iter()
        .find(|(from, _)| *from == token)
        .map_or(token.as_str(), |(_, to)| to);
    let mut out = format!("+js({}", scriptlet_name(renamed)?);
    for arg in &args {
        out.push_str(", ");
        out.push_str(&requote(arg)?);
    }
    out.push(')');
    Some(out)
}

/// Quotes an argument so that uBO's `+js()` parser reads it back unchanged.
/// Unquoted values cannot hold separators, edge whitespace, or a trailing
/// backslash. Quoted values need a quote character the value does not contain.
fn requote(value: &str) -> Option<String> {
    let plain = !value.is_empty()
        && !value.contains([',', '\'', '"', '`'])
        && value.trim() == value
        && !value.ends_with('\\');
    if plain {
        return Some(value.to_string());
    }
    if value.ends_with('\\') {
        return None;
    }
    let quote = ['\'', '"', '`'].into_iter().find(|q| !value.contains(*q))?;
    Some(format!("{quote}{value}{quote}"))
}

/// uBO's procedural operator names: `:-abp-*` (only with `#?#`), `:contains()`,
/// `:nth-ancestor()`, and `:watch-attrs()` (AST normalization in uBO).
fn rewrite_ops(body: &str, abp: bool) -> Cow<'_, str> {
    const RENAMES: [(&str, &str); 5] = [
        (":-abp-contains(", ":has-text("),
        (":-abp-has(", ":has("),
        (":contains(", ":has-text("),
        (":nth-ancestor(", ":upward("),
        (":watch-attrs(", ":watch-attr("),
    ];
    let mut out = Cow::Borrowed(body);
    if !body.contains(':') {
        return out;
    }
    for (from, to) in RENAMES {
        if from.starts_with(":-abp-") && !abp {
            continue;
        }
        if out.contains(from) {
            out = Cow::Owned(out.replace(from, to));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ast::{CosmeticBody, ParsedLine, Rule, SourceRef};
    use crate::parse::parse_line;

    /// Runs every case; a line that comes back unchanged must be borrowed.
    fn check(cases: &[(&str, &str)]) {
        let mut bad = Vec::new();
        for (line, want) in cases {
            let got = adguard_to_ubo(line);
            if got != *want {
                bad.push(format!("{line:?}\n   want {want}\n   got  {got}"));
            }
            if got == *line {
                assert!(matches!(got, Cow::Borrowed(_)), "unchanged but owned: {line}");
            }
        }
        assert!(bad.is_empty(), "{} mismatches:\n{}", bad.len(), bad.join("\n"));
    }

    #[test]
    fn unchanged_lines_are_borrowed() {
        check(&[
            ("##.ad", "##.ad"),
            ("example.com##.ad", "example.com##.ad"),
            ("#@#.ad", "#@#.ad"),
            ("||example.com/#foo", "||example.com/#foo"),
            ("||example.com^$third-party", "||example.com^$third-party"),
            ("! comment ##.x", "! comment ##.x"),
            ("# comment ##.x", "# comment ##.x"),
            ("#### section", "#### section"),
            ("example.com$$script[tag-content=\"x\"]", "example.com$$script[tag-content=\"x\"]"),
            ("example.com$@$script[tag-content=\"x\"]", "example.com$@$script[tag-content=\"x\"]"),
            ("example.com##div:-abp-has(span)", "example.com##div:-abp-has(span)"),
            ("example.com##div:matches-css-before(content: x)", "example.com##div:matches-css-before(content: x)"),
            ("example.com##^script", "example.com##^script"),
            ("example.com##+js(aopr, a)", "example.com##+js(aopr, a)"),
            ("example.com#$#log 'x'", "example.com#$#log 'x'"),
            ("example.com#@$#.ad { color: red; }", "example.com#@$#.ad { color: red; }"),
            ("example.com#$#.a {}", "example.com#$#.a {}"),
            ("example.com#$#.a { color: red } extra", "example.com#$#.a { color: red } extra"),
            ("example.com#$#", "example.com#$#"),
        ]);
    }

    #[test]
    fn adguard_scriptlets() {
        check(&[
            (
                "example.com#%#//scriptlet('abort-on-property-read', 'x')",
                "example.com##+js(abort-on-property-read, x)",
            ),
            (
                "#@%#//scriptlet('set-constant', 'a', 'true')",
                "#@#+js(set-constant, a, true)",
            ),
            (
                "example.com#%#//scriptlet('abort-current-inline-script', 'document.getElementsByTagName', '$$$')",
                "example.com##+js(abort-current-script, document.getElementsByTagName, $$$)",
            ),
            (
                "example.com#%#//scriptlet('abort-on-property-read', 'a', 'b')",
                "example.com##+js(abort-on-property-read, a, b)",
            ),
            (
                "example.com#%#//scriptlet('abort-on-property-read', 'it\\'s')",
                "example.com##+js(abort-on-property-read, \"it's\")",
            ),
            (
                "example.com#%#//scriptlet('abort-on-property-read', 'a,b')",
                "example.com##+js(abort-on-property-read, 'a,b')",
            ),
            (
                "example.com#%#//scriptlet('abort-on-property-read', ' x ')",
                "example.com##+js(abort-on-property-read, ' x ')",
            ),
            (
                "example.com#%#//scriptlet('abort-on-property-read', '')",
                "example.com##+js(abort-on-property-read, '')",
            ),
            (
                "example.com#%#//scriptlet('set-constant', 'a', 'undefined')",
                "example.com##+js(set-constant, a, undefined)",
            ),
            ("example.com#%#//scriptlet('set', 'a', '1')", "example.com##+js(set-constant, a, 1)"),
            ("example.com#%#//scriptlet('sid', 'x')", "example.com##+js(prevent-setInterval, x)"),
            ("example.com#%#//scriptlet('std', 'x')", "example.com##+js(prevent-setTimeout, x)"),
            ("example.com#%#//scriptlet('abp-json-prune', 'a')", "example.com##+js(json-prune, a)"),
            (
                "example.com#%#//scriptlet('abp-override-property-read', 'a')",
                "example.com##+js(set-constant, a)",
            ),
            (
                "example.com#%#//scriptlet('abp-prevent-listener', 'click')",
                "example.com##+js(prevent-addEventListener, click)",
            ),
            (
                "example.com#%#//scriptlet('prevent-eval-if', 'x')",
                "example.com##+js(noeval-if, x)",
            ),
            (
                "example.com#%#//scriptlet('trusted-click-element', 'div > button')",
                "example.com##+js(trusted-click-element, div > button)",
            ),
            (
                "example.com#%#//scriptlet('remove-attr.js', 'x')",
                "example.com##+js(remove-attr, x)",
            ),
            (
                "example.com#%#//scriptlet('abort-on-property-read.js')",
                "example.com##+js(abort-on-property-read)",
            ),
            (
                "example.com#@%#//scriptlet('prevent-fetch', 'x')",
                "example.com#@#+js(prevent-fetch, x)",
            ),
            ("example.com#%#//scriptlet('nosuch', 'x')", "example.com#%#//scriptlet('nosuch', 'x')"),
            ("example.com#%#//scriptlet('noeval')", "example.com#%#//scriptlet('noeval')"),
            (
                "example.com#%#//scriptlet('ubo-aopr', 'x')",
                "example.com#%#//scriptlet('ubo-aopr', 'x')",
            ),
            (
                "example.com#%#//scriptlet(abort-on-property-read, x)",
                "example.com#%#//scriptlet(abort-on-property-read, x)",
            ),
            (
                "example.com#%#//scriptlet('abort-on-property-read', 'x', y)",
                "example.com#%#//scriptlet('abort-on-property-read', 'x', y)",
            ),
            (
                "example.com#%#//scriptlet('abort-on-property-read', 'x'",
                "example.com#%#//scriptlet('abort-on-property-read', 'x'",
            ),
            (
                "example.com#%#var a = 1;",
                "example.com#%#var a = 1;",
            ),
        ]);
    }

    #[test]
    fn adguard_css_injection() {
        check(&[
            (
                "example.com#$#.pub { display: block !important; }",
                "example.com##.pub:style(display: block !important;)",
            ),
            ("example.com#$#.ad { display: none !important; }", "example.com##.ad"),
            ("example.com#$#.ad{display:none!important}", "example.com##.ad"),
            ("example.com#$#.ad { remove: true; }", "example.com##.ad:remove()"),
            ("example.com#$#.ad { remove: true }", "example.com##.ad:remove()"),
            (
                "example.com#$?#div:has-text(x) { display: none !important; }",
                "example.com##div:has-text(x)",
            ),
            (
                "example.com#$?#html > div { remove: true; }",
                "example.com##html > div:remove()",
            ),
            ("example.com#$#.a { color : red }", "example.com##.a:style(color : red)"),
            (
                "example.com#$#.a { background: url(x.png) }",
                "example.com##.a:style(background: url(x.png))",
            ),
            (
                "example.com#$#body > * { filter: none !important; }",
                "example.com##body > *:style(filter: none !important;)",
            ),
            ("#$#body { color: red }", "##body:style(color: red)"),
            ("example.com#@$#.ad { display: none !important; }", "example.com#@#.ad"),
            ("example.com#@$?#.ad { display: none !important; }", "example.com#@#.ad"),
            // uBO takes the last `{` (greedy `(.+)`), so the selector keeps the first block.
            ("example.com#$#div { color: red; }{ x }", "example.com##div { color: red; }:style(x)"),
        ]);
    }

    #[test]
    fn procedural_markers_and_operators() {
        check(&[
            ("example.com#?#.a:has-text(x)", "example.com##.a:has-text(x)"),
            ("example.com#@?#.a:has-text(x)", "example.com#@#.a:has-text(x)"),
            (
                "deliveroo.*#?#a[role=\"button\"]:has(p:has-text(Sponsored))",
                "deliveroo.*##a[role=\"button\"]:has(p:has-text(Sponsored))",
            ),
            ("example.com#?#div:-abp-has(span)", "example.com##div:has(span)"),
            ("example.com#?#div:-abp-contains(x)", "example.com##div:has-text(x)"),
            ("example.com#?#div:-abp-properties(x)", "example.com##div:-abp-properties(x)"),
            ("example.com##div:contains(x)", "example.com##div:has-text(x)"),
            ("example.com##div:nth-ancestor(2)", "example.com##div:upward(2)"),
            ("example.com##a:watch-attrs(href)", "example.com##a:watch-attr(href)"),
            ("example.com##.a:contains(b)", "example.com##.a:has-text(b)"),
            ("example.com##.a:contains(b):nth-ancestor(1)", "example.com##.a:has-text(b):upward(1)"),
            ("example.com##div:matches-css-after(content: x)", "example.com##div:matches-css-after(content: x)"),
        ]);
    }

    #[test]
    fn rewritten_lines_parse_as_ubo_rules() {
        let cases = [
            "example.com#%#//scriptlet('abort-current-inline-script', 'document.getElementsByTagName', '$$$')",
            "example.com#$#.ad { display: none !important; }",
            "example.com#?#div:-abp-contains(x)",
            "example.com#@$#.ad { display: none !important; }",
        ];
        for line in cases {
            let normalized = adguard_to_ubo(line);
            let parsed = parse_line(&normalized, SourceRef::default());
            assert!(
                matches!(parsed, ParsedLine::Rule(Rule::Cosmetic(_)) | ParsedLine::Rule(Rule::Scriptlet(_))),
                "{line} -> {normalized} -> {parsed:?}"
            );
        }
        let ParsedLine::Rule(Rule::Cosmetic(c)) = parse_line("example.com##div:has-text(x)", SourceRef::default()) else {
            panic!("not a cosmetic rule");
        };
        assert!(matches!(c.body, CosmeticBody::Procedural(_)));
    }
}
