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

  // Scriptlets/src/scriptlets/set-local-storage-item.js
  var set_local_storage_item_exports = {};
  __export(set_local_storage_item_exports, {
    setLocalStorageItem: () => setLocalStorageItem,
    setLocalStorageItemNames: () => setLocalStorageItemNames
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

  // Scriptlets/src/helpers/string-utils.ts
  var escapeRegExp = (str) => str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  var toRegExp = (rawInput) => {
    const input = rawInput || "";
    const DEFAULT_VALUE = ".?";
    const FORWARD_SLASH = "/";
    if (input === "") {
      return new RegExp(DEFAULT_VALUE);
    }
    const delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
    const flagsPart = input.substring(delimiterIndex + 1);
    const regExpPart = input.substring(0, delimiterIndex + 1);
    const isValidRegExpFlag = (flag) => {
      if (!flag) {
        return false;
      }
      try {
        new RegExp("", flag);
        return true;
      } catch (ex) {
        return false;
      }
    };
    const getRegExpFlags = (regExpStr, flagsStr) => {
      if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
        return flagsStr;
      }
      return "";
    };
    const flags = getRegExpFlags(regExpPart, flagsPart);
    if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
      const regExpInput = flags ? regExpPart : input;
      return new RegExp(regExpInput.slice(1, -1), flags);
    }
    const escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return new RegExp(escaped);
  };
  var isValidStrPattern = (input) => {
    const FORWARD_SLASH = "/";
    let str = escapeRegExp(input);
    if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
      str = input.slice(1, -1);
    }
    let isValid;
    try {
      isValid = new RegExp(str);
      isValid = true;
    } catch (e) {
      isValid = false;
    }
    return isValid;
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
  var removeStorageItem = (source, storage, key) => {
    try {
      if (key.startsWith("/") && (key.endsWith("/") || key.endsWith("/i")) && isValidStrPattern(key)) {
        const regExpKey = toRegExp(key);
        const storageKeys = Object.keys(storage);
        storageKeys.forEach((storageKey) => {
          if (regExpKey.test(storageKey)) {
            storage.removeItem(storageKey);
          }
        });
      } else {
        storage.removeItem(key);
      }
    } catch (e) {
      const message = `Unable to remove storage item due to: ${e.message}`;
      logMessage(source, message);
    }
  };
  var getLimitedStorageItemValue = (value) => {
    if (typeof value !== "string") {
      throw new Error("Invalid value");
    }
    const allowedStorageValues = /* @__PURE__ */ new Set([
      "undefined",
      "false",
      "true",
      "null",
      "",
      "yes",
      "no",
      "on",
      "off",
      "accept",
      "accepted",
      "reject",
      "rejected",
      "allowed",
      "denied",
      "forbidden",
      "forever"
    ]);
    let validValue;
    if (allowedStorageValues.has(value.toLowerCase())) {
      validValue = value;
    } else if (value === "emptyArr") {
      validValue = "[]";
    } else if (value === "emptyObj") {
      validValue = "{}";
    } else if (/^\d+$/.test(value)) {
      validValue = parseFloat(value);
      if (nativeIsNaN(validValue)) {
        throw new Error("Invalid value");
      }
      if (Math.abs(validValue) > 32767) {
        throw new Error("Invalid value");
      }
    } else if (value === "$remove$") {
      validValue = "$remove$";
    } else {
      throw new Error("Invalid value");
    }
    return validValue;
  };

  // Scriptlets/src/scriptlets/set-local-storage-item.js
  function setLocalStorageItem(source, key, value) {
    if (typeof key === "undefined") {
      logMessage(source, "Item key should be specified.");
      return;
    }
    let validValue;
    try {
      validValue = getLimitedStorageItemValue(value);
    } catch {
      logMessage(source, `Invalid storage item value: '${value}'`);
      return;
    }
    const { localStorage } = window;
    if (validValue === "$remove$") {
      removeStorageItem(source, localStorage, key);
    } else {
      setStorageItem(source, localStorage, key, validValue);
    }
    hit(source);
  }
  var setLocalStorageItemNames = [
    "set-local-storage-item",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "set-local-storage-item.js",
    "ubo-set-local-storage-item.js",
    "ubo-set-local-storage-item"
  ];
  setLocalStorageItem.primaryName = setLocalStorageItemNames[0];
  setLocalStorageItem.injections = [
    hit,
    logMessage,
    nativeIsNaN,
    setStorageItem,
    removeStorageItem,
    getLimitedStorageItemValue,
    // following helpers are needed for helpers above
    isValidStrPattern,
    toRegExp,
    escapeRegExp
  ];
  return __toCommonJS(set_local_storage_item_exports);
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
    console.warn("No callable function found for scriptlet module: set-local-storage-item");
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
