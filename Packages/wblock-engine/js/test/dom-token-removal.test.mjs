import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';

const resources = new URL('../../../../wBlock Scripts (iOS)/Resources/scriptlets/', import.meta.url);
const tick = () => new Promise(resolve => setTimeout(resolve, 30));

function setup(name, args) {
  const dom = new JSDOM('<html><head></head><body><main></main></body></html>', {
    runScripts: 'outside-only', pretendToBeVisual: true,
  });
  const win = dom.window;
  win.Request = Request;
  win.fetch = fetch;
  win.CSS = { escape: value => value };
  let searches = 0;
  let scheduled = 0;
  const query = win.document.querySelectorAll.bind(win.document);
  win.document.querySelectorAll = (...args) => { searches++; return query(...args); };
  win.requestIdleCallback = callback => { scheduled++; return win.setTimeout(callback, 0); };
  win.cancelIdleCallback = win.clearTimeout;
  win.__wbeScriptletCalls = { [name]: [args] };
  win.eval(readFileSync(new URL(`${name}.js`, resources), 'utf8'));
  return { dom, win, document: win.document, counts: () => ({ searches, scheduled }) };
}

for (const [name, args] of [
  ['remove-class', ['didomi-popup-open', 'body.didomi-popup-open', 'stay']],
  ['remove-attr', ['class', 'div.wkwp-paywall', 'stay']],
]) {
  test(`${name} does not rescan the document or schedule work for unrelated DOM changes`, async () => {
    const env = setup(name, args);
    try {
      await tick();
      const before = env.counts();
      for (let i = 0; i < 5; i++) {
        env.document.querySelector('main').innerHTML = '<div class="todo"><span>text</span></div>'.repeat(50);
        await tick();
      }
      assert.deepEqual(env.counts(), before);
    } finally { env.dom.window.close(); }
  });
}

test('persistent class removal handles existing, added, and reclassified targets', async () => {
  const env = setup('remove-class', ['blocked|locked', '.overlay', 'stay']);
  try {
    const wrapper = env.document.createElement('section');
    wrapper.innerHTML = '<div class="overlay blocked locked"></div><div class="blocked"></div>';
    env.document.body.append(wrapper);
    await tick();
    assert.equal(wrapper.firstChild.className, 'overlay');
    assert.equal(wrapper.lastChild.className, 'blocked');
    wrapper.lastChild.classList.add('overlay');
    await tick();
    assert.equal(wrapper.lastChild.className, 'overlay');
    wrapper.firstChild.classList.add('locked');
    await tick();
    assert.equal(wrapper.firstChild.className, 'overlay');
  } finally { env.dom.window.close(); }
});

test('persistent attribute removal finds nested targets without touching other elements', async () => {
  const env = setup('remove-attr', ['class|style', 'div.wkwp-paywall', 'stay']);
  try {
    const wrapper = env.document.createElement('section');
    wrapper.innerHTML = '<div class="wkwp-paywall" style="color:red"></div><div class="keep" style="color:red"></div>';
    env.document.body.append(wrapper);
    await tick();
    assert.equal(wrapper.firstChild.hasAttribute('class'), false);
    assert.equal(wrapper.firstChild.hasAttribute('style'), false);
    assert.equal(wrapper.lastChild.className, 'keep');
  } finally { env.dom.window.close(); }
});

test('complex relational selectors retain the upstream whole-document path', async () => {
  const env = setup('remove-class', ['blocked', '.parent.active .child', 'stay']);
  try {
    env.document.body.innerHTML = '<section class="parent"><div class="child blocked"></div></section>';
    await tick();
    env.document.querySelector('section').classList.add('active');
    await tick();
    assert.equal(env.document.querySelector('.child').className, 'child');
  } finally { env.dom.window.close(); }
});

test('compound selectors follow id changes and preserve other attributes', async () => {
  const env = setup('remove-attr', ['data-lock|style', 'div#wall.overlay', 'stay']);
  try {
    const element = env.document.createElement('div');
    element.className = 'overlay';
    element.setAttribute('data-lock', 'locked');
    element.style.color = 'red';
    env.document.body.append(element);
    await tick();
    assert.equal(element.getAttribute('data-lock'), 'locked');
    element.id = 'wall';
    await tick();
    assert.equal(element.hasAttribute('data-lock'), false);
    assert.equal(element.hasAttribute('style'), false);
    assert.equal(element.className, 'overlay');
    element.setAttribute('data-lock', 'locked-again');
    await tick();
    assert.equal(element.hasAttribute('data-lock'), false);
  } finally { env.dom.window.close(); }
});
