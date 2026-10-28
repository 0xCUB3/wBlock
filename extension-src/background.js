(function (browser) {
  'use strict';

  /**
   * @file Defines message interface.
   */
  /**
   * Represents a type of message.
   */
  var MessageType;
  (function (MessageType) {
    MessageType["InitContentScript"] = "InitContentScript";
  })(MessageType || (MessageType = {}));

  /**
   * @file Background script for the WebExtension.
   *
   * This script handles messages from other parts of the extension,
   * communicates with a native messaging host, and uses a cache mechanism
   * to serve responses quickly while updating them in the background.
   */
  /**
   * Global variable to track the engine timestamp.
   * This value is used to invalidate the cache when the underlying engine
   * is updated.
   */
  let engineTimestamp = 0;
  let configurationGeneration = 0;
  const CSS_SELECTORS_PER_INSERT = 1000;
  // Queues scriptlet calls in the page (MAIN world) for the scriptlets/*.js
  // files injected right after; each file runs and removes its own queue.
  // Injected functions and files are exempt from the page's CSP, unlike a
  // page script element. Runs as a function, so it must not close over anything.
  const queueScriptletCalls = calls => {
    const queue = globalThis.__wbeScriptletCalls || (globalThis.__wbeScriptletCalls = {});
    for (const [name, ...args] of calls) (queue[name] || (queue[name] = [])).push(args);
  };
  const runScriptlets = async (target, calls) => {
    await executeInFrame({ target, world: 'MAIN', injectImmediately: true, func: queueScriptletCalls, args: [calls] });
    const files = [...new Set(calls.map(([name]) => `scriptlets/${name}.js`))];
    await executeInFrame({ target, world: 'MAIN', injectImmediately: true, files });
  };
  // Safari's extension error summary shows only the first console argument, so
  // each line is one string with its details folded in.
  const formatLogValue = value => {
    if (value instanceof Error) return value.stack || value.message || String(value);
    if (typeof value === 'string') return value;
    try {
      return JSON.stringify(value);
    } catch (_error) {
      return String(value);
    }
  };
  const logError = (...args) => console.error(args.map(formatLogValue).join(' '));
  const PERMISSION_FAILURE_PATTERNS = ['permission', 'not allowed', 'denied', 'cannot access', 'not granted', 'not permitted', 'does not have access'];
  // Frames without website access, or already gone, are skipped quietly.
  const executeInFrame = async injection => {
    let results;
    try {
      results = await browser.scripting.executeScript(injection);
    } catch (error) {
      const message = String((error && error.message) || error || '').toLowerCase();
      if (!PERMISSION_FAILURE_PATTERNS.some(pattern => message.includes(pattern))) {
        logError('[wBlock] Failed to execute script in target', injection.target, 'error', error);
      }
      return;
    }
    if (results && results.length > 0 && results[0].error) {
      logError('[wBlock] Failed to execute script in target', injection.target, 'error', results[0].error);
    }
  };
  /**
   * Applies a per-page payload to one frame. Scriptlets are queued first so
   * they start as early as the frame allows.
   *
   * @param tabId ID of the tab to apply the configuration to.
   * @param frameId ID of the frame to apply the configuration to.
   * @param configuration Payload from the native handler.
   * @returns Promise that resolves when the injections have settled.
   */
  const applyConfiguration = (tabId, frameId, configuration) => {
    const target = { tabId, frameIds: [frameId] };
    const selectors = configuration.css || [];
    const procedural = configuration.procedural || [];
    const pending = [];
    const scriptlets = configuration.scriptlets || [];
    if (scriptlets.length > 0) {
      pending.push(runScriptlets(target, scriptlets));
    }
    // One rule per selector: a selector the engine rejects drops only itself.
    for (let i = 0; i < selectors.length; i += CSS_SELECTORS_PER_INSERT) {
      const css = selectors.slice(i, i + CSS_SELECTORS_PER_INSERT).map(selector => `${selector} { display: none !important; }`).join('\n');
      pending.push(browser.scripting.insertCSS({ target, origin: 'USER', css }));
    }
    if (procedural.length > 0) {
      pending.push((async () => {
        await executeInFrame({ target, files: ['procedural.js'], injectImmediately: true });
        await executeInFrame({ target, func: filters => wbeProcedural.apply(filters), args: [procedural] });
      })());
    }
    return Promise.all(pending);
  };
  /**
   * Cache to store the rules for a given URL. The key is a URL (string) and
   * the value is a Configuration. Caching content script configurations allows us
   * to respond to content script requests quickly while also updating the cache
   * in the background.
   */
  const cache = new Map();
  // Include frame configurations in the bound: their URLs can change on every
  // navigation even when the top-level URL stays the same.
  const CONFIG_CACHE_LIMIT = 128;
  /**
   * Persistent copy of the configuration cache (top frames only).
   *
   * The background page is not persistent, so the in-memory cache dies with
   * it (e.g. whenever Safari restarts). The first page load after a cold
   * start would then have to wait for the native host to spawn and load the
   * filter engine, which can take long enough that scriptlets miss their
   * injection window. To avoid that, top-frame configurations are mirrored
   * to browser.storage.local and restored on startup: stale entries are
   * served instantly and revalidated in the background, and the regular
   * engineTimestamp check drops them as soon as the native host reports a
   * newer engine.
   */
  const PERSISTED_CONFIG_CACHE_KEY = "wblockConfigCacheV2";
  const PERSISTED_CONFIG_CACHE_LIMIT = 40;
  const PERSIST_CONFIG_CACHE_DELAY_MS = 1000;
  let persistConfigCacheTimer = null;
  const persistConfigCache = () => {
    if (persistConfigCacheTimer !== null) {
      return;
    }
    const generation = configurationGeneration;
    persistConfigCacheTimer = setTimeout(async () => {
      persistConfigCacheTimer = null;
      if (generation !== configurationGeneration) return;
      try {
        const entries = [];
        for (const [key, configuration] of cache) {
          // Top-frame cache keys have no topUrl component.
          if (key.endsWith("#")) {
            entries.push([key, configuration]);
          }
        }
        await browser.storage.local.set({
          [PERSISTED_CONFIG_CACHE_KEY]: {
            engineTimestamp,
            entries: entries.slice(-PERSISTED_CONFIG_CACHE_LIMIT)
          }
        });
      } catch (error) {
        console.warn("[wBlock] Failed to persist config cache:", error);
      }
    }, PERSIST_CONFIG_CACHE_DELAY_MS);
  };
  const clearPersistedConfigCache = () => {
    if (persistConfigCacheTimer !== null) {
      clearTimeout(persistConfigCacheTimer);
      persistConfigCacheTimer = null;
    }
    return browser.storage.local.remove(PERSISTED_CONFIG_CACHE_KEY).catch(error => {
      console.warn("[wBlock] Failed to clear persisted config cache:", error);
    });
  };
  const configCacheHydration = (async () => {
    const generation = configurationGeneration;
    try {
      const stored = await browser.storage.local.get(PERSISTED_CONFIG_CACHE_KEY);
      if (generation !== configurationGeneration) return;
      const persisted = stored && stored[PERSISTED_CONFIG_CACHE_KEY];
      if (!persisted || typeof persisted.engineTimestamp !== "number" || !Array.isArray(persisted.entries)) {
        return;
      }
      // A native response that arrived before hydration finished is fresher
      // than anything on disk; in that case keep what we have.
      if (cache.size > 0 || engineTimestamp !== 0) {
        return;
      }
      engineTimestamp = persisted.engineTimestamp;
      for (const entry of persisted.entries.slice(-PERSISTED_CONFIG_CACHE_LIMIT)) {
        if (Array.isArray(entry) && typeof entry[0] === "string" && entry[1] && typeof entry[1] === "object") {
          cache.set(entry[0], entry[1]);
        }
      }
    } catch (error) {
      console.warn("[wBlock] Failed to hydrate config cache:", error);
    }
  })();
  // Native validation is authoritative; only broadcast session invalidation to tabs.
  const clearDocumentStartSessionCache = async () => {
    if (!browser.tabs || typeof browser.tabs.query !== "function") return;
    try {
      const tabs = await browser.tabs.query({});
      await Promise.all(tabs.map(tab => {
        if (!tab || typeof tab.id !== "number") return Promise.resolve();
        return browser.tabs.sendMessage(tab.id, {
          type: "wblock:clearDocumentStartSessionCache"
        }).catch(() => {});
      }));
    } catch {}
  };
  let nativeMessageQueue = Promise.resolve();
  const nativeMessageTimeoutMs = request => {
    const action = request && typeof request.action === "string" ? request.action : "";
    if (action === "syncZapperRules" || action === "getZapperRules") return 3500;
    if (action === "startFilterUpdate" || action === "getFilterUpdateStatus") return 10000;
    // A script pass can download several files; give it room before the
    // queue moves on. The native gate refuses overlapping runs anyway.
    if (action === "maybeUpdateUserScripts" || action === "maybeStageFilterUpdates") return 120000;
    // Cold native-host launches wait for app data to load; a short cutoff
    // fails the whole page init (#893).
    if (action === "getBlockingState") return 10000;
    return 30000;
  };
  const withNativeMessageTimeout = (promise, timeoutMs, action) => {
    let timer = null;
    return Promise.race([Promise.resolve(promise).finally(() => {
      if (timer !== null) clearTimeout(timer);
    }), new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(`Native message timed out: ${action || "unknown"}`)), timeoutMs);
    })]);
  };
  // Sequential frames of one page, and iframe-heavy apps, ask for the same
  // configuration many times a second. A cache entry the native host
  // confirmed within this window is served without another lookup or state
  // query. Any state-changing native call ends the window for every entry.
  // The same window covers per-frame state reads (site state, No Autoplay,
  // zapper rules, userscripts): identical reads share one native answer.
  const CONFIG_REVALIDATE_INTERVAL_MS = 5000;
  const configValidatedAt = new Map();
  const recentNativeReads = new Map();
  const isConfigFresh = key => Date.now() - (configValidatedAt.get(key) || 0) < CONFIG_REVALIDATE_INTERVAL_MS;
  // A lookup that was in flight when state changed must not start a window.
  let nativeStateEpoch = 0;
  const forgetRecentNativeState = () => {
    nativeStateEpoch += 1;
    configValidatedAt.clear();
    recentNativeReads.clear();
  };
  // Mutations end the window when sent and again when done, so reads that
  // overlapped them are not shared either.
  const forgetStaleStateAround = (action, response) => {
    if (!/^(set|resume|pause|clear|sync|delete)/.test(action)) return response;
    forgetRecentNativeState();
    Promise.resolve(response).finally(forgetRecentNativeState).catch(() => {});
    return response;
  };
  const RECENT_NATIVE_READ_LIMIT = 128;
  const readNativeRecently = (request, send = sendPriorityNativeMessage, shareable = () => true) => {
    const key = JSON.stringify(request);
    const hit = recentNativeReads.get(key);
    if (hit && Date.now() - hit.at < CONFIG_REVALIDATE_INTERVAL_MS) return hit.promise;
    const promise = send(request);
    const entry = { promise, at: Date.now() };
    recentNativeReads.delete(key);
    recentNativeReads.set(key, entry);
    if (recentNativeReads.size > RECENT_NATIVE_READ_LIMIT) {
      recentNativeReads.delete(recentNativeReads.keys().next().value);
    }
    const forget = () => {
      if (recentNativeReads.get(key) === entry) recentNativeReads.delete(key);
    };
    // Failures and malformed answers are never shared; the next frame asks again.
    promise.then(response => {
      if (!response || typeof response !== "object" || response.error
        || response.state === "error" || response.ok === false || !shareable(response)) forget();
    }, forget);
    return promise;
  };
  const sendQueuedNativeMessage = request => {
    const action = request && typeof request.action === "string" ? request.action : "";
    const response = nativeMessageQueue.then(() => withNativeMessageTimeout(browser.runtime.sendNativeMessage("application.id", request), nativeMessageTimeoutMs(request), action));
    nativeMessageQueue = response.catch(() => {});
    return forgetStaleStateAround(action, response);
  };
  const sendPriorityNativeMessage = request => {
    const action = request && typeof request.action === "string" ? request.action : "";
    return forgetStaleStateAround(action, withNativeMessageTimeout(
      browser.runtime.sendNativeMessage("application.id", request),
      nativeMessageTimeoutMs(request),
      action
    ));
  };
  let nativeStatePort = null;
  let nativeStateReconnectTimer = null;
  const connectNativeStatePort = () => {
    if (!(browser.runtime && typeof browser.runtime.connectNative === "function") || nativeStatePort) return;
    try {
      const port = browser.runtime.connectNative("application.id");
      nativeStatePort = port;
      if (port && port.onMessage) {
        port.onMessage.addListener(message => {
          const action = message && (
            message.action ||
            message.name ||
            message.messageName ||
            (message.userInfo && message.userInfo.action)
          );
          forgetRecentNativeState();
          if (action === "wblock:userscriptsChanged") {
            clearDocumentStartSessionCache();
          } else if (action === "wblock:zapperRulesChanged") {
            if (browser.tabs && typeof browser.tabs.query === "function") {
              browser.tabs.query({}).then(tabs => Promise.all(tabs.map(tab => {
                if (!tab || typeof tab.id !== "number") return Promise.resolve();
                return browser.tabs.sendMessage(tab.id, { type: "wblock:zapper:reloadRules" }).catch(() => {});
              }))).catch(() => {});
            }
          }
        });
      }
      if (port && port.onDisconnect) {
        port.onDisconnect.addListener(() => {
          if (nativeStatePort === port) nativeStatePort = null;
          if (nativeStateReconnectTimer !== null) clearTimeout(nativeStateReconnectTimer);
          nativeStateReconnectTimer = setTimeout(() => {
            nativeStateReconnectTimer = null;
            connectNativeStatePort();
          }, 1000);
        });
      }
    } catch (error) {
      console.warn("[wBlock] Failed to open native state port:", error);
    }
  };
  connectNativeStatePort();
  /**
   * Returns a cache key for the given URL and top-level URL.
   *
   * @param url - Page URL for which the rules are requested.
   * @param topUrl - Top-level page URL (to distinguish between frames)
   * @returns The cache key.
   */
  const cacheKey = (url, topUrl) => `${url}#${topUrl ?? ''}`;
  /**
   * Makes a native messaging request to obtain rules for the given message.
   * Also handles cache invalidation if the engine timestamp has changed.
   *
   * @param request - Original request from the content script.
   * @param url - Page URL for which the rules are requested.
   * @param topUrl - Top-level page URL (to distinguish between frames)
   * @returns The response message from the native host.
   */
  const requestConfiguration = async (request, url, topUrl) => {
    const generation = configurationGeneration;
    const epoch = nativeStateEpoch;
    // Prepare the request payload.
    request.payload = {
      url,
      topUrl
    };
    // Page rules must not wait behind maintenance downloads. Same-page
    // requests are still coalesced by requestConfigurationCoalesced.
    const response = await sendPriorityNativeMessage(request);
    const message = response;
    if (message && message.state === "error") {
      throw new Error(message.error || "Native configuration unavailable");
    }
    if (!message || !message.payload) {
      const error = message && message.error ? message.error : "Native configuration unavailable";
      throw new Error(error);
    }
    // Inert responses must not replace a usable configuration in the cache.
    const configuration = message.payload;
    const key = cacheKey(url, topUrl);
    if (configuration.disabled === true || configuration.paused === true) {
      // Pause and site state reach beyond this URL, and reads already in
      // flight must not restart freshness afterward.
      forgetRecentNativeState();
      return configuration;
    }
    if (generation !== configurationGeneration) return configuration;
    const fresh = epoch === nativeStateEpoch;
    // If the engine timestamp has been updated, clear the cache and update
    // the timestamp.
    if (configuration.engineTimestamp !== engineTimestamp) {
      cache.clear();
      forgetRecentNativeState();
      engineTimestamp = configuration.engineTimestamp;
    }
    if (fresh) configValidatedAt.set(key, Date.now());
    // Save the new message in the cache for the given URL. Delete the key
    // first so Map insertion order doubles as LRU order for the persisted
    // slice.
    cache.delete(key);
    cache.set(key, configuration);
    if (cache.size > CONFIG_CACHE_LIMIT) {
      const evicted = cache.keys().next().value;
      cache.delete(evicted);
      configValidatedAt.delete(evicted);
    }
    persistConfigCache();
    return configuration;
  };
  const pendingConfigurationRequests = new Map();
  const requestConfigurationCoalesced = (request, url, topUrl) => {
    const key = cacheKey(url, topUrl);
    const pending = pendingConfigurationRequests.get(key);
    if (pending) {
      return pending;
    }
    const requestPromise = requestConfiguration(request, url, topUrl).finally(() => {
      if (pendingConfigurationRequests.get(key) === requestPromise) {
        pendingConfigurationRequests.delete(key);
      }
    });
    pendingConfigurationRequests.set(key, requestPromise);
    return requestPromise;
  };
  /**
   * Tries to get rules from the cache. If not found, requests them from the
   * native host.
   *
   * @param message - The original message from the content script.
   * @param url - Page URL for which the rules are requested.
   * @param topUrl - Top-level page URL (to distinguish between frames)
   * @returns The response message from the native host.
   */
  const getConfiguration = async (message, url, topUrl) => {
    await configCacheHydration;
    const key = cacheKey(url, topUrl);
    if (cache.has(key) && isConfigFresh(key)) {
      return { configuration: cache.get(key), fromCache: true, fresh: true };
    }
    if (cache.has(key)) {
      // Revalidate without making the cached path wait for the full rules lookup.
      void requestConfigurationCoalesced(message, url, topUrl).catch(error => {
        console.warn("[wBlock] Background configuration refresh failed:", error);
      });
      const configuration = cache.get(key);
      if (configuration) return { configuration, fromCache: true };
    }
    const configuration = await requestConfigurationCoalesced(message, url, topUrl);
    return { configuration, fromCache: false };
  };
  const emptyConfigurationForState = (disabled, paused) => ({
    css: [],
    procedural: [],
    scriptlets: [],
    userScripts: [],
    engineTimestamp: 0,
    disabled,
    paused
  });
  /**
   * Message listener that intercepts messages sent to the background script.
   *
   * @param request Message from the content script.
   * @param sender The sender of the message.
   * @returns The response message from the native host.
   */
  const gmConnectAllows = (entries, target, pageURL) => {
    try {
      const url = new URL(target);
      if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) return false;
      const host = url.hostname.toLowerCase().replace(/\.+$/, "");
      const pageHost = new URL(pageURL).hostname.toLowerCase().replace(/\.+$/, "");
      return entries.some(raw => {
        if (typeof raw !== "string") return false;
        const value = raw.trim().toLowerCase();
        if (value === "*") return true;
        if (value === "self") return host === pageHost;
        if (!value || /[\s/:@?#*]/.test(value) || value.includes("\\") || value.includes("%")) return false;
        try {
          const domain = new URL(`https://${value}`).hostname.toLowerCase().replace(/\.+$/, "");
          return !!domain && (host === domain || host.endsWith(`.${domain}`));
        } catch { return false; }
      });
    } catch { return false; }
  };
  const fetchGMWithConnect = async (target, options, entries, pageURL, redirect) => {
    let url = new URL(target);
    const headers = new Headers(options.headers);
    let method = String(options.method || "GET").toUpperCase();
    let body = options.body;
    for (let hop = 0; hop <= 20; hop++) {
      if (!gmConnectAllows(entries, url.href, pageURL)) throw new Error("GM_xmlhttpRequest redirect blocked by @connect");
      const response = await fetch(url.href, { ...options, method, body, headers, redirect: "manual" });
      if (response.type === "opaqueredirect") throw new Error("GM_xmlhttpRequest cannot safely inspect this redirect");
      if (![301, 302, 303, 307, 308].includes(response.status)) return response;
      if (redirect === "manual") return response;
      if (redirect !== "follow") throw new Error("GM_xmlhttpRequest redirect refused");
      const location = response.headers.get("location");
      if (!location) return response;
      const next = new URL(location, url);
      if (next.origin !== url.origin) {
        for (const name of ["authorization", "cookie", "proxy-authorization"]) headers.delete(name);
      }
      if ((response.status === 303 && method !== "HEAD") || ([301, 302].includes(response.status) && method === "POST")) {
        method = "GET"; body = undefined;
        for (const name of ["content-type", "content-length"]) headers.delete(name);
      }
      if (response.body) await response.body.cancel();
      url = next;
    }
    throw new Error("GM_xmlhttpRequest redirect limit exceeded");
  };
  const FORBIDDEN_GM_XHR_HEADER_NAMES = new Set([
    "accept-charset",
    "accept-encoding",
    "access-control-request-headers",
    "access-control-request-method",
    "connection",
    "content-length",
    "cookie",
    "date",
    "dnt",
    "host",
    "keep-alive",
    "origin",
    "permissions-policy",
    "referer",
    "referrer",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
    "user-agent",
    "via"
  ]);
  const shouldUseNativeGMXmlhttpRequest = headers => {
    if (!headers || typeof headers !== "object") {
      return false;
    }
    return Object.keys(headers).some(name => {
      const normalized = String(name || "").trim().toLowerCase();
      return FORBIDDEN_GM_XHR_HEADER_NAMES.has(normalized) || normalized.startsWith("proxy-") || normalized.startsWith("sec-");
    });
  };
  const formatGMResponseHeaders = headers => {
    if (typeof headers === "string") {
      return headers;
    }
    if (!headers || typeof headers !== "object") {
      return "";
    }
    return Object.entries(headers).map(([key, value]) => `${key}: ${value}`).join("\r\n");
  };
  const normalizeGMResponseType = responseType => String(responseType || "text").trim().toLowerCase();
  const isBinaryGMResponseType = responseType => {
    const normalized = normalizeGMResponseType(responseType);
    return normalized === "blob" || normalized === "arraybuffer";
  };
  const arrayBufferToBase64 = buffer => {
    const bytes = new Uint8Array(buffer);
    let binary = "";
    const chunkSize = 32768;
    for (let i = 0; i < bytes.length; i += chunkSize) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunkSize));
    }
    return btoa(binary);
  };
  const extractCharsetFromContentType = contentType => {
    const match = String(contentType || "").match(/charset\s*=\s*[\"']?([^;\"'\s]+)/i);
    return match ? match[1].trim() : "";
  };
  const decodeGMFetchResponseText = async (response, overrideMimeType) => {
    const charset = extractCharsetFromContentType(overrideMimeType) || extractCharsetFromContentType(response.headers.get("content-type"));
    if (!charset || typeof TextDecoder === "undefined") {
      return await response.text();
    }
    const buffer = await response.arrayBuffer();
    try {
      return new TextDecoder(charset).decode(buffer);
    } catch (_error) {
      return new TextDecoder("utf-8").decode(buffer);
    }
  };
  const readGMFetchResponseBytes = async (response, maximumBytes) => {
    if (!response.body || typeof response.body.getReader !== "function") {
      throw new Error("GM_xmlhttpRequest response cannot be safely bounded");
    }
    const reader = response.body.getReader();
    const chunks = [];
    let total = 0;
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        const chunk = value instanceof Uint8Array ? value : new Uint8Array(value || []);
        total += chunk.byteLength;
        if (total > maximumBytes) throw new Error("GM_xmlhttpRequest response is too large");
        chunks.push(chunk);
      }
    } catch (error) {
      try { await reader.cancel(); } catch (_) {}
      throw error;
    }
    const result = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      result.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return result;
  };
  const decodeGMResponseBytes = (bytes, response, overrideMimeType) => {
    const charset = extractCharsetFromContentType(overrideMimeType) || extractCharsetFromContentType(response.headers.get("content-type"));
    if (typeof TextDecoder === "undefined") return String.fromCharCode(...bytes);
    try {
      return new TextDecoder(charset || "utf-8").decode(bytes);
    } catch (_) {
      return new TextDecoder("utf-8").decode(bytes);
    }
  };
  const parseGMResponseBody = (responseText, responseType) => {
    const normalized = normalizeGMResponseType(responseType);
    if (normalized === "json") {
      try {
        return JSON.parse(responseText || "null");
      } catch (_error) {
        return null;
      }
    }
    return responseText;
  };
  const sendGMPortMessage = async (sender, portName, message) => {
    var _sender$tab;
    const tabId = (_sender$tab = sender.tab) === null || _sender$tab === void 0 ? void 0 : _sender$tab.id;
    if (!tabId || !portName) {
      return false;
    }
    try {
      await browser.tabs.sendMessage(tabId, {
        type: "wblock:gm-port-message",
        portName,
        message
      }, {
        frameId: sender.frameId ?? 0
      });
      return true;
    } catch (error) {
      console.error("[wBlock] Failed to deliver userscript stream chunk:", error);
      return false;
    }
  };
  const streamGMFetchResponseToPort = async (fetchResponse, sender, portName) => {
    if (!fetchResponse.body || typeof fetchResponse.body.getReader !== "function") {
      const declaredLength = Number(fetchResponse.headers.get("content-length") || 0);
      if (!Number.isFinite(declaredLength) || declaredLength > 25 * 1024 * 1024) {
        throw new Error("GM_xmlhttpRequest response is too large");
      }
      const text = await fetchResponse.text();
      const responseLength = new TextEncoder().encode(text).byteLength;
      if (responseLength > 25 * 1024 * 1024) throw new Error("GM_xmlhttpRequest response is too large");
      await sendGMPortMessage(sender, portName, text);
      await sendGMPortMessage(sender, portName, "[DONE]");
      return { responseLength, sentDone: true };
    }

    const reader = fetchResponse.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    let responseLength = 0;
    let sentDone = false;
    const emitLine = async line => {
      const trimmed = String(line || "").trim();
      if (!trimmed || trimmed.startsWith("event:")) return;
      const message = trimmed.startsWith("data:") ? trimmed.slice(5).trim() : trimmed;
      if (!message) return;
      if (message === "[DONE]") sentDone = true;
      await sendGMPortMessage(sender, portName, message);
    };

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      responseLength += value ? value.byteLength || value.length || 0 : 0;
      if (responseLength > 25 * 1024 * 1024) {
        try { await reader.cancel(); } catch (_) {}
        throw new Error("GM_xmlhttpRequest response is too large");
      }
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split(/\r?\n/);
      buffer = lines.pop() || "";
      for (const line of lines) {
        await emitLine(line);
      }
    }

    buffer += decoder.decode();
    if (buffer) await emitLine(buffer);
    if (!sentDone) await sendGMPortMessage(sender, portName, "[DONE]");
    return { responseLength, sentDone: true };
  };
  const normalizeSiteDisabledHost = host => typeof host === "string"
    ? host.trim().toLowerCase()
    : "";
  // Zapper activation and action state cannot wait behind background updates.
  // The app can change these without telling Safari (iOS), so frames share
  // only a read still in flight, never a settled answer.
  const inFlightOnly = () => false;
  const requestSiteDisabledState = host => readNativeRecently({
    action: "getSiteDisabledState",
    host: normalizeSiteDisabledHost(host)
  }, sendPriorityNativeMessage, inFlightOnly);
  const requestBlockingState = host => readNativeRecently({
    action: "getBlockingState",
    host: normalizeSiteDisabledHost(host)
  }, sendPriorityNativeMessage, inFlightOnly);
  // No Autoplay's scripts load only while it can block on some site, so with
  // it off no frame runs them or asks native for its state. Safari before
  // 16.4 cannot register scripts; there they are injected as frames start.
  const NO_AUTOPLAY_SCRIPT = {
    id: "wblock-no-autoplay",
    js: ["no-autoplay-gate.js", "no-autoplay.js"],
    matches: ["<all_urls>"],
    allFrames: true,
    runAt: "document_start"
  };
  const canRegisterNoAutoplay = !!(browser.scripting && browser.scripting.registerContentScripts);
  // Mirrors the controller's state sources: a cached enabled flag counts
  // before migration and whenever native cannot answer. null means unknown,
  // so the current setup is left as it is.
  const isNoAutoplayActive = async () => {
    const stored = await browser.storage.local.get(["wblock.noAutoplay.enabled.v1", "wblock.noAutoplay.nativeMigrated.v1"]);
    const cachedEnabled = !!stored && stored["wblock.noAutoplay.enabled.v1"] === true;
    if (cachedEnabled && stored["wblock.noAutoplay.nativeMigrated.v1"] !== true) return true;
    const response = await readNativeRecently({ action: "getNoAutoplayState" }).catch(() => null);
    if (response && typeof response.active === "boolean") return response.active;
    return cachedEnabled || null;
  };
  const injectNoAutoplay = target => browser.scripting.executeScript({
    target, files: NO_AUTOPLAY_SCRIPT.js, injectImmediately: true
  }).catch(() => {});
  let noAutoplaySync = Promise.resolve();
  let lastNoAutoplaySync = 0;
  // Without registration, the last state this background saw stands in; the
  // first one seen is not a change, or every wake would inject into all tabs.
  // A forced (popup) sync always backfills, since the popup may have woken it.
  let noAutoplayLoaded = null;
  const syncNoAutoplayScripts = (force = false) => {
    if (!force && Date.now() - lastNoAutoplaySync < CONFIG_REVALIDATE_INTERVAL_MS) return noAutoplaySync;
    lastNoAutoplaySync = Date.now();
    noAutoplaySync = noAutoplaySync.then(async () => {
      const active = await isNoAutoplayActive();
      if (active === null) return;
      const ids = [NO_AUTOPLAY_SCRIPT.id];
      const loaded = canRegisterNoAutoplay
        ? (await browser.scripting.getRegisteredContentScripts({ ids })).length > 0
        : !force && (noAutoplayLoaded ?? active);
      noAutoplayLoaded = active;
      if (active === loaded) return;
      if (canRegisterNoAutoplay) {
        await (active
          ? browser.scripting.registerContentScripts([NO_AUTOPLAY_SCRIPT])
          : browser.scripting.unregisterContentScripts({ ids }));
      }
      if (!active) return;
      // Registration only reaches documents that start later. Not awaited, so
      // the popup's reply does not wait on every tab.
      browser.tabs.query({}).then(tabs => tabs.forEach(tab => {
        if (typeof tab.id === "number") injectNoAutoplay({ tabId: tab.id, allFrames: true });
      }), () => {});
    }).catch(error => console.warn("[wBlock] No Autoplay setup failed:", error));
    return noAutoplaySync;
  };
  // Global Privacy Control is sent only while its app setting is on: a
  // Sec-GPC header rule, then a page-world script for
  // navigator.globalPrivacyControl, so the property never claims a header
  // Safari is not sending. WebKit skips main-frame requests when a rule lists
  // no resource types, and ignores the whole rule when "object" is listed.
  // Priority 1 belongs to the blocked-request count's allow and block rules.
  const GPC_RULE = {
    id: 1700000,
    priority: 2,
    action: { type: "modifyHeaders", requestHeaders: [{ header: "Sec-GPC", operation: "set", value: "1" }] },
    condition: { resourceTypes: ["main_frame", "sub_frame", "stylesheet", "script", "image", "font", "xmlhttprequest", "ping", "media", "websocket", "other"] }
  };
  const GPC_SCRIPT = {
    id: "wblock-gpc",
    js: ["gpc.js"],
    matches: ["<all_urls>"],
    allFrames: true,
    runAt: "document_start",
    world: "MAIN"
  };
  let gpcSync = Promise.resolve();
  let lastGPCSync = 0;
  const syncGlobalPrivacyControl = () => {
    const dnr = browser.declarativeNetRequest;
    if (!canRegisterNoAutoplay || !dnr || typeof dnr.getDynamicRules !== "function") return gpcSync;
    if (Date.now() - lastGPCSync < CONFIG_REVALIDATE_INTERVAL_MS) return gpcSync;
    lastGPCSync = Date.now();
    gpcSync = gpcSync.then(async () => {
      const response = await readNativeRecently({ action: "getGlobalPrivacyControlState" }).catch(() => null);
      if (!response || typeof response.enabled !== "boolean") return;
      const ids = [GPC_SCRIPT.id];
      const installedRule = (await dnr.getDynamicRules()).find(rule => rule && rule.id === GPC_RULE.id);
      const ruleInstalled = !!installedRule;
      const scriptLoaded = (await browser.scripting.getRegisteredContentScripts({ ids })).length > 0;
      if (!response.enabled) {
        if (scriptLoaded) await browser.scripting.unregisterContentScripts({ ids });
        if (ruleInstalled) await dnr.updateDynamicRules({ removeRuleIds: [GPC_RULE.id] });
        return;
      }
      // Builds before the blocked-request count installed it at priority 1.
      if (!ruleInstalled || installedRule.priority !== GPC_RULE.priority) {
        await dnr.updateDynamicRules({ removeRuleIds: ruleInstalled ? [GPC_RULE.id] : [], addRules: [GPC_RULE] });
      }
      if (!scriptLoaded) await browser.scripting.registerContentScripts([GPC_SCRIPT]);
    }).catch(error => console.warn("[wBlock] Global Privacy Control setup failed:", error));
    return gpcSync;
  };
  const handleMessages = async (request, sender) => {
    var _sender$tab, _sender$tab2;
    // Cast the incoming request to `Message`.
    let message = request;
    if (message && message.action === "wblock:popup:nativeMessage") {
      const allowedActions = new Set([
        "logExtensionDiagnostic", "syncZapperRules", "getZapperRules",
        "getBlockingPausedState", "getResumeRequestStatus", "resumeBlocking",
        "getSiteDisabledState", "setSiteDisabledState", "setSiteZapperDisabled",
        "getSiteFilterDisabledState", "setSiteFilterDisabledState", "setUserScriptsSiteDisabled",
        "getPageUserScripts", "setUserScriptSiteDisabledState", "getNoAutoplayState",
        "setNoAutoplaySiteAllowed", "setNoAutoplayEnabled"
      ]);
      const nativeRequest = message.message;
      // A content script must not gain the popup's native mutation privileges.
      // Safari 17 sends popup messages as { origin: "null" } with no URL (#896).
      const isPopupSender = sender && !sender.tab && (sender.url === browser.runtime.getURL("pages/popup/popup.html")
          || (sender.url === undefined && sender.origin === "null" && sender.frameId === undefined));
      if (!isPopupSender) {
        // Echo the sender's shape so a popup error screenshot shows what Safari sent.
        const shape = sender ? { tab: Boolean(sender.tab), url: sender.url, origin: sender.origin, frameId: sender.frameId } : null;
        return { ok: false, error: `Invalid popup sender ${JSON.stringify(shape)}` };
      }
      if (!nativeRequest || !allowedActions.has(nativeRequest.action)) {
        return { ok: false, error: "Invalid popup native request" };
      }
      try {
        // User actions must not wait behind queued filter or userscript updates.
        const response = await sendPriorityNativeMessage(nativeRequest);
        if (/^setNoAutoplay/.test(nativeRequest.action)) await syncNoAutoplayScripts(true);
        return { ok: true, response };
      } catch (error) {
        return { ok: false, error: String(error && error.message ? error.message : error) };
      }
    }
    const frameActions = new Set([
      "getUserScripts", "validateUserScriptExecution", "getUserScriptContentChunk",
      "getUserScriptResourceChunk", "setUserScriptStorageValue", "deleteUserScriptStorageValue"
    ]);
    if (message && frameActions.has(message.action)) {
      // Content code never chooses its origin or top-frame status. This does
      // not authenticate individual installed scripts within the content world.
      if (!sender || !Number.isSafeInteger(sender.frameId) || sender.frameId < 0
          || typeof sender.url !== "string" || !/^https?:\/\//.test(sender.url)) {
        return {ok:false, error:"Userscript request requires a verified frame"};
      }
      message = {...message, url:sender.url, pageURL:sender.url, isTopFrame:sender.frameId === 0};
    }
    if (message && message.action === "wblock:noAutoplay:injectGate") {
      // Page-world fallback for the No Autoplay gate when the page's CSP
      // blocks inline scripts. Inject the bundled function directly so a
      // strict CSP cannot block an eval inside the injected callback.
      const tabId = sender && sender.tab ? sender.tab.id : undefined;
      if (typeof tabId !== "number" || !browser.scripting || typeof globalThis.__wblockNoAutoplayGate !== "function" || typeof message.token !== "string") {
        return { ok: false };
      }
      try {
        await browser.scripting.executeScript({
          target: { tabId, frameIds: [sender.frameId ?? 0] },
          func: globalThis.__wblockNoAutoplayGate,
          args: [message.token],
          world: "MAIN",
          injectImmediately: true
        });
        return { ok: true };
      } catch (error) {
        return { ok: false, error: String(error && error.message ? error.message : error) };
      }
    }
    if (message && message.action === "wblock:filterUpdate:start") {
      try {
        return await sendPriorityNativeMessage({ action: "startFilterUpdate" });
      } catch (error) {
        return {
          ok: false,
          state: "failed",
          error: String(error && error.message ? error.message : error)
        };
      }
    }
    if (message && message.action === "wblock:filterUpdate:getStatus") {
      try {
        return await sendPriorityNativeMessage({ action: "getFilterUpdateStatus" });
      } catch (error) {
        return {
          ok: false,
          state: "failed",
          error: String(error && error.message ? error.message : error)
        };
      }
    }
    if (message && message.action === "wblock:clearCache") {
      configurationGeneration += 1;
      cache.clear();
      forgetRecentNativeState();
      engineTimestamp = 0;
      pendingConfigurationRequests.clear();
      await Promise.all([
        clearPersistedConfigCache(),
        clearDocumentStartSessionCache()
      ]);
      await scheduleInstallRemoveParamDNRRules(true);
      await refreshActionStateForActiveTabs();
      return {
        ok: true
      };
    }
    if (message && message.action === "wblock:installRemoveParamDNRRules") {
      await scheduleInstallRemoveParamDNRRules(true);
      return {
        ok: true
      };
    }
    if (message && message.action === "wblock:getCleanURL") {
      const url = typeof message.url === "string" ? message.url : "";
      const cleanUrl = await getCleanURLWithRemoveParamRules(url);
      return {
        ok: true,
        cleanUrl
      };
    }
    // Per-site disable check used by the content script to skip advanced
    // rules and removeparam rewrites on whitelisted sites (issue #445).
    if (message && message.action === "wblock:getSiteDisabledState") {
      const host = normalizeSiteDisabledHost(message.host);
      if (!host) {
        return { ok: false, disabled: false, error: "Missing host" };
      }
      try {
        const response = await requestSiteDisabledState(host);
        return {
          ok: true,
          disabled: !!(response && response.disabled)
        };
      } catch (error) {
        console.warn("[wBlock] Failed to resolve site disabled state for", host, error);
        return {
          ok: false,
          disabled: false,
          error: String(error && error.message ? error.message : error)
        };
      }
    }
    if (message && message.action === "wblock:noAutoplay:getState") {
      const host = normalizeSiteDisabledHost(message.host);
      if (!host) {
        return { ok: false, error: "Missing host" };
      }
      try {
        const response = await readNativeRecently({ action: "getNoAutoplayState", host });
        if (!response || typeof response.enabled !== "boolean" || typeof response.siteAllowed !== "boolean") {
          throw new Error("Invalid No Autoplay state from native host");
        }
        return { ok: true, enabled: response.enabled, siteAllowed: response.siteAllowed };
      } catch (error) {
        return { ok: false, error: String(error && error.message ? error.message : error) };
      }
    }
    if (message && message.action === "wblock:zapper:syncRules") {
      const hostname = typeof message.hostname === "string" ? message.hostname : "";
      const rules = Array.isArray(message.rules) ? message.rules : [];
      if (!hostname) {
        return { ok: false, error: "Missing hostname", rules: [] };
      }
      try {
        const response = await sendQueuedNativeMessage({
          action: "syncZapperRules",
          hostname,
          rules
        });
        return response || { ok: false, rules: [] };
      } catch (error) {
        const errorMessage = String(error && error.message ? error.message : error);
        console.error(`[wBlock] Failed to sync zapper rules via background bridge: ${errorMessage}`, error);
        return { ok: false, error: errorMessage, rules: [] };
      }
    }
    if (message && message.action === "wblock:zapper:getRules") {
      const hostname = typeof message.hostname === "string" ? message.hostname : "";
      if (!hostname) {
        return { ok: false, error: "Missing hostname", rules: [] };
      }
      try {
        const response = await readNativeRecently({
          action: "getZapperRules",
          hostname
        }, sendQueuedNativeMessage);
        return response || { ok: false, rules: [] };
      } catch (error) {
        const errorMessage = String(error && error.message ? error.message : error);
        console.error(`[wBlock] Failed to fetch zapper rules via background bridge: ${errorMessage}`, error);
        return { ok: false, error: errorMessage, rules: [] };
      }
    }
    if (message && message.action === "wblock:zapper:setDisabled") {
      const hostname = typeof message.hostname === "string" ? message.hostname : "";
      if (!hostname) return { ok: false, error: "Missing hostname" };
      try {
        const response = await sendQueuedNativeMessage({
          action: "setSiteZapperDisabled",
          hostname,
          disabled: message.disabled === true
        });
        return response || { ok: false, error: "Empty response from native host" };
      } catch (error) {
        return { ok: false, error: String(error && error.message ? error.message : error) };
      }
    }
    if (message && message.action === "wblock:zapper:broadcastReload") {
      const tabId = sender && sender.tab ? sender.tab.id : undefined;
      if (typeof tabId !== "number" || !browser.tabs || typeof browser.tabs.sendMessage !== "function") {
        return { ok: false, error: "Missing tab" };
      }
      try {
        await browser.tabs.sendMessage(tabId, { type: "wblock:zapper:reloadRules" });
        return { ok: true };
      } catch (error) {
        return { ok: false, error: String(error && error.message ? error.message : error) };
      }
    }
    if (message && message.action === "getUserScripts") {
      const userScriptRequest = {
        action: "getUserScripts",
        url: message.url,
        isTopFrame: message.isTopFrame,
        includeContent: message.includeContent === true,
        maxInlineContentBytes: message.maxInlineContentBytes || 0
      };

      try {
        // Only "no scripts here" is shared: script payloads carry revisions and
        // GM storage that must stay current.
        const response = await readNativeRecently(userScriptRequest, sendPriorityNativeMessage,
          answer => Array.isArray(answer.userScripts) && answer.userScripts.length === 0);
        const scripts = response && response.userScripts ? response.userScripts : [];
        if (response && response.error) {
          return { userScripts: scripts, error: response.error };
        }
        return { userScripts: scripts };
      } catch (error) {
        const errorMessage = String(error && error.message ? error.message : error);
        console.error(`[wBlock] Failed to get userscripts: ${errorMessage}`, error);
        return { userScripts: [], error: errorMessage };
      }
    }
    if (message && (message.action === "setUserScriptStorageValue" || message.action === "deleteUserScriptStorageValue")) {
      const storageRequest = {
        action: message.action,
        requestId: "userscript-storage-" + Date.now(),
        scriptId: message.scriptId,
        pageURL: message.pageURL,
        isTopFrame: message.isTopFrame,
        key: message.key
      };
      if (typeof message.rawValue === "string") {
        storageRequest.rawValue = message.rawValue;
      }

      try {
        const response = await sendQueuedNativeMessage(storageRequest);
        if (!response || typeof response.ok !== "boolean") {
          return { ok: false, error: "Empty response from native host" };
        }
        return response;
      } catch (error) {
        const errorMessage = String(error && error.message ? error.message : error);
        console.error(`[wBlock] Failed to update userscript storage: ${errorMessage}`, error);
        return { ok: false, error: errorMessage };
      }
    }
    if (message && message.action === "wblock:menu:updateFrameCommands") {
      const tabId = ((_sender$tab = sender.tab) === null || _sender$tab === void 0 ? void 0 : _sender$tab.id) ?? 0;
      const frameId = sender.frameId ?? 0;
      setFrameMenuCommands(tabId, frameId, message.commands);
      return { ok: true };
    }
    if (message && message.action === "wblock:menu:getCommands") {
      const tabId = typeof message.tabId === "number" ? message.tabId : (((_sender$tab = sender.tab) === null || _sender$tab === void 0 ? void 0 : _sender$tab.id) ?? 0);
      const liveCommands = await queryLiveTabMenuCommands(tabId);
      return { ok: true, commands: Array.isArray(liveCommands) ? liveCommands : getTabMenuCommands(tabId) };
    }
    if (message && message.action === "wblock:menu:invokeCommand") {
      const tabId = typeof message.tabId === "number" ? message.tabId : (((_sender$tab = sender.tab) === null || _sender$tab === void 0 ? void 0 : _sender$tab.id) ?? 0);
      const frameId = typeof message.frameId === "number" ? message.frameId : 0;
      if (!tabId) {
        return { ok: false, error: "Missing tab" };
      }
      try {
        const response = await browser.tabs.sendMessage(tabId, {
          type: "wblock:menu:invokeCommand",
          bridgeId: message.bridgeId,
          commandId: message.commandId
        }, {
          frameId
        });
        return response || { ok: false, error: "Empty response from content script" };
      } catch (error) {
        return { ok: false, error: String(error && error.message ? error.message : error) };
      }
    }
    if (message && message.action === "gmXmlhttpRequest") {
      try {
        const pageURL = sender.url;
        if (typeof message.scriptId !== "string" || typeof pageURL !== "string" || !/^https?:/.test(pageURL)) {
          return { error: "GM_xmlhttpRequest requires a verified script and frame" };
        }
        const policy = await sendPriorityNativeMessage({
          action: "getUserScriptRequestPolicy", scriptId: message.scriptId,
          pageURL, isTopFrame: sender.frameId === 0
        });
        if (!policy || policy.ok !== true || !Array.isArray(policy.connect)) {
          return { error: "GM_xmlhttpRequest script is no longer authorized" };
        }
        const entries = policy.connect;
        if (!gmConnectAllows(entries, message.url, pageURL)) return { error: "GM_xmlhttpRequest blocked by @connect" };
        const MAX_GM_XHR_RESPONSE_BYTES = 25 * 1024 * 1024;
        const MAX_GM_XHR_REQUEST_BODY_BYTES = 2 * 1024 * 1024;
        const requestHeaders = message.headers || {};
        if (Object.keys(requestHeaders).length > 128) return { error: "Too many request headers" };
        if (typeof message.body === "string" && new TextEncoder().encode(message.body).byteLength > MAX_GM_XHR_REQUEST_BODY_BYTES) return { error: "Request body is too large" };
        const streamPortName = typeof message.portName === "string" ? message.portName : "";
        const wantsStreamResponse = !!streamPortName || normalizeGMResponseType(message.responseType) === "stream" || normalizeGMResponseType(message.responseType) === "realstream";
        if (shouldUseNativeGMXmlhttpRequest(requestHeaders)) {
          if (wantsStreamResponse) {
            return { error: "Streaming GM_xmlhttpRequest is not available for native-header requests" };
          }
          const nativeRequest = {
            action: "gmXmlhttpRequestNative",
            scriptId: message.scriptId,
            pageURL,
            isTopFrame: sender.frameId === 0,
            requestId: "userscript-gmxhr-native-" + Date.now(),
            url: message.url,
            method: message.method || 'GET',
            headers: requestHeaders,
            body: message.body || null,
            anonymous: message.anonymous === true,
            responseType: message.responseType || 'text',
            redirect: message.redirect || 'follow',
            timeout: message.timeout || 0,
            overrideMimeType: message.overrideMimeType || ''
          };
          const nativeResponse = await sendQueuedNativeMessage(nativeRequest);
          return nativeResponse || { error: "Empty response from native host" };
        }

        const timeoutMs = Number(message.timeout || 0);
        const abortController = Number.isFinite(timeoutMs) && timeoutMs > 0 ? new AbortController() : null;
        let timeoutId = null;
        if (abortController) {
          timeoutId = setTimeout(() => abortController.abort(), timeoutMs);
        }
        const fetchOptions = {
          method: message.method || 'GET',
          headers: requestHeaders,
          credentials: message.anonymous ? 'omit' : 'include',
          redirect: "manual"
        };
        if (abortController) {
          fetchOptions.signal = abortController.signal;
        }
        const httpMethod = (message.method || 'GET').toUpperCase();
        if (message.body && httpMethod !== 'GET' && httpMethod !== 'HEAD') {
          fetchOptions.body = message.body;
        }
        let fetchResponse;
        try {
          fetchResponse = await fetchGMWithConnect(message.url, fetchOptions, entries, pageURL, message.redirect || "follow");
        } finally {
          if (timeoutId) {
            clearTimeout(timeoutId);
          }
        }
        const responseHeaders = {};
        fetchResponse.headers.forEach((value, key) => {
          responseHeaders[key] = value;
        });
        const responseType = normalizeGMResponseType(message.responseType);
        const declaredLength = Number(fetchResponse.headers.get("content-length") || 0);
        if (Number.isFinite(declaredLength) && declaredLength > MAX_GM_XHR_RESPONSE_BYTES) return { error: "GM_xmlhttpRequest response is too large" };
        if (streamPortName) {
          const streamResult = await streamGMFetchResponseToPort(fetchResponse, sender, streamPortName);
          return {
            status: fetchResponse.status,
            statusText: fetchResponse.statusText,
            responseHeaders: formatGMResponseHeaders(responseHeaders),
            responseText: "",
            response: null,
            responseLength: streamResult.responseLength,
            responseTotal: streamResult.responseLength,
            finalUrl: fetchResponse.url
          };
        }
        if (responseType === "stream" || responseType === "realstream") {
          return { error: "Streaming GM_xmlhttpRequest requires a portName" };
        }
        let responseText = "";
        let response = null;
        let responseBase64 = null;
        const responseMimeType = fetchResponse.headers.get("content-type") || "";
        let responseLength = 0;

        const responseBytes = await readGMFetchResponseBytes(fetchResponse, MAX_GM_XHR_RESPONSE_BYTES);
        responseLength = responseBytes.byteLength;
        if (isBinaryGMResponseType(responseType)) {
          responseBase64 = arrayBufferToBase64(responseBytes);
        } else {
          responseText = decodeGMResponseBytes(responseBytes, fetchResponse, message.overrideMimeType);
          response = parseGMResponseBody(responseText, responseType);
        }
        const responseTotal = Number.isFinite(declaredLength) && declaredLength > 0 ? declaredLength : responseLength;

        return {
          status: fetchResponse.status,
          statusText: fetchResponse.statusText,
          responseHeaders: formatGMResponseHeaders(responseHeaders),
          responseText: responseText,
          response: response,
          responseBase64: responseBase64,
          responseMimeType: responseMimeType,
          responseLength: responseLength,
          responseTotal: responseTotal,
          finalUrl: fetchResponse.url
        };
      } catch (error) {
        return { error: error.message || String(error) };
      }
    }
    if (message && message.action === "validateUserScriptExecution") {
      try {
        return await sendPriorityNativeMessage({
          action: message.action,
          requestId: "userscript-validate-" + Date.now(),
          isTopFrame: message.isTopFrame,
          scriptId: message.scriptId,
          url: message.url,
          payloadRevision: message.payloadRevision,
          ...(typeof message.contentDigest === "string" ? { contentDigest: message.contentDigest } : {})
        });
      } catch (error) {
        return { ok: false, error: String(error && error.message ? error.message : error) };
      }
    }
    if (message && (message.action === "getUserScriptContentChunk" || message.action === "getUserScriptResourceChunk")) {
      const chunkRequest = {
        action: message.action,
        requestId: "userscript-chunk-" + Date.now(),
        isTopFrame: message.isTopFrame,
        scriptId: message.scriptId,
        chunkIndex: message.chunkIndex,
        chunkSize: message.chunkSize,
        payloadRevision: message.payloadRevision,
        url: message.url
      };
      if (typeof message.resourceName === "string" && message.resourceName.length > 0) {
        chunkRequest.resourceName = message.resourceName;
      }

      try {
        const response = await sendQueuedNativeMessage(chunkRequest);
        return response || { error: "Empty response from native host" };
      } catch (error) {
        const errorMessage = String(error && error.message ? error.message : error);
        console.error(`[wBlock] Failed to get userscript chunk: ${errorMessage}`, error);
        return { error: errorMessage };
      }
    }
    if (message && ["gmXmlhttpRequestNative", "getUserScriptRequestPolicy"].includes(message.action)) {
      return { error: "Native userscript networking is only available through the authorized GM bridge" };
    }
    const tabId = ((_sender$tab = sender.tab) === null || _sender$tab === void 0 ? void 0 : _sender$tab.id) ?? 0;
    const frameId = sender.frameId ?? 0;
    let blankFrame = false;
    let url = sender.url || '';
    const topUrl = frameId === 0 ? undefined : (_sender$tab2 = sender.tab) === null || _sender$tab2 === void 0 ? void 0 : _sender$tab2.url;
    if (!url.startsWith('http') && topUrl) {
      // Handle the case of non-HTTP iframes, i.e. frames created by JS.
      // For instance, frames can be created as 'about:blank' or 'data:text/html'
      url = topUrl;
      blankFrame = true;
    }
    let configurationResult;
    try {
      configurationResult = await getConfiguration(message, url, topUrl);
    } catch (error) {
      const errorMessage = String(error && error.message ? error.message : error);
      logError('[wBlock] Native configuration lookup failed for ', url, errorMessage);
      return { type: MessageType.InitContentScript, state: "error", error: errorMessage };
    }
    if (!configurationResult || !configurationResult.configuration) {
      const errorMessage = "Native configuration unavailable";
      logError('[wBlock]', errorMessage, url);
      return { type: MessageType.InitContentScript, state: "error", error: errorMessage };
    }
    const { configuration: cachedConfiguration, fromCache, fresh } = configurationResult;
    let configuration = cachedConfiguration;
    let cachedBlockingState = null;
    if (fresh) {
      cachedBlockingState = { disabled: false, paused: false };
      configuration = { ...cachedConfiguration, disabled: false, paused: false };
    } else if (fromCache) {
      let host = "";
      try {
        host = new URL(url).hostname;
      } catch {}
      try {
        const state = await requestBlockingState(host);
        if (!state || typeof state.disabled !== "boolean" || typeof state.paused !== "boolean") {
          throw new Error("Invalid blocking state from native host");
        }
        cachedBlockingState = state;
      } catch (error) {
        const errorMessage = String(error && error.message ? error.message : error);
        logError('[wBlock] Cached configuration state lookup failed for ', url, errorMessage);
        return { type: MessageType.InitContentScript, state: "error", error: errorMessage };
      }
      if (cachedBlockingState.disabled || cachedBlockingState.paused) {
        forgetRecentNativeState();
        configuration = emptyConfigurationForState(
          cachedBlockingState.disabled,
          cachedBlockingState.paused
        );
      } else {
        configuration = {
          ...cachedConfiguration,
          disabled: false,
          paused: false
        };
      }
    } else if (configuration.disabled === true || configuration.paused === true) {
      configuration = emptyConfigurationForState(configuration.disabled === true, configuration.paused === true);
    }
    // Preserve native state on both response paths. Cached state is never used;
    // it is replaced with the result of the priority state lookup above.
    const response = {
      type: MessageType.InitContentScript,
      ...(fromCache
        ? cachedBlockingState
        : typeof configuration.disabled === "boolean"
          && typeof configuration.paused === "boolean"
          ? { disabled: configuration.disabled, paused: configuration.paused }
          : {})
    };
    // In the current Safari version we cannot apply rules to blank frames from
    // the background: https://bugs.webkit.org/show_bug.cgi?id=296702
    //
    // In this case we fallback to using the content script to apply rules.
    // The downside here is that the content script cannot override website's
    // CSPs. A sender without a tab (e.g. a page Safari loads before it joins a
    // tab) has no injection target either, so it takes the same path.
    if (!blankFrame && tabId) {
      if (!fromCache || !(cachedBlockingState.disabled || cachedBlockingState.paused)) {
        // Injection may have partly landed; an error here would make the
        // content script retry and inject twice.
        try {
          await applyConfiguration(tabId, frameId, configuration);
        } catch (error) {
          logError('[wBlock] Failed to apply configuration for ', url, String(error && error.message ? error.message : error));
        }
      }
    } else {
      response.payload = configuration;
    }
    return response;
  };
  const POPUP_PATH = "pages/popup/popup.html";
  const SUPPORTED_PAGE_PROTOCOLS = new Set(["http:", "https:"]);
  const DEFAULT_ACTION_ICON = {
    16: "assets/images/icon-16.png",
    19: "assets/images/icon-19.png",
    32: "assets/images/icon-32.png",
    38: "assets/images/icon-38.png",
    48: "assets/images/icon-48.png",
    96: "assets/images/icon-96.png",
    128: "assets/images/icon-128.png",
    256: "assets/images/icon-256.png",
    512: "assets/images/icon-512.png"
  };
  const DISABLED_ACTION_ICON = {
    16: "assets/images/icon-disabled-16.png",
    19: "assets/images/icon-disabled-19.png",
    32: "assets/images/icon-disabled-32.png",
    38: "assets/images/icon-disabled-38.png",
    48: "assets/images/icon-disabled-48.png",
    96: "assets/images/icon-disabled-96.png",
    128: "assets/images/icon-disabled-128.png",
    256: "assets/images/icon-disabled-256.png",
    512: "assets/images/icon-disabled-512.png"
  };
  const canControlActionState = typeof browser !== "undefined" && !!(browser.action && browser.action.enable && browser.action.disable);
  const canSetActionPopup = typeof browser !== "undefined" && !!(browser.action && browser.action.setPopup);
  const canSetActionIcon = typeof browser !== "undefined" && !!(browser.action && browser.action.setIcon);
  const canSetActionTitle = typeof browser !== "undefined" && !!(browser.action && browser.action.setTitle);
  const canSetActionBadgeText = typeof browser !== "undefined" && !!(browser.action && browser.action.setBadgeText);
  const canSetActionBadgeBackgroundColor = typeof browser !== "undefined" && !!(browser.action && browser.action.setBadgeBackgroundColor);
  const canObserveTabs = typeof browser !== "undefined" && !!browser.tabs;
  const canDisplayActionCount = typeof browser !== "undefined" && !!(browser.declarativeNetRequest && browser.declarativeNetRequest.setExtensionActionOptions);
  const supportStateByTab = new Map();
  const actionSyncGenerationByTab = new Map();
  const menuCommandsByTab = new Map();
  const normalizeMenuCommands = commands => Array.isArray(commands) ? commands.filter(command => command && typeof command === "object").map(command => ({
    bridgeId: typeof command.bridgeId === "string" ? command.bridgeId : "",
    commandId: typeof command.commandId === "string" ? command.commandId : "",
    caption: typeof command.caption === "string" ? command.caption : "",
    title: typeof command.title === "string" ? command.title : "",
    accessKey: typeof command.accessKey === "string" ? command.accessKey : "",
    scriptName: typeof command.scriptName === "string" ? command.scriptName : "",
    sortOrder: Number.isFinite(Number(command.sortOrder)) ? Number(command.sortOrder) : 0
  })).filter(command => command.bridgeId && command.commandId && command.caption.trim()) : [];
  const setFrameMenuCommands = (tabId, frameId, commands) => {
    if (typeof tabId !== "number") {
      return;
    }
    const normalized = normalizeMenuCommands(commands).map(command => ({
      ...command,
      frameId
    }));
    const frameCommands = menuCommandsByTab.get(tabId) || new Map();
    if (normalized.length === 0) {
      frameCommands.delete(frameId);
    } else {
      frameCommands.set(frameId, normalized);
    }
    if (frameCommands.size === 0) {
      menuCommandsByTab.delete(tabId);
    } else {
      menuCommandsByTab.set(tabId, frameCommands);
    }
  };
  const getTabMenuCommands = tabId => {
    if (typeof tabId !== "number") {
      return [];
    }
    const frameCommands = menuCommandsByTab.get(tabId);
    if (!frameCommands) {
      return [];
    }
    const commands = [];
    frameCommands.forEach(frameList => {
      commands.push(...frameList);
    });
    commands.sort((left, right) => {
      const leftTop = left.frameId === 0 ? 0 : 1;
      const rightTop = right.frameId === 0 ? 0 : 1;
      if (leftTop !== rightTop) return leftTop - rightTop;
      if (left.frameId !== right.frameId) return left.frameId - right.frameId;
      if (left.sortOrder !== right.sortOrder) return left.sortOrder - right.sortOrder;
      return left.caption.localeCompare(right.caption);
    });
    return commands;
  };
  const queryLiveTabMenuCommands = async tabId => {
    if (!browser.scripting || !browser.scripting.executeScript || typeof tabId !== "number" || !tabId) {
      return null;
    }
    try {
      const executionResults = await browser.scripting.executeScript({
        target: {
          tabId,
          allFrames: true
        },
        func: () => Array.isArray(window.__wBlockUserscriptMenuState) ? window.__wBlockUserscriptMenuState : []
      });
      const frameCommands = new Map();
      for (const executionResult of executionResults || []) {
        const frameId = typeof executionResult.frameId === "number" ? executionResult.frameId : 0;
        const normalized = normalizeMenuCommands(executionResult.result).map(command => ({
          ...command,
          frameId
        }));
        if (normalized.length > 0) {
          frameCommands.set(frameId, normalized);
        }
      }
      if (frameCommands.size === 0) {
        menuCommandsByTab.delete(tabId);
      } else {
        menuCommandsByTab.set(tabId, frameCommands);
      }
      return getTabMenuCommands(tabId);
    } catch (error) {
      console.warn("[wBlock] Failed to query live menu commands:", error);
      return null;
    }
  };
  const normalizeDiagnosticFields = fields => {
    const entries = Object.entries(fields).filter(([, value]) => value !== undefined && value !== null && value !== "");
    return Object.fromEntries(entries.map(([key, value]) => [key, String(value)]));
  };
  const logSupportDiagnostic = async fields => {
    const normalizedFields = normalizeDiagnosticFields(fields);
    console.info("[wBlock] Support diagnostic", normalizedFields);
    try {
      await sendQueuedNativeMessage({
        action: "logExtensionDiagnostic",
        fields: normalizedFields
      });
    } catch (error) {
      console.warn("[wBlock] Failed to forward support diagnostic to native log:", error, normalizedFields);
    }
  };
  const isSupportedActionUrl = urlString => {
    if (typeof urlString !== "string" || urlString.length === 0) {
      return {
        supported: false,
        reason: "missing_url",
        url: ""
      };
    }
    try {
      const url = new URL(urlString);
      if (!SUPPORTED_PAGE_PROTOCOLS.has(url.protocol)) {
        return {
          supported: false,
          reason: "unsupported_scheme",
          url: urlString,
          protocol: url.protocol,
          host: url.hostname || ""
        };
      }
      if (url.hostname.length === 0) {
        return {
          supported: false,
          reason: "missing_hostname",
          url: urlString,
          protocol: url.protocol
        };
      }
      return {
        supported: true,
        reason: "url_supported",
        url: urlString,
        protocol: url.protocol,
        host: url.hostname
      };
    } catch (_unused) {
      return {
        supported: false,
        reason: "invalid_url",
        url: urlString
      };
    }
  };
  const resolveTabSupport = async tab => {
    if (!tab || typeof tab.id !== "number") {
      return {
        supported: false,
        reason: "missing_tab"
      };
    }
    const urlSupport = isSupportedActionUrl(tab.url);
    if (urlSupport.reason === "missing_url") {
      return {
        supported: true,
        reason: "pending_url",
        tabId: tab.id
      };
    }
    if (!urlSupport.supported) {
      return {
        ...urlSupport,
        tabId: tab.id
      };
    }
    return {
      supported: true,
      reason: "supported",
      tabId: tab.id,
      url: urlSupport.url,
      protocol: urlSupport.protocol,
      host: urlSupport.host
    };
  };
  const actionMessage = (key, fallback) => {
    try {
      const value = browser.i18n && browser.i18n.getMessage ? browser.i18n.getMessage(key) : "";
      return value || fallback;
    } catch (_error) {
      return fallback;
    }
  };
  const actionTitleForState = (supported, blockingPaused, siteDisabled) => {
    const extensionName = actionMessage("extension_name", "wBlock Scripts");
    if (!supported) {
      return `${extensionName} — ${actionMessage("popup_status_unsupported", "Unsupported")}`;
    }
    if (blockingPaused) {
      return `${extensionName} — ${actionMessage("popup_status_paused", "Paused")}`;
    }
    if (siteDisabled) {
      return `${extensionName} — ${actionMessage("popup_status_disabled", "Disabled")}`;
    }
    return extensionName;
  };
  const getBlockingPausedForAction = async () => {
    try {
      const response = await sendQueuedNativeMessage({
        action: "getBlockingPausedState"
      });
      return Boolean(response && response.paused);
    } catch (error) {
      console.warn("[wBlock] Failed to resolve global pause state:", error);
      return false;
    }
  };
  const getSiteDisabledForAction = async host => {
    const normalizedHost = normalizeSiteDisabledHost(host);
    if (!normalizedHost) {
      return false;
    }
    try {
      const response = await requestSiteDisabledState(normalizedHost);
      return Boolean(response && response.disabled);
    } catch (error) {
      console.warn("[wBlock] Failed to resolve action disabled state:", error);
      return false;
    }
  };
  // Only the active tab shows the action; the rest sync through onActivated.
  // Each sync costs native lookups, and Safari refuses every native message
  // for about 5 s after roughly 150 inside that window (#1040).
  const syncActionStateForTab = async tab => {
    if (!tab || !tab.active || typeof tab.id !== "number") {
      return;
    }
    // Native lookups are slow; a newer sync for this tab (e.g. navigating to the
    // unsupported start page) must not be overwritten by one that started earlier.
    const generation = (actionSyncGenerationByTab.get(tab.id) || 0) + 1;
    actionSyncGenerationByTab.set(tab.id, generation);
    const support = await resolveTabSupport(tab);
    const supported = support.supported;
    const blockingPaused = supported ? await getBlockingPausedForAction() : false;
    const siteDisabled = supported && !blockingPaused ? await getSiteDisabledForAction(support.host || "") : false;
    if (actionSyncGenerationByTab.get(tab.id) !== generation) {
      return;
    }
    const updates = [];
    if (canControlActionState) {
      updates.push((supported ? browser.action.enable(tab.id) : browser.action.disable(tab.id)).catch(error => {
        console.warn("[wBlock] Failed to update action enabled state:", error);
      }));
    }
    if (canSetActionPopup) {
      updates.push(browser.action.setPopup({
        tabId: tab.id,
        popup: supported ? POPUP_PATH : ""
      }).catch(error => {
        console.warn("[wBlock] Failed to update action popup:", error);
      }));
    }
    if (canSetActionIcon) {
      updates.push(browser.action.setIcon({
        tabId: tab.id,
        // Safari applies its own tint; the disabled asset must differ in shape.
        path: !supported || blockingPaused || siteDisabled ? DISABLED_ACTION_ICON : DEFAULT_ACTION_ICON
      }).catch(error => {
        console.warn("[wBlock] Failed to update action icon:", error);
      }));
    }
    if (canSetActionBadgeText) {
      updates.push(browser.action.setBadgeText({
        tabId: tab.id,
        // null, not "": any custom text hides Safari's blocked-request count.
        text: blockingPaused ? "II" : (canDisplayActionCount ? null : "")
      }).catch(error => {
        console.warn("[wBlock] Failed to update action badge:", error);
      }));
    }
    if (canSetActionBadgeBackgroundColor && blockingPaused) {
      updates.push(browser.action.setBadgeBackgroundColor({
        tabId: tab.id,
        color: "#F59E0B"
      }).catch(error => {
        console.warn("[wBlock] Failed to update action badge color:", error);
      }));
    }
    if (canSetActionTitle) {
      updates.push(browser.action.setTitle({
        tabId: tab.id,
        title: actionTitleForState(supported, blockingPaused, siteDisabled)
      }).catch(error => {
        console.warn("[wBlock] Failed to update action title:", error);
      }));
    }
    if (updates.length > 0) {
      await Promise.all(updates);
    }
    const fingerprint = JSON.stringify({
      supported: support.supported,
      blockingPaused,
      siteDisabled,
      reason: support.reason,
      protocol: support.protocol || "",
      host: support.host || "",
      url: support.url || "",
      error: support.error || ""
    });
    if (supportStateByTab.get(tab.id) !== fingerprint) {
      supportStateByTab.set(tab.id, fingerprint);
      if (!support.supported) {
        await logSupportDiagnostic({
          event: "support_decision",
          source: "background",
          outcome: "unsupported",
          reason: support.reason,
          tabId: tab.id,
          protocol: support.protocol,
          host: support.host,
          url: support.url,
          error: support.error
        });
      }
    }
  };
  const refreshActionStateForActiveTabs = async () => {
    if (!canObserveTabs || !browser.tabs.query) {
      return;
    }
    try {
      const tabs = await browser.tabs.query({ active: true });
      await Promise.all(tabs.map(syncActionStateForTab));
    } catch (error) {
      console.warn("[wBlock] Failed to refresh action state for tabs:", error);
    }
  };
  /**
   * Opportunistic userscript refresh while Safari is in use (#611). The native
   * side skips scripts already checked inside the auto-update interval, so the
   * only cost here is one native round-trip per throttle window. Filters are
   * not touched from the extension; see handleMaybeUpdateUserScripts.
   */
  const USERSCRIPT_REFRESH_PING_INTERVAL_MS = 15 * 60 * 1000;
  let lastUserScriptRefreshPingAt = 0;
  let userScriptRefreshPingInFlight = null;
  const maybeRefreshUserScripts = () => {
    const now = Date.now();
    if (userScriptRefreshPingInFlight || now - lastUserScriptRefreshPingAt < USERSCRIPT_REFRESH_PING_INTERVAL_MS) {
      return userScriptRefreshPingInFlight || Promise.resolve();
    }
    lastUserScriptRefreshPingAt = now;
    userScriptRefreshPingInFlight = sendQueuedNativeMessage({ action: "maybeUpdateUserScripts" })
      .then(response => {
        if (response && response.updated > 0) {
          clearDocumentStartSessionCache();
        }
      })
      .catch(error => {
        console.warn("[wBlock] Userscript refresh ping failed:", error);
      })
      .finally(() => {
        userScriptRefreshPingInFlight = null;
      });
    return userScriptRefreshPingInFlight;
  };
  // Filter lists download the same way (#528); the native side throttles to
  // the auto-update interval and the app rebuilds from the staged files.
  const FILTER_STAGE_PING_INTERVAL_MS = 15 * 60 * 1000;
  let lastFilterStagePingAt = 0;
  let filterStagePingInFlight = null;
  const maybeStageFilterUpdates = () => {
    const now = Date.now();
    if (filterStagePingInFlight || now - lastFilterStagePingAt < FILTER_STAGE_PING_INTERVAL_MS) {
      return filterStagePingInFlight || Promise.resolve();
    }
    lastFilterStagePingAt = now;
    filterStagePingInFlight = sendQueuedNativeMessage({ action: "maybeStageFilterUpdates" })
      .catch(error => {
        console.warn("[wBlock] Filter staging ping failed:", error);
      })
      .finally(() => {
        filterStagePingInFlight = null;
      });
    return filterStagePingInFlight;
  };
  if (canObserveTabs) {
    if (browser.tabs.onUpdated) {
      browser.tabs.onUpdated.addListener((_tabId, changeInfo, tab) => {
        if (!tab) {
          return;
        }
        if (changeInfo && (changeInfo.status === "loading" || typeof changeInfo.url === "string")) {
          menuCommandsByTab.delete(tab.id);
        }
        if (changeInfo && changeInfo.status && changeInfo.status !== "complete" && !changeInfo.url) {
          return;
        }
        syncActionStateForTab(tab);
        if (changeInfo && changeInfo.status === "complete") {
          maybeRefreshUserScripts().then(maybeStageFilterUpdates);
        }
      });
    }
    if (browser.tabs.onActivated && browser.tabs.get) {
      browser.tabs.onActivated.addListener(async activeInfo => {
        try {
          // Safari's tabs.get can still report the tab inactive here; the
          // activation event is the proof.
          const tab = await browser.tabs.get(activeInfo.tabId);
          await syncActionStateForTab(tab && { ...tab, active: true });
        } catch (error) {
          console.warn("[wBlock] Failed to sync action state for active tab:", error);
        }
      });
    }
    if (browser.tabs.onCreated) {
      browser.tabs.onCreated.addListener(tab => {
        syncActionStateForTab(tab);
      });
    }
    if (browser.tabs.onRemoved) {
      browser.tabs.onRemoved.addListener(tabId => {
        supportStateByTab.delete(tabId);
        actionSyncGenerationByTab.delete(tabId);
        menuCommandsByTab.delete(tabId);
      });
    }
  }
  const REMOVE_PARAM_DNR_CHUNK_SIZE = 250;
  const REMOVE_PARAM_DNR_STORAGE_KEY = "wblockRemoveParamDNRVersion";
  const REMOVE_PARAM_DNR_CHECK_INTERVAL_MS = 60000;
  // Safari 16.4 added the runtime capacity constant. Older Safari versions
  // supported dynamic DNR but did not expose their quota, so keep a
  // conservative compatibility ceiling only for that legacy tier.
  const REMOVE_PARAM_DNR_OLD_SAFARI_FALLBACK_LIMIT = 5000;
  const REDIRECT_DNR_STATUS_REPORT_KEY = "wblockRedirectDNRStatusReport";
  const REDIRECT_DNR_STATUS_REPORT_THROTTLE_MS = 6 * 60 * 60 * 1000;
  let removeParamDNRInstallPromise = null;
  let removeParamDNRRulesCache = null;
  let removeParamDNRVersion = "";
  let lastRemoveParamDNRCheck = 0;
  // Copies of whole-host filter-list blocks. Safari counts them on the
  // toolbar badge even when a content blocker blocked the same request.
  const BLOCKED_COUNT_DNR_CHUNK_SIZE = 1000;
  const BLOCKED_COUNT_DNR_ID_BASE = 1660000;
  const BLOCKED_COUNT_DNR_ID_LIMIT = 1700000;
  // WebKit compiles every DNR rule into one content rule list capped at
  // 150,000 rules, and an overflow fails the whole list. It emits one rule per
  // request domain or excluded request domain, so budget by that.
  const DNR_TRANSLATED_RULE_BUDGET = 120000;
  const translatedRuleCost = rule => {
    const condition = (rule && rule.condition) || {};
    const domains = Array.isArray(condition.requestDomains) ? condition.requestDomains.length : 0;
    const excluded = Array.isArray(condition.excludedRequestDomains) ? condition.excludedRequestDomains.length : 0;
    return Math.max(1, domains) + excluded;
  };
  let blockedCountDNRRulesCache = null;
  const loadBlockedCountDNRRules = async () => {
    const rules = [];
    let header = null;
    for (let offset = 0; !header || offset < header.count; offset = rules.length) {
      const chunk = await sendQueuedNativeMessage({
        action: "getBlockedCountDNRRules",
        offset,
        limit: BLOCKED_COUNT_DNR_CHUNK_SIZE
      });
      if (!chunk || chunk.ok !== true) {
        throw new Error(chunk && chunk.error ? chunk.error : `Failed to load blocked-count DNR rules at ${offset}`);
      }
      const version = String(chunk.version || "");
      if (!header) {
        header = { enabled: chunk.enabled === true, version, count: Math.max(0, Number(chunk.count) || 0) };
        const cached = blockedCountDNRRulesCache;
        if (cached && cached.enabled === header.enabled && cached.version === version && cached.rules.length === header.count) {
          return cached;
        }
      } else if (version !== header.version) {
        throw new Error(`Blocked-count DNR rules changed while loading at ${offset}`);
      }
      if (header.count === 0) break;
      if (!Array.isArray(chunk.rules) || chunk.rules.length === 0) {
        throw new Error(`Blocked-count DNR rules ended early at ${offset}`);
      }
      rules.push(...chunk.rules);
    }
    if (rules.length !== header.count) {
      throw new Error(`Blocked-count DNR rule count mismatch: expected ${header.count}, got ${rules.length}`);
    }
    blockedCountDNRRulesCache = { ...header, rules };
    return blockedCountDNRRulesCache;
  };
  const loadRemoveParamDNRRules = async () => {
    const firstChunk = await sendQueuedNativeMessage({
      action: "getRemoveParamDNRRules",
      offset: 0,
      limit: REMOVE_PARAM_DNR_CHUNK_SIZE
    });
    if (!firstChunk || firstChunk.ok !== true) {
      throw new Error(firstChunk && firstChunk.error ? firstChunk.error : "Failed to load removeparam DNR rules");
    }
    const version = String(firstChunk.version || "");
    const count = Math.max(0, Number(firstChunk.count) || 0);
    if (removeParamDNRRulesCache && removeParamDNRVersion === version && removeParamDNRRulesCache.length === count) {
      return {
        version,
        count,
        ruleIdBase: Number(firstChunk.ruleIdBase) || 1500000,
        ruleIdLimit: Number(firstChunk.ruleIdLimit) || 1650000,
        rules: removeParamDNRRulesCache
      };
    }
    const rules = Array.isArray(firstChunk.rules) ? firstChunk.rules.slice() : [];
    for (let offset = REMOVE_PARAM_DNR_CHUNK_SIZE; offset < count; offset += REMOVE_PARAM_DNR_CHUNK_SIZE) {
      const chunk = await sendQueuedNativeMessage({
        action: "getRemoveParamDNRRules",
        offset,
        limit: REMOVE_PARAM_DNR_CHUNK_SIZE
      });
      if (!chunk || chunk.ok !== true) {
        throw new Error(chunk && chunk.error ? chunk.error : `Failed to load removeparam DNR rules at ${offset}`);
      }
      if (String(chunk.version || "") !== version) {
        throw new Error(`Removeparam DNR rules changed while loading at ${offset}`);
      }
      if (Array.isArray(chunk.rules)) {
        rules.push(...chunk.rules);
      }
    }
    if (rules.length !== count) {
      throw new Error(`Removeparam DNR rule count mismatch: expected ${count}, got ${rules.length}`);
    }
    removeParamDNRRulesCache = rules;
    removeParamDNRVersion = version;
    return {
      version,
      count,
      ruleIdBase: Number(firstChunk.ruleIdBase) || 1500000,
      ruleIdLimit: Number(firstChunk.ruleIdLimit) || 1650000,
      rules
    };
  };
  const legacySafariRemoveParamRule = rule => {
    if (!rule || !rule.condition) return rule;
    const condition = { ...rule.condition };

    // Accept cached/generated rules from builds that used the newer spelling.
    // `domains` is the compatibility representation wBlock now generates.
    if (Array.isArray(condition.initiatorDomains)) {
      condition.domains = condition.initiatorDomains;
      delete condition.initiatorDomains;
    }
    if (Array.isArray(condition.excludedInitiatorDomains)) {
      condition.excludedDomains = condition.excludedInitiatorDomains;
      delete condition.excludedInitiatorDomains;
    }

    if (Array.isArray(condition.excludedRequestDomains) && condition.excludedRequestDomains.length > 0) {
      // No exact pre-16.4 equivalent; dropping the scope would widen stripping.
      return null;
    }
    if (Array.isArray(condition.requestDomains) && condition.requestDomains.length > 0) {
      // A request-domain allow with no existing URL filter is safely expressible
      // as one host-anchored URL filter (used by disabled-site protection).
      if (rule.action && rule.action.type === "allow"
          && !condition.urlFilter && condition.requestDomains.length === 1) {
        condition.urlFilter = `||${condition.requestDomains[0]}^`;
        delete condition.requestDomains;
      } else {
        // `$to=` redirect scopes have no exact legacy equivalent. Skip them
        // rather than widening a removeparam rule beyond its intended target.
        return null;
      }
    }
    return { ...rule, condition };
  };
  const reportRedirectDNRStatus = async (installedRules) => {
    try {
      let hostAccess = false;
      try {
        // Safari answers false for "<all_urls>" even when every site is granted.
        hostAccess = await browser.permissions.contains({ origins: ["*://*/*"] });
      } catch {
        hostAccess = false;
      }
      let privateAccess = null;
      try {
        if (typeof browser.extension?.isAllowedIncognitoAccess === "function") {
          privateAccess = await browser.extension.isAllowedIncognitoAccess();
        }
      } catch {
        privateAccess = null;
      }
      const installedRedirects = installedRules.filter(rule =>
        rule && rule.action && rule.action.redirect && typeof rule.action.redirect.extensionPath === "string"
      ).length;
      const status = { installedRedirects, hostAccess, privateAccess, at: Date.now() };
      const stored = await browser.storage.local.get(REDIRECT_DNR_STATUS_REPORT_KEY);
      const lastReport = stored && stored[REDIRECT_DNR_STATUS_REPORT_KEY];
      const shouldReport = !lastReport
        || lastReport.installedRedirects !== installedRedirects
        || lastReport.hostAccess !== hostAccess
        || lastReport.privateAccess !== privateAccess
        || Date.now() - (lastReport.at || 0) >= REDIRECT_DNR_STATUS_REPORT_THROTTLE_MS;
      if (shouldReport) {
        // Priority path: a slow queued request (script updates wait up to
        // two minutes) must not hold this report until the page suspends.
        await sendPriorityNativeMessage({
          action: "reportRedirectDNRStatus",
          installedRedirects,
          hostAccess,
          privateAccess
        });
        await browser.storage.local.set({ [REDIRECT_DNR_STATUS_REPORT_KEY]: status });
      }
    } catch (error) {
      console.warn("[wBlock] Failed to report redirect DNR status:", error);
      logSupportDiagnostic({ event: "dnr_status_report_failed", error: String(error && error.message || error) });
    }
  };
  const prepareRemoveParamRulesForRuntime = rules => {
    const dnr = browser.declarativeNetRequest;
    const reported = Number(dnr && dnr.MAX_NUMBER_OF_DYNAMIC_AND_SESSION_RULES);
    const modernConditionSupport = Number.isFinite(reported) && reported > 0;
    let prepared = rules.slice();
    if (!modernConditionSupport) {
      const legacyRules = rules.map(legacySafariRemoveParamRule);
      const lostProtection = rules.some((rule, index) =>
        rule && rule.action && rule.action.type === "allow" && !legacyRules[index]);
      // Dropping a redirect narrows behavior; dropping its exception widens it.
      // Without an exact legacy exception, keep query parameters untouched.
      prepared = lostProtection ? [] : legacyRules.filter(Boolean);
    }
    return { prepared, reportedLimit: modernConditionSupport ? Math.floor(reported) : REMOVE_PARAM_DNR_OLD_SAFARI_FALLBACK_LIMIT };
  };
  const installRemoveParamDNRRules = async () => {
    if (!browser.declarativeNetRequest || typeof browser.declarativeNetRequest.updateDynamicRules !== "function") {
      return;
    }
    const loaded = await loadRemoveParamDNRRules();
    const { version, ruleIdBase, ruleIdLimit, rules } = loaded;
    const stored = await browser.storage.local.get(REMOVE_PARAM_DNR_STORAGE_KEY);
    const dynamicRules = typeof browser.declarativeNetRequest.getDynamicRules === "function"
      ? await browser.declarativeNetRequest.getDynamicRules()
      : [];
    const trackedRules = dynamicRules.filter(rule => rule && rule.id >= ruleIdBase && rule.id < ruleIdLimit);
    const trackedCountRules = dynamicRules.filter(rule => rule && rule.id >= BLOCKED_COUNT_DNR_ID_BASE && rule.id < BLOCKED_COUNT_DNR_ID_LIMIT);
    const unrelatedDynamicCount = Math.max(0, dynamicRules.length - trackedRules.length - trackedCountRules.length);
    const sessionRules = typeof browser.declarativeNetRequest.getSessionRules === "function"
      ? await browser.declarativeNetRequest.getSessionRules()
      : [];
    const { prepared, reportedLimit } = prepareRemoveParamRulesForRuntime(rules);
    const availableCapacity = Math.max(0, Math.min(
      ruleIdLimit - ruleIdBase,
      reportedLimit - unrelatedDynamicCount - sessionRules.length
    ));
    const protectiveRules = prepared.filter(rule => rule && rule.action && rule.action.type === "allow");
    const redirectRules = prepared.filter(rule => !rule || !rule.action || rule.action.type !== "allow");
    const installRules = protectiveRules.length > availableCapacity
      ? []
      : protectiveRules.concat(redirectRules.slice(0, availableCapacity - protectiveRules.length));
    // The count needs Safari 16.4's action count and modern rule conditions.
    // A failed load keeps whatever counting rules are already installed.
    let blockedCount = null;
    if (canDisplayActionCount && Number(browser.declarativeNetRequest.MAX_NUMBER_OF_DYNAMIC_AND_SESSION_RULES) > 0) {
      blockedCount = await loadBlockedCountDNRRules().catch(error => {
        console.warn("[wBlock] Failed to load blocked-count DNR rules:", error);
        return null;
      });
    }
    // Dropping counting rules only lowers the count, so they get what is left
    // of both the dynamic-rule quota and WebKit's compiled-rule budget.
    // WebKit's quota check counts the installed dynamic rules twice (current
    // plus updated), so the counting rules may only fill the quota minus
    // twice the others; that keeps every step below within the check.
    const otherDynamicCount = unrelatedDynamicCount + installRules.length;
    const countCapacity = Math.max(0, reportedLimit - sessionRules.length - 2 * otherDynamicCount - 100);
    let translatedRemaining = DNR_TRANSLATED_RULE_BUDGET
      - installRules.concat(sessionRules, dynamicRules.filter(rule => rule && !(rule.id >= ruleIdBase && rule.id < ruleIdLimit)
        && !(rule.id >= BLOCKED_COUNT_DNR_ID_BASE && rule.id < BLOCKED_COUNT_DNR_ID_LIMIT)))
        .reduce((sum, rule) => sum + translatedRuleCost(rule), 0);
    let installCountRules = !blockedCount ? trackedCountRules : [];
    if (blockedCount && blockedCount.enabled) {
      // Allows carry the filter-list exceptions. Without all of them a copy
      // could block what the content blockers allow, so then copy nothing.
      const allows = blockedCount.rules.filter(rule => rule && rule.action && rule.action.type === "allow");
      const allowCost = allows.reduce((sum, rule) => sum + translatedRuleCost(rule), 0);
      if (allows.length <= countCapacity && allowCost <= translatedRemaining) {
        installCountRules = allows.slice();
        translatedRemaining -= allowCost;
        for (const rule of blockedCount.rules) {
          if (installCountRules.length >= countCapacity) break;
          if (!rule || !rule.action || rule.action.type === "allow") continue;
          const cost = translatedRuleCost(rule);
          if (cost > translatedRemaining) continue;
          translatedRemaining -= cost;
          installCountRules.push(rule);
        }
      }
    }
    const countVersion = blockedCount ? `${blockedCount.enabled}:${blockedCount.version}` : null;
    const storedState = stored && stored[REMOVE_PARAM_DNR_STORAGE_KEY];
    const removeParamCurrent = storedState && typeof storedState === "object"
      && storedState.version === version
      && storedState.count === installRules.length
      && trackedRules.length === installRules.length;
    const countCurrent = !blockedCount || (storedState && typeof storedState === "object"
      && storedState.countVersion === countVersion
      && storedState.countCount === installCountRules.length
      && trackedCountRules.length === installCountRules.length);
    if (blockedCount) {
      await browser.declarativeNetRequest.setExtensionActionOptions({
        displayActionCountAsBadgeText: blockedCount.enabled
      }).catch(error => console.warn("[wBlock] Failed to set action count display:", error));
    }
    if (removeParamCurrent && countCurrent) {
      await reportRedirectDNRStatus(trackedRules);
      return;
    }
    // Counting rules come off first and go back on last: with them
    // installed, WebKit's doubled quota check would reject the removeparam
    // swap. Only the count is briefly missing in between.
    const replaceCountRules = !countCurrent || (!removeParamCurrent && trackedCountRules.length > 0);
    if (replaceCountRules && trackedCountRules.length > 0) {
      await browser.declarativeNetRequest.updateDynamicRules({
        removeRuleIds: trackedCountRules.map(rule => rule.id)
      });
    }
    if (!removeParamCurrent) {
      // One API call is one atomic ruleset replacement: validation/quota failure
      // leaves the previous complete set installed instead of a partial prefix.
      await browser.declarativeNetRequest.updateDynamicRules({
        removeRuleIds: trackedRules.map(rule => rule.id),
        addRules: installRules
      });
    }
    if (replaceCountRules && installCountRules.length > 0) {
      await browser.declarativeNetRequest.updateDynamicRules({ addRules: installCountRules });
    }
    await browser.storage.local.set({
      [REMOVE_PARAM_DNR_STORAGE_KEY]: {
        version,
        count: installRules.length,
        countVersion: countVersion !== null ? countVersion : storedState && storedState.countVersion,
        countCount: installCountRules.length
      }
    });
    await reportRedirectDNRStatus(installRules);
  };
  const removeParamURLFilterRegexCache = new Map();
  const dnrSeparatorPattern = "(?:[^A-Za-z0-9_.%-]|$)";
  const domainMatches = (host, domain) => {
    const normalizedHost = String(host || "").toLowerCase();
    const normalizedDomain = String(domain || "").toLowerCase();
    return normalizedHost === normalizedDomain || normalizedHost.endsWith(`.${normalizedDomain}`);
  };
  const urlFilterToRegex = urlFilter => {
    if (!urlFilter) return null;
    if (removeParamURLFilterRegexCache.has(urlFilter)) {
      return removeParamURLFilterRegexCache.get(urlFilter);
    }
    let source = String(urlFilter);
    let regexSource = "";
    if (source.startsWith("||")) {
      source = source.slice(2);
      let domainPart = "";
      while (domainPart.length < source.length && /[A-Za-z0-9._-]/.test(source[domainPart.length])) {
        domainPart += source[domainPart.length];
      }
      source = source.slice(domainPart.length);
      const escapedDomain = domainPart.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      regexSource = `^[a-z][a-z0-9+.-]*://([^/?#]*\\.)?${escapedDomain}`;
    }
    for (const char of source) {
      if (char === "*") {
        regexSource += ".*";
      } else if (char === "^") {
        regexSource += dnrSeparatorPattern;
      } else if (char === "|") {
        regexSource += "^";
      } else {
        regexSource += char.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      }
    }
    try {
      const regex = new RegExp(regexSource);
      removeParamURLFilterRegexCache.set(urlFilter, regex);
      return regex;
    } catch (_error) {
      removeParamURLFilterRegexCache.set(urlFilter, null);
      return null;
    }
  };
  const conditionMatchesTopLevelURL = (condition, url) => {
    if (!condition) return true;
    if (Array.isArray(condition.resourceTypes) && !condition.resourceTypes.includes("main_frame")) {
      return false;
    }
    if (condition.domainType) {
      return false;
    }
    const host = url.hostname.toLowerCase();
    if (Array.isArray(condition.requestDomains) && !condition.requestDomains.some(domain => domainMatches(host, domain))) {
      return false;
    }
    if (Array.isArray(condition.excludedRequestDomains) && condition.excludedRequestDomains.some(domain => domainMatches(host, domain))) {
      return false;
    }
    if (Array.isArray(condition.initiatorDomains) && condition.initiatorDomains.length > 0) {
      return false;
    }
    if (Array.isArray(condition.excludedInitiatorDomains) && condition.excludedInitiatorDomains.some(domain => domainMatches(host, domain))) {
      return false;
    }
    if (Array.isArray(condition.domains) && condition.domains.length > 0) {
      return false;
    }
    if (Array.isArray(condition.excludedDomains) && condition.excludedDomains.some(domain => domainMatches(host, domain))) {
      return false;
    }
    const regex = urlFilterToRegex(condition.urlFilter || "");
    return regex ? regex.test(url.href) : true;
  };
  const applyRemoveParamRuleToURL = (rule, url) => {
    const transform = rule && rule.action && rule.action.redirect && rule.action.redirect.transform;
    if (!transform) return false;
    if (transform.query === "") {
      if (!url.search) return false;
      url.search = "";
      return true;
    }
    const params = transform.queryTransform && Array.isArray(transform.queryTransform.removeParams)
      ? transform.queryTransform.removeParams
      : [];
    let changed = false;
    for (const param of params) {
      if (url.searchParams.has(param)) {
        url.searchParams.delete(param);
        changed = true;
      }
    }
    return changed;
  };
  const getCleanURLWithRemoveParamRules = async urlString => {
    if (!urlString || !/^https?:/i.test(urlString)) return urlString;
    // Removeparam rules only strip query parameters.
    if (!urlString.includes("?")) return urlString;
    const loaded = await loadRemoveParamDNRRules();
    if (!loaded.rules || loaded.rules.length === 0) return urlString;
    const originalURL = new URL(urlString);
    let url = new URL(urlString);
    const rules = loaded.rules.slice().sort((a, b) => (b?.priority ?? 0) - (a?.priority ?? 0));
    for (let pass = 0; pass < 8; pass += 1) {
      let changed = false;
      for (const rule of rules) {
        if (!rule || !rule.action || !conditionMatchesTopLevelURL(rule.condition, url)) {
          continue;
        }
        if (rule.action.type === "allow") {
          return originalURL.href;
        }
        if (rule.action.type === "redirect") {
          changed = applyRemoveParamRuleToURL(rule, url) || changed;
        }
      }
      if (!changed) break;
    }
    return url.href;
  };
  const scheduleInstallRemoveParamDNRRules = (force = false) => {
    const now = Date.now();
    if (!force && now - lastRemoveParamDNRCheck < REMOVE_PARAM_DNR_CHECK_INTERVAL_MS) {
      return removeParamDNRInstallPromise || Promise.resolve();
    }
    lastRemoveParamDNRCheck = now;
    if (!removeParamDNRInstallPromise) {
      removeParamDNRInstallPromise = installRemoveParamDNRRules().catch(error => {
        const errorMessage = String(error && error.message || error);
        console.error(`[wBlock] Failed to install removeparam DNR rules: ${errorMessage}`, error);
        logSupportDiagnostic({ event: "dnr_install_failed", error: errorMessage });
      }).finally(() => {
        removeParamDNRInstallPromise = null;
      });
    }
    return removeParamDNRInstallPromise;
  };
  if (browser.runtime.onInstalled) {
    browser.runtime.onInstalled.addListener(() => {
      clearDocumentStartSessionCache();
      scheduleInstallRemoveParamDNRRules(true);
    });
  }
  if (browser.runtime.onStartup) {
    browser.runtime.onStartup.addListener(() => {
      clearDocumentStartSessionCache();
      scheduleInstallRemoveParamDNRRules(true);
    });
  }
  /**
   * Warm up the native host as soon as the background page starts so the
   * extension process spawns and the filter engine is deserialized before
   * the first real page request needs it. Runs after hydration so a fresh
   * native engineTimestamp can validate (or drop) the restored cache.
   */
  const NATIVE_WARMUP_URL = "https://warmup.wblock.invalid/";
  const warmUpNativeHost = async () => {
    try {
      await requestConfigurationCoalesced({}, NATIVE_WARMUP_URL, undefined);
    } catch (error) {
      console.warn("[wBlock] Native host warm-up failed:", error);
    } finally {
      const key = cacheKey(NATIVE_WARMUP_URL, undefined);
      cache.delete(key);
      configValidatedAt.delete(key);
    }
  };
  configCacheHydration.then(warmUpNativeHost);
  scheduleInstallRemoveParamDNRRules(true);
  refreshActionStateForActiveTabs();
  // Start handling messages from content scripts.
  syncNoAutoplayScripts();
  syncGlobalPrivacyControl();
  browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
    scheduleInstallRemoveParamDNRRules(false);
    syncNoAutoplayScripts();
    syncGlobalPrivacyControl();
    if (!canRegisterNoAutoplay && request && request.type === MessageType.InitContentScript
      && sender && sender.tab && typeof sender.tab.id === "number" && Number.isSafeInteger(sender.frameId)) {
      isNoAutoplayActive().then(active => {
        if (active) injectNoAutoplay({ tabId: sender.tab.id, frameIds: [sender.frameId] });
      }, () => {});
    }
    // Keep Safari's response channel open until the native request finishes.
    Promise.resolve().then(() => handleMessages(request, sender)).then(sendResponse, error => {
      sendResponse({ ok: false, error: String(error && error.message ? error.message : error) });
    });
    return true;
  });
})(browser);
