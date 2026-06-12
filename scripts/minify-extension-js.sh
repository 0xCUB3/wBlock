#!/usr/bin/env bash
set -euo pipefail

# Minifies the unminified extension JS sources in extension-src/ into the
# shipped Safari extension resources in "wBlock Scripts (iOS)/Resources/".
#
# extension-src/*.js are the source of truth (spliceable by
# scripts/update-scriptlets.sh and hand-editable in the wBlock custom
# sections). The Resources copies are generated artifacts — never edit them.
#
# Usage: ./scripts/minify-extension-js.sh
# Prerequisites: node (npx fetches the pinned esbuild on first run)

ESBUILD_VERSION="0.28.1"
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
RES_DIR="${ROOT_DIR}/wBlock Scripts (iOS)/Resources"

FAIL=0

minify_one() {
  local name="$1"
  local src="${SRC_DIR}/${name}.js"
  local out="${RES_DIR}/${name}.js"

  if [[ ! -f "${src}" ]]; then
    error "Source not found: ${src}"
    exit 1
  fi

  # Pull version markers out of the unminified source for the banner.
  local ext_version scriptlets_version
  ext_version="$(grep -o 'SafariExtension v[0-9][0-9.]*' "${src}" | head -1 || true)"
  scriptlets_version="$(grep -o 'scriptlets [0-9][0-9.]*' "${src}" | head -1 || true)"

  info "Minifying ${name}.js (${ext_version:-unknown version}${scriptlets_version:+, ${scriptlets_version}})..."

  local tmp
  tmp="$(mktemp)"
  npx --yes "esbuild@${ESBUILD_VERSION}" "${src}" \
    --minify \
    --target="${ESBUILD_TARGET}" \
    --line-limit=500 \
    --legal-comments=none \
    --log-level=error \
    --outfile="${tmp}"

  # Banner: keeps the version greppable in the artifact and tells editors
  # where the real source lives. GPL-3.0 notice carried over from upstream.
  {
    printf '/*! %s%s. Upstream (c) Adguard Software Ltd., GPL-3.0, https://github.com/AdguardTeam/SafariConverterLib/tree/master/Extension */\n' \
      "${ext_version:-SafariExtension}" "${scriptlets_version:+ (${scriptlets_version})}"
    printf '/*! Generated artifact — do not edit. Edit extension-src/%s.js and run scripts/minify-extension-js.sh */\n' "${name}"
    cat "${tmp}"
  } > "${out}"
  rm -f "${tmp}"

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

minify_one "background"
minify_one "content"

# Symbols the runtime depends on must survive minification.
check_grep "engineTimestamp" "engineTimestamp" "${RES_DIR}/background.js"
check_grep "window.adguard"  "window.adguard"  "${RES_DIR}/content.js"
check_grep "version banner"  "SafariExtension v" "${RES_DIR}/background.js"
check_grep "version banner"  "SafariExtension v" "${RES_DIR}/content.js"

if [[ "${FAIL}" -ne 0 ]]; then
  error "Minification verification failed."
  exit 1
fi

success "Minified artifacts written to ${RES_DIR}"
