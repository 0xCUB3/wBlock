//! wBlock filter engine: parses uBlock Origin (and uBO-compatible AdGuard /
//! ABP) filter lists and compiles them to Safari content-blocker JSON, plus
//! the leftover rules the wBlock Scripts extension applies per page.

pub mod apply;
pub mod ast;
pub mod compile;
pub mod normalize;
pub mod parse;
pub mod runtime;
pub mod webkit;

#[cfg(not(target_arch = "wasm32"))]
pub mod ffi;

pub use compile::{compile, CompileOptions, CompileOutput, ListInput, Stats};
pub use parse::parse_line;

/// Version of everything the engine writes: Safari JSON, runtime rules, and
/// the serialized per-page engine. Bump it whenever any of them changes for
/// the same input, so callers discard outputs cached by an older engine.
pub const OUTPUT_VERSION: u32 = 5;

/// The registrable domain (eTLD+1) of `host`, or `None` for a public suffix
/// or an invalid name.
pub fn registrable_domain(host: &str) -> Option<&str> {
    addr::parse_domain_name(host).ok()?.root()
}

#[cfg(test)]
mod tests {
    #[test]
    fn registrable_domain_follows_the_public_suffix_list() {
        assert_eq!(
            super::registrable_domain("news.bbc.co.uk"),
            Some("bbc.co.uk")
        );
        assert_eq!(
            super::registrable_domain("example.com"),
            Some("example.com")
        );
        assert_eq!(super::registrable_domain("co.uk"), None);
        assert_eq!(super::registrable_domain("github.io"), None);
    }
}
