# Dark Reader vendored API

- License: MIT (see `DarkReader-LICENSE.txt`).
- Upstream: https://github.com/darkreader/darkreader
- Package: `darkreader@4.9.128`
- Official API source: the unminified `darkreader.js` artifact from npm, SHA-256 `ce0b18e9a89caf7145292e7d7d2592b5bac664c49567fbf2d59c57a2bc7014e5`.
- Reproducible transform: pinned `terser@5.46.0` with `--compress --mangle --comments '/^!|@license|Dark Reader v/'`; intermediate SHA-256 `629f0a0077c32cdad9b934a06100154c1a47aab00cfef0a88df6214cc4e58c47`.
- wBlock patches privately shim Chrome runtime access and exclude `style[data-wblock-userstyle]`; final SHA-256 `433921d71add2d8119025c3727fc8ff5357e54ac40dd068ad73ec45619f09206`.
- The Dark Reader engine is included. The full extension UI, configuration, and site-fix data are omitted.

This integration is beta and uses the API engine's generic dynamic theme behavior.
