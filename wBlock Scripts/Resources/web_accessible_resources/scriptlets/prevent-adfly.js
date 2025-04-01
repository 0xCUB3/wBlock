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

  // Scriptlets/src/scriptlets/prevent-adfly.js
  var prevent_adfly_exports = {};
  __export(prevent_adfly_exports, {
    preventAdfly: () => preventAdfly,
    preventAdflyNames: () => preventAdflyNames
  });

  // Scriptlets/src/helpers/log-message.ts
  var logMessage = (source, message, forced = false, convertMessageToString = true) => {
    const {
      name,
      verbose
    } = source;
    if (!forced && !verbose) {
      return;
    }
    const nativeConsole = console.log;
    if (!convertMessageToString) {
      nativeConsole(`${name}:`, message);
      return;
    }
    nativeConsole(`${name}: ${message}`);
  };

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

  // Scriptlets/src/helpers/object-utils.ts
  function setPropertyAccess(object, property, descriptor) {
    const currentDescriptor = Object.getOwnPropertyDescriptor(object, property);
    if (currentDescriptor && !currentDescriptor.configurable) {
      return false;
    }
    Object.defineProperty(object, property, descriptor);
    return true;
  }

  // Scriptlets/src/scriptlets/prevent-adfly.js
  function preventAdfly(source) {
    const isDigit = (data) => /^\d$/.test(data);
    const handler = function(encodedURL) {
      let evenChars = "";
      let oddChars = "";
      for (let i = 0; i < encodedURL.length; i += 1) {
        if (i % 2 === 0) {
          evenChars += encodedURL.charAt(i);
        } else {
          oddChars = encodedURL.charAt(i) + oddChars;
        }
      }
      let data = (evenChars + oddChars).split("");
      for (let i = 0; i < data.length; i += 1) {
        if (isDigit(data[i])) {
          for (let ii = i + 1; ii < data.length; ii += 1) {
            if (isDigit(data[ii])) {
              const temp = parseInt(data[i], 10) ^ parseInt(data[ii], 10);
              if (temp < 10) {
                data[i] = temp.toString();
              }
              i = ii;
              break;
            }
          }
        }
      }
      data = data.join("");
      const decodedURL = window.atob(data).slice(16, -16);
      if (window.stop) {
        window.stop();
      }
      window.onbeforeunload = null;
      window.location.href = decodedURL;
    };
    let val;
    let applyHandler = true;
    const result = setPropertyAccess(window, "ysmm", {
      configurable: false,
      set: (value) => {
        if (applyHandler) {
          applyHandler = false;
          try {
            if (typeof value === "string") {
              handler(value);
            }
          } catch (err) {
          }
        }
        val = value;
      },
      get: () => val
    });
    if (result) {
      hit(source);
    } else {
      logMessage(source, "Failed to set up prevent-adfly scriptlet");
    }
  }
  var preventAdflyNames = [
    "prevent-adfly"
    // there are no aliases for this scriptlet
  ];
  preventAdfly.primaryName = preventAdflyNames[0];
  preventAdfly.injections = [
    setPropertyAccess,
    hit,
    logMessage
  ];
  return __toCommonJS(prevent_adfly_exports);
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
    console.warn("No callable function found for scriptlet module: prevent-adfly");
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
