//! Line parser. Mirrors uBO's static-filtering-parser.js: which marker a line
//! uses, which options exist (and their aliases), and what is invalid.

pub(crate) mod cosmetic;
mod network;

use crate::ast::{ParsedLine, SourceRef};

/// Parse one already-normalized line (see `normalize::adguard_to_ubo`).
pub fn parse_line(line: &str, source: SourceRef) -> ParsedLine {
    let line = line.trim();
    if line.is_empty() || line.starts_with('!') || line.starts_with('[') {
        return ParsedLine::Ignored;
    }
    if let Some(parsed) = cosmetic::parse(line, source) {
        return parsed;
    }
    network::parse(line, source)
}
