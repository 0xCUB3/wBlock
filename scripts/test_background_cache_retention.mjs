// Exercise the shipped background runtime, not a reimplementation of its cache.
// Run: node scripts/test_background_cache_retention.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { performance } from 'node:perf_hooks';

for (const file of ['extension-src/background.js', 'wBlock Scripts (iOS)/Resources/background.js']) {
  const maps = [];
  class ObservedMap extends Map {
    constructor(...args) { super(...args); maps.push(this); }
  }
  const timers = new Set();
  const later = (fn, ms) => {
    const id = setTimeout(() => { timers.delete(id); fn(); }, ms);
    timers.add(id);
    return id;
  };
  const cancel = id => { timers.delete(id); clearTimeout(id); };
  const storage = {};
  let listener;
  let nativeActive = 0;
  let nativePeak = 0;
  let nativeCalls = 0;
  let listenerCount = 0;
  let revision = 1;
  const event = { addListener() { listenerCount++; } };
  const browser = {
    runtime: {
      onMessage: { addListener(fn) { listener = fn; listenerCount++; } },
      onStartup: event, onInstalled: event,
      getURL: file => `safari-web-extension://test/${file}`,
      connectNative: () => ({ onMessage: event, onDisconnect: event }),
      async sendNativeMessage(_id, request) {
        nativeCalls++;
        nativePeak = Math.max(nativePeak, ++nativeActive);
        await new Promise(resolve => setTimeout(resolve, 1));
        nativeActive--;
        if (request.action === 'getRemoveParamDNRRules') return { ok: true, version: 'test', count: 0, rules: [] };
        if (request.action === 'getBlockingState') return { disabled: false, paused: false };
        return { payload: { css: [`/*${request.payload?.url}: ${'x'.repeat(16384)}*/ .ad`],
          extendedCss: [], js: [], scriptlets: [], engineTimestamp: revision, disabled: false, paused: false } };
      }
    },
    storage: { local: {
      get: async () => structuredClone(storage),
      set: async items => Object.assign(storage, structuredClone(items)),
      remove: async key => { delete storage[key]; }
    } },
    tabs: { query: async () => [], get: async () => ({}), sendMessage: async () => ({}),
      onUpdated: event, onActivated: event, onCreated: event, onRemoved: event },
    scripting: { executeScript: async () => [{}], insertCSS: async () => {} },
    i18n: { getMessage: () => '' }
  };
  new Function('browser', 'window', 'self', 'Map', 'setTimeout', 'clearTimeout', readFileSync(file, 'utf8'))(
    browser, globalThis, globalThis, ObservedMap, later, cancel);
  const navigate = (index, frameId = 0) => {
    const url = `https://retention.example/navigation/${index}`;
    return listener({ type: 'InitContentScript' }, { url, frameId, tab: { id: 7, url: `https://retention.example/top/${index}` } });
  };
  const retained = () => maps.flatMap(map => [...map.values()].filter(value => Array.isArray(value?.css)));
  const samples = [];
  try {
    await new Promise(resolve => setTimeout(resolve, 20));
    const initialListeners = listenerCount;
    for (let batch = 0; batch < 6; batch++) {
      const start = performance.now();
      for (let i = batch * 256; i < (batch + 1) * 256; i += 8) {
        await Promise.all(Array.from({ length: 8 }, (_, frame) => navigate(i + frame, frame)));
      }
      samples.push({ navigations: (batch + 1) * 256, entries: retained().length,
        payloadBytes: retained().reduce((n, value) => n + JSON.stringify(value).length, 0),
        ms: Math.round(performance.now() - start), nativeActive, timers: timers.size, listeners: listenerCount });
    }
    console.log(JSON.stringify({ file, samples, nativePeak, nativeCalls }));
    assert.ok(samples.every(sample => sample.entries === 128), 'configuration retention must be bounded across distinct top/frame URLs');
    assert.equal(listenerCount, initialListeners, 'navigation must not register background listeners');
    assert.equal(nativeActive, 0, 'completed navigations drain native requests');
    assert.ok(maps.every(map => [...map.values()].every(value => !(value instanceof Promise))),
      'completed navigation promises must leave the coalescing maps');
    assert.ok(retained().some(value => value.css[0].includes('/navigation/1535:')),
      'recent frame configurations remain reusable');
    assert.ok(!retained().some(value => value.css[0].includes('/navigation/0:')),
      'old configurations are evicted rather than dropping new cache entries');
    assert.ok(timers.size <= 1, 'only the debounced persistence timer remains');
    await new Promise(resolve => setTimeout(resolve, 1100));
    const persisted = storage.wblockConfigCacheV1;
    assert.ok(persisted.entries.length <= 40);
    assert.ok(persisted.entries.every(([key]) => key.endsWith('#')), 'only top frames persist');
    assert.equal(timers.size, 0);
    revision++;
    await navigate('new-engine');
    assert.equal(retained().length, 1, 'engine changes discard all old configurations');
    await listener({ action: 'wblock:clearCache' }, { url: 'https://retention.example/', frameId: 0, tab: { id: 7 } });
    assert.equal(retained().length, 0, 'explicit invalidation drops retained payloads');
  } finally {
    for (const id of timers) clearTimeout(id);
  }
}
console.log('PASS: background configuration retention stays bounded');
