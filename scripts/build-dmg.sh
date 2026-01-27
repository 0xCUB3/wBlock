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

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
DEVELOPMENT_TEAM_ID="${DEVELOPMENT_TEAM_ID:-}"

mkdir -p "${OUT_DIR}"
rm -f "${DMG_PATH}"

echo "Building ${SCHEME} (${CONFIGURATION})…"
CODE_SIGNING_ALLOWED="NO"
EXTRA_BUILD_SETTINGS=()

if [[ -n "${SIGNING_IDENTITY}" ]]; then
  CODE_SIGNING_ALLOWED="YES"
  EXTRA_BUILD_SETTINGS+=(
    "CODE_SIGN_IDENTITY=${SIGNING_IDENTITY}"
    "CODE_SIGN_STYLE=Manual"
    "ENABLE_HARDENED_RUNTIME=YES"
    "OTHER_CODE_SIGN_FLAGS=--timestamp"
    "PROVISIONING_PROFILE="
    "PROVISIONING_PROFILE_SPECIFIER="
  )
  if [[ -n "${DEVELOPMENT_TEAM_ID}" ]]; then
    EXTRA_BUILD_SETTINGS+=("DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM_ID}")
  fi
fi

xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA}" \
  "CODE_SIGNING_ALLOWED=${CODE_SIGNING_ALLOWED}" \
  "${EXTRA_BUILD_SETTINGS[@]}" \
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
