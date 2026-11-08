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
  const BAD_STYLE = /image-set\(|url\(|expression|\\|\/\s*\/|\/\*|[{}<>]/i;
  // Pseudo-classes that depend only on tree shape and the selectors they wrap.
  const STRUCTURAL = /^(?:not|is|where|has|matches|nth-(?:last-)?(?:child|of-type)|(?:first|last|only)-(?:child|of-type)|root|scope)$/;

  const state = {
    filters: [],
    marks: new Map(), // element -> attribute names set by the last pass
    styles: new Map(), // style text -> generated attribute name
    styleEl: null,
    observe: true,
    queued: false,
    cleanups: [],
    shadowRoots: new Set(),
    shadowStyles: new Map(),
    shadowWatch: false,
    deps: null,
  };

  // What the filters can depend on besides tree shape: attribute names, class
  // and id tokens, and text. `any` keeps every attribute and text change.
  const newDeps = () => ({ any: false, text: false, attrs: new Set(), classes: new Set(), ids: new Set() });
  const fold = (s) => (document.compatMode === 'BackCompat' ? s.toLowerCase() : s);

  const trackCss = (sel) => {
    const { deps } = state;
    if (/[\\|]/.test(sel)) return void (deps.any = true);
    const rest = sel.replace(/\[\s*([^\s~|^$*=\]]+)[^\]]*\]/g, (_, name) => {
      deps.attrs.add(name).add(name.toLowerCase());
      return ' ';
    });
    for (const [, kind, name] of rest.matchAll(/([.#]|:+)([^\s.#[\]:>+~,()*|='"]+)/g)) {
      if (kind === '.') deps.classes.add(fold(name));
      else if (kind === '#') deps.ids.add(fold(name));
      else if (!STRUCTURAL.test(name)) deps.any = true;
    }
  };

  const trackOperator = (type, arg) => {
    const { deps } = state;
    if (type === 'css-selector' || type === 'shadow' || (type === 'upward' && !/^\d+$/.test(arg))) trackCss(arg);
    else if (type === 'has-text' || type === 'min-text-length') deps.text = true;
    else if (type === 'watch-attr' || type === 'matches-attr') {
      const names = type === 'matches-attr' ? [nameValue(arg)[0]] : String(arg).split(',').map(s => s.trim()).filter(Boolean);
      if (names.length === 0 || names.some(n => n.startsWith('/'))) deps.any = true;
      for (const n of names) deps.attrs.add(n);
    } else if (/^(?:matches-css|matches-prop|xpath)/.test(type)) deps.any = true;
  };

  const trackAction = (action) => {
    if (!action || (action.type !== 'remove-attr' && action.type !== 'remove-class')) return;
    const name = unquote(action.arg || '');
    if (action.type === 'remove-attr' && name.startsWith('/')) state.deps.any = true;
    else if (name.startsWith('/')) state.deps.attrs.add('class');
    else if (action.type === 'remove-class') state.deps.classes.add(fold(name));
    else state.deps.attrs.add(name);
  };

  const tokens = (s) => new Set(s ? fold(s).split(/\s+/) : []);
  const tokensChanged = (wanted, before, after) => {
    const a = tokens(before), b = tokens(after);
    for (const t of a) if (!b.has(t) && wanted.has(t)) return true;
    for (const t of b) if (!a.has(t) && wanted.has(t)) return true;
    return false;
  };

  // Attribute and text records outside the tracked dependencies cannot change a result.
  const relevant = (r) => {
    const { deps } = state;
    if (r.type === 'childList' || deps.any) return true;
    if (r.type === 'characterData') return deps.text;
    const name = r.attributeName;
    if (deps.attrs.has(name)) return true;
    if (name === 'class') return tokensChanged(deps.classes, r.oldValue, r.target.getAttribute('class'));
    return name === 'id' && tokensChanged(deps.ids, r.oldValue, r.target.getAttribute('id'));
  };

  const observeOptions = () => {
    const { any, text, attrs, classes, ids } = state.deps;
    const options = { childList: true, subtree: true, characterData: any || text };
    if (any) return { ...options, attributes: true };
    const filter = [...attrs];
    if (classes.size) filter.push('class');
    if (ids.size) filter.push('id');
    return filter.length ? { ...options, attributeFilter: filter, attributeOldValue: true } : options;
  };

  const observer = new MutationObserver((records) => {
    if (records.some(relevant)) schedule();
  });

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

  // Mirrors uBO's spath handling: a leading >, + or ~ is relative to each element,
  // a leading space is a descendant search, anything else tests the element itself.
  const cssOp = (arg) => {
    const t = arg.trimStart();
    const comb = t[0];
    if (comb === '>') return expand(el => Array.from(el.querySelectorAll(':scope ' + t)));
    if (comb === '+' || comb === '~') {
      // querySelectorAll on the parent preserves the whole relative chain.
      return expand(el => {
        const parent = el.parentElement;
        if (!parent) return [];
        const index = Array.from(parent.children).indexOf(el) + 1;
        return Array.from(parent.querySelectorAll(`:scope > :nth-child(${index}) ${t}`));
      });
    }
    if (arg !== t) return expand((el) => Array.from(el.querySelectorAll(':scope ' + t)));
    return filter((el) => el.matches(arg));
  };

  const hasText = (arg) => {
    const re = toRegex(unquote(arg));
    return filter((el) => re.test(el.textContent));
  };

  // uBO compileMatchAttrArgument, shared by matches-attr and matches-prop:
  // `"name"=value`, or one (possibly quoted) `name=value`. The value is null when absent.
  const nameValue = (arg) => {
    const quoted = /^(["'])(.*?)\1=(.*)$/s.exec(arg);
    if (quoted) return [quoted[2], unquote(quoted[3])];
    const whole = unquote(arg);
    const i = whole.indexOf('=');
    return i < 0 ? [whole, null] : [whole.slice(0, i), unquote(whole.slice(i + 1))];
  };

  const matchesAttr = (arg) => {
    const [name, raw] = nameValue(arg);
    const key = toRegex(name, true);
    const value = raw === null ? null : toRegex(raw, true);
    return filter((el) =>
      el.getAttributeNames().some((n) => key.test(n) && (!value || value.test(el.getAttribute(n)))),
    );
  };

  // uBO compileCSSDeclaration: `[before|after, ]name: value`.
  const matchesCss = (arg) => {
    const prefix = /^([a-z-]+),\s*/.exec(arg);
    const pseudo = prefix ? '::' + prefix[1] : null;
    if (prefix) arg = arg.slice(prefix[0].length);
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

  const matchesMedia = (arg) => {
    const media = matchMedia(arg);
    media.addEventListener('change', schedule);
    state.cleanups.push(() => media.removeEventListener('change', schedule));
    return (els) => media.matches ? els : [];
  };

  const matchesProperty = (arg) => {
    const [path, raw] = nameValue(arg);
    const value = raw === null ? null : toRegex(raw, true);
    // Regex path components may contain dots; split only outside /regex/.
    const parts = path.match(/\/(?:\\.|[^/])+\/|[^.]+/g).map(part =>
      part.startsWith('/') ? toRegex(part, true) : part);
    const matches = (object, index) => {
      if (index === parts.length) return object !== undefined && (!value || value.test(String(object)));
      if (object == null) return false;
      const part = parts[index];
      const keys = typeof part === 'string' ? [part] : Object.getOwnPropertyNames(object).filter(key => part.test(key));
      return keys.some(key => {
        try { return matches(object[key], index + 1); } catch { return false; }
      });
    };
    return filter(el => matches(el, 0));
  };

  const others = () => (els) => {
    const targets = els.filter(el => !els.some(parent => parent !== el && parent.contains(el)));
    const keep = new Set(targets);
    const discard = new Set();
    for (let el of targets) {
      for (; el && el !== document.body && el !== document.head; el = el.parentElement) {
        keep.add(el);
        discard.delete(el);
        for (const sibling of el.parentElement?.children || []) {
          if (!keep.has(sibling) && !/^(head|link|meta|script|style)$/.test(sibling.localName)) discard.add(sibling);
        }
      }
    }
    return [...discard];
  };

  const shadow = (arg) => {
    if (!state.shadowWatch) {
      // Attaching a root to an existing host is not a document mutation.
      const timer = setInterval(() => { if (state.observe) schedule(); }, 1000);
      state.cleanups.push(() => clearInterval(timer));
      state.shadowWatch = true;
    }
    return expand(el => {
      const root = el.shadowRoot;
      if (!root) return [];
      state.shadowRoots.add(root);
      return Array.from(root.querySelectorAll(arg || '*'));
    });
  };

  const nested = (arg, type) => {
    const run = compileSelector(arg);
    const self = type === 'not' || type === 'is' || type === 'where';
    const negate = type === 'not' || type === 'if-not';
    return filter(el => (run(el, self).length !== 0) !== negate);
  };

  const OPS = new Map([
    ['css-selector', cssOp],
    ['has-text', hasText],
    ['matches-media', matchesMedia],
    ['matches-property', matchesProperty],
    ['matches-prop', matchesProperty],
    ['others', others],
    ['shadow', shadow],
    // The shared observer already watches attributes throughout each subtree.
    ['watch-attr', () => els => els],
    ...['has', 'if', 'if-not', 'not', 'is', 'where'].map(type => [type, arg => nested(arg, type)]),
    ['matches-attr', matchesAttr],
    ['matches-css', matchesCss],
    ['matches-css-after', (a) => matchesCss(`after, ${a}`)],
    ['matches-css-before', (a) => matchesCss(`before, ${a}`)],
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
    for (const sheet of state.shadowStyles.values()) sheet.textContent = state.styleEl.textContent;
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

  const compileSelector = (selector) => {
    if (!Array.isArray(selector) || selector.length === 0) throw new Error('empty selector');
    const ops = selector.map(({ type, arg }) => {
      const make = OPS.get(type);
      if (!make || (typeof arg !== 'string' && !Array.isArray(arg))) throw new Error('bad operator');
      if (arg === '' && type !== 'others' && type !== 'watch-attr' && type !== 'shadow') throw new Error('empty argument');
      const run = make(arg);
      trackOperator(type, arg);
      return run;
    });
    const head = selector[0];
    return (root = document, self = false) => {
      let els;
      let skip = 0;
      if (head.type === 'css-selector') {
        const css = head.arg.trim();
        els = self ? (root.matches(css) ? [root] : [])
          : /^[>+~]/.test(css) ? cssOp(css)([root]) : Array.from(root.querySelectorAll(css));
        skip = 1;
      } else if (head.type === 'xpath') {
        els = xpathNodes(unquote(head.arg), root);
        skip = 1;
      } else {
        els = root === document ? Array.from(document.querySelectorAll('*')).filter(el => el !== state.styleEl) : [root];
      }
      for (let i = skip; i < ops.length && els.length; i++) els = ops[i](els);
      return els;
    };
  };

  const compileFilter = (json) => {
    const { selector, action } = typeof json === 'string' ? JSON.parse(json) : json;
    const compiled = { dead: false, run: compileSelector(selector), act: compileAction(action) };
    trackAction(action);
    return compiled;
  };

  const pass = () => {
    const next = new Map();
    const mark = (el, attr) => {
      const root = el.getRootNode();
      if (root.host && !state.shadowStyles.has(root)) {
        const sheet = document.createElement('style');
        sheet.textContent = state.styleEl.textContent;
        root.append(sheet);
        state.shadowStyles.set(root, sheet);
      }
      let set = next.get(el);
      if (!set) next.set(el, (set = new Set()));
      set.add(attr);
    };
    for (const f of state.filters) {
      if (f.dead) continue;
      try {
        for (const el of f.run()) f.act(el, mark);
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
    for (const [root, sheet] of state.shadowStyles) {
      if (root.host.isConnected) continue;
      sheet.remove();
      state.shadowStyles.delete(root);
      state.shadowRoots.delete(root);
    }
  };

  // Disconnecting first drops the records caused by our own attribute and style writes.
  const sync = () => {
    observer.disconnect();
    try {
      pass();
    } catch {
      // Keep the page usable; the next mutation retries.
    } finally {
      if (state.observe) {
        const options = observeOptions();
        observer.observe(document, options);
        for (const root of state.shadowRoots) if (root.host.isConnected) observer.observe(root, options);
      }
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
    for (const cleanup of state.cleanups) cleanup();
    state.cleanups = [];
    state.shadowWatch = false;
    state.shadowRoots.clear();
    state.filters = [];
    state.deps = newDeps();
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
