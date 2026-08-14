# Offline UserStyle compiler runtimes

wBlock runs each selected compiler in a fresh Blob Worker owned by a disposable, nonpersistent `WKWebView`. The host passes JSON-compatible data only and exposes no native message bridge. Network, nested workers, imports, and browser storage are disabled before the fixed bundled runtime loads. A page-side watchdog terminates the Worker after 10 seconds, including when compiler JavaScript is stuck synchronously. Source is limited to 2 MiB and generated CSS to 10 MiB.

The Worker runs in WebKit's WebContent process, which keeps compiler failure separate from ordinary app work. WebKit does not expose a per-Worker memory cap, so the source/output limits and fixed offline subsets remain necessary. Raw UserCSS is authoritative for persistence, cloud sync, and backups; compiled output is a validated transient sidecar.

| Backend | Exact revision | Runtime | Size | SHA-256 |
| --- | --- | --- | ---: | --- |
| Less | 4.9.0 | `less.min.js` | 158,891 | `59c1ed0a6f51215a702b3b4095bf9f296c67d5c1610f82b95d82991c3c3f3082` |
| Sass / SCSS | 1.102.0 | `sass/wblock-sass-1.102.0.min.js` | 3,277,321 | `a575120ee471de3fc9f8ddad036f4296de483ec312daf960bdda8f289582d6c8` |
| PostCSS + nested | 8.5.26 + 8.0.1 | `postcss-nested/wblock-postcss-nested.js` | 125,669 | `68709da6d84de1838dfde79a68b0451f242eb4f2fa60a0b2f38fcb0a79f1d60e` |
| Stylus | 0.64.0, bounded offline | `stylus/stylus-jsc.js` | 420,979 | `8e6ef62152979cac41e145b3056d1a3a1c7ea6b2359bcf1ef332655b2b23af4b` |

The Sass bridge supports SCSS and indented Sass, variables, nesting, and mixins. Sass `@import`, `@use`, and `@forward` are rejected. Stylus supports its offline core, globals, nesting, and mixins; imports, plugins, file-backed helpers, and source maps are rejected. PostCSS is deliberately the pinned `postcss-nested` plugin only. Less imports and inline JavaScript are disabled, while ordinary CSS imports remain in generated CSS.

Supported metadata preprocessors are empty/default, `uso`, `less`, `sass`, `scss`, `stylus`, and `postcss`. A complete UserCSS metadata block is required; file extensions identify candidates but never select a compiler. Recognized paths include `.css`, `.user.css`, `.less`, `.sass`, `.scss`, `.styl`, and `.pcss`, including matching URL query values.

## Packaging and verification

`wBlockCoreService` supports macOS and iOS, including the iOS app running in Apple Vision compatibility mode; it is not a native xrOS target. Xcode's synchronized resource group may flatten these directories in a built framework, so runtime lookup checks `UserStyleCompiler/` and then the framework root. Runtime basenames are unique. The packaged-framework test in `scripts/test_issue_511_preprocessors.sh` executes all four runtimes from the built product.

Verify the checked-in source artifacts in place:

```sh
cd wBlockCoreService/Resources/UserStyleCompiler
shasum -a 256 -c SHA256SUMS-runtimes
shasum -a 256 -c SHA256SUMS-less
(cd sass && shasum -a 256 -c SHA256SUMS-sass)
(cd postcss-nested && shasum -a 256 -c SHA256SUMS-postcss-nested)
(cd stylus && shasum -a 256 -c SHA256SUMS-stylus)
```

`LESS-PROVENANCE.md` records Less's npm origin and byte-for-byte comparison. The backend directories retain exact dependency versions, upstream notices, generation records, and shipped-tree checksums. Build workspaces, npm caches, tarballs, probes, and gzip outputs are intentionally not packaged.
