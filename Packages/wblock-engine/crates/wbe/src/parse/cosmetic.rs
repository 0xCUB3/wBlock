use crate::ast::{ParsedLine, SourceRef};

/// Parse a cosmetic, scriptlet, or HTML-filter line. Returns `None` when the
/// line has no cosmetic marker (`##`, `#@#`, `#?#`, `#$#`, `#%#`, `##^`, ...),
/// so the caller treats it as a network filter.
pub(super) fn parse(_line: &str, _source: SourceRef) -> Option<ParsedLine> {
    todo!("cosmetic parser")
}
