//! Line parser. Mirrors uBO's static-filtering-parser.js: which marker a line
//! uses, which options exist (and their aliases), and what is invalid.

pub(crate) mod cosmetic;
mod network;

use crate::ast::{ParsedLine, SourceRef};

/// Parse one already-normalized line (see `normalize::adguard_to_ubo`).
pub fn parse_line(line: &str, source: SourceRef) -> ParsedLine {
    let line = line.trim();
    // uBO's `reCommentLine`: other `[` lines, like `[$domain=/re/]##.x`, are filters.
    let header = line.get(..8).is_some_and(|s| s.eq_ignore_ascii_case("[adblock"));
    if line.is_empty() || line.starts_with('!') || header {
        return ParsedLine::Ignored;
    }
    if let Some(parsed) = cosmetic::parse(line, source) {
        return parsed;
    }
    network::parse(line, source)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ast::{DomainMatcher, Rule};

    #[test]
    fn only_adblock_headers_are_bracket_comments() {
        assert_eq!(parse_line("[Adblock Plus 2.0]", SourceRef::default()), ParsedLine::Ignored);
        let ParsedLine::Rule(Rule::Scriptlet(r)) =
            parse_line("[$domain=/^www\\.a\\.(com|net)$/]##+js(set, x, 1)", SourceRef::default())
        else {
            panic!("regex-scoped scriptlet ignored");
        };
        assert_eq!(r.domains.include, [DomainMatcher::Regex("^www\\.a\\.(com|net)$".into())]);
    }
}
