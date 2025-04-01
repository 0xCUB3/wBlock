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

  // Scriptlets/src/scriptlets/trusted-set-local-storage-item.js
  var trusted_set_local_storage_item_exports = {};
  __export(trusted_set_local_storage_item_exports, {
    trustedSetLocalStorageItem: () => trustedSetLocalStorageItem,
    trustedSetLocalStorageItemNames: () => trustedSetLocalStorageItemNames
  });

  // Scriptlets/src/helpers/number-utils.ts
  var nativeIsNaN = (num) => {
    const native = Number.isNaN || window.isNaN;
    return native(num);
  };

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

  // Scriptlets/src/helpers/storage-utils.ts
  var setStorageItem = (source, storage, key, value) => {
    try {
      storage.setItem(key, value);
    } catch (e) {
      const message = `Unable to set storage item due to: ${e.message}`;
      logMessage(source, message);
    }
  };

  // Scriptlets/src/helpers/parse-keyword-value.ts
  var parseKeywordValue = (rawValue) => {
    const NOW_VALUE_KEYWORD = "$now$";
    const CURRENT_DATE_KEYWORD = "$currentDate$";
    const CURRENT_ISO_DATE_KEYWORD = "$currentISODate$";
    let parsedValue = rawValue;
    if (rawValue === NOW_VALUE_KEYWORD) {
      parsedValue = Date.now().toString();
    } else if (rawValue === CURRENT_DATE_KEYWORD) {
      parsedValue = Date();
    } else if (rawValue === CURRENT_ISO_DATE_KEYWORD) {
      parsedValue = (/* @__PURE__ */ new Date()).toISOString();
    }
    return parsedValue;
  };

  // Scriptlets/src/scriptlets/trusted-set-local-storage-item.js
  function trustedSetLocalStorageItem(source, key, value) {
    if (typeof key === "undefined") {
      logMessage(source, "Item key should be specified");
      return;
    }
    if (typeof value === "undefined") {
      logMessage(source, "Item value should be specified");
      return;
    }
    const parsedValue = parseKeywordValue(value);
    const { localStorage } = window;
    setStorageItem(source, localStorage, key, parsedValue);
    hit(source);
  }
  var trustedSetLocalStorageItemNames = [
    "trusted-set-local-storage-item"
    // trusted scriptlets support no aliases
  ];
  trustedSetLocalStorageItem.primaryName = trustedSetLocalStorageItemNames[0];
  trustedSetLocalStorageItem.injections = [
    hit,
    logMessage,
    nativeIsNaN,
    setStorageItem,
    parseKeywordValue
  ];
  return __toCommonJS(trusted_set_local_storage_item_exports);
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
    console.warn("No callable function found for scriptlet module: trusted-set-local-storage-item");
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
