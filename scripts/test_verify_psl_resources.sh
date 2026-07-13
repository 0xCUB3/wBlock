#!/usr/bin/env bash
set -euo pipefail

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

app="$root/Test.app"
mac_framework="$app/Contents/Frameworks/wBlockCoreService.framework"
mac_resources="$mac_framework/Resources/swift-psl_PublicSuffixList.bundle/Contents/Resources"
mkdir -p "$mac_resources"
printf 'resource' > "$mac_resources/common.bin"
printf 'resource' > "$mac_resources/negated.bin"
printf 'resource' > "$mac_resources/asterisk.bin"

ios_framework="$app/PlugIns/Test Extension.appex/Frameworks/wBlockCoreService.framework"
ios_resources="$ios_framework/swift-psl_PublicSuffixList.bundle"
mkdir -p "$ios_resources"
printf 'resource' > "$ios_resources/common.bin"
printf 'resource' > "$ios_resources/negated.bin"
printf 'resource' > "$ios_resources/asterisk.bin"

scripts/verify_psl_resources.sh "$app"

rm "$ios_resources/asterisk.bin"
if scripts/verify_psl_resources.sh "$app" >/dev/null 2>&1; then
    echo 'FAIL: missing PSL resource should fail verification' >&2
    exit 1
fi

printf 'PASS: PSL resource verifier\n'