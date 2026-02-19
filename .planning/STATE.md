# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-19)

**Core value:** Any popular community filter list that works in AdGuard or uBlock Origin should also work in wBlock
**Current focus:** v1.2 Distribution & Code Signing — Phase 10: Build and Entitlements

## Current Position

Milestone: v1.2 Distribution & Code Signing
Phase: 10 of 12 (Build and Entitlements)
Plan: 2 of 2 complete
Status: Phase 10 complete
Last activity: 2026-02-19 — Phase 10 Plan 02 complete (archive + exportArchive pipeline, spctl gate)

Progress: [██████████░░░░░░░░░░░░░░░░░░░░] v1.0 + v1.1 shipped, v1.2 starting

## Performance Metrics

**v1.0 Velocity:**
- Total plans completed: 10
- Phases: 6
- Timeline: 2 days (2026-02-17 → 2026-02-18)

**v1.1 Velocity:**
- Total plans completed: 3
- Phases: 3
- Timeline: 1 day (2026-02-19)

**v1.2 Velocity:**
- Total plans completed: 2
- Phases: 3 planned

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.

Recent decisions affecting v1.2:
- Switch entire build approach to `xcodebuild archive` + `exportArchive` — `CODE_SIGNING_ALLOWED=NO` + manual re-sign is the root cause of error 163 and cannot be fixed incrementally
- Phase 11 has one open design decision: Path A (Developer ID provisioning profile covering CloudKit + push) vs Path B (separate entitlements file without APS/iCloud for Developer ID builds). Resolve by auditing whether CloudKit or APNs are called at runtime in the direct-download build path before planning Phase 11.
- Phase 10-01: All 5 extension entitlements (Advanced, Privacy, Security, Custom, Foreign) required app-sandbox key — added matching wBlock Ads reference structure
- Phase 10-01: ENABLE_HARDENED_RUNTIME was NO on wBlock Ads target — fixed to YES in both Debug and Release (required for notarization)

### Pending Todos

None.

### Blockers/Concerns

- Phase 11 (Notarization): `aps-environment`/iCloud entitlements require either a Developer ID provisioning profile (Path A) or stripping those entitlements from the Developer ID build (Path B). Path depends on whether CloudKit/push are used at runtime. Resolve during Phase 11 planning via 5-10 min code audit.

## Session Continuity

Last session: 2026-02-19
Stopped at: Phase 10 Plan 02 complete — ready for Phase 11 (Notarization)
Resume file: None

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 1 | audit and merge PR #248 | 2026-02-18 | 73e9615 | [1-audit-and-merge-pr-248](./quick/1-audit-and-merge-pr-248/) |
| 2 | audit and merge PR #247 | 2026-02-18 | 5a42ef4 | [2-audit-and-merge-pr-247](./quick/2-audit-and-merge-pr-247/) |
| 3 | fix stale rules count when 0 filters enabled | 2026-02-19 | 083b34c | [3-fix-update-button-disabled-when-0-filter](./quick/3-fix-update-button-disabled-when-0-filter/) |
| 4 | review and merge PR #252 (SafariConverterLib 4.2.1) | 2026-02-19 | 292c834 | [4-scaffold-pr-252-and-merge-if-clean](./quick/4-scaffold-pr-252-and-merge-if-clean/) |
| 5 | update comparison page with recent features (issue #246) | 2026-02-19 | 6579bc9 | [5-update-adblock-comparison-md-with-recent](./quick/5-update-adblock-comparison-md-with-recent/) |
| 6 | fix keyboard auto-focus on iOS add sheets (issue #249) | 2026-02-19 | 3a02265 | [6-fix-keyboard-auto-focus-covering-bottom-](./quick/6-fix-keyboard-auto-focus-covering-bottom-/) |
| 7 | fix element zapper undo not restoring all elements (issue #242) | 2026-02-19 | 24237f4 | [7-fix-element-zapper-undo-not-restoring-al](./quick/7-fix-element-zapper-undo-not-restoring-al/) |
| 8 | fix Package.resolved for Xcode Cloud builds | 2026-02-19 | b00ce43 | [8-fix-package-resolved-out-of-date-for-xc](./quick/8-fix-package-resolved-out-of-date-for-xc/) |
| 9 | add Manage Whitelist to iOS Settings (issue #241) | 2026-02-19 | 3c7cbe6 | [9-add-manage-whitelist-section-to-ios-sett](./quick/9-add-manage-whitelist-section-to-ios-sett/) |
| 10 | fix regional filters empty if app closed on first launch (issue #231) | 2026-02-19 | 9d94efb | [10-fix-regional-filters-empty-if-app-closed](./quick/10-fix-regional-filters-empty-if-app-closed/) |
| 11 | fix element zapper rules dropdown not collapsing and truncating to 3 (issue #243) | 2026-02-19 | 283eaef | [11-fix-element-zapper-rules-dropdown-not-co](./quick/11-fix-element-zapper-rules-dropdown-not-co/) |
| 12 | add backup and restore for filter settings (issue #244) | 2026-02-19 | d0e378a | [12-add-backup-and-restore-for-filter-settin](./quick/12-add-backup-and-restore-for-filter-settin/) |
