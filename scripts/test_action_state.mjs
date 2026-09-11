// Run: node scripts/test_action_state.mjs
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = new URL('../', import.meta.url);
const resources = new URL('wBlock Scripts (iOS)/Resources/', root);
const event = () => ({ listeners: [], addListener(fn) { this.listeners.push(fn); } });
const settle = async () => {
  for (let i = 0; i < 10; i++) await new Promise(resolve => setImmediate(resolve));
};

for (const file of ['extension-src/background.js', 'wBlock Scripts (iOS)/Resources/background.js']) {
  const tabs = [{ id: 1, url: 'https://example.com/' }, { id: 2, url: 'https://other.example/' }];
  const disabledHosts = new Set();
  let paused = false;
  const states = new Map();
  const state = id => {
    if (!states.has(id)) states.set(id, {});
    return states.get(id);
  };
  const storage = {};
  const browser = {
    runtime: {
      onMessage: event(), onInstalled: event(), onStartup: event(),
      sendNativeMessage: async (_app, message) => {
        if (message.action === 'getBlockingPausedState') return { paused };
        if (message.action === 'getSiteDisabledState') return { disabled: disabledHosts.has(message.host) };
        if (message.action === 'getRemoveParamDNRRules') return { ok: true, version: 'test', rules: [], count: 0 };
        return { ok: true, payload: { css: [], extendedCss: [], js: [], scriptlets: [], engineTimestamp: 1 } };
      }
    },
    storage: { local: {
      get: async () => ({ ...storage }),
      set: async values => Object.assign(storage, values),
      remove: async key => { delete storage[key]; }
    } },
    tabs: {
      query: async () => tabs,
      get: async id => tabs.find(tab => tab.id === id),
      onUpdated: event(), onActivated: event(), onCreated: event(), onRemoved: event()
    },
    action: {
      enable: async id => { state(id).enabled = true; },
      disable: async id => { state(id).enabled = false; },
      setIcon: async ({ tabId, path }) => { state(tabId).icon = path; },
      setPopup: async ({ tabId, popup }) => { state(tabId).popup = popup; },
      setTitle: async ({ tabId, title }) => { state(tabId).title = title; },
      setBadgeText: async ({ tabId, text }) => { state(tabId).badge = text; },
      setBadgeBackgroundColor: async () => {}
    },
    i18n: { getMessage: () => '' }
  };
  new Function('browser', 'window', 'self', readFileSync(new URL(file, root), 'utf8'))(browser, globalThis, globalThis);
  await settle();
  const check = (id, disabled, supported = true, title = '') => {
    const actual = state(id);
    assert.equal(actual.enabled, supported, 'site disable must leave the popup accessible');
    assert.equal(actual.popup, supported ? 'pages/popup/popup.html' : '');
    assert.equal(actual.title, `wBlock Scripts${title ? ` — ${title}` : ''}`);
    for (const size of [48, 96, 128, 256, 512]) {
      const expected = `assets/images/icon-${disabled ? 'disabled-' : ''}${size}.png`;
      assert.equal(actual.icon[size], expected);
      assert.ok(existsSync(fileURLToPath(new URL(expected, resources))), expected);
    }
  };
  const refresh = async () => {
    const result = await browser.runtime.onMessage.listeners[0]({ action: 'wblock:clearCache' }, {});
    assert.equal(result.ok, true);
  };
  check(1, false);
  check(2, false);
  disabledHosts.add('example.com');
  await refresh();
  check(1, true, true, 'Disabled');
  check(2, false);
  paused = true;
  await refresh();
  check(1, true, true, 'Paused');
  check(2, true, true, 'Paused');
  assert.equal(state(2).badge, 'II');
  paused = false;
  await refresh();
  check(1, true, true, 'Disabled');
  check(2, false);
  assert.equal(state(2).badge, '');
  disabledHosts.clear();
  await refresh();
  check(1, false);
  tabs[0].url = 'about:blank';
  for (const listener of browser.tabs.onUpdated.listeners) listener(1, { url: tabs[0].url }, tabs[0]);
  await settle();
  check(1, true, false, 'Unsupported');
  tabs[0].url = 'https://example.com/';
  for (const listener of browser.tabs.onActivated.listeners) await listener({ tabId: 1 });
  check(1, false);
  console.log(`PASS: ${file}: startup, per-site disable/re-enable, tab isolation, pause/resume, unsupported navigation, activation`);
}
