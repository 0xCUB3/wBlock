#!/bin/bash
# Runs the production rules viewer in a small simulator host with real touch gestures.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SIMULATOR=${1:?Pass an available iOS simulator UUID}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/wblock-scroll-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/scripts/rules-viewer-ui/"{App.swift,ScrollTests.swift,project.yml} "$WORK/"
for source in MonospacedTextView ViewportSyntaxHighlighter AdGuardSyntaxHighlighter; do
    ln -s "$ROOT/wBlock/$source.swift" "$WORK/$source.swift"
done
xcodegen generate --spec "$WORK/project.yml" --project "$WORK"
xcodebuild -project "$WORK/ScrollProbe.xcodeproj" -scheme ScrollProbe \
    -destination "platform=iOS Simulator,id=$SIMULATOR" \
    -parallel-testing-enabled NO test
