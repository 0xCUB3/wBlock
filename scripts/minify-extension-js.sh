#!/usr/bin/env bash
set -euo pipefail

# Minifies the unminified extension JS sources in extension-src/ and the
# procedural cosmetic engine in Packages/wblock-engine/js/ into the shipped
# Safari extension resources in "wBlock Scripts (iOS)/Resources/".
#
# extension-src/*.js and Packages/wblock-engine/js/procedural.js are the source
# of truth. The Resources copies are generated artifacts — never edit them.
#
# Usage: ./scripts/minify-extension-js.sh
# Prerequisites: node (npx fetches the pinned esbuild on first run)

ESBUILD_VERSION="0.28.2"
# Deployment floor is iOS 15.4 / Safari 15.4; safari15 prevents esbuild from
# emitting newer syntax while leaving the existing (already-supported) syntax
# untouched.
ESBUILD_TARGET="safari15"

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${BOLD}[info]${RESET}  $*"; }
success() { echo -e "${GREEN}[ok]${RESET}    $*"; }
error()   { echo -e "${RED}[error]${RESET} $*" >&2; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/extension-src"
ENGINE_JS_DIR="${ROOT_DIR}/Packages/wblock-engine/js"
RES_DIR="${ROOT_DIR}/wBlock Scripts (iOS)/Resources"

FAIL=0

# minify_one <source file> <artifact name>
minify_one() {
  local src="$1"
  local name="$2"
  local out="${RES_DIR}/${name}.js"
  local rel_src="${src#"${ROOT_DIR}/"}"

  if [[ ! -f "${src}" ]]; then
    error "Source not found: ${src}"
    exit 1
  fi

  info "Minifying ${name}.js (${rel_src})..."

  local tmp
  tmp="$(mktemp)"
  npx --yes "esbuild@${ESBUILD_VERSION}" "${src}" \
    --minify \
    --target="${ESBUILD_TARGET}" \
    --line-limit=500 \
    --legal-comments=none \
    --log-level=error \
    --outfile="${tmp}"

  # Banner: tells editors where the real source lives. The no-autoplay gate
  # keeps its own short banner.
  {
    if [[ "${name}" == "no-autoplay-gate" ]]; then
      printf '/*! wBlock No Autoplay gate. */\n'
    fi
    printf '/*! Generated artifact — do not edit. Edit %s and run scripts/minify-extension-js.sh */\n' "${rel_src}"
    cat "${tmp}"
  } > "${out}"
  rm -f "${tmp}"
  perl -pi -e 's/[ \t]+$//' "${out}"

  # --- Artifact checks ---
  if node --check "${out}" 2>/dev/null; then
    success "JS syntax OK: ${name}.js"
  else
    error "JS syntax INVALID: ${name}.js"
    FAIL=1
  fi

  local src_bytes out_bytes
  src_bytes="$(wc -c < "${src}")"
  out_bytes="$(wc -c < "${out}")"
  if (( out_bytes >= src_bytes )); then
    error "Artifact is not smaller than source for ${name}.js (${out_bytes} >= ${src_bytes})"
    FAIL=1
  else
    success "Size: ${name}.js $(( src_bytes / 1024 ))KB -> $(( out_bytes / 1024 ))KB"
  fi
}

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

check_absent() {
  local label="$1"
  local pattern="$2"
  local file="$3"
  if grep -qE "${pattern}" "${file}"; then
    error "${label}: unexpectedly found in $(basename "${file}")"
    FAIL=1
  else
    success "${label}: absent from $(basename "${file}")"
  fi
}

minify_one "${SRC_DIR}/background.js" "background"
minify_one "${SRC_DIR}/content.js" "content"
minify_one "${SRC_DIR}/no-autoplay-gate.js" "no-autoplay-gate"
minify_one "${ENGINE_JS_DIR}/procedural.js" "procedural"

# Symbols the runtime depends on must survive minification.
check_grep "engineTimestamp" "engineTimestamp" "${RES_DIR}/background.js"
check_grep "hide-selector rule" "display: none !important" "${RES_DIR}/background.js"
check_grep "hide-selector rule" "display: none !important" "${RES_DIR}/content.js"
check_grep "procedural API" "wbeProcedural" "${RES_DIR}/procedural.js"
check_grep "procedural API use" "wbeProcedural" "${RES_DIR}/content.js"
check_grep "procedural API use" "wbeProcedural" "${RES_DIR}/background.js"
check_absent "retired AdGuard runtime" "adguard|ExtendedCss|getScriptletFunction|scriptletsMap" "${RES_DIR}/background.js"
check_absent "retired AdGuard runtime" "adguard|ExtendedCss|getScriptletFunction|scriptletsMap" "${RES_DIR}/content.js"

if [[ "${FAIL}" -ne 0 ]]; then
  error "Minification verification failed."
  exit 1
fi

success "Minified artifacts written to ${RES_DIR}"
