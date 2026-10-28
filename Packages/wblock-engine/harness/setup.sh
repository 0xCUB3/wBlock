#!/usr/bin/env bash
# Fetches uBlock Origin at a pinned commit and builds its Node core
# (static network filtering engine) into harness/.cache/ublock-core.
set -euo pipefail

UBO_COMMIT=aaefbdb76ed367da08d8aec193d6e8fa1b84485d
HARNESS=$(cd "$(dirname "$0")" && pwd)
CACHE=$HARNESS/.cache
SRC=$CACHE/ublock
DEST=$CACHE/ublock-core
LOCAL_COPY=/tmp/research/ublock

mkdir -p "$CACHE"

if [ -d "$LOCAL_COPY/.git" ] && [ "$(git -C "$LOCAL_COPY" rev-parse HEAD)" = "$UBO_COMMIT" ]; then
    rm -rf "$SRC"
    cp -R "$LOCAL_COPY" "$SRC"
else
    if [ ! -d "$SRC/.git" ] || [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$UBO_COMMIT" ]; then
        rm -rf "$SRC"
        mkdir -p "$SRC"
        git -C "$SRC" init -q
        git -C "$SRC" remote add origin https://github.com/gorhill/uBlock
        git -C "$SRC" fetch -q --depth 1 origin "$UBO_COMMIT"
        git -C "$SRC" checkout -q FETCH_HEAD
    fi
fi

# The Node core in uBO's tree is assembled by its own script; it needs the PSL
# data file, which uBO pulls from publicsuffix.org at build time.
rm -rf "$DEST"
(cd "$SRC" && ./tools/make-nodejs.sh "$DEST")
cp "$SRC/src/js/publicsuffix.js" "$SRC/src/js/trusted-tokens.js" "$DEST/js/"
PSL_DIR=$DEST/assets/thirdparties/publicsuffix.org/list
mkdir -p "$PSL_DIR"
curl -sfL -o "$PSL_DIR/effective_tld_names.dat" https://publicsuffix.org/list/public_suffix_list.dat
# uBO's Node build writes a PSL selfie through JSON, which drops the Uint32Array
# it needs, so fromSelfie() silently leaves the list empty. A null selfie makes
# pslInit() parse the .dat file at startup instead.
mkdir -p "$DEST/build"
printf 'null\n' > "$DEST/build/publicsuffixlist.json"
printf '{ "type": "module" }\n' > "$DEST/package.json"
echo "uBO core ready at $DEST (commit $UBO_COMMIT)"
