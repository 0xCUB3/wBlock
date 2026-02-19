---
phase: 12-add-backup-and-restore-for-filter-settin
plan: 01
subsystem: settings
tags: [backup, restore, export, import, settings]
dependency_graph:
  requires: []
  provides: [backup-restore-settings]
  affects: [SettingsView, AppFilterManager, ZapperRuleManager]
tech_stack:
  added: [UniformTypeIdentifiers, FileDocument]
  patterns: [BackupManager static methods, NSSavePanel on macOS, fileExporter on iOS, fileImporter]
key_files:
  created:
    - wBlock/BackupManager.swift
  modified:
    - wBlock/SettingsView.swift
decisions:
  - Stored pendingBackup as WBlockBackup (not Data) so confirmation alert can show metadata (date, version, count)
  - Used NSSavePanel on macOS for native save UX, BackupDocument+fileExporter on iOS
  - Backup version field set to 1 for future format migration support
metrics:
  duration: 116s
  completed: 2026-02-19
  tasks_completed: 2
  files_changed: 2
---

# Quick Task 12: Add Backup and Restore for Filter Settings Summary

**One-liner:** JSON export/import for filter selections, whitelist, and zapper rules via BackupManager with native Save/Open dialogs.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create BackupManager with export/import logic | 7facb9e | wBlock/BackupManager.swift |
| 2 | Add Export and Import buttons to SettingsView | d0e378a | wBlock/SettingsView.swift |

## What Was Built

**BackupManager.swift** (new file, 184 lines):
- `WBlockBackup` Codable struct with `version`, `createdAt`, `appVersion`, `filterSelections`, `customFilterLists`, `whitelistedDomains`, `zapperRules`
- `BackupDocument: FileDocument` for iOS fileExporter
- `BackupManager.createBackup(filterManager:)` - reads filter selections (by URL), custom lists (with inline content for wblock:// user lists), whitelist from UserDefaults "disabledSites", and all "zapperRules_*" keys
- `BackupManager.exportData(backup:)` - JSON with prettyPrinted + sortedKeys + ISO8601 dates
- `BackupManager.importData(from:)` - decodes JSON with ISO8601 dates
- `BackupManager.restoreBackup(_:filterManager:)` - restores filter selections by URL match, re-adds custom lists, writes whitelist and zapper rules back to UserDefaults, sets `hasUnappliedChanges = true`, refreshes ZapperRuleManager

**SettingsView.swift** (modified):
- Added state vars: `showingImportDialog`, `showingRestoreBackupConfirmation`, `pendingBackup`, `backupStatusMessage`, `showingBackupStatus`, and iOS-only `backupDocument`/`showingExportSheet`
- "Export Settings" and "Import Settings" buttons added after "Manage Element Zapper Rules" in Actions section
- `exportBackup()`: NSSavePanel on macOS, BackupDocument + fileExporter on iOS
- `.fileImporter` modifier for picking JSON file
- `handleImportResult()`: reads file with security-scoped resource access on iOS, parses backup, shows confirmation with metadata
- `performRestore()`: calls BackupManager.restoreBackup then shows success status
- Confirmation alert shows backup date, app version, and filter count
- Status alert for success/error feedback

## Deviations from Plan

None - plan executed exactly as written.

## Self-Check

**Files exist:**
- wBlock/BackupManager.swift: exists
- wBlock/SettingsView.swift: exists (modified)

**Commits exist:**
- 7facb9e: BackupManager creation
- d0e378a: SettingsView Export/Import buttons

## Self-Check: PASSED
