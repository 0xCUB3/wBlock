import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';

const SRC = readFileSync(new URL('../procedural.js', import.meta.url), 'utf8');

// Loads procedural.js into a fresh jsdom window so its globals are the page's globals.
const setup = (html, url = 'https://example.com/') => {
  const dom = new JSDOM(html, { url, runScripts: 'outside-only', pretendToBeVisual: true });
  dom.window.eval(SRC);
  const { document } = dom.window;
  return { dom, document, api: dom.window.wbeProcedural, win: dom.window };
};

const op = (type, arg) => ({ type, arg });
const filt = (selector, action) => JSON.stringify(action ? { selector, action } : { selector });
const act = (type, arg) => (arg === undefined ? { type } : { type, arg });

const isHidden = (win, el) => win.getComputedStyle(el).display === 'none';
const isMarked = (el) => [...el.attributes].some((a) => a.name.startsWith('data-wbe-'));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

describe('css-selector', () => {
  test('first operator hides matches through a generated attribute, not inline style', () => {
    const { document, api, win } = setup('<div id="a" class="ad"></div><div id="b"></div>');
    api.apply([filt([op('css-selector', '.ad')])]);
    const a = document.getElementById('a');
    assert.equal(isHidden(win, a), true);
    assert.equal(a.getAttribute('style'), null);
    assert.equal(isHidden(win, document.getElementById('b')), false);
    assert.equal(document.querySelectorAll('style').length, 1);
  });

  test('leading space is a descendant search from the previous operator', () => {
    const { document, api, win } = setup(
      '<div class="box" id="x"><span class="t" id="in">hi</span></div><span class="t" id="out">hi</span>',
    );
    api.apply([filt([op('css-selector', '.box'), op('has-text', 'hi'), op('css-selector', ' .t')])]);
    assert.equal(isHidden(win, document.getElementById('in')), true);
    assert.equal(isHidden(win, document.getElementById('out')), false);
    assert.equal(isHidden(win, document.getElementById('x')), false);
  });

  test('leading > selects children of the previous match', () => {
    const { document, api, win } = setup(
      '<div class="box"><p id="child"></p><section><p id="grand"></p></section></div>',
    );
    api.apply([filt([op('css-selector', '.box'), op('css-selector', '> p')])]);
    assert.equal(isHidden(win, document.getElementById('child')), true);
    assert.equal(isHidden(win, document.getElementById('grand')), false);
  });

  test('leading + selects only the next element sibling', () => {
    const { document, api, win } = setup(
      '<h2 id="h">x</h2><p id="next"></p><p id="later"></p>',
    );
    api.apply([filt([op('css-selector', 'h2'), op('css-selector', '+ p')])]);
    assert.equal(isHidden(win, document.getElementById('next')), true);
    assert.equal(isHidden(win, document.getElementById('later')), false);
  });

  test('leading ~ selects following siblings only', () => {
    const { document, api, win } = setup(
      '<div id="before" class="c"></div><h2 id="h">x</h2><div id="after" class="c"></div>',
    );
    api.apply([filt([op('css-selector', 'h2'), op('css-selector', '~ .c')])]);
    assert.equal(isHidden(win, document.getElementById('after')), true);
    assert.equal(isHidden(win, document.getElementById('before')), false);
  });

  test('an invalid selector disables only that filter', () => {
    const { document, api, win } = setup('<div id="a" class="ad"></div>');
    api.apply([filt([op('css-selector', '[[[')]), filt([op('css-selector', '.ad')])]);
    assert.equal(isHidden(win, document.getElementById('a')), true);
  });
});

describe('has-text', () => {
  const html = '<p id="hit">Anzeige hier</p><p id="miss">Nachricht</p>';

  test('plain text is a substring match', () => {
    const { document, api, win } = setup(html);
    api.apply([filt([op('css-selector', 'p'), op('has-text', 'Anzeige')])]);
    assert.equal(isHidden(win, document.getElementById('hit')), true);
    assert.equal(isHidden(win, document.getElementById('miss')), false);
  });

  test('regex literal with flags', () => {
    const { document, api, win } = setup(html);
    api.apply([filt([op('css-selector', 'p'), op('has-text', '/ANZEIGE/i')])]);
    assert.equal(isHidden(win, document.getElementById('hit')), true);
    assert.equal(isHidden(win, document.getElementById('miss')), false);
  });

  test('regex alternation', () => {
    const { document, api, win } = setup('<p id="a">Info</p><p id="b">Hallo</p>');
    api.apply([filt([op('css-selector', 'p'), op('has-text', '/Anzeige|Info/')])]);
    assert.equal(isHidden(win, document.getElementById('a')), true);
    assert.equal(isHidden(win, document.getElementById('b')), false);
  });

  test('brackets in plain text are literal', () => {
    const { document, api, win } = setup('<div id="a">x [Anzeige] y</div><div id="b">Anzeige</div>');
    api.apply([filt([op('css-selector', 'div'), op('has-text', '[Anzeige]')])]);
    assert.equal(isHidden(win, document.getElementById('a')), true);
    assert.equal(isHidden(win, document.getElementById('b')), false);
  });

  test('an invalid regex drops only that filter', () => {
    const { document, api, win } = setup('<p id="a">x</p>');
    api.apply([filt([op('css-selector', 'p'), op('has-text', '/(/')]), filt([op('css-selector', 'p')])]);
    assert.equal(isHidden(win, document.getElementById('a')), true);
  });
});

describe('matches-attr', () => {
  test('name-only regex', () => {
    const { document, api, win } = setup('<a id="a" data-ref="1"></a><a id="b" title="x"></a>');
    api.apply([filt([op('css-selector', 'a'), op('matches-attr', '/-h?ref/')])]);
    assert.equal(isHidden(win, document.getElementById('a')), true);
    assert.equal(isHidden(win, document.getElementById('b')), false);
  });

  test('name=value is exact on both sides', () => {
    const { document, api, win } = setup(
      '<div id="a" role="dialog"></div><div id="b" role="dialog-x"></div><div id="c" role="menu"></div>',
    );
    api.apply([filt([op('css-selector', 'div'), op('matches-attr', 'role=dialog')])]);
    assert.equal(isHidden(win, document.getElementById('a')), true);
    assert.equal(isHidden(win, document.getElementById('b')), false);
    assert.equal(isHidden(win, document.getElementById('c')), false);
  });

  test('value regex', () => {
    const { document, api, win } = setup('<div id="a" data-x="v9"></div><div id="b" data-x="w"></div>');
    api.apply([filt([op('css-selector', 'div'), op('matches-attr', 'data-x=/^v\\d$/')])]);
    assert.equal(isHidden(win, document.getElementById('a')), true);
    assert.equal(isHidden(win, document.getElementById('b')), false);
  });
});

describe('matches-css', () => {
  test('exact value and regex value on computed style', () => {
    const { document, api } = setup(
      '<div id="a" style="display: none"></div><div id="b" style="display: block"></div>',
    );
    api.apply([filt([op('css-selector', 'div'), op('matches-css', 'display: none')])]);
    assert.equal(isMarked(document.getElementById('a')), true);
    assert.equal(isMarked(document.getElementById('b')), false);
    api.apply([filt([op('css-selector', 'div'), op('matches-css', 'display: /^blo/')])]);
    assert.equal(isMarked(document.getElementById('a')), false);
    assert.equal(isMarked(document.getElementById('b')), true);
  });

  test('exact value does not match a substring', () => {
    const { document, api } = setup('<div id="a" style="display: block"></div>');
    api.apply([filt([op('css-selector', 'div'), op('matches-css', 'display: bloc')])]);
    assert.equal(isMarked(document.getElementById('a')), false);
  });

  test('matches-css-before reads the ::before pseudo element', () => {
    const { document, api, win } = setup(
      '<div id="a"></div><div id="b"></div>',
    );
    const real = win.getComputedStyle;
    win.getComputedStyle = (el, pseudo) => {
      if (pseudo !== '::before') return real(el, pseudo);
      return { getPropertyValue: (n) => (el.id === 'a' && n === 'content' ? '"Anzeige"' : '') };
    };
    api.apply([filt([op('css-selector', 'div'), op('matches-css-before', 'content:/Anzeige/i')])]);
    assert.equal(isMarked(document.getElementById('a')), true);
    assert.equal(isMarked(document.getElementById('b')), false);
  });

  test('matches-css-after reads the ::after pseudo element', () => {
    const { document, api, win } = setup('<div id="a"></div>');
    const real = win.getComputedStyle;
    const seen = [];
    win.getComputedStyle = (el, pseudo) => {
      if (pseudo !== '::after') return real(el, pseudo);
      seen.push(pseudo);
      return { getPropertyValue: () => 'x' };
    };
    api.apply([filt([op('css-selector', 'div'), op('matches-css-after', 'content: x')])]);
    assert.deepEqual(seen, ['::after']);
    assert.equal(isMarked(document.getElementById('a')), true);
  });
});

describe('matches-path', () => {
  const url = 'https://example.com/marketplace?tab=1';

  test('applies the chain only when the path matches', () => {
    const on = setup('<div id="a"></div>', url);
    on.api.apply([filt([op('matches-path', '/marketplace'), op('css-selector', 'div')])]);
    assert.equal(isHidden(on.win, on.document.getElementById('a')), true);

    const off = setup('<div id="a"></div>', url);
    off.api.apply([filt([op('matches-path', '/feed'), op('css-selector', 'div')])]);
    assert.equal(isHidden(off.win, off.document.getElementById('a')), false);
  });

  test('matches the query string too', () => {
    const { document, api, win } = setup('<div id="a"></div>', url);
    api.apply([filt([op('matches-path', '/marketplace?tab=1'), op('css-selector', 'div')])]);
    assert.equal(isHidden(win, document.getElementById('a')), true);
  });
});

describe('min-text-length', () => {
  test('keeps elements whose text is long enough', () => {
    const { document, api, win } = setup('<div id="short">abc</div><div id="long">abcdefghij</div>');
    api.apply([filt([op('css-selector', 'div'), op('min-text-length', '5')])]);
    assert.equal(isHidden(win, document.getElementById('long')), true);
    assert.equal(isHidden(win, document.getElementById('short')), false);
  });

  test('a non-integer argument drops the filter', () => {
    const { document, api, win } = setup('<div id="a">abc</div>');
    api.apply([filt([op('css-selector', 'div'), op('min-text-length', 'abc')])]);
    assert.equal(isHidden(win, document.getElementById('a')), false);
  });
});

describe('upward', () => {
  const html = '<div id="l2"><div id="l1"><a id="target">x</a></div></div>';

  test('integer climbs that many parents', () => {
    const { document, api, win } = setup(html);
    api.apply([filt([op('css-selector', '#target'), op('upward', '2')])]);
    assert.equal(isHidden(win, document.getElementById('l2')), true);
    assert.equal(isHidden(win, document.getElementById('l1')), false);
    assert.equal(isHidden(win, document.getElementById('target')), false);
  });

  test('climbing past the root yields nothing', () => {
    const { document, api, win } = setup(html);
    api.apply([filt([op('css-selector', '#target'), op('upward', '50')])]);
    assert.equal(isMarked(document.getElementById('l2')), false);
    assert.equal(isHidden(win, document.getElementById('l2')), false);
  });

  test('out-of-range integer drops the filter', () => {
    const { document, api } = setup(html);
    api.apply([filt([op('css-selector', '#target'), op('upward', '0')])]);
    assert.equal(isMarked(document.getElementById('l1')), false);
    assert.equal(isMarked(document.getElementById('l2')), false);
  });

  test('selector finds the nearest ancestor from the parent', () => {
    const { document, api, win } = setup(
      '<section class="wrap" id="w"><div><p id="target">x</p></div></section>',
    );
    api.apply([filt([op('css-selector', '#target'), op('upward', 'section.wrap')])]);
    assert.equal(isHidden(win, document.getElementById('w')), true);
  });
});

describe('xpath', () => {
  test('absolute expression as the first operator', () => {
    const { document, api, win } = setup(
      '<div id="x3"><div id="x2"><div id="x1"><strong>VPN</strong></div></div></div>',
    );
    api.apply([filt([op('xpath', '//strong[contains(text(),"VPN")]/../../..')])]);
    assert.equal(isHidden(win, document.getElementById('x3')), true);
    assert.equal(isHidden(win, document.getElementById('x1')), false);
  });

  test('relative expression evaluated per element in a chain', () => {
    const { document, api, win } = setup(
      '<section id="w"><div><p id="p">Ad</p></div></section><section id="o"><p>News</p></section>',
    );
    api.apply([filt([op('css-selector', 'p'), op('has-text', 'Ad'), op('xpath', '../..')])]);
    assert.equal(isHidden(win, document.getElementById('w')), true);
    assert.equal(isHidden(win, document.getElementById('o')), false);
  });

  test('a quoted expression is unquoted', () => {
    const { document, api, win } = setup('<div id="w"><div id="s"><span>VPN</span></div></div>');
    api.apply([filt([op('xpath', `'//span[contains(text(),"VPN")]/..'`)])]);
    assert.equal(isHidden(win, document.getElementById('s')), true);
    assert.equal(isHidden(win, document.getElementById('w')), false);
  });
});

describe('actions', () => {
  test('remove detaches matches', () => {
    const { document, api } = setup('<div class="banner" id="a"></div><div id="b"></div>');
    api.apply([filt([op('css-selector', '.banner')], act('remove'))]);
    assert.equal(document.getElementById('a'), null);
    assert.ok(document.getElementById('b'));
  });

  test('style adds a rule and marks the element', () => {
    const { document, api, win } = setup('<div id="a"></div>');
    api.apply([filt([op('css-selector', '#a')], act('style', 'height: 1px !important'))]);
    const a = document.getElementById('a');
    assert.equal(isMarked(a), true);
    assert.equal(isHidden(win, a), false);
    assert.equal(a.getAttribute('style'), null);
    assert.match(document.querySelector('style').textContent, /height: 1px !important/);
  });

  test('style with the same text reuses one rule', () => {
    const { document, api } = setup('<div class="s"></div><div class="s"></div>');
    api.apply([filt([op('css-selector', '.s')], act('style', 'color: red'))]);
    assert.equal(document.querySelectorAll('style').length, 1);
    assert.equal(document.querySelector('style').textContent.split('color: red').length, 2);
  });

  test('style rejects url(), expression, escapes and braces', () => {
    for (const bad of ['background: url(x.png)', 'width: expression(1)', 'content: "\\"', 'color: red}body{display:none']) {
      const { document, api } = setup('<div id="a"></div>');
      api.apply([filt([op('css-selector', '#a')], act('style', bad))]);
      assert.equal(isMarked(document.getElementById('a')), false, bad);
    }
  });

  test('remove-attr by exact name and by regex', () => {
    const { document, api } = setup('<div id="a" onclick="1" onmouseover="2" title="t"></div>');
    api.apply([filt([op('css-selector', '#a')], act('remove-attr', 'onclick'))]);
    const a = document.getElementById('a');
    assert.equal(a.hasAttribute('onclick'), false);
    assert.equal(a.hasAttribute('onmouseover'), true);
    api.apply([filt([op('css-selector', '#a')], act('remove-attr', '/^on/'))]);
    assert.equal(a.hasAttribute('onmouseover'), false);
    assert.equal(a.getAttribute('title'), 't');
  });

  test('remove-class by exact name and by regex', () => {
    const { document, api } = setup('<div id="a" class="advert ad-slot keep"></div>');
    api.apply([filt([op('css-selector', '#a')], act('remove-class', 'advert'))]);
    assert.equal(document.getElementById('a').className, 'ad-slot keep');
    api.apply([filt([op('css-selector', '#a')], act('remove-class', '/^ad/'))]);
    assert.equal(document.getElementById('a').className, 'keep');
  });
});

describe('re-application on mutation', () => {
  test('new matching nodes are hidden after a mutation', async () => {
    const { document, api, win } = setup('<div id="root"></div>');
    api.apply([filt([op('css-selector', '.ad')])]);
    const ad = document.createElement('div');
    ad.className = 'ad';
    document.getElementById('root').append(ad);
    await sleep(250);
    assert.equal(isHidden(win, ad), true);
  });

  test('remove re-applies to nodes the page re-inserts', async () => {
    const { document, api } = setup('<div id="root"></div>');
    api.apply([filt([op('css-selector', '.ad')], act('remove'))]);
    const ad = document.createElement('div');
    ad.className = 'ad';
    document.getElementById('root').append(ad);
    await sleep(250);
    assert.equal(ad.isConnected, false);
  });

  test('attribute changes that stop matching restore the element', async () => {
    const { document, api, win } = setup('<div id="a" class="ad"></div>');
    api.apply([filt([op('css-selector', '.ad')])]);
    const a = document.getElementById('a');
    assert.equal(isHidden(win, a), true);
    a.className = 'content';
    await sleep(250);
    assert.equal(isMarked(a), false);
    assert.equal(isHidden(win, a), false);
  });

  test('our own writes do not trigger further passes', async () => {
    const { document, api } = setup('<div class="x">x</div>');
    let scans = 0;
    const real = document.querySelectorAll.bind(document);
    document.querySelectorAll = (sel) => {
      if (sel === '*') scans++;
      return real(sel);
    };
    api.apply([filt([op('has-text', 'x')], act('style', 'color: red'))]);
    await sleep(300);
    assert.equal(scans, 1);
    assert.equal(isMarked(document.querySelector('.x')), true);
    document.querySelector('.x').append('later');
    await sleep(300);
    assert.equal(scans, 2);
  });

  test('observe:false applies once without watching', async () => {
    const { document, api, win } = setup('<div id="root"></div>');
    api.apply([filt([op('css-selector', '.ad')])], { observe: false });
    const ad = document.createElement('div');
    ad.className = 'ad';
    document.getElementById('root').append(ad);
    await sleep(250);
    assert.equal(isHidden(win, ad), false);
  });
});

describe('chains and replacement', () => {
  test('operators compose left to right', () => {
    const { document, api, win } = setup(
      '<ul><li id="ad" class="item">Sponsored</li><li id="ok" class="item">Hello</li></ul>',
    );
    api.apply([filt([op('css-selector', 'li.item'), op('has-text', 'Sponsored'), op('upward', 'ul')])]);
    assert.equal(isHidden(win, document.getElementById('ad').parentElement), true);
    assert.equal(isHidden(win, document.getElementById('ok')), false);
  });

  test('the engine style element is never a candidate for later filters', () => {
    const { document, api, win } = setup('<div id="a" class="ad"></div>');
    api.apply([filt([op('css-selector', '.ad')]), filt([op('has-text', 'none !important'), op('css-selector', 'style')], act('remove'))]);
    assert.equal(document.querySelectorAll('style').length, 1);
    assert.equal(isHidden(win, document.getElementById('a')), true);
  });

  test('a later apply replaces the earlier set and clears its marks', () => {
    const { document, api, win } = setup('<div id="a" class="ad"></div>');
    api.apply([filt([op('css-selector', '.ad')])]);
    assert.equal(isHidden(win, document.getElementById('a')), true);
    api.apply([]);
    assert.equal(isMarked(document.getElementById('a')), false);
    assert.equal(isHidden(win, document.getElementById('a')), false);
  });
});

describe('malformed input', () => {
  test('never throws and keeps valid filters working', () => {
    const { document, api, win } = setup('<div id="a" class="ad"></div>');
    const bad = [
      'not json',
      '{}',
      '{"selector": []}',
      '{"selector": [{"type": "nope", "arg": "x"}]}',
      '{"selector": [{"type": "css-selector"}]}',
      '{"selector": [{"type": "css-selector", "arg": "p"}], "action": {"type": "explode"}}',
      '{"selector": [{"type": "has-text", "arg": ""}]}',
      '{"selector": [{"type": "css-selector", "arg": ".ad"}], "action": {"type": "style"}}',
      'null',
      42,
      { selector: [{ type: '__proto__', arg: 'x' }] },
    ];
    assert.doesNotThrow(() => api.apply([...bad, filt([op('css-selector', '.ad')])]));
    assert.equal(isHidden(win, document.getElementById('a')), true);
  });

  test('a non-array argument clears filters without throwing', () => {
    const { api } = setup('<div></div>');
    assert.doesNotThrow(() => api.apply(undefined));
    assert.doesNotThrow(() => api.apply('x'));
  });

  test('exposes only wbeProcedural', () => {
    const { win } = setup('');
    assert.deepEqual(Object.keys(win.wbeProcedural), ['apply']);
  });
});

// Real lines from https://ublockorigin.github.io/uAssets/filters/filters.txt, converted by hand
// to the adblock-rust JSON shape. Each entry lists the ids that must be hidden or kept.
describe('real uAssets lines', () => {
  const cases = [
    {
      line: 'sport1.de##strong:has-text(/anzeige/i)',
      filter: { selector: [op('css-selector', 'strong'), op('has-text', '/anzeige/i')] },
      html: '<p><strong id="h">Anzeige</strong></p><strong id="k">News</strong>',
      hidden: ['h'], kept: ['k'],
    },
    {
      line: 'btc-echo.de##.elementor-row:has-text([Anzeige])',
      filter: { selector: [op('css-selector', '.elementor-row'), op('has-text', '[Anzeige]')] },
      html: '<div class="elementor-row" id="h">x [Anzeige]</div><div class="elementor-row" id="k">plain</div>',
      hidden: ['h'], kept: ['k'],
    },
    {
      line: 'web.de##.iba-acceptable:has-text(/Anzeige|Info/)',
      filter: { selector: [op('css-selector', '.iba-acceptable'), op('has-text', '/Anzeige|Info/')] },
      html: '<div class="iba-acceptable" id="h">Info</div><div class="iba-acceptable" id="k">Hallo</div>',
      hidden: ['h'], kept: ['k'],
    },
    {
      line: 'pornhub.*##div.container:style(margin-top: 0px !important)',
      filter: { selector: [op('css-selector', 'div.container')], action: act('style', 'margin-top: 0px !important') },
      html: '<div class="container" id="s"></div>',
      marked: ['s'], kept: ['s'],
    },
    {
      line: 'aranzulla.it##.banner:remove()',
      filter: { selector: [op('css-selector', '.banner')], action: act('remove') },
      html: '<div class="banner" id="h"></div><div id="k"></div>',
      removed: ['h'], kept: ['k'],
    },
    {
      line: 'aranzulla.it##[id^="ad"]:remove()',
      filter: { selector: [op('css-selector', '[id^="ad"]')], action: act('remove') },
      html: '<div id="ad-slot" class="h"></div><div id="header" class="k"></div>',
      removed: ['ad-slot'], kept: ['header'],
    },
    {
      line: 'businesstoday.in###zedoads1:style(height: 1px !important)',
      filter: { selector: [op('css-selector', '#zedoads1')], action: act('style', 'height: 1px !important') },
      html: '<div id="zedoads1"></div><div id="k"></div>',
      marked: ['zedoads1'], kept: ['k'],
    },
    {
      line: 'indiatimes.com##[onclick] p:has-text(/Ad/):xpath(../../..)',
      filter: { selector: [op('css-selector', '[onclick] p'), op('has-text', '/Ad/'), op('xpath', '../../..')] },
      html: '<div onclick="1" id="top"><div id="d3"><div id="d2"><div id="d1"><p>Ad</p></div></div></div></div>',
      hidden: ['d3'], kept: ['top', 'd2'],
    },
    {
      line: 'indiatimes.com##p:matches-css(background-image: /colombia-icon/):xpath(../..)',
      filter: {
        selector: [op('css-selector', 'p'), op('matches-css', 'background-image: /colombia-icon/'), op('xpath', '../..')],
      },
      html: '<div id="w"><div id="d"><p style="background-image: url(/img/colombia-icon.png)"></p></div></div>',
      hidden: ['w'], kept: ['d'],
    },
    {
      line: 'bild.de##div:matches-css-before(content:/Anzeige/i)',
      filter: { selector: [op('css-selector', 'div'), op('matches-css-before', 'content:/Anzeige/i')] },
      html: '<div id="h"></div><div id="k"></div>',
      pseudo: { '::before': { h: '"Anzeige"' } },
      hidden: ['h'], kept: ['k'],
    },
    {
      line: 'pussyspace.com,pussyspace.net##a:matches-attr(/-h?ref/)',
      filter: { selector: [op('css-selector', 'a'), op('matches-attr', '/-h?ref/')] },
      html: '<a id="h" data-ref="1"></a><a id="k" title="x"></a>',
      hidden: ['h'], kept: ['k'],
    },
    {
      line: 'yts.mx##.title ~ a[href] .button:upward(.container > div)',
      filter: {
        selector: [op('css-selector', '.title ~ a[href] .button'), op('upward', '.container > div')],
      },
      html: '<div class="container"><div id="h"><div class="title"></div><a href="#"><span class="button"></span></a></div></div>',
      hidden: ['h'], kept: [],
    },
    {
      line: 'feet9.com##[href^="https://go.cam.feet9.com/"]:upward(3)',
      filter: { selector: [op('css-selector', '[href^="https://go.cam.feet9.com/"]'), op('upward', '3')] },
      html: '<div id="h"><div><div><a href="https://go.cam.feet9.com/x" id="a"></a></div></div></div>',
      hidden: ['h'], kept: ['a'],
    },
    {
      line: 'torlock.*##:xpath(//strong[contains(text(),"VPN")]/../../..)',
      filter: { selector: [op('xpath', '//strong[contains(text(),"VPN")]/../../..')] },
      html: '<div id="h"><div id="x2"><div id="k"><strong>VPN</strong></div></div></div>',
      hidden: ['h'], kept: ['k', 'x2'],
    },
    {
      line: 'mypornstarbook.net##table > tbody > tr:has-text(Advertisement)',
      filter: { selector: [op('css-selector', 'table > tbody > tr'), op('has-text', 'Advertisement')] },
      html: '<table><tbody><tr id="h"><td>Advertisement</td></tr><tr id="k"><td>News</td></tr></tbody></table>',
      hidden: ['h'], kept: ['k'],
    },
    {
      line: 'ccn.com##.widget:has-text(/advert|sponsor/i)',
      filter: { selector: [op('css-selector', '.widget'), op('has-text', '/advert|sponsor/i')] },
      html: '<div class="widget" id="h">Sponsored</div><div class="widget" id="k">Latest</div>',
      hidden: ['h'], kept: ['k'],
    },
    {
      line: 'gamepedia.com###bodyContent:style(width:100%!important)',
      filter: { selector: [op('css-selector', '#bodyContent')], action: act('style', 'width:100%!important') },
      html: '<div id="bodyContent"></div>',
      marked: ['bodyContent'], kept: ['bodyContent'],
    },
    {
      line: "ettv.*##:xpath('//*[contains(text(),\"VPN\")]'):upward(2)",
      filter: { selector: [op('xpath', "'//*[contains(text(),\"VPN\")]'"), op('upward', '2')] },
      html: '<div id="h"><div id="p"><span>VPN</span></div></div>',
      hidden: ['h'], kept: ['p'],
    },
  ];

  for (const c of cases) {
    test(c.line, () => {
      const { document, api, win } = setup(c.html);
      if (c.pseudo) {
        const real = win.getComputedStyle;
        win.getComputedStyle = (el, pseudo) => {
          const v = c.pseudo[pseudo]?.[el.id];
          if (pseudo === null || pseudo === undefined) return real(el, pseudo);
          return { getPropertyValue: (n) => (n === 'content' && v ? v : '') };
        };
      }
      api.apply([JSON.stringify(c.filter)]);
      const byId = (id) => document.getElementById(id);
      for (const id of c.hidden ?? []) assert.equal(isHidden(win, byId(id)), true, `hidden ${id}`);
      for (const id of c.marked ?? []) assert.equal(isMarked(byId(id)), true, `marked ${id}`);
      for (const id of c.removed ?? []) assert.equal(byId(id), null, `removed ${id}`);
      for (const id of c.kept ?? []) {
        assert.ok(byId(id), `kept ${id} exists`);
        assert.equal(isHidden(win, byId(id)), false, `kept ${id}`);
      }
    });
  }
});
