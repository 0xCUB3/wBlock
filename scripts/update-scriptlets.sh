#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/update-scriptlets.sh [safari-extension-version]
# Example: ./scripts/update-scriptlets.sh 4.3.0
# If no version argument is given, the script auto-detects npm latest.
#
# Prerequisites: node, pnpm, git (all available via Homebrew on macOS)

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${BOLD}[info]${RESET}  $*"; }
success() { echo -e "${GREEN}[ok]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${RESET}  $*"; }
error()   { echo -e "${RED}[error]${RESET} $*" >&2; }

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SCRIPT_JS="${ROOT_DIR}/wBlock Advanced/Resources/script.js"
BACKGROUND_JS="${ROOT_DIR}/wBlock Scripts (iOS)/Resources/background.js"
CONTENT_JS="${ROOT_DIR}/wBlock Scripts (iOS)/Resources/content.js"

# ---------------------------------------------------------------------------
# Version detection
# ---------------------------------------------------------------------------
if [[ $# -ge 1 ]]; then
  VERSION="$1"
else
  info "No version specified — detecting latest @adguard/safari-extension from npm..."
  VERSION="$(npm view @adguard/safari-extension version)"
fi

echo ""
echo -e "${BOLD}Target: @adguard/safari-extension ${VERSION}${RESET}"
echo ""
warn "Review the version above. Press Ctrl-C within 5 seconds to abort."
sleep 5
echo ""

# ---------------------------------------------------------------------------
# Temp directory — leave on error, clean on success
# ---------------------------------------------------------------------------
WORK_DIR="$(mktemp -d)"
CLONE_DIR="${WORK_DIR}/safari-blocker"

cleanup_on_success() {
  rm -rf "${WORK_DIR}"
}

# Only register the cleanup on EXIT (which runs after a successful run);
# on error (set -e will exit) we intentionally do NOT clean up.
# We achieve this by registering cleanup only after all work is done.

info "Working directory: ${WORK_DIR}"
info "On error, this directory is left intact for debugging."
echo ""

# ---------------------------------------------------------------------------
# Step 1: Clone ameshkov/safari-blocker
# ---------------------------------------------------------------------------
info "Cloning ameshkov/safari-blocker (depth=1)..."
git clone --depth=1 https://github.com/ameshkov/safari-blocker.git "${CLONE_DIR}"
success "Cloned to ${CLONE_DIR}"

# ---------------------------------------------------------------------------
# Step 2: Bump @adguard/safari-extension version in both package.json files
# ---------------------------------------------------------------------------
info "Bumping @adguard/safari-extension to ${VERSION} in package.json files..."

APPEXT_PKG="${CLONE_DIR}/extensions/appext/package.json"
WEBEXT_PKG="${CLONE_DIR}/extensions/webext/package.json"

sed -i '' \
  "s/\"@adguard\/safari-extension\": \"[^\"]*\"/\"@adguard\/safari-extension\": \"${VERSION}\"/" \
  "${APPEXT_PKG}" \
  "${WEBEXT_PKG}"

success "Updated appext/package.json"
success "Updated webext/package.json"

# ---------------------------------------------------------------------------
# Step 3: Build appext (produces dist/script.js)
# ---------------------------------------------------------------------------
info "Building appext (script.js)..."
(
  cd "${CLONE_DIR}/extensions/appext"
  pnpm install --frozen-lockfile=false
  pnpm run build
)
success "appext build complete: ${CLONE_DIR}/extensions/appext/dist/script.js"

# ---------------------------------------------------------------------------
# Step 4: Build webext (produces dist/background.js, dist/content.js)
# ---------------------------------------------------------------------------
info "Building webext (background.js, content.js)..."
(
  cd "${CLONE_DIR}/extensions/webext"
  pnpm install --frozen-lockfile=false
  pnpm run build
)
success "webext build complete"

# ---------------------------------------------------------------------------
# splice_file: replace the upstream section in a wBlock JS file
#
# Arguments:
#   $1  built_file      — fresh upstream build output
#   $2  wblock_file     — existing wBlock file to update in place
#   $3  boundary_pattern — grep pattern that identifies the @file comment
#       beginning the wBlock custom code section (e.g. "@file App extension")
#
# Algorithm:
#   1. In the wBlock file, find the boundary line (the @file comment).
#      Back up 1 line to capture the opening "  /**" of the JSDoc block.
#      Extract everything from that "  /**" to EOF — this is the wBlock custom
#      code that must be preserved.
#   2. In the fresh built file, find the same boundary line.
#      Back up 1 line to capture the opening "  /**".
#      Extract everything BEFORE that line — this is the fresh upstream code.
#   3. Concatenate fresh upstream + wBlock custom → write to wblock_file.
# ---------------------------------------------------------------------------
splice_file() {
  local built_file="$1"
  local wblock_file="$2"
  local boundary_pattern="$3"

  local wblock_basename
  wblock_basename="$(basename "${wblock_file}")"

  info "Splicing ${wblock_basename}..."

  # --- Find boundary in the wBlock file ---
  local wblock_boundary_line
  wblock_boundary_line="$(grep -n "${boundary_pattern}" "${wblock_file}" | head -1 | cut -d: -f1)"

  if [[ -z "${wblock_boundary_line}" ]]; then
    error "Boundary pattern '${boundary_pattern}' not found in ${wblock_file}"
    error "The @file boundary marker may have changed in an upstream update."
    error "Check the file manually and update the boundary pattern if needed."
    exit 1
  fi

  # Back up 1 line to include the opening "  /**" of the JSDoc block
  local wblock_custom_start=$(( wblock_boundary_line - 1 ))

  # --- Find boundary in the built file ---
  local built_boundary_line
  built_boundary_line="$(grep -n "${boundary_pattern}" "${built_file}" | head -1 | cut -d: -f1)"

  if [[ -z "${built_boundary_line}" ]]; then
    error "Boundary pattern '${boundary_pattern}' not found in built file ${built_file}"
    error "The upstream build output format may have changed."
    exit 1
  fi

  # Back up 1 line to exclude the opening "  /**" from the upstream section
  local built_upstream_end=$(( built_boundary_line - 2 ))

  # --- Extract pieces into temp files ---
  local tmp_upstream="${WORK_DIR}/upstream_${wblock_basename}"
  local tmp_custom="${WORK_DIR}/custom_${wblock_basename}"

  head -n "${built_upstream_end}" "${built_file}" > "${tmp_upstream}"
  tail -n +"${wblock_custom_start}" "${wblock_file}" > "${tmp_custom}"

  # --- Concatenate and write ---
  cat "${tmp_upstream}" "${tmp_custom}" > "${wblock_file}"

  success "Spliced ${wblock_basename} (upstream: lines 1-${built_upstream_end}, custom: from wBlock line ${wblock_custom_start})"
}

# ---------------------------------------------------------------------------
# Step 5: Splice all three files
# ---------------------------------------------------------------------------
echo ""
info "--- Splicing files ---"

splice_file \
  "${CLONE_DIR}/extensions/appext/dist/script.js" \
  "${SCRIPT_JS}" \
  "@file App extension content script"

splice_file \
  "${CLONE_DIR}/extensions/webext/dist/background.js" \
  "${BACKGROUND_JS}" \
  "@file Background script for the WebExtension"

splice_file \
  "${CLONE_DIR}/extensions/webext/dist/content.js" \
  "${CONTENT_JS}" \
  "@file Content script for the WebExtension"

# ---------------------------------------------------------------------------
# Step 6: Verification checks
# ---------------------------------------------------------------------------
echo ""
info "--- Running verification checks ---"

FAIL=0

check_grep() {
  local label="$1"
  local pattern="$2"
  local file="$3"
  if grep -q "${pattern}" "${file}"; then
    success "${label}: found in $(basename "${file}")"
  else
    error "${label}: NOT found in $(basename "${file}")"
    FAIL=1
  fi
}

check_syntax() {
  local file="$1"
  if node --check "${file}" 2>/dev/null; then
    success "JS syntax OK: $(basename "${file}")"
  else
    error "JS syntax INVALID: $(basename "${file}")"
    FAIL=1
  fi
}

# Version marker in all three files
check_grep "SafariExtension v${VERSION}" "SafariExtension v${VERSION}" "${SCRIPT_JS}"
check_grep "SafariExtension v${VERSION}" "SafariExtension v${VERSION}" "${BACKGROUND_JS}"
check_grep "SafariExtension v${VERSION}" "SafariExtension v${VERSION}" "${CONTENT_JS}"

# wBlock custom code symbols
check_grep "handleZapperMessage"   "handleZapperMessage"   "${SCRIPT_JS}"
check_grep "wBlockLogger"          "wBlockLogger"           "${SCRIPT_JS}"
check_grep "engineTimestamp"       "engineTimestamp"        "${BACKGROUND_JS}"
check_grep "window.adguard"        "window.adguard"         "${CONTENT_JS}"

# JS syntax
check_syntax "${SCRIPT_JS}"
check_syntax "${BACKGROUND_JS}"
check_syntax "${CONTENT_JS}"

if [[ "${FAIL}" -ne 0 ]]; then
  echo ""
  error "One or more verification checks failed."
  error "Temp directory left for debugging: ${WORK_DIR}"
  exit 1
fi

# ---------------------------------------------------------------------------
# Cleanup (only on success)
# ---------------------------------------------------------------------------
trap cleanup_on_success EXIT

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}${BOLD}--- Done ---${RESET}"
echo ""
echo -e "  Version updated to: ${BOLD}@adguard/safari-extension ${VERSION}${RESET}"
echo "  Files modified:"
echo "    - wBlock Advanced/Resources/script.js"
echo "    - wBlock Scripts (iOS)/Resources/background.js"
echo "    - wBlock Scripts (iOS)/Resources/content.js"
echo ""
echo "  Next step: commit all three files:"
echo -e "  ${BOLD}git add 'wBlock Advanced/Resources/script.js' \\"
echo "        'wBlock Scripts (iOS)/Resources/background.js' \\"
echo "        'wBlock Scripts (iOS)/Resources/content.js'"
echo ""

# Detect scriptlets version embedded in the output for the commit message hint
SCRIPTLETS_VER="$(grep -o 'scriptlets [0-9]*\.[0-9]*\.[0-9]*' "${SCRIPT_JS}" | head -1 | awk '{print $2}' || true)"
if [[ -n "${SCRIPTLETS_VER}" ]]; then
  echo -e "  git commit -m \"rebuild extension JS with safari-extension ${VERSION} (scriptlets ${SCRIPTLETS_VER})\"${RESET}"
else
  echo -e "  git commit -m \"rebuild extension JS with safari-extension ${VERSION}\"${RESET}"
fi
echo ""
