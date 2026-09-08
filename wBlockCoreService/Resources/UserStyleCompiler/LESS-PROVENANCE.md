# Less 4.9.1 provenance

`less.min.js` is byte-for-byte `package/dist/less.min.js` from the official npm package `less@4.9.1`.

- Registry tarball: `https://registry.npmjs.org/less/-/less-4.9.1.tgz`
- npm integrity: `sha512-orp15PfJvvNDIqJdVWzMI9Sjpjp3VTiw3sfvbB+67LlISTEn8uVT2EdYSuyl02BLvaftv6sdk9Umnxmm5rckmg==`
- Runtime SHA-256: `4283b275378371c38b8dc1cc1d2d683947b441aa875e1d9716e922e2cff34977`
- License: Apache-2.0, retained as `LICENSE`

Reverify from a temporary directory:

```sh
npm pack less@4.9.1 --ignore-scripts
tar -xzf less-4.9.1.tgz
shasum -a 256 package/dist/less.min.js
cmp package/dist/less.min.js less.min.js
```

The app invokes this fixed browser runtime in the same disposable WebKit Worker host as the other backends. Less imports and inline JavaScript are disabled by the adapter.
