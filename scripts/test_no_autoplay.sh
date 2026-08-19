#!/usr/bin/env bash
# CI wrapper for the No Autoplay content script behavioral test.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
node scripts/test_no_autoplay.mjs
