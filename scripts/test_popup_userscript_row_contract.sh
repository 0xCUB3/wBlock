#!/usr/bin/env bash
# CI wrapper for the userscript popup row / disclosure contract.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
node scripts/test_popup_userscript_row_contract.mjs
