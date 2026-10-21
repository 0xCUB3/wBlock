#!/bin/bash
# Checks the bundled userstyle compiler sources against their pinned hashes.
# The compiler behavior tests run as separate jobs in run-ci-tests.sh.
set -euo pipefail

cd "$(dirname "$0")/../wBlockCoreService/Resources/UserStyleCompiler"
shasum -a 256 -c SHA256SUMS-runtimes
shasum -a 256 -c SHA256SUMS-less
(cd stylus && shasum -a 256 -c SHA256SUMS-stylus)
cd ../../..
find wBlock -path '*.lproj/Localizable.strings' -print0 | xargs -0 -n1 plutil -lint >/dev/null
