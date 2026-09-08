# Offline Stylus artifact

This directory ships `stylus-jsc.js`, a 428,606-byte browser bundle containing Stylus 0.64.0 and 34 reachable pinned dependencies listed in `DEPENDENCIES-stylus.tsv`.

The bundle installs `StylusCompile`. It accepts `{source, variables}` and returns `{css}` or `{error:{code,message}}`. Imports and `@require` are rejected, including inline imports. File-backed built-ins (`json`, `image-size`, and `embedurl`) remain unavailable. Ordinary CSS `url()` values pass through without fetching anything. Source maps are disabled. Filesystem and glob modules are throwing stubs; no network, process, or host integration is required.

The entry module embeds the unmodified `lib/functions/index.styl` from the official `stylus-0.64.0.tgz`. Its SHA-256 is `04c7a9d8e6f7b62a60204038e34ee889879f5190e2beaa722c5994315592acba`. It is parsed into a fresh, unscoped import block in memory for each compilation, preserving lexical scope and user-source line numbers without reopening filesystem imports. Metadata variables are parsed as Stylus expressions so colors and numbers work with standard helpers.

The original generation record used exact npm versions, the official tarball, offline reductions, and Browserify 17.0.1. The built-in source and offline evaluator are embedded in the existing entry module; no dependency versions changed. `DEPENDENCIES-stylus.tsv` records versions, npm integrities, and installed sizes. `THIRD-PARTY-NOTICES.md` and `licenses/` contain the notices for all reachable code. Build workspaces and package archives are not shipped in the app.

The integration tests run the artifact through the app's WebKit Worker host and cover variables, nesting, standard color helpers, CSS filters and URLs, syntax errors, import rejection, timeout recovery, and denied Worker capabilities:

```sh
WBLOCK_CORE_PRODUCTS="/path/to/signed/Debug" scripts/test_issue_511_preprocessors.sh
```

Verify every file shipped from this directory with `shasum -a 256 -c SHA256SUMS-stylus`.

This remains a bounded offline Stylus subset. File imports, plugins, file-backed helpers, source maps, and host integration are intentionally unsupported.
