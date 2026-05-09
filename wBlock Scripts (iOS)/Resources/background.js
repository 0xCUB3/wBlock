/*
 * wBlock WebExtension background runtime.
 * uBO-compatible scriptlet dispatcher backed by wBlock's native filter compiler
 * output.
 */
'use strict';

const NATIVE_HOST_ID = 'application.id';
const MESSAGE_INIT_CONTENT_SCRIPT = 'InitContentScript';
function wBlockApplyConfiguration(configuration) {
  'use strict';
  const config = configuration || {};
  const css = Array.isArray(config.css) ? config.css : [];
  const extendedCss = Array.isArray(config.extendedCss) ? config.extendedCss : [];
  const scriptlets = Array.isArray(config.scriptlets) ? config.scriptlets : [];
  const scripts = Array.isArray(config.js) ? config.js : [];
  const root = globalThis;
  const applied = root.__wblockUboAppliedScriptlets || (root.__wblockUboAppliedScriptlets = new Set());
  const scriptletGlobals = root.__wblockUboScriptletGlobals || (root.__wblockUboScriptletGlobals = { canDebug: false, logLevel: 0 });
  scriptletGlobals.logLevel = 0;


  class ArglistParser {
      constructor(separatorChar = ',', mustQuote = false) {
          this.separatorChar = this.actualSeparatorChar = separatorChar;
          this.separatorCode = this.actualSeparatorCode = separatorChar.charCodeAt(0);
          this.mustQuote = mustQuote;
          this.quoteBeg = 0; this.quoteEnd = 0;
          this.argBeg = 0; this.argEnd = 0;
          this.separatorBeg = 0; this.separatorEnd = 0;
          this.transform = false;
          this.failed = false;
          this.reWhitespaceStart = /^\s+/;
          this.reWhitespaceEnd = /(?:^|\S)(\s+)$/;
          this.reOddTrailingEscape = /(?:^|[^\\])(?:\\\\)*\\$/;
          this.reTrailingEscapeChars = /\\+$/;
      }
      nextArg(pattern, beg = 0) {
          const len = pattern.length;
          this.quoteBeg = beg + this.leftWhitespaceCount(pattern.slice(beg));
          this.failed = false;
          const qc = pattern.charCodeAt(this.quoteBeg);
          if ( qc === 0x22 /* " */ || qc === 0x27 /* ' */ || qc === 0x60 /* ` */ ) {
              this.indexOfNextArgSeparator(pattern, qc);
              if ( this.argEnd !== len ) {
                  this.quoteEnd = this.argEnd + 1;
                  this.separatorBeg = this.separatorEnd = this.quoteEnd;
                  this.separatorEnd += this.leftWhitespaceCount(pattern.slice(this.quoteEnd));
                  if ( this.separatorEnd === len ) { return this; }
                  if ( pattern.charCodeAt(this.separatorEnd) === this.separatorCode ) {
                      this.separatorEnd += 1;
                      return this;
                  }
              }
          }
          this.indexOfNextArgSeparator(pattern, this.separatorCode);
          this.separatorBeg = this.separatorEnd = this.argEnd;
          if ( this.separatorBeg < len ) {
              this.separatorEnd += 1;
          }
          this.argEnd -= this.rightWhitespaceCount(pattern.slice(0, this.separatorBeg));
          this.quoteEnd = this.argEnd;
          if ( this.mustQuote ) {
              this.failed = true;
          }
          return this;
      }
      normalizeArg(s, char = '') {
          if ( char === '' ) { char = this.actualSeparatorChar; }
          let out = '';
          let pos = 0;
          while ( (pos = s.lastIndexOf(char)) !== -1 ) {
              out = s.slice(pos) + out;
              s = s.slice(0, pos);
              const match = this.reTrailingEscapeChars.exec(s);
              if ( match === null ) { continue; }
              const tail = (match[0].length & 1) !== 0
                  ? match[0].slice(0, -1)
                  : match[0];
              out = tail + out;
              s = s.slice(0, -match[0].length);
          }
          if ( out === '' ) { return s; }
          return s + out;
      }
      leftWhitespaceCount(s) {
          const match = this.reWhitespaceStart.exec(s);
          return match === null ? 0 : match[0].length;
      }
      rightWhitespaceCount(s) {
          const match = this.reWhitespaceEnd.exec(s);
          return match === null ? 0 : match[1].length;
      }
      indexOfNextArgSeparator(pattern, separatorCode) {
          this.argBeg = this.argEnd = separatorCode !== this.separatorCode
              ? this.quoteBeg + 1
              : this.quoteBeg;
          this.transform = false;
          if ( separatorCode !== this.actualSeparatorCode ) {
              this.actualSeparatorCode = separatorCode;
              this.actualSeparatorChar = String.fromCharCode(separatorCode);
          }
          while ( this.argEnd < pattern.length ) {
              const pos = pattern.indexOf(this.actualSeparatorChar, this.argEnd);
              if ( pos === -1 ) {
                  return (this.argEnd = pattern.length);
              }
              if ( this.reOddTrailingEscape.test(pattern.slice(0, pos)) === false ) {
                  return (this.argEnd = pos);
              }
              this.transform = true;
              this.argEnd = pos + 1;
          }
      }
  }


  class JSONPath {
      static create(query) {
          const jsonp = new JSONPath();
          jsonp.compile(query);
          return jsonp;
      }
      static toJSON(obj, stringifier, ...args) {
          return (stringifier || JSON.stringify)(obj, ...args)
              .replace(/\//g, '\\/');
      }
      get value() {
          return this.#compiled && this.#compiled.rval;
      }
      set value(v) {
          if ( this.#compiled === undefined ) { return; }
          this.#compiled.rval = v;
      }
      get valid() {
          return this.#compiled !== undefined;
      }
      compile(query) {
          this.#compiled = undefined;
          const r = this.#compile(query, 0);
          if ( r === undefined ) { return; }
          if ( r.i !== query.length ) {
              let val;
              if ( query.startsWith('=', r.i) ) {
                  if ( /^=repl\(.+\)$/.test(query.slice(r.i)) ) {
                      r.modify = 'repl';
                      val = query.slice(r.i+6, -1);
                  } else {
                      val = query.slice(r.i+1);
                  }
              } else if ( query.startsWith('+=', r.i) ) {
                  r.modify = '+';
                  val = query.slice(r.i+2);
              }
              try { r.rval = JSON.parse(val); }
              catch { return; }
          }
          this.#compiled = r;
      }
      evaluate(root) {
          if ( this.valid === false ) { return []; }
          this.#root = root;
          const paths = this.#evaluate(this.#compiled.steps, []);
          this.#root = null;
          return paths;
      }
      apply(root) {
          if ( this.valid === false ) { return; }
          const { rval } = this.#compiled;
          this.#root = { '$': root };
          const paths = this.#evaluate(this.#compiled.steps, []);
          let i = paths.length
          if ( i === 0 ) { this.#root = null; return; }
          while ( i-- ) {
              const { obj, key } = this.#resolvePath(paths[i]);
              if ( rval !== undefined ) {
                  this.#modifyVal(obj, key);
              } else if ( Array.isArray(obj) && typeof key === 'number' ) {
                  obj.splice(key, 1);
              } else {
                  delete obj[key];
              }
          }
          const result = this.#root['$'] ?? null;
          this.#root = null;
          return result;
      }
      dump() {
          return JSON.stringify(this.#compiled);
      }
      toJSON(obj, ...args) {
          return JSONPath.toJSON(obj, null, ...args)
      }
      get [Symbol.toStringTag]() {
          return 'JSONPath';
      }
      #UNDEFINED = 0;
      #ROOT = 1;
      #CURRENT = 2;
      #CHILDREN = 3;
      #DESCENDANTS = 4;
      #reUnquotedIdentifier = /^[A-Za-z_][\w]*|^\*/;
      #reExpr = /^([!=^$*]=|[<>]=?)(.+?)\]/;
      #reIndice = /^-?\d+/;
      #root;
      #compiled;
      #compile(query, i) {
          if ( query.length === 0 ) { return; }
          const steps = [];
          let c = query.charCodeAt(i);
          if ( c === 0x24 /* $ */ ) {
              steps.push({ mv: this.#ROOT });
              i += 1;
          } else if ( c === 0x40 /* @ */ ) {
              steps.push({ mv: this.#CURRENT });
              i += 1;
          } else {
              steps.push({ mv: i === 0 ? this.#ROOT : this.#CURRENT });
          }
          let mv = this.#UNDEFINED;
          for (;;) {
              if ( i === query.length ) { break; }
              c = query.charCodeAt(i);
              if ( c === 0x20 /* whitespace */ ) {
                  i += 1;
                  continue;
              }
              // Dot accessor syntax
              if ( c === 0x2E /* . */ ) {
                  if ( mv !== this.#UNDEFINED ) { return; }
                  if ( query.startsWith('..', i) ) {
                      mv = this.#DESCENDANTS;
                      i += 2;
                  } else {
                      mv = this.#CHILDREN;
                      i += 1;
                  }
                  continue;
              }
              if ( c !== 0x5B /* [ */ ) {
                  if ( mv === this.#UNDEFINED ) {
                      const step = steps.at(-1);
                      if ( step === undefined ) { return; }
                      i = this.#compileExpr(query, step, i);
                      break;
                  }
                  const s = this.#consumeUnquotedIdentifier(query, i);
                  if  ( s === undefined ) { return; }
                  steps.push({ mv, k: s });
                  i += s.length;
                  mv = this.#UNDEFINED;
                  continue;
              }
              // Bracket accessor syntax
              if ( query.startsWith('[?', i) ) {
                  const not = query.charCodeAt(i+2) === 0x21 /* ! */;
                  const j = i + 2 + (not ? 1 : 0);
                  const r = this.#compile(query, j);
                  if ( r === undefined ) { return; }
                  if ( query.startsWith(']', r.i) === false ) { return; }
                  if ( not ) { r.steps.at(-1).not = true; }
                  steps.push({ mv: mv || this.#CHILDREN, steps: r.steps });
                  i = r.i + 1;
                  mv = this.#UNDEFINED;
                  continue;
              }
              if ( query.startsWith('[*]', i) ) {
                  mv ||= this.#CHILDREN;
                  steps.push({ mv, k: '*' });
                  i += 3;
                  mv = this.#UNDEFINED;
                  continue;
              }
              const r = this.#consumeIdentifier(query, i+1);
              if ( r === undefined ) { return; }
              mv ||= this.#CHILDREN;
              steps.push({ mv, k: r.s });
              i = r.i + 1;
              mv = this.#UNDEFINED;
          }
          if ( steps.length === 0 ) { return; }
          if ( mv !== this.#UNDEFINED ) { return; }
          return { steps, i };
      }
      #evaluate(steps, pathin) {
          let resultset = [];
          if ( Array.isArray(steps) === false ) { return resultset; }
          for ( const step of steps ) {
              switch ( step.mv ) {
              case this.#ROOT:
                  resultset = [ [ '$' ] ];
                  break;
              case this.#CURRENT:
                  resultset = [ pathin ];
                  break;
              case this.#CHILDREN:
              case this.#DESCENDANTS:
                  resultset = this.#getMatches(resultset, step);
                  break;
              default:
                  break;
              }
          }
          return resultset;
      }
      #getMatches(listin, step) {
          const listout = [];
          for ( const pathin of listin ) {
              const { value: owner } = this.#resolvePath(pathin);
              if ( step.k === '*' ) {
                  this.#getMatchesFromAll(pathin, step, owner, listout);
              } else if ( step.k !== undefined ) {
                  this.#getMatchesFromKeys(pathin, step, owner, listout);
              } else if ( step.steps ) {
                  this.#getMatchesFromExpr(pathin, step, owner, listout);
              }
          }
          return listout;
      }
      #getMatchesFromAll(pathin, step, owner, out) {
          const recursive = step.mv === this.#DESCENDANTS;
          for ( const { path } of this.#getDescendants(owner, recursive) ) {
              out.push([ ...pathin, ...path ]);
          }
      }
      #getMatchesFromKeys(pathin, step, owner, out) {
          const kk = Array.isArray(step.k) ? step.k : [ step.k ];
          for ( const k of kk ) {
              const normalized = this.#evaluateExpr(step, owner, k);
              if ( normalized === undefined ) { continue; }
              out.push([ ...pathin, normalized ]);
          }
          if ( step.mv !== this.#DESCENDANTS ) { return; }
          for ( const { obj, key, path } of this.#getDescendants(owner, true) ) {
              for ( const k of kk ) {
                  const normalized = this.#evaluateExpr(step, obj[key], k);
                  if ( normalized === undefined ) { continue; }
                  out.push([ ...pathin, ...path, normalized ]);
              }
          }
      }
      #getMatchesFromExpr(pathin, step, owner, out) {
          const recursive = step.mv === this.#DESCENDANTS;
          if ( Array.isArray(owner) === false ) {
              const r = this.#evaluate(step.steps, pathin);
              if ( r.length !== 0 ) { out.push(pathin); }
              if ( recursive !== true ) { return; }
          }
          for ( const { obj, key, path } of this.#getDescendants(owner, recursive) ) {
              if ( Array.isArray(obj[key]) ) { continue; }
              const q = [ ...pathin, ...path ];
              const r = this.#evaluate(step.steps, q);
              if ( r.length === 0 ) { continue; }
              out.push(q);
          }
      }
      #normalizeKey(owner, key) {
          if ( typeof key === 'number' ) {
              if ( Array.isArray(owner) ) {
                  return key >= 0 ? key : owner.length + key;
              }
          }
          return key;
      }
      #getDescendants(v, recursive) {
          const iterator = {
              next() {
                  const n = this.stack.length;
                  if ( n === 0 ) {
                      this.value = undefined;
                      this.done = true;
                      return this;
                  }
                  const details = this.stack[n-1];
                  const entry = details.keys.next();
                  if ( entry.done ) {
                      this.stack.pop();
                      this.path.pop();
                      return this.next();
                  }
                  this.path[n-1] = entry.value;
                  this.value = {
                      obj: details.obj,
                      key: entry.value,
                      path: this.path.slice(),
                  };
                  const v = this.value.obj[this.value.key];
                  if ( recursive ) {
                      if ( Array.isArray(v) ) {
                          this.stack.push({ obj: v, keys: v.keys() });
                      } else if ( typeof v === 'object' && v !== null ) {
                          this.stack.push({ obj: v, keys: Object.keys(v).values() });
                      }
                  }
                  return this;
              },
              path: [],
              value: undefined,
              done: false,
              stack: [],
              [Symbol.iterator]() { return this; },
          };
          if ( Array.isArray(v) ) {
              iterator.stack.push({ obj: v, keys: v.keys() });
          } else if ( typeof v === 'object' && v !== null ) {
              iterator.stack.push({ obj: v, keys: Object.keys(v).values() });
          }
          return iterator;
      }
      #consumeIdentifier(query, i) {
          const keys = [];
          for (;;) {
              const c0 = query.charCodeAt(i);
              if ( c0 === 0x5D /* ] */ ) { break; }
              if ( c0 === 0x2C /* , */ ) {
                  i += 1;
                  continue;
              }
              if ( c0 === 0x27 /* ' */ ) {
                  const r = this.#untilChar(query, 0x27 /* ' */, i+1)
                  if ( r === undefined ) { return; }
                  keys.push(r.s);
                  i = r.i;
                  continue;
              }
              if ( c0 === 0x2D /* - */ || c0 >= 0x30 && c0 <= 0x39 ) {
                  const match = this.#reIndice.exec(query.slice(i));
                  if ( match === null ) { return; }
                  const indice = parseInt(query.slice(i), 10);
                  keys.push(indice);
                  i += match[0].length;
                  continue;
              }
              const s = this.#consumeUnquotedIdentifier(query, i);
              if ( s === undefined ) { return; }
              keys.push(s);
              i += s.length;
          }
          return { s: keys.length === 1 ? keys[0] : keys, i };
      }
      #consumeUnquotedIdentifier(query, i) {
          const match = this.#reUnquotedIdentifier.exec(query.slice(i));
          if ( match === null ) { return; }
          return match[0];
      }
      #untilChar(query, targetCharCode, i) {
          const len = query.length;
          const parts = [];
          let beg = i, end = i;
          for (;;) {
              if ( end === len ) { return; }
              const c = query.charCodeAt(end);
              if ( c === targetCharCode ) {
                  parts.push(query.slice(beg, end));
                  end += 1;
                  break;
              }
              if ( c === 0x5C /* \ */ && (end+1) < len ) {
                  const d = query.charCodeAt(end+1);
                  if ( d === targetCharCode ) {
                      parts.push(query.slice(beg, end));
                      end += 1;
                      beg = end;
                  }
              }
              end += 1;
          }
          return { s: parts.join(''), i: end };
      }
      #compileExpr(query, step, i) {
          if ( query.startsWith('=/', i) ) {
              const r = this.#untilChar(query, 0x2F /* / */, i+2);
              if ( r === undefined ) { return i; }
              const match = /^[i]/.exec(query.slice(r.i));
              try {
                  step.rval = new RegExp(r.s, match && match[0] || undefined);
              } catch {
                  return i;
              }
              step.op = 're';
              if ( match ) { r.i += match[0].length; }
              return r.i;
          }
          const match = this.#reExpr.exec(query.slice(i));
          if ( match === null ) { return i; }
          try {
              step.rval = JSON.parse(match[2]);
              step.op = match[1];
          } catch {
          }
          return i + match[1].length + match[2].length;
      }
      #resolvePath(path) {
          if ( path.length === 0 ) { return { value: this.#root }; }
          const key = path.at(-1);
          let obj = this.#root
          for ( let i = 0, n = path.length-1; i < n; i++ ) {
              obj = obj[path[i]];
          }
          return { obj, key, value: obj[key] };
      }
      #evaluateExpr(step, owner, key) {
          if ( owner === undefined || owner === null ) { return; }
          if ( typeof key === 'number' ) {
              if ( Array.isArray(owner) === false ) { return; }
          }
          const k = this.#normalizeKey(owner, key);
          const hasOwn = Object.hasOwn(owner, k);
          if ( step.op !== undefined && hasOwn === false ) { return; }
          const target = step.not !== true;
          const v = owner[k];
          let outcome = false;
          switch ( step.op ) {
          case '==': outcome = (v === step.rval) === target; break;
          case '!=': outcome = (v !== step.rval) === target; break;
          case  '<': outcome = (v < step.rval) === target; break;
          case '<=': outcome = (v <= step.rval) === target; break;
          case  '>': outcome = (v > step.rval) === target; break;
          case '>=': outcome = (v >= step.rval) === target; break;
          case '^=': outcome = `${v}`.startsWith(step.rval) === target; break;
          case '$=': outcome = `${v}`.endsWith(step.rval) === target; break;
          case '*=': outcome = `${v}`.includes(step.rval) === target; break;
          case 're': outcome = step.rval.test(`${v}`); break;
          default: outcome = hasOwn === target; break;
          }
          if ( outcome ) { return k; }
      }
      #modifyVal(obj, key) {
          let { modify, rval } = this.#compiled;
          if ( typeof rval === 'string' ) {
              rval = rval.replace('${now}', `${Date.now()}`);
          }
          switch ( modify ) {
          case undefined:
              obj[key] = rval;
              break;
          case '+': {
              if ( rval instanceof Object === false ) { return; }
              const lval = obj[key];
              if ( lval instanceof Object === false ) { return; }
              if ( Array.isArray(lval) ) { return; }
              for ( const [ k, v ] of Object.entries(rval) ) {
                  lval[k] = v;
              }
              break;
          }
          case 'repl': {
              const lval = obj[key];
              if ( typeof lval !== 'string' ) { return; }
              if ( this.#compiled.re === undefined ) {
                  this.#compiled.re = null;
                  try {
                      this.#compiled.re = rval.regex !== undefined
                          ? new RegExp(rval.regex, rval.flags)
                          : new RegExp(rval.pattern.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
                  } catch {
                  }
              }
              if ( this.#compiled.re === null ) { return; }
              obj[key] = lval.replace(this.#compiled.re, rval.replacement);
              break;
          }
          default:
              break;
          }
      }
  }


  class RangeParser {
      constructor(s) {
          this.not = s.charAt(0) === '!';
          if ( this.not ) { s = s.slice(1); }
          if ( s === '' ) { return; }
          const pos = s.indexOf('-');
          if ( pos !== 0 ) {
              this.min = this.max = parseInt(s, 10) || 0;
          }
          if ( pos !== -1 ) {
              this.max = parseInt(s.slice(pos + 1), 10) || Number.MAX_SAFE_INTEGER;
          }
      }
      unbound() {
          return this.min === undefined && this.max === undefined;
      }
      test(v) {
          const n = Math.min(Math.max(Number(v) || 0, 0), Number.MAX_SAFE_INTEGER);
          if ( this.min === this.max ) {
              return (this.min === undefined || n === this.min) !== this.not;
          }
          if ( this.min === undefined ) {
              return (n <= this.max) !== this.not;
          }
          if ( this.max === undefined ) {
              return (n >= this.min) !== this.not;
          }
          return (n >= this.min && n <= this.max) !== this.not;
      }
  }


  function abortCurrentScript(...args) {
      runAtHtmlElementFn(( ) => {
          abortCurrentScriptFn(...args);
      });
  }


  function abortCurrentScriptFn(
      target = '',
      needle = '',
      context = ''
  ) {
      if ( typeof target !== 'string' ) { return; }
      if ( target === '' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('abort-current-script', target, needle, context);
      const reNeedle = safe.patternToRegex(needle);
      const reContext = safe.patternToRegex(context);
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 3);
      const thisScript = document.currentScript;
      const chain = safe.String_split.call(target, '.');
      let owner = window;
      let prop;
      for (;;) {
          prop = chain.shift();
          if ( chain.length === 0 ) { break; }
          if ( prop in owner === false ) { break; }
          owner = owner[prop];
          if ( owner instanceof Object === false ) { return; }
      }
      let value;
      let desc = Object.getOwnPropertyDescriptor(owner, prop);
      if (
          desc instanceof Object === false ||
          desc.get instanceof Function === false
      ) {
          value = owner[prop];
          desc = undefined;
      }
      const debug = shouldDebug(extraArgs);
      const exceptionToken = getExceptionTokenFn();
      const scriptTexts = new WeakMap();
      const textContentGetter = Object.getOwnPropertyDescriptor(Node.prototype, 'textContent').get;
      const getScriptText = elem => {
          let text = textContentGetter.call(elem);
          if ( text.trim() !== '' ) { return text; }
          if ( scriptTexts.has(elem) ) { return scriptTexts.get(elem); }
          const [ , mime, content ] =
              /^data:([^,]*),(.+)$/.exec(elem.src.trim()) ||
              [ '', '', '' ];
          try {
              switch ( true ) {
              case mime.endsWith(';base64'):
                  text = self.atob(content);
                  break;
              default:
                  text = self.decodeURIComponent(content);
                  break;
              }
          } catch {
          }
          scriptTexts.set(elem, text);
          return text;
      };
      const validate = ( ) => {
          const e = document.currentScript;
          if ( e instanceof HTMLScriptElement === false ) { return; }
          if ( e === thisScript ) { return; }
          if ( context !== '' && reContext.test(e.src) === false ) {
              // eslint-disable-next-line no-debugger
              if ( debug === 'nomatch' || debug === 'all' ) { debugger; }
              return;
          }
          if ( safe.logLevel > 1 && context !== '' ) {
              safe.uboLog(logPrefix, `Matched src\n${e.src}`);
          }
          const scriptText = getScriptText(e);
          if ( reNeedle.test(scriptText) === false ) {
              // eslint-disable-next-line no-debugger
              if ( debug === 'nomatch' || debug === 'all' ) { debugger; }
              return;
          }
          if ( safe.logLevel > 1 ) {
              safe.uboLog(logPrefix, `Matched text\n${scriptText}`);
          }
          // eslint-disable-next-line no-debugger
          if ( debug === 'match' || debug === 'all' ) { debugger; }
          safe.uboLog(logPrefix, 'Aborted');
          throw new ReferenceError(exceptionToken);
      };
      // eslint-disable-next-line no-debugger
      if ( debug === 'install' ) { debugger; }
      try {
          Object.defineProperty(owner, prop, {
              get: function() {
                  validate();
                  return desc instanceof Object
                      ? desc.get.call(owner)
                      : value;
              },
              set: function(a) {
                  validate();
                  if ( desc instanceof Object ) {
                      desc.set.call(owner, a);
                  } else {
                      value = a;
                  }
              }
          });
      } catch(ex) {
          safe.uboErr(logPrefix, `Error: ${ex}`);
      }
  }


  function abortOnPropertyRead(
      chain = ''
  ) {
      if ( typeof chain !== 'string' ) { return; }
      if ( chain === '' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('abort-on-property-read', chain);
      const exceptionToken = getExceptionTokenFn();
      const abort = function() {
          safe.uboLog(logPrefix, 'Aborted');
          throw new ReferenceError(exceptionToken);
      };
      const makeProxy = function(owner, chain) {
          const pos = chain.indexOf('.');
          if ( pos === -1 ) {
              const desc = Object.getOwnPropertyDescriptor(owner, chain);
              if ( !desc || desc.get !== abort ) {
                  Object.defineProperty(owner, chain, {
                      get: abort,
                      set: function(){}
                  });
              }
              return;
          }
          const prop = chain.slice(0, pos);
          let v = owner[prop];
          chain = chain.slice(pos + 1);
          if ( v ) {
              makeProxy(v, chain);
              return;
          }
          const desc = Object.getOwnPropertyDescriptor(owner, prop);
          if ( desc && desc.set !== undefined ) { return; }
          Object.defineProperty(owner, prop, {
              get: function() { return v; },
              set: function(a) {
                  v = a;
                  if ( a instanceof Object ) {
                      makeProxy(a, chain);
                  }
              }
          });
      };
      const owner = window;
      makeProxy(owner, chain);
  }


  function abortOnPropertyWrite(
      prop = ''
  ) {
      if ( typeof prop !== 'string' ) { return; }
      if ( prop === '' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('abort-on-property-write', prop);
      const exceptionToken = getExceptionTokenFn();
      let owner = window;
      for (;;) {
          const pos = prop.indexOf('.');
          if ( pos === -1 ) { break; }
          owner = owner[prop.slice(0, pos)];
          if ( owner instanceof Object === false ) { return; }
          prop = prop.slice(pos + 1);
      }
      delete owner[prop];
      Object.defineProperty(owner, prop, {
          set: function() {
              safe.uboLog(logPrefix, 'Aborted');
              throw new ReferenceError(exceptionToken);
          }
      });
  }


  function abortOnStackTrace(
      chain = '',
      needle = ''
  ) {
      if ( typeof chain !== 'string' ) { return; }
      const safe = safeSelf();
      const needleDetails = safe.initPattern(needle, { canNegate: true });
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 2);
      if ( needle === '' ) { extraArgs.log = 'all'; }
      const makeProxy = function(owner, chain) {
          const pos = chain.indexOf('.');
          if ( pos === -1 ) {
              let v = owner[chain];
              Object.defineProperty(owner, chain, {
                  get: function() {
                      const log = safe.logLevel > 1 ? 'all' : 'match';
                      if ( matchesStackTraceFn(needleDetails, log) ) {
                          throw new ReferenceError(getExceptionTokenFn());
                      }
                      return v;
                  },
                  set: function(a) {
                      const log = safe.logLevel > 1 ? 'all' : 'match';
                      if ( matchesStackTraceFn(needleDetails, log) ) {
                          throw new ReferenceError(getExceptionTokenFn());
                      }
                      v = a;
                  },
              });
              return;
          }
          const prop = chain.slice(0, pos);
          let v = owner[prop];
          chain = chain.slice(pos + 1);
          if ( v ) {
              makeProxy(v, chain);
              return;
          }
          const desc = Object.getOwnPropertyDescriptor(owner, prop);
          if ( desc && desc.set !== undefined ) { return; }
          Object.defineProperty(owner, prop, {
              get: function() { return v; },
              set: function(a) {
                  v = a;
                  if ( a instanceof Object ) {
                      makeProxy(a, chain);
                  }
              }
          });
      };
      const owner = window;
      makeProxy(owner, chain);
  }


  function adjustSetInterval(
      needleArg = '',
      delayArg = '',
      boostArg = ''
  ) {
      if ( typeof needleArg !== 'string' ) { return; }
      const safe = safeSelf();
      const reNeedle = safe.patternToRegex(needleArg);
      let delay = delayArg !== '*' ? parseInt(delayArg, 10) : -1;
      if ( isNaN(delay) || isFinite(delay) === false ) { delay = 1000; }
      let boost = parseFloat(boostArg);
      boost = isNaN(boost) === false && isFinite(boost)
          ? Math.min(Math.max(boost, 0.001), 50)
          : 0.05;
      self.setInterval = new Proxy(self.setInterval, {
          apply: function(target, thisArg, args) {
              const [ a, b ] = args;
              if (
                  (delay === -1 || b === delay) &&
                  reNeedle.test(a.toString())
              ) {
                  args[1] = b * boost;
              }
              return target.apply(thisArg, args);
          }
      });
  }


  function adjustSetTimeout(
      needleArg = '',
      delayArg = '',
      boostArg = ''
  ) {
      if ( typeof needleArg !== 'string' ) { return; }
      const safe = safeSelf();
      const reNeedle = safe.patternToRegex(needleArg);
      let delay = delayArg !== '*' ? parseInt(delayArg, 10) : -1;
      if ( isNaN(delay) || isFinite(delay) === false ) { delay = 1000; }
      let boost = parseFloat(boostArg);
      boost = isNaN(boost) === false && isFinite(boost)
          ? Math.min(Math.max(boost, 0.001), 50)
          : 0.05;
      self.setTimeout = new Proxy(self.setTimeout, {
          apply: function(target, thisArg, args) {
              const [ a, b ] = args;
              if (
                  (delay === -1 || b === delay) &&
                  reNeedle.test(a.toString())
              ) {
                  args[1] = b * boost;
              }
              return target.apply(thisArg, args);
          }
      });
  }


  function alertBuster() {
      window.alert = new Proxy(window.alert, {
          apply: function(a) {
              console.info(a);
          },
          get(target, prop) {
              if ( prop === 'toString' ) {
                  return target.toString.bind(target);
              }
              return Reflect.get(target, prop);
          },
      });
  }


  function callNothrow(
      chain = ''
  ) {
      if ( typeof chain !== 'string' ) { return; }
      if ( chain === '' ) { return; }
      const safe = safeSelf();
      const parts = safe.String_split.call(chain, '.');
      let owner = window, prop;
      for (;;) {
          prop = parts.shift();
          if ( parts.length === 0 ) { break; }
          owner = owner[prop];
          if ( owner instanceof Object === false ) { return; }
      }
      if ( prop === '' ) { return; }
      const fn = owner[prop];
      if ( typeof fn !== 'function' ) { return; }
      owner[prop] = new Proxy(fn, {
          apply: function(...args) {
              let r;
              try {
                  r = Reflect.apply(...args);
              } catch {
              }
              return r;
          },
      });
  }


  function closeWindow(
      arg1 = ''
  ) {
      if ( typeof arg1 !== 'string' ) { return; }
      const safe = safeSelf();
      let subject = '';
      if ( /^\/.*\/$/.test(arg1) ) {
          subject = window.location.href;
      } else if ( arg1 !== '' ) {
          subject = `${window.location.pathname}${window.location.search}`;
      }
      try {
          const re = safe.patternToRegex(arg1);
          if ( re.test(subject) ) {
              window.close();
          }
      } catch(ex) {
          console.log(ex);
      }
  }


  function collateFetchArgumentsFn(resource, options) {
      const safe = safeSelf();
      const props = [
          'body', 'cache', 'credentials', 'duplex', 'headers',
          'integrity', 'keepalive', 'method', 'mode', 'priority',
          'redirect', 'referrer', 'referrerPolicy', 'url'
      ];
      const out = {};
      if ( collateFetchArgumentsFn.collateKnownProps === undefined ) {
          collateFetchArgumentsFn.collateKnownProps = (src, out) => {
              for ( const prop of props ) {
                  if ( src[prop] === undefined ) { continue; }
                  out[prop] = src[prop];
              }
          };
      }
      if (
          typeof resource !== 'object' ||
          safe.Object_toString.call(resource) !== '[object Request]'
      ) {
          out.url = `${resource}`;
      } else {
          let clone;
          try {
              clone = safe.Request_clone.call(resource);
          } catch {
          }
          collateFetchArgumentsFn.collateKnownProps(clone || resource, out);
      }
      if ( typeof options === 'object' && options !== null ) {
          collateFetchArgumentsFn.collateKnownProps(options, out);
      }
      return out;
  }


  function disableNewtabLinks() {
      document.addEventListener('click', ev => {
          let target = ev.target;
          while ( target !== null ) {
              if ( target.localName === 'a' && target.hasAttribute('target') ) {
                  ev.stopPropagation();
                  ev.preventDefault();
                  break;
              }
              target = target.parentNode;
          }
      }, { capture: true });
  }


  function editInboundObject(propChain = '', argPos = '', jsonq = '') {
      editInboundObjectFn(false, propChain, argPos, jsonq);
  }


  function editInboundObjectFn(
      trusted = false,
      propChain = '',
      argPosRaw = '',
      jsonq = '',
  ) {
      if ( propChain === '' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix(
          `${trusted ? 'trusted-' : ''}edit-inbound-object`,
          propChain,
          jsonq
      );
      const jsonp = JSONPath.create(jsonq);
      if ( jsonp.valid === false || jsonp.value !== undefined && trusted !== true ) {
          return safe.uboLog(logPrefix, 'Bad JSONPath query');
      }
      const argPos = parseInt(argPosRaw, 10);
      if ( isNaN(argPos) ) { return; }
      const getArgPos = args => {
          if ( Array.isArray(args) === false ) { return; }
          if ( argPos >= 0 ) {
              if ( args.length <= argPos ) { return; }
              return argPos;
          }
          if ( args.length < -argPos ) { return; }
          return args.length + argPos;
      };
      const editObj = obj => {
          let clone;
          try {
              clone = safe.JSON_parse(safe.JSON_stringify(obj));
          } catch {
          }
          if ( typeof clone !== 'object' || clone === null ) { return; }
          const objAfter = jsonp.apply(clone);
          if ( objAfter === undefined ) { return; }
          safe.uboLog(logPrefix, 'Edited');
          if ( safe.logLevel > 1 ) {
              safe.uboLog(logPrefix, `After edit:\n${safe.JSON_stringify(objAfter, null, 2)}`);
          }
          return objAfter;
      };
      proxyApplyFn(propChain, function(context) {
          const i = getArgPos(context.callArgs);
          if ( i !== undefined ) {
              const obj = editObj(context.callArgs[i]);
              if ( obj ) {
                  context.callArgs[i] = obj;
              }
          }
          return context.reflect();
      });
  }


  function editOutboundObject(propChain = '', jsonq = '') {
      editOutboundObjectFn(false, propChain, jsonq);
  }


  function editOutboundObjectFn(
      trusted = false,
      propChain = '',
      jsonq = '',
  ) {
      if ( propChain === '' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix(
          `${trusted ? 'trusted-' : ''}edit-outbound-object`,
          propChain,
          jsonq
      );
      const jsonp = JSONPath.create(jsonq);
      if ( jsonp.valid === false || jsonp.value !== undefined && trusted !== true ) {
          return safe.uboLog(logPrefix, 'Bad JSONPath query');
      }
      proxyApplyFn(propChain, function(context) {
          const obj = context.reflect();
          const objAfter = jsonp.apply(obj);
          if ( objAfter === undefined ) { return obj; }
          safe.uboLog(logPrefix, 'Edited');
          if ( safe.logLevel > 1 ) {
              safe.uboLog(logPrefix, `After edit:\n${safe.JSON_stringify(objAfter, null, 2)}`);
          }
          return objAfter;
      });
  }


  function evaldataPrune(
      rawPrunePaths = '',
      rawNeedlePaths = ''
  ) {
      proxyApplyFn('eval', function(context) {
          const before = context.reflect();
          if ( typeof before !== 'object' ) { return before; }
          if ( before === null ) { return null; }
          const after = objectPruneFn(before, rawPrunePaths, rawNeedlePaths);
          return after || before;
      });
  }


  function freezeElementProperty(
      property = '',
      selector = '',
      pattern = ''
  ) {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('freeze-element-property', property, selector, pattern);
      const matcher = safe.initPattern(pattern, { canNegate: true });
      const owner = (( ) => {
          if ( Object.hasOwn(Element.prototype, property) ) {
              return Element.prototype;
          }
          if ( Object.hasOwn(HTMLElement.prototype, property) ) {
              return HTMLElement.prototype;
          }
          if ( Object.hasOwn(Node.prototype, property) ) {
              return Node.prototype;
          }
          return null;
      })();
      if ( owner === null ) { return; }
      const current = safe.Object_getOwnPropertyDescriptor(owner, property);
      if ( current === undefined ) { return; }
      const shouldPreventSet = (elem, a) => {
          if ( selector !== '' ) {
              if ( typeof elem.matches !== 'function' ) { return false; }
              if ( elem.matches(selector) === false ) { return false; }
          }
          return safe.testPattern(matcher, `${a}`);
      };
      Object.defineProperty(owner, property, {
          get: function() {
              return current.get
                  ? current.get.call(this)
                  : current.value;
          },
          set: function(a) {
              if ( shouldPreventSet(this, a) ) {
                  safe.uboLog(logPrefix, 'Assignment prevented');
              } else if ( current.set ) {
                  current.set.call(this, a);
              }
              if ( safe.logLevel > 1 ) {
                  safe.uboLog(logPrefix, `Assigned:\n${a}`);
              }
              current.value = a;
          },
      });
  }


  function generateContentFn(trusted, directive) {
      const safe = safeSelf();
      const randomize = len => {
          const chunks = [];
          let textSize = 0;
          do {
              const s = safe.Math_random().toString(36).slice(2);
              chunks.push(s);
              textSize += s.length;
          }
          while ( textSize < len );
          return chunks.join(' ').slice(0, len);
      };
      if ( directive === 'true' ) {
          return randomize(10);
      }
      if ( directive === 'emptyObj' ) {
          return '{}';
      }
      if ( directive === 'emptyArr' ) {
          return '[]';
      }
      if ( directive === 'emptyStr' ) {
          return '';
      }
      if ( directive.startsWith('length:') ) {
          const match = /^length:(\d+)(?:-(\d+))?$/.exec(directive);
          if ( match === null ) { return ''; }
          const min = parseInt(match[1], 10);
          const extent = safe.Math_max(parseInt(match[2], 10) || 0, min) - min;
          const len = safe.Math_min(min + extent * safe.Math_random(), 500000);
          return randomize(len | 0);
      }
      if ( directive.startsWith('war:') ) {
          if ( scriptletGlobals.warOrigin === undefined ) { return ''; }
          return new Promise(resolve => {
              const warOrigin = scriptletGlobals.warOrigin;
              const warName = directive.slice(4);
              const fullpath = [ warOrigin, '/', warName ];
              const warSecret = scriptletGlobals.warSecret;
              if ( warSecret !== undefined ) {
                  fullpath.push('?secret=', warSecret);
              }
              const warXHR = new safe.XMLHttpRequest();
              warXHR.responseType = 'text';
              warXHR.onloadend = ev => {
                  resolve(ev.target.responseText || '');
              };
              warXHR.open('GET', fullpath.join(''));
              warXHR.send();
          }).catch(( ) => '');
      }
      if ( directive.startsWith('join:') ) {
          const parts = directive.slice(7)
                  .split(directive.slice(5, 7))
                  .map(a => generateContentFn(trusted, a));
          return parts.some(a => a instanceof Promise)
              ? Promise.all(parts).then(parts => parts.join(''))
              : parts.join('');
      }
      if ( trusted ) {
          return directive;
      }
      return '';
  }


  function getAllCookiesFn() {
      const safe = safeSelf();
      return safe.String_split.call(document.cookie, /\s*;\s*/).map(s => {
          const pos = s.indexOf('=');
          if ( pos === 0 ) { return; }
          if ( pos === -1 ) { return `${s.trim()}=`; }
          const key = s.slice(0, pos).trim();
          const value = s.slice(pos+1).trim();
          return { key, value };
      }).filter(s => s !== undefined);
  }


  function getAllLocalStorageFn(which = 'localStorage') {
      const storage = self[which];
      const out = [];
      for ( let i = 0; i < storage.length; i++ ) {
          const key = storage.key(i);
          const value = storage.getItem(key);
          return { key, value };
      }
      return out;
  }


  function getCookieFn(
      name = ''
  ) {
      const safe = safeSelf();
      for ( const s of safe.String_split.call(document.cookie, /\s*;\s*/) ) {
          const pos = s.indexOf('=');
          if ( pos === -1 ) { continue; }
          if ( s.slice(0, pos) !== name ) { continue; }
          return s.slice(pos+1).trim();
      }
  }


  function getExceptionTokenFn() {
      const token = getRandomTokenFn();
      const oe = self.onerror;
      self.onerror = function(msg, ...args) {
          if ( typeof msg === 'string' && msg.includes(token) ) { return true; }
          if ( oe instanceof Function ) {
              return oe.call(this, msg, ...args);
          }
      }.bind();
      return token;
  }


  function getRandomTokenFn() {
      const safe = safeSelf();
      return safe.String_fromCharCode(Date.now() % 26 + 97) +
          safe.Math_floor(safe.Math_random() * 982451653 + 982451653).toString(36);
  }


  function getSafeCookieValuesFn() {
      return [
          'accept', 'reject',
          'accepted', 'rejected', 'notaccepted',
          'allow', 'disallow', 'deny',
          'allowed', 'denied',
          'approved', 'disapproved',
          'checked', 'unchecked',
          'dismiss', 'dismissed',
          'enable', 'disable',
          'enabled', 'disabled',
          'essential', 'nonessential',
          'forbidden', 'forever',
          'hide', 'hidden',
          'necessary', 'required',
          'ok',
          'on', 'off',
          'true', 't', 'false', 'f',
          'yes', 'y', 'no', 'n',
          'all', 'none', 'functional',
          'granted', 'done',
          'decline', 'declined',
          'closed', 'next', 'mandatory',
          'disagree', 'agree',
      ];
  }


  function hrefSanitizer(
      selector = '',
      source = ''
  ) {
      if ( typeof selector !== 'string' ) { return; }
      if ( selector === '' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('href-sanitizer', selector, source);
      if ( source === '' ) { source = 'text'; }
      const sanitizeCopycats = (href, text) => {
          let elems = [];
          try {
              elems = document.querySelectorAll(`a[href="${href}"`);
          }
          catch {
          }
          for ( const elem of elems ) {
              elem.setAttribute('href', text);
          }
          return elems.length;
      };
      const validateURL = text => {
          if ( typeof text !== 'string' ) { return ''; }
          if ( text === '' ) { return ''; }
          if ( /[\x00-\x20\x7f]/.test(text) ) { return ''; }
          try {
              const url = new URL(text, document.location);
              return url.href;
          } catch {
          }
          return '';
      };
      const extractURL = (elem, source) => {
          if ( /^\[.*\]$/.test(source) ) {
              return elem.getAttribute(source.slice(1,-1).trim()) || '';
          }
          if ( source === 'text' ) {
              return elem.textContent
                  .replace(/^[^\x21-\x7e]+/, '')  // remove leading invalid characters
                  .replace(/[^\x21-\x7e]+$/, ''); // remove trailing invalid characters
          }
          const steps = source.replace(/(\S)\?/g, '\\1 ?').split(/\s+/);
          const url = urlSkip(elem.href, false, steps);
          if ( url === undefined ) { return; }
          return url.replace(/ /g, '%20');
      };
      const sanitize = ( ) => {
          let elems = [];
          try {
              elems = document.querySelectorAll(selector);
          }
          catch {
              return false;
          }
          for ( const elem of elems ) {
              if ( elem.localName !== 'a' ) { continue; }
              if ( elem.hasAttribute('href') === false ) { continue; }
              const href = elem.getAttribute('href');
              const text = extractURL(elem, source);
              const hrefAfter = validateURL(text);
              if ( hrefAfter === '' ) { continue; }
              if ( hrefAfter === href ) { continue; }
              elem.setAttribute('href', hrefAfter);
              const count = sanitizeCopycats(href, hrefAfter);
              safe.uboLog(logPrefix, `Sanitized ${count+1} links to\n${hrefAfter}`);
          }
          return true;
      };
      let observer, timer;
      const onDomChanged = mutations => {
          if ( timer !== undefined ) { return; }
          let shouldSanitize = false;
          for ( const mutation of mutations ) {
              if ( mutation.addedNodes.length === 0 ) { continue; }
              for ( const node of mutation.addedNodes ) {
                  if ( node.nodeType !== 1 ) { continue; }
                  shouldSanitize = true;
                  break;
              }
              if ( shouldSanitize ) { break; }
          }
          if ( shouldSanitize === false ) { return; }
          timer = safe.onIdle(( ) => {
              timer = undefined;
              sanitize();
          });
      };
      const start = ( ) => {
          if ( sanitize() === false ) { return; }
          observer = new MutationObserver(onDomChanged);
          observer.observe(document.body, {
              subtree: true,
              childList: true,
          });
      };
      runAt(( ) => { start(); }, 'interactive');
  }


  function jsonEdit(jsonq = '') {
      editOutboundObjectFn(false, 'JSON.parse', jsonq);
  }


  function jsonEditFetchRequest(jsonq = '', ...args) {
      jsonEditFetchRequestFn(false, jsonq, ...args);
  }


  function jsonEditFetchRequestFn(trusted, jsonq = '') {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix(
          `${trusted ? 'trusted-' : ''}json-edit-fetch-request`,
          jsonq
      );
      const jsonp = JSONPath.create(jsonq);
      if ( jsonp.valid === false || jsonp.value !== undefined && trusted !== true ) {
          return safe.uboLog(logPrefix, 'Bad JSONPath query');
      }
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 2);
      const propNeedles = parsePropertiesToMatchFn(extraArgs.propsToMatch, 'url');
      const filterBody = body => {
          if ( typeof body !== 'string' ) { return; }
          let data;
          try { data = safe.JSON_parse(body); }
          catch { }
          if ( data instanceof Object === false ) { return; }
          const objAfter = jsonp.apply(data);
          if ( objAfter === undefined ) { return; }
          return safe.JSON_stringify(objAfter);
      }
      const proxyHandler = context => {
          const args = context.callArgs;
          const [ resource, options ] = args;
          const bodyBefore = options?.body;
          if ( Boolean(bodyBefore) === false ) { return context.reflect(); }
          const bodyAfter = filterBody(bodyBefore);
          if ( bodyAfter === undefined || bodyAfter === bodyBefore ) {
              return context.reflect();
          }
          if ( propNeedles.size !== 0 ) {
              const props = collateFetchArgumentsFn(resource, options);
              const matched = matchObjectPropertiesFn(propNeedles, props);
              if ( matched === undefined ) { return context.reflect(); }
              if ( safe.logLevel > 1 ) {
                  safe.uboLog(logPrefix, `Matched "propsToMatch":\n\t${matched.join('\n\t')}`);
              }
          }
          safe.uboLog(logPrefix, 'Edited');
          if ( safe.logLevel > 1 ) {
              safe.uboLog(logPrefix, `After edit:\n${bodyAfter}`);
          }
          options.body = bodyAfter;
          return context.reflect();
      };
      proxyApplyFn('fetch', proxyHandler);
      proxyApplyFn('Request', proxyHandler);
  }


  function jsonEditFetchResponse(jsonq = '', ...args) {
      jsonEditFetchResponseFn(false, jsonq, ...args);
  }


  function jsonEditFetchResponseFn(trusted, jsonq = '') {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix(
          `${trusted ? 'trusted-' : ''}json-edit-fetch-response`,
          jsonq
      );
      const jsonp = JSONPath.create(jsonq);
      if ( jsonp.valid === false || jsonp.value !== undefined && trusted !== true ) {
          return safe.uboLog(logPrefix, 'Bad JSONPath query');
      }
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 2);
      const propNeedles = parsePropertiesToMatchFn(extraArgs.propsToMatch, 'url');
      proxyApplyFn('fetch', function(context) {
          const args = context.callArgs;
          const fetchPromise = context.reflect();
          if ( propNeedles.size !== 0 ) {
              const props = collateFetchArgumentsFn(...args);
              const matched = matchObjectPropertiesFn(propNeedles, props);
              if ( matched === undefined ) { return fetchPromise; }
              if ( safe.logLevel > 1 ) {
                  safe.uboLog(logPrefix, `Matched "propsToMatch":\n\t${matched.join('\n\t')}`);
              }
          }
          return fetchPromise.then(responseBefore => {
              const response = responseBefore.clone();
              return response.json().then(obj => {
                  if ( typeof obj !== 'object' ) { return responseBefore; }
                  const objAfter = jsonp.apply(obj);
                  if ( objAfter === undefined ) { return responseBefore; }
                  safe.uboLog(logPrefix, 'Edited');
                  const responseAfter = Response.json(objAfter, {
                      status: responseBefore.status,
                      statusText: responseBefore.statusText,
                      headers: responseBefore.headers,
                  });
                  Object.defineProperties(responseAfter, {
                      ok: { value: responseBefore.ok },
                      redirected: { value: responseBefore.redirected },
                      type: { value: responseBefore.type },
                      url: { value: responseBefore.url },
                  });
                  return responseAfter;
              }).catch(reason => {
                  safe.uboErr(logPrefix, 'Error:', reason);
                  return responseBefore;
              });
          }).catch(reason => {
              safe.uboErr(logPrefix, 'Error:', reason);
              return fetchPromise;
          });
      });
  }


  function jsonEditXhrRequest(jsonq = '', ...args) {
      jsonEditXhrRequestFn(false, jsonq, ...args);
  }


  function jsonEditXhrRequestFn(trusted, jsonq = '') {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix(
          `${trusted ? 'trusted-' : ''}json-edit-xhr-request`,
          jsonq
      );
      const xhrInstances = new WeakMap();
      const jsonp = JSONPath.create(jsonq);
      if ( jsonp.valid === false || jsonp.value !== undefined && trusted !== true ) {
          return safe.uboLog(logPrefix, 'Bad JSONPath query');
      }
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 2);
      const propNeedles = parsePropertiesToMatchFn(extraArgs.propsToMatch, 'url');
      self.XMLHttpRequest = class extends self.XMLHttpRequest {
          open(method, url, ...args) {
              const xhrDetails = { method, url };
              const matched = propNeedles.size === 0 ||
                  matchObjectPropertiesFn(propNeedles, xhrDetails);
              if ( matched ) {
                  if ( safe.logLevel > 1 && Array.isArray(matched) ) {
                      safe.uboLog(logPrefix, `Matched "propsToMatch":\n\t${matched.join('\n\t')}`);
                  }
                  xhrInstances.set(this, xhrDetails);
              }
              return super.open(method, url, ...args);
          }
          send(body) {
              const xhrDetails = xhrInstances.get(this);
              if ( xhrDetails ) {
                  body = this.#filterBody(body) || body;
              }
              super.send(body);
          }
          #filterBody(body) {
              if ( typeof body !== 'string' ) { return; }
              let data;
              try { data = safe.JSON_parse(body); }
              catch { }
              if ( data instanceof Object === false ) { return; }
              const objAfter = jsonp.apply(data);
              if ( objAfter === undefined ) { return; }
              body = safe.JSON_stringify(objAfter);
              safe.uboLog(logPrefix, 'Edited');
              if ( safe.logLevel > 1 ) {
                  safe.uboLog(logPrefix, `After edit:\n${body}`);
              }
              return body;
          }
      };
  }


  function jsonEditXhrResponse(jsonq = '', ...args) {
      jsonEditXhrResponseFn(false, jsonq, ...args);
  }


  function jsonEditXhrResponseFn(trusted, jsonq = '') {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix(
          `${trusted ? 'trusted-' : ''}json-edit-xhr-response`,
          jsonq
      );
      const xhrInstances = new WeakMap();
      const jsonp = JSONPath.create(jsonq);
      if ( jsonp.valid === false || jsonp.value !== undefined && trusted !== true ) {
          return safe.uboLog(logPrefix, 'Bad JSONPath query');
      }
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 2);
      const propNeedles = parsePropertiesToMatchFn(extraArgs.propsToMatch, 'url');
      self.XMLHttpRequest = class extends self.XMLHttpRequest {
          open(method, url, ...args) {
              const xhrDetails = { method, url };
              const matched = propNeedles.size === 0 ||
                  matchObjectPropertiesFn(propNeedles, xhrDetails);
              if ( matched ) {
                  if ( safe.logLevel > 1 && Array.isArray(matched) ) {
                      safe.uboLog(logPrefix, `Matched "propsToMatch":\n\t${matched.join('\n\t')}`);
                  }
                  xhrInstances.set(this, xhrDetails);
              }
              return super.open(method, url, ...args);
          }
          get response() {
              const innerResponse = super.response;
              const xhrDetails = xhrInstances.get(this);
              if ( xhrDetails === undefined ) { return innerResponse; }
              const responseLength = typeof innerResponse === 'string'
                  ? innerResponse.length
                  : undefined;
              if ( xhrDetails.lastResponseLength !== responseLength ) {
                  xhrDetails.response = undefined;
                  xhrDetails.lastResponseLength = responseLength;
              }
              if ( xhrDetails.response !== undefined ) {
                  return xhrDetails.response;
              }
              let obj;
              if ( typeof innerResponse === 'object' ) {
                  obj = innerResponse;
              } else if ( typeof innerResponse === 'string' ) {
                  try { obj = safe.JSON_parse(innerResponse); } catch { }
              }
              if ( typeof obj !== 'object' || obj === null ) {
                  return (xhrDetails.response = innerResponse);
              }
              const objAfter = jsonp.apply(obj);
              if ( objAfter === undefined ) {
                  return (xhrDetails.response = innerResponse);
              }
              safe.uboLog(logPrefix, 'Edited');
              const outerResponse = typeof innerResponse === 'string'
                  ? JSONPath.toJSON(objAfter, safe.JSON_stringify)
                  : objAfter;
              return (xhrDetails.response = outerResponse);
          }
          get responseText() {
              const response = this.response;
              return typeof response !== 'string'
                  ? super.responseText
                  : response;
          }
      };
  }


  function jsonPrune(
      rawPrunePaths = '',
      rawNeedlePaths = '',
      stackNeedle = ''
  ) {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('json-prune', rawPrunePaths, rawNeedlePaths, stackNeedle);
      const stackNeedleDetails = safe.initPattern(stackNeedle, { canNegate: true });
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 3);
      proxyApplyFn('JSON.parse', function(context) {
          const objBefore = context.reflect();
          if ( rawPrunePaths === '' ) {
              safe.uboLog(logPrefix, safe.JSON_stringify(objBefore, null, 2));
          }
          const objAfter = objectPruneFn(
              objBefore,
              rawPrunePaths,
              rawNeedlePaths,
              stackNeedleDetails,
              extraArgs
          );
          if ( objAfter === undefined ) { return objBefore; }
          safe.uboLog(logPrefix, 'Pruned');
          if ( safe.logLevel > 1 ) {
              safe.uboLog(logPrefix, `After pruning:\n${safe.JSON_stringify(objAfter, null, 2)}`);
          }
          return objAfter;
      });
  }


  function jsonPruneFetchResponse(
      rawPrunePaths = '',
      rawNeedlePaths = ''
  ) {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('json-prune-fetch-response', rawPrunePaths, rawNeedlePaths);
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 2);
      const propNeedles = parsePropertiesToMatchFn(extraArgs.propsToMatch, 'url');
      const stackNeedle = safe.initPattern(extraArgs.stackToMatch || '', { canNegate: true });
      const logall = rawPrunePaths === '';
      const applyHandler = function(target, thisArg, args) {
          const fetchPromise = Reflect.apply(target, thisArg, args);
          if ( propNeedles.size !== 0 ) {
              const props = collateFetchArgumentsFn(...args);
              const matched = matchObjectPropertiesFn(propNeedles, props);
              if ( matched === undefined ) { return fetchPromise; }
              if ( safe.logLevel > 1 ) {
                  safe.uboLog(logPrefix, `Matched "propsToMatch":\n\t${matched.join('\n\t')}`);
              }
          }
          return fetchPromise.then(responseBefore => {
              const response = responseBefore.clone();
              return response.json().then(objBefore => {
                  if ( typeof objBefore !== 'object' ) { return responseBefore; }
                  if ( logall ) {
                      safe.uboLog(logPrefix, safe.JSON_stringify(objBefore, null, 2));
                      return responseBefore;
                  }
                  const objAfter = objectPruneFn(
                      objBefore,
                      rawPrunePaths,
                      rawNeedlePaths,
                      stackNeedle,
                      extraArgs
                  );
                  if ( typeof objAfter !== 'object' ) { return responseBefore; }
                  safe.uboLog(logPrefix, 'Pruned');
                  const responseAfter = Response.json(objAfter, {
                      status: responseBefore.status,
                      statusText: responseBefore.statusText,
                      headers: responseBefore.headers,
                  });
                  Object.defineProperties(responseAfter, {
                      ok: { value: responseBefore.ok },
                      redirected: { value: responseBefore.redirected },
                      type: { value: responseBefore.type },
                      url: { value: responseBefore.url },
                  });
                  return responseAfter;
              }).catch(reason => {
                  safe.uboErr(logPrefix, 'Error:', reason);
                  return responseBefore;
              });
          }).catch(reason => {
              safe.uboErr(logPrefix, 'Error:', reason);
              return fetchPromise;
          });
      };
      self.fetch = new Proxy(self.fetch, {
          apply: applyHandler
      });
  }


  function jsonPruneXhrResponse(
      rawPrunePaths = '',
      rawNeedlePaths = ''
  ) {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('json-prune-xhr-response', rawPrunePaths, rawNeedlePaths);
      const xhrInstances = new WeakMap();
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 2);
      const propNeedles = parsePropertiesToMatchFn(extraArgs.propsToMatch, 'url');
      const stackNeedle = safe.initPattern(extraArgs.stackToMatch || '', { canNegate: true });
      self.XMLHttpRequest = class extends self.XMLHttpRequest {
          open(method, url, ...args) {
              const xhrDetails = { method, url };
              let outcome = 'match';
              if ( propNeedles.size !== 0 ) {
                  if ( matchObjectPropertiesFn(propNeedles, xhrDetails) === undefined ) {
                      outcome = 'nomatch';
                  }
              }
              if ( outcome === 'match' ) {
                  if ( safe.logLevel > 1 ) {
                      safe.uboLog(logPrefix, `Matched optional "propsToMatch", "${extraArgs.propsToMatch}"`);
                  }
                  xhrInstances.set(this, xhrDetails);
              }
              return super.open(method, url, ...args);
          }
          get response() {
              const innerResponse = super.response;
              const xhrDetails = xhrInstances.get(this);
              if ( xhrDetails === undefined ) {
                  return innerResponse;
              }
              const responseLength = typeof innerResponse === 'string'
                  ? innerResponse.length
                  : undefined;
              if ( xhrDetails.lastResponseLength !== responseLength ) {
                  xhrDetails.response = undefined;
                  xhrDetails.lastResponseLength = responseLength;
              }
              if ( xhrDetails.response !== undefined ) {
                  return xhrDetails.response;
              }
              let objBefore;
              if ( typeof innerResponse === 'object' ) {
                  objBefore = innerResponse;
              } else if ( typeof innerResponse === 'string' ) {
                  try {
                      objBefore = safe.JSON_parse(innerResponse);
                  } catch {
                  }
              }
              if ( typeof objBefore !== 'object' ) {
                  return (xhrDetails.response = innerResponse);
              }
              const objAfter = objectPruneFn(
                  objBefore,
                  rawPrunePaths,
                  rawNeedlePaths,
                  stackNeedle,
                  extraArgs
              );
              let outerResponse;
              if ( typeof objAfter === 'object' ) {
                  outerResponse = typeof innerResponse === 'string'
                      ? safe.JSON_stringify(objAfter)
                      : objAfter;
                  safe.uboLog(logPrefix, 'Pruned');
              } else {
                  outerResponse = innerResponse;
              }
              return (xhrDetails.response = outerResponse);
          }
          get responseText() {
              const response = this.response;
              return typeof response !== 'string'
                  ? super.responseText
                  : response;
          }
      };
  }


  function jsonlEditFetchResponse(jsonq = '', ...args) {
      jsonlEditFetchResponseFn(false, jsonq, ...args);
  }


  function jsonlEditFetchResponseFn(trusted, jsonq = '') {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix(
          `${trusted ? 'trusted-' : ''}jsonl-edit-fetch-response`,
          jsonq
      );
      const jsonp = JSONPath.create(jsonq);
      if ( jsonp.valid === false || jsonp.value !== undefined && trusted !== true ) {
          return safe.uboLog(logPrefix, 'Bad JSONPath query');
      }
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 2);
      const propNeedles = parsePropertiesToMatchFn(extraArgs.propsToMatch, 'url');
      const logall = jsonq === '';
      proxyApplyFn('fetch', function(context) {
          const args = context.callArgs;
          const fetchPromise = context.reflect();
          if ( propNeedles.size !== 0 ) {
              const props = collateFetchArgumentsFn(...args);
              const matched = matchObjectPropertiesFn(propNeedles, props);
              if ( matched === undefined ) { return fetchPromise; }
              if ( safe.logLevel > 1 ) {
                  safe.uboLog(logPrefix, `Matched "propsToMatch":\n\t${matched.join('\n\t')}`);
              }
          }
          return fetchPromise.then(responseBefore => {
              const response = responseBefore.clone();
              return response.text().then(textBefore => {
                  if ( typeof textBefore !== 'string' ) { return textBefore; }
                  if ( logall ) {
                      safe.uboLog(logPrefix, textBefore);
                      return responseBefore;
                  }
                  const textAfter = jsonlEditFn(jsonp, textBefore);
                  if ( textAfter === textBefore ) { return responseBefore; }
                  safe.uboLog(logPrefix, 'Pruned');
                  const responseAfter = new Response(textAfter, {
                      status: responseBefore.status,
                      statusText: responseBefore.statusText,
                      headers: responseBefore.headers,
                  });
                  Object.defineProperties(responseAfter, {
                      ok: { value: responseBefore.ok },
                      redirected: { value: responseBefore.redirected },
                      type: { value: responseBefore.type },
                      url: { value: responseBefore.url },
                  });
                  return responseAfter;
              }).catch(reason => {
                  safe.uboErr(logPrefix, 'Error:', reason);
                  return responseBefore;
              });
          }).catch(reason => {
              safe.uboErr(logPrefix, 'Error:', reason);
              return fetchPromise;
          });
      });
  }


  function jsonlEditFn(jsonp, text = '') {
      const safe = safeSelf();
      const lineSeparator = /\r?\n/.exec(text)?.[0] || '\n';
      const linesBefore = text.split('\n');
      const linesAfter = [];
      for ( const lineBefore of linesBefore ) {
          let obj;
          try { obj = safe.JSON_parse(lineBefore); } catch { }
          if ( typeof obj !== 'object' || obj === null ) {
              linesAfter.push(lineBefore);
              continue;
          }
          const objAfter = jsonp.apply(obj);
          if ( objAfter === undefined ) {
              linesAfter.push(lineBefore);
              continue;
          }
          const lineAfter = safe.JSON_stringify(objAfter);
          linesAfter.push(lineAfter);
      }
      return linesAfter.join(lineSeparator);
  }


  function jsonlEditXhrResponse(jsonq = '', ...args) {
      jsonlEditXhrResponseFn(false, jsonq, ...args);
  }


  function jsonlEditXhrResponseFn(trusted, jsonq = '') {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix(
          `${trusted ? 'trusted-' : ''}jsonl-edit-xhr-response`,
          jsonq
      );
      const xhrInstances = new WeakMap();
      const jsonp = JSONPath.create(jsonq);
      if ( jsonp.valid === false || jsonp.value !== undefined && trusted !== true ) {
          return safe.uboLog(logPrefix, 'Bad JSONPath query');
      }
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 2);
      const propNeedles = parsePropertiesToMatchFn(extraArgs.propsToMatch, 'url');
      self.XMLHttpRequest = class extends self.XMLHttpRequest {
          open(method, url, ...args) {
              const xhrDetails = { method, url };
              const matched = propNeedles.size === 0 ||
                  matchObjectPropertiesFn(propNeedles, xhrDetails);
              if ( matched ) {
                  if ( safe.logLevel > 1 && Array.isArray(matched) ) {
                      safe.uboLog(logPrefix, `Matched "propsToMatch":\n\t${matched.join('\n\t')}`);
                  }
                  xhrInstances.set(this, xhrDetails);
              }
              return super.open(method, url, ...args);
          }
          get response() {
              const innerResponse = super.response;
              const xhrDetails = xhrInstances.get(this);
              if ( xhrDetails === undefined ) {
                  return innerResponse;
              }
              const responseLength = typeof innerResponse === 'string'
                  ? innerResponse.length
                  : undefined;
              if ( xhrDetails.lastResponseLength !== responseLength ) {
                  xhrDetails.response = undefined;
                  xhrDetails.lastResponseLength = responseLength;
              }
              if ( xhrDetails.response !== undefined ) {
                  return xhrDetails.response;
              }
              if ( typeof innerResponse !== 'string' ) {
                  return (xhrDetails.response = innerResponse);
              }
              const outerResponse = jsonlEditFn(jsonp, innerResponse);
              if ( outerResponse !== innerResponse ) {
                  safe.uboLog(logPrefix, 'Pruned');
              }
              return (xhrDetails.response = outerResponse);
          }
          get responseText() {
              const response = this.response;
              return typeof response !== 'string'
                  ? super.responseText
                  : response;
          }
      };
  }


  function m3uPrune(
      m3uPattern = '',
      urlPattern = ''
  ) {
      if ( typeof m3uPattern !== 'string' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('m3u-prune', m3uPattern, urlPattern);
      const toLog = [];
      const regexFromArg = arg => {
          if ( arg === '' ) { return /^/; }
          const match = /^\/(.+)\/([gms]*)$/.exec(arg);
          if ( match !== null ) {
              let flags = match[2] || '';
              if ( flags.includes('m') ) { flags += 's'; }
              return new RegExp(match[1], flags);
          }
          return new RegExp(
              arg.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*+/g, '.*?')
          );
      };
      const reM3u = regexFromArg(m3uPattern);
      const reUrl = regexFromArg(urlPattern);
      const pruneSpliceoutBlock = (lines, i) => {
          if ( lines[i].startsWith('#EXT-X-CUE:TYPE="SpliceOut"') === false ) {
              return false;
          }
          toLog.push(`\t${lines[i]}`);
          lines[i] = undefined; i += 1;
          if ( lines[i].startsWith('#EXT-X-ASSET:CAID') ) {
              toLog.push(`\t${lines[i]}`);
              lines[i] = undefined; i += 1;
          }
          if ( lines[i].startsWith('#EXT-X-SCTE35:') ) {
              toLog.push(`\t${lines[i]}`);
              lines[i] = undefined; i += 1;
          }
          if ( lines[i].startsWith('#EXT-X-CUE-IN') ) {
              toLog.push(`\t${lines[i]}`);
              lines[i] = undefined; i += 1;
          }
          if ( lines[i].startsWith('#EXT-X-SCTE35:') ) {
              toLog.push(`\t${lines[i]}`);
              lines[i] = undefined; i += 1;
          }
          return true;
      };
      const pruneInfBlock = (lines, i) => {
          if ( lines[i].startsWith('#EXTINF') === false ) { return false; }
          if ( reM3u.test(lines[i+1]) === false ) { return false; }
          toLog.push('Discarding', `\t${lines[i]}, \t${lines[i+1]}`);
          lines[i] = lines[i+1] = undefined; i += 2;
          if ( lines[i].startsWith('#EXT-X-DISCONTINUITY') ) {
              toLog.push(`\t${lines[i]}`);
              lines[i] = undefined; i += 1;
          }
          return true;
      };
      const pruner = text => {
          if ( (/^\s*#EXTM3U/.test(text)) === false ) { return text; }
          if ( m3uPattern === '' ) {
              safe.uboLog(` Content:\n${text}`);
              return text;
          }
          if ( reM3u.multiline ) {
              reM3u.lastIndex = 0;
              for (;;) {
                  const match = reM3u.exec(text);
                  if ( match === null ) { break; }
                  let discard = match[0];
                  let before = text.slice(0, match.index);
                  if (
                      /^[\n\r]+/.test(discard) === false &&
                      /[\n\r]+$/.test(before) === false
                  ) {
                      const startOfLine = /[^\n\r]+$/.exec(before);
                      if ( startOfLine !== null ) {
                          before = before.slice(0, startOfLine.index);
                          discard = startOfLine[0] + discard;
                      }
                  }
                  let after = text.slice(match.index + match[0].length);
                  if (
                      /[\n\r]+$/.test(discard) === false &&
                      /^[\n\r]+/.test(after) === false
                  ) {
                      const endOfLine = /^[^\n\r]+/.exec(after);
                      if ( endOfLine !== null ) {
                          after = after.slice(endOfLine.index);
                          discard += discard + endOfLine[0];
                      }
                  }
                  text = before.trim() + '\n' + after.trim();
                  reM3u.lastIndex = before.length + 1;
                  toLog.push('Discarding', ...safe.String_split.call(discard, /\n+/).map(s => `\t${s}`));
                  if ( reM3u.global === false ) { break; }
              }
              return text;
          }
          const lines = safe.String_split.call(text, /\n\r|\n|\r/);
          for ( let i = 0; i < lines.length; i++ ) {
              if ( lines[i] === undefined ) { continue; }
              if ( pruneSpliceoutBlock(lines, i) ) { continue; }
              if ( pruneInfBlock(lines, i) ) { continue; }
          }
          return lines.filter(l => l !== undefined).join('\n');
      };
      const urlFromArg = arg => {
          if ( typeof arg === 'string' ) { return arg; }
          if ( arg instanceof Request ) { return arg.url; }
          return String(arg);
      };
      proxyApplyFn('fetch', async function fetch(context) {
          const args = context.callArgs;
          const fetchPromise = context.reflect();
          if ( reUrl.test(urlFromArg(args[0])) === false ) { return fetchPromise; }
          const responseBefore = await fetchPromise;
          const responseClone = responseBefore.clone();
          const textBefore = await responseClone.text();
          const textAfter = pruner(textBefore);
          if ( textAfter === textBefore ) { return responseBefore; }
          const responseAfter = new Response(textAfter, {
              status: responseBefore.status,
              statusText: responseBefore.statusText,
              headers: responseBefore.headers,
          });
          Object.defineProperties(responseAfter, {
              url: { value: responseBefore.url },
              type: { value: responseBefore.type },
          });
          if ( toLog.length !== 0 ) {
              toLog.unshift(logPrefix);
              safe.uboLog(toLog.join('\n'));
          }
          return responseAfter;
      })
      self.XMLHttpRequest.prototype.open = new Proxy(self.XMLHttpRequest.prototype.open, {
          apply: async (target, thisArg, args) => {
              if ( reUrl.test(urlFromArg(args[1])) === false ) {
                  return Reflect.apply(target, thisArg, args);
              }
              thisArg.addEventListener('readystatechange', function() {
                  if ( thisArg.readyState !== 4 ) { return; }
                  const type = thisArg.responseType;
                  if ( type !== '' && type !== 'text' ) { return; }
                  const textin = thisArg.responseText;
                  const textout = pruner(textin);
                  if ( textout === textin ) { return; }
                  Object.defineProperty(thisArg, 'response', { value: textout });
                  Object.defineProperty(thisArg, 'responseText', { value: textout });
                  if ( toLog.length !== 0 ) {
                      toLog.unshift(logPrefix);
                      safe.uboLog(toLog.join('\n'));
                  }
              });
              return Reflect.apply(target, thisArg, args);
          }
      });
  }


  function matchObjectPropertiesFn(propNeedles, ...objs) {
      const safe = safeSelf();
      const matched = [];
      for ( const obj of objs ) {
          if ( obj instanceof Object === false ) { continue; }
          for ( const [ prop, details ] of propNeedles ) {
              let value = obj[prop];
              if ( value === undefined ) { continue; }
              if ( typeof value !== 'string' ) {
                  try { value = safe.JSON_stringify(value); }
                  catch { }
                  if ( typeof value !== 'string' ) { continue; }
              }
              if ( safe.testPattern(details, value) === false ) { return; }
              matched.push(`${prop}: ${value}`);
          }
      }
      return matched;
  }


  function matchesStackTraceFn(
      needleDetails,
      logLevel = ''
  ) {
      const safe = safeSelf();
      const exceptionToken = getExceptionTokenFn();
      const error = new safe.Error(exceptionToken);
      const docURL = new URL(self.location.href);
      docURL.hash = '';
      // Normalize stack trace
      const reLine = /(.*?@)?(\S+)(:\d+):\d+\)?$/;
      const lines = [];
      for ( let line of safe.String_split.call(error.stack, /[\n\r]+/) ) {
          if ( line.includes(exceptionToken) ) { continue; }
          line = line.trim();
          const match = safe.RegExp_exec.call(reLine, line);
          if ( match === null ) { continue; }
          let url = match[2];
          if ( url.startsWith('(') ) { url = url.slice(1); }
          if ( url === docURL.href ) {
              url = 'inlineScript';
          } else if ( url.startsWith('<anonymous>') ) {
              url = 'injectedScript';
          }
          let fn = match[1] !== undefined
              ? match[1].slice(0, -1)
              : line.slice(0, match.index).trim();
          if ( fn.startsWith('at') ) { fn = fn.slice(2).trim(); }
          let rowcol = match[3];
          lines.push(' ' + `${fn} ${url}${rowcol}:1`.trim());
      }
      lines[0] = `stackDepth:${lines.length-1}`;
      const stack = lines.join('\t');
      const r = needleDetails.matchAll !== true &&
          safe.testPattern(needleDetails, stack);
      if (
          logLevel === 'all' ||
          logLevel === 'match' && r ||
          logLevel === 'nomatch' && !r
      ) {
          safe.uboLog(stack.replace(/\t/g, '\n'));
      }
      return r;
  }


  function multiup() {
      const handler = ev => {
          const target = ev.target;
          if ( target.matches('button[link]') === false ) { return; }
          const ancestor = target.closest('form');
          if ( ancestor === null ) { return; }
          if ( ancestor !== target.parentElement ) { return; }
          const link = (target.getAttribute('link') || '').trim();
          if ( link === '' ) { return; }
          ev.preventDefault();
          ev.stopPropagation();
          document.location.href = link;
      };
      document.addEventListener('click', handler, { capture: true });
  }


  function noEvalIf(
      needle = ''
  ) {
      if ( typeof needle !== 'string' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('noeval-if', needle);
      const reNeedle = safe.patternToRegex(needle);
      proxyApplyFn('eval', function(context) {
          const { callArgs } = context;
          const a = String(callArgs[0]);
          if ( needle !== '' && reNeedle.test(a) ) {
              safe.uboLog(logPrefix, 'Prevented:\n', a);
              return;
          }
          if ( needle === '' || safe.logLevel > 1 ) {
              safe.uboLog(logPrefix, 'Not prevented:\n', a);
          }
          return context.reflect();
      });
  }


  function noWebrtc() {
      var rtcName = window.RTCPeerConnection ? 'RTCPeerConnection' : (
          window.webkitRTCPeerConnection ? 'webkitRTCPeerConnection' : ''
      );
      if ( rtcName === '' ) { return; }
      var log = console.log.bind(console);
      var pc = function(cfg) {
          log('Document tried to create an RTCPeerConnection: %o', cfg);
      };
      const noop = function() {
      };
      pc.prototype = {
          close: noop,
          createDataChannel: noop,
          createOffer: noop,
          setRemoteDescription: noop,
          toString: function() {
              return '[object RTCPeerConnection]';
          }
      };
      var z = window[rtcName];
      window[rtcName] = pc.bind(window);
      if ( z.prototype ) {
          z.prototype.createDataChannel = function() {
              return {
                  close: function() {},
                  send: function() {}
              };
          }.bind(null);
      }
  }


  function noWindowOpenIf(
      pattern = '',
      delay = '',
      decoy = ''
  ) {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('no-window-open-if', pattern, delay, decoy);
      const targetMatchResult = pattern.startsWith('!') === false;
      if ( targetMatchResult === false ) {
          pattern = pattern.slice(1);
      }
      const rePattern = safe.patternToRegex(pattern);
      const autoRemoveAfter = (parseFloat(delay) || 0) * 1000;
      const setTimeout = self.setTimeout;
      const createDecoy = function(tag, urlProp, url) {
          const decoyElem = document.createElement(tag);
          decoyElem[urlProp] = url;
          decoyElem.style.setProperty('height','1px', 'important');
          decoyElem.style.setProperty('position','fixed', 'important');
          decoyElem.style.setProperty('top','-1px', 'important');
          decoyElem.style.setProperty('width','1px', 'important');
          document.body.appendChild(decoyElem);
          setTimeout(( ) => { decoyElem.remove(); }, autoRemoveAfter);
          return decoyElem;
      };
      const noopFunc = function(){};
      proxyApplyFn('open', function open(context) {
          if ( pattern === 'debug' && safe.logLevel !== 0 ) {
              debugger; // eslint-disable-line no-debugger
              return context.reflect();
          }
          const { callArgs } = context;
          const haystack = callArgs.join(' ');
          if ( rePattern.test(haystack) !== targetMatchResult ) {
              if ( safe.logLevel > 1 ) {
                  safe.uboLog(logPrefix, `Allowed (${callArgs.join(', ')})`);
              }
              return context.reflect();
          }
          safe.uboLog(logPrefix, `Prevented (${callArgs.join(', ')})`);
          if ( delay === '' ) { return null; }
          if ( decoy === 'blank' ) {
              callArgs[0] = 'about:blank';
              const r = context.reflect();
              setTimeout(( ) => { r.close(); }, autoRemoveAfter);
              return r;
          }
          const decoyElem = decoy === 'obj'
              ? createDecoy('object', 'data', ...callArgs)
              : createDecoy('iframe', 'src', ...callArgs);
          let popup = decoyElem.contentWindow;
          if ( typeof popup === 'object' && popup !== null ) {
              Object.defineProperty(popup, 'closed', { value: false });
          } else {
              popup = new Proxy(self, {
                  get: function(target, prop, ...args) {
                      if ( prop === 'closed' ) { return false; }
                      const r = Reflect.get(target, prop, ...args);
                      if ( typeof r === 'function' ) { return noopFunc; }
                      return r;
                  },
                  set: function(...args) {
                      return Reflect.set(...args);
                  },
              });
          }
          if ( safe.logLevel !== 0 ) {
              popup = new Proxy(popup, {
                  get: function(target, prop, ...args) {
                      const r = Reflect.get(target, prop, ...args);
                      safe.uboLog(logPrefix, `popup / get ${prop} === ${r}`);
                      if ( typeof r === 'function' ) {
                          return (...args) => { return r.call(target, ...args); };
                      }
                      return r;
                  },
                  set: function(target, prop, value, ...args) {
                      safe.uboLog(logPrefix, `popup / set ${prop} = ${value}`);
                      return Reflect.set(target, prop, value, ...args);
                  },
              });
          }
          return popup;
      });
  }


  function objectFindOwnerFn(
      root,
      path,
      prune = false
  ) {
      const safe = safeSelf();
      let owner = root;
      let chain = path;
      for (;;) {
          if ( typeof owner !== 'object' || owner === null  ) { return false; }
          const pos = chain.indexOf('.');
          if ( pos === -1 ) {
              if ( prune === false ) {
                  return safe.Object_hasOwn(owner, chain);
              }
              let modified = false;
              if ( chain === '*' ) {
                  for ( const key in owner ) {
                      if ( safe.Object_hasOwn(owner, key) === false ) { continue; }
                      delete owner[key];
                      modified = true;
                  }
              } else if ( safe.Object_hasOwn(owner, chain) ) {
                  delete owner[chain];
                  modified = true;
              }
              return modified;
          }
          const prop = chain.slice(0, pos);
          const next = chain.slice(pos + 1);
          let found = false;
          if ( prop === '[-]' && Array.isArray(owner) ) {
              let i = owner.length;
              while ( i-- ) {
                  if ( objectFindOwnerFn(owner[i], next) === false ) { continue; }
                  owner.splice(i, 1);
                  found = true;
              }
              return found;
          }
          if ( prop === '{-}' && owner instanceof Object ) {
              for ( const key of Object.keys(owner) ) {
                  if ( objectFindOwnerFn(owner[key], next) === false ) { continue; }
                  delete owner[key];
                  found = true;
              }
              return found;
          }
          if (
              prop === '[]' && Array.isArray(owner) ||
              prop === '{}' && owner instanceof Object ||
              prop === '*' && owner instanceof Object
          ) {
              for ( const key of Object.keys(owner) ) {
                  if (objectFindOwnerFn(owner[key], next, prune) === false ) { continue; }
                  found = true;
              }
              return found;
          }
          if ( safe.Object_hasOwn(owner, prop) === false ) { return false; }
          owner = owner[prop];
          chain = chain.slice(pos + 1);
      }
  }


  function objectPruneFn(
      obj,
      rawPrunePaths,
      rawNeedlePaths,
      stackNeedleDetails = { matchAll: true },
      extraArgs = {}
  ) {
      if ( typeof rawPrunePaths !== 'string' ) { return; }
      const safe = safeSelf();
      const prunePaths = rawPrunePaths !== ''
          ? safe.String_split.call(rawPrunePaths, / +/)
          : [];
      const needlePaths = prunePaths.length !== 0 && rawNeedlePaths !== ''
          ? safe.String_split.call(rawNeedlePaths, / +/)
          : [];
      if ( stackNeedleDetails.matchAll !== true ) {
          if ( matchesStackTraceFn(stackNeedleDetails, extraArgs.logstack) === false ) {
              return;
          }
      }
      if ( objectPruneFn.mustProcess === undefined ) {
          objectPruneFn.mustProcess = (root, needlePaths) => {
              for ( const needlePath of needlePaths ) {
                  if ( objectFindOwnerFn(root, needlePath) === false ) {
                      return false;
                  }
              }
              return true;
          };
      }
      if ( prunePaths.length === 0 ) { return; }
      let outcome = 'nomatch';
      if ( objectPruneFn.mustProcess(obj, needlePaths) ) {
          for ( const path of prunePaths ) {
              if ( objectFindOwnerFn(obj, path, true) ) {
                  outcome = 'match';
              }
          }
      }
      if ( outcome === 'match' ) { return obj; }
  }


  function overlayBuster(allFrames) {
      if ( allFrames === '' && window !== window.top ) { return; }
      var tstart;
      var ttl = 30000;
      var delay = 0;
      var delayStep = 50;
      var buster = function() {
          var docEl = document.documentElement,
              bodyEl = document.body,
              vw = Math.min(docEl.clientWidth, window.innerWidth),
              vh = Math.min(docEl.clientHeight, window.innerHeight),
              tol = Math.min(vw, vh) * 0.05,
              el = document.elementFromPoint(vw/2, vh/2),
              style, rect;
          for (;;) {
              if ( el === null || el.parentNode === null || el === bodyEl ) {
                  break;
              }
              style = window.getComputedStyle(el);
              if ( parseInt(style.zIndex, 10) >= 1000 || style.position === 'fixed' ) {
                  rect = el.getBoundingClientRect();
                  if ( rect.left <= tol && rect.top <= tol && (vw - rect.right) <= tol && (vh - rect.bottom) < tol ) {
                      el.parentNode.removeChild(el);
                      tstart = Date.now();
                      el = document.elementFromPoint(vw/2, vh/2);
                      bodyEl.style.setProperty('overflow', 'auto', 'important');
                      docEl.style.setProperty('overflow', 'auto', 'important');
                      continue;
                  }
              }
              el = el.parentNode;
          }
          if ( (Date.now() - tstart) < ttl ) {
              delay = Math.min(delay + delayStep, 1000);
              setTimeout(buster, delay);
          }
      };
      var domReady = function(ev) {
          if ( ev ) {
              document.removeEventListener(ev.type, domReady);
          }
          tstart = Date.now();
          setTimeout(buster, delay);
      };
      if ( document.readyState === 'loading' ) {
          document.addEventListener('DOMContentLoaded', domReady);
      } else {
          domReady();
      }
  }


  function parsePropertiesToMatchFn(propsToMatch, implicit = '') {
      const safe = safeSelf();
      const needles = new Map();
      if ( propsToMatch === undefined || propsToMatch === '' ) { return needles; }
      const options = { canNegate: true };
      for ( const needle of safe.String_split.call(propsToMatch, /\s+/) ) {
          let [ prop, pattern ] = safe.String_split.call(needle, ':');
          if ( prop === '' ) { continue; }
          if ( pattern !== undefined && /[^$\w -]/.test(prop) ) {
              prop = `${prop}:${pattern}`;
              pattern = undefined;
          }
          if ( pattern !== undefined ) {
              needles.set(prop, safe.initPattern(pattern, options));
          } else if ( implicit !== '' ) {
              needles.set(implicit, safe.initPattern(prop, options));
          }
      }
      return needles;
  }


  function parseReplaceFn(s) {
      if ( s.charCodeAt(0) !== 0x2F /* / */ ) { return; }
      const parser = new ArglistParser('/');
      parser.nextArg(s, 1);
      let pattern = s.slice(parser.argBeg, parser.argEnd);
      if ( parser.transform ) {
          pattern = parser.normalizeArg(pattern);
      }
      if ( pattern === '' ) { return; }
      parser.nextArg(s, parser.separatorEnd);
      let replacement = s.slice(parser.argBeg, parser.argEnd);
      if ( parser.separatorEnd === parser.separatorBeg ) { return; }
      if ( parser.transform ) {
          replacement = parser.normalizeArg(replacement);
      }
      const flags = s.slice(parser.separatorEnd);
      try {
          return { re: new RegExp(pattern, flags), replacement };
      } catch {
      }
  }


  function preventAddEventListener(
      type = '',
      pattern = ''
  ) {
      const safe = safeSelf();
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 2);
      const logPrefix = safe.makeLogPrefix('prevent-addEventListener', type, pattern);
      const reType = safe.patternToRegex(type, undefined, true);
      const rePattern = safe.patternToRegex(pattern);
      const targetSelector = extraArgs.elements || undefined;
      const elementMatches = elem => {
          if ( targetSelector === 'window' ) { return elem === window; }
          if ( targetSelector === 'document' ) { return elem === document; }
          if ( elem && elem.matches && elem.matches(targetSelector) ) { return true; }
          const elems = Array.from(document.querySelectorAll(targetSelector));
          return elems.includes(elem);
      };
      const elementDetails = elem => {
          if ( elem instanceof Window ) { return 'window'; }
          if ( elem instanceof Document ) { return 'document'; }
          if ( elem instanceof Element === false ) { return '?'; }
          const parts = [];
          // https://github.com/uBlockOrigin/uAssets/discussions/17907#discussioncomment-9871079
          const id = String(elem.id);
          if ( id !== '' ) { parts.push(`#${CSS.escape(id)}`); }
          for ( let i = 0; i < elem.classList.length; i++ ) {
              parts.push(`.${CSS.escape(elem.classList.item(i))}`);
          }
          for ( let i = 0; i < elem.attributes.length; i++ ) {
              const attr = elem.attributes.item(i);
              if ( attr.name === 'id' ) { continue; }
              if ( attr.name === 'class' ) { continue; }
              parts.push(`[${CSS.escape(attr.name)}="${attr.value}"]`);
          }
          return parts.join('');
      };
      const shouldPrevent = (thisArg, type, handler) => {
          const matchesType = safe.RegExp_test.call(reType, type);
          const matchesHandler = safe.RegExp_test.call(rePattern, handler);
          const matchesEither = matchesType || matchesHandler;
          const matchesBoth = matchesType && matchesHandler;
          if ( safe.logLevel > 1 && matchesEither ) {
              debugger; // eslint-disable-line no-debugger
          }
          if ( matchesBoth && targetSelector !== undefined ) {
              if ( elementMatches(thisArg) === false ) { return false; }
          }
          return matchesBoth;
      };
      const proxyFn = function(context) {
          const { callArgs, thisArg } = context;
          let t, h;
          try {
              t = String(callArgs[0]);
              if ( typeof callArgs[1] === 'function' ) {
                  h = String(safe.Function_toString(callArgs[1]));
              } else if ( typeof callArgs[1] === 'object' && callArgs[1] !== null ) {
                  if ( typeof callArgs[1].handleEvent === 'function' ) {
                      h = String(safe.Function_toString(callArgs[1].handleEvent));
                  }
              } else {
                  h = String(callArgs[1]);
              }
          } catch {
          }
          if ( type === '' && pattern === '' ) {
              safe.uboLog(logPrefix, `Called: ${t}\n${h}\n${elementDetails(thisArg)}`);
          } else if ( shouldPrevent(thisArg, t, h) ) {
              return safe.uboLog(logPrefix, `Prevented: ${t}\n${h}\n${elementDetails(thisArg)}`);
          }
          return context.reflect();
      };
      runAt(( ) => {
          proxyApplyFn('EventTarget.prototype.addEventListener', proxyFn);
          if ( extraArgs.protect ) {
              const { addEventListener } = EventTarget.prototype;
              Object.defineProperty(EventTarget.prototype, 'addEventListener', {
                  set() { },
                  get() { return addEventListener; }
              });
          }
          proxyApplyFn('document.addEventListener', proxyFn);
          if ( extraArgs.protect ) {
              const { addEventListener } = document;
              Object.defineProperty(document, 'addEventListener', {
                  set() { },
                  get() { return addEventListener; }
              });
          }
      }, extraArgs.runAt);
  }


  function preventCanvas(
      contextType = ''
  ) {
      const safe = safeSelf();
      const pattern = safe.initPattern(contextType, { canNegate: true });
      const proto = globalThis.HTMLCanvasElement.prototype;
      proto.getContext = new Proxy(proto.getContext, {
          apply(target, thisArg, args) {
              if ( safe.testPattern(pattern, args[0]) ) { return null; }
              return Reflect.apply(target, thisArg, args);
          }
      });
  }


  function preventDialog(
      selector = '',
  ) {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('prevent-dialog', selector);
      const prevent = ( ) => {
          debouncer = undefined;
          const elems = document.querySelectorAll(`dialog${selector}`);
          for ( const elem of elems ) {
              if ( typeof elem.close !== 'function' ) { continue; }
              if ( elem.open === false ) { continue; }
              elem.close();
              safe.uboLog(logPrefix, 'Closed');
          }
      };
      let debouncer;
      const observer = new MutationObserver(( ) => {
          if ( debouncer !== undefined ) { return; }
          debouncer = requestAnimationFrame(prevent);
      });
      observer.observe(document, {
          attributes: true,
          childList: true,
          subtree: true,
      });
  }


  function preventFetch(...args) {
      preventFetchFn(false, ...args);
  }


  function preventFetchFn(
      trusted = false,
      propsToMatch = '',
      responseBody = '',
      responseType = ''
  ) {
      const safe = safeSelf();
      const setTimeout = self.setTimeout;
      const scriptletName = `${trusted ? 'trusted-' : ''}prevent-fetch`;
      const logPrefix = safe.makeLogPrefix(
          scriptletName,
          propsToMatch,
          responseBody,
          responseType
      );
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 4);
      const propNeedles = parsePropertiesToMatchFn(propsToMatch, 'url');
      const validResponseProps = {
          ok: [ false, true ],
          status: [ 403 ],
          statusText: [ '', 'Not Found' ],
          type: [ 'basic', 'cors', 'default', 'error', 'opaque' ],
      };
      const responseProps = {
          statusText: { value: 'OK' },
      };
      const responseHeaders = {};
      if ( /^\{.*\}$/.test(responseType) ) {
          try {
              Object.entries(JSON.parse(responseType)).forEach(([ p, v ]) => {
                  if ( p === 'headers' && trusted ) {
                      Object.assign(responseHeaders, v);
                      return;
                  }
                  if ( validResponseProps[p] === undefined ) { return; }
                  if ( validResponseProps[p].includes(v) === false ) { return; }
                  responseProps[p] = { value: v };
              });
          }
          catch { }
      } else if ( responseType !== '' ) {
          if ( validResponseProps.type.includes(responseType) ) {
              responseProps.type = { value: responseType };
          }
      }
      proxyApplyFn('fetch', function fetch(context) {
          const { callArgs } = context;
          const details = collateFetchArgumentsFn(...callArgs);
          if ( safe.logLevel > 1 || propsToMatch === '' && responseBody === '' ) {
              const out = Array.from(Object.entries(details)).map(a => `${a[0]}:${a[1]}`);
              safe.uboLog(logPrefix, `Called: ${out.join('\n')}`);
          }
          if ( propsToMatch === '' && responseBody === '' ) {
              return context.reflect();
          }
          const matched = matchObjectPropertiesFn(propNeedles, details);
          if ( matched === undefined || matched.length === 0 ) {
              return context.reflect();
          }
          return Promise.resolve(generateContentFn(trusted, responseBody)).then(text => {
              safe.uboLog(logPrefix, `Prevented with response "${text}"`);
              const headers = Object.assign({}, responseHeaders);
              if ( headers['content-length'] === undefined ) {
                  headers['content-length'] = text.length;
              }
              const response = new Response(text, { headers });
              const props = Object.assign(
                  { url: { value: details.url } },
                  responseProps
              );
              safe.Object_defineProperties(response, props);
              if ( extraArgs.throttle ) {
                  return new Promise(resolve => {
                      setTimeout(( ) => { resolve(response); }, extraArgs.throttle);
                  });
              }
              return response;
          });
      });
  }


  function preventInnerHTML(
      selector = '',
      pattern = ''
  ) {
      freezeElementProperty('innerHTML', selector, pattern);
  }


  function preventNavigation(
      pattern = ''
  ) {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('prevent-navigation', pattern);
      const needle = pattern === 'location.href' ? self.location.href : pattern;
      const matcher = safe.initPattern(needle, { canNegate: true });
      self.navigation.addEventListener('navigate', ev => {
          if ( ev.userInitiated ) { return; }
          const { url } = ev.destination;
          if ( pattern === '' ) {
              safe.uboLog(logPrefix, `Navigation to ${url}`);
              return;
          }
          if ( safe.testPattern(matcher, url) ) {
              ev.preventDefault();
              safe.uboLog(logPrefix, `Prevented navigation to ${url}`);
          }
      });
  }


  function preventRefresh(
      delay = ''
  ) {
      if ( typeof delay !== 'string' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('prevent-refresh', delay);
      const stop = content => {
          window.stop();
          safe.uboLog(logPrefix, `Prevented "${content}"`);
      };
      const defuse = ( ) => {
          const meta = document.querySelector('meta[http-equiv="refresh" i][content]');
          if ( meta === null ) { return; }
          const content = meta.getAttribute('content') || '';
          const ms = delay === ''
              ? Math.max(parseFloat(content) || 0, 0) * 500
              : 0;
          if ( ms === 0 ) {
              stop(content);
          } else {
              setTimeout(( ) => { stop(content); }, ms);
          }
      };
      self.addEventListener('load', defuse, { capture: true, once: true });
  }


  function preventRequestAnimationFrame(
      needleRaw = ''
  ) {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('prevent-requestAnimationFrame', needleRaw);
      const needleNot = needleRaw.charAt(0) === '!';
      const reNeedle = safe.patternToRegex(needleNot ? needleRaw.slice(1) : needleRaw);
      proxyApplyFn('requestAnimationFrame', function(context) {
          const { callArgs } = context;
          const a = callArgs[0] instanceof Function
              ? safe.String(safe.Function_toString(callArgs[0]))
              : safe.String(callArgs[0]);
          if ( needleRaw === '' ) {
              safe.uboLog(logPrefix, `Called:\n${a}`);
          } else if ( reNeedle.test(a) !== needleNot ) {
              callArgs[0] = function(){};
              safe.uboLog(logPrefix, `Prevented:\n${a}`);
          }
          return context.reflect();
      });
  }


  function preventSetInterval(
      needleRaw = '',
      delayRaw = ''
  ) {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('prevent-setInterval', needleRaw, delayRaw);
      const needleNot = needleRaw.charAt(0) === '!';
      const reNeedle = safe.patternToRegex(needleNot ? needleRaw.slice(1) : needleRaw);
      const range = new RangeParser(delayRaw);
      proxyApplyFn('setInterval', function(context) {
          const { callArgs } = context;
          const a = callArgs[0] instanceof Function
              ? safe.String(safe.Function_toString(callArgs[0]))
              : safe.String(callArgs[0]);
          const b = callArgs[1];
          if ( needleRaw === '' && range.unbound() ) {
              safe.uboLog(logPrefix, `Called:\n${a}\n${b}`);
              return context.reflect();
          }
          if ( reNeedle.test(a) !== needleNot && range.test(b) ) {
              callArgs[0] = function(){};
              safe.uboLog(logPrefix, `Prevented:\n${a}\n${b}`);
          }
          return context.reflect();
      });
  }


  function preventSetTimeout(
      needleRaw = '',
      delayRaw = ''
  ) {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('prevent-setTimeout', needleRaw, delayRaw);
      const needleNot = needleRaw.charAt(0) === '!';
      const reNeedle = safe.patternToRegex(needleNot ? needleRaw.slice(1) : needleRaw);
      const range = new RangeParser(delayRaw);
      proxyApplyFn('setTimeout', function(context) {
          const { callArgs } = context;
          const a = callArgs[0] instanceof Function
              ? safe.String(safe.Function_toString(callArgs[0]))
              : safe.String(callArgs[0]);
          const b = callArgs[1];
          if ( needleRaw === '' && range.unbound() ) {
              safe.uboLog(logPrefix, `Called:\n${a}\n${b}`);
              return context.reflect();
          }
          if ( reNeedle.test(a) !== needleNot && range.test(b) ) {
              callArgs[0] = function(){};
              safe.uboLog(logPrefix, `Prevented:\n${a}\n${b}`);
          }
          return context.reflect();
      });
  }


  function preventXhr(...args) {
      return preventXhrFn(false, ...args);
  }


  function preventXhrFn(
      trusted = false,
      propsToMatch = '',
      directive = ''
  ) {
      if ( typeof propsToMatch !== 'string' ) { return; }
      const safe = safeSelf();
      const scriptletName = trusted ? 'trusted-prevent-xhr' : 'prevent-xhr';
      const logPrefix = safe.makeLogPrefix(scriptletName, propsToMatch, directive);
      const xhrInstances = new WeakMap();
      const propNeedles = parsePropertiesToMatchFn(propsToMatch, 'url');
      const warOrigin = scriptletGlobals.warOrigin;
      const safeDispatchEvent = (xhr, type) => {
          try {
              xhr.dispatchEvent(new Event(type));
          } catch {
          }
      };
      proxyApplyFn('XMLHttpRequest.prototype.open', function(context) {
          const { thisArg, callArgs } = context;
          xhrInstances.delete(thisArg);
          const [ method, url, ...args ] = callArgs;
          if ( warOrigin !== undefined && url.startsWith(warOrigin) ) {
              return context.reflect();
          }
          const haystack = { method, url };
          if ( propsToMatch === '' && directive === '' ) {
              safe.uboLog(logPrefix, `Called: ${safe.JSON_stringify(haystack, null, 2)}`);
              return context.reflect();
          }
          if ( matchObjectPropertiesFn(propNeedles, haystack) ) {
              const xhrDetails = Object.assign(haystack, {
                  xhr: thisArg,
                  defer: args.length === 0 || !!args[0],
                  directive,
                  headers: {
                      'date': '',
                      'content-type': '',
                      'content-length': '',
                  },
                  url: haystack.url,
                  props: {
                      response: { value: '' },
                      responseText: { value: '' },
                      responseXML: { value: null },
                  },
              });
              xhrInstances.set(thisArg, xhrDetails);
          }
          return context.reflect();
      });
      proxyApplyFn('XMLHttpRequest.prototype.send', function(context) {
          const { thisArg } = context;
          const xhrDetails = xhrInstances.get(thisArg);
          if ( xhrDetails === undefined ) {
              return context.reflect();
          }
          xhrDetails.headers['date'] = (new Date()).toUTCString();
          let xhrText = '';
          switch ( thisArg.responseType ) {
          case 'arraybuffer':
              xhrDetails.props.response.value = new ArrayBuffer(0);
              xhrDetails.headers['content-type'] = 'application/octet-stream';
              break;
          case 'blob':
              xhrDetails.props.response.value = new Blob([]);
              xhrDetails.headers['content-type'] = 'application/octet-stream';
              break;
          case 'document': {
              const parser = new DOMParser();
              const doc = parser.parseFromString('', 'text/html');
              xhrDetails.props.response.value = doc;
              xhrDetails.props.responseXML.value = doc;
              xhrDetails.headers['content-type'] = 'text/html';
              break;
          }
          case 'json':
              xhrDetails.props.response.value = {};
              xhrDetails.props.responseText.value = '{}';
              xhrDetails.headers['content-type'] = 'application/json';
              break;
          default: {
              if ( directive === '' ) { break; }
              xhrText = generateContentFn(trusted, xhrDetails.directive);
              if ( xhrText instanceof Promise ) {
                  xhrText = xhrText.then(text => {
                      xhrDetails.props.response.value = text;
                      xhrDetails.props.responseText.value = text;
                  });
              } else {
                  xhrDetails.props.response.value = xhrText;
                  xhrDetails.props.responseText.value = xhrText;
              }
              xhrDetails.headers['content-type'] = 'text/plain';
              break;
          }
          }
          if ( xhrDetails.defer === false ) {
              xhrDetails.headers['content-length'] = `${xhrDetails.props.response.value}`.length;
              Object.defineProperties(xhrDetails.xhr, {
                  readyState: { value: 4 },
                  responseURL: { value: xhrDetails.url },
                  status: { value: 200 },
                  statusText: { value: 'OK' },
              });
              Object.defineProperties(xhrDetails.xhr, xhrDetails.props);
              return;
          }
          Promise.resolve(xhrText).then(( ) => xhrDetails).then(details => {
              Object.defineProperties(details.xhr, {
                  readyState: { value: 1, configurable: true },
                  responseURL: { value: xhrDetails.url },
              });
              safeDispatchEvent(details.xhr, 'readystatechange');
              return details;
          }).then(details => {
              xhrDetails.headers['content-length'] = `${details.props.response.value}`.length;
              Object.defineProperties(details.xhr, {
                  readyState: { value: 2, configurable: true },
                  status: { value: 200 },
                  statusText: { value: 'OK' },
              });
              safeDispatchEvent(details.xhr, 'readystatechange');
              return details;
          }).then(details => {
              Object.defineProperties(details.xhr, {
                  readyState: { value: 3, configurable: true },
              });
              Object.defineProperties(details.xhr, details.props);
              safeDispatchEvent(details.xhr, 'readystatechange');
              return details;
          }).then(details => {
              Object.defineProperties(details.xhr, {
                  readyState: { value: 4 },
              });
              safeDispatchEvent(details.xhr, 'readystatechange');
              safeDispatchEvent(details.xhr, 'load');
              safeDispatchEvent(details.xhr, 'loadend');
              safe.uboLog(logPrefix, `Prevented with response:\n${details.xhr.response}`);
          });
      });
      proxyApplyFn('XMLHttpRequest.prototype.getResponseHeader', function(context) {
          const { thisArg } = context;
          const xhrDetails = xhrInstances.get(thisArg);
          if ( xhrDetails === undefined || thisArg.readyState < thisArg.HEADERS_RECEIVED ) {
              return context.reflect();
          }
          const headerName = `${context.callArgs[0]}`;
          const value = xhrDetails.headers[headerName.toLowerCase()];
          if ( value !== undefined && value !== '' ) { return value; }
          return null;
      });
      proxyApplyFn('XMLHttpRequest.prototype.getAllResponseHeaders', function(context) {
          const { thisArg } = context;
          const xhrDetails = xhrInstances.get(thisArg);
          if ( xhrDetails === undefined || thisArg.readyState < thisArg.HEADERS_RECEIVED ) {
              return context.reflect();
          }
          const out = [];
          for ( const [ name, value ] of Object.entries(xhrDetails.headers) ) {
              if ( !value ) { continue; }
              out.push(`${name}: ${value}`);
          }
          if ( out.length !== 0 ) { out.push(''); }
          return out.join('\r\n');
      });
  }


  function proxyApplyFn(
      target = '',
      handler = ''
  ) {
      let context = globalThis;
      let prop = target;
      for (;;) {
          const pos = prop.indexOf('.');
          if ( pos === -1 ) { break; }
          context = context[prop.slice(0, pos)];
          if ( context instanceof Object === false ) { return; }
          prop = prop.slice(pos+1);
      }
      const fn = context[prop];
      if ( typeof fn !== 'function' ) { return; }
      if ( proxyApplyFn.CtorContext === undefined ) {
          proxyApplyFn.ctorContexts = [];
          proxyApplyFn.CtorContext = class {
              constructor(...args) {
                  this.init(...args);
              }
              init(callFn, callArgs) {
                  this.callFn = callFn;
                  this.callArgs = callArgs;
                  return this;
              }
              reflect() {
                  const r = Reflect.construct(this.callFn, this.callArgs);
                  this.callFn = this.callArgs = this.private = undefined;
                  proxyApplyFn.ctorContexts.push(this);
                  return r;
              }
              static factory(...args) {
                  return proxyApplyFn.ctorContexts.length !== 0
                      ? proxyApplyFn.ctorContexts.pop().init(...args)
                      : new proxyApplyFn.CtorContext(...args);
              }
          };
          proxyApplyFn.applyContexts = [];
          proxyApplyFn.ApplyContext = class {
              constructor(...args) {
                  this.init(...args);
              }
              init(callFn, thisArg, callArgs) {
                  this.callFn = callFn;
                  this.thisArg = thisArg;
                  this.callArgs = callArgs;
                  return this;
              }
              reflect() {
                  const r = Reflect.apply(this.callFn, this.thisArg, this.callArgs);
                  this.callFn = this.thisArg = this.callArgs = this.private = undefined;
                  proxyApplyFn.applyContexts.push(this);
                  return r;
              }
              static factory(...args) {
                  return proxyApplyFn.applyContexts.length !== 0
                      ? proxyApplyFn.applyContexts.pop().init(...args)
                      : new proxyApplyFn.ApplyContext(...args);
              }
          };
          proxyApplyFn.isCtor = new Map();
          proxyApplyFn.proxies = new WeakMap();
          proxyApplyFn.nativeToString = Function.prototype.toString;
          const proxiedToString = new Proxy(Function.prototype.toString, {
              apply(target, thisArg) {
                  let proxied = thisArg;
                  for(;;) {
                      const fn = proxyApplyFn.proxies.get(proxied);
                      if ( fn === undefined ) { break; }
                      proxied = fn;
                  }
                  return proxyApplyFn.nativeToString.call(proxied);
              }
          });
          proxyApplyFn.proxies.set(proxiedToString, proxyApplyFn.nativeToString);
          Function.prototype.toString = proxiedToString;
      }
      if ( proxyApplyFn.isCtor.has(target) === false ) {
          proxyApplyFn.isCtor.set(target, fn.prototype?.constructor === fn);
      }
      const proxyDetails = {
          apply(target, thisArg, args) {
              return handler(proxyApplyFn.ApplyContext.factory(target, thisArg, args));
          }
      };
      if ( proxyApplyFn.isCtor.get(target) ) {
          proxyDetails.construct = function(target, args) {
              return handler(proxyApplyFn.CtorContext.factory(target, args));
          };
      }
      const proxiedTarget = new Proxy(fn, proxyDetails);
      proxyApplyFn.proxies.set(proxiedTarget, fn);
      context[prop] = proxiedTarget;
  }


  function removeAttr(
      rawToken = '',
      rawSelector = '',
      behavior = ''
  ) {
      if ( typeof rawToken !== 'string' ) { return; }
      if ( rawToken === '' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('remove-attr', rawToken, rawSelector, behavior);
      const tokens = safe.String_split.call(rawToken, /\s*\|\s*/);
      const selector = tokens
          .map(a => `${rawSelector}[${CSS.escape(a)}]`)
          .join(',');
      if ( safe.logLevel > 1 ) {
          safe.uboLog(logPrefix, `Target selector:\n\t${selector}`);
      }
      const asap = /\basap\b/.test(behavior);
      let timerId;
      const rmattrAsync = ( ) => {
          if ( timerId !== undefined ) { return; }
          timerId = safe.onIdle(( ) => {
              timerId = undefined;
              rmattr();
          }, { timeout: 17 });
      };
      const rmattr = ( ) => {
          if ( timerId !== undefined ) {
              safe.offIdle(timerId);
              timerId = undefined;
          }
          try {
              const nodes = document.querySelectorAll(selector);
              for ( const node of nodes ) {
                  for ( const attr of tokens ) {
                      if ( node.hasAttribute(attr) === false ) { continue; }
                      node.removeAttribute(attr);
                      safe.uboLog(logPrefix, `Removed attribute '${attr}'`);
                  }
              }
          } catch {
          }
      };
      const mutationHandler = mutations => {
          if ( timerId !== undefined ) { return; }
          let skip = true;
          for ( let i = 0; i < mutations.length && skip; i++ ) {
              const { type, addedNodes, removedNodes } = mutations[i];
              if ( type === 'attributes' ) { skip = false; }
              for ( let j = 0; j < addedNodes.length && skip; j++ ) {
                  if ( addedNodes[j].nodeType === 1 ) { skip = false; break; }
              }
              for ( let j = 0; j < removedNodes.length && skip; j++ ) {
                  if ( removedNodes[j].nodeType === 1 ) { skip = false; break; }
              }
          }
          if ( skip ) { return; }
          asap ? rmattr() : rmattrAsync();
      };
      const start = ( ) => {
          rmattr();
          if ( /\bstay\b/.test(behavior) === false ) { return; }
          const observer = new MutationObserver(mutationHandler);
          observer.observe(document, {
              attributes: true,
              attributeFilter: tokens,
              childList: true,
              subtree: true,
          });
      };
      runAt(( ) => { start(); }, safe.String_split.call(behavior, /\s+/));
  }


  function removeCacheStorageItem(
      cacheNamePattern = '',
      requestPattern = ''
  ) {
      if ( cacheNamePattern === '' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('remove-cache-storage-item', cacheNamePattern, requestPattern);
      const cacheStorage = self.caches;
      if ( cacheStorage instanceof Object === false ) { return; }
      const reCache = safe.patternToRegex(cacheNamePattern, undefined, true);
      const reRequest = safe.patternToRegex(requestPattern, undefined, true);
      cacheStorage.keys().then(cacheNames => {
          for ( const cacheName of cacheNames ) {
              if ( reCache.test(cacheName) === false ) { continue; }
              if ( requestPattern === '' ) {
                  cacheStorage.delete(cacheName).then(result => {
                      if ( safe.logLevel > 1 ) {
                          safe.uboLog(logPrefix, `Deleting ${cacheName}`);
                      }
                      if ( result !== true ) { return; }
                      safe.uboLog(logPrefix, `Deleted ${cacheName}: ${result}`);
                  });
                  continue;
              }
              cacheStorage.open(cacheName).then(cache => {
                  cache.keys().then(requests => {
                      for ( const request of requests ) {
                          if ( reRequest.test(request.url) === false ) { continue; }
                          if ( safe.logLevel > 1 ) {
                              safe.uboLog(logPrefix, `Deleting ${cacheName}/${request.url}`);
                          }
                          cache.delete(request).then(result => {
                              if ( result !== true ) { return; }
                              safe.uboLog(logPrefix, `Deleted ${cacheName}/${request.url}: ${result}`);
                          });
                      }
                  });
              });
          }
      });
  }


  function removeClass(
      rawToken = '',
      rawSelector = '',
      behavior = ''
  ) {
      if ( typeof rawToken !== 'string' ) { return; }
      if ( rawToken === '' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('remove-class', rawToken, rawSelector, behavior);
      const tokens = safe.String_split.call(rawToken, /\s*\|\s*/);
      const selector = tokens
          .map(a => `${rawSelector}.${CSS.escape(a)}`)
          .join(',');
      if ( safe.logLevel > 1 ) {
          safe.uboLog(logPrefix, `Target selector:\n\t${selector}`);
      }
      const mustStay = /\bstay\b/.test(behavior);
      let timer;
      const rmclass = ( ) => {
          timer = undefined;
          try {
              const nodes = document.querySelectorAll(selector);
              for ( const node of nodes ) {
                  node.classList.remove(...tokens);
                  safe.uboLog(logPrefix, 'Removed class(es)');
              }
          } catch {
          }
          if ( mustStay ) { return; }
          if ( document.readyState !== 'complete' ) { return; }
          observer.disconnect();
      };
      const mutationHandler = mutations => {
          if ( timer !== undefined ) { return; }
          let skip = true;
          for ( let i = 0; i < mutations.length && skip; i++ ) {
              const { type, addedNodes, removedNodes } = mutations[i];
              if ( type === 'attributes' ) { skip = false; }
              for ( let j = 0; j < addedNodes.length && skip; j++ ) {
                  if ( addedNodes[j].nodeType === 1 ) { skip = false; break; }
              }
              for ( let j = 0; j < removedNodes.length && skip; j++ ) {
                  if ( removedNodes[j].nodeType === 1 ) { skip = false; break; }
              }
          }
          if ( skip ) { return; }
          timer = safe.onIdle(rmclass, { timeout: 67 });
      };
      const observer = new MutationObserver(mutationHandler);
      const start = ( ) => {
          rmclass();
          observer.observe(document, {
              attributes: true,
              attributeFilter: [ 'class' ],
              childList: true,
              subtree: true,
          });
      };
      runAt(( ) => {
          start();
      }, /\bcomplete\b/.test(behavior) ? 'idle' : 'loading');
  }


  function removeCookie(
      needle = ''
  ) {
      if ( typeof needle !== 'string' ) { return; }
      const safe = safeSelf();
      const reName = safe.patternToRegex(needle);
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 1);
      const throttle = (fn, ms = 500) => {
          if ( throttle.timer !== undefined ) { return; }
          throttle.timer = setTimeout(( ) => {
              throttle.timer = undefined;
              fn();
          }, ms);
      };
      const baseURL = new URL(document.baseURI);
      let targetDomain = extraArgs.domain;
      if ( targetDomain && /^\/.+\//.test(targetDomain) ) {
          const reDomain = new RegExp(targetDomain.slice(1, -1));
          const match = reDomain.exec(baseURL.hostname);
          targetDomain = match ? match[0] : undefined;
      }
      const remove = ( ) => {
          safe.String_split.call(document.cookie, ';').forEach(cookieStr => {
              const pos = cookieStr.indexOf('=');
              if ( pos === -1 ) { return; }
              const cookieName = cookieStr.slice(0, pos).trim();
              if ( reName.test(cookieName) === false ) { return; }
              const part1 = cookieName + '=';
              const part2a = `; domain=${baseURL.hostname}`;
              const part2b = `; domain=.${baseURL.hostname}`;
              let part2c, part2d;
              if ( targetDomain ) {
                  part2c = `; domain=${targetDomain}`;
                  part2d = `; domain=.${targetDomain}`;
              } else if ( document.domain ) {
                  const domain = document.domain;
                  if ( domain !== baseURL.hostname ) {
                      part2c = `; domain=.${domain}`;
                  }
                  if ( domain.startsWith('www.') ) {
                      part2d = `; domain=${domain.replace('www', '')}`;
                  }
              }
              const part3 = '; path=/';
              const part4 = '; Max-Age=-1000; expires=Thu, 01 Jan 1970 00:00:00 GMT';
              document.cookie = part1 + part4;
              document.cookie = part1 + part2a + part4;
              document.cookie = part1 + part2b + part4;
              document.cookie = part1 + part3 + part4;
              document.cookie = part1 + part2a + part3 + part4;
              document.cookie = part1 + part2b + part3 + part4;
              if ( part2c !== undefined ) {
                  document.cookie = part1 + part2c + part3 + part4;
              }
              if ( part2d !== undefined ) {
                  document.cookie = part1 + part2d + part3 + part4;
              }
          });
      };
      remove();
      window.addEventListener('beforeunload', remove);
      if ( typeof extraArgs.when !== 'string' ) { return; }
      const supportedEventTypes = [ 'scroll', 'keydown' ];
      const eventTypes = safe.String_split.call(extraArgs.when, /\s/);
      for ( const type of eventTypes ) {
          if ( supportedEventTypes.includes(type) === false ) { continue; }
          document.addEventListener(type, ( ) => {
              throttle(remove);
          }, { passive: true });
      }
  }


  function removeNodeText(
      nodeName,
      includes,
      ...extraArgs
  ) {
      replaceNodeTextFn(nodeName, '', '', 'includes', includes || '', ...extraArgs);
  }


  function replaceFetchResponseFn(
      trusted = false,
      pattern = '',
      replacement = '',
      propsToMatch = ''
  ) {
      if ( trusted !== true ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('replace-fetch-response', pattern, replacement, propsToMatch);
      if ( pattern === '*' ) { pattern = '.*'; }
      const rePattern = safe.patternToRegex(pattern);
      const propNeedles = parsePropertiesToMatchFn(propsToMatch, 'url');
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 4);
      const reIncludes = extraArgs.includes ? safe.patternToRegex(extraArgs.includes) : null;
      self.fetch = new Proxy(self.fetch, {
          apply: function(target, thisArg, args) {
              const fetchPromise = Reflect.apply(target, thisArg, args);
              if ( pattern === '' ) { return fetchPromise; }
              if ( propNeedles.size !== 0 ) {
                  const props = collateFetchArgumentsFn(...args);
                  const matched = matchObjectPropertiesFn(propNeedles, props);
                  if ( matched === undefined ) { return fetchPromise; }
                  if ( safe.logLevel > 1 ) {
                      safe.uboLog(logPrefix, `Matched "propsToMatch":\n\t${matched.join('\n\t')}`);
                  }
              }
              return fetchPromise.then(responseBefore => {
                  const response = responseBefore.clone();
                  return response.text().then(textBefore => {
                      if ( reIncludes && reIncludes.test(textBefore) === false ) {
                          return responseBefore;
                      }
                      const textAfter = textBefore.replace(rePattern, replacement);
                      if ( textAfter === textBefore ) { return responseBefore; }
                      safe.uboLog(logPrefix, 'Replaced');
                      const responseAfter = new Response(textAfter, {
                          status: responseBefore.status,
                          statusText: responseBefore.statusText,
                          headers: responseBefore.headers,
                      });
                      Object.defineProperties(responseAfter, {
                          ok: { value: responseBefore.ok },
                          redirected: { value: responseBefore.redirected },
                          type: { value: responseBefore.type },
                          url: { value: responseBefore.url },
                      });
                      return responseAfter;
                  }).catch(reason => {
                      safe.uboErr(logPrefix, reason);
                      return responseBefore;
                  });
              }).catch(reason => {
                  safe.uboErr(logPrefix, reason);
                  return fetchPromise;
              });
          }
      });
  }


  function replaceNodeText(
      nodeName,
      pattern,
      replacement,
      ...extraArgs
  ) {
      replaceNodeTextFn(nodeName, pattern, replacement, ...extraArgs);
  }


  function replaceNodeTextFn(
      nodeName = '',
      pattern = '',
      replacement = ''
  ) {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('replace-node-text.fn', ...Array.from(arguments));
      const reNodeName = safe.patternToRegex(nodeName, 'i', true);
      const rePattern = safe.patternToRegex(pattern, 'gms');
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 3);
      const reIncludes = extraArgs.includes || extraArgs.condition
          ? safe.patternToRegex(extraArgs.includes || extraArgs.condition, 'ms')
          : null;
      const reExcludes = extraArgs.excludes
          ? safe.patternToRegex(extraArgs.excludes, 'ms')
          : null;
      const stop = (takeRecord = true) => {
          if ( takeRecord ) {
              handleMutations(observer.takeRecords());
          }
          observer.disconnect();
          if ( safe.logLevel > 1 ) {
              safe.uboLog(logPrefix, 'Quitting');
          }
      };
      const textContentFactory = (( ) => {
          const out = { createScript: s => s };
          const { trustedTypes: tt } = self;
          if ( tt instanceof Object ) {
              try {
                  if ( typeof tt.getPropertyType === 'function' ) {
                      if ( tt.getPropertyType('script', 'textContent') === 'TrustedScript' ) {
                          return tt.createPolicy(getRandomTokenFn(), out);
                      }
                  }
              } catch (_) {}
          }
          return out;
      })();
      let sedCount = extraArgs.sedCount || 0;
      const handleNode = node => {
          const before = node.textContent;
          if ( reIncludes ) {
              reIncludes.lastIndex = 0;
              if ( safe.RegExp_test.call(reIncludes, before) === false ) { return true; }
          }
          if ( reExcludes ) {
              reExcludes.lastIndex = 0;
              if ( safe.RegExp_test.call(reExcludes, before) ) { return true; }
          }
          rePattern.lastIndex = 0;
          if ( safe.RegExp_test.call(rePattern, before) === false ) { return true; }
          rePattern.lastIndex = 0;
          const after = pattern !== ''
              ? before.replace(rePattern, replacement)
              : replacement;
          try {
              node.textContent = node.nodeName === 'SCRIPT'
                  ? textContentFactory.createScript(after)
                  : after;
          } catch (_) {
              return true;
          }
          if ( safe.logLevel > 1 ) {
              safe.uboLog(logPrefix, `Text before:\n${before.trim()}`);
          }
          safe.uboLog(logPrefix, `Text after:\n${after.trim()}`);
          return sedCount === 0 || (sedCount -= 1) !== 0;
      };
      const handleMutations = mutations => {
          for ( const mutation of mutations ) {
              for ( const node of mutation.addedNodes ) {
                  if ( reNodeName.test(node.nodeName) === false ) { continue; }
                  if ( handleNode(node) ) { continue; }
                  stop(false); return;
              }
          }
      };
      const observer = new MutationObserver(handleMutations);
      observer.observe(document, { childList: true, subtree: true });
      if ( document.documentElement ) {
          const treeWalker = document.createTreeWalker(
              document.documentElement,
              NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT
          );
          let count = 0;
          for (;;) {
              const node = treeWalker.nextNode();
              count += 1;
              if ( node === null ) { break; }
              if ( reNodeName.test(node.nodeName) === false ) { continue; }
              if ( node === document.currentScript ) { continue; }
              if ( handleNode(node) ) { continue; }
              stop(); break;
          }
          safe.uboLog(logPrefix, `${count} nodes present before installing mutation observer`);
      }
      if ( extraArgs.stay ) { return; }
      runAt(( ) => {
          const quitAfter = extraArgs.quitAfter || 0;
          if ( quitAfter !== 0 ) {
              setTimeout(( ) => { stop(); }, quitAfter);
          } else {
              stop();
          }
      }, 'interactive');
  }


  function runAt(fn, when) {
      const intFromReadyState = state => {
          const targets = {
              'loading': 1, 'asap': 1,
              'interactive': 2, 'end': 2, '2': 2,
              'complete': 3, 'idle': 3, '3': 3,
          };
          const tokens = Array.isArray(state) ? state : [ state ];
          for ( const token of tokens ) {
              const prop = `${token}`;
              if ( Object.hasOwn(targets, prop) === false ) { continue; }
              return targets[prop];
          }
          return 0;
      };
      const runAt = intFromReadyState(when);
      if ( intFromReadyState(document.readyState) >= runAt ) {
          fn(); return;
      }
      const onStateChange = ( ) => {
          if ( intFromReadyState(document.readyState) < runAt ) { return; }
          fn();
          safe.removeEventListener.apply(document, args);
      };
      const safe = safeSelf();
      const args = [ 'readystatechange', onStateChange, { capture: true } ];
      safe.addEventListener.apply(document, args);
  }


  function runAtHtmlElementFn(fn) {
      if ( document.documentElement ) {
          fn();
          return;
      }
      const observer = new MutationObserver(( ) => {
          observer.disconnect();
          fn();
      });
      observer.observe(document, { childList: true });
  }


  function safeSelf() {
      if ( scriptletGlobals.safeSelf ) {
          return scriptletGlobals.safeSelf;
      }
      const self = globalThis;
      const safe = {
          'Array_from': Array.from,
          'Error': self.Error,
          'Function_toStringFn': self.Function.prototype.toString,
          'Function_toString': thisArg => safe.Function_toStringFn.call(thisArg),
          'Math_floor': Math.floor,
          'Math_max': Math.max,
          'Math_min': Math.min,
          'Math_random': Math.random,
          'Object': Object,
          'Object_defineProperty': Object.defineProperty.bind(Object),
          'Object_defineProperties': Object.defineProperties.bind(Object),
          'Object_fromEntries': Object.fromEntries.bind(Object),
          'Object_getOwnPropertyDescriptor': Object.getOwnPropertyDescriptor.bind(Object),
          'Object_hasOwn': Object.hasOwn.bind(Object),
          'Object_toString': Object.prototype.toString,
          'RegExp': self.RegExp,
          'RegExp_test': self.RegExp.prototype.test,
          'RegExp_exec': self.RegExp.prototype.exec,
          'Request_clone': self.Request.prototype.clone,
          'String': self.String,
          'String_fromCharCode': String.fromCharCode,
          'String_split': String.prototype.split,
          'XMLHttpRequest': self.XMLHttpRequest,
          'addEventListener': self.EventTarget.prototype.addEventListener,
          'removeEventListener': self.EventTarget.prototype.removeEventListener,
          'fetch': self.fetch,
          'JSON': self.JSON,
          'JSON_parseFn': self.JSON.parse,
          'JSON_stringifyFn': self.JSON.stringify,
          'JSON_parse': (...args) => safe.JSON_parseFn.call(safe.JSON, ...args),
          'JSON_stringify': (...args) => safe.JSON_stringifyFn.call(safe.JSON, ...args),
          'log': console.log.bind(console),
          // Properties
          logLevel: 0,
          // Methods
          makeLogPrefix(...args) {
              return this.sendToLogger && `[${args.join(' \u205D ')}]` || '';
          },
          uboLog(...args) {
              if ( this.sendToLogger === undefined ) { return; }
              if ( args === undefined || args[0] === '' ) { return; }
              return this.sendToLogger('info', ...args);

          },
          uboErr(...args) {
              if ( this.sendToLogger === undefined ) { return; }
              if ( args === undefined || args[0] === '' ) { return; }
              return this.sendToLogger('error', ...args);
          },
          escapeRegexChars(s) {
              return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
          },
          initPattern(pattern, options = {}) {
              if ( pattern === '' ) {
                  return { matchAll: true, expect: true };
              }
              const expect = (options.canNegate !== true || pattern.startsWith('!') === false);
              if ( expect === false ) {
                  pattern = pattern.slice(1);
              }
              const match = /^\/(.+)\/([gimsu]*)$/.exec(pattern);
              if ( match !== null ) {
                  return {
                      re: new this.RegExp(
                          match[1],
                          match[2] || options.flags
                      ),
                      expect,
                  };
              }
              if ( options.flags !== undefined ) {
                  return {
                      re: new this.RegExp(this.escapeRegexChars(pattern),
                          options.flags
                      ),
                      expect,
                  };
              }
              return { pattern, expect };
          },
          testPattern(details, haystack) {
              if ( details.matchAll ) { return true; }
              if ( details.re ) {
                  return this.RegExp_test.call(details.re, haystack) === details.expect;
              }
              return haystack.includes(details.pattern) === details.expect;
          },
          patternToRegex(pattern, flags = undefined, verbatim = false) {
              if ( pattern === '' ) { return /^/; }
              const match = /^\/(.+)\/([gimsu]*)$/.exec(pattern);
              if ( match === null ) {
                  const reStr = this.escapeRegexChars(pattern);
                  return new RegExp(verbatim ? `^${reStr}$` : reStr, flags);
              }
              try {
                  return new RegExp(match[1], match[2] || undefined);
              }
              catch {
              }
              return /^/;
          },
          getExtraArgs(args, offset = 0) {
              const entries = args.slice(offset).reduce((out, v, i, a) => {
                  if ( (i & 1) === 0 ) {
                      const rawValue = a[i+1];
                      const value = /^\d+$/.test(rawValue)
                          ? parseInt(rawValue, 10)
                          : rawValue;
                      out.push([ a[i], value ]);
                  }
                  return out;
              }, []);
              return this.Object_fromEntries(entries);
          },
          onIdle(fn, options) {
              if ( self.requestIdleCallback ) {
                  return self.requestIdleCallback(fn, options);
              }
              return self.requestAnimationFrame(fn);
          },
          offIdle(id) {
              if ( self.requestIdleCallback ) {
                  return self.cancelIdleCallback(id);
              }
              return self.cancelAnimationFrame(id);
          }
      };
      scriptletGlobals.safeSelf = safe;
      if ( scriptletGlobals.bcSecret === undefined ) { return safe; }
      // This is executed only when the logger is opened
      safe.logLevel = scriptletGlobals.logLevel || 1;
      let lastLogType = '';
      let lastLogText = '';
      let lastLogTime = 0;
      safe.toLogText = (type, ...args) => {
          if ( args.length === 0 ) { return; }
          const text = `[${document.location.hostname || document.location.href}]${args.join(' ')}`;
          if ( text === lastLogText && type === lastLogType ) {
              if ( (Date.now() - lastLogTime) < 5000 ) { return; }
          }
          lastLogType = type;
          lastLogText = text;
          lastLogTime = Date.now();
          return text;
      };
      try {
          const bc = new self.BroadcastChannel(scriptletGlobals.bcSecret);
          let bcBuffer = [];
          safe.sendToLogger = (type, ...args) => {
              const text = safe.toLogText(type, ...args);
              if ( text === undefined ) { return; }
              if ( bcBuffer === undefined ) {
                  return bc.postMessage({ what: 'messageToLogger', type, text });
              }
              bcBuffer.push({ type, text });
          };
          bc.onmessage = ev => {
              const msg = ev.data;
              switch ( msg ) {
              case 'iamready!':
                  if ( bcBuffer === undefined ) { break; }
                  bcBuffer.forEach(({ type, text }) =>
                      bc.postMessage({ what: 'messageToLogger', type, text })
                  );
                  bcBuffer = undefined;
                  break;
              case 'setScriptletLogLevelToOne':
                  safe.logLevel = 1;
                  break;
              case 'setScriptletLogLevelToTwo':
                  safe.logLevel = 2;
                  break;
              }
          };
          bc.postMessage('areyouready?');
      } catch {
          safe.sendToLogger = (type, ...args) => {
              const text = safe.toLogText(type, ...args);
              if ( text === undefined ) { return; }
              safe.log(`uBO ${text}`);
          };
      }
      return safe;
  }


  function setAttr(
      selector = '',
      attr = '',
      value = ''
  ) {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('set-attr', selector, attr, value);
      const validValues = [ '', 'false', 'true' ];
      if ( validValues.includes(value.toLowerCase()) === false ) {
          if ( /^\d+$/.test(value) ) {
              const n = parseInt(value, 10);
              if ( n >= 32768 ) { return; }
              value = `${n}`;
          } else if ( /^\[.+\]$/.test(value) === false ) {
              return;
          }
      }
      const options = safe.getExtraArgs(Array.from(arguments), 3);
      setAttrFn(false, logPrefix, selector, attr, value, options);
  }


  function setAttrFn(
      trusted = false,
      logPrefix,
      selector = '',
      attr = '',
      value = '',
      options = {}
  ) {
      if ( selector === '' ) { return; }
      if ( attr === '' ) { return; }

      const safe = safeSelf();
      const copyFrom = trusted === false && /^\[.+\]$/.test(value)
          ? value.slice(1, -1)
          : '';

      const extractValue = elem => copyFrom !== ''
          ? elem.getAttribute(copyFrom) || ''
          : value;

      const applySetAttr = ( ) => {
          let elems;
          try {
              elems = document.querySelectorAll(selector);
          } catch {
              return false;
          }
          for ( const elem of elems ) {
              const before = elem.getAttribute(attr);
              const after = extractValue(elem);
              if ( after === before ) { continue; }
              if ( after !== '' && /^on/i.test(attr) ) {
                  if ( attr.toLowerCase() in elem ) { continue; }
              }
              elem.setAttribute(attr, after);
              safe.uboLog(logPrefix, `${attr}="${after}"`);
          }
          return true;
      };

      let observer, timer;
      const onDomChanged = mutations => {
          if ( timer !== undefined ) { return; }
          let shouldWork = false;
          for ( const mutation of mutations ) {
              if ( mutation.addedNodes.length === 0 ) { continue; }
              for ( const node of mutation.addedNodes ) {
                  if ( node.nodeType !== 1 ) { continue; }
                  shouldWork = true;
                  break;
              }
              if ( shouldWork ) { break; }
          }
          if ( shouldWork === false ) { return; }
          timer = self.requestAnimationFrame(( ) => {
              timer = undefined;
              applySetAttr();
          });
      };

      const start = ( ) => {
          if ( applySetAttr() === false ) { return; }
          observer = new MutationObserver(onDomChanged);
          observer.observe(document.body, {
              subtree: true,
              childList: true,
          });
      };
      runAt(( ) => { start(); }, options.runAt || 'idle');
  }


  function setConstant(
      ...args
  ) {
      setConstantFn(false, ...args);
  }


  function setConstantFn(
      trusted = false,
      chain = '',
      rawValue = ''
  ) {
      if ( chain === '' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('set-constant', chain, rawValue);
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 3);
      function setConstant(chain, rawValue) {
          const trappedProp = (( ) => {
              const pos = chain.lastIndexOf('.');
              if ( pos === -1 ) { return chain; }
              return chain.slice(pos+1);
          })();
          const cloakFunc = fn => {
              safe.Object_defineProperty(fn, 'name', { value: trappedProp });
              return new Proxy(fn, {
                  defineProperty(target, prop) {
                      if ( prop !== 'toString' ) {
                          return Reflect.defineProperty(...arguments);
                      }
                      return true;
                  },
                  deleteProperty(target, prop) {
                      if ( prop !== 'toString' ) {
                          return Reflect.deleteProperty(...arguments);
                      }
                      return true;
                  },
                  get(target, prop) {
                      if ( prop === 'toString' ) {
                          return function() {
                              return `function ${trappedProp}() { [native code] }`;
                          }.bind(null);
                      }
                      return Reflect.get(...arguments);
                  },
              });
          };
          if ( trappedProp === '' ) { return; }
          const thisScript = document.currentScript;
          let normalValue = validateConstantFn(trusted, rawValue, extraArgs);
          if ( rawValue === 'noopFunc' || rawValue === 'trueFunc' || rawValue === 'falseFunc' ) {
              normalValue = cloakFunc(normalValue);
          }
          let aborted = false;
          const mustAbort = function(v) {
              if ( trusted ) { return false; }
              if ( aborted ) { return true; }
              aborted =
                  (v !== undefined && v !== null) &&
                  (normalValue !== undefined && normalValue !== null) &&
                  (typeof v !== typeof normalValue);
              if ( aborted ) {
                  safe.uboLog(logPrefix, `Aborted because value set to ${v}`);
              }
              return aborted;
          };
          // https://github.com/uBlockOrigin/uBlock-issues/issues/156
          //   Support multiple trappers for the same property.
          const trapProp = function(owner, prop, configurable, handler) {
              if ( handler.init(configurable ? owner[prop] : normalValue) === false ) { return; }
              const odesc = safe.Object_getOwnPropertyDescriptor(owner, prop);
              let prevGetter, prevSetter;
              if ( odesc instanceof safe.Object ) {
                  owner[prop] = normalValue;
                  if ( odesc.get instanceof Function ) {
                      prevGetter = odesc.get;
                  }
                  if ( odesc.set instanceof Function ) {
                      prevSetter = odesc.set;
                  }
              }
              try {
                  safe.Object_defineProperty(owner, prop, {
                      configurable,
                      get() {
                          if ( prevGetter !== undefined ) {
                              prevGetter();
                          }
                          return handler.getter();
                      },
                      set(a) {
                          if ( prevSetter !== undefined ) {
                              prevSetter(a);
                          }
                          handler.setter(a);
                      }
                  });
                  safe.uboLog(logPrefix, 'Trap installed');
              } catch(ex) {
                  safe.uboErr(logPrefix, ex);
              }
          };
          const trapChain = function(owner, chain) {
              const pos = chain.indexOf('.');
              if ( pos === -1 ) {
                  trapProp(owner, chain, false, {
                      v: undefined,
                      init: function(v) {
                          if ( mustAbort(v) ) { return false; }
                          this.v = v;
                          return true;
                      },
                      getter: function() {
                          if ( thisScript && document.currentScript === thisScript ) {
                              return this.v;
                          }
                          safe.uboLog(logPrefix, 'Property read');
                          return normalValue;
                      },
                      setter: function(a) {
                          if ( mustAbort(a) === false ) { return; }
                          normalValue = a;
                      }
                  });
                  return;
              }
              const prop = chain.slice(0, pos);
              const v = owner[prop];
              chain = chain.slice(pos + 1);
              if ( v instanceof safe.Object || typeof v === 'object' && v !== null ) {
                  trapChain(v, chain);
                  return;
              }
              trapProp(owner, prop, true, {
                  v: undefined,
                  init: function(v) {
                      this.v = v;
                      return true;
                  },
                  getter: function() {
                      return this.v;
                  },
                  setter: function(a) {
                      this.v = a;
                      if ( a instanceof safe.Object ) {
                          trapChain(a, chain);
                      }
                  }
              });
          };
          trapChain(window, chain);
      }
      runAt(( ) => {
          setConstant(chain, rawValue);
      }, extraArgs.runAt);
  }


  function setCookie(
      name = '',
      value = '',
      path = ''
  ) {
      if ( name === '' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('set-cookie', name, value, path);
      const normalized = value.toLowerCase();
      const match = /^("?)(.+)\1$/.exec(normalized);
      const unquoted = match && match[2] || normalized;
      const validValues = getSafeCookieValuesFn();
      if ( validValues.includes(unquoted) === false ) {
          if ( /^-?\d+$/.test(unquoted) === false ) { return; }
          const n = parseInt(value, 10) || 0;
          if ( n < -32767 || n > 32767 ) { return; }
      }

      const done = setCookieFn(
          false,
          name,
          value,
          '',
          path,
          safe.getExtraArgs(Array.from(arguments), 3)
      );

      if ( done ) {
          safe.uboLog(logPrefix, 'Done');
      }
  }


  function setCookieFn(
      trusted = false,
      name = '',
      value = '',
      expires = '',
      path = '',
      options = {},
  ) {
      // https://datatracker.ietf.org/doc/html/rfc2616#section-2.2
      // https://github.com/uBlockOrigin/uBlock-issues/issues/2777
      if ( trusted === false && /[^!#$%&'*+\-.0-9A-Z[\]^_`a-z|~]/.test(name) ) {
          name = encodeURIComponent(name);
      }
      // https://datatracker.ietf.org/doc/html/rfc6265#section-4.1.1
      // The characters [",] are given a pass from the RFC requirements because
      // apparently browsers do not follow the RFC to the letter.
      if ( /[^ -:<-[\]-~]/.test(value) ) {
          value = encodeURIComponent(value);
      }

      const cookieBefore = getCookieFn(name);
      if ( cookieBefore !== undefined && options.dontOverwrite ) { return; }
      if ( cookieBefore === value && options.reload ) { return; }

      const cookieParts = [ name, '=', value ];
      if ( expires !== '' ) {
          cookieParts.push('; expires=', expires);
      }

      if ( path === '' ) { path = '/'; }
      else if ( path === 'none' ) { path = ''; }
      if ( path !== '' && path !== '/' ) { return; }
      if ( path === '/' ) {
          cookieParts.push('; path=/');
      }

      if ( trusted ) {
          if ( options.domain ) {
              let domain = options.domain;
              if ( /^\/.+\//.test(domain) ) {
                  const baseURL = new URL(document.baseURI);
                  const reDomain = new RegExp(domain.slice(1, -1));
                  const match = reDomain.exec(baseURL.hostname);
                  domain = match ? match[0] : undefined;
              }
              if ( domain ) {
                  cookieParts.push(`; domain=${domain}`);
              }
          }
          cookieParts.push('; Secure');
      } else if ( /^__(Host|Secure)-/.test(name) ) {
          cookieParts.push('; Secure');
      }

      try {
          document.cookie = cookieParts.join('');
      } catch {
      }

      const done = getCookieFn(name) === value;
      if ( done && options.reload ) {
          window.location.reload();
      }

      return done;
  }


  function setCookieReload(name, value, path, ...args) {
      setCookie(name, value, path, 'reload', '1', ...args);
  }


  function setLocalStorageItem(key = '', value = '') {
      const safe = safeSelf();
      const options = safe.getExtraArgs(Array.from(arguments), 2)
      setLocalStorageItemFn('local', false, key, value, options);
  }


  function setLocalStorageItemFn(
      which = 'local',
      trusted = false,
      key = '',
      value = '',
      options = {}
  ) {
      if ( key === '' ) { return; }

      // For increased compatibility with AdGuard
      if ( value === 'emptyArr' ) {
          value = '[]';
      } else if ( value === 'emptyObj' ) {
          value = '{}';
      }

      const trustedValues = [
          '',
          'undefined', 'null',
          '{}', '[]', '""',
          '$remove$',
          ...getSafeCookieValuesFn(),
      ];

      if ( trusted ) {
          if ( value.includes('$now$') ) {
              value = value.replaceAll('$now$', Date.now());
          }
          if ( value.includes('$currentDate$') ) {
              value = value.replaceAll('$currentDate$', `${Date()}`);
          }
          if ( value.includes('$currentISODate$') ) {
              value = value.replaceAll('$currentISODate$', (new Date()).toISOString());
          }
      } else {
          const normalized = value.toLowerCase();
          const match = /^("?)(.+)\1$/.exec(normalized);
          const unquoted = match && match[2] || normalized;
          if ( trustedValues.includes(unquoted) === false ) {
              if ( /^-?\d+$/.test(unquoted) === false ) { return; }
              const n = parseInt(unquoted, 10) || 0;
              if ( n < -32767 || n > 32767 ) { return; }
          }
      }

      let modified = false;

      try {
          const storage = self[`${which}Storage`];
          if ( value === '$remove$' ) {
              const safe = safeSelf();
              const pattern = safe.patternToRegex(key, undefined, true );
              const toRemove = [];
              for ( let i = 0, n = storage.length; i < n; i++ ) {
                  const key = storage.key(i);
                  if ( pattern.test(key) ) { toRemove.push(key); }
              }
              modified = toRemove.length !== 0;
              for ( const key of toRemove ) {
                  storage.removeItem(key);
              }
          } else {

              const before = storage.getItem(key);
              const after = `${value}`;
              modified = after !== before;
              if ( modified ) {
                  storage.setItem(key, after);
              }
          }
      } catch {
      }

      if ( modified && typeof options.reload === 'number' ) {
          setTimeout(( ) => { window.location.reload(); }, options.reload);
      }
  }


  function setSessionStorageItem(key = '', value = '') {
      const safe = safeSelf();
      const options = safe.getExtraArgs(Array.from(arguments), 2)
      setLocalStorageItemFn('session', false, key, value, options);
  }


  function shouldDebug(details) {
      if ( details instanceof Object === false ) { return false; }
      return scriptletGlobals.canDebug && details.debug;
  }


  function spoofCSS(
      selector,
      ...args
  ) {
      if ( typeof selector !== 'string' ) { return; }
      if ( selector === '' ) { return; }
      const toCamelCase = s => s.replace(/-[a-z]/g, s => s.charAt(1).toUpperCase());
      const propToValueMap = new Map();
      const privatePropToValueMap = new Map();
      for ( let i = 0; i < args.length; i += 2 ) {
          const prop = toCamelCase(args[i+0]);
          if ( prop === '' ) { break; }
          const value = args[i+1];
          if ( typeof value !== 'string' ) { break; }
          if ( prop.charCodeAt(0) === 0x5F /* _ */ ) {
              privatePropToValueMap.set(prop, value);
          } else {
              propToValueMap.set(prop, value);
          }
      }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('spoof-css', selector, ...args);
      const instanceProperties = [ 'cssText', 'length', 'parentRule' ];
      const spoofStyle = (prop, real) => {
          const normalProp = toCamelCase(prop);
          const shouldSpoof = propToValueMap.has(normalProp);
          const value = shouldSpoof ? propToValueMap.get(normalProp) : real;
          if ( shouldSpoof ) {
              safe.uboLog(logPrefix, `Spoofing ${prop} to ${value}`);
          }
          return value;
      };
      const cloackFunc = (fn, thisArg, name) => {
          const trap = fn.bind(thisArg);
          Object.defineProperty(trap, 'name', { value: name });
          Object.defineProperty(trap, 'toString', {
              value: ( ) => `function ${name}() { [native code] }`
          });
          return trap;
      };
      self.getComputedStyle = new Proxy(self.getComputedStyle, {
          apply: function(target, thisArg, args) {
              // eslint-disable-next-line no-debugger
              if ( privatePropToValueMap.has('_debug') ) { debugger; }
              const style = Reflect.apply(target, thisArg, args);
              const targetElements = new WeakSet(document.querySelectorAll(selector));
              if ( targetElements.has(args[0]) === false ) { return style; }
              const proxiedStyle = new Proxy(style, {
                  get(target, prop) {
                      if ( typeof target[prop] === 'function' ) {
                          if ( prop === 'getPropertyValue' ) {
                              return cloackFunc(function getPropertyValue(prop) {
                                  return spoofStyle(prop, target[prop]);
                              }, target, 'getPropertyValue');
                          }
                          return cloackFunc(target[prop], target, prop);
                      }
                      if ( instanceProperties.includes(prop) ) {
                          return Reflect.get(target, prop);
                      }
                      return spoofStyle(prop, Reflect.get(target, prop));
                  },
                  getOwnPropertyDescriptor(target, prop) {
                      if ( propToValueMap.has(prop) ) {
                          return {
                              configurable: true,
                              enumerable: true,
                              value: propToValueMap.get(prop),
                              writable: true,
                          };
                      }
                      return Reflect.getOwnPropertyDescriptor(target, prop);
                  },
              });
              return proxiedStyle;
          },
          get(target, prop) {
              if ( prop === 'toString' ) {
                  return target.toString.bind(target);
              }
              return Reflect.get(target, prop);
          },
      });
      Element.prototype.getBoundingClientRect = new Proxy(Element.prototype.getBoundingClientRect, {
          apply: function(target, thisArg, args) {
              // eslint-disable-next-line no-debugger
              if ( privatePropToValueMap.has('_debug') ) { debugger; }
              const rect = Reflect.apply(target, thisArg, args);
              const targetElements = new WeakSet(document.querySelectorAll(selector));
              if ( targetElements.has(thisArg) === false ) { return rect; }
              let { x, y, height, width } = rect;
              if ( privatePropToValueMap.has('_rectx') ) {
                  x = parseFloat(privatePropToValueMap.get('_rectx'));
              }
              if ( privatePropToValueMap.has('_recty') ) {
                  y = parseFloat(privatePropToValueMap.get('_recty'));
              }
              if ( privatePropToValueMap.has('_rectw') ) {
                  width = parseFloat(privatePropToValueMap.get('_rectw'));
              } else if ( propToValueMap.has('width') ) {
                  width = parseFloat(propToValueMap.get('width'));
              }
              if ( privatePropToValueMap.has('_recth') ) {
                  height = parseFloat(privatePropToValueMap.get('_recth'));
              } else if ( propToValueMap.has('height') ) {
                  height = parseFloat(propToValueMap.get('height'));
              }
              return new self.DOMRect(x, y, width, height);
          },
          get(target, prop) {
              if ( prop === 'toString' ) {
                  return target.toString.bind(target);
              }
              return Reflect.get(target, prop);
          },
      });
  }


  function trustedClickElement(
      selectors = '',
      extraMatch = '',
      delay = ''
  ) {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('trusted-click-element', selectors, extraMatch, delay);

      if ( extraMatch !== '' ) {
          const assertions = safe.String_split.call(extraMatch, ',').map(s => {
              const pos1 = s.indexOf(':');
              const s1 = pos1 !== -1 ? s.slice(0, pos1) : s;
              const not = s1.startsWith('!');
              const type = not ? s1.slice(1) : s1;
              const s2 = pos1 !== -1 ? s.slice(pos1+1).trim() : '';
              if ( s2 === '' ) { return; }
              const out = { not, type };
              const match = /^\/(.+)\/(i?)$/.exec(s2);
              if ( match !== null ) {
                  out.re = new RegExp(match[1], match[2] || undefined);
                  return out;
              }
              const pos2 = s2.indexOf('=');
              const key = pos2 !== -1 ? s2.slice(0, pos2).trim() : s2;
              const value = pos2 !== -1 ? s2.slice(pos2+1).trim() : '';
              out.re = new RegExp(`^${safe.escapeRegexChars(key)}=${safe.escapeRegexChars(value)}`);
              return out;
          }).filter(details => details !== undefined);
          const allCookies = assertions.some(o => o.type === 'cookie')
              ? getAllCookiesFn()
              : [];
          const allStorageItems = assertions.some(o => o.type === 'localStorage')
              ? getAllLocalStorageFn()
              : [];
          const hasNeedle = (haystack, needle) => {
              for ( const { key, value } of haystack ) {
                  if ( needle.test(`${key}=${value}`) ) { return true; }
              }
              return false;
          };
          for ( const { not, type, re } of assertions ) {
              switch ( type ) {
              case 'cookie':
                  if ( hasNeedle(allCookies, re) === not ) { return; }
                  break;
              case 'localStorage':
                  if ( hasNeedle(allStorageItems, re) === not ) { return; }
                  break;
              }
          }
      }

      const getShadowRoot = elem => {
          // Firefox
          if ( elem.openOrClosedShadowRoot ) {
              return elem.openOrClosedShadowRoot;
          }
          // Chromium
          if ( typeof chrome === 'object' ) {
              if ( chrome.dom && chrome.dom.openOrClosedShadowRoot ) {
                  return chrome.dom.openOrClosedShadowRoot(elem);
              }
          }
          return elem.shadowRoot;
      };

      const querySelectorEx = (selector, context = document) => {
          const pos = selector.indexOf(' >>> ');
          if ( pos === -1 ) { return context.querySelector(selector); }
          const outside = selector.slice(0, pos).trim();
          const inside = selector.slice(pos + 5).trim();
          const elem = context.querySelector(outside);
          if ( elem === null ) { return null; }
          const shadowRoot = getShadowRoot(elem);
          return shadowRoot && querySelectorEx(inside, shadowRoot);
      };

      const steps = safe.String_split.call(selectors, /\s*,\s*/).map(a => {
          if ( /^\d+$/.test(a) ) { return parseInt(a, 10); }
          return a;
      });
      if ( steps.length === 0 ) { return; }
      const clickDelay = parseInt(delay, 10) || 1;
      for ( let i = steps.length-1; i > 0; i-- ) {
          if ( typeof steps[i] !== 'string' ) { continue; }
          if ( typeof steps[i-1] !== 'string' ) { continue; }
          steps.splice(i, 0, clickDelay);
      }
      if ( steps.length === 1 && delay !== '' ) {
          steps.unshift(clickDelay);
      }
      if ( typeof steps.at(-1) !== 'number' ) {
          steps.push(10000);
      }

      const waitForTime = ms => {
          return new Promise(resolve => {
              safe.uboLog(logPrefix, `Waiting for ${ms} ms`);
              waitForTime.timer = setTimeout(( ) => {
                  waitForTime.timer = undefined;
                  resolve();
              }, ms);
          });
      };
      waitForTime.cancel = ( ) => {
          const { timer } = waitForTime;
          if ( timer === undefined ) { return; }
          clearTimeout(timer);
          waitForTime.timer = undefined;
      };

      const waitForElement = selector => {
          return new Promise(resolve => {
              const elem = querySelectorEx(selector);
              if ( elem !== null ) {
                  elem.click();
                  resolve();
                  return;
              }
              safe.uboLog(logPrefix, `Waiting for ${selector}`);
              const observer = new MutationObserver(( ) => {
                  const elem = querySelectorEx(selector);
                  if ( elem === null ) { return; }
                  waitForElement.cancel();
                  elem.click();
                  resolve();
              });
              observer.observe(document, {
                  attributes: true,
                  childList: true,
                  subtree: true,
              });
              waitForElement.observer = observer;
          });
      };
      waitForElement.cancel = ( ) => {
          const { observer } = waitForElement;
          if ( observer === undefined ) { return; }
          waitForElement.observer = undefined;
          observer.disconnect();
      };

      const waitForTimeout = ms => {
          waitForTimeout.cancel();
          waitForTimeout.timer = setTimeout(( ) => {
              waitForTimeout.timer = undefined;
              terminate();
              safe.uboLog(logPrefix, `Timed out after ${ms} ms`);
          }, ms);
      };
      waitForTimeout.cancel = ( ) => {
          if ( waitForTimeout.timer === undefined ) { return; }
          clearTimeout(waitForTimeout.timer);
          waitForTimeout.timer = undefined;
      };

      const terminate = ( ) => {
          waitForTime.cancel();
          waitForElement.cancel();
          waitForTimeout.cancel();
      };

      const process = async ( ) => {
          waitForTimeout(steps.pop());
          while ( steps.length !== 0 ) {
              const step = steps.shift();
              if ( step === undefined ) { break; }
              if ( typeof step === 'number' ) {
                  await waitForTime(step);
                  if ( step === 1 ) { continue; }
                  continue;
              }
              if ( step.startsWith('!') ) { continue; }
              await waitForElement(step);
              safe.uboLog(logPrefix, `Clicked ${step}`);
          }
          terminate();
      };

      runAtHtmlElementFn(process);
  }


  function trustedCreateHTML(
      parentSelector,
      htmlStr = '',
      durationStr = ''
  ) {
      if ( parentSelector === '' ) { return; }
      if ( htmlStr === '' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('trusted-create-html', parentSelector, htmlStr, durationStr);
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 3);
      // We do not want to recursively create elements
      self.trustedCreateHTML = true;
      let ancestor = self.frameElement;
      while ( ancestor ) {
          const doc = ancestor.ownerDocument;
          if ( doc === null ) { break; }
          const win = doc.defaultView;
          if ( win === null ) { break; }
          if ( win.trustedCreateHTML ) { return; }
          ancestor = ancestor.frameElement;
      }
      const duration = parseInt(durationStr, 10);
      const domParser = new DOMParser();
      const externalDoc = domParser.parseFromString(htmlStr, 'text/html');
      const toAppend = [];
      while ( externalDoc.body.firstChild !== null ) {
          toAppend.push(document.adoptNode(externalDoc.body.firstChild));
      }
      if ( toAppend.length === 0 ) { return; }
      const toRemove = [];
      const remove = ( ) => {
          for ( const node of toRemove ) {
              if ( node.parentNode === null ) { continue; }
              node.parentNode.removeChild(node);
          }
          safe.uboLog(logPrefix, 'Node(s) removed');
      };
      const appendOne = (target, nodes) => {
          for ( const node of nodes ) {
              target.append(node);
              if ( isNaN(duration) ) { continue; }
              toRemove.push(node);
          }
      };
      const append = ( ) => {
          const targets = document.querySelectorAll(parentSelector);
          if ( targets.length === 0 ) { return false; }
          const limit = Math.min(targets.length, extraArgs.limit || 1) - 1;
          for ( let i = 0; i < limit; i++ ) {
              appendOne(targets[i], toAppend.map(a => a.cloneNode(true)));
          }
          appendOne(targets[limit], toAppend);
          safe.uboLog(logPrefix, 'Node(s) appended');
          if ( toRemove.length === 0 ) { return true; }
          setTimeout(remove, duration);
          return true;
      };
      const start = ( ) => {
          if ( append() ) { return; }
          const observer = new MutationObserver(( ) => {
              if ( append() === false ) { return; }
              observer.disconnect();
          });
          const observerOptions = {
              childList: true,
              subtree: true,
          };
          if ( /[#.[]/.test(parentSelector) ) {
              observerOptions.attributes = true;
              if ( parentSelector.includes('[') === false ) {
                  observerOptions.attributeFilter = [];
                  if ( parentSelector.includes('#') ) {
                      observerOptions.attributeFilter.push('id');
                  }
                  if ( parentSelector.includes('.') ) {
                      observerOptions.attributeFilter.push('class');
                  }
              }
          }
          observer.observe(document, observerOptions);
      };
      runAt(start, extraArgs.runAt || 'loading');
  }


  function trustedEditInboundObject(propChain = '', argPos = '', jsonq = '') {
      editInboundObjectFn(true, propChain, argPos, jsonq);
  }


  function trustedEditOutboundObject(propChain = '', jsonq = '') {
      editOutboundObjectFn(true, propChain, jsonq);
  }


  function trustedJsonEdit(jsonq = '') {
      editOutboundObjectFn(true, 'JSON.parse', jsonq);
  }


  function trustedJsonEditFetchRequest(jsonq = '', ...args) {
      jsonEditFetchRequestFn(true, jsonq, ...args);
  }


  function trustedJsonEditFetchResponse(jsonq = '', ...args) {
      jsonEditFetchResponseFn(true, jsonq, ...args);
  }


  function trustedJsonEditXhrRequest(jsonq = '', ...args) {
      jsonEditXhrRequestFn(true, jsonq, ...args);
  }


  function trustedJsonEditXhrResponse(jsonq = '', ...args) {
      jsonEditXhrResponseFn(true, jsonq, ...args);
  }


  function trustedJsonlEditFetchResponse(jsonq = '', ...args) {
      jsonlEditFetchResponseFn(true, jsonq, ...args);
  }


  function trustedJsonlEditXhrResponse(jsonq = '', ...args) {
      jsonlEditXhrResponseFn(true, jsonq, ...args);
  }


  function trustedOverrideElementMethod(
      methodPath = '',
      selector = '',
      disposition = ''
  ) {
      if ( methodPath === '' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('trusted-override-element-method', methodPath, selector, disposition);
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 3);
      proxyApplyFn(methodPath, function(context) {
          let override = selector === '';
          if ( override === false ) {
              const { thisArg } = context;
              try {
                  override = thisArg.closest(selector) === thisArg;
              } catch {
              }
          }
          if ( override === false ) {
              return context.reflect();
          }
          safe.uboLog(logPrefix, 'Overridden');
          if ( disposition === '' ) { return; }
          if ( disposition === 'debug' && safe.logLevel !== 0 ) {
              debugger; // eslint-disable-line no-debugger
          }
          if ( disposition === 'throw' ) {
              throw new ReferenceError();
          }
          return validateConstantFn(true, disposition, extraArgs);
      });
  }


  function trustedPreventDomBypass(
      methodPath = '',
      targetProp = ''
  ) {
      if ( methodPath === '' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('trusted-prevent-dom-bypass', methodPath, targetProp);
      proxyApplyFn(methodPath, function(context) {
          const elems = new Set(context.callArgs.filter(e => e instanceof HTMLElement));
          const r = context.reflect();
          if ( elems.size === 0 ) { return r; }
          for ( const elem of elems ) {
              try {
                  if ( elem instanceof HTMLIFrameElement && elem.sandbox?.length !== 0 && elem.sandbox.contains('allow-scripts') === false ) { continue; }
                  if ( `${elem.contentWindow}` !== '[object Window]' ) { continue; }
                  if ( elem.contentWindow.location.href !== 'about:blank' ) {
                      if ( elem.contentWindow.location.href !== self.location.href ) {
                          continue;
                      }
                  }
                  if ( targetProp !== '' ) {
                      let me = self, it = elem.contentWindow;
                      let chain = targetProp;
                      for (;;) {
                          const pos = chain.indexOf('.');
                          if ( pos === -1 ) { break; }
                          const prop = chain.slice(0, pos);
                          me = me[prop]; it = it[prop];
                          chain = chain.slice(pos+1);
                      }
                      it[chain] = me[chain];
                  } else {
                      Object.defineProperty(elem, 'contentWindow', { value: self });
                  }
                  safe.uboLog(logPrefix, 'Bypass prevented');
              } catch {
              }
          }
          return r;
      });
  }


  function trustedPreventFetch(...args) {
      preventFetchFn(true, ...args);
  }


  function trustedPreventXhr(...args) {
      return preventXhrFn(true, ...args);
  }


  function trustedPruneInboundObject(
      entryPoint = '',
      argPos = '',
      rawPrunePaths = '',
      rawNeedlePaths = ''
  ) {
      if ( entryPoint === '' ) { return; }
      let context = globalThis;
      let prop = entryPoint;
      for (;;) {
          const pos = prop.indexOf('.');
          if ( pos === -1 ) { break; }
          context = context[prop.slice(0, pos)];
          if ( context instanceof Object === false ) { return; }
          prop = prop.slice(pos+1);
      }
      if ( typeof context[prop] !== 'function' ) { return; }
      const argIndex = parseInt(argPos);
      if ( isNaN(argIndex) ) { return; }
      if ( argIndex < 1 ) { return; }
      const safe = safeSelf();
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 4);
      const needlePaths = [];
      if ( rawPrunePaths !== '' ) {
          needlePaths.push(...safe.String_split.call(rawPrunePaths, / +/));
      }
      if ( rawNeedlePaths !== '' ) {
          needlePaths.push(...safe.String_split.call(rawNeedlePaths, / +/));
      }
      const stackNeedle = safe.initPattern(extraArgs.stackToMatch || '', { canNegate: true });
      const mustProcess = root => {
          for ( const needlePath of needlePaths ) {
              if ( objectFindOwnerFn(root, needlePath) === false ) {
                  return false;
              }
          }
          return true;
      };
      context[prop] = new Proxy(context[prop], {
          apply: function(target, thisArg, args) {
              const targetArg = argIndex <= args.length
                  ? args[argIndex-1]
                  : undefined;
              if ( targetArg instanceof Object && mustProcess(targetArg) ) {
                  let objBefore = targetArg;
                  if ( extraArgs.dontOverwrite ) {
                      try {
                          objBefore = safe.JSON_parse(safe.JSON_stringify(targetArg));
                      } catch {
                          objBefore = undefined;
                      }
                  }
                  if ( objBefore !== undefined ) {
                      const objAfter = objectPruneFn(
                          objBefore,
                          rawPrunePaths,
                          rawNeedlePaths,
                          stackNeedle,
                          extraArgs
                      );
                      args[argIndex-1] = objAfter || objBefore;
                  }
              }
              return Reflect.apply(target, thisArg, args);
          },
      });
  }


  function trustedPruneOutboundObject(
      propChain = '',
      rawPrunePaths = '',
      rawNeedlePaths = ''
  ) {
      if ( propChain === '' ) { return; }
      const safe = safeSelf();
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 3);
      proxyApplyFn(propChain, function(context) {
          const objBefore = context.reflect();
          if ( objBefore instanceof Object === false ) { return objBefore; }
          const objAfter = objectPruneFn(
              objBefore,
              rawPrunePaths,
              rawNeedlePaths,
              { matchAll: true },
              extraArgs
          );
          return objAfter || objBefore;
      });
  }


  function trustedReplaceArgument(
      propChain = '',
      argposRaw = '',
      argraw = ''
  ) {
      if ( propChain === '' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('trusted-replace-argument', propChain, argposRaw, argraw);
      const argoffset = parseInt(argposRaw, 10) || 0;
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 3);
      let replacer;
      if ( argraw.startsWith('repl:/') ) {
          const parsed = parseReplaceFn(argraw.slice(5));
          if ( parsed === undefined ) { return; }
          replacer = arg => `${arg}`.replace(replacer.re, replacer.replacement);
          Object.assign(replacer, parsed);
      } else if ( argraw.startsWith('add:') ) {
          const delta = parseFloat(argraw.slice(4));
          if ( isNaN(delta) ) { return; }
          replacer = arg => Number(arg) + delta;
      } else {
          const value = validateConstantFn(true, argraw, extraArgs);
          replacer = ( ) => value;
      }
      const reCondition = extraArgs.condition
          ? safe.patternToRegex(extraArgs.condition)
          : /^/;
      const getArg = context => {
          if ( argposRaw === 'this' ) { return context.thisArg; }
          const { callArgs } = context;
          const argpos = argoffset >= 0 ? argoffset : callArgs.length - argoffset;
          if ( argpos < 0 || argpos >= callArgs.length ) { return; }
          context.private = { argpos };
          return callArgs[argpos];
      };
      const setArg = (context, value) => {
          if ( argposRaw === 'this' ) {
              if ( value !== context.thisArg ) {
                  context.thisArg = value;
              }
          } else if ( context.private ) {
              context.callArgs[context.private.argpos] = value;
          }
      };
      proxyApplyFn(propChain, function(context) {
          if ( argposRaw === '' ) {
              safe.uboLog(logPrefix, `Arguments:\n${context.callArgs.join('\n')}`);
              return context.reflect();
          }
          const argBefore = getArg(context);
          if ( extraArgs.condition !== undefined ) {
              if ( safe.RegExp_test.call(reCondition, argBefore) === false ) {
                  return context.reflect();
              }
          }
          const argAfter = replacer(argBefore);
          if ( argAfter !== argBefore ) {
              setArg(context, argAfter);
              safe.uboLog(logPrefix, `Replaced argument:\nBefore: ${JSON.stringify(argBefore)}\nAfter: ${argAfter}`);
          }
          return context.reflect();
      });
  }


  function trustedReplaceFetchResponse(...args) {
      replaceFetchResponseFn(true, ...args);
  }


  function trustedReplaceOutboundText(
      propChain = '',
      rawPattern = '',
      rawReplacement = '',
      ...args
  ) {
      if ( propChain === '' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('trusted-replace-outbound-text', propChain, rawPattern, rawReplacement, ...args);
      const rePattern = safe.patternToRegex(rawPattern);
      const replacement = rawReplacement.startsWith('json:')
          ? safe.JSON_parse(rawReplacement.slice(5))
          : rawReplacement;
      const extraArgs = safe.getExtraArgs(args);
      const reCondition = safe.patternToRegex(extraArgs.condition || '');
      proxyApplyFn(propChain, function(context) {
          const encodedTextBefore = context.reflect();
          let textBefore = encodedTextBefore;
          if ( extraArgs.encoding === 'base64' ) {
              try { textBefore = self.atob(encodedTextBefore); }
              catch { return encodedTextBefore; }
          }
          if ( rawPattern === '' ) {
              safe.uboLog(logPrefix, 'Decoded outbound text:\n', textBefore);
              return encodedTextBefore;
          }
          reCondition.lastIndex = 0;
          if ( reCondition.test(textBefore) === false ) { return encodedTextBefore; }
          const textAfter = textBefore.replace(rePattern, replacement);
          if ( textAfter === textBefore ) { return encodedTextBefore; }
          safe.uboLog(logPrefix, 'Matched and replaced');
          if ( safe.logLevel > 1 ) {
              safe.uboLog(logPrefix, 'Modified decoded outbound text:\n', textAfter);
          }
          let encodedTextAfter = textAfter;
          if ( extraArgs.encoding === 'base64' ) {
              encodedTextAfter = self.btoa(textAfter);
          }
          return encodedTextAfter;
      });
  }


  function trustedReplaceXhrResponse(
      pattern = '',
      replacement = '',
      propsToMatch = ''
  ) {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('trusted-replace-xhr-response', pattern, replacement, propsToMatch);
      const xhrInstances = new WeakMap();
      if ( pattern === '*' ) { pattern = '.*'; }
      const rePattern = safe.patternToRegex(pattern);
      const propNeedles = parsePropertiesToMatchFn(propsToMatch, 'url');
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 3);
      const reIncludes = extraArgs.includes ? safe.patternToRegex(extraArgs.includes) : null;
      self.XMLHttpRequest = class extends self.XMLHttpRequest {
          open(method, url, ...args) {
              const outerXhr = this;
              const xhrDetails = { method, url };
              let outcome = 'match';
              if ( propNeedles.size !== 0 ) {
                  if ( matchObjectPropertiesFn(propNeedles, xhrDetails) === undefined ) {
                      outcome = 'nomatch';
                  }
              }
              if ( outcome === 'match' ) {
                  if ( safe.logLevel > 1 ) {
                      safe.uboLog(logPrefix, `Matched "propsToMatch"`);
                  }
                  xhrInstances.set(outerXhr, xhrDetails);
              }
              return super.open(method, url, ...args);
          }
          get response() {
              const innerResponse = super.response;
              const xhrDetails = xhrInstances.get(this);
              if ( xhrDetails === undefined ) {
                  return innerResponse;
              }
              const responseLength = typeof innerResponse === 'string'
                  ? innerResponse.length
                  : undefined;
              if ( xhrDetails.lastResponseLength !== responseLength ) {
                  xhrDetails.response = undefined;
                  xhrDetails.lastResponseLength = responseLength;
              }
              if ( xhrDetails.response !== undefined ) {
                  return xhrDetails.response;
              }
              if ( typeof innerResponse !== 'string' ) {
                  return (xhrDetails.response = innerResponse);
              }
              if ( reIncludes && reIncludes.test(innerResponse) === false ) {
                  return (xhrDetails.response = innerResponse);
              }
              const textBefore = innerResponse;
              const textAfter = textBefore.replace(rePattern, replacement);
              if ( textAfter !== textBefore ) {
                  safe.uboLog(logPrefix, 'Match');
              }
              return (xhrDetails.response = textAfter);
          }
          get responseText() {
              const response = this.response;
              if ( typeof response !== 'string' ) {
                  return super.responseText;
              }
              return response;
          }
      };
  }


  function trustedSetAttr(
      selector = '',
      attr = '',
      value = ''
  ) {
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('trusted-set-attr', selector, attr, value);
      const options = safe.getExtraArgs(Array.from(arguments), 3);
      setAttrFn(true, logPrefix, selector, attr, value, options);
  }


  function trustedSetConstant(
      ...args
  ) {
      setConstantFn(true, ...args);
  }


  function trustedSetCookie(
      name = '',
      value = '',
      offsetExpiresSec = '',
      path = ''
  ) {
      if ( name === '' ) { return; }

      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('set-cookie', name, value, path);
      const time = new Date();

      if ( value.includes('$now$') ) {
          value = value.replaceAll('$now$', time.getTime());
      }
      if ( value.includes('$currentDate$') ) {
          value = value.replaceAll('$currentDate$', time.toUTCString());
      }
      if ( value.includes('$currentISODate$') ) {
          value = value.replaceAll('$currentISODate$', time.toISOString());
      }

      let expires = '';
      if ( offsetExpiresSec !== '' ) {
          if ( offsetExpiresSec === '1day' ) {
              time.setDate(time.getDate() + 1);
          } else if ( offsetExpiresSec === '1year' ) {
              time.setFullYear(time.getFullYear() + 1);
          } else {
              if ( /^\d+$/.test(offsetExpiresSec) === false ) { return; }
              time.setSeconds(time.getSeconds() + parseInt(offsetExpiresSec, 10));
          }
          expires = time.toUTCString();
      }

      const done = setCookieFn(
          true,
          name,
          value,
          expires,
          path,
          safeSelf().getExtraArgs(Array.from(arguments), 4)
      );

      if ( done ) {
          safe.uboLog(logPrefix, 'Done');
      }
  }


  function trustedSetCookieReload(name, value, offsetExpiresSec, path, ...args) {
      trustedSetCookie(name, value, offsetExpiresSec, path, 'reload', '1', ...args);
  }


  function trustedSetLocalStorageItem(key = '', value = '') {
      const safe = safeSelf();
      const options = safe.getExtraArgs(Array.from(arguments), 2)
      setLocalStorageItemFn('local', true, key, value, options);
  }


  function trustedSetSessionStorageItem(key = '', value = '') {
      const safe = safeSelf();
      const options = safe.getExtraArgs(Array.from(arguments), 2)
      setLocalStorageItemFn('session', true, key, value, options);
  }


  function trustedSuppressNativeMethod(
      methodPath = '',
      signature = '',
      how = '',
      stack = ''
  ) {
      if ( methodPath === '' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('trusted-suppress-native-method', methodPath, signature, how, stack);
      const signatureArgs = safe.String_split.call(signature, /\s*\|\s*/).map(v => {
          if ( /^".*"$/.test(v) ) {
              return { type: 'pattern', re: safe.patternToRegex(v.slice(1, -1)) };
          }
          if ( /^\/.+\/$/.test(v) ) {
              return { type: 'pattern', re: safe.patternToRegex(v) };
          }
          if ( v === 'false' ) {
              return { type: 'exact', value: false };
          }
          if ( v === 'true' ) {
              return { type: 'exact', value: true };
          }
          if ( v === 'null' ) {
              return { type: 'exact', value: null };
          }
          if ( v === 'undefined' ) {
              return { type: 'exact', value: undefined };
          }
      });
      const stackNeedle = safe.initPattern(stack, { canNegate: true });
      proxyApplyFn(methodPath, function(context) {
          const { callArgs } = context;
          if ( signature === '' ) {
              safe.uboLog(logPrefix, `Arguments:\n${callArgs.join('\n')}`);
              return context.reflect();
          }
          for ( let i = 0; i < signatureArgs.length; i++ ) {
              const signatureArg = signatureArgs[i];
              if ( signatureArg === undefined ) { continue; }
              const targetArg = i < callArgs.length ? callArgs[i] : undefined;
              if ( signatureArg.type === 'exact' ) {
                  if ( targetArg !== signatureArg.value ) {
                      return context.reflect();
                  }
              }
              if ( signatureArg.type === 'pattern' ) {
                  if ( safe.RegExp_test.call(signatureArg.re, targetArg) === false ) {
                      return context.reflect();
                  }
              }
          }
          if ( stackNeedle.matchAll !== true ) {
              const logLevel = safe.logLevel > 1 ? 'all' : '';
              if ( matchesStackTraceFn(stackNeedle, logLevel) === false ) {
                  return context.reflect();
              }
          }
          if ( how === 'debug' ) {
              debugger; // eslint-disable-line no-debugger
              return context.reflect();
          }
          safe.uboLog(logPrefix, `Suppressed:\n${callArgs.join('\n')}`);
          if ( how === 'abort' ) {
              throw new ReferenceError();
          }
      });
  }


  function urlSkip(url, blocked, steps) {
      try {
          let redirectBlocked = false;
          let urlout = url;
          for ( const step of steps ) {
              const urlin = urlout;
              const c0 = step.charCodeAt(0);
              // Extract from hash
              if ( c0 === 0x23 && step === '#' ) { // #
                  const pos = urlin.indexOf('#');
                  urlout = pos !== -1 ? urlin.slice(pos+1) : '';
                  continue;
              }
              // Extract from URL parameter name at position i
              if ( c0 === 0x26 ) { // &
                  const i = (parseInt(step.slice(1)) || 0) - 1;
                  if ( i < 0 ) { return; }
                  const url = new URL(urlin);
                  if ( i >= url.searchParams.size ) { return; }
                  const params = Array.from(url.searchParams.keys());
                  urlout = decodeURIComponent(params[i]);
                  continue;
              }
              // Enforce https
              if ( c0 === 0x2B && step === '+https' ) { // +
                  const s = urlin.replace(/^https?:\/\//, '');
                  if ( /^[\w-]:\/\//.test(s) ) { return; }
                  urlout = `https://${s}`;
                  continue;
              }
              // Decode
              if ( c0 === 0x2D ) { // -
                  // Base64
                  if ( step === '-base64' ) {
                      urlout = self.atob(urlin);
                      continue;
                  }
                  // Safe Base64
                  if ( step === '-safebase64' ) {
                      if ( urlSkip.safeBase64Replacer === undefined ) {
                          urlSkip.safeBase64Map = { '-': '+', '_': '/' };
                          urlSkip.safeBase64Replacer = s => urlSkip.safeBase64Map[s];
                      }
                      urlout = urlin.replace(/[-_]/g, urlSkip.safeBase64Replacer);
                      urlout = self.atob(urlout);
                      continue;
                  }
                  // URI component
                  if ( step === '-uricomponent' ) {
                      urlout = decodeURIComponent(urlin);
                      continue;
                  }
                  // Enable skip of blocked requests
                  if ( step === '-blocked' ) {
                      redirectBlocked = true;
                      continue;
                  }
              }
              // Regex extraction from first capture group
              if ( c0 === 0x2F ) { // /
                  const re = new RegExp(step.slice(1, -1));
                  const match = re.exec(urlin);
                  if ( match === null ) { return; }
                  if ( match.length <= 1 ) { return; }
                  urlout = match[1];
                  continue;
              }
              // Extract from URL parameter
              if ( c0 === 0x3F ) { // ?
                  urlout = (new URL(urlin)).searchParams.get(step.slice(1));
                  if ( urlout === null ) { return; }
                  if ( urlout.includes(' ') ) {
                      urlout = urlout.replace(/ /g, '%20');
                  }
                  continue;
              }
              // Unknown directive
              return;
          }
          const urlfinal = new URL(urlout);
          if ( urlfinal.protocol !== 'https:' ) {
              if ( urlfinal.protocol !== 'http:' ) { return; }
          }
          if ( blocked && redirectBlocked !== true ) { return; }
          return urlout;
      } catch {
      }
  }


  function validateConstantFn(trusted, raw, extraArgs = {}) {
      const safe = safeSelf();
      let value;
      if ( raw === 'undefined' ) {
          value = undefined;
      } else if ( raw === 'false' ) {
          value = false;
      } else if ( raw === 'true' ) {
          value = true;
      } else if ( raw === 'null' ) {
          value = null;
      } else if ( raw === "''" || raw === '' ) {
          value = '';
      } else if ( raw === '[]' || raw === 'emptyArr' ) {
          value = [];
      } else if ( raw === '{}' || raw === 'emptyObj' ) {
          value = {};
      } else if ( raw === 'noopFunc' ) {
          value = function(){};
      } else if ( raw === 'trueFunc' ) {
          value = function(){ return true; };
      } else if ( raw === 'falseFunc' ) {
          value = function(){ return false; };
      } else if ( raw === 'throwFunc' ) {
          value = function(){ throw ''; };
      } else if ( /^-?\d+$/.test(raw) ) {
          value = parseInt(raw);
          if ( isNaN(raw) ) { return; }
          if ( Math.abs(raw) > 0x7FFF ) { return; }
      } else if ( trusted ) {
          if ( raw.startsWith('json:') ) {
              try { value = safe.JSON_parse(raw.slice(5)); } catch { return; }
          } else if ( raw.startsWith('{') && raw.endsWith('}') ) {
              try { value = safe.JSON_parse(raw).value; } catch { return; }
          }
      } else {
          return;
      }
      if ( extraArgs.as !== undefined ) {
          if ( extraArgs.as === 'function' ) {
              return ( ) => value;
          } else if ( extraArgs.as === 'callback' ) {
              return ( ) => (( ) => value);
          } else if ( extraArgs.as === 'resolved' ) {
              return Promise.resolve(value);
          } else if ( extraArgs.as === 'rejected' ) {
              return Promise.reject(value);
          }
      }
      return value;
  }


  function webrtcIf(
      good = ''
  ) {
      if ( typeof good !== 'string' ) { return; }
      const safe = safeSelf();
      const reGood = safe.patternToRegex(good);
      const rtcName = window.RTCPeerConnection
          ? 'RTCPeerConnection'
          : (window.webkitRTCPeerConnection ? 'webkitRTCPeerConnection' : '');
      if ( rtcName === '' ) { return; }
      const log = console.log.bind(console);
      const neuteredPeerConnections = new WeakSet();
      const isGoodConfig = function(instance, config) {
          if ( neuteredPeerConnections.has(instance) ) { return false; }
          if ( config instanceof Object === false ) { return true; }
          if ( Array.isArray(config.iceServers) === false ) { return true; }
          for ( const server of config.iceServers ) {
              const urls = typeof server.urls === 'string'
                  ? [ server.urls ]
                  : server.urls;
              if ( Array.isArray(urls) ) {
                  for ( const url of urls ) {
                      if ( reGood.test(url) ) { return true; }
                  }
              }
              if ( typeof server.username === 'string' ) {
                  if ( reGood.test(server.username) ) { return true; }
              }
              if ( typeof server.credential === 'string' ) {
                  if ( reGood.test(server.credential) ) { return true; }
              }
          }
          neuteredPeerConnections.add(instance);
          return false;
      };
      const peerConnectionCtor = window[rtcName];
      const peerConnectionProto = peerConnectionCtor.prototype;
      peerConnectionProto.createDataChannel =
          new Proxy(peerConnectionProto.createDataChannel, {
              apply: function(target, thisArg, args) {
                  if ( isGoodConfig(target, args[1]) === false ) {
                      log('uBO:', args[1]);
                      return Reflect.apply(target, thisArg, args.slice(0, 1));
                  }
                  return Reflect.apply(target, thisArg, args);
              },
          });
      window[rtcName] =
          new Proxy(peerConnectionCtor, {
              construct: function(target, args) {
                  if ( isGoodConfig(target, args[0]) === false ) {
                      log('uBO:', args[0]);
                      return Reflect.construct(target);
                  }
                  return Reflect.construct(target, args);
              }
          });
  }


  function windowNameDefuser() {
      if ( window === window.top ) {
          window.name = '';
      }
  }


  function xmlPrune(
      selector = '',
      selectorCheck = '',
      urlPattern = ''
  ) {
      if ( typeof selector !== 'string' ) { return; }
      if ( selector === '' ) { return; }
      const safe = safeSelf();
      const logPrefix = safe.makeLogPrefix('xml-prune', selector, selectorCheck, urlPattern);
      const reUrl = safe.patternToRegex(urlPattern);
      const extraArgs = safe.getExtraArgs(Array.from(arguments), 3);
      const queryAll = (xmlDoc, selector) => {
          const isXpath = /^xpath\(.+\)$/.test(selector);
          if ( isXpath === false ) {
              return Array.from(xmlDoc.querySelectorAll(selector));
          }
          const xpr = xmlDoc.evaluate(
              selector.slice(6, -1),
              xmlDoc,
              null,
              XPathResult.UNORDERED_NODE_SNAPSHOT_TYPE,
              null
          );
          const out = [];
          for ( let i = 0; i < xpr.snapshotLength; i++ ) {
              const node = xpr.snapshotItem(i);
              out.push(node);
          }
          return out;
      };
      const pruneFromDoc = xmlDoc => {
          try {
              if ( selectorCheck !== '' && xmlDoc.querySelector(selectorCheck) === null ) {
                  return xmlDoc;
              }
              if ( extraArgs.logdoc ) {
                  const serializer = new XMLSerializer();
                  safe.uboLog(logPrefix, `Document is\n\t${serializer.serializeToString(xmlDoc)}`);
              }
              const items = queryAll(xmlDoc, selector);
              if ( items.length === 0 ) { return xmlDoc; }
              safe.uboLog(logPrefix, `Removing ${items.length} items`);
              for ( const item of items ) {
                  if ( item.nodeType === 1 ) {
                      item.remove();
                  } else if ( item.nodeType === 2 ) {
                      item.ownerElement.removeAttribute(item.nodeName);
                  }
                  safe.uboLog(logPrefix, `${item.constructor.name}.${item.nodeName} removed`);
              }
          } catch(ex) {
              safe.uboErr(logPrefix, `Error: ${ex}`);
          }
          return xmlDoc;
      };
      const pruneFromText = text => {
          if ( (/^\s*</.test(text) && />\s*$/.test(text)) === false ) {
              return text;
          }
          try {
              const xmlParser = new DOMParser();
              const xmlDoc = xmlParser.parseFromString(text, 'text/xml');
              pruneFromDoc(xmlDoc);
              const serializer = new XMLSerializer();
              text = serializer.serializeToString(xmlDoc);
          } catch {
          }
          return text;
      };
      const urlFromArg = arg => {
          if ( typeof arg === 'string' ) { return arg; }
          if ( arg instanceof Request ) { return arg.url; }
          return String(arg);
      };
      self.fetch = new Proxy(self.fetch, {
          apply: function(target, thisArg, args) {
              const fetchPromise = Reflect.apply(target, thisArg, args);
              if ( reUrl.test(urlFromArg(args[0])) === false ) {
                  return fetchPromise;
              }
              return fetchPromise.then(responseBefore => {
                  const response = responseBefore.clone();
                  return response.text().then(text => {
                      const responseAfter = new Response(pruneFromText(text), {
                          status: responseBefore.status,
                          statusText: responseBefore.statusText,
                          headers: responseBefore.headers,
                      });
                      Object.defineProperties(responseAfter, {
                          ok: { value: responseBefore.ok },
                          redirected: { value: responseBefore.redirected },
                          type: { value: responseBefore.type },
                          url: { value: responseBefore.url },
                      });
                      return responseAfter;
                  }).catch(( ) =>
                      responseBefore
                  );
              });
          }
      });
      self.XMLHttpRequest.prototype.open = new Proxy(self.XMLHttpRequest.prototype.open, {
          apply: async (target, thisArg, args) => {
              if ( reUrl.test(urlFromArg(args[1])) === false ) {
                  return Reflect.apply(target, thisArg, args);
              }
              thisArg.addEventListener('readystatechange', function() {
                  if ( thisArg.readyState !== 4 ) { return; }
                  const type = thisArg.responseType;
                  if (
                      type === 'document' ||
                      type === '' && thisArg.responseXML instanceof XMLDocument
                  ) {
                      pruneFromDoc(thisArg.responseXML);
                      const serializer = new XMLSerializer();
                      const textout = serializer.serializeToString(thisArg.responseXML);
                      Object.defineProperty(thisArg, 'responseText', { value: textout });
                      if ( typeof thisArg.response === 'string' ) {
                          Object.defineProperty(thisArg, 'response', { value: textout });
                      }
                      return;
                  }
                  if (
                      type === 'text' ||
                      type === '' && typeof thisArg.responseText === 'string'
                  ) {
                      const textin = thisArg.responseText;
                      const textout = pruneFromText(textin);
                      if ( textout === textin ) { return; }
                      Object.defineProperty(thisArg, 'response', { value: textout });
                      Object.defineProperty(thisArg, 'responseText', { value: textout });
                      return;
                  }
              });
              return Reflect.apply(target, thisArg, args);
          }
      });
  }


  const scriptletFunctionByName = new Map([["abort-current-inline-script", abortCurrentScript],["abort-current-inline-script.js", abortCurrentScript],["abort-current-script", abortCurrentScript],["abort-current-script.fn", abortCurrentScriptFn],["abort-current-script.js", abortCurrentScript],["abort-on-property-read", abortOnPropertyRead],["abort-on-property-read.js", abortOnPropertyRead],["abort-on-property-write", abortOnPropertyWrite],["abort-on-property-write.js", abortOnPropertyWrite],["abort-on-stack-trace", abortOnStackTrace],["abort-on-stack-trace.js", abortOnStackTrace],["acis", abortCurrentScript],["acis.js", abortCurrentScript],["acs", abortCurrentScript],["acs.js", abortCurrentScript],["addEventListener-defuser", preventAddEventListener],["addEventListener-defuser.js", preventAddEventListener],["adjust-setInterval", adjustSetInterval],["adjust-setInterval.js", adjustSetInterval],["adjust-setTimeout", adjustSetTimeout],["adjust-setTimeout.js", adjustSetTimeout],["aeld", preventAddEventListener],["aeld.js", preventAddEventListener],["alert-buster", alertBuster],["alert-buster.js", alertBuster],["aopr", abortOnPropertyRead],["aopr.js", abortOnPropertyRead],["aopw", abortOnPropertyWrite],["aopw.js", abortOnPropertyWrite],["aost", abortOnStackTrace],["aost.js", abortOnStackTrace],["arglist-parser.fn", ArglistParser],["call-nothrow", callNothrow],["call-nothrow.js", callNothrow],["close-window", closeWindow],["close-window.js", closeWindow],["collate-fetch-arguments.fn", collateFetchArgumentsFn],["cookie-remover", removeCookie],["cookie-remover.js", removeCookie],["disable-newtab-links", disableNewtabLinks],["disable-newtab-links.js", disableNewtabLinks],["edit-inbound-object", editInboundObject],["edit-inbound-object.fn", editInboundObjectFn],["edit-inbound-object.js", editInboundObject],["edit-outbound-object", editOutboundObject],["edit-outbound-object.fn", editOutboundObjectFn],["edit-outbound-object.js", editOutboundObject],["evaldata-prune", evaldataPrune],["evaldata-prune.js", evaldataPrune],["freeze-element-property", freezeElementProperty],["freeze-element-property.js", freezeElementProperty],["generate-content.fn", generateContentFn],["get-all-cookies.fn", getAllCookiesFn],["get-all-local-storage.fn", getAllLocalStorageFn],["get-cookie.fn", getCookieFn],["get-exception-token.fn", getExceptionTokenFn],["get-random-token.fn", getRandomTokenFn],["get-safe-cookie-values.fn", getSafeCookieValuesFn],["href-sanitizer", hrefSanitizer],["href-sanitizer.js", hrefSanitizer],["json-edit", jsonEdit],["json-edit-fetch-request", jsonEditFetchRequest],["json-edit-fetch-request.fn", jsonEditFetchRequestFn],["json-edit-fetch-request.js", jsonEditFetchRequest],["json-edit-fetch-response", jsonEditFetchResponse],["json-edit-fetch-response.fn", jsonEditFetchResponseFn],["json-edit-fetch-response.js", jsonEditFetchResponse],["json-edit-xhr-request", jsonEditXhrRequest],["json-edit-xhr-request.fn", jsonEditXhrRequestFn],["json-edit-xhr-request.js", jsonEditXhrRequest],["json-edit-xhr-response", jsonEditXhrResponse],["json-edit-xhr-response.fn", jsonEditXhrResponseFn],["json-edit-xhr-response.js", jsonEditXhrResponse],["json-edit.js", jsonEdit],["json-prune", jsonPrune],["json-prune-fetch-response", jsonPruneFetchResponse],["json-prune-fetch-response.js", jsonPruneFetchResponse],["json-prune-xhr-response", jsonPruneXhrResponse],["json-prune-xhr-response.js", jsonPruneXhrResponse],["json-prune.js", jsonPrune],["jsonl-edit-fetch-response", jsonlEditFetchResponse],["jsonl-edit-fetch-response.fn", jsonlEditFetchResponseFn],["jsonl-edit-fetch-response.js", jsonlEditFetchResponse],["jsonl-edit-xhr-response", jsonlEditXhrResponse],["jsonl-edit-xhr-response.fn", jsonlEditXhrResponseFn],["jsonl-edit-xhr-response.js", jsonlEditXhrResponse],["jsonl-edit.fn", jsonlEditFn],["jsonpath.fn", JSONPath],["m3u-prune", m3uPrune],["m3u-prune.js", m3uPrune],["match-object-properties.fn", matchObjectPropertiesFn],["matches-stack-trace.fn", matchesStackTraceFn],["multiup", multiup],["multiup.js", multiup],["nano-setInterval-booster", adjustSetInterval],["nano-setInterval-booster.js", adjustSetInterval],["nano-setTimeout-booster", adjustSetTimeout],["nano-setTimeout-booster.js", adjustSetTimeout],["nano-sib", adjustSetInterval],["nano-sib.js", adjustSetInterval],["nano-stb", adjustSetTimeout],["nano-stb.js", adjustSetTimeout],["no-fetch-if", preventFetch],["no-fetch-if.js", preventFetch],["no-requestAnimationFrame-if", preventRequestAnimationFrame],["no-requestAnimationFrame-if.js", preventRequestAnimationFrame],["no-setInterval-if", preventSetInterval],["no-setInterval-if.js", preventSetInterval],["no-setTimeout-if", preventSetTimeout],["no-setTimeout-if.js", preventSetTimeout],["no-window-open-if", noWindowOpenIf],["no-window-open-if.js", noWindowOpenIf],["no-xhr-if", preventXhr],["no-xhr-if.js", preventXhr],["noeval-if", noEvalIf],["noeval-if.js", noEvalIf],["norafif", preventRequestAnimationFrame],["norafif.js", preventRequestAnimationFrame],["nosiif", preventSetInterval],["nosiif.js", preventSetInterval],["nostif", preventSetTimeout],["nostif.js", preventSetTimeout],["nowebrtc", noWebrtc],["nowebrtc.js", noWebrtc],["nowoif", noWindowOpenIf],["nowoif.js", noWindowOpenIf],["object-find-owner.fn", objectFindOwnerFn],["object-prune.fn", objectPruneFn],["overlay-buster", overlayBuster],["overlay-buster.js", overlayBuster],["parse-properties-to-match.fn", parsePropertiesToMatchFn],["parse-replace.fn", parseReplaceFn],["prevent-addEventListener", preventAddEventListener],["prevent-addEventListener.js", preventAddEventListener],["prevent-canvas", preventCanvas],["prevent-canvas.js", preventCanvas],["prevent-dialog", preventDialog],["prevent-dialog.js", preventDialog],["prevent-eval-if", noEvalIf],["prevent-eval-if.js", noEvalIf],["prevent-fetch", preventFetch],["prevent-fetch.fn", preventFetchFn],["prevent-fetch.js", preventFetch],["prevent-innerHTML", preventInnerHTML],["prevent-innerHTML.js", preventInnerHTML],["prevent-navigation", preventNavigation],["prevent-navigation.js", preventNavigation],["prevent-refresh", preventRefresh],["prevent-refresh.js", preventRefresh],["prevent-requestAnimationFrame", preventRequestAnimationFrame],["prevent-requestAnimationFrame.js", preventRequestAnimationFrame],["prevent-setInterval", preventSetInterval],["prevent-setInterval.js", preventSetInterval],["prevent-setTimeout", preventSetTimeout],["prevent-setTimeout.js", preventSetTimeout],["prevent-window-open", noWindowOpenIf],["prevent-window-open.js", noWindowOpenIf],["prevent-xhr", preventXhr],["prevent-xhr.fn", preventXhrFn],["prevent-xhr.js", preventXhr],["proxy-apply.fn", proxyApplyFn],["ra", removeAttr],["ra.js", removeAttr],["range-parser.fn", RangeParser],["rc", removeClass],["rc.js", removeClass],["refresh-defuser", preventRefresh],["refresh-defuser.js", preventRefresh],["remove-attr", removeAttr],["remove-attr.js", removeAttr],["remove-cache-storage-item.fn", removeCacheStorageItem],["remove-class", removeClass],["remove-class.js", removeClass],["remove-cookie", removeCookie],["remove-cookie.js", removeCookie],["remove-node-text", removeNodeText],["remove-node-text.js", removeNodeText],["replace-fetch-response.fn", replaceFetchResponseFn],["replace-node-text", replaceNodeText],["replace-node-text.fn", replaceNodeTextFn],["replace-node-text.js", replaceNodeText],["rmnt", removeNodeText],["rmnt.js", removeNodeText],["rpnt", replaceNodeText],["rpnt.js", replaceNodeText],["run-at-html-element.fn", runAtHtmlElementFn],["run-at.fn", runAt],["safe-self.fn", safeSelf],["set", setConstant],["set-attr", setAttr],["set-attr.fn", setAttrFn],["set-attr.js", setAttr],["set-constant", setConstant],["set-constant.fn", setConstantFn],["set-constant.js", setConstant],["set-cookie", setCookie],["set-cookie-reload", setCookieReload],["set-cookie-reload.js", setCookieReload],["set-cookie.fn", setCookieFn],["set-cookie.js", setCookie],["set-local-storage-item", setLocalStorageItem],["set-local-storage-item.fn", setLocalStorageItemFn],["set-local-storage-item.js", setLocalStorageItem],["set-session-storage-item", setSessionStorageItem],["set-session-storage-item.js", setSessionStorageItem],["set.js", setConstant],["setInterval-defuser", preventSetInterval],["setInterval-defuser.js", preventSetInterval],["setTimeout-defuser", preventSetTimeout],["setTimeout-defuser.js", preventSetTimeout],["should-debug.fn", shouldDebug],["spoof-css", spoofCSS],["spoof-css.js", spoofCSS],["trusted-click-element", trustedClickElement],["trusted-click-element.js", trustedClickElement],["trusted-create-html", trustedCreateHTML],["trusted-create-html.js", trustedCreateHTML],["trusted-edit-inbound-object", trustedEditInboundObject],["trusted-edit-inbound-object.js", trustedEditInboundObject],["trusted-edit-outbound-object", trustedEditOutboundObject],["trusted-edit-outbound-object.js", trustedEditOutboundObject],["trusted-json-edit", trustedJsonEdit],["trusted-json-edit-fetch-request", trustedJsonEditFetchRequest],["trusted-json-edit-fetch-request.js", trustedJsonEditFetchRequest],["trusted-json-edit-fetch-response", trustedJsonEditFetchResponse],["trusted-json-edit-fetch-response.js", trustedJsonEditFetchResponse],["trusted-json-edit-xhr-request", trustedJsonEditXhrRequest],["trusted-json-edit-xhr-request.js", trustedJsonEditXhrRequest],["trusted-json-edit-xhr-response", trustedJsonEditXhrResponse],["trusted-json-edit-xhr-response.js", trustedJsonEditXhrResponse],["trusted-json-edit.js", trustedJsonEdit],["trusted-jsonl-edit-fetch-response", trustedJsonlEditFetchResponse],["trusted-jsonl-edit-fetch-response.js", trustedJsonlEditFetchResponse],["trusted-jsonl-edit-xhr-response", trustedJsonlEditXhrResponse],["trusted-jsonl-edit-xhr-response.js", trustedJsonlEditXhrResponse],["trusted-override-element-method", trustedOverrideElementMethod],["trusted-override-element-method.js", trustedOverrideElementMethod],["trusted-prevent-dom-bypass", trustedPreventDomBypass],["trusted-prevent-dom-bypass.js", trustedPreventDomBypass],["trusted-prevent-fetch", trustedPreventFetch],["trusted-prevent-fetch.js", trustedPreventFetch],["trusted-prevent-xhr", trustedPreventXhr],["trusted-prevent-xhr.js", trustedPreventXhr],["trusted-prune-inbound-object", trustedPruneInboundObject],["trusted-prune-inbound-object.js", trustedPruneInboundObject],["trusted-prune-outbound-object", trustedPruneOutboundObject],["trusted-prune-outbound-object.js", trustedPruneOutboundObject],["trusted-replace-argument", trustedReplaceArgument],["trusted-replace-argument.js", trustedReplaceArgument],["trusted-replace-fetch-response", trustedReplaceFetchResponse],["trusted-replace-fetch-response.js", trustedReplaceFetchResponse],["trusted-replace-node-text", replaceNodeText],["trusted-replace-node-text.js", replaceNodeText],["trusted-replace-outbound-text", trustedReplaceOutboundText],["trusted-replace-outbound-text.js", trustedReplaceOutboundText],["trusted-replace-xhr-response", trustedReplaceXhrResponse],["trusted-replace-xhr-response.js", trustedReplaceXhrResponse],["trusted-rpfr", trustedReplaceFetchResponse],["trusted-rpfr.js", trustedReplaceFetchResponse],["trusted-rpnt", replaceNodeText],["trusted-rpnt.js", replaceNodeText],["trusted-set", trustedSetConstant],["trusted-set-attr", trustedSetAttr],["trusted-set-attr.js", trustedSetAttr],["trusted-set-constant", trustedSetConstant],["trusted-set-constant.js", trustedSetConstant],["trusted-set-cookie", trustedSetCookie],["trusted-set-cookie-reload", trustedSetCookieReload],["trusted-set-cookie-reload.js", trustedSetCookieReload],["trusted-set-cookie.js", trustedSetCookie],["trusted-set-local-storage-item", trustedSetLocalStorageItem],["trusted-set-local-storage-item.js", trustedSetLocalStorageItem],["trusted-set-session-storage-item", trustedSetSessionStorageItem],["trusted-set-session-storage-item.js", trustedSetSessionStorageItem],["trusted-set.js", trustedSetConstant],["trusted-suppress-native-method", trustedSuppressNativeMethod],["trusted-suppress-native-method.js", trustedSuppressNativeMethod],["ubo-abort-current-inline-script", abortCurrentScript],["ubo-abort-current-inline-script.js", abortCurrentScript],["ubo-abort-current-script", abortCurrentScript],["ubo-abort-current-script.fn", abortCurrentScriptFn],["ubo-abort-current-script.js", abortCurrentScript],["ubo-abort-on-property-read", abortOnPropertyRead],["ubo-abort-on-property-read.js", abortOnPropertyRead],["ubo-abort-on-property-write", abortOnPropertyWrite],["ubo-abort-on-property-write.js", abortOnPropertyWrite],["ubo-abort-on-stack-trace", abortOnStackTrace],["ubo-abort-on-stack-trace.js", abortOnStackTrace],["ubo-acis", abortCurrentScript],["ubo-acis.js", abortCurrentScript],["ubo-acs", abortCurrentScript],["ubo-acs.js", abortCurrentScript],["ubo-addEventListener-defuser", preventAddEventListener],["ubo-addEventListener-defuser.js", preventAddEventListener],["ubo-adjust-setInterval", adjustSetInterval],["ubo-adjust-setInterval.js", adjustSetInterval],["ubo-adjust-setTimeout", adjustSetTimeout],["ubo-adjust-setTimeout.js", adjustSetTimeout],["ubo-aeld", preventAddEventListener],["ubo-aeld.js", preventAddEventListener],["ubo-alert-buster", alertBuster],["ubo-alert-buster.js", alertBuster],["ubo-aopr", abortOnPropertyRead],["ubo-aopr.js", abortOnPropertyRead],["ubo-aopw", abortOnPropertyWrite],["ubo-aopw.js", abortOnPropertyWrite],["ubo-aost", abortOnStackTrace],["ubo-aost.js", abortOnStackTrace],["ubo-arglist-parser.fn", ArglistParser],["ubo-call-nothrow", callNothrow],["ubo-call-nothrow.js", callNothrow],["ubo-close-window", closeWindow],["ubo-close-window.js", closeWindow],["ubo-collate-fetch-arguments.fn", collateFetchArgumentsFn],["ubo-cookie-remover", removeCookie],["ubo-cookie-remover.js", removeCookie],["ubo-disable-newtab-links", disableNewtabLinks],["ubo-disable-newtab-links.js", disableNewtabLinks],["ubo-edit-inbound-object", editInboundObject],["ubo-edit-inbound-object.fn", editInboundObjectFn],["ubo-edit-inbound-object.js", editInboundObject],["ubo-edit-outbound-object", editOutboundObject],["ubo-edit-outbound-object.fn", editOutboundObjectFn],["ubo-edit-outbound-object.js", editOutboundObject],["ubo-evaldata-prune", evaldataPrune],["ubo-evaldata-prune.js", evaldataPrune],["ubo-freeze-element-property", freezeElementProperty],["ubo-freeze-element-property.js", freezeElementProperty],["ubo-generate-content.fn", generateContentFn],["ubo-get-all-cookies.fn", getAllCookiesFn],["ubo-get-all-local-storage.fn", getAllLocalStorageFn],["ubo-get-cookie.fn", getCookieFn],["ubo-get-exception-token.fn", getExceptionTokenFn],["ubo-get-random-token.fn", getRandomTokenFn],["ubo-get-safe-cookie-values.fn", getSafeCookieValuesFn],["ubo-href-sanitizer", hrefSanitizer],["ubo-href-sanitizer.js", hrefSanitizer],["ubo-json-edit", jsonEdit],["ubo-json-edit-fetch-request", jsonEditFetchRequest],["ubo-json-edit-fetch-request.fn", jsonEditFetchRequestFn],["ubo-json-edit-fetch-request.js", jsonEditFetchRequest],["ubo-json-edit-fetch-response", jsonEditFetchResponse],["ubo-json-edit-fetch-response.fn", jsonEditFetchResponseFn],["ubo-json-edit-fetch-response.js", jsonEditFetchResponse],["ubo-json-edit-xhr-request", jsonEditXhrRequest],["ubo-json-edit-xhr-request.fn", jsonEditXhrRequestFn],["ubo-json-edit-xhr-request.js", jsonEditXhrRequest],["ubo-json-edit-xhr-response", jsonEditXhrResponse],["ubo-json-edit-xhr-response.fn", jsonEditXhrResponseFn],["ubo-json-edit-xhr-response.js", jsonEditXhrResponse],["ubo-json-edit.js", jsonEdit],["ubo-json-prune", jsonPrune],["ubo-json-prune-fetch-response", jsonPruneFetchResponse],["ubo-json-prune-fetch-response.js", jsonPruneFetchResponse],["ubo-json-prune-xhr-response", jsonPruneXhrResponse],["ubo-json-prune-xhr-response.js", jsonPruneXhrResponse],["ubo-json-prune.js", jsonPrune],["ubo-jsonl-edit-fetch-response", jsonlEditFetchResponse],["ubo-jsonl-edit-fetch-response.fn", jsonlEditFetchResponseFn],["ubo-jsonl-edit-fetch-response.js", jsonlEditFetchResponse],["ubo-jsonl-edit-xhr-response", jsonlEditXhrResponse],["ubo-jsonl-edit-xhr-response.fn", jsonlEditXhrResponseFn],["ubo-jsonl-edit-xhr-response.js", jsonlEditXhrResponse],["ubo-jsonl-edit.fn", jsonlEditFn],["ubo-jsonpath.fn", JSONPath],["ubo-m3u-prune", m3uPrune],["ubo-m3u-prune.js", m3uPrune],["ubo-match-object-properties.fn", matchObjectPropertiesFn],["ubo-matches-stack-trace.fn", matchesStackTraceFn],["ubo-multiup", multiup],["ubo-multiup.js", multiup],["ubo-nano-setInterval-booster", adjustSetInterval],["ubo-nano-setInterval-booster.js", adjustSetInterval],["ubo-nano-setTimeout-booster", adjustSetTimeout],["ubo-nano-setTimeout-booster.js", adjustSetTimeout],["ubo-nano-sib", adjustSetInterval],["ubo-nano-sib.js", adjustSetInterval],["ubo-nano-stb", adjustSetTimeout],["ubo-nano-stb.js", adjustSetTimeout],["ubo-no-fetch-if", preventFetch],["ubo-no-fetch-if.js", preventFetch],["ubo-no-requestAnimationFrame-if", preventRequestAnimationFrame],["ubo-no-requestAnimationFrame-if.js", preventRequestAnimationFrame],["ubo-no-setInterval-if", preventSetInterval],["ubo-no-setInterval-if.js", preventSetInterval],["ubo-no-setTimeout-if", preventSetTimeout],["ubo-no-setTimeout-if.js", preventSetTimeout],["ubo-no-window-open-if", noWindowOpenIf],["ubo-no-window-open-if.js", noWindowOpenIf],["ubo-no-xhr-if", preventXhr],["ubo-no-xhr-if.js", preventXhr],["ubo-noeval-if", noEvalIf],["ubo-noeval-if.js", noEvalIf],["ubo-norafif", preventRequestAnimationFrame],["ubo-norafif.js", preventRequestAnimationFrame],["ubo-nosiif", preventSetInterval],["ubo-nosiif.js", preventSetInterval],["ubo-nostif", preventSetTimeout],["ubo-nostif.js", preventSetTimeout],["ubo-nowebrtc", noWebrtc],["ubo-nowebrtc.js", noWebrtc],["ubo-nowoif", noWindowOpenIf],["ubo-nowoif.js", noWindowOpenIf],["ubo-object-find-owner.fn", objectFindOwnerFn],["ubo-object-prune.fn", objectPruneFn],["ubo-overlay-buster", overlayBuster],["ubo-overlay-buster.js", overlayBuster],["ubo-parse-properties-to-match.fn", parsePropertiesToMatchFn],["ubo-parse-replace.fn", parseReplaceFn],["ubo-prevent-addEventListener", preventAddEventListener],["ubo-prevent-addEventListener.js", preventAddEventListener],["ubo-prevent-canvas", preventCanvas],["ubo-prevent-canvas.js", preventCanvas],["ubo-prevent-dialog", preventDialog],["ubo-prevent-dialog.js", preventDialog],["ubo-prevent-eval-if", noEvalIf],["ubo-prevent-eval-if.js", noEvalIf],["ubo-prevent-fetch", preventFetch],["ubo-prevent-fetch.fn", preventFetchFn],["ubo-prevent-fetch.js", preventFetch],["ubo-prevent-innerHTML", preventInnerHTML],["ubo-prevent-innerHTML.js", preventInnerHTML],["ubo-prevent-navigation", preventNavigation],["ubo-prevent-navigation.js", preventNavigation],["ubo-prevent-refresh", preventRefresh],["ubo-prevent-refresh.js", preventRefresh],["ubo-prevent-requestAnimationFrame", preventRequestAnimationFrame],["ubo-prevent-requestAnimationFrame.js", preventRequestAnimationFrame],["ubo-prevent-setInterval", preventSetInterval],["ubo-prevent-setInterval.js", preventSetInterval],["ubo-prevent-setTimeout", preventSetTimeout],["ubo-prevent-setTimeout.js", preventSetTimeout],["ubo-prevent-window-open", noWindowOpenIf],["ubo-prevent-window-open.js", noWindowOpenIf],["ubo-prevent-xhr", preventXhr],["ubo-prevent-xhr.fn", preventXhrFn],["ubo-prevent-xhr.js", preventXhr],["ubo-proxy-apply.fn", proxyApplyFn],["ubo-ra", removeAttr],["ubo-ra.js", removeAttr],["ubo-range-parser.fn", RangeParser],["ubo-rc", removeClass],["ubo-rc.js", removeClass],["ubo-refresh-defuser", preventRefresh],["ubo-refresh-defuser.js", preventRefresh],["ubo-remove-attr", removeAttr],["ubo-remove-attr.js", removeAttr],["ubo-remove-cache-storage-item.fn", removeCacheStorageItem],["ubo-remove-class", removeClass],["ubo-remove-class.js", removeClass],["ubo-remove-cookie", removeCookie],["ubo-remove-cookie.js", removeCookie],["ubo-remove-node-text", removeNodeText],["ubo-remove-node-text.js", removeNodeText],["ubo-replace-fetch-response.fn", replaceFetchResponseFn],["ubo-replace-node-text", replaceNodeText],["ubo-replace-node-text.fn", replaceNodeTextFn],["ubo-replace-node-text.js", replaceNodeText],["ubo-rmnt", removeNodeText],["ubo-rmnt.js", removeNodeText],["ubo-rpnt", replaceNodeText],["ubo-rpnt.js", replaceNodeText],["ubo-run-at-html-element.fn", runAtHtmlElementFn],["ubo-run-at.fn", runAt],["ubo-safe-self.fn", safeSelf],["ubo-set", setConstant],["ubo-set-attr", setAttr],["ubo-set-attr.fn", setAttrFn],["ubo-set-attr.js", setAttr],["ubo-set-constant", setConstant],["ubo-set-constant.fn", setConstantFn],["ubo-set-constant.js", setConstant],["ubo-set-cookie", setCookie],["ubo-set-cookie-reload", setCookieReload],["ubo-set-cookie-reload.js", setCookieReload],["ubo-set-cookie.fn", setCookieFn],["ubo-set-cookie.js", setCookie],["ubo-set-local-storage-item", setLocalStorageItem],["ubo-set-local-storage-item.fn", setLocalStorageItemFn],["ubo-set-local-storage-item.js", setLocalStorageItem],["ubo-set-session-storage-item", setSessionStorageItem],["ubo-set-session-storage-item.js", setSessionStorageItem],["ubo-set.js", setConstant],["ubo-setInterval-defuser", preventSetInterval],["ubo-setInterval-defuser.js", preventSetInterval],["ubo-setTimeout-defuser", preventSetTimeout],["ubo-setTimeout-defuser.js", preventSetTimeout],["ubo-should-debug.fn", shouldDebug],["ubo-spoof-css", spoofCSS],["ubo-spoof-css.js", spoofCSS],["ubo-trusted-click-element", trustedClickElement],["ubo-trusted-click-element.js", trustedClickElement],["ubo-trusted-create-html", trustedCreateHTML],["ubo-trusted-create-html.js", trustedCreateHTML],["ubo-trusted-edit-inbound-object", trustedEditInboundObject],["ubo-trusted-edit-inbound-object.js", trustedEditInboundObject],["ubo-trusted-edit-outbound-object", trustedEditOutboundObject],["ubo-trusted-edit-outbound-object.js", trustedEditOutboundObject],["ubo-trusted-json-edit", trustedJsonEdit],["ubo-trusted-json-edit-fetch-request", trustedJsonEditFetchRequest],["ubo-trusted-json-edit-fetch-request.js", trustedJsonEditFetchRequest],["ubo-trusted-json-edit-fetch-response", trustedJsonEditFetchResponse],["ubo-trusted-json-edit-fetch-response.js", trustedJsonEditFetchResponse],["ubo-trusted-json-edit-xhr-request", trustedJsonEditXhrRequest],["ubo-trusted-json-edit-xhr-request.js", trustedJsonEditXhrRequest],["ubo-trusted-json-edit-xhr-response", trustedJsonEditXhrResponse],["ubo-trusted-json-edit-xhr-response.js", trustedJsonEditXhrResponse],["ubo-trusted-json-edit.js", trustedJsonEdit],["ubo-trusted-jsonl-edit-fetch-response", trustedJsonlEditFetchResponse],["ubo-trusted-jsonl-edit-fetch-response.js", trustedJsonlEditFetchResponse],["ubo-trusted-jsonl-edit-xhr-response", trustedJsonlEditXhrResponse],["ubo-trusted-jsonl-edit-xhr-response.js", trustedJsonlEditXhrResponse],["ubo-trusted-override-element-method", trustedOverrideElementMethod],["ubo-trusted-override-element-method.js", trustedOverrideElementMethod],["ubo-trusted-prevent-dom-bypass", trustedPreventDomBypass],["ubo-trusted-prevent-dom-bypass.js", trustedPreventDomBypass],["ubo-trusted-prevent-fetch", trustedPreventFetch],["ubo-trusted-prevent-fetch.js", trustedPreventFetch],["ubo-trusted-prevent-xhr", trustedPreventXhr],["ubo-trusted-prevent-xhr.js", trustedPreventXhr],["ubo-trusted-prune-inbound-object", trustedPruneInboundObject],["ubo-trusted-prune-inbound-object.js", trustedPruneInboundObject],["ubo-trusted-prune-outbound-object", trustedPruneOutboundObject],["ubo-trusted-prune-outbound-object.js", trustedPruneOutboundObject],["ubo-trusted-replace-argument", trustedReplaceArgument],["ubo-trusted-replace-argument.js", trustedReplaceArgument],["ubo-trusted-replace-fetch-response", trustedReplaceFetchResponse],["ubo-trusted-replace-fetch-response.js", trustedReplaceFetchResponse],["ubo-trusted-replace-node-text", replaceNodeText],["ubo-trusted-replace-node-text.js", replaceNodeText],["ubo-trusted-replace-outbound-text", trustedReplaceOutboundText],["ubo-trusted-replace-outbound-text.js", trustedReplaceOutboundText],["ubo-trusted-replace-xhr-response", trustedReplaceXhrResponse],["ubo-trusted-replace-xhr-response.js", trustedReplaceXhrResponse],["ubo-trusted-rpfr", trustedReplaceFetchResponse],["ubo-trusted-rpfr.js", trustedReplaceFetchResponse],["ubo-trusted-rpnt", replaceNodeText],["ubo-trusted-rpnt.js", replaceNodeText],["ubo-trusted-set", trustedSetConstant],["ubo-trusted-set-attr", trustedSetAttr],["ubo-trusted-set-attr.js", trustedSetAttr],["ubo-trusted-set-constant", trustedSetConstant],["ubo-trusted-set-constant.js", trustedSetConstant],["ubo-trusted-set-cookie", trustedSetCookie],["ubo-trusted-set-cookie-reload", trustedSetCookieReload],["ubo-trusted-set-cookie-reload.js", trustedSetCookieReload],["ubo-trusted-set-cookie.js", trustedSetCookie],["ubo-trusted-set-local-storage-item", trustedSetLocalStorageItem],["ubo-trusted-set-local-storage-item.js", trustedSetLocalStorageItem],["ubo-trusted-set-session-storage-item", trustedSetSessionStorageItem],["ubo-trusted-set-session-storage-item.js", trustedSetSessionStorageItem],["ubo-trusted-set.js", trustedSetConstant],["ubo-trusted-suppress-native-method", trustedSuppressNativeMethod],["ubo-trusted-suppress-native-method.js", trustedSuppressNativeMethod],["ubo-urlskip", hrefSanitizer],["ubo-urlskip.fn", urlSkip],["ubo-urlskip.js", hrefSanitizer],["ubo-validate-constant.fn", validateConstantFn],["ubo-webrtc-if", webrtcIf],["ubo-webrtc-if.js", webrtcIf],["ubo-window-close-if", closeWindow],["ubo-window-close-if.js", closeWindow],["ubo-window.name-defuser", windowNameDefuser],["ubo-window.name-defuser.js", windowNameDefuser],["ubo-window.open-defuser", noWindowOpenIf],["ubo-window.open-defuser.js", noWindowOpenIf],["ubo-xml-prune", xmlPrune],["ubo-xml-prune.js", xmlPrune],["urlskip", hrefSanitizer],["urlskip.fn", urlSkip],["urlskip.js", hrefSanitizer],["validate-constant.fn", validateConstantFn],["webrtc-if", webrtcIf],["webrtc-if.js", webrtcIf],["window-close-if", closeWindow],["window-close-if.js", closeWindow],["window.name-defuser", windowNameDefuser],["window.name-defuser.js", windowNameDefuser],["window.open-defuser", noWindowOpenIf],["window.open-defuser.js", noWindowOpenIf],["xml-prune", xmlPrune],["xml-prune.js", xmlPrune]]);

  function normalizeIncomingName(name) {
    const raw = String(name || '').trim();
    if (raw.startsWith('ubo-')) {
      const unprefixed = raw.slice(4);
      if (scriptletFunctionByName.has(unprefixed)) return unprefixed;
      if (scriptletFunctionByName.has(unprefixed + '.js')) return unprefixed + '.js';
    }
    if (scriptletFunctionByName.has(raw)) return raw;
    if (raw.endsWith('.js') === false && scriptletFunctionByName.has(raw + '.js')) return raw + '.js';
    return raw;
  }

  const proceduralOperatorNames = [
    'matches-css-before', 'matches-css-after', 'matches-css',
    'matches-attr', 'matches-property', 'min-text-length',
    'has-text', '-abp-contains', 'contains', 'nth-ancestor',
    'upward', 'xpath', 'has', 'not'
  ];
  const proceduralCssPattern = /(^\^)|[(:]has-text|:-abp-contains|:contains|:xpath|:upward|:nth-ancestor|:matches-css|:matches-attr|:matches-property|:min-text-length|:remove\(\)|:style\(|:has\(/;
  const proceduralSelectorCache = new Map();

  function stripWatchAttr(selector) {
    return String(selector || '').replace(/:watch-attr\([^)]*\)/g, '');
  }

  function parseTrailingFunction(selector, name) {
    const needle = `:${name}(`;
    if (!String(selector || '').endsWith(')')) return null;
    const start = selector.lastIndexOf(needle);
    if (start === -1) return null;
    return {
      selector: selector.slice(0, start),
      argument: selector.slice(start + needle.length, -1)
    };
  }

  function cssDeclarationText(styleText) {
    return String(styleText || '')
      .split(';')
      .map(part => part.trim())
      .filter(Boolean)
      .map(part => /!important\s*$/i.test(part) ? part : `${part} !important`)
      .join(';');
  }

  function injectCssRules() {
    const cssRules = [];
    for (const rule of [...css, ...extendedCss]) {
      if (typeof rule !== 'string' || !rule.trim()) continue;
      const trimmedRule = rule.trim();
      if (trimmedRule.startsWith('^')) continue;
      const styleAction = parseTrailingFunction(trimmedRule, 'style');
      if (styleAction) {
        const selector = stripWatchAttr(styleAction.selector).trim();
        if (selector && !proceduralCssPattern.test(selector)) {
          cssRules.push(`${selector}{${cssDeclarationText(styleAction.argument)}}`);
        }
        continue;
      }
      const selector = stripWatchAttr(trimmedRule);
      if (proceduralCssPattern.test(selector)) continue;
      cssRules.push(selector.includes('{') ? selector : `${selector}{display:none!important;}`);
    }
    if (!cssRules.length || !document.documentElement) return;
    const style = document.createElement('style');
    style.setAttribute('data-wblock-runtime', 'css');
    style.textContent = cssRules.join('\n');
    (document.head || document.documentElement).appendChild(style);
  }

  function regexFromLiteral(text) {
    const value = String(text || '').trim();
    if (value.startsWith('/') && value.lastIndexOf('/') > 0) {
      const end = value.lastIndexOf('/');
      try { return new RegExp(value.slice(1, end), value.slice(end + 1)); } catch (_) { return null; }
    }
    try { return new RegExp(value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')); } catch (_) { return null; }
  }

  function parseCSSPropertyTest(text) {
    const index = String(text || '').indexOf(':');
    if (index === -1) return null;
    return {
      property: text.slice(0, index).trim(),
      value: text.slice(index + 1).trim()
    };
  }

  function elementMatchesCSSTest(element, test, pseudo = null) {
    if (!element || !test) return false;
    try {
      if (getComputedStyle(element, pseudo).getPropertyValue(test.property).trim() === test.value) return true;
    } catch (_) {}
    if (!pseudo) return false;
    try {
      const pseudoName = pseudo.replace(/^::?/, '');
      const pseudoSuffixes = [`::${pseudoName}`, `:${pseudoName}`];
      for (const sheet of document.styleSheets) {
        let rules;
        try { rules = sheet.cssRules; } catch (_) { continue; }
        for (const rule of rules) {
          const selectorText = rule && rule.selectorText;
          const style = rule && rule.style;
          if (!selectorText || !style) continue;
          for (const selector of selectorText.split(',')) {
            const trimmed = selector.trim();
            const pseudoSuffix = pseudoSuffixes.find(suffix => trimmed.endsWith(suffix));
            if (!pseudoSuffix) continue;
            const base = trimmed.slice(0, -pseudoSuffix.length).trim();
            if (base && element.matches(base) && style.getPropertyValue(test.property).trim() === test.value) return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  function nthChildIndex(element) {
    let index = 1;
    for (let node = element.previousElementSibling; node; node = node.previousElementSibling) index += 1;
    return index;
  }

  function relativeQueryAll(element, selector) {
    selector = String(selector || '').trim();
    if (!selector) return [];
    selector = selector.replace(/^:scope\s*/, '').trim();
    if (!selector) return [element];
    if (selector.startsWith('>')) {
      try { return Array.from(element.querySelectorAll(`:scope ${selector}`)); } catch (_) { return []; }
    }
    if (selector.startsWith('+') || selector.startsWith('~')) {
      const parent = element.parentElement;
      if (!parent) return [];
      try { return Array.from(parent.querySelectorAll(`:scope > :nth-child(${nthChildIndex(element)})${selector}`)); } catch (_) { return []; }
    }
    try { return Array.from(element.querySelectorAll(selector)); } catch (_) { return []; }
  }

  function queryAllFromContext(context, selector) {
    selector = String(selector || '').trim();
    if (!selector) return context && context.nodeType === 1 ? [context] : [document];
    if (context && context.nodeType === 1) {
      if (/^(?:\s*[>+~]|:scope\b)/.test(selector)) return relativeQueryAll(context, selector);
      try { return Array.from(context.querySelectorAll(selector)); } catch (_) { return []; }
    }
    try { return Array.from(document.querySelectorAll(selector)); } catch (_) { return []; }
  }

  function findNextProceduralOperator(selector, start = 0) {
    let depth = 0;
    let quote = '';
    for (let i = start; i < selector.length; i++) {
      const ch = selector[i];
      if (quote) {
        if (ch === '\\') { i += 1; continue; }
        if (ch === quote) quote = '';
        continue;
      }
      if (ch === '"' || ch === "'" || ch === '`') { quote = ch; continue; }
      if (ch === '(') { depth += 1; continue; }
      if (ch === ')') { depth = Math.max(0, depth - 1); continue; }
      if (ch !== ':' || depth !== 0) continue;
      for (const name of proceduralOperatorNames) {
        if (selector.startsWith(`${name}(`, i + 1)) {
          return { index: i, name, argStart: i + name.length + 2 };
        }
      }
    }
    return null;
  }

  function findClosingParen(text, openIndex) {
    let depth = 1;
    let quote = '';
    for (let i = openIndex + 1; i < text.length; i++) {
      const ch = text[i];
      if (quote) {
        if (ch === '\\') { i += 1; continue; }
        if (ch === quote) quote = '';
        continue;
      }
      if (ch === '"' || ch === "'" || ch === '`') { quote = ch; continue; }
      if (ch === '(') { depth += 1; continue; }
      if (ch === ')') {
        depth -= 1;
        if (depth === 0) return i;
      }
    }
    return -1;
  }

  function normalizeProceduralOperator(name) {
    if (name === '-abp-contains' || name === 'contains') return 'has-text';
    if (name === 'nth-ancestor') return 'upward';
    return name;
  }

  function parseProceduralSelector(rawSelector) {
    const raw = stripWatchAttr(String(rawSelector || '').trim());
    const cached = proceduralSelectorCache.get(raw);
    if (cached) return cached;
    const first = findNextProceduralOperator(raw, 0);
    if (!first) {
      const parsed = { selector: raw, tasks: [], procedural: false };
      proceduralSelectorCache.set(raw, parsed);
      return parsed;
    }
    const out = { selector: raw.slice(0, first.index).trim(), tasks: [], procedural: true };
    let cursor = first.index;
    while (cursor < raw.length) {
      const found = findNextProceduralOperator(raw, cursor);
      if (!found) {
        const spath = raw.slice(cursor).trim();
        if (spath) out.tasks.push(['spath', spath]);
        break;
      }
      if (found.index > cursor) {
        const spath = raw.slice(cursor, found.index).trim();
        if (spath) out.tasks.push(['spath', spath]);
      }
      const close = findClosingParen(raw, found.argStart - 1);
      if (close === -1) break;
      out.tasks.push([normalizeProceduralOperator(found.name), raw.slice(found.argStart, close)]);
      cursor = close + 1;
    }
    proceduralSelectorCache.set(raw, out);
    return out;
  }

  function evaluateProceduralSelector(parsed, context = document) {
    let nodes = queryAllFromContext(context, parsed.selector);
    for (const task of parsed.tasks) {
      if (!nodes.length) break;
      const op = task[0];
      const arg = String(task[1] || '').trim();
      if (op === 'spath') {
        nodes = nodes.flatMap(node => relativeQueryAll(node, arg));
      } else if (op === 'has') {
        nodes = nodes.filter(node => evaluateProceduralSelector(parseProceduralSelector(arg), node).length > 0);
      } else if (op === 'not') {
        nodes = nodes.filter(node => evaluateProceduralSelector(parseProceduralSelector(arg), node).length === 0);
      } else if (op === 'has-text') {
        const re = regexFromLiteral(arg);
        nodes = re ? nodes.filter(node => re.test(node.textContent || '')) : [];
      } else if (op === 'min-text-length') {
        const min = Number(arg);
        nodes = Number.isFinite(min) ? nodes.filter(node => (node.textContent || '').length >= min) : [];
      } else if (op === 'matches-css') {
        const test = parseCSSPropertyTest(arg);
        nodes = nodes.filter(node => elementMatchesCSSTest(node, test));
      } else if (op === 'matches-css-before' || op === 'matches-css-after') {
        const test = parseCSSPropertyTest(arg);
        const pseudo = op.endsWith('before') ? '::before' : '::after';
        nodes = nodes.filter(node => elementMatchesCSSTest(node, test, pseudo));
      } else if (op === 'upward') {
        const out = [];
        for (const node of nodes) {
          let target = node;
          if (/^\d+$/.test(arg)) {
            for (let i = 0; target && i < Number(arg); i++) target = target.parentElement;
          } else {
            target = target.parentElement ? target.parentElement.closest(arg) : null;
          }
          if (target) out.push(target);
        }
        nodes = out;
      } else if (op === 'xpath') {
        const out = [];
        for (const node of nodes) {
          try {
            const result = document.evaluate(arg, node, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            for (let i = 0; i < result.snapshotLength; i++) {
              const item = result.snapshotItem(i);
              if (item && item.nodeType === 1) out.push(item);
            }
          } catch (_) {}
        }
        nodes = out;
      } else {
        nodes = [];
      }
    }
    return Array.from(new Set(nodes)).filter(node => node && node.nodeType === 1);
  }

  function applyProceduralAction(elements, styleText, remove) {
    for (const element of elements) {
      if (!element || element.nodeType !== 1) continue;
      try {
        if (remove) {
          element.remove();
        } else if (styleText !== null) {
          element.style.cssText += ';' + cssDeclarationText(styleText);
        } else {
          element.style.setProperty('display', 'none', 'important');
        }
      } catch (_) {}
    }
  }

  function selectProceduralElements(rawRule) {
    let selector = stripWatchAttr(String(rawRule || '').trim());
    let styleText = null;
    let remove = false;
    if (selector.startsWith('^')) {
      selector = selector.slice(1).trim();
      remove = true;
    }
    const styleAction = parseTrailingFunction(selector, 'style');
    if (styleAction) {
      selector = styleAction.selector;
      styleText = styleAction.argument;
    }
    if (selector.endsWith(':remove()')) {
      selector = selector.slice(0, -':remove()'.length);
      remove = true;
    }
    const parsed = parseProceduralSelector(selector);
    try {
      const elements = parsed.procedural
        ? evaluateProceduralSelector(parsed, document)
        : Array.from(document.querySelectorAll(selector));
      return { elements, styleText, remove };
    } catch (_) {
      return { elements: [], styleText, remove };
    }
  }

  function runProceduralCssRules() {
    const rules = extendedCss.filter(rule => typeof rule === 'string' && proceduralCssPattern.test(rule));
    if (!rules.length || !document.documentElement) return;
    for (const rule of rules) {
      const result = selectProceduralElements(rule);
      applyProceduralAction(result.elements, result.styleText, result.remove);
    }
  }

  function installProceduralCssRuntime() {
    const rules = extendedCss.filter(rule => typeof rule === 'string' && proceduralCssPattern.test(rule));
    if (!rules.length || !document.documentElement) return;
    const run = () => { try { runProceduralCssRules(); } catch (_) {} };
    let pending = false;
    const scheduleRun = () => {
      if (pending) return;
      pending = true;
      const flush = () => { pending = false; run(); };
      try { requestAnimationFrame(flush); } catch (_) { setTimeout(flush, 16); }
    };
    run();
    try { document.addEventListener('DOMContentLoaded', scheduleRun, { once: true }); } catch (_) {}
    try { setTimeout(scheduleRun, 50); setTimeout(scheduleRun, 150); setTimeout(scheduleRun, 500); } catch (_) {}
    try { new MutationObserver(scheduleRun).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['class'] }); } catch (_) {}
  }

  function runRawScripts() {
    for (const source of scripts) {
      if (typeof source !== 'string' || !source.trim()) continue;
      try { (0, eval)(source); } catch (_) {}
    }
  }

  try { injectCssRules(); } catch (_) {}
  try { installProceduralCssRuntime(); } catch (_) {}
  for (const scriptlet of scriptlets) {
    const args = Array.isArray(scriptlet && scriptlet.args) ? scriptlet.args : [];
    const normalizedName = normalizeIncomingName(scriptlet && scriptlet.name);
    const fn = scriptletFunctionByName.get(normalizedName);
    if (!fn) continue;
    const key = normalizedName + '\u001f' + JSON.stringify(args);
    if (applied.has(key)) continue;
    applied.add(key);
    try { fn(...args); } catch (_) {}
  }
  try { runRawScripts(); } catch (_) {}
}

let engineTimestamp = 0;
let dnrRulesTimestamp = 0;
const WBLOCK_DNR_DYNAMIC_ID_MIN = 2000000;
const WBLOCK_DNR_DYNAMIC_ID_MAX = 2999999;
const cache = new Map();
let nativeMessageQueue = Promise.resolve();
let registeredAdvancedRuntimeTimestamp = 0;
let registeredAdvancedRuntimeKey = '';
let registeredAdvancedRuntimeRefresh = null;
let registeredYouTubeMainRuntimeKey = '';
const WBLOCK_REGISTERED_ADVANCED_RUNTIME_ID = 'wblock-advanced-runtime-scriptlets';
const WBLOCK_YOUTUBE_MAIN_RUNTIME_ID = 'wblock-youtube-main-runtime';
const WBLOCK_YOUTUBE_MAIN_RUNTIME_MATCHES = [
  '*://youtube.com/*',
  '*://www.youtube.com/*',
  '*://m.youtube.com/*',
  '*://music.youtube.com/*',
  '*://tv.youtube.com/*',
  '*://youtube-nocookie.com/*',
  '*://www.youtube-nocookie.com/*',
  '*://youtubekids.com/*',
  '*://www.youtubekids.com/*'
];
const menuCommandsByTab = new Map();

const sendQueuedNativeMessage = request => {
  const response = nativeMessageQueue.then(() => browser.runtime.sendNativeMessage(NATIVE_HOST_ID, request));
  nativeMessageQueue = response.catch(() => {});
  return response;
};

const cacheKey = (url, topUrl) => `${url}#${topUrl || ''}`;

function hasDNRDomainScope(condition) {
  return Boolean(
    condition && (
      condition.requestDomains ||
      condition.excludedRequestDomains ||
      condition.initiatorDomains ||
      condition.excludedInitiatorDomains
    )
  );
}

function isUnsafeBroadDNRRedirect(rule) {
  const redirect = rule && rule.action && rule.action.redirect;
  const condition = rule && rule.condition;
  return Boolean(
    redirect &&
    redirect.extensionPath &&
    condition &&
    condition.urlFilter === '*' &&
    !hasDNRDomainScope(condition)
  );
}

function isGoogleVideoPlaybackDNRRule(rule) {
  const actionType = rule && rule.action && rule.action.type;
  if (actionType !== 'block' && actionType !== 'redirect') return false;
  const condition = rule && rule.condition;
  if (!condition) return false;
  const haystack = [
    condition.urlFilter,
    condition.regexFilter,
    ...(Array.isArray(condition.requestDomains) ? condition.requestDomains : []),
    ...(Array.isArray(condition.excludedRequestDomains) ? condition.excludedRequestDomains : [])
  ].filter(Boolean).join('\n').toLowerCase();
  const isPlaybackHost = haystack.includes('googlevideo') || haystack.includes('c.youtube');
  return isPlaybackHost && (haystack.includes('videoplayback') || haystack.includes('initplayback'));
}

function normalizeDynamicDNRRules(rules) {
  if (!Array.isArray(rules)) return [];
  const normalized = [];
  let nextId = WBLOCK_DNR_DYNAMIC_ID_MIN;
  for (const rule of rules) {
    if (!rule || typeof rule !== 'object') continue;
    if (!rule.action || !rule.condition) continue;
    if (isUnsafeBroadDNRRedirect(rule)) continue;
    if (isGoogleVideoPlaybackDNRRule(rule)) continue;
    const copy = JSON.parse(JSON.stringify(rule));
    // Safari rejects safari-web-extension:// URLs in DNR redirect.url.
    // Keep extensionPath intact so WebKit can resolve the packaged resource.
    copy.id = nextId++;
    if (copy.id > WBLOCK_DNR_DYNAMIC_ID_MAX) break;
    normalized.push(copy);
  }
  return normalized;
}

function logDNRSyncDiagnostic(fields) {
  browser.runtime.sendNativeMessage(NATIVE_HOST_ID, {
    action: 'logExtensionDiagnostic',
    fields: { source: 'background', event: 'dnr_sync', ...fields }
  }).catch(() => {});
}

function invalidDynamicRuleIndex(error) {
  const text = error && error.message ? error.message : String(error || '');
  const match = text.match(/rule_at_index_(\d+)/i);
  return match ? Number.parseInt(match[1], 10) : -1;
}

async function updateDynamicRulesSkippingInvalid(removeRuleIds, rules) {
  const candidates = rules.slice();
  const rejected = [];
  for (;;) {
    try {
      await browser.declarativeNetRequest.updateDynamicRules({ removeRuleIds, addRules: candidates });
      return { rules: candidates, rejected };
    } catch (error) {
      const index = invalidDynamicRuleIndex(error);
      if (!Number.isInteger(index) || index < 0 || index >= candidates.length) throw error;
      const rejectedRule = candidates.splice(index, 1)[0];
      rejected.push({ id: rejectedRule && rejectedRule.id, reason: error && error.message ? error.message : String(error) });
      if (candidates.length === 0) {
        await browser.declarativeNetRequest.updateDynamicRules({ removeRuleIds, addRules: [] });
        return { rules: candidates, rejected };
      }
    }
  }
}

async function allDynamicDNRRuleIds() {
  if (browser.declarativeNetRequest.getDynamicRules) {
    const existing = await browser.declarativeNetRequest.getDynamicRules();
    return existing
      .map(rule => rule && rule.id)
      .filter(id => Number.isInteger(id));
  }
  return Array.from({ length: WBLOCK_DNR_DYNAMIC_ID_MAX - WBLOCK_DNR_DYNAMIC_ID_MIN + 1 }, (_, i) => WBLOCK_DNR_DYNAMIC_ID_MIN + i);
}

async function clearDynamicDNRRules(reason = 'clear') {
  if (!browser.declarativeNetRequest || !browser.declarativeNetRequest.updateDynamicRules) return;
  try {
    const removeRuleIds = await allDynamicDNRRuleIds();
    if (!removeRuleIds.length) return;
    await browser.declarativeNetRequest.updateDynamicRules({ removeRuleIds, addRules: [] });
    dnrRulesTimestamp = 0;
    logDNRSyncDiagnostic({ outcome: reason, rules: 0, removed: removeRuleIds.length });
  } catch (error) {
    console.warn('[wBlock] Dynamic DNR clear failed:', error);
    logDNRSyncDiagnostic({ outcome: `${reason}_failure`, rules: 0, reason: error && error.message ? error.message : String(error) });
  }
}

async function syncDynamicDNRRules(configuration) {
  const timestamp = configuration && configuration.engineTimestamp || 0;
  if (timestamp === dnrRulesTimestamp) return;
  if (!browser.declarativeNetRequest || !browser.declarativeNetRequest.updateDynamicRules) return;
  const rules = normalizeDynamicDNRRules(configuration && configuration.dnrRules);
  try {
    const removeRuleIds = await allDynamicDNRRuleIds();
    const result = await updateDynamicRulesSkippingInvalid(removeRuleIds, rules);
    dnrRulesTimestamp = timestamp;
    if (result.rejected.length) {
      logDNRSyncDiagnostic({ outcome: 'success_partial', rules: result.rules.length, rejected: result.rejected.length, rejectedIds: result.rejected.map(rule => rule.id).join(','), removed: removeRuleIds.length, timestamp });
    } else {
      logDNRSyncDiagnostic({ outcome: 'success', rules: result.rules.length, removed: removeRuleIds.length, timestamp });
    }
  } catch (error) {
    console.warn('[wBlock] Dynamic DNR sync failed:', error);
    logDNRSyncDiagnostic({ outcome: 'failure', rules: rules.length, reason: error && error.message ? error.message : String(error) });
  }
}

function wBlockRegisteredAdvancedRuntimeCode(payload) {
  const scriptlets = Array.isArray(payload && payload.scriptlets) ? payload.scriptlets : [];
  const disabledSites = Array.isArray(payload && payload.disabledSites) ? payload.disabledSites : [];
  const configurationJSON = JSON.stringify({ scriptlets, disabledSites });
  return `(() => {
    const registered = ${configurationJSON};
    const normalizeDomain = value => String(value || '').trim().replace(/^\\.+|\\.+$/g, '').toLowerCase();
    const domainMatches = (domain, host) => {
      const normalized = normalizeDomain(domain);
      if (!normalized) return false;
      if (normalized === '*') return true;
      const suffix = normalized.startsWith('*.') ? normalized.slice(2) : normalized;
      return host === suffix || host.endsWith('.' + suffix);
    };
    const host = normalizeDomain(location.hostname);
    if (!host) return;
    if (registered.disabledSites.some(domain => domainMatches(domain, host))) return;
    const activeScriptlets = [];
    for (const rule of registered.scriptlets) {
      if (!rule || typeof rule.name !== 'string') continue;
      const ifDomains = Array.isArray(rule.ifDomains) ? rule.ifDomains : [];
      const unlessDomains = Array.isArray(rule.unlessDomains) ? rule.unlessDomains : [];
      if (unlessDomains.some(domain => domainMatches(domain, host))) continue;
      if (ifDomains.length && !ifDomains.some(domain => domainMatches(domain, host))) continue;
      activeScriptlets.push({ name: rule.name, args: Array.isArray(rule.args) ? rule.args : [] });
    }
    if (!activeScriptlets.length) return;
    (${wBlockApplyConfiguration.toString()})({ css: [], extendedCss: [], js: [], scriptlets: activeScriptlets });
  })();`;
}

function wBlockNormalizeDomain(value) {
  return String(value || '').trim().replace(/^\.+|\.+$/g, '').toLowerCase();
}

function wBlockDomainMatches(domain, host) {
  const normalized = wBlockNormalizeDomain(domain);
  const normalizedHost = wBlockNormalizeDomain(host);
  if (!normalized || !normalizedHost) return false;
  if (normalized === '*') return true;
  const suffix = normalized.startsWith('*.') ? normalized.slice(2) : normalized;
  return normalizedHost === suffix || normalizedHost.endsWith('.' + suffix);
}

function wBlockIsYouTubeRuntimeDisabled(disabledSites) {
  const hosts = ['youtube.com', 'www.youtube.com', 'music.youtube.com', 'm.youtube.com', 'tv.youtube.com', 'youtube-nocookie.com', 'www.youtube-nocookie.com', 'youtubekids.com', 'www.youtubekids.com'];
  return Array.isArray(disabledSites) && disabledSites.some(domain => hosts.some(host => wBlockDomainMatches(domain, host)));
}

async function unregisterRegisteredAdvancedRuntime(reason = 'unregister') {
  if (!browser.userScripts || !browser.userScripts.unregister) return false;
  try {
    await browser.userScripts.unregister({ ids: [WBLOCK_REGISTERED_ADVANCED_RUNTIME_ID] });
    registeredAdvancedRuntimeTimestamp = 0;
    registeredAdvancedRuntimeKey = '';
    return true;
  } catch (error) {
    console.warn(`[wBlock] Registered advanced runtime ${reason} failed:`, error);
    return false;
  }
}

async function unregisterYouTubeMainRuntime(reason = 'unregister') {
  if (!browser.scripting || !browser.scripting.unregisterContentScripts) return false;
  try {
    await browser.scripting.unregisterContentScripts({ ids: [WBLOCK_YOUTUBE_MAIN_RUNTIME_ID] });
    registeredYouTubeMainRuntimeKey = '';
    return true;
  } catch (error) {
    console.warn(`[wBlock] YouTube MAIN runtime ${reason} unregister failed:`, error);
    return false;
  }
}

async function registerYouTubeMainRuntimeScript(script) {
  const attempts = [
    script,
    { ...script, persistAcrossSessions: undefined },
    { ...script, matchOriginAsFallback: undefined },
    { ...script, persistAcrossSessions: undefined, matchOriginAsFallback: undefined }
  ];
  let lastError = null;
  for (const attempt of attempts) {
    const cleaned = Object.fromEntries(Object.entries(attempt).filter(([, value]) => value !== undefined));
    try {
      await browser.scripting.registerContentScripts([cleaned]);
      return true;
    } catch (error) {
      lastError = error;
    }
  }
  if (lastError) throw lastError;
  return false;
}

async function refreshYouTubeMainRuntimeRegistration(disabledSites, reason = 'refresh') {
  if (!browser.scripting || !browser.scripting.registerContentScripts || !browser.scripting.unregisterContentScripts) return false;
  const disabled = wBlockIsYouTubeRuntimeDisabled(disabledSites);
  const registrationKey = disabled ? 'disabled' : 'enabled';
  if (registrationKey === registeredYouTubeMainRuntimeKey) return true;
  if (disabled) {
    if (await unregisterYouTubeMainRuntime('disabled')) {
      registeredYouTubeMainRuntimeKey = registrationKey;
    }
    return false;
  }
  const script = {
    id: WBLOCK_YOUTUBE_MAIN_RUNTIME_ID,
    js: ['youtube-early-main.js'],
    matches: WBLOCK_YOUTUBE_MAIN_RUNTIME_MATCHES,
    allFrames: true,
    runAt: 'document_start',
    world: 'MAIN',
    matchOriginAsFallback: true,
    persistAcrossSessions: true
  };
  try {
    await browser.scripting.unregisterContentScripts({ ids: [WBLOCK_YOUTUBE_MAIN_RUNTIME_ID] }).catch(() => {});
    await registerYouTubeMainRuntimeScript(script);
    registeredYouTubeMainRuntimeKey = registrationKey;
    return true;
  } catch (error) {
    registeredYouTubeMainRuntimeKey = '';
    console.warn(`[wBlock] YouTube MAIN runtime ${reason} register failed:`, error);
    return false;
  }
}

async function refreshRegisteredAdvancedRuntime(reason = 'refresh') {
  if (registeredAdvancedRuntimeRefresh) return registeredAdvancedRuntimeRefresh;
  registeredAdvancedRuntimeRefresh = (async () => {
    let payload = null;
    try {
      const response = await sendQueuedNativeMessage({ action: 'getAdvancedRuntimeRegistration' });
      payload = response && response.payload;
    } catch (error) {
      console.warn('[wBlock] Registered advanced runtime lookup failed:', error);
      return false;
    }

    const disabledSites = Array.isArray(payload && payload.disabledSites) ? payload.disabledSites : [];
    await refreshYouTubeMainRuntimeRegistration(disabledSites, reason);

    if (!browser.userScripts || !browser.userScripts.register || !browser.userScripts.unregister) return false;
    const timestamp = payload && payload.engineTimestamp || 0;
    const scriptlets = Array.isArray(payload && payload.scriptlets) ? payload.scriptlets : [];
    if (!timestamp || !scriptlets.length) {
      await unregisterRegisteredAdvancedRuntime('empty');
      return false;
    }
    const registrationKey = JSON.stringify({ timestamp, disabledSites, scriptlets: scriptlets.length });
    if (registrationKey === registeredAdvancedRuntimeKey) return true;

    const code = wBlockRegisteredAdvancedRuntimeCode(payload);
    try {
      await browser.userScripts.unregister({ ids: [WBLOCK_REGISTERED_ADVANCED_RUNTIME_ID] }).catch(() => {});
      await browser.userScripts.register([{
        id: WBLOCK_REGISTERED_ADVANCED_RUNTIME_ID,
        js: [{ code }],
        matches: ['http://*/*', 'https://*/*'],
        allFrames: true,
        runAt: 'document_start',
        world: 'MAIN'
      }]);
      registeredAdvancedRuntimeTimestamp = timestamp;
      registeredAdvancedRuntimeKey = registrationKey;
      return true;
    } catch (error) {
      registeredAdvancedRuntimeTimestamp = 0;
      registeredAdvancedRuntimeKey = '';
      console.warn(`[wBlock] Registered advanced runtime ${reason} failed:`, error);
      return false;
    }
  })().finally(() => { registeredAdvancedRuntimeRefresh = null; });
  return registeredAdvancedRuntimeRefresh;
}

function scheduleRegisteredAdvancedRuntimeRefresh(reason = 'schedule') {
  refreshRegisteredAdvancedRuntime(reason).catch(() => {});
}

clearDynamicDNRRules('startup_clear').catch(() => {});
scheduleRegisteredAdvancedRuntimeRefresh('startup');

async function requestConfiguration(originalRequest, url, topUrl) {
  const request = { ...(originalRequest || {}), payload: { url, topUrl } };
  const response = await sendQueuedNativeMessage(request);
  const configuration = response && response.payload;
  if (!configuration) return null;
  if (configuration.engineTimestamp !== engineTimestamp) {
    cache.clear();
    engineTimestamp = configuration.engineTimestamp || 0;
    scheduleRegisteredAdvancedRuntimeRefresh('engine_timestamp_changed');
  }
  await syncDynamicDNRRules(configuration);
  cache.set(cacheKey(url, topUrl), configuration);
  return configuration;
}

async function getConfiguration(message, url, topUrl) {
  const key = cacheKey(url, topUrl);
  if (cache.has(key)) {
    requestConfiguration(message, url, topUrl).catch(() => {});
    return cache.get(key);
  }
  return requestConfiguration(message, url, topUrl);
}

async function insertCss(tabId, frameId, configuration) {
  const css = Array.isArray(configuration.css) ? configuration.css : [];
  const extendedCss = Array.isArray(configuration.extendedCss) ? configuration.extendedCss : [];
  const simpleExtended = extendedCss.filter(rule => typeof rule === 'string' && !/[(:]has-text|:-abp-contains|:xpath|:upward|:matches-css|:matches-attr|:matches-property|:remove\(\)|:style\(/.test(rule));
  const selectors = [...css, ...simpleExtended].filter(rule => typeof rule === 'string' && rule.trim());
  if (!selectors.length || !browser.scripting || !browser.scripting.insertCSS) return;
  const cssText = selectors.map(selector => selector.includes('{') ? selector : `${selector}{display:none!important;}`).join('\n');
  await browser.scripting.insertCSS({
    target: { tabId, frameIds: [frameId] },
    origin: 'USER',
    css: cssText
  }).catch(error => console.warn('[wBlock] CSS injection failed:', error));
}

async function applyConfiguration(tabId, frameId, configuration) {
  if (!configuration) return;
  await insertCss(tabId, frameId, configuration);
  const scriptlets = Array.isArray(configuration.scriptlets) ? configuration.scriptlets : [];
  const scripts = Array.isArray(configuration.js) ? configuration.js : [];
  const extendedCss = Array.isArray(configuration.extendedCss) ? configuration.extendedCss : [];
  if (!scriptlets.length && !scripts.length && !extendedCss.length) return;
  await browser.scripting.executeScript({
    target: { tabId, frameIds: [frameId] },
    func: wBlockApplyConfiguration,
    args: [configuration],
    world: 'MAIN',
    injectImmediately: true
  }).catch(error => console.warn('[wBlock] MAIN-world runtime injection failed:', error));
}

function wBlockExecuteUserScriptSource(source) {
  'use strict';
  if (typeof source !== 'string' || !source) return false;
  (0, Function)(source)();
  return true;
}

async function executeUserScriptInMainWorld(tabId, frameId, source) {
  if (!tabId || !browser.scripting || !browser.scripting.executeScript) {
    return { ok: false, error: 'MAIN-world scripting API unavailable' };
  }
  const details = {
    target: { tabId, frameIds: [frameId] },
    func: wBlockExecuteUserScriptSource,
    args: [source],
    world: 'MAIN',
    injectImmediately: true
  };
  try {
    await browser.scripting.executeScript(details);
    return { ok: true };
  } catch (firstError) {
    try {
      const retryDetails = { ...details };
      delete retryDetails.injectImmediately;
      await browser.scripting.executeScript(retryDetails);
      return { ok: true };
    } catch (retryError) {
      return { ok: false, error: String((retryError && retryError.message) || (firstError && firstError.message) || retryError || firstError) };
    }
  }
}

const FORBIDDEN_GM_XHR_HEADER_NAMES = new Set([
  'accept-charset', 'accept-encoding', 'access-control-request-headers',
  'access-control-request-method', 'connection', 'content-length', 'cookie',
  'date', 'dnt', 'host', 'keep-alive', 'origin', 'permissions-policy',
  'referer', 'referrer', 'te', 'trailer', 'transfer-encoding', 'upgrade',
  'user-agent', 'via'
]);
const shouldUseNativeGMXmlhttpRequest = headers => !!headers && typeof headers === 'object' && Object.keys(headers).some(name => {
  const normalized = String(name || '').trim().toLowerCase();
  return FORBIDDEN_GM_XHR_HEADER_NAMES.has(normalized) || normalized.startsWith('proxy-') || normalized.startsWith('sec-');
});
const formatGMResponseHeaders = headers => !headers || typeof headers !== 'object' ? '' : Object.entries(headers).map(([key, value]) => `${key}: ${value}`).join('\r\n');
const normalizeGMResponseType = responseType => String(responseType || 'text').trim().toLowerCase();
const isBinaryGMResponseType = responseType => ['arraybuffer', 'blob'].includes(normalizeGMResponseType(responseType));
const isTextLikeMimeType = mimeType => {
  const normalized = String(mimeType || '').toLowerCase();
  return normalized.startsWith('text/') || normalized.includes('json') || normalized.includes('javascript') || normalized.includes('xml') || normalized === 'image/svg+xml';
};
const bytesToBase64 = bytes => {
  let binary = '';
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
};
const parseGMResponseBody = (responseText, responseType) => {
  if (normalizeGMResponseType(responseType) === 'json') {
    try { return JSON.parse(responseText || 'null'); } catch (_) { return null; }
  }
  return responseText;
};
const buildGMResponsePayload = async (fetchResponse, responseType) => {
  const headers = {};
  fetchResponse.headers.forEach((value, key) => { headers[key] = value; });
  const normalizedResponseType = normalizeGMResponseType(responseType);
  const contentType = fetchResponse.headers.get('content-type') || '';

  if (isBinaryGMResponseType(normalizedResponseType)) {
    const arrayBuffer = await fetchResponse.arrayBuffer();
    const bytes = new Uint8Array(arrayBuffer);
    const responseText = isTextLikeMimeType(contentType) ? new TextDecoder().decode(bytes) : '';
    return {
      status: fetchResponse.status,
      statusText: fetchResponse.statusText,
      responseHeaders: formatGMResponseHeaders(headers),
      responseText,
      response: null,
      responseBase64: bytesToBase64(bytes),
      responseMimeType: contentType,
      responseType: normalizedResponseType,
      finalUrl: fetchResponse.url
    };
  }

  const responseText = await fetchResponse.text();
  return {
    status: fetchResponse.status,
    statusText: fetchResponse.statusText,
    responseHeaders: formatGMResponseHeaders(headers),
    responseText,
    response: parseGMResponseBody(responseText, normalizedResponseType),
    responseType: normalizedResponseType,
    finalUrl: fetchResponse.url
  };
};

const normalizeMenuCommands = commands => Array.isArray(commands) ? commands.filter(command => command && typeof command === 'object').map(command => ({
  bridgeId: typeof command.bridgeId === 'string' ? command.bridgeId : '',
  commandId: typeof command.commandId === 'string' ? command.commandId : '',
  caption: typeof command.caption === 'string' ? command.caption : '',
  title: typeof command.title === 'string' ? command.title : '',
  accessKey: typeof command.accessKey === 'string' ? command.accessKey : '',
  scriptName: typeof command.scriptName === 'string' ? command.scriptName : '',
  sortOrder: Number.isFinite(Number(command.sortOrder)) ? Number(command.sortOrder) : 0
})).filter(command => command.bridgeId && command.commandId && command.caption.trim()) : [];

function setFrameMenuCommands(tabId, frameId, commands) {
  if (typeof tabId !== 'number') return;
  const frameCommands = menuCommandsByTab.get(tabId) || new Map();
  const normalized = normalizeMenuCommands(commands).map(command => ({ ...command, frameId }));
  if (normalized.length) frameCommands.set(frameId, normalized); else frameCommands.delete(frameId);
  if (frameCommands.size) menuCommandsByTab.set(tabId, frameCommands); else menuCommandsByTab.delete(tabId);
}
function getTabMenuCommands(tabId) {
  const frameCommands = menuCommandsByTab.get(tabId);
  if (!frameCommands) return [];
  return Array.from(frameCommands.values()).flat().sort((a, b) => a.sortOrder - b.sortOrder || a.caption.localeCompare(b.caption));
}
async function queryLiveTabMenuCommands(tabId) {
  if (!tabId) return [];
  try { await browser.tabs.sendMessage(tabId, { type: 'wblock:menu:syncState' }); } catch (_) {}
  return getTabMenuCommands(tabId);
}

async function handleGMXmlhttpRequest(message) {
  try {
    const requestHeaders = message.headers || {};
    if (shouldUseNativeGMXmlhttpRequest(requestHeaders)) {
      return await sendQueuedNativeMessage({
        action: 'gmXmlhttpRequestNative',
        requestId: 'userscript-gmxhr-native-' + Date.now(),
        url: message.url,
        method: message.method || 'GET',
        headers: requestHeaders,
        body: message.body || null,
        anonymous: message.anonymous === true,
        responseType: message.responseType || 'text',
        redirect: message.redirect || 'follow',
        timeout: message.timeout || 0
      }) || { error: 'Empty response from native host' };
    }
    const timeoutMs = Number(message.timeout || 0);
    const abortController = Number.isFinite(timeoutMs) && timeoutMs > 0 ? new AbortController() : null;
    const timeoutId = abortController ? setTimeout(() => abortController.abort(), timeoutMs) : null;
    const method = message.method || 'GET';
    const options = { method, headers: requestHeaders, credentials: message.anonymous ? 'omit' : 'include', redirect: message.redirect || 'follow' };
    if (abortController) options.signal = abortController.signal;
    if (message.body && !['GET', 'HEAD'].includes(method.toUpperCase())) options.body = message.body;
    let fetchResponse;
    try { fetchResponse = await fetch(message.url, options); } finally { if (timeoutId) clearTimeout(timeoutId); }
    return await buildGMResponsePayload(fetchResponse, message.responseType);
  } catch (error) {
    return { error: error && error.message ? error.message : String(error) };
  }
}

async function handleMessages(request, sender) {
  const message = request || {};
  if (message.action === 'wblock:clearCache') { cache.clear(); engineTimestamp = 0; scheduleRegisteredAdvancedRuntimeRefresh('clear_cache'); return { ok: true }; }
  if (message.action === 'wblock:zapper:syncRules') {
    if (typeof message.hostname !== 'string' || !message.hostname) return { ok: false, error: 'Missing hostname', rules: [] };
    try { return await sendQueuedNativeMessage({ action: 'syncZapperRules', hostname: message.hostname, rules: Array.isArray(message.rules) ? message.rules : [] }) || { ok: false, rules: [] }; }
    catch (error) { return { ok: false, error: String(error && error.message ? error.message : error), rules: [] }; }
  }
  if (message.action === 'wblock:zapper:getRules') {
    if (typeof message.hostname !== 'string' || !message.hostname) return { ok: false, error: 'Missing hostname', rules: [] };
    try { return await sendQueuedNativeMessage({ action: 'getZapperRules', hostname: message.hostname }) || { ok: false, rules: [] }; }
    catch (error) { return { ok: false, error: String(error && error.message ? error.message : error), rules: [] }; }
  }
  if (message.action === 'getUserScripts') {
    try {
      const response = await sendQueuedNativeMessage({ action: 'getUserScripts', url: message.url, requestId: message.requestId || ('userscripts-' + Date.now()), includeContent: message.includeContent === true, maxInlineContentBytes: message.maxInlineContentBytes || 0 });
      return { userScripts: response && response.userScripts ? response.userScripts : [], ...(response && response.error ? { error: response.error } : {}) };
    } catch (error) { return { userScripts: [], error: String(error && error.message ? error.message : error) }; }
  }
  if (message.action === 'wblock:userscript:executeMainWorld') {
    const tabId = sender && sender.tab ? sender.tab.id : 0;
    const frameId = sender && typeof sender.frameId === 'number' ? sender.frameId : 0;
    return executeUserScriptInMainWorld(tabId, frameId, message.source || '');
  }
  if (message.action === 'setUserScriptStorageValue' || message.action === 'deleteUserScriptStorageValue') {
    const storageRequest = { action: message.action, requestId: message.requestId || ('userscript-storage-' + Date.now()), scriptId: message.scriptId, key: message.key };
    if (typeof message.rawValue === 'string') storageRequest.rawValue = message.rawValue;
    try { return await sendQueuedNativeMessage(storageRequest) || { ok: false, error: 'Empty response from native host' }; }
    catch (error) { return { ok: false, error: String(error && error.message ? error.message : error) }; }
  }
  if (message.action === 'getUserScriptContentChunk' || message.action === 'getUserScriptResourceChunk') {
    const chunkRequest = { action: message.action, requestId: message.requestId || ('userscript-chunk-' + Date.now()), scriptId: message.scriptId, chunkIndex: message.chunkIndex, chunkSize: message.chunkSize };
    if (typeof message.resourceName === 'string' && message.resourceName) chunkRequest.resourceName = message.resourceName;
    try { return await sendQueuedNativeMessage(chunkRequest) || { error: 'Empty response from native host' }; }
    catch (error) { return { error: String(error && error.message ? error.message : error) }; }
  }
  if (message.action === 'gmXmlhttpRequest') return handleGMXmlhttpRequest(message);
  if (message.action === 'wblock:menu:updateFrameCommands') {
    setFrameMenuCommands(sender && sender.tab ? sender.tab.id : 0, sender && typeof sender.frameId === 'number' ? sender.frameId : 0, message.commands);
    return { ok: true };
  }
  if (message.action === 'wblock:menu:getCommands') {
    const tabId = typeof message.tabId === 'number' ? message.tabId : (sender && sender.tab ? sender.tab.id : 0);
    const commands = await queryLiveTabMenuCommands(tabId);
    return { ok: true, commands };
  }
  if (message.action === 'wblock:menu:invokeCommand') {
    const tabId = typeof message.tabId === 'number' ? message.tabId : (sender && sender.tab ? sender.tab.id : 0);
    const frameId = typeof message.frameId === 'number' ? message.frameId : 0;
    if (!tabId) return { ok: false, error: 'Missing tab' };
    try { return await browser.tabs.sendMessage(tabId, { type: 'wblock:menu:invokeCommand', bridgeId: message.bridgeId, commandId: message.commandId }, { frameId }) || { ok: false, error: 'Empty response from content script' }; }
    catch (error) { return { ok: false, error: String(error && error.message ? error.message : error) }; }
  }

  const tabId = sender && sender.tab ? sender.tab.id : 0;
  const frameId = sender && typeof sender.frameId === 'number' ? sender.frameId : 0;
  let url = sender && sender.url ? sender.url : '';
  const topUrl = frameId === 0 ? undefined : (sender && sender.tab ? sender.tab.url : undefined);
  let blankFrame = false;
  if (!url.startsWith('http') && topUrl) { url = topUrl; blankFrame = true; }
  const configuration = await getConfiguration(message, url, topUrl);
  if (!configuration) return { type: MESSAGE_INIT_CONTENT_SCRIPT };
  if (!blankFrame && tabId) await applyConfiguration(tabId, frameId, configuration);
  return { type: MESSAGE_INIT_CONTENT_SCRIPT, payload: blankFrame ? { ...configuration, scriptlets: [], js: [] } : null };
}

browser.runtime.onMessage.addListener((request, sender) => handleMessages(request, sender));
browser.tabs && browser.tabs.onRemoved && browser.tabs.onRemoved.addListener(tabId => menuCommandsByTab.delete(tabId));
