#!/usr/bin/env bash
# CI wrapper for the zapper rules disclosure animation contract.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
node scripts/test_popup_zapper_rules_disclosure.mjs
