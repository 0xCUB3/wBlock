#!/bin/bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DERIVED="${TMPDIR:-/tmp}/wblock-issue-511-tests"
LOG="${TMPDIR:-/tmp}/wblock-issue-511-build.log"
FRAMEWORKS="$DERIVED/Build/Products/Debug"

cd "$ROOT"
(
  cd wBlockCoreService/Resources/UserStyleCompiler
  shasum -a 256 -c SHA256SUMS-runtimes
  shasum -a 256 -c SHA256SUMS-less
  (cd sass && shasum -a 256 -c SHA256SUMS-sass)
  (cd postcss-nested && shasum -a 256 -c SHA256SUMS-postcss-nested)
  (cd stylus && shasum -a 256 -c SHA256SUMS-stylus)
)
rm -rf "$DERIVED"
xcodebuild -project wBlock.xcodeproj -scheme wBlockCoreService \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build >"$LOG" 2>&1

swiftc -D DEBUG -framework WebKit -framework CryptoKit \
  scripts/test_userstyle_parsing_and_matching.swift \
  wBlockCoreService/UserStyleCompilerExecutionHost.swift \
  wBlockCoreService/UserStyleCompiler.swift \
  wBlockCoreService/UserStyle.swift \
  wBlockCoreService/UserScript.swift \
  wBlockCoreService/FilterListCategory.swift \
  -o "${TMPDIR:-/tmp}/wblock-userstyle-preprocessor-tests"

swiftc -D DEBUG -framework WebKit -framework CryptoKit \
  scripts/test_issue_511_compiler_timeout.swift \
  wBlockCoreService/UserStyleCompilerExecutionHost.swift \
  wBlockCoreService/UserStyleCompiler.swift \
  wBlockCoreService/UserStyle.swift \
  wBlockCoreService/UserScript.swift \
  wBlockCoreService/FilterListCategory.swift \
  -o "${TMPDIR:-/tmp}/wblock-compiler-timeout-tests"
"${TMPDIR:-/tmp}/wblock-compiler-timeout-tests"

WBLOCK_LESS_BUNDLE="$ROOT/wBlockCoreService/Resources/UserStyleCompiler/less.min.js" \
WBLOCK_SASS_BUNDLE="$ROOT/wBlockCoreService/Resources/UserStyleCompiler/sass/wblock-sass-1.102.0.min.js" \
WBLOCK_STYLUS_BUNDLE="$ROOT/wBlockCoreService/Resources/UserStyleCompiler/stylus/stylus-jsc.js" \
WBLOCK_POSTCSS_BUNDLE="$ROOT/wBlockCoreService/Resources/UserStyleCompiler/postcss-nested/wblock-postcss-nested.js" \
  "${TMPDIR:-/tmp}/wblock-userstyle-preprocessor-tests"

swift scripts/test_issue_511_compiled_style_contract.swift
swift scripts/test_userstyle_less_import_contract.swift
swift scripts/test_issue_508_file_import_contract.swift
swift scripts/test_issue_508_text_metadata_source.swift
swift scripts/test_issue_508_localization.swift

swiftc scripts/test_issue_511_packaged_compilers.swift \
  -F "$FRAMEWORKS" -framework wBlockCoreService \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -o "${TMPDIR:-/tmp}/wblock-packaged-preprocessor-tests"
"${TMPDIR:-/tmp}/wblock-packaged-preprocessor-tests"

find wBlock -path '*.lproj/Localizable.strings' -print0 \
  | xargs -0 -n1 plutil -lint >/dev/null
git diff --check

echo "PASS: issue #511 preprocessors"
