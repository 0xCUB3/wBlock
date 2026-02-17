# wBlock Filter Compatibility

## What This Is

A comprehensive filter list compatibility upgrade for wBlock, a macOS/iOS Safari content blocker. wBlock currently fails to load popular filter lists (like Web Annoyances Ultralist) that use preprocessor directives (`!#include`, `!#if`/`!#endif`) and extended AdGuard/uBO filter syntax. This project adds a preprocessing layer and improves overall filter syntax compatibility so users can subscribe to any major community filter list and have it work.

## Core Value

Any popular community filter list that works in AdGuard or uBlock Origin should also work in wBlock.

## Requirements

### Validated

- ✓ Download and parse standard ABP/EasyList filter lists — existing
- ✓ Convert filter rules to Safari content blocker JSON via SafariConverterLib — existing
- ✓ Distribute rules across 5 extension slots with bin-packing — existing
- ✓ Auto-update filters in background (macOS + iOS) — existing
- ✓ Custom filter list subscription via URL — existing
- ✓ Filter list metadata parsing (title, homepage, version, expires) — existing
- ✓ iCloud sync of filter list selections — existing
- ✓ Built-in curated filter lists by category — existing
- ✓ Userscript support via Advanced extension — existing
- ✓ Element zapper in Safari toolbar — existing

### Active

- [ ] Preprocessor directive support (`!#include`, `!#if`/`!#endif`)
- [ ] Extended AdGuard/uBO filter syntax compatibility
- [ ] Graceful handling of unsupported syntax (skip, don't crash)
- [ ] Improved filter list validation (don't reject lists with preprocessor content)

### Out of Scope

- Real-time rule injection (Safari content blocker API is static JSON) — platform limitation
- Full uBlock Origin scriptlet compatibility — different execution model than Safari
- Writing/editing filter rules in-app — user-facing filter authoring is a separate project

## Context

- wBlock uses `AdguardTeam/SafariConverterLib` v4.1.0 for rule conversion
- SafariConverterLib already supports much of the AdGuard extended syntax, but wBlock's download/validation pipeline rejects lists before they reach the converter
- The main file of lists like Ultralist is entirely `!#include` directives — wBlock downloads it, finds no valid rules after stripping unknowns, and rejects it as invalid (error: "Downloaded content does not appear to be a valid filter list", contentLength=1402)
- `!#if`/`!#endif` conditionals wrap platform-specific blocks (e.g., `!#if (adguard_app_ios)`) — wBlock needs to evaluate these for its platform context
- `!#include` directives reference sub-list files by relative URL — wBlock needs to fetch and inline these
- Multiple users in the community have reported issues with various lists, not just Ultralist
- AdGuard and uBO share a common EasyList root but have divergent extensions; AdGuard's directives are documented at adguard.com/kb/general/ad-filtering/create-own-filters/

## Constraints

- **Platform**: Safari Content Blocker API accepts only static JSON — no dynamic script execution at rule level
- **Dependencies**: SafariConverterLib handles rule-level conversion; this project focuses on the preprocessing layer above it
- **Compatibility**: Must not break existing working filter lists
- **Architecture**: Preprocessing must happen before rules are fed to SafariConverterLib for conversion

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Preprocess before SafariConverterLib | SCL handles rule conversion; we handle list assembly and conditional evaluation | — Pending |
| Prioritize `!#include` and `!#if` first | Unblocks the most user-reported lists immediately | — Pending |
| Evaluate conditionals for Safari/wBlock context | Platform variables like `adguard_app_ios`, `ext_safari` determine which rules apply | — Pending |

---
*Last updated: 2026-02-17 after initialization*
