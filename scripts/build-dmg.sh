#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/wBlock.xcodeproj"
SCHEME="wBlock"
CONFIGURATION="Release"

OUT_DIR="${ROOT_DIR}/build/homebrew"
ARCHIVE_PATH="${OUT_DIR}/wBlock.xcarchive"
EXPORT_PATH="${OUT_DIR}/export"
APP_PATH="${EXPORT_PATH}/wBlock.app"
DMG_PATH="${OUT_DIR}/wBlock.dmg"

mkdir -p "${OUT_DIR}"
rm -f "${DMG_PATH}"
rm -rf "${ARCHIVE_PATH}"
rm -rf "${EXPORT_PATH}"

echo "Archiving ${SCHEME} (${CONFIGURATION})…"

# Build the archive command with optional provisioning updates
ARCHIVE_CMD=(xcodebuild archive
  -project "${PROJECT_PATH}"
  -scheme "${SCHEME}"
  -configuration Release
  -destination "platform=macOS"
  -archivePath "${ARCHIVE_PATH}"
  CODE_SIGN_STYLE=Automatic
  DEVELOPMENT_TEAM=DNP7DGUB7B
  "CODE_SIGN_IDENTITY=Developer ID Application"
)

# In CI, pass -allowProvisioningUpdates with API key so Xcode can
# auto-manage provisioning profiles for all targets
if [[ -n "${APPLE_API_KEY_P8_B64:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER_ID:-}" ]]; then
  KEY_PATH="${RUNNER_TEMP:-/tmp}/AuthKey_${APPLE_API_KEY_ID}.p8"
  if [[ ! -f "${KEY_PATH}" ]]; then
    echo "${APPLE_API_KEY_P8_B64}" | base64 --decode > "${KEY_PATH}"
  fi
  ARCHIVE_CMD+=(
    -allowProvisioningUpdates
    -authenticationKeyPath "${KEY_PATH}"
    -authenticationKeyID "${APPLE_API_KEY_ID}"
    -authenticationKeyIssuerID "${APPLE_API_ISSUER_ID}"
  )
  echo "Using API key for automatic provisioning"
fi

"${ARCHIVE_CMD[@]}"

if [[ ! -d "${ARCHIVE_PATH}" ]]; then
  echo "Expected archive not found at: ${ARCHIVE_PATH}" >&2
  exit 1
fi

echo "Exporting archive…"
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_PATH}" \
  -exportOptionsPlist "${ROOT_DIR}/ExportOptions.plist"

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
