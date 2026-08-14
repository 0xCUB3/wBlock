# wBlock offline Sass artifact

This directory builds a pinned JavaScriptCore bundle for Sass/SCSS evaluation. The source artifact is `final/wblock-sass-1.102.0.js`; shipping outputs are written only to `shipping/`.

The bridge exposes synchronous `wblockSassCompile`. It accepts SCSS or indented Sass, prepends UserCSS-style variables, rejects `@import`, `@use`, and `@forward`, and returns expanded CSS. It uses no filesystem, network, DOM, Node, `process`, `require`, or native bridge at runtime.

## Rebuild

```sh
cd build-tools && npm ci --ignore-scripts
cd ..
./build.sh
```

`build-tools/package-lock.json` pins the current terser release used for this artifact: `terser@5.50.0`, integrity `sha512-CN9BVxWhgS/hRxtUMjtC2uRWSTcSfQFHMDWma6sKKfIivCD91sM+FOPfvwoaRMqCSrUpe1nv3jDamd9eEQ4y+w==`. Minification uses exactly `--compress --mangle --comments false`; no top-level mangling is enabled. `provenance.json` records the resulting sizes and hashes.

The raw and minified bundles are both shipped so semantic comparisons remain reproducible. Gzip sizes use `gzip -n`.

## Verification

Compile and run the direct macOS JavaScriptCore probe against the minified output:

```sh
swiftc shipping/probe.swift -framework JavaScriptCore -o /tmp/wblock-sass-probe
/tmp/wblock-sass-probe shipping/wblock-sass-1.102.0.min.js
```

The probe covers SCSS nesting and variables, indented Sass, syntax errors with locations, absent host globals, and import rejection. It also compares representative compiled CSS from raw and minified bundles byte-for-byte. Swift and JavaScriptCore are required.

`LICENSE.sass` and `LICENSE.immutable` are complete upstream notices and are preserved unchanged.
