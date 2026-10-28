/*
 * Procedural and action cosmetic filters for the per-page engine.
 *
 * Input is the `procedural` list from the runtime: JSON strings of
 * adblock-rust's ProceduralOrActionFilter, { selector: [{ type, arg }], action? }.
 * Operator semantics follow uBlock Origin's src/js/contentscript-extra.js (GPL-3.0),
 * including its regex-literal rules and style sanitizing. The JSON shape and the
 * rejection of url()/expression in styles follow brave-core's
 * components/cosmetic_filters/resources/data/procedural_filters.ts (MPL-2.0).
 */
(() => {
  'use strict';

  const DEFAULT_STYLE = 'display: none !important';
  const OBSERVE = { attributes: true, childList: true, subtree: true };
  const BAD_STYLE = /image-set\(|url\(|expression|\\|\/\s*\/|\/\*|[{}<>]/i;

  const state = {
    filters: [],
    marks: new Map(), // element -> attribute names set by the last pass
    styles: new Map(), // style text -> generated attribute name
    styleEl: null,
    observe: true,
    queued: false,
  };

  const observer = new MutationObserver(() => schedule());

  const token = () => 'data-wbe-' + Math.random().toString(36).slice(2, 10);

  const unquote = (s) => {
    const q = s[0];
    return (q === '"' || q === "'") && s.length > 1 && s.endsWith(q) ? s.slice(1, -1) : s;
  };

  // uBO regexFromString: `/re/flags` is a regex, anything else is a literal substring
  // (whole string when `exact`).
  const toRegex = (s, exact = false) => {
    if (s === '') return /^/;
    const m = /^\/(.+)\/([imu]*)$/.exec(s);
    if (m) return new RegExp(m[1], m[2]);
    const literal = s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    return new RegExp(exact ? `^${literal}$` : literal);
  };

  const filter = (pred) => (els) => els.filter(pred);

  const expand = (fn) => (els) => {
    const out = new Set();
    for (const el of els) for (const x of fn(el)) out.add(x);
    return [...out];
  };

  const xpathNodes = (expr, ctx) => {
    const snap = document.evaluate(expr, ctx, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
    const out = [];
    for (let i = 0; i < snap.snapshotLength; i++) {
      const node = snap.snapshotItem(i);
      if (node.nodeType === 1) out.push(node);
    }
    return out;
  };

  const followingSiblings = (el) => {
    const out = [];
    for (let s = el.nextElementSibling; s; s = s.nextElementSibling) out.push(s);
    return out;
  };

  // Mirrors uBO's spath handling: a leading >, + or ~ is relative to each element,
  // a leading space is a descendant search, anything else tests the element itself.
  const cssOp = (arg) => {
    const t = arg.trimStart();
    const comb = t[0];
    if (comb === '>' || comb === '+' || comb === '~') {
      const sel = t.slice(1).trimStart();
      const candidates =
        comb === '>' ? (el) => Array.from(el.children)
          : comb === '+' ? (el) => followingSiblings(el).slice(0, 1)
            : followingSiblings;
      return expand((el) => candidates(el).filter((x) => x.matches(sel)));
    }
    if (arg !== t) return expand((el) => Array.from(el.querySelectorAll(':scope ' + t)));
    return filter((el) => el.matches(arg));
  };

  const hasText = (arg) => {
    const re = toRegex(unquote(arg));
    return filter((el) => re.test(el.textContent));
  };

  const matchesAttr = (arg) => {
    const i = arg.indexOf('=');
    const key = toRegex(unquote(i < 0 ? arg : arg.slice(0, i)), true);
    const value = i < 0 ? null : toRegex(unquote(arg.slice(i + 1)), true);
    return filter((el) =>
      el.getAttributeNames().some((n) => key.test(n) && (!value || value.test(el.getAttribute(n)))),
    );
  };

  const matchesCss = (arg, pseudo) => {
    const i = arg.indexOf(':');
    if (i < 0) throw new Error('matches-css: expected name: value');
    const name = arg.slice(0, i).trim();
    const re = toRegex(arg.slice(i + 1).trim(), true);
    return filter((el) => re.test(getComputedStyle(el, pseudo).getPropertyValue(name)));
  };

  const matchesPath = (arg) => {
    const re = toRegex(unquote(arg).replace(/[^\x00-\x7F]/g, encodeURIComponent));
    return (els) => (re.test(location.pathname + location.search) ? els : []);
  };

  const minTextLength = (arg) => {
    if (!/^\d+$/.test(arg)) throw new Error('min-text-length: expected integer');
    const min = Number(arg);
    return filter((el) => el.textContent.length >= min);
  };

  // uBO upward: an integer climbs that many parents (1-255); otherwise closest() from the parent.
  const upward = (arg) => {
    if (!/^\d+$/.test(arg)) {
      return expand((el) => {
        const p = el.parentElement?.closest(arg);
        return p ? [p] : [];
      });
    }
    const n = Number(arg);
    if (n < 1 || n > 255) throw new Error('upward: out of range');
    return expand((el) => {
      let p = el;
      for (let i = 0; i < n && p; i++) p = p.parentElement;
      return p ? [p] : [];
    });
  };

  const OPS = new Map([
    ['css-selector', cssOp],
    ['has-text', hasText],
    ['matches-attr', matchesAttr],
    ['matches-css', (a) => matchesCss(a, null)],
    ['matches-css-after', (a) => matchesCss(a, '::after')],
    ['matches-css-before', (a) => matchesCss(a, '::before')],
    ['matches-path', matchesPath],
    ['min-text-length', minTextLength],
    ['upward', upward],
    ['xpath', (a) => expand((el) => xpathNodes(unquote(a), el))],
  ]);

  // Generated attribute per style text; one rule per style in a single <style> element.
  const styleAttr = (css) => {
    let attr = state.styles.get(css);
    if (attr) return attr;
    attr = token();
    state.styles.set(css, attr);
    if (!state.styleEl) {
      state.styleEl = document.createElement('style');
      (document.head || document.documentElement).append(state.styleEl);
    }
    state.styleEl.textContent += `[${attr}]{${css}}\n`;
    return attr;
  };

  // Returns (el, mark) => void. Hide and style record a mark; the rest act immediately.
  const compileAction = (action) => {
    if (!action) return (el, mark) => mark(el, styleAttr(DEFAULT_STYLE));
    const { type, arg } = action;
    switch (type) {
      case 'remove':
        return (el) => el.remove();
      case 'style':
        if (!arg || BAD_STYLE.test(arg)) throw new Error('style: rejected');
        return (el, mark) => mark(el, styleAttr(arg));
      case 'remove-attr': {
        const re = toRegex(unquote(arg), true);
        return (el) => {
          for (const n of el.getAttributeNames()) if (re.test(n)) el.removeAttribute(n);
        };
      }
      case 'remove-class': {
        const re = toRegex(unquote(arg), true);
        return (el) => {
          for (const c of Array.from(el.classList)) if (re.test(c)) el.classList.remove(c);
        };
      }
      default:
        throw new Error('unknown action');
    }
  };

  const compileFilter = (json) => {
    const { selector, action } = typeof json === 'string' ? JSON.parse(json) : json;
    if (!Array.isArray(selector) || selector.length === 0) throw new Error('empty selector');
    const ops = selector.map(({ type, arg }) => {
      const make = OPS.get(type);
      if (!make || typeof arg !== 'string' || arg === '') throw new Error('bad operator');
      return make(arg);
    });
    const head = selector[0];
    // The first operator is evaluated against the document directly instead of
    // against every element.
    const source =
      head.type === 'css-selector' ? () => Array.from(document.querySelectorAll(head.arg))
        : head.type === 'xpath' ? () => xpathNodes(unquote(head.arg), document)
          : (all) => all();
    const skip = head.type === 'css-selector' || head.type === 'xpath' ? 1 : 0;
    return {
      dead: false,
      run(all) {
        let els = source(all);
        for (let i = skip; i < ops.length && els.length > 0; i++) els = ops[i](els);
        return els;
      },
      act: compileAction(action),
    };
  };

  const pass = () => {
    const next = new Map();
    const mark = (el, attr) => {
      let set = next.get(el);
      if (!set) next.set(el, (set = new Set()));
      set.add(attr);
    };
    let all = null;
    const everything = () => all || (all = Array.from(document.querySelectorAll('*')).filter((el) => el !== state.styleEl));
    for (const f of state.filters) {
      if (f.dead) continue;
      try {
        for (const el of f.run(everything)) f.act(el, mark);
      } catch {
        // A filter that fails on this page (bad selector, regex or xpath) cannot start working later.
        f.dead = true;
      }
    }
    for (const [el, attrs] of state.marks) {
      const cur = next.get(el);
      for (const a of attrs) if (!cur || !cur.has(a)) el.removeAttribute(a);
    }
    for (const [el, attrs] of next) {
      for (const a of attrs) if (!el.hasAttribute(a)) el.setAttribute(a, '');
    }
    state.marks = next;
  };

  // Disconnecting first drops the records caused by our own attribute and style writes.
  const sync = () => {
    observer.disconnect();
    try {
      pass();
    } catch {
      // Keep the page usable; the next mutation retries.
    } finally {
      if (state.observe) observer.observe(document, OBSERVE);
    }
  };

  // Batch bursts of mutations into one pass per frame, or 100 ms if frames are paused.
  const schedule = () => {
    if (state.queued) return;
    state.queued = true;
    const go = () => {
      if (!state.queued) return;
      state.queued = false;
      sync();
    };
    if (typeof requestAnimationFrame === 'function') requestAnimationFrame(go);
    setTimeout(go, 100);
  };

  const apply = (filters, options) => {
    state.filters = [];
    for (const json of filters || []) {
      try {
        state.filters.push(compileFilter(json));
      } catch {
        // A malformed filter is skipped; the others still apply.
      }
    }
    state.observe = options?.observe !== false;
    sync();
  };

  globalThis.wbeProcedural = { apply };
})();
