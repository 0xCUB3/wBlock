#!/usr/bin/env bash
# Builds build/WBE.xcframework: libwbe.a for macOS (universal), iOS device,
# and iOS simulator (universal), with crates/wbe/include as headers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
WORK="$OUT/slices"
HEADERS="$ROOT/crates/wbe/include"
export MACOSX_DEPLOYMENT_TARGET=12.3
export IPHONEOS_DEPLOYMENT_TARGET=15.4

MAC_ARM=aarch64-apple-darwin
MAC_X86=x86_64-apple-darwin
IOS=aarch64-apple-ios
SIM_ARM=aarch64-apple-ios-sim
SIM_X86=x86_64-apple-ios

# Run cargo through rustup: a Homebrew cargo or rustc on PATH has no std for
# the targets added through rustup. rustc 1.96 fails to build zerofrom with the
# workspace's lto = "fat" (E0463 on zerofrom_derive); 1.97.1 and 1.98 build.
TOOLCHAIN="${WBE_TOOLCHAIN:-1.98}"
# A restored CI cache or an earlier local build is reused when nothing that
# goes into the library changed.
STAMP="$OUT/WBE.xcframework.inputs"
inputs="$(cd "$ROOT" && { echo "$TOOLCHAIN"; find Cargo.toml Cargo.lock crates scripts/build-xcframework.sh -type f -print0 | sort -z | xargs -0 shasum; } | shasum | cut -d' ' -f1)"
if [[ -d "$OUT/WBE.xcframework" && "$(cat "$STAMP" 2>/dev/null)" == "$inputs" ]]; then
    echo "WBE.xcframework is current"
    exit 0
fi
# Xcode Cloud and some CI images ship without Rust.
export PATH="$HOME/.cargo/bin:$PATH"
command -v rustup >/dev/null || curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain none
rustup toolchain install "$TOOLCHAIN" --profile minimal
rustup target add --toolchain "$TOOLCHAIN" "$MAC_ARM" "$MAC_X86" "$IOS" "$SIM_ARM" "$SIM_X86"
for target in "$MAC_ARM" "$MAC_X86" "$IOS" "$SIM_ARM" "$SIM_X86"; do
    rustup run "$TOOLCHAIN" cargo build --release --manifest-path "$ROOT/Cargo.toml" -p wbe --lib --target "$target"
done
lib_path() { echo "$ROOT/target/$1/release/libwbe.a"; }

rm -rf "$WORK" "$OUT/WBE.xcframework"
mkdir -p "$WORK/macos" "$WORK/ios" "$WORK/ios-simulator"
lipo -create "$(lib_path "$MAC_ARM")" "$(lib_path "$MAC_X86")" -output "$WORK/macos/libwbe.a"
cp "$(lib_path "$IOS")" "$WORK/ios/libwbe.a"
lipo -create "$(lib_path "$SIM_ARM")" "$(lib_path "$SIM_X86")" -output "$WORK/ios-simulator/libwbe.a"
# Std ships debug info in its rlibs; Xcode links the bodies, not the symbols.
strip -S "$WORK"/macos/libwbe.a "$WORK"/ios/libwbe.a "$WORK"/ios-simulator/libwbe.a

xcodebuild -create-xcframework \
    -library "$WORK/macos/libwbe.a" -headers "$HEADERS" \
    -library "$WORK/ios/libwbe.a" -headers "$HEADERS" \
    -library "$WORK/ios-simulator/libwbe.a" -headers "$HEADERS" \
    -output "$OUT/WBE.xcframework"

du -h "$WORK"/*/libwbe.a
echo "$inputs" > "$STAMP"
