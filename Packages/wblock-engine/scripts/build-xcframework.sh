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
# The workspace release profile sets panic = "abort", which would turn a panic
# inside the C ABI into a process abort. ffi.rs needs unwinding to catch it.
export CARGO_PROFILE_RELEASE_PANIC=unwind

MAC_ARM=aarch64-apple-darwin
MAC_X86=x86_64-apple-darwin
IOS=aarch64-apple-ios
SIM_ARM=aarch64-apple-ios-sim
SIM_X86=x86_64-apple-ios

# Run cargo through rustup: a Homebrew cargo or rustc on PATH has no std for
# the targets added through rustup. rustc 1.96 fails to build zerofrom with the
# workspace's lto = "fat" (E0463 on zerofrom_derive); 1.97.1 and 1.98 build.
TOOLCHAIN="${WBE_TOOLCHAIN:-1.98}"
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
