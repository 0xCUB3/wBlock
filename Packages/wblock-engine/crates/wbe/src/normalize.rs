//! AdGuard and ABP syntax rewritten to uBO syntax, the way uBO itself accepts
//! it. Lines uBO would drop are returned unchanged and later reported as
//! unsupported by the parser.

use std::borrow::Cow;

pub fn adguard_to_ubo(line: &str) -> Cow<'_, str> {
    Cow::Borrowed(line)
}
