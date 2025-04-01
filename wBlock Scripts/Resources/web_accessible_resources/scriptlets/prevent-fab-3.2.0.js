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

  // Scriptlets/src/scriptlets/prevent-fab-3.2.0.js
  var prevent_fab_3_2_0_exports = {};
  __export(prevent_fab_3_2_0_exports, {
    preventFab: () => preventFab,
    preventFabNames: () => preventFabNames
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

  // Scriptlets/src/helpers/noop-utils.ts
  var noopFunc = () => {
  };
  function noopThis() {
    return this;
  }

  // Scriptlets/src/scriptlets/prevent-fab-3.2.0.js
  function preventFab(source) {
    hit(source);
    const Fab = function() {
    };
    Fab.prototype.check = noopFunc;
    Fab.prototype.clearEvent = noopFunc;
    Fab.prototype.emitEvent = noopFunc;
    Fab.prototype.on = function(a, b) {
      if (!a) {
        b();
      }
      return this;
    };
    Fab.prototype.onDetected = noopThis;
    Fab.prototype.onNotDetected = function(a) {
      a();
      return this;
    };
    Fab.prototype.setOption = noopFunc;
    Fab.prototype.options = {
      set: noopFunc,
      get: noopFunc
    };
    const fab = new Fab();
    const getSetFab = {
      get() {
        return Fab;
      },
      set() {
      }
    };
    const getsetfab = {
      get() {
        return fab;
      },
      set() {
      }
    };
    if (Object.prototype.hasOwnProperty.call(window, "FuckAdBlock")) {
      window.FuckAdBlock = Fab;
    } else {
      Object.defineProperty(window, "FuckAdBlock", getSetFab);
    }
    if (Object.prototype.hasOwnProperty.call(window, "BlockAdBlock")) {
      window.BlockAdBlock = Fab;
    } else {
      Object.defineProperty(window, "BlockAdBlock", getSetFab);
    }
    if (Object.prototype.hasOwnProperty.call(window, "SniffAdBlock")) {
      window.SniffAdBlock = Fab;
    } else {
      Object.defineProperty(window, "SniffAdBlock", getSetFab);
    }
    if (Object.prototype.hasOwnProperty.call(window, "fuckAdBlock")) {
      window.fuckAdBlock = fab;
    } else {
      Object.defineProperty(window, "fuckAdBlock", getsetfab);
    }
    if (Object.prototype.hasOwnProperty.call(window, "blockAdBlock")) {
      window.blockAdBlock = fab;
    } else {
      Object.defineProperty(window, "blockAdBlock", getsetfab);
    }
    if (Object.prototype.hasOwnProperty.call(window, "sniffAdBlock")) {
      window.sniffAdBlock = fab;
    } else {
      Object.defineProperty(window, "sniffAdBlock", getsetfab);
    }
  }
  var preventFabNames = [
    "prevent-fab-3.2.0",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "nofab.js",
    "ubo-nofab.js",
    "fuckadblock.js-3.2.0",
    "ubo-fuckadblock.js-3.2.0",
    "ubo-nofab"
  ];
  preventFab.primaryName = preventFabNames[0];
  preventFab.injections = [hit, noopFunc, noopThis];
  return __toCommonJS(prevent_fab_3_2_0_exports);
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
    console.warn("No callable function found for scriptlet module: prevent-fab-3.2.0");
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
