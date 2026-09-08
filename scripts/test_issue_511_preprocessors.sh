#!/bin/bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/wblock-preprocessors.XXXXXX")
trap 'rm -rf "$TEST_TMP"' EXIT
LOG="$TEST_TMP/core-build.log"
FRAMEWORKS="${WBLOCK_CORE_PRODUCTS:-}"

cd "$ROOT"
(
  cd wBlockCoreService/Resources/UserStyleCompiler
  shasum -a 256 -c SHA256SUMS-runtimes
  shasum -a 256 -c SHA256SUMS-less
  (cd sass && shasum -a 256 -c SHA256SUMS-sass)
  (cd postcss-nested && shasum -a 256 -c SHA256SUMS-postcss-nested)
  (cd stylus && shasum -a 256 -c SHA256SUMS-stylus)
)
# run-ci-tests.sh already built the core framework; reuse it instead of a
# second three-minute xcodebuild.
if [ -n "${WBLOCK_CORE_PRODUCTS:-}" ] && [ -d "${WBLOCK_CORE_PRODUCTS}/wBlockCoreService.framework" ]; then
  FRAMEWORKS="$WBLOCK_CORE_PRODUCTS"
else
  DERIVED="${WBLOCK_DERIVED_DATA:-}"
  if [ -z "$DERIVED" ]; then
    for candidate in "$HOME"/Library/Developer/Xcode/DerivedData/wBlock-*/Build/Products/Debug/wBlock.app; do
      if [ -d "$candidate" ]; then
        DERIVED="${candidate%/Build/Products/Debug/wBlock.app}"
        break
      fi
    done
  fi
  : "${DERIVED:?Set WBLOCK_DERIVED_DATA to the existing signed Xcode build directory}"
  FRAMEWORKS="$DERIVED/Build/Products/Debug"
  signing_args=()
  if [[ "${CI:-}" == "true" ]]; then signing_args+=(CODE_SIGNING_ALLOWED=NO); fi
  xcodebuild -project wBlock.xcodeproj -scheme wBlockCoreService \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
    "${signing_args[@]}" build >"$LOG" 2>&1 || { cat "$LOG"; exit 1; }
fi

swiftc -D DEBUG -framework WebKit -framework CryptoKit \
  scripts/test_userstyle_parsing_and_matching.swift \
  wBlockCoreService/UserStyleCompilerExecutionHost.swift \
  wBlockCoreService/UserStyleCompiler.swift \
  wBlockCoreService/UserStyle.swift \
  wBlockCoreService/UserStyleRemoteImportInliner.swift \
  wBlockCoreService/UserScript.swift \
  wBlockCoreService/FilterListCategory.swift \
  -o "$TEST_TMP/userstyle-tests"

swiftc -D DEBUG -framework WebKit -framework CryptoKit \
  scripts/test_issue_511_compiler_timeout.swift \
  wBlockCoreService/UserStyleCompilerExecutionHost.swift \
  wBlockCoreService/UserStyleCompiler.swift \
  wBlockCoreService/UserStyle.swift \
  wBlockCoreService/UserScript.swift \
  wBlockCoreService/FilterListCategory.swift \
  -o "$TEST_TMP/timeout-tests"
"$TEST_TMP/timeout-tests"

WBLOCK_LESS_BUNDLE="$ROOT/wBlockCoreService/Resources/UserStyleCompiler/less.min.js" \
WBLOCK_SASS_BUNDLE="$ROOT/wBlockCoreService/Resources/UserStyleCompiler/sass/wblock-sass-1.104.0.min.js" \
WBLOCK_STYLUS_BUNDLE="$ROOT/wBlockCoreService/Resources/UserStyleCompiler/stylus/stylus-jsc.js" \
WBLOCK_POSTCSS_BUNDLE="$ROOT/wBlockCoreService/Resources/UserStyleCompiler/postcss-nested/wblock-postcss-nested.js" \
  "$TEST_TMP/userstyle-tests"

swiftc scripts/test_issue_511_packaged_compilers.swift \
  -F "$FRAMEWORKS" -framework wBlockCoreService \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -o "$TEST_TMP/packaged-tests"
"$TEST_TMP/packaged-tests"

find wBlock -path '*.lproj/Localizable.strings' -print0 \
  | xargs -0 -n1 plutil -lint >/dev/null
git diff --check

echo "PASS: issue #511 preprocessors"
