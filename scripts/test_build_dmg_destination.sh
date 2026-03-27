#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="${ROOT_DIR}/scripts/build-dmg.sh"

if ! grep -Fq -- '-destination "generic/platform=macOS"' "${BUILD_SCRIPT}"; then
  echo "expected build-dmg.sh to use generic/platform=macOS" >&2
  exit 1
fi

if grep -Fq -- '-destination "platform=macOS"' "${BUILD_SCRIPT}"; then
  echo "build-dmg.sh still uses platform=macOS" >&2
  exit 1
fi
