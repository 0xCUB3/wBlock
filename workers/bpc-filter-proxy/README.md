# bpc-filter-proxy

Mirrors the Bypass Paywalls Clean filter list from gitflic into R2 so the app
reads a static object instead of invoking a worker on every update check.

How it fits together:

- A cron trigger runs four times a day, fetches the list from gitflic with
  browser-like headers, rejects DDoS-guard pages, and writes the object to the
  `bpc-filter` bucket only when the bytes changed. Unchanged content keeps the
  same ETag, so clients get 304s.
- The app's default URL is the bucket's public `r2.dev` URL.
- The worker's `fetch` handler is a legacy path for installs that still point
  at the `workers.dev` URL. It serves the R2 copy through the edge cache and
  never fetches gitflic on the request path.

Deploy:

```sh
npx wrangler r2 bucket create bpc-filter
npx wrangler deploy
# one-off to populate the bucket without waiting for the cron
npx wrangler dev --test-scheduled   # then: curl 'http://localhost:8787/__scheduled'
```

Enable public access for the bucket (`r2 bucket dev-url enable bpc-filter`) and
put the resulting `https://pub-….r2.dev/bpc-paywall-filter.txt` URL in
`FilterListLoader.swift` and the `filterURLMigrations` table.
