# Offline PostCSS nested JSC artifact

This directory contains a reproducible browser/IJavaScriptCore bundle for exactly:

- `postcss@8.5.26`
- `postcss-nested@8.0.1`

The bundle is not an arbitrary PostCSS plugin runner. It embeds only those two packages and the pinned transitive dependencies in `package-lock.json`. It performs no filesystem, network, Node, process, DOM, or native-bridge operation.

## API

The IIFE defines one global function, `wblockPostcssNested`. It is synchronous. Pass a JSON string containing `{ "source": string, "variables": object }`; it returns a JSON string containing either `{ "css": string }` or `{ "error": { "name", "message", optional "line", "column" } }`.

`variables` is the `postcss-nested` options object, limited to `bubble`, `unwrap`, `preserveEmpty`, and `rootRuleName`. It is not CSS-variable interpolation and unknown keys are rejected.

Example:

```js
wblockPostcssNested(JSON.stringify({
  source: '.a { .b { color: red } }',
  variables: {}
}))
// {"css":".a .b { color: red }"}
```

## Rebuild

Requires Node/npm and network access only to install the pinned development dependencies. Runtime use is offline.

```sh
npm ci --ignore-scripts
npm run build
```

`build.mjs` uses esbuild browser conditions, ES2020, no sourcemap, minification, and deterministic gzip (`level 9`, `mtime=0`). `final/SIZES.txt` records sizes.

## Verification

```sh
npm run build
swiftc -O swift_probe.swift -framework JavaScriptCore -o /tmp/wblock-jsc-probe
/tmp/wblock-jsc-probe final/wblock-postcss-nested.js
```

The probe covers nested rules, ordinary CSS, `@-moz-document`, syntax errors, and absent host globals. The bundle has no unresolved `require(...)`; browser aliases for optional PostCSS source-map filesystem/path support are empty and unreachable, and `process.env.LANG` is compile-time eliminated. `final/LICENSES/` contains the exact license files for every installed package.

## Supply-chain record

`package-lock.json` contains exact versions, registry tarball URLs, and SHA-512 integrity values for the runtime and build packages. The direct runtime tarballs are:

- postcss 8.5.26 — `sha512-u82N74LFzG8ca+dD8puPnplTXoGH4fTPpVGuIbt36G3qvNlkvfD0lEAZSxaly3KX8TS/L1A1gsCEmvKmBcVbkQ==`
- postcss-nested 8.0.1 — `sha512-PvSIwDVh1NTw939iu4FBK+oeZfSm0cbErFAjXCTPiStammzobBNE2SiQNezy8Xp+Oud2uLXaLpTauv3UdxWjbQ==`

All packages are retained in the lockfile because they are bundled transitively; no runtime package lookup occurs.
