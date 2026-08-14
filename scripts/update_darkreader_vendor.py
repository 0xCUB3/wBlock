#!/usr/bin/env python3
"""Pin, minify, and patch the official Dark Reader API build.

Usage: scripts/update_darkreader_vendor.py /path/to/darkreader.js
The input is the official unminified npm darkreader@4.9.128 artifact.
Terser is fetched by npx only when updating; it is never a runtime dependency.
"""
import hashlib
import subprocess
import sys
import tempfile
from pathlib import Path

SOURCE_SHA256 = "ce0b18e9a89caf7145292e7d7d2592b5bac664c49567fbf2d59c57a2bc7014e5"
MINIFIED_SHA256 = "629f0a0077c32cdad9b934a06100154c1a47aab00cfef0a88df6214cc4e58c47"
PATCHED_SHA256 = "433921d71add2d8119025c3727fc8ff5357e54ac40dd068ad73ec45619f09206"
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "wBlockCoreService/Vendored/DarkReader/darkreader-api.min.js"

if len(sys.argv) != 2:
    raise SystemExit("usage: update_darkreader_vendor.py /path/to/darkreader.js")
data = Path(sys.argv[1]).read_bytes()
actual = hashlib.sha256(data).hexdigest()
if actual != SOURCE_SHA256:
    raise SystemExit(f"unexpected Dark Reader source hash: {actual} (expected {SOURCE_SHA256})")
with tempfile.TemporaryDirectory() as tmp:
    minified = Path(tmp) / "darkreader.js"
    command = ["npx", "--yes", "--package", "terser@5.46.0", "terser", sys.argv[1],
               "--compress", "--mangle", "--comments", "/^!|@license|Dark Reader v/",
               "--output", str(minified)]
    subprocess.run(command, check=True)
    data = minified.read_bytes()
actual = hashlib.sha256(data).hexdigest()
if actual != MINIFIED_SHA256:
    raise SystemExit(f"unexpected Terser output hash: {actual} (expected {MINIFIED_SHA256})")
s = data.decode("utf-8")
anchor = "window.chrome||(window.chrome={}),chrome.runtime||(chrome.runtime={})"
if s.count(anchor) != 1 or s.count("chrome.runtime") < 1 or s.count("chrome.dom") < 1 or s.count("!e.classList.contains(\"darkreader\")") != 1:
    raise SystemExit("Dark Reader patch anchors changed; refusing to patch")
s = s.replace(anchor, "__wblockDarkReaderChrome")
s = "const __wblockDarkReaderChrome={runtime:{}};" + s
s = s.replace("chrome.runtime", "__wblockDarkReaderChrome.runtime")
s = s.replace("chrome.dom", "__wblockDarkReaderChrome.dom")
s = s.replace("!e.classList.contains(\"darkreader\")", "!e.hasAttribute(\"data-wblock-userstyle\")&&!e.classList.contains(\"darkreader\")")
patched = hashlib.sha256(s.encode()).hexdigest()
if patched != PATCHED_SHA256:
    raise SystemExit(f"unexpected patched hash: {patched} (expected {PATCHED_SHA256})")
OUT.write_text(s)
print(f"wrote {OUT} (sha256={patched})")
