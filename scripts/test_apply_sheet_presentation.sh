#!/bin/bash
set -euo pipefail
# Usage: bash scripts/test_apply_sheet_presentation.sh <available iPad simulator UUID>
# Requires an iOS 26+ SDK; run on iPadOS 17.x as well as a current runtime.
root=$(cd "$(dirname "$0")/.." && pwd)
device=${1:?Pass an available iPad simulator UUID}
xcrun simctl bootstatus "$device" -b
source=${SWIFTUI_COMPAT_SOURCE:-$root/wBlock/SwiftUICompatibility.swift}
work=$(mktemp -d)
bundle=dev.wblock.ApplySheetProbe
trap 'xcrun simctl terminate "$device" "$bundle" >/dev/null 2>&1 || true; xcrun simctl uninstall "$device" "$bundle" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT
app="$work/ApplySheetProbe.app"
mkdir -p "$app"
xcrun --sdk iphonesimulator swiftc -parse-as-library -target "$(uname -m)-apple-ios17.0-simulator" \
    -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    "$source" "$root/scripts/test_apply_sheet_presentation.swift" -o "$app/ApplySheetProbe"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $bundle" \
    -c 'Add :CFBundleExecutable string ApplySheetProbe' \
    -c 'Add :CFBundlePackageType string APPL' \
    -c 'Add :CFBundleSupportedPlatforms array' \
    -c 'Add :CFBundleSupportedPlatforms:0 string iPhoneSimulator' \
    -c 'Add :UIDeviceFamily array' -c 'Add :UIDeviceFamily:0 integer 2' \
    -c 'Add :UILaunchScreen dict' -c 'Add :MinimumOSVersion string 17.0' "$app/Info.plist" >/dev/null
codesign --force --sign - "$app" 2>/dev/null
xcrun simctl install "$device" "$app"
xcrun simctl launch --terminate-running-process --console "$device" "$bundle" | tee "$work/result"
grep -q '^PASS:' "$work/result"
