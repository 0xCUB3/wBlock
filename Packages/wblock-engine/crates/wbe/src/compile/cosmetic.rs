use super::{CompileOptions, Stats, Tiered};
use crate::ast::CosmeticRule;

/// Page-level exceptions (`$elemhide`, `$generichide`) are network rules and
/// are emitted by `network::compile`.
pub(super) fn compile(
    _rules: &[CosmeticRule],
    _opts: &CompileOptions,
    _out: &mut Vec<Tiered>,
    _runtime: &mut Vec<String>,
    _stats: &mut Stats,
) {
    todo!("cosmetic compiler")
}
