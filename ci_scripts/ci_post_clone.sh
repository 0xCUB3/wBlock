#!/bin/sh
# Xcode Cloud: build the Rust engine library the WBE package links.
set -eu
"$CI_PRIMARY_REPOSITORY_PATH/Packages/wblock-engine/scripts/build-xcframework.sh"
