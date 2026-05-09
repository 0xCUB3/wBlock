/*
 * Browser-registered YouTube document_start runtime.
 * Keep this intentionally small and Safari-safe: only remove ad metadata from
 * YouTube player JSON responses. Avoid request spoofing, DOM-bypass, timer, and
 * player/client mutation scriptlets because they can stall SABR playback.
 */
'use strict';

(() => {
  const host = String(location.hostname || '').toLowerCase();
  const youtubeHosts = new Set([
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
    'tv.youtube.com',
    'youtube-nocookie.com',
    'www.youtube-nocookie.com',
    'youtubekids.com',
    'www.youtubekids.com'
  ]);
  if (!youtubeHosts.has(host)) return;
  if (globalThis.__wBlockYouTubeDocumentStartRuntime) return;
  globalThis.__wBlockYouTubeDocumentStartRuntime = true;

  const diagnostics = (() => {
    const startedAt = typeof performance !== 'undefined' && performance.now ? performance.now() : Date.now();
    const recent = [];
    const debug = (() => {
      try {
        return new URL(location.href).searchParams.get('wblockytdebug') === '1' || localStorage.getItem('wblockYouTubeDiagnostics') === '1';
      } catch (_) {
        return false;
      }
    })();
    const now = () => Math.round((typeof performance !== 'undefined' && performance.now ? performance.now() : Date.now()) - startedAt);
    const remember = entry => {
      recent.push(entry);
      if (recent.length > 60) recent.shift();
      return entry;
    };
    const log = (level, event, data = {}) => {
      const entry = remember({ t: now(), event, ...data });
      if (debug) {
        try { (console[level] || console.info).call(console, `[wBlock:yt] ${event}`, entry); } catch (_) {}
      }
      return entry;
    };
    return {
      debug,
      recent,
      log,
      enable() { try { localStorage.setItem('wblockYouTubeDiagnostics', '1'); } catch (_) {} log('info', 'diagnostics-enabled', { reloadRequired: true }); },
      disable() { try { localStorage.removeItem('wblockYouTubeDiagnostics'); } catch (_) {} log('info', 'diagnostics-disabled', { reloadRequired: true }); }
    };
  })();
  globalThis.__wBlockYouTubeDiagnostics = diagnostics;
  diagnostics.log('info', 'runtime-start', { href: location.href, readyState: document.readyState });

  const urlFrom = value => {
    try {
      if (typeof value === 'string') return value;
      if (value && typeof value.url === 'string') return value.url;
      return String(value || '');
    } catch (_) {
      return '';
    }
  };

  const shouldPruneURL = rawURL => {
    let parsed;
    try { parsed = new URL(rawURL, location.href); } catch (_) { return false; }
    const hostname = parsed.hostname.toLowerCase();
    if (!youtubeHosts.has(hostname)) return false;
    const path = parsed.pathname;
    return path === '/youtubei/v1/player' || path === '/youtubei/v1/playlist' || /\/player(?:$|[?#])/.test(path);
  };

  const pruneAdMetadata = value => {
    let changed = false;
    const visit = node => {
      if (!node || typeof node !== 'object') return;
      if (Array.isArray(node)) {
        for (const item of node) visit(item);
        return;
      }
      for (const key of ['adPlacements', 'adSlots']) {
        if (Object.prototype.hasOwnProperty.call(node, key)) {
          delete node[key];
          changed = true;
        }
      }
      for (const item of Object.values(node)) visit(item);
    };
    visit(value);
    return changed;
  };

  const prunedJSONText = text => {
    if (typeof text !== 'string' || !text.includes('ad')) return null;
    try {
      const json = JSON.parse(text);
      if (!pruneAdMetadata(json)) return null;
      return JSON.stringify(json);
    } catch (_) {
      return null;
    }
  };

  const installFetchPruner = () => {
    if (typeof fetch !== 'function' || fetch.__wBlockYouTubeSafePruner) return;
    const nativeFetch = fetch;
    const wrappedFetch = new Proxy(nativeFetch, { apply(target, thisArg, args) {
      const rawURL = urlFrom(args[0]);
      const shouldPrune = shouldPruneURL(rawURL);
      const result = Reflect.apply(target, thisArg, args);
      if (!shouldPrune || !result || typeof result.then !== 'function') return result;
      return result.then(async response => {
        if (!response || response.ok === false) return response;
        try {
          const text = await response.clone().text();
          const pruned = prunedJSONText(text);
          if (pruned === null) return response;
          const headers = new Headers(response.headers);
          headers.delete('content-length');
          diagnostics.log('info', 'player-response-pruned', { transport: 'fetch', url: rawURL.slice(0, 160) });
          const responseAfter = new Response(pruned, { status: response.status, statusText: response.statusText, headers });
          try {
            Object.defineProperties(responseAfter, {
              url: { value: response.url },
              type: { value: response.type },
              redirected: { value: response.redirected }
            });
          } catch (_) {}
          return responseAfter;
        } catch (error) {
          diagnostics.log('warn', 'fetch-prune-failed', { error: String(error && error.message || error) });
          return response;
        }
      });
    }});
    try { Object.defineProperty(wrappedFetch, '__wBlockYouTubeSafePruner', { value: true }); } catch (_) {}
    fetch = wrappedFetch;
  };

  const installXHRPruner = () => {
    const proto = typeof XMLHttpRequest !== 'undefined' && XMLHttpRequest.prototype;
    if (!proto || proto.__wBlockYouTubeSafePruner) return;
    const nativeOpen = proto.open;
    proto.open = function(method, url, ...rest) {
      try {
        this.__wBlockYouTubePruneResponse = shouldPruneURL(urlFrom(url));
      } catch (_) {
        this.__wBlockYouTubePruneResponse = false;
      }
      return nativeOpen.call(this, method, url, ...rest);
    };

    const responseTextDescriptor = Object.getOwnPropertyDescriptor(proto, 'responseText');
    if (responseTextDescriptor && typeof responseTextDescriptor.get === 'function' && responseTextDescriptor.configurable !== false) {
      Object.defineProperty(proto, 'responseText', {
        configurable: true,
        enumerable: responseTextDescriptor.enumerable,
        get() {
          const text = responseTextDescriptor.get.call(this);
          if (!this.__wBlockYouTubePruneResponse) return text;
          const pruned = prunedJSONText(text);
          if (pruned === null) return text;
          diagnostics.log('info', 'player-response-pruned', { transport: 'xhr' });
          return pruned;
        }
      });
    }

    const responseDescriptor = Object.getOwnPropertyDescriptor(proto, 'response');
    if (responseDescriptor && typeof responseDescriptor.get === 'function' && responseDescriptor.configurable !== false) {
      Object.defineProperty(proto, 'response', {
        configurable: true,
        enumerable: responseDescriptor.enumerable,
        get() {
          const response = responseDescriptor.get.call(this);
          if (!this.__wBlockYouTubePruneResponse || !response) return response;
          if (typeof response === 'string') return prunedJSONText(response) || response;
          if (typeof response === 'object') {
            try {
              if (pruneAdMetadata(response)) diagnostics.log('info', 'player-response-pruned', { transport: 'xhr', type: 'json' });
            } catch (_) {}
          }
          return response;
        }
      });
    }
    try { Object.defineProperty(proto, '__wBlockYouTubeSafePruner', { value: true }); } catch (_) {}
  };

  try { installFetchPruner(); installXHRPruner(); } catch (error) {
    diagnostics.log('warn', 'install-failed', { error: String(error && error.message || error) });
  }
})();
