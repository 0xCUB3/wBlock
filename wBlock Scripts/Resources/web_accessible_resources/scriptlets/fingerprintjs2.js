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

  // Scriptlets/src/scriptlets/fingerprintjs2.ts
  var fingerprintjs2_exports = {};
  __export(fingerprintjs2_exports, {
    Fingerprintjs2: () => Fingerprintjs2,
    Fingerprintjs2Names: () => Fingerprintjs2Names
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

  // Scriptlets/src/redirects/fingerprintjs2.js
  function Fingerprintjs2(source) {
    let browserId = "";
    for (let i = 0; i < 8; i += 1) {
      browserId += (Math.random() * 65536 + 4096).toString(16).slice(-4);
    }
    const Fingerprint2 = function() {
    };
    Fingerprint2.get = function(options, callback) {
      if (!callback) {
        callback = options;
      }
      setTimeout(() => {
        if (callback) {
          callback(browserId, []);
        }
      }, 1);
    };
    Fingerprint2.prototype = {
      get: Fingerprint2.get
    };
    window.Fingerprint2 = Fingerprint2;
    hit(source);
  }
  var Fingerprintjs2Names = [
    "fingerprintjs2",
    // redirect aliases are needed for conversion:
    // prefixed for us
    "ubo-fingerprint2.js",
    // original ubo name
    "fingerprint2.js"
  ];
  Fingerprintjs2.primaryName = Fingerprintjs2Names[0];
  Fingerprintjs2.injections = [hit];
  return __toCommonJS(fingerprintjs2_exports);
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
    console.warn("No callable function found for scriptlet module: fingerprintjs2");
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
