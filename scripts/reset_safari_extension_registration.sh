#!/usr/bin/env bash
set -euo pipefail

# Repairs macOS LaunchServices/pluginkit state for local wBlock debug builds.
# Use when SFContentBlockerManager.reloadContentBlocker reports SFErrorDomain Code=1
# (SFError.noExtensionFound) even though the app and extensions are built.
#
# The common local-development cause is multiple registered wBlock.app build products
# with the same extension bundle identifiers under different DerivedData/build paths.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -x "$LSREGISTER" ]]; then
  echo "lsregister not found at $LSREGISTER" >&2
  exit 1
fi

echo "Quit Safari and wBlock before running this repair. Continuing in 2 seconds…"
sleep 2

# Remove stale registrations from repo-local build folders. These are created by
# xcodebuild -derivedDataPath smoke builds and can confuse SafariServices.
if [[ -d "$ROOT_DIR/build" ]]; then
  while IFS= read -r appex; do
    echo "unregister stale appex: $appex"
    pluginkit -r "$appex" 2>/dev/null || true
  done < <(find "$ROOT_DIR/build" -path '*/wBlock.app/Contents/PlugIns/*.appex' -type d 2>/dev/null | sort)
fi

# Re-register Safari's extension points. This is the targeted fix recommended by
# Safari extension developers for SFErrorDomain Code=1 caused by stale LS state.
echo "re-register Safari extension points"
"$LSREGISTER" -f -R /Applications/Safari.app

# Re-register the current Xcode debug app if present.
ACTIVE_APP=""
while IFS= read -r app; do
  if [[ "$app" != *Index.noindex* ]]; then
    ACTIVE_APP="$app"
    break
  fi
done < <(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug/wBlock.app' -type d 2>/dev/null | sort -r)

if [[ -n "$ACTIVE_APP" ]]; then
  echo "re-register active app: $ACTIVE_APP"
  "$LSREGISTER" -f -R "$ACTIVE_APP"
else
  echo "no active Xcode Debug wBlock.app found under DerivedData"
fi

# Restart registration-related daemons. They restart automatically.
echo "restart plug-in/LaunchServices preference daemons"
killall -9 pluginkit 2>/dev/null || true
killall -9 pkd 2>/dev/null || true
killall -9 cfprefsd 2>/dev/null || true
sleep 1

echo
echo "Registered wBlock macOS content blockers:"
pluginkit -m -A -D -vvv \
  | grep -E 'skula\.wBlock\.wBlock-(Ads|Privacy|Security|Foreign|Custom)( |$|\()' -A2 -B1 \
  || echo "No wBlock content blocker registrations found. Build/run the app from Xcode once."

echo
echo "Done. Reopen wBlock, then open Safari Settings > Extensions and make sure the wBlock blockers are enabled."
