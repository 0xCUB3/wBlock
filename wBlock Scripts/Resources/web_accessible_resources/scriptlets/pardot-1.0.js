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

  // Scriptlets/src/scriptlets/pardot-1.0.ts
  var pardot_1_0_exports = {};
  __export(pardot_1_0_exports, {
    Pardot: () => Pardot,
    PardotNames: () => PardotNames
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
  var noopNull = () => null;
  var noopStr = () => "";

  // Scriptlets/src/redirects/pardot-1.0.js
  function Pardot(source) {
    window.piVersion = "1.0.2";
    window.piScriptNum = 0;
    window.piScriptObj = [];
    window.checkNamespace = noopFunc;
    window.getPardotUrl = noopStr;
    window.piGetParameter = noopNull;
    window.piSetCookie = noopFunc;
    window.piGetCookie = noopStr;
    function piTracker() {
      window.pi = {
        tracker: {
          visitor_id: "",
          visitor_id_sign: "",
          pi_opt_in: "",
          campaign_id: ""
        }
      };
      window.piScriptNum += 1;
    }
    window.piResponse = noopFunc;
    window.piTracker = piTracker;
    piTracker();
    hit(source);
  }
  var PardotNames = ["pardot-1.0"];
  Pardot.primaryName = PardotNames[0];
  Pardot.injections = [
    hit,
    noopFunc,
    noopStr,
    noopNull
  ];
  return __toCommonJS(pardot_1_0_exports);
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
    console.warn("No callable function found for scriptlet module: pardot-1.0");
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
