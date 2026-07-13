#!/bin/sh
set -eu

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

app="$root/Test.app"
framework="$app/Contents/Frameworks/wBlockCoreService.framework"
resources="$framework/Resources/swift-psl_PublicSuffixList.bundle/Contents/Resources"
mkdir -p "$resources"
printf 'resource' > "$resources/common.bin"
printf 'resource' > "$resources/negated.bin"
printf 'resource' > "$resources/asterisk.bin"

scripts/verify_psl_resources.sh "$app"

rm "$resources/asterisk.bin"
if scripts/verify_psl_resources.sh "$app" >/dev/null 2>&1; then
    echo 'FAIL: missing PSL resource should fail verification' >&2
    exit 1
fi

printf 'PASS: PSL resource verifier\n'