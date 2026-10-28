use super::{CompileOptions, Stats, Tiered};
use crate::ast::NetworkRule;

pub(super) fn compile(
    _rules: &[NetworkRule],
    _opts: &CompileOptions,
    _out: &mut Vec<Tiered>,
    _stats: &mut Stats,
) {
    todo!("network compiler")
}
