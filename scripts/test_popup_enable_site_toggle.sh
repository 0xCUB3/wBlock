#!/usr/bin/env bash
# CI wrapper for the popup site-enable toggle contract.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
node scripts/test_popup_enable_site_toggle.mjs
