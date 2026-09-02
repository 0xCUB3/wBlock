#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

run() {
  echo "[test] $*"
  "$@"
}

# Source-contract tests are ordinary top-level Swift scripts. Tests with @main
# are compiled below with their production dependencies instead of being run in
# an invalid interpreter context.
for test in scripts/test_*.swift; do
  if ! grep -q '@main' "$test" && ! grep -q 'import wBlockCoreService' "$test"; then
    run swift "$test"
  fi
done

# The skipped Swift tests are compiled in explicit dependency groups below. The
# temporary module is built from the same Xcode target used by production; tests
# that need internal production symbols are compiled with those source files in
# the same invocation instead of being weakened or treated as source contracts.
CORE_DERIVED_DATA="$TMP/core-derived-data"
run xcodebuild -project wBlock.xcodeproj \
  -scheme wBlockCoreService \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$CORE_DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null
CORE_PRODUCTS="$CORE_DERIVED_DATA/Build/Products/Debug"

compile_core_test() {
  local name="$1"
  local test="$2"
  shift 2
  local test_source="$TMP/$name.swift"
  if grep -q '^import wBlockCoreService\\b' "$test"; then
    cp "$test" "$test_source"
  else
    {
      echo 'import wBlockCoreService'
      cat "$test"
    } > "$test_source"
  fi
  echo "[test] $name ($test)"
  swiftc -parse-as-library \
    -F "$CORE_PRODUCTS" -I "$CORE_PRODUCTS" -L "$CORE_PRODUCTS" \
    -framework wBlockCoreService \
    -Xlinker -rpath -Xlinker "$CORE_PRODUCTS" \
    "$@" "$test_source" -o "$TMP/$name"
  "$TMP/$name"
}

compile_direct_test() {
  local name="$1"
  shift
  local test="${!#}"
  echo "[test] $name ($test)"
  swiftc -parse-as-library "$@" -o "$TMP/$name"
  "$TMP/$name"
}

# Tests with only Foundation and repository-file inspection.
compile_direct_test adguard-mobile scripts/test_adguard_mobile_filter_migration.swift
compile_direct_test apply-progress-localization scripts/test_apply_progress_localization.swift
compile_direct_test compiler-timeout scripts/test_issue_511_compiler_timeout.swift
compile_direct_test issue-574-cloudkit-availability scripts/test_issue_574_cloudkit_availability.swift
compile_direct_test issue-574-filters-scroll-reset scripts/test_issue_574_filters_scroll_reset.swift
compile_direct_test language-selection-localization scripts/test_language_selection_localization.swift
compile_direct_test main-window-frame-restore \
  wBlock/MainWindowFrameRestorer.swift scripts/test_main_window_frame_restore.swift
compile_direct_test site-settings-localization scripts/test_site_settings_localization.swift

# Core-module API tests. Source-only wBlock tests add their production source
# explicitly; the remaining tests use the freshly built core framework.
compile_core_test apply-progress-presentation scripts/test_apply_progress_presentation.swift \
  wBlock/ApplyChangesViewModel.swift
compile_core_test apply-update-counts scripts/test_apply_update_counts.swift \
  wBlock/ApplyChangesViewModel.swift
compile_core_test filter-refresh-planner scripts/test_filter_refresh_planner.swift
compile_core_test cosmetic-filtering-preference scripts/test_cosmetic_filtering_preference.swift
compile_core_test cloud-custom-filters scripts/test_cloud_sync_custom_filters.swift \
  wBlock/CloudSyncCustomFilterSync.swift
compile_core_test cloud-local-user-scripts scripts/test_cloud_sync_local_user_scripts.swift \
  wBlock/CloudSyncUserScriptSync.swift
compile_core_test cloud-remote-user-scripts scripts/test_cloud_sync_remote_user_scripts.swift \
  wBlock/CloudSyncRemoteUserScriptSync.swift
cat > "$TMP/localization-formatting-shim.swift" <<'SWIFT'
import Foundation

extension Locale {
  static var appCurrent: Locale { .current }
}

enum LocalizedFormatting {
  static func relativeDateTimeFormatter(unitsStyle: RelativeDateTimeFormatter.UnitsStyle) -> RelativeDateTimeFormatter {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = unitsStyle
    return formatter
  }

  static func timeFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter
  }

  static func dateTimeFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
    return formatter
  }
}
SWIFT
compile_direct_test cloud-timestamp-formatter \
  "$TMP/localization-formatting-shim.swift" \
  wBlock/CloudSyncTimestampFormatter.swift scripts/test_cloud_sync_timestamp_formatter.swift
compile_core_test cloud-upload-coordinator scripts/test_cloud_sync_upload_coordinator.swift
compile_core_test dark-reader-appearance scripts/test_dark_reader_appearance_preference.swift
compile_core_test disabled-sites-normalization scripts/test_disabled_sites_normalization.swift
compile_core_test filter-list-flags scripts/test_filter_list_flags.swift
compile_direct_test filter-update-popup-status \
  wBlockCoreService/FilterUpdatePopupStatus.swift \
  scripts/test_filter_update_popup_status.swift
compile_core_test filter-selection-rebase scripts/test_filter_selection_rebase.swift
compile_core_test filter-catalog-remote scripts/test_filter_catalog_remote.swift
compile_core_test filter-list-fetch-chain scripts/test_filter_list_fetch_chain.swift
compile_core_test issue-508-backup scripts/test_issue_508_backup_userscript.swift
compile_core_test issue-508-import-identity scripts/test_issue_508_import_identity.swift
compile_core_test issue-508-oversized-import scripts/test_issue_508_oversized_import.swift
compile_core_test issue-531-custom-exception-affinity scripts/test_issue_531_custom_exception_affinity.swift
compile_core_test removeparam-dnr scripts/test_removeparam_dnr_rule_generator.swift
compile_core_test safari-affinity-snapshot scripts/test_safari_affinity_snapshot_behavior.swift
compile_core_test safari-rule-limit-cap scripts/test_safari_rule_limit_cap.swift
compile_core_test site-component-disable-policy scripts/test_site_component_disable_policy.swift
compile_core_test user-script-url-support scripts/test_userscript_url_support.swift
compile_core_test zapper-native-rules scripts/test_zapper_native_rule_generator.swift

# These tests exercise internal generated/model state and therefore compile the
# production files beside the test. SwiftProtobuf is the package product built
# by the same Xcode invocation.
compile_direct_test issue-508-protobuf-roundtrip \
  -I "$CORE_PRODUCTS" "$CORE_PRODUCTS/SwiftProtobuf.o" \
  wBlockCoreService/DataModels.pb.swift scripts/test_issue_508_protobuf_roundtrip.swift
compile_direct_test userscript-persistence-race \
  -I "$CORE_PRODUCTS" "$CORE_PRODUCTS/SwiftProtobuf.o" \
  wBlockCoreService/DataModels.pb.swift \
  wBlockCoreService/UserScriptPersistence.swift \
  scripts/test_userscript_persistence_race.swift
compile_direct_test userscript-matching-payload \
  wBlockCoreService/FilterListCategory.swift \
  wBlockCoreService/UserScript.swift \
  wBlockCoreService/UserStyle.swift \
  wBlockCoreService/UserStyleCompiler.swift \
  wBlockCoreService/UserStyleCompilerExecutionHost.swift \
  scripts/test_userscript_matching_and_payload.swift
compile_direct_test userscript-metadata-emoji \
  wBlockCoreService/FilterListCategory.swift \
  wBlockCoreService/UserScript.swift \
  wBlockCoreService/UserStyle.swift \
  wBlockCoreService/UserStyleCompiler.swift \
  wBlockCoreService/UserStyleCompilerExecutionHost.swift \
  scripts/test_userscript_metadata_emoji_strip.swift
echo "[test] userstyle-parsing-matching (scripts/test_userstyle_parsing_and_matching.swift)"
swiftc -parse-as-library -D DEBUG \
  wBlockCoreService/FilterListCategory.swift \
  wBlockCoreService/UserScript.swift \
  wBlockCoreService/UserStyle.swift \
  wBlockCoreService/UserStyleCompiler.swift \
  wBlockCoreService/UserStyleCompilerExecutionHost.swift \
  wBlockCoreService/UserStyleRemoteImportInliner.swift \
  scripts/test_userstyle_parsing_and_matching.swift -o "$TMP/userstyle-parsing-matching"
WBLOCK_LESS_BUNDLE="$ROOT/wBlockCoreService/Resources/UserStyleCompiler/less.min.js" \
WBLOCK_SASS_BUNDLE="$ROOT/wBlockCoreService/Resources/UserStyleCompiler/sass/wblock-sass-1.102.0.min.js" \
WBLOCK_STYLUS_BUNDLE="$ROOT/wBlockCoreService/Resources/UserStyleCompiler/stylus/stylus-jsc.js" \
WBLOCK_POSTCSS_BUNDLE="$ROOT/wBlockCoreService/Resources/UserStyleCompiler/postcss-nested/wblock-postcss-nested.js" \
  "$TMP/userstyle-parsing-matching"

# This one intentionally remains a script-mode compile: its top-level semaphore
# loop is the test's executable entry point.
echo "[test] packaged-compilers (scripts/test_issue_511_packaged_compilers.swift)"
swiftc -F "$CORE_PRODUCTS" -I "$CORE_PRODUCTS" -L "$CORE_PRODUCTS" \
  -framework wBlockCoreService -Xlinker -rpath -Xlinker "$CORE_PRODUCTS" \
  scripts/test_issue_511_packaged_compilers.swift -o "$TMP/packaged-compilers"
WBLOCK_LESS_BUNDLE="$ROOT/wBlockCoreService/Resources/UserStyleCompiler/less.min.js" \
WBLOCK_SASS_BUNDLE="$ROOT/wBlockCoreService/Resources/UserStyleCompiler/sass/wblock-sass-1.102.0.min.js" \
WBLOCK_STYLUS_BUNDLE="$ROOT/wBlockCoreService/Resources/UserStyleCompiler/stylus/stylus-jsc.js" \
WBLOCK_POSTCSS_BUNDLE="$ROOT/wBlockCoreService/Resources/UserStyleCompiler/postcss-nested/wblock-postcss-nested.js" \
  "$TMP/packaged-compilers"

for test in scripts/test_*.sh; do
  run bash "$test"
done

compile_and_run() {
  local name="$1"
  shift
  echo "[test] $name"
  swiftc -parse-as-library "$@" -o "$TMP/$name"
  "$TMP/$name"
}

compile_and_run adguard-syntax \
  wBlock/AdGuardSyntaxHighlighter.swift \
  scripts/test_adguard_syntax_highlighter.swift

compile_and_run filter-diff \
  wBlockCoreService/FilterDiffUpdater.swift \
  scripts/test_filter_diff_updater.swift

compile_and_run include-resolution \
  wBlockCoreService/IncludeResolver.swift \
  wBlockCoreService/ConditionalEvaluator.swift \
  wBlockCoreService/PlatformConstants.swift \
  scripts/test_include_resolver_url_encoding.swift

compile_and_run pause-store \
  wBlockCoreService/GroupIdentifier.swift \
  wBlockCoreService/BlockingPauseStore.swift \
  scripts/test_issue_508_pause_store.swift

compile_and_run bounded-concurrency \
  wBlockCoreService/AsyncConcurrency.swift \
  scripts/test_bounded_concurrent_compact_map.swift

compile_and_run filter-validation \
  wBlockCoreService/FilterListValidation.swift \
  scripts/test_filter_list_validation.swift

echo "All CI tests passed"
