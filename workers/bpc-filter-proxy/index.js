const UPSTREAM_URL =
  "https://gitflic.ru/project/magnolia1234/bypass-paywalls-clean-filters/blob/raw?file=bpc-paywall-filter.txt&branch=master";

const CACHE_TTL = 6 * 60 * 60; // 6 hours

export default {
  async fetch(request) {
    const cacheUrl = new URL(request.url);
    const cacheKey = new Request(cacheUrl.toString(), request);
    const cache = caches.default;

    // Serve from cache if available
    let response = await cache.match(cacheKey);
    if (response) {
      return response;
    }

    // Fetch from gitflic with browser-like headers
    const upstream = await fetch(UPSTREAM_URL, {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
        Accept: "text/plain,*/*;q=0.9",
        "Accept-Language": "en-US,en;q=0.9",
        Host: "gitflic.ru",
        Referer: "https://gitflic.ru/",
        "Sec-Fetch-Dest": "document",
        "Sec-Fetch-Mode": "navigate",
        "Sec-Fetch-Site": "same-origin",
      },
      redirect: "follow",
    });

    if (!upstream.ok) {
      return new Response("upstream fetch failed", { status: 502 });
    }

    const body = await upstream.text();

    // Validate: must look like a filter list, not a DDoS page
    if (
      body.length < 1000 ||
      body.includes("ddos-guard") ||
      body.includes("DDoS protection") ||
      body.includes("checking your browser") ||
      (body.startsWith("<!doctype") || body.startsWith("<!DOCTYPE"))
    ) {
      return new Response("upstream returned invalid content", { status: 502 });
    }

    response = new Response(body, {
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": `public, max-age=${CACHE_TTL}`,
        "Access-Control-Allow-Origin": "*",
      },
    });

    // Store in Cloudflare edge cache
    const cacheResponse = response.clone();
    await cache.put(cacheKey, cacheResponse);

    return response;
  },
};
