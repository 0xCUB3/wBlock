#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required_keys=(
  "Base filter only."
  "Balanced defaults."
  "Enable the Safari extensions so wBlock can block ads."
  "Manage Element Zapper Rules"
  "Import"
  "Update Interval"
)

missing=0

check_locale() {
  local locale="$1"
  local strings_file="${ROOT_DIR}/wBlock/${locale}.lproj/Localizable.strings"
  local json

  json="$(plutil -convert json -o - "${strings_file}")"

  for key in "${required_keys[@]}"; do
    if ! jq -e --arg key "${key}" 'has($key)' <<<"${json}" >/dev/null; then
      echo "Missing localization key in ${locale}: ${key}" >&2
      missing=1
    fi
  done
}

check_locale "en"
check_locale "el"

exit "${missing}"
