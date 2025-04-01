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

  // Scriptlets/src/scriptlets/fingerprintjs3.ts
  var fingerprintjs3_exports = {};
  __export(fingerprintjs3_exports, {
    Fingerprintjs3: () => Fingerprintjs3,
    Fingerprintjs3Names: () => Fingerprintjs3Names
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
  var noopStr = () => "";

  // Scriptlets/src/redirects/fingerprintjs3.js
  function Fingerprintjs3(source) {
    const visitorId = (() => {
      let id = "";
      for (let i = 0; i < 8; i += 1) {
        id += (Math.random() * 65536 + 4096).toString(16).slice(-4);
      }
      return id;
    })();
    const FingerprintJS = function() {
    };
    FingerprintJS.prototype = {
      load() {
        return Promise.resolve(new FingerprintJS());
      },
      get() {
        return Promise.resolve({
          visitorId
        });
      },
      hashComponents: noopStr
    };
    window.FingerprintJS = new FingerprintJS();
    hit(source);
  }
  var Fingerprintjs3Names = [
    "fingerprintjs3",
    // redirect aliases are needed for conversion:
    // prefixed for us
    "ubo-fingerprint3.js",
    // original ubo name
    "fingerprint3.js"
  ];
  Fingerprintjs3.primaryName = Fingerprintjs3Names[0];
  Fingerprintjs3.injections = [hit, noopStr];
  return __toCommonJS(fingerprintjs3_exports);
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
    console.warn("No callable function found for scriptlet module: fingerprintjs3");
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
