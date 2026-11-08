import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../extension-src/background.js', import.meta.url), 'utf8');
const start = source.indexOf('  const popupCandidates = new Map();');
const end = source.indexOf('  const pendingConfigurationRequests', start);
const listeners = {};
const tabs = new Map([[1, { id: 1, url: 'https://example.com/page#section' }]]);
const removed = [];
const requests = [];
let response = { popup_blocked: true };
let beforeResponse = () => {};
const event = name => ({ addListener(fn) { listeners[name] = fn; } });
vm.runInNewContext(source.slice(start, end), {
  browser: { tabs: {
    get: async id => tabs.get(id), remove: async id => removed.push(id),
    onCreated: event('created'), onUpdated: event('updated'), onRemoved: event('removed'),
  } },
  requestConfiguration: async (_request, url) => { requests.push(url); beforeResponse(); return response; },
});
const flush = () => new Promise(resolve => setImmediate(resolve));
// Safari's created event omits openerTabId; tabs.get reports it.
async function create(id, url, openerTabId) {
  tabs.set(id, { id, url, openerTabId }); listeners.created({ id, url }); await flush();
}
await create(2, 'https://ads.test/', undefined);
assert.deepEqual(removed, [], 'ordinary navigation has no opener and is untouched');
await create(3, 'about:blank', 1);
assert.deepEqual(removed, [], 'blank popup waits for its target');
tabs.get(3).url = 'https://ads.test/';
listeners.updated(3, { url: 'https://ads.test/' }); await flush();
assert.deepEqual(removed, [3]);
assert.equal(requests[0], 'wbe-popup-https://example.com/page#https://ads.test/');
for (const state of [{ disabled: true }, { paused: true }, { popup_blocked: false }]) {
  response = { popup_blocked: true, ...state };
  await create(4, 'https://ads.test/', 1);
  assert.deepEqual(removed, [3], JSON.stringify(state));
}
response = { popup_blocked: true };
beforeResponse = () => { tabs.get(5).url = 'https://news.test/'; };
await create(5, 'https://ads.test/', 1);
assert.deepEqual(removed, [3], 'navigation racing native lookup is preserved');
console.log('PASS popup creation, delayed URL, page disable, pause and navigation race');
// uBO keeps a popup candidate for 10 s and tests every URL it reaches, so a
// popup that passes through an unblocked redirector is still closed.
response = { popup_blocked: false };
beforeResponse = () => {};
await create(6, 'about:blank', 1);
tabs.get(6).url = 'https://redirect.test/';
listeners.updated(6, { url: 'https://redirect.test/' }); await flush();
response = { popup_blocked: true };
tabs.get(6).url = 'https://ads.test/';
listeners.updated(6, { url: 'https://ads.test/' }); await flush();
assert.deepEqual(removed, [3, 6], 'redirected popup is tested again');
// A redirect that lands while the first lookup is in flight is tested too.
beforeResponse = () => {
  beforeResponse = () => {};
  tabs.get(7).url = 'https://ads.test/landing';
  listeners.updated(7, { url: 'https://ads.test/landing' });
};
await create(7, 'https://ads.test/', 1); await flush();
assert.deepEqual(removed, [3, 6, 7], 'redirect racing the lookup is tested');
// The opener is judged by the page that opened the popup, even if it navigates
// away before the popup reaches its URL.
await create(8, 'about:blank', 1);
tabs.get(1).url = 'https://elsewhere.test/';
tabs.get(8).url = 'https://ads.test/';
listeners.updated(8, { url: 'https://ads.test/' }); await flush();
assert.equal(requests.at(-1), 'wbe-popup-https://example.com/page#https://ads.test/');
console.log('PASS popup redirects are tested again against the original opener');
