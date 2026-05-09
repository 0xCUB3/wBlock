/*
 * Static YouTube document_start runtime.
 *
 * Safari needs these hooks before YouTube's player bootstrap runs. Keep this
 * packaged and tiny instead of feeding dynamic filter-list scriptlets through
 * the generic runtime.
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

  const AD_METADATA_KEYS = ['adPlacements', 'adSlots', 'playerAds'];
  const INITIAL_RESPONSE_PROPS = ['ytInitialPlayerResponse', 'playerResponse'];

  const urlFrom = value => {
    try {
      if (typeof value === 'string') return value;
      if (value && typeof value.url === 'string') return value.url;
      return String(value || '');
    } catch (_) {
      return '';
    }
  };

  const youtubeResponseKind = rawURL => {
    let parsed;
    try { parsed = new URL(rawURL, location.href); } catch (_) { return ''; }
    const hostname = parsed.hostname.toLowerCase();
    if (!youtubeHosts.has(hostname)) return '';
    const path = parsed.pathname;
    if (path === '/youtubei/v1/player' || /\/player(?:$|[?#])/.test(path)) return 'player';
    if (path === '/youtubei/v1/playlist' || path === '/playlist') return 'playlist';
    if (path === '/youtubei/v1/get_watch' || path === '/get_video_info') return 'get_watch';
    if (path === '/watch') return 'watch';
    return '';
  };

  const shouldPruneFetchURL = rawURL => {
    const kind = youtubeResponseKind(rawURL);
    return kind === 'player' || kind === 'playlist' || kind === 'get_watch';
  };
  const shouldPruneXHRURL = rawURL => youtubeResponseKind(rawURL) !== '';

  const pruneAdMetadata = value => {
    let changed = false;
    const visited = typeof WeakSet === 'function' ? new WeakSet() : null;
    const visit = node => {
      if (!node || typeof node !== 'object') return;
      if (visited) {
        if (visited.has(node)) return;
        visited.add(node);
      }
      if (Array.isArray(node)) {
        for (const item of node) visit(item);
        return;
      }
      for (const key of AD_METADATA_KEYS) {
        if (Object.prototype.hasOwnProperty.call(node, key)) {
          delete node[key];
          changed = true;
        }
      }
      try {
        if (node.playerConfig && node.playerConfig.audioConfig && node.playerConfig.audioConfig.muteOnStart === true) {
          node.playerConfig.audioConfig.muteOnStart = false;
          changed = true;
        }
        if (Object.prototype.hasOwnProperty.call(node, 'youThereRenderer')) {
          delete node.youThereRenderer;
          changed = true;
        }
      } catch (_) {}
      for (const item of Object.values(node)) visit(item);
    };
    visit(value);
    return changed;
  };

  const hasAdMetadataText = text => {
    if (typeof text !== 'string') return false;
    return text.includes('"adPlacements"') || text.includes('"adSlots"') || text.includes('"playerAds"') ||
      text.includes('"muteOnStart":true') || text.includes('"youThereRenderer"');
  };

  const prunedJSONText = text => {
    if (!hasAdMetadataText(text)) return null;
    try {
      const json = JSON.parse(text);
      pruneAdMetadata(json);
      return JSON.stringify(json);
    } catch (_) {
      return null;
    }
  };

  const rewrittenAdMetadataText = text => {
    if (!hasAdMetadataText(text)) return null;
    return text
      .replaceAll('"adPlacements"', '"no_ads"')
      .replaceAll('"adSlots"', '"no_ads"')
      .replaceAll('"playerAds"', '"no_ads"');
  };

  const sanitizedResponseText = text => {
    const pruned = prunedJSONText(text);
    return pruned || rewrittenAdMetadataText(text);
  };

  const sanitizeObject = value => {
    try { pruneAdMetadata(value); } catch (_) {}
    return value;
  };

  const installInitialResponsePruner = () => {
    for (const prop of INITIAL_RESPONSE_PROPS) {
      try {
        const descriptor = Object.getOwnPropertyDescriptor(globalThis, prop);
        if (descriptor && descriptor.configurable === false) {
          try { sanitizeObject(globalThis[prop]); } catch (_) {}
          continue;
        }

        let current;
        if (descriptor && Object.prototype.hasOwnProperty.call(descriptor, 'value')) {
          current = sanitizeObject(descriptor.value);
        } else if (descriptor && typeof descriptor.get === 'function') {
          try { current = sanitizeObject(descriptor.get.call(globalThis)); } catch (_) {}
        } else if (Object.prototype.hasOwnProperty.call(globalThis, prop)) {
          current = sanitizeObject(globalThis[prop]);
        }

        Object.defineProperty(globalThis, prop, {
          configurable: true,
          enumerable: descriptor ? descriptor.enumerable : true,
          get() {
            return current;
          },
          set(value) {
            current = sanitizeObject(value);
          }
        });
      } catch (_) {}
    }
  };

  const installJSONParsePruner = () => {
    if (!JSON || typeof JSON.parse !== 'function' || JSON.parse.__wBlockYouTubeSafePruner) return;
    const nativeParse = JSON.parse;
    const wrappedParse = new Proxy(nativeParse, { apply(target, thisArg, args) {
      const result = Reflect.apply(target, thisArg, args);
      if (hasAdMetadataText(args[0])) {
        try { sanitizeObject(result); } catch (_) {}
      }
      return result;
    }});
    try { Object.defineProperty(wrappedParse, '__wBlockYouTubeSafePruner', { value: true }); } catch (_) {}
    JSON.parse = wrappedParse;
  };

  const installFetchPruner = () => {
    if (typeof fetch !== 'function' || fetch.__wBlockYouTubeSafePruner) return;
    const nativeFetch = fetch;
    const wrappedFetch = new Proxy(nativeFetch, { apply(target, thisArg, args) {
      const rawURL = urlFrom(args[0]);
      const result = Reflect.apply(target, thisArg, args);
      if (!shouldPruneFetchURL(rawURL) || !result || typeof result.then !== 'function') return result;
      return result.then(async response => {
        if (!response || response.ok === false) return response;
        try {
          const text = await response.clone().text();
          const pruned = sanitizedResponseText(text);
          if (pruned === null) return response;
          const headers = new Headers(response.headers);
          headers.delete('content-length');
          const responseAfter = new Response(pruned, { status: response.status, statusText: response.statusText, headers });
          try {
            Object.defineProperties(responseAfter, {
              url: { value: response.url },
              type: { value: response.type },
              redirected: { value: response.redirected }
            });
          } catch (_) {}
          return responseAfter;
        } catch (_) {
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
        this.__wBlockYouTubePruneResponse = shouldPruneXHRURL(urlFrom(url));
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
          return sanitizedResponseText(text) || text;
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
          if (typeof response === 'string') return sanitizedResponseText(response) || response;
          if (typeof response === 'object') {
            try { pruneAdMetadata(response); } catch (_) {}
          }
          return response;
        }
      });
    }
    try { Object.defineProperty(proto, '__wBlockYouTubeSafePruner', { value: true }); } catch (_) {}
  };

  try {
    installInitialResponsePruner();
    installJSONParsePruner();
    installFetchPruner();
    installXHRPruner();
  } catch (_) {}
})();
