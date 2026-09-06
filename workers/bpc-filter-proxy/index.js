const UPSTREAM_URL =
  "https://gitflic.ru/project/magnolia1234/bypass-paywalls-clean-filters/blob/raw?file=bpc-paywall-filter.txt&branch=master";

const OBJECT_KEY = "bpc-paywall-filter.txt";

// Served to any client that still hits the worker URL directly. Long enough
// that legacy installs cost a handful of invocations a day instead of thousands.
const LEGACY_CACHE_TTL = 6 * 60 * 60;

const UPSTREAM_HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
  Accept: "text/plain,*/*;q=0.9",
  "Accept-Language": "en-US,en;q=0.9",
  Referer: "https://gitflic.ru/",
  "Sec-Fetch-Dest": "document",
  "Sec-Fetch-Mode": "navigate",
  "Sec-Fetch-Site": "same-origin",
};

function looksLikeFilterList(body) {
  if (body.length < 1000) return false;
  const head = body.slice(0, 512).toLowerCase();
  if (head.startsWith("<!doctype") || head.startsWith("<html")) return false;
  if (
    body.includes("ddos-guard") ||
    body.includes("DDoS protection") ||
    body.includes("checking your browser")
  ) {
    return false;
  }
  return true;
}

async function fetchUpstream() {
  const upstream = await fetch(UPSTREAM_URL, {
    headers: UPSTREAM_HEADERS,
    redirect: "follow",
  });
  if (!upstream.ok) {
    throw new Error(`upstream status ${upstream.status}`);
  }
  const body = await upstream.text();
  if (!looksLikeFilterList(body)) {
    throw new Error("upstream returned invalid content");
  }
  return body;
}

async function sha256Hex(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

// Pulls the list from gitflic and writes it to R2 only when the content changed,
// so the object's ETag and Last-Modified stay stable between real updates and
// clients keep getting 304s.
async function refresh(env) {
  const body = await fetchUpstream();
  const digest = await sha256Hex(body);
  const existing = await env.BPC_BUCKET.head(OBJECT_KEY);
  if (existing?.customMetadata?.sha256 === digest) {
    return { changed: false, bytes: body.length };
  }
  await env.BPC_BUCKET.put(OBJECT_KEY, body, {
    httpMetadata: {
      contentType: "text/plain; charset=utf-8",
      cacheControl: `public, max-age=${LEGACY_CACHE_TTL}`,
    },
    customMetadata: { sha256: digest, fetchedAt: new Date().toISOString() },
  });
  return { changed: true, bytes: body.length };
}

export default {
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(
      refresh(env).then(
        (r) => console.log(`bpc refresh: changed=${r.changed} bytes=${r.bytes}`),
        (err) => console.error(`bpc refresh failed: ${err.message}`)
      )
    );
  },

  // Legacy path for installs that still point at the worker URL. Serves the R2
  // copy through the edge cache; never talks to gitflic on the request path.
  async fetch(request, env, ctx) {
    const cache = caches.default;
    const cacheKey = new Request(new URL(request.url).toString(), { method: "GET" });
    const cached = await cache.match(cacheKey);
    if (cached) return cached;

    const object = await env.BPC_BUCKET.get(OBJECT_KEY);
    if (!object) {
      return new Response("filter list not yet mirrored", { status: 503 });
    }
    const response = new Response(object.body, {
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": `public, max-age=${LEGACY_CACHE_TTL}`,
        ETag: object.httpEtag,
        "Last-Modified": object.uploaded.toUTCString(),
        "Access-Control-Allow-Origin": "*",
      },
    });
    ctx.waitUntil(cache.put(cacheKey, response.clone()));
    return response;
  },
};
