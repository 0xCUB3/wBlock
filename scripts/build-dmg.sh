#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/wBlock.xcodeproj"
SCHEME="wBlock"
CONFIGURATION="Release"

OUT_DIR="${ROOT_DIR}/build/homebrew"
DERIVED_DATA="${OUT_DIR}/DerivedData"
APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/wBlock.app"
DMG_PATH="${OUT_DIR}/wBlock.dmg"

mkdir -p "${OUT_DIR}"
rm -f "${DMG_PATH}"

echo "Building ${SCHEME} (${CONFIGURATION})…"
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Expected app not found at: ${APP_PATH}" >&2
  exit 1
fi

echo "Creating DMG…"
hdiutil create \
  -volname "wBlock" \
  -srcfolder "${APP_PATH}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" >/dev/null

echo "Created: ${DMG_PATH}"
