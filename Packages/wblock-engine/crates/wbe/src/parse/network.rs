use crate::ast::{ParsedLine, SourceRef};

/// Parse a network filter (anything that is not a cosmetic/scriptlet line).
pub(super) fn parse(_line: &str, _source: SourceRef) -> ParsedLine {
    todo!("network parser")
}
