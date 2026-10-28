# wblock-engine: shared brief

wBlock is a Safari content blocker (macOS 12.3+, iOS 15.4+). It currently uses
AdGuard's SafariConverterLib to turn filter lists into Safari content-blocker
JSON, and AdGuard's extended-css/scriptlets in its "wBlock Scripts" web
extension. This crate replaces all of that with an engine that follows
uBlock Origin's filter semantics (uBO lists first; AdGuard/ABP syntax only as
far as uBO accepts it).

## Architecture

- `crates/wbe/src/ast.rs` — parsed rule types. Shared contract; do not change
  it without being told to. If you need a field, say so in your report.
- `parse/` — line parser (uBO semantics). `normalize.rs` rewrites AdGuard/ABP
  syntax to uBO syntax first.
- `compile/` — rules to Safari JSON (`webkit.rs` types). Everything Safari can
  enforce natively goes native; the rest (procedural cosmetics, `:style`,
  `:remove`, scriptlets) goes to `runtime` for the Scripts extension.
- `runtime.rs` — per-page engine (wraps brave/adblock-rust) for the
  leftovers. `ffi.rs` — C ABI for Swift.
- `harness/` — Node/TypeScript tests and benchmarks. No Swift tests.

Safari facts (verified on macOS 27 / WebKit main): see the header of
`crates/wbe/src/webkit.rs`. In short: one domain/url condition per trigger;
no `redirect`/`modify-headers`/`request-method` for content blockers;
restricted url-filter regex; order matters (`ignore-previous-rules`).

## References (read-only, already on disk)

- uBlock Origin source, pinned commit aaefbdb76ed367da08d8aec193d6e8fa1b84485d:
  `/tmp/research/ublock` — `src/js/static-filtering-parser.js` (syntax,
  option names and aliases), `src/js/static-net-filtering.js` (matching
  semantics, DNR conversion `dnrRulesetFromRawLists`),
  `src/js/cosmetic-filtering.js`, `src/js/scriptlet-filtering.js`,
  `src/js/resources/scriptlets.js`, `src/js/redirect-resources.js`.
- AdGuard SafariConverterLib 4.3.0 (what we replace; good reference for
  WebKit quirks and Safari version gates):
  `~/Library/Developer/Xcode/DerivedData/wBlock-ccgvgkpgtaqtzjfxeodsttzpctkj/SourcePackages/checkouts/SafariConverterLib/Sources/ContentBlockerConverter`
  (see `Compiler/BlockerEntryFactory.swift`, `Rules/NetworkRule.swift`,
  `Rules/CosmeticRule.swift`, `Compiler/SafariRegex.swift`,
  `Rules/SafariVersion.swift`). Its CLI is built at
  `/tmp/research/bench/scl/.build/release/ConverterTool`
  (`ConverterTool --safari-version 18 --advanced-blocking true < list.txt`,
  JSON with `safariRulesJSON` on stdout).
- brave/adblock-rust, commit 6028a6d5735f1e81346eeef73c194c7240035248:
  `/tmp/research/adblock-rust` (`src/content_blocking.rs` is Brave's own,
  more limited, Safari exporter).
- WebKit content-blocker parser: `/tmp/research/cep.cpp`,
  `/tmp/research/cea.cpp`, `/tmp/research/ceb.cpp`.
- Real WebKit compile check: `/tmp/research/bench/wk rules.json` prints
  compile time or the WebKit error for a Safari JSON file.

Licensing: wBlock is GPL-3.0. uBO (GPL-3.0) and adblock-rust/brave resources
(MPL-2.0) may be ported or vendored with attribution in a file header comment.

## Rules for every agent

- Work only in your own worktree and only on the files your task lists.
  Commit there (`git add` your files, `git commit -m "..."`) when done. Do not
  push, do not merge, do not touch other branches.
- Keep the crate compiling: run `cargo check` from `Packages/wblock-engine`
  before you finish. Leave `todo!()` stubs you do not own alone.
- Rust tests live in your module (`#[cfg(test)] mod tests`). Run
  `cargo test --lib <module>` from `Packages/wblock-engine`.
- Match the surrounding code style: short doc comments, no banner comments,
  no dead code, no speculative features.
- When something in uBO's behavior is unclear, read its source; do not guess.
  Cite the uBO function you followed in a one-line comment.
- Finish with a short report: what you built, what tests show, what you
  could not do, and any change you need in shared files.
