#!/usr/bin/env bash
# CI wrapper for the No Autoplay popup visibility contract.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
node scripts/test_popup_no_autoplay_contract.mjs
