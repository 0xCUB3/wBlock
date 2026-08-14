# Offline Stylus artifact

This directory ships `stylus-jsc.js`, a 420,979-byte browser bundle containing Stylus 0.64.0 and 34 reachable pinned dependencies listed in `DEPENDENCIES-stylus.tsv`.

The bundle installs `StylusCompile`. It accepts `{source, variables}` and returns `{css}` or `{error:{code,message}}`. Imports and `@require` return `imports_rejected`. File-backed built-ins (`url`, `json`, `image-size`, and `embedurl`) return `unsupported_builtin`. Source maps are disabled. Filesystem and glob modules are throwing stubs; no network, process, or host integration is required.

The retained generation record used exact npm versions, the official `stylus-0.64.0.tgz`, offline reductions, and Browserify 17.0.1. Build workspaces and package archives are not shipped in the app. `DEPENDENCIES-stylus.tsv` records versions, npm integrities, and installed sizes. `THIRD-PARTY-NOTICES.md` and `licenses/` contain the notices for all reachable code.

The current integration test runs the artifact through the app's WebKit Worker host and covers variables, nesting, mixins, syntax errors, import rejection, unsupported built-ins, timeout recovery, and denied Worker capabilities:

```sh
scripts/test_issue_511_preprocessors.sh
```

Verify every file shipped from this directory with `shasum -a 256 -c SHA256SUMS-stylus`.

This is a bounded offline Stylus subset, not full Stylus compatibility. File imports, plugins, file-backed helpers, source maps, and host integration remain intentionally unsupported.
