#!/usr/bin/env bash
# Builds build/WBE.xcframework: libwbe.a for macOS (universal), iOS device,
# and iOS simulator (universal), with crates/wbe/include as headers.
# Set WBE_SLICES to a comma-separated subset of macos,ios,ios-simulator (default: all)
# to build only the slices needed by a single CI platform action.
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

SLICES="${WBE_SLICES:-all}"
if [[ "$SLICES" == "all" ]]; then
    SLICES="macos,ios,ios-simulator"
fi

WANT_MACOS=0
WANT_IOS=0
WANT_SIM=0
TARGETS=()
IFS=',' read -ra SLICE_LIST <<< "$SLICES"
for slice in "${SLICE_LIST[@]}"; do
    case "$slice" in
        macos)
            WANT_MACOS=1
            TARGETS+=("$MAC_ARM" "$MAC_X86")
            ;;
        ios)
            WANT_IOS=1
            TARGETS+=("$IOS")
            ;;
        ios-simulator)
            WANT_SIM=1
            TARGETS+=("$SIM_ARM" "$SIM_X86")
            ;;
        *)
            echo "Unknown WBE_SLICES entry: $slice (expected macos, ios, ios-simulator, or all)" >&2
            exit 2
            ;;
    esac
done
if [[ "${#TARGETS[@]}" -eq 0 ]]; then
    echo "WBE_SLICES selected no targets" >&2
    exit 2
fi

# Run cargo through rustup: a Homebrew cargo or rustc on PATH has no std for
# the targets added through rustup.
TOOLCHAIN="${WBE_TOOLCHAIN:-1.98}"
# A restored CI cache or an earlier local build is reused when nothing that
# goes into the library changed.
STAMP="$OUT/WBE.xcframework.inputs"
inputs="$(cd "$ROOT" && { echo "$TOOLCHAIN"; echo "$SLICES"; find Cargo.toml Cargo.lock crates scripts/build-xcframework.sh -type f -print0 | sort -z | xargs -0 shasum; } | shasum | cut -d' ' -f1)"
if [[ -d "$OUT/WBE.xcframework" && "$(cat "$STAMP" 2>/dev/null)" == "$inputs" ]]; then
    echo "WBE.xcframework is current ($SLICES)"
    exit 0
fi

# Xcode Cloud and some CI images ship without Rust. Their network sometimes
# refuses early connections (build 1656, 1711), including inside rustup-init.sh
# and rustup's own downloads, so retry the whole install/toolchain/target steps.
retry() {
    local attempt=1
    local max_attempts=5
    while true; do
        if "$@"; then
            return 0
        fi
        local status=$?
        if [[ "$attempt" -ge "$max_attempts" ]]; then
            return "$status"
        fi
        echo "Command failed with exit $status (attempt $attempt/$max_attempts); retrying in 5s: $*" >&2
        attempt=$((attempt + 1))
        sleep 5
    done
}

install_rustup() {
    curl --proto '=https' --tlsv1.2 -sSf --retry 5 --retry-all-errors --retry-delay 5 https://sh.rustup.rs \
        | sh -s -- -y --profile minimal --default-toolchain none
}

export PATH="$HOME/.cargo/bin:$PATH"
command -v rustup >/dev/null || retry install_rustup
if ! rustup toolchain list | grep -q "^${TOOLCHAIN}"; then
    retry rustup toolchain install "$TOOLCHAIN" --profile minimal
fi
INSTALLED_TARGETS="$(rustup target list --toolchain "$TOOLCHAIN" --installed)"
MISSING_TARGETS=()
for target in "${TARGETS[@]}"; do
    if ! grep -qx "$target" <<< "$INSTALLED_TARGETS"; then
        MISSING_TARGETS+=("$target")
    fi
done
if [[ "${#MISSING_TARGETS[@]}" -gt 0 ]]; then
    retry rustup target add --toolchain "$TOOLCHAIN" "${MISSING_TARGETS[@]}"
fi

# Build all requested targets in one cargo invocation so build scripts and
# proc-macros compile once and target builds pipeline across CPU cores.
TARGET_ARGS=()
for target in "${TARGETS[@]}"; do
    TARGET_ARGS+=(--target "$target")
done
rustup run "$TOOLCHAIN" cargo build --release --manifest-path "$ROOT/Cargo.toml" -p wbe --lib "${TARGET_ARGS[@]}"

lib_path() { echo "$ROOT/target/$1/release/libwbe.a"; }

rm -rf "$WORK" "$OUT/WBE.xcframework"
XCFRAMEWORK_ARGS=()
if [[ "$WANT_MACOS" -eq 1 ]]; then
    mkdir -p "$WORK/macos"
    lipo -create "$(lib_path "$MAC_ARM")" "$(lib_path "$MAC_X86")" -output "$WORK/macos/libwbe.a"
    strip -S "$WORK/macos/libwbe.a"
    XCFRAMEWORK_ARGS+=(-library "$WORK/macos/libwbe.a" -headers "$HEADERS")
fi
if [[ "$WANT_IOS" -eq 1 ]]; then
    mkdir -p "$WORK/ios"
    cp "$(lib_path "$IOS")" "$WORK/ios/libwbe.a"
    strip -S "$WORK/ios/libwbe.a"
    XCFRAMEWORK_ARGS+=(-library "$WORK/ios/libwbe.a" -headers "$HEADERS")
fi
if [[ "$WANT_SIM" -eq 1 ]]; then
    mkdir -p "$WORK/ios-simulator"
    lipo -create "$(lib_path "$SIM_ARM")" "$(lib_path "$SIM_X86")" -output "$WORK/ios-simulator/libwbe.a"
    strip -S "$WORK/ios-simulator/libwbe.a"
    XCFRAMEWORK_ARGS+=(-library "$WORK/ios-simulator/libwbe.a" -headers "$HEADERS")
fi

xcodebuild -create-xcframework \
    "${XCFRAMEWORK_ARGS[@]}" \
    -output "$OUT/WBE.xcframework"

du -h "$WORK"/*/libwbe.a
echo "$inputs" > "$STAMP"
