# Offline Stylus JSC artifact

Status: shipping candidate. The bundle is **420,979 bytes** and has **35 pinned code dependencies** (Stylus plus 34 reachable npm packages; see `DEPENDENCIES.tsv`). SHA-256 is in `SHA256SUMS`.

`stylus-jsc.js` installs synchronous global `StylusCompile`. It accepts `{source, variables}` and returns `{css}` or `{error:{code,message}}`. Imports and `@require` return `imports_rejected`. Filesystem-backed built-ins (`url`, `json`, `image-size`, `embedurl`) return `unsupported_builtin` before Stylus runs. Source maps are disabled. The filesystem and glob modules are throwing stubs; no network, crypto, timers, vm, source-map, process, or host API shim is reachable.

## Rebuild

From this directory, with the pinned lockfile and npm cache/registry available:

```sh
npm ci --ignore-scripts
./build.sh
```

`package.json` uses exact versions; `package-lock.json` records the resolved graph and integrity hashes. The build extracts the retained official `stylus-0.64.0.tgz`, applies the offline reductions, and runs the pinned Browserify 17.0.1. It does not modify the repository.

## Evidence

```sh
xcrun swiftc -framework JavaScriptCore swift_jsc_test.swift -o swift_jsc_test
./swift_jsc_test stylus-jsc.js
```

The Swift JavaScriptCore probe covers variables, nesting, mixins, syntax errors, `@import`/`@require` rejection, explicit unsupported built-ins, and absence of `fs`, `process`, `require`, `module`, DOM, and network globals. The recorded target run ends `PASS direct Swift JavaScriptCore`.

Static graph is `reachable-files.txt`. The decisive scan is:

```sh
grep -E '/node_modules/(crypto|process|timers|vm|source-map|http|https|net|tls|dns|fs|glob|sax)/' reachable-files.txt
```

It returns no matches. `THIRD-PARTY-NOTICES.md` and `licenses/` contain complete license texts for every dependency whose code is reachable, including Browserify's empty-module file and the Stylus MIT text. `DEPENDENCIES.tsv` records exact versions, npm integrities, and installed sizes.

## Remaining risk

This is a bounded offline Stylus surface, not full Stylus compatibility. File imports, plugins, file-backed helpers, source maps, and host integration are intentionally unsupported. The bundle must be evaluated in a fresh `JSContext` with no injected native globals; the probe demonstrates the artifact itself does not create those globals.
