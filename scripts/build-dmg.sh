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
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA}" \
  "CODE_SIGNING_ALLOWED=NO" \
  build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Expected app not found at: ${APP_PATH}" >&2
  exit 1
fi

if [[ -n "${SIGNING_IDENTITY}" ]]; then
  echo "Signing app for distribution…"

  sign_item() {
    local item_path="$1"
    local entitlements_path="${2:-}"
    if [[ -n "${entitlements_path}" ]]; then
      codesign --force --options runtime --timestamp \
        --sign "${SIGNING_IDENTITY}" \
        --entitlements "${entitlements_path}" \
        "${item_path}"
    else
      codesign --force --options runtime --timestamp \
        --sign "${SIGNING_IDENTITY}" \
        "${item_path}"
    fi
  }

  # Sign embedded frameworks/dylibs first
  if [[ -d "${APP_PATH}/Contents/Frameworks" ]]; then
    while IFS= read -r -d '' f; do
      sign_item "${f}"
    done < <(find "${APP_PATH}/Contents/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -print0)
  fi

  # Sign embedded XPC services
  if [[ -d "${APP_PATH}/Contents/XPCServices" ]]; then
    while IFS= read -r -d '' xpc; do
      local_entitlements="${ROOT_DIR}/FilterUpdateService/FilterUpdateService.entitlements"
      if [[ -f "${local_entitlements}" ]]; then
        sign_item "${xpc}" "${local_entitlements}"
      else
        sign_item "${xpc}"
      fi
    done < <(find "${APP_PATH}/Contents/XPCServices" -maxdepth 1 -name "*.xpc" -print0)
  fi

  # Sign embedded Safari extensions
  if [[ -d "${APP_PATH}/Contents/PlugIns" ]]; then
    while IFS= read -r -d '' appex; do
      appex_name="$(basename "${appex}" .appex)"
      entitlements=""
      case "${appex_name}" in
        "wBlock Ads") entitlements="${ROOT_DIR}/wBlock Ads/wBlock_Ads.entitlements" ;;
        "wBlock Advanced") entitlements="${ROOT_DIR}/wBlock Advanced/wBlock_Advanced.entitlements" ;;
        "wBlock Security") entitlements="${ROOT_DIR}/wBlock Security/wBlock_Security.entitlements" ;;
        "wBlock Foreign") entitlements="${ROOT_DIR}/wBlock Foreign/wBlock_Foreign.entitlements" ;;
        "wBlock Custom") entitlements="${ROOT_DIR}/wBlock Custom/wBlock_Custom.entitlements" ;;
        "wBlock Privacy") entitlements="${ROOT_DIR}/wBlock/wBlock.entitlements" ;;
      esac

      if [[ -n "${entitlements}" && -f "${entitlements}" ]]; then
        sign_item "${appex}" "${entitlements}"
      else
        sign_item "${appex}"
      fi
    done < <(find "${APP_PATH}/Contents/PlugIns" -maxdepth 1 -name "*.appex" -print0)
  fi

  # Finally, sign the app itself
  app_entitlements="${ROOT_DIR}/wBlock/wBlock.entitlements"
  if [[ -f "${app_entitlements}" ]]; then
    sign_item "${APP_PATH}" "${app_entitlements}"
  else
    sign_item "${APP_PATH}"
  fi

  codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
fi

echo "Creating DMG…"
hdiutil create \
  -volname "wBlock" \
  -srcfolder "${APP_PATH}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" >/dev/null

echo "Created: ${DMG_PATH}"
