# Offline UserStyle compiler runtimes

wBlock evaluates each selected runtime in a fresh JavaScriptCore context with no DOM, host bridge, network, filesystem, process, timers, or inline JavaScript adapter. Source is limited to 2 MiB and generated CSS to 10 MiB. Raw UserCSS remains the persisted/cloud/backup authority; compiled output is a validated transient sidecar. Xcode may flatten resource folders in a built framework; runtime lookup therefore tries `UserStyleCompiler/` first and the framework root as a fallback.

| Backend | Exact revision | Runtime | Size | SHA-256 |
| --- | --- | ---: | ---: | --- |
| Less | 4.9.0 | `less.min.js` | 158,891 | `59c1ed0a6f51215a702b3b4095bf9f296c67d5c1610f82b95d82991c3c3f3082` |
| Sass / SCSS | 1.102.0 | `wblock-sass-1.102.0.min.js` | 3,277,321 | `a575120ee471de3fc9f8ddad036f4296de483ec312daf960bdda8f289582d6c8` |
| PostCSS + nested | 8.5.26 + 8.0.1 | `wblock-postcss-nested.js` | 125,669 | `68709da6d84de1838dfde79a68b0451f242eb4f2fa60a0b2f38fcb0a79f1d60e` |
| Stylus | 0.64.0, bounded offline | `stylus-jsc.js` | 420,979 | `8e6ef62152979cac41e145b3056d1a3a1c7ea6b2359bcf1ef332655b2b23af4b` |

The Sass bridge supports SCSS and indented Sass, variables, nesting, and mixins. Sass `@import`, `@use`, and `@forward` are rejected. Stylus supports the offline core language, globals, nesting, and mixins; imports, plugins, file-backed helpers, and source maps are rejected. PostCSS is deliberately only the pinned `postcss-nested` plugin: arbitrary plugins, preset-env, and autoprefixer are not supported. Less keeps imports disabled while ordinary CSS imports remain in output.

Supported metadata preprocessors are empty/default, `uso`, `less`, `sass`, `scss`, `stylus`, and `postcss`. A complete UserCSS metadata block is required; file extension only identifies a candidate and never selects a compiler. Recognized source paths include `.css`, `.user.css`, `.less`, `.sass`, `.scss`, `.styl`, and `.pcss`, including matching query values. JavaScriptCore does not provide a hard execution timeout; safety relies on the fixed offline runtimes, fresh contexts, input/output limits, and disabled host capabilities.

Rebuild provenance and complete notices are retained in the `sass/`, `postcss-nested/`, and `stylus/` directories. Shipping contains minified/runtime JavaScript only; no gzip files, npm caches, tarballs, probes, node_modules, or build outputs are packaged. Sass provenance is in `sass/provenance.json`; PostCSS provenance and security records are in `postcss-nested/DEPENDENCIES-postcss-nested.tsv`, `SECURITY-SCAN.txt`, and `SHA256SUMS-postcss-nested`; Stylus provenance is in `stylus/DEPENDENCIES-stylus.tsv`, `THIRD-PARTY-NOTICES.md`, and `SHA256SUMS-stylus`.
