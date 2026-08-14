# Offline PostCSS nested artifact

This directory ships a fixed browser bundle containing exactly `postcss@8.5.26`, `postcss-nested@8.0.1`, and their pinned reachable dependencies. It is not an arbitrary PostCSS plugin runner.

The IIFE defines synchronous `wblockPostcssNested`. Pass a JSON string containing `{ "source": string, "variables": object }`; it returns a JSON string containing either `{ "css": string }` or `{ "error": { "name", "message", optional "line", "column" } }`. The app passes no arbitrary plugin or host object. PostCSS variables are not UserCSS variable interpolation.

The retained generation record used esbuild 0.25.9 with browser conditions, ES2020, no source map, and minification. `DEPENDENCIES-postcss-nested.tsv` records exact versions and npm integrities. `LICENSES/` contains notices for every shipped dependency, and `SECURITY-SCAN.txt` records the generation-time static checks. Build workspaces, lockfiles, caches, and gzip output are not packaged.

The current integration test executes the shipped artifact through the app's WebKit Worker host and covers nested and ordinary CSS, `@-moz-document`, syntax locations, timeout recovery, and denied Worker capabilities:

```sh
scripts/test_issue_511_preprocessors.sh
```

Verify every file shipped from this directory with `shasum -a 256 -c SHA256SUMS-postcss-nested`.

Direct package integrities:

- postcss 8.5.26: `sha512-u82N74LFzG8ca+dD8puPnplTXoGH4fTPpVGuIbt36G3qvNlkvfD0lEAZSxaly3KX8TS/L1A1gsCEmvKmBcVbkQ==`
- postcss-nested 8.0.1: `sha512-PvSIwDVh1NTw939iu4FBK+oeZfSm0cbErFAjXCTPiStammzobBNE2SiQNezy8Xp+Oud2uLXaLpTauv3UdxWjbQ==`
