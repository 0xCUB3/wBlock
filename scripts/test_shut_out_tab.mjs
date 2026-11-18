// Run: node scripts/test_shut_out_tab.mjs
// Safari shuts the extension out of the tab it shows after a profile switch.
// That page moves to a new tab, once per background.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const root = new URL('../', import.meta.url);
const event = () => ({ listeners: [], addListener(fn) { this.listeners.push(fn); } });
const settle = async () => {
  for (let i = 0; i < 20; i++) await new Promise(resolve => setImmediate(resolve));
};

const load = (file, { probe = null, allowed = true, refused = true } = {}) => {
  const created = [];
  const removed = [];
  const browser = {
    runtime: {
      onMessage: event(), onInstalled: event(), onStartup: event(),
      sendNativeMessage: async () => ({ ok: true, rules: [], userScripts: [] })
    },
    storage: { local: { get: async () => ({}), set: async () => {}, remove: async () => {} } },
    tabs: {
      query: async () => [],
      get: async id => ({ id, url: 'https://example.com/' }),
      sendMessage: async () => { if (!probe) throw new Error('Could not establish connection'); return probe; },
      create: async props => { created.push(props); return { id: 100 + created.length, ...props }; },
      remove: async id => { removed.push(id); },
      onUpdated: event(), onActivated: event(), onCreated: event(), onRemoved: event()
    },
    permissions: { contains: async () => allowed },
    scripting: {
      executeScript: async () => {
        if (refused) throw new Error('Invalid call to scripting.executeScript(). Could not execute script on this tab.');
        return [{ result: true }];
      }
    },
    action: {
      enable: async () => {}, disable: async () => {}, setIcon: async () => {}, setPopup: async () => {},
      setTitle: async () => {}, setBadgeText: async () => {}, setBadgeBackgroundColor: async () => {}
    },
    i18n: { getMessage: () => '' }
  };
  new Function('browser', 'window', 'self', readFileSync(new URL(file, root), 'utf8'))(browser, globalThis, globalThis);
  const complete = async tab => {
    for (const listener of browser.tabs.onUpdated.listeners) listener(tab.id, { status: 'complete' }, tab);
    await settle();
  };
  return { created, removed, complete };
};

const tab = { id: 7, index: 2, active: true, windowId: 1, url: 'https://example.com/page' };

for (const file of ['extension-src/background.js', 'wBlock Scripts (iOS)/Resources/background.js']) {
  {
    const page = load(file);
    await settle();
    await page.complete(tab);
    assert.deepEqual(page.created, [{ url: tab.url, index: 3, active: true, windowId: 1 }], `${file}: a shut-out page moves to a new tab`);
    assert.deepEqual(page.removed, [7], `${file}: the shut-out tab closes`);
    await page.complete({ ...tab, id: 8 });
    assert.equal(page.created.length, 1, `${file}: only one tab is replaced per background`);
  }
  for (const [label, options] of [
    ['content scripts answered', { probe: { ok: true } }],
    ['site not allowed', { allowed: false }],
    ['executeScript accepted', { refused: false }]
  ]) {
    const page = load(file, options);
    await settle();
    await page.complete(tab);
    assert.equal(page.created.length + page.removed.length, 0, `${file}: ${label} leaves the tab alone`);
  }
  {
    const page = load(file);
    await settle();
    await page.complete({ ...tab, url: 'about:blank' });
    assert.equal(page.created.length, 0, `${file}: non-web pages are left alone`);
    await page.complete({ ...tab, incognito: true });
    assert.equal(page.created.length, 0, `${file}: private tabs never reopen outside Private Browsing`);
  }
}

console.log('All shut-out tab checks passed');
