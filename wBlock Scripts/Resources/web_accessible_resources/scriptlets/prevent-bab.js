"use strict";
var main = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // Scriptlets/src/scriptlets/prevent-bab.js
  var prevent_bab_exports = {};
  __export(prevent_bab_exports, {
    preventBab: () => preventBab,
    preventBabNames: () => preventBabNames
  });

  // Scriptlets/src/helpers/hit.ts
  var hit = (source) => {
    const ADGUARD_PREFIX = "[AdGuard]";
    if (!source.verbose) {
      return;
    }
    try {
      const trace = console.trace.bind(console);
      let label = `${ADGUARD_PREFIX} `;
      if (source.engine === "corelibs") {
        label += source.ruleText;
      } else {
        if (source.domainName) {
          label += `${source.domainName}`;
        }
        if (source.args) {
          label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
        } else {
          label += `#%#//scriptlet('${source.name}')`;
        }
      }
      if (trace) {
        trace(label);
      }
    } catch (e) {
    }
    if (typeof window.__debug === "function") {
      window.__debug(source);
    }
  };

  // Scriptlets/src/scriptlets/prevent-bab.js
  function preventBab(source) {
    const nativeSetTimeout = window.setTimeout;
    const babRegex = /\.bab_elementid.$/;
    const timeoutWrapper = (callback, ...args) => {
      if (typeof callback !== "string" || !babRegex.test(callback)) {
        return nativeSetTimeout.apply(window, [callback, ...args]);
      }
      hit(source);
    };
    window.setTimeout = timeoutWrapper;
    const signatures = [
      ["blockadblock"],
      ["babasbm"],
      [/getItem\('babn'\)/],
      [
        "getElementById",
        "String.fromCharCode",
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789",
        "charAt",
        "DOMContentLoaded",
        "AdBlock",
        "addEventListener",
        "doScroll",
        "fromCharCode",
        "<<2|r>>4",
        "sessionStorage",
        "clientWidth",
        "localStorage",
        "Math",
        "random"
      ]
    ];
    const check = (str) => {
      if (typeof str !== "string") {
        return false;
      }
      for (let i = 0; i < signatures.length; i += 1) {
        const tokens = signatures[i];
        let match = 0;
        for (let j = 0; j < tokens.length; j += 1) {
          const token = tokens[j];
          const found = token instanceof RegExp ? token.test(str) : str.includes(token);
          if (found) {
            match += 1;
          }
        }
        if (match / tokens.length >= 0.8) {
          return true;
        }
      }
      return false;
    };
    const nativeEval = window.eval;
    const evalWrapper = (str) => {
      if (!check(str)) {
        return nativeEval(str);
      }
      hit(source);
      const bodyEl = document.body;
      if (bodyEl) {
        bodyEl.style.removeProperty("visibility");
      }
      const el = document.getElementById("babasbmsgx");
      if (el) {
        el.parentNode.removeChild(el);
      }
    };
    window.eval = evalWrapper.bind(window);
    window.eval.toString = nativeEval.toString.bind(nativeEval);
  }
  var preventBabNames = [
    "prevent-bab"
    // there are no aliases for this scriptlet
  ];
  preventBab.primaryName = preventBabNames[0];
  preventBab.injections = [hit];
  return __toCommonJS(prevent_bab_exports);
})();

;(function(){
  window.adguardScriptlets = window.adguardScriptlets || {};
  var fn = null;

  // Unwrap the export from "main"
  if (typeof main === 'function') {
    fn = main;
  } else if (main && typeof main.default === 'function') {
    fn = main.default;
  } else {
    for (var key in main) {
      if (typeof main[key] === 'function') {
        fn = main[key];
        break;
      }
    }
  }

  if (!fn) {
    console.warn("No callable function found for scriptlet module: prevent-bab");
  }

  var aliases = [];
  Object.keys(main).forEach(function(key) {
    if (/Names$/.test(key)) {
      var arr = main[key];
      if (Array.isArray(arr)) {
        aliases = aliases.concat(arr);
      }
    }
  });

  if (aliases.length === 0 && fn && fn.primaryName) {
    aliases.push(fn.primaryName);
  }

  aliases.forEach(function(alias) {
    window.adguardScriptlets[alias] = fn;
  });
})();
