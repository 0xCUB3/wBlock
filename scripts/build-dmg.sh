#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/wBlock.xcodeproj"
SCHEME="wBlock"
CONFIGURATION="Release"

OUT_DIR="${ROOT_DIR}/build/homebrew"
DERIVED_DATA="${OUT_DIR}/DerivedData"
APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/wBlock.app"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
VERSION="${VERSION:-}"
if [[ -n "${VERSION}" ]]; then
  DMG_NAME="wBlock-${VERSION}.dmg"
else
  DMG_NAME="wBlock.dmg"
fi
DMG_PATH="${OUT_DIR}/${DMG_NAME}"

mkdir -p "${OUT_DIR}"
rm -f "${DMG_PATH}"

TEAM_ID="${TEAM_ID:-DNP7DGUB7B}"

echo "Building ${SCHEME} (${CONFIGURATION})…"
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA}" \
  "CODE_SIGNING_ALLOWED=NO" \
  "ARCHS=arm64 x86_64" \
  build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Expected app not found at: ${APP_PATH}" >&2
  exit 1
fi

# CODE_SIGNING_ALLOWED=NO leaves $(AppIdentifierPrefix) unresolved in plists.
# Patch it so Safari can identify the extension's team, and so GroupIdentifier
# can construct the team-prefixed group ID (avoids Sequoia TCC prompts).
if [[ -n "${TEAM_ID}" ]]; then
  # Patch appex plists
  for appex_plist in "${APP_PATH}/Contents/PlugIns/"*.appex/Contents/Info.plist; do
    if [[ -f "${appex_plist}" ]]; then
      if ! /usr/libexec/PlistBuddy -c "Print :AppIdentifierPrefix" "${appex_plist}" &>/dev/null; then
        /usr/libexec/PlistBuddy -c "Add :AppIdentifierPrefix string ${TEAM_ID}." "${appex_plist}"
      else
        /usr/libexec/PlistBuddy -c "Set :AppIdentifierPrefix ${TEAM_ID}." "${appex_plist}"
      fi
    fi
  done

  # Patch main app plist so GroupIdentifier picks up the team prefix
  main_plist="${APP_PATH}/Contents/Info.plist"
  if [[ -f "${main_plist}" ]]; then
    if ! /usr/libexec/PlistBuddy -c "Print :AppIdentifierPrefix" "${main_plist}" &>/dev/null; then
      /usr/libexec/PlistBuddy -c "Add :AppIdentifierPrefix string ${TEAM_ID}." "${main_plist}"
    else
      /usr/libexec/PlistBuddy -c "Set :AppIdentifierPrefix ${TEAM_ID}." "${main_plist}"
    fi
  fi

  # Patch XPC service plists so they also use the team-prefixed group
  if [[ -d "${APP_PATH}/Contents/XPCServices" ]]; then
    for xpc_plist in "${APP_PATH}/Contents/XPCServices/"*.xpc/Contents/Info.plist; do
      if [[ -f "${xpc_plist}" ]]; then
        if ! /usr/libexec/PlistBuddy -c "Print :AppIdentifierPrefix" "${xpc_plist}" &>/dev/null; then
          /usr/libexec/PlistBuddy -c "Add :AppIdentifierPrefix string ${TEAM_ID}." "${xpc_plist}"
        else
          /usr/libexec/PlistBuddy -c "Set :AppIdentifierPrefix ${TEAM_ID}." "${xpc_plist}"
        fi
      fi
    done
  fi
fi

if [[ -n "${SIGNING_IDENTITY}" ]]; then
  echo "Signing app for distribution…"

  TEAM_GROUP="${TEAM_ID}.group.skula.wBlock"

  # Create a modified entitlements file that adds the team-prefixed app group.
  # On macOS Sequoia, non-MAS apps accessing a group container without a team
  # prefix trigger repeated "access data from other apps" TCC prompts.
  prepare_entitlements() {
    local src="$1"
    local tmp
    tmp=$(mktemp)
    cp "${src}" "${tmp}"
    # Check if application-groups array exists and add team-prefixed group
    if /usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups" "${tmp}" &>/dev/null; then
      /usr/libexec/PlistBuddy -c "Add :com.apple.security.application-groups: string ${TEAM_GROUP}" "${tmp}" 2>/dev/null || true
    fi
    echo "${tmp}"
  }

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

  # Sign embedded frameworks first (inside-out)
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
        modified_ent="$(prepare_entitlements "${local_entitlements}")"
        sign_item "${xpc}" "${modified_ent}"
        rm -f "${modified_ent}"
      else
        sign_item "${xpc}"
      fi
    done < <(find "${APP_PATH}/Contents/XPCServices" -maxdepth 1 -name "*.xpc" -print0)
  fi

  # Sign embedded Safari extensions (sign nested frameworks inside each appex first)
  if [[ -d "${APP_PATH}/Contents/PlugIns" ]]; then
    while IFS= read -r -d '' appex; do
      # Sign frameworks nested inside the appex before signing the appex itself
      if [[ -d "${appex}/Contents/Frameworks" ]]; then
        while IFS= read -r -d '' nested; do
          sign_item "${nested}"
        done < <(find "${appex}/Contents/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -print0)
      fi

      appex_name="$(basename "${appex}" .appex)"
      entitlements=""
      case "${appex_name}" in
        "wBlock Ads") entitlements="${ROOT_DIR}/wBlock Ads/wBlock_Ads.entitlements" ;;
        "wBlock Scripts") entitlements="${ROOT_DIR}/wBlock Scripts/wBlock Scripts.entitlements" ;;
        "wBlock Security") entitlements="${ROOT_DIR}/wBlock Security/wBlock_Security.entitlements" ;;
        "wBlock Foreign") entitlements="${ROOT_DIR}/wBlock Foreign/wBlock_Foreign.entitlements" ;;
        "wBlock Custom") entitlements="${ROOT_DIR}/wBlock Custom/wBlock_Custom.entitlements" ;;
        "wBlock Privacy") entitlements="${ROOT_DIR}/wBlock Privacy/wBlock_Privacy.entitlements" ;;
        "wBlock Scripts") entitlements="${ROOT_DIR}/wBlock Scripts/wBlock Scripts.entitlements" ;;
      esac

      if [[ -n "${entitlements}" && -f "${entitlements}" ]]; then
        modified_ent="$(prepare_entitlements "${entitlements}")"
        sign_item "${appex}" "${modified_ent}"
        rm -f "${modified_ent}"
      else
        sign_item "${appex}"
      fi
    done < <(find "${APP_PATH}/Contents/PlugIns" -maxdepth 1 -name "*.appex" -print0)
  fi

  # Sign the main app last (outermost)
  # Use the direct-distribution entitlements which strip restricted
  # entitlements (iCloud, push notifications) that require an embedded
  # provisioning profile. Without a profile, AMFI rejects the app on launch.
  app_entitlements="${ROOT_DIR}/wBlock/wBlock-DirectDistribution.entitlements"
  if [[ -f "${app_entitlements}" ]]; then
    modified_ent="$(prepare_entitlements "${app_entitlements}")"
    sign_item "${APP_PATH}" "${modified_ent}"
    rm -f "${modified_ent}"
  else
    sign_item "${APP_PATH}"
  fi

  echo "Verifying code signature…"
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
