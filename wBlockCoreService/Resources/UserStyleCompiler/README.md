# Offline UserStyle compiler runtimes

wBlock runs each selected compiler in a fresh Blob Worker owned by a disposable, nonpersistent `WKWebView`. The host passes JSON-compatible data only and exposes no native message bridge. Network, nested workers, imports, and browser storage are disabled before the fixed bundled runtime loads. A page-side watchdog terminates the Worker after 10 seconds, including when compiler JavaScript is stuck synchronously. Source is limited to 2 MiB and generated CSS to 10 MiB.

The Worker runs in WebKit's WebContent process, which keeps compiler failure separate from ordinary app work. WebKit does not expose a per-Worker memory cap, so the source/output limits and fixed offline subsets remain necessary. Raw UserCSS is authoritative for persistence, cloud sync, and backups; compiled output is a validated transient sidecar.

| Backend | Exact revision | Runtime | Size | SHA-256 |
| --- | --- | --- | ---: | --- |
| Less | 4.9.1 | `less.min.js` | 158,911 | `4283b275378371c38b8dc1cc1d2d683947b441aa875e1d9716e922e2cff34977` |
| Sass / SCSS | 1.104.0 | `sass/wblock-sass-1.104.0.min.js` | 3,279,821 | `ef5db10a0eb58fd8fbb2027f476d27197118c6280e2669996c5f43df7b6f305f` |
| PostCSS + nested | 8.5.28 + 8.0.1 | `postcss-nested/wblock-postcss-nested.js` | 125,732 | `42d84b46d040387ef527b87b4b1a86d5fbbafb90cb0de63cbdd2a3d668c1d0f9` |
| Stylus | 0.64.0, bounded offline | `stylus/stylus-jsc.js` | 428,606 | `b512616bb0de26ba1e92e45e03cb1144cb1facbad23304685c2494e7f8ef127b` |

The Sass bridge supports SCSS and indented Sass, variables, nesting, and mixins. Sass `@import`, `@use`, and `@forward` are rejected. Stylus embeds its pinned standard library and supports typed globals, nesting, mixins, and ordinary CSS URLs; imports, plugins, file-backed helpers, and source maps are rejected. PostCSS is deliberately the pinned `postcss-nested` plugin only. Less imports and inline JavaScript are disabled, while ordinary CSS imports remain in generated CSS.

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
