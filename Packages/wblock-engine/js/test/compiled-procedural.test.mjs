import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { JSDOM } from 'jsdom';

const root = new URL('../../', import.meta.url).pathname;
if (!process.env.WBE_BIN) execFileSync('cargo', ['build', '--quiet', '--manifest-path', root + 'Cargo.toml', '--bin', 'wbe']);
const binary = process.env.WBE_BIN || root + 'target/debug/wbe';
const source = readFileSync(root + 'js/procedural.js', 'utf8');
const compile = text => {
  const dir = mkdtempSync(join(tmpdir(), 'wbe-dom-'));
  writeFileSync(join(dir, 'list'), text);
  try {
    const native = JSON.parse(execFileSync(binary, ['compile', '--runtime-out', join(dir, 'runtime'), join(dir, 'list')], { stdio: ['ignore', 'pipe', 'pipe'] }));
    execFileSync(binary, ['engine-build', '--out', join(dir, 'engine'), join(dir, 'runtime')], { stdio: 'pipe' });
    const page = url => JSON.parse(execFileSync(binary, ['lookup', join(dir, 'engine'), url], { stdio: ['ignore', 'pipe', 'pipe'] }));
    return { native, page, close: () => rmSync(dir, { recursive: true }) };
  } catch (error) { rmSync(dir, { recursive: true }); throw error; }
};

test('production compiler and DOM runtime agree on nested chains and property conditions', () => {
  const built = compile('example.com##section:has(> div p:has-text(Ad)):not(.keep)\nexample.com##img:matches-property(naturalWidth=300)\nexample.com##div:matches-media((min-width: 1200px)):style(color: red)');
  const dom = new JSDOM('<section id="ad"><div><p>Ad</p></div></section><section class="keep" id="keep"><div><p>Ad</p></div></section><img id="image"><div id="media"></div>', { url: 'https://example.com/', runScripts: 'outside-only' });
  try {
    const page = built.page('https://example.com/');
    assert.deepEqual(page.hide, []);
    assert.equal(page.procedural.length, 3);
    Object.defineProperty(dom.window.document.querySelector('img'), 'naturalWidth', { value: 300 });
    dom.window.matchMedia = () => ({ matches: false, addEventListener() {}, removeEventListener() {} });
    dom.window.eval(source);
    dom.window.wbeProcedural.apply(page.procedural, { observe: false });
    const marked = id => dom.window.document.getElementById(id).getAttributeNames().some(name => name.startsWith('data-wbe-'));
    assert.equal(marked('ad'), true);
    assert.equal(marked('keep'), false);
    assert.equal(marked('image'), true);
    assert.equal(marked('media'), false);
  } finally { dom.window.close(); built.close(); }
});

test('compiled shadow chains style open roots and observe their mutations', async () => {
  const built = compile('example.com##article:shadow(div):has(:shadow(span:has-text(Ad)))');
  // Nested procedural conditions live outside shadow(), whose argument is CSS.
  assert.deepEqual(built.page('https://example.com/').procedural, []);
  built.close();
  const rules = compile('example.com##article:shadow(div):has(:shadow(span):has-text(Ad))');
  const dom = new JSDOM('<article></article>', { url: 'https://example.com/', runScripts: 'outside-only', pretendToBeVisual: true });
  try {
    const outer = dom.window.document.querySelector('article').attachShadow({ mode: 'open' });
    const host = dom.window.document.createElement('div'); outer.append(host);
    const inner = host.attachShadow({ mode: 'open' });
    inner.innerHTML = '<span>Ad</span>';
    dom.window.eval(source);
    const page = rules.page('https://example.com/');
    assert.equal(page.procedural.length, 1);
    dom.window.wbeProcedural.apply(page.procedural);
    const marked = () => host.getAttributeNames().some(name => name.startsWith('data-wbe-'));
    assert.equal(marked(), true);
    assert.match(outer.querySelector('style').textContent, /display: none !important/);
    inner.querySelector('span').firstChild.data = 'News';
    await new Promise(resolve => setTimeout(resolve, 150));
    assert.equal(marked(), false);
  } finally { dom.window.wbeProcedural.apply([], { observe: false }); dom.window.close(); rules.close(); }
});

test('genericblock exempts generic network requests while preserving specific blocks and cosmetics', () => {
  const built = compile('||ads.test^\n||specific.test^$domain=example.com\n@@||example.com^$genericblock\nexample.com##.ad\n||important.test^$important');
  try {
    const decide = (host, top, type) => {
      let blocked = false;
      const hides = [];
      for (const { trigger: t, action: a } of built.native) {
        if (!new RegExp(t['url-filter']).test(`https://${host}/`)) continue;
        if (t['resource-type'] && !t['resource-type'].includes(type)) continue;
        if (t['unless-domain']?.some(d => top === d.replace(/^\*/, ''))) continue;
        if (t['if-domain'] && !t['if-domain'].some(d => top === d.replace(/^\*/, ''))) continue;
        if (a.type === 'block') blocked = true;
        if (a.type === 'ignore-previous-rules') { blocked = false; hides.length = 0; }
        if (a.type === 'css-display-none') hides.push(a.selector);
      }
      return { blocked, hides };
    };
    assert.equal(decide('ads.test', 'example.com', 'script').blocked, false);
    assert.equal(decide('ads.test', 'other.com', 'script').blocked, true);
    assert.equal(decide('specific.test', 'example.com', 'script').blocked, true);
    assert.equal(decide('important.test', 'example.com', 'script').blocked, true);
    // Site hides are the runtime's; $genericblock leaves them in place.
    assert.deepEqual(built.page('https://example.com/').hide, ['.ad']);
  } finally { built.close(); }
});

test('genericblock badfilter restores generic blocking without disabling cosmetic exceptions', () => {
  const built = compile('||ads.test^\n@@||example.com^$genericblock\n@@||example.com^$genericblock,badfilter\n@@||other.com^$generichide');
  try {
    const block = built.native.find(rule => rule.action.type === 'block');
    assert.equal(block.trigger['unless-domain'], undefined);
  } finally { built.close(); }
});

test('popup lookups preserve exceptions and scope blocks by the opener tab', () => {
  const built = compile('||ads.test^$popup\n||scoped.test^$popup,domain=example.com\n@@||ads.test/allowed$popup\n||ads.test/forced$popup,important\nexample.com#@#+js()\n@@||exempt.com^$genericblock');
  try {
    const lookup = (source, target) => built.page(`wbe-popup-https://${source}/#https://${target}`).popup_blocked;
    assert.ok(built.native.every(rule => rule.action.type !== 'block'));
    assert.equal(lookup('example.com', 'ads.test/'), true);
    assert.equal(lookup('other.com', 'ads.test/'), true);
    assert.equal(lookup('example.com', 'scoped.test/'), true);
    assert.equal(lookup('other.com', 'scoped.test/'), false);
    assert.equal(lookup('example.com', 'ads.test/allowed'), false);
    assert.equal(lookup('example.com', 'ads.test/forced'), true);
    assert.equal(lookup('exempt.com', 'ads.test/'), false);
    assert.equal(lookup('exempt.com', 'ads.test/forced'), true);
    assert.equal(built.page('https://ads.test/').popup_blocked, undefined);
    assert.equal(built.page('https://example.com/#wbe-popup=https://ads.test/').popup_blocked, undefined);
  } finally { built.close(); }
});
