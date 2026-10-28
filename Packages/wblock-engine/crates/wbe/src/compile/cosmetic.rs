use super::{CompileOptions, Stats, Tiered};
use crate::ast::{CosmeticRule, NetworkRule};

/// `network` is passed so page-level exceptions (`$elemhide`,
/// `$generichide`, `$specifichide`) can be applied to cosmetic output.
pub(super) fn compile(
    _rules: &[CosmeticRule],
    _network: &[NetworkRule],
    _opts: &CompileOptions,
    _out: &mut Vec<Tiered>,
    _runtime: &mut Vec<String>,
    _stats: &mut Stats,
) {
    todo!("cosmetic compiler")
}
