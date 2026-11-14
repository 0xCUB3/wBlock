import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { JSDOM } from 'jsdom';

for (const file of ['../procedural.js', '../../../../wBlock Scripts (iOS)/Resources/procedural.js']) {
  for (const action of [undefined, { type: 'remove' }]) {
    for (const matching of [false, true]) {
      test(`${file}: detached shadow roots are released, action=${action?.type || 'hide'}, matching=${matching}`, () => {
        const dom = new JSDOM('<!doctype html><body></body>', { runScripts: 'outside-only' });
        const w = dom.window, sets = [], frames = [];
        let tick;
        w.Set = class extends w.Set { constructor(...args) { super(...args); sets.push(this); } };
        w.requestAnimationFrame = fn => frames.push(fn);
        w.setTimeout = () => 1;
        w.setInterval = fn => { tick = fn; return 1; };
        w.clearInterval = () => {};
        w.eval(readFileSync(new URL(file, import.meta.url), 'utf8'));
        const flush = () => { tick(); while (frames.length) frames.shift()(); };
        const rules = [JSON.stringify({ selector: [
          { type: 'css-selector', arg: '.host' }, { type: 'shadow', arg: '.ad' },
        ], action })];
        try {
          w.wbeProcedural.apply(rules);
          let tracked;
          for (let batch = 0; batch < 4; batch++) {
            const hosts = [];
            for (let i = 0; i < 100; i++) {
              const host = w.document.createElement('section'); host.className = 'host';
              const root = host.attachShadow({ mode: 'open' });
              root.innerHTML = matching ? '<div class="ad"></div>' : '<div class="content"></div>';
              w.document.body.append(host); hosts.push(host);
            }
            flush();
            tracked ||= sets.find(set => set.has(hosts[0].shadowRoot));
            assert.ok(tracked, 'the runtime tracks connected roots for observation');
            assert.equal(tracked.size, 100);
            if (matching) assert.equal(hosts[0].shadowRoot.querySelector('.ad') === null, action?.type === 'remove');
            for (const host of hosts) host.remove();
            flush();
            assert.equal(tracked.size, 0, 'detached roots must not accumulate across passes');
            for (const host of hosts) assert.equal(host.shadowRoot.querySelector('style'), null);
            const host = hosts[0]; host.shadowRoot.innerHTML = '<div class="ad"></div>';
            w.document.body.append(host); flush();
            assert.ok(tracked.has(host.shadowRoot), 'reattached roots are rediscovered');
            const ad = host.shadowRoot.querySelector('.ad');
            if (action?.type === 'remove') assert.equal(ad, null);
            else assert.ok(ad.getAttributeNames().some(name => name.startsWith('data-wbe-')));
            host.remove(); flush(); assert.equal(tracked.size, 0);
          }
        } finally { w.wbeProcedural.apply([], { observe: false }); w.close(); }
      });
    }
  }
}
