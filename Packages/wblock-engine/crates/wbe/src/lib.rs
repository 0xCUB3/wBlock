//! wBlock filter engine: parses uBlock Origin (and uBO-compatible AdGuard /
//! ABP) filter lists and compiles them to Safari content-blocker JSON, plus
//! the leftover rules the wBlock Scripts extension applies per page.

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
