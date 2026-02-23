# AdGuard Syntax Highlighting for Custom Filter Rules

**Issue:** https://github.com/0xCUB3/wBlock/issues/263
**Date:** 2026-02-23

## Summary

Add real-time syntax highlighting to the custom filter rule editor (`EditUserListView`) on both macOS and iOS. Uses native `NSTextView`/`UITextView` wrappers with `NSAttributedString` coloring, no external dependencies.

## Architecture

Three components:

1. **`AdGuardSyntaxHighlighter.swift`** -- Shared tokenizer. Takes a `String`, returns `NSAttributedString` with syntax colors applied per-line via regex matching. Platform-agnostic.

2. **`SyntaxHighlightingTextView.swift`** -- SwiftUI representable wrapping `NSTextView` (macOS) and `UITextView` (iOS) via `#if os()`. Exposes `Binding<String>` for drop-in replacement of `TextEditor`.

3. **Edit to `ContentView.swift`** -- Replace `TextEditor(text: $rules)` in `EditUserListView` (lines ~1567 and ~1657) with `SyntaxHighlightingTextView(text: $rules)`.

## Syntax Elements

Processed per-line via regex:

| Element | Pattern | Color |
|-|-|-|
| Comments | `!` prefix | Gray/dim |
| Section headers | `[Adblock Plus ...]` | Gray italic |
| Element hiding | `##`, `#@#`, `#?#`, `#$#` | Purple/violet |
| URL blocking | `\|\|domain^` patterns | Blue |
| Exception rules | `@@` prefix | Green |
| Modifiers | `$domain=`, `$third-party` etc. | Orange |
| Extended CSS | `#?#`, `:has()`, `:contains()` | Teal |
| Scriptlets | `#%#//scriptlet(...)` | Red/pink |
| HTML filtering | `$$` rules | Yellow/amber |
| Regex patterns | `/regex/` | Cyan |
| Domains | domain portion before `##` etc. | Default/primary |

Colors adapt to light/dark mode using semantic colors or adaptive `UIColor`/`NSColor`.

## Performance

- Re-highlight on text change only
- Line-by-line processing
- Debounce ~100ms for large lists (10k+ lines)

## Scope

- Both macOS and iOS
- Full AdGuard syntax support
- No line numbers
- No external dependencies
