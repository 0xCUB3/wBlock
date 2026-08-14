# wBlock offline Sass artifact

This directory ships the pinned Sass/SCSS runtime `wblock-sass-1.102.0.min.js`. It embeds Dart Sass 1.102.0 and Immutable 5.1.5. The bridge accepts SCSS or indented Sass, prepends UserCSS variables, rejects `@import`, `@use`, and `@forward`, and returns expanded CSS. It requires no filesystem, network, DOM, Node, `process`, `require`, or native bridge.

`provenance.json` records source and minified hashes, byte sizes, Terser 5.50.0 integrity, and exact minification flags. The original generation workspace is not shipped in the app. Its recorded process was:

```sh
npm ci --ignore-scripts
terser wblock-sass-1.102.0.js --compress --mangle --comments false \
  --output wblock-sass-1.102.0.min.js
```

The repository integration test executes the shipped runtime through the same WebKit Worker host used by the app and covers SCSS nesting and variables, indented Sass, syntax locations, import rejection, timeout recovery, and denied host capabilities:

```sh
scripts/test_issue_511_preprocessors.sh
```

Verify every file shipped from this directory with `shasum -a 256 -c SHA256SUMS-sass`. `LICENSE.sass` and `LICENSE.immutable` are complete upstream notices preserved unchanged.
