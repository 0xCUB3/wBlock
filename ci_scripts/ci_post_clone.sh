#!/bin/sh
# Xcode Cloud: build only the Rust engine slice needed for this workflow action.
set -eu

case "${CI_PRODUCT_PLATFORM:-}" in
    macOS)
        WBE_SLICES="macos"
        ;;
    iOS)
        case "${CI_XCODEBUILD_ACTION:-}" in
            archive)
                WBE_SLICES="ios"
                ;;
            build-for-testing|test-without-building)
                WBE_SLICES="ios-simulator"
                ;;
            *)
                WBE_SLICES="ios,ios-simulator"
                ;;
        esac
        ;;
    *)
        WBE_SLICES="all"
        ;;
esac

echo "Xcode Cloud WBE build: platform=${CI_PRODUCT_PLATFORM:-unset} action=${CI_XCODEBUILD_ACTION:-unset} slices=${WBE_SLICES}"
export WBE_SLICES
exec "$CI_PRIMARY_REPOSITORY_PATH/Packages/wblock-engine/scripts/build-xcframework.sh"
