#!/usr/bin/env bash
# CI wrapper for the native popup layout contract.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
node scripts/test_popup_native_layout_contract.mjs
