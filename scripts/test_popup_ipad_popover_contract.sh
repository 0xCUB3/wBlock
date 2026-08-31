#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
node scripts/test_popup_ipad_popover_contract.mjs
