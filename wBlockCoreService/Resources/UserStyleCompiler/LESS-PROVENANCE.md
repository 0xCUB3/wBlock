# Less 4.9.0 provenance

`less.min.js` is byte-for-byte `package/dist/less.min.js` from the official npm package `less@4.9.0`.

- Registry tarball: `https://registry.npmjs.org/less/-/less-4.9.0.tgz`
- npm integrity: `sha512-umRhrCH7fCi8Uj2RcwKjJdvUORTjeWqkdKx0LbcZvjIwsAVsnIAGcxHaqowPeBFBjQuWOeC/bve0AlpFzF/+SQ==`
- Runtime SHA-256: `59c1ed0a6f51215a702b3b4095bf9f296c67d5c1610f82b95d82991c3c3f3082`
- License: Apache-2.0, retained as `LICENSE`

Reverify from a temporary directory:

```sh
npm pack less@4.9.0 --ignore-scripts
tar -xzf less-4.9.0.tgz
shasum -a 256 package/dist/less.min.js
cmp package/dist/less.min.js less.min.js
```

The app invokes this fixed browser runtime in the same disposable WebKit Worker host as the other backends. Less imports and inline JavaScript are disabled by the adapter.
