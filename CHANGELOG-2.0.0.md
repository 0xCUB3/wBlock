## What's Changed
### Major Features & Improvements
-   **Element Zapper (`be500b0`, `7c76c54`, `a9e7dd2`, `8d6fcc1`, `93c0bd5`, `64d8959`, `e2b0b7a`, #115, #214)**
    Added a full element zapper UI with a blocked-request logger and per-site toggles. Users can now visually select and hide page elements directly in Safari. Manual per-site CSS selector rules can be entered in the in-page zapper for persistent blocking. Fixed CSP-blocked inline injection on macOS, improved iOS tap targets, and unified the popup UI across platforms.
-   **iCloud Sync (`fc56189`, `0135a01`, `2d454f6`, `a60dd80`, `09ffa09`, `eefb77e`, `58c781c`, `519f05d`, #159)**
    Added optional iCloud sync for filter selections, custom lists, userscripts, and whitelist across all your devices. Includes a sync toggle during onboarding and in Settings, CloudKit container entitlements, and platform-safe sync logic. The apply-changes flow was refined to support non-blocking iCloud configuration adoption.
-   **Inline User Lists — Paste and Import (`f48b336`, `aa64ab0`, `76956c9`, `9e0bb58`, `3ea970a`, `a0067f7`, `b33b3e6`, `939d344`, `7ab7076`, `aa0b6fd`, `f962c23`, #90, #201)**
    Added the ability to create custom filter lists by pasting rules directly or importing from a file, in addition to the existing URL method. The Add Filter List sheet now has URL, Paste, and File tabs with per-platform native UI. User lists support custom titles and descriptions, and deletion properly handles iCloud sync tombstones.
-   **Content Blocker Slot Distribution (`5de6f48`, `3449a35`, `aeaf7ca`, #200, #208, #209)**
    Filters are now intelligently distributed across all 5 content blocker extension slots (wBlock 1–5), maximizing the total number of rules Safari can enforce. This replaces the old category-based allocation and allows significantly more rules to be active simultaneously.
-   **Userscript Auto-Update (`1029775`, `e0270d3`)**
    Enabled userscripts are now automatically checked for updates alongside filter lists during the apply-changes flow, with a dedicated progress step.
-   **Custom Filter List Management (`a59ba14`, `1448666`, `46128c8`, `79d0bef`, `0735ec0`)**
    Custom filter lists can now be named, renamed, and assigned to any category. The Add Filter List sheet was simplified and improved on both platforms.
-   **Localization Support (`7498e38`, #218, #219)**
    Added localization infrastructure and major language resources, making wBlock accessible to a much wider audience.
-   **Unified Onboarding (`1330235`)**
    Merged the separate onboarding and setup checklist flows into a single 5-step onboarding experience. Removed the duplicate inline progress view in favor of the standard apply-changes sheet. Eliminated ~190 lines of redundant code.
-   **Toolbar Search (`a7b7b26`, `7abe8e5`, `c75e162`, `c071da4`, `e53288c`)**
    Added searchable filter and userscript lists with native system search UI. macOS uses an expandable toolbar search field, iOS uses the system searchable modifier with minimized behavior.
-   **Homebrew Cask Distribution (`ed2d417`, `046a438`, `0e41d5a`, `e8cfaa5`, `beb1bd1`)**
    Added a native Homebrew cask with a full release pipeline including CI signing and notarization for macOS DMG distribution.
-   **iOS 26 / Liquid Glass Compatibility (`bca15f1`)**
    Replaced iOS 26-only glass APIs with a material-based glass design system that works across all supported OS versions.
---
### Performance & Reliability Upgrades
-   **Streaming IO and Conversion Cache (`6521488`, `854d96f`, `43872f9`)**
    Refactored the update pipeline for dramatically lower IO. Streaming IO replaces full-file reads, and per-target conversion results are cached and reused when inputs haven't changed.
-   **Protobuf Userscript Migration (`6c3bb62`)**
    Userscripts now store only metadata in protobuf, with content files managed separately. Safe migration ensures no data loss during the transition.
-   **Auto-Update Reliability (`f8664aa`, `8b9e9a6`, `bc053f6`, `7f2189e`, `e3c4c2e`, `1a927d3`, `e64b5f6`, `e8aa18a`)**
    Comprehensive hardening of the auto-update system: reliable scheduling, RunningBoard crash mitigation, iOS background fetch fallback, hardened task lifecycle and timeout cleanup, deduplicated entry points, and centralized interval normalization.
-   **Auto-Update Telemetry (`eb0620c`, `6107922`, `4e42ad7`, `c39ac48`, `32e12dd`)**
    Added structured telemetry and skip-reason tracking for auto-updates. Unified manual and auto-update response classification, reduced false-positive update detections, and added mock HTTP integration tests for edge cases.
-   **XPC Continuation Race Fix (`6e2b0ab`)**
    Fixed a race condition in the XPC continuation handling that could cause crashes during filter updates.
-   **Code Cleanup (`b859751`, `1acaadd`, `431dd98`, `89b036d`, `26b9989`, `6742794`)**
    Removed unused userscript and UI dead code, deduplicated filename helpers, removed redundant wrappers and legacy state fields. Apply and auto-update logs are now concise with timing summaries.
---
### Bug Fixes
-   **Dynamic Ad/Script Coverage Gap (`4de4fd1`, #205, #217)**
    Fixed a gap in core conversion that could allow dynamic ads and ad scripts to slip through content blocking.
-   **Userscript Injection Race (`9fe79bb`, #153)**
    Fixed a race condition in userscript injection on Safari that could cause scripts to not activate.
-   **Userscript Injection for ComicRead (`682dc6d`)**
    Fixed userscript injection for sites like ComicRead that use specific content security policies.
-   **CRLF Rule Splitting (`a16bc13`)**
    Fixed filter rule parsing to correctly handle Windows-style CRLF line endings during conversion.
-   **Bypass Paywalls Clean Enable Flow (`5f45b9a`, `2b00fd9`, #215)**
    Fixed the remote userscript enable flow for Bypass Paywalls Clean, and improved userscript matching and batch-enable error reporting.
-   **Userscript Defaults Behavior (`11cc455`, #202)**
    Fixed an issue where deleted default userscripts would reappear unexpectedly.
-   **Custom Filter Persistence (`d574687`)**
    Fixed migrated custom filter lists losing their custom status after migration.
-   **Site Disable in Scripts Extension (`69f26f4`)**
    Fixed per-site disable not working correctly in the Scripts extension.
-   **User List Deletion (`a0067f7`)**
    Fixed user list deletion and ensured iCloud sync tombstones are properly created.
-   **Privacy Target Wiring (`c487934`)**
    Fixed Privacy target wiring and extension plist memberships.
-   **Filter Row Text Clipping (`aacd36d`)**
    Fixed filter row long-press text clipping and corrected stat display order.
-   **Filter Refresh Validators (`3fd1410`)**
    Fixed filter refresh to use persisted validators instead of stale in-memory state.
-   **Production Crash Safety (`dad8fc8`)**
    Replaced a `fatalError` in the ZIP archive builder with graceful error handling, and removed unguarded `print()` statements from production code.
-   **Locale-Aware Userscript Metadata (`dad8fc8`)**
    The userscript metadata parser now respects locale-specific `@description:en` and `@name:en` fields, fixing non-English descriptions showing for scripts like AdGuard Extra.
---
### UI/UX Improvements
-   **Apply Changes Progress View (`519f05d`, `8dd2630`, `72aa5f8`, `d0bb5c5`, `0597de0`)**
    Completely redesigned the apply-changes progress sheet with phase-based progress rows, sub-progress bars, stat cards, and a detailed summary view. Shows the last completed extension name and clarifies reload progress labeling.
-   **Add Filter List Sheet Polish (`79d0bef`, `0735ec0`, `aa64ab0`, `b33b3e6`, `939d344`, `f962c23`, `ad49cb1`)**
    Simplified and polished the Add Filter List sheet across both platforms with native iOS controls, refined layout, macOS TabView integration, and native sheet presentation controls.
-   **Add Userscript Sheet Polish (`bcc40a6`, `9326a3b`, `8198548`)**
    Polished the Add Userscript sheet layout, controls, and helper text copy. Fixed local import labeling.
-   **Remove Redundant Cancel Buttons (`26e7c00`)**
    Removed redundant Cancel buttons from sheet presentations across the app.
-   **Open Collective Link (`20da7c3`)**
    Added an Open Collective funding link in Settings for community support.
---
## Notes
I could not be more grateful for all of your feedback. The community is what keeps this project alive. If you encounter issues or have suggestions, please open an [issue](https://github.com/0xCUB3/wBlock/issues) on GitHub.
Thank you for supporting wBlock and helping make Safari the best browsing experience possible!
# Download
**Download from the App Store:** https://apps.apple.com/app/wblock/id6746388723
## Note: the app is currently in review. It might not be available in your region for up to 72 hours.
## Join the Discord: https://discord.gg/Y3yTFPpbXr
