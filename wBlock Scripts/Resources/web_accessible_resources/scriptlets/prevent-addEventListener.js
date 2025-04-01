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

  // Scriptlets/src/scriptlets/prevent-addEventListener.js
  var prevent_addEventListener_exports = {};
  __export(prevent_addEventListener_exports, {
    preventAddEventListener: () => preventAddEventListener,
    preventAddEventListenerNames: () => preventAddEventListenerNames
  });

  // Scriptlets/src/helpers/add-event-listener-utils.ts
  var validateType = (type) => {
    return typeof type !== "undefined";
  };
  var validateListener = (listener) => {
    return typeof listener !== "undefined" && (typeof listener === "function" || typeof listener === "object" && listener !== null && "handleEvent" in listener && typeof listener.handleEvent === "function");
  };
  var listenerToString = (listener) => {
    return typeof listener === "function" ? listener.toString() : listener.handleEvent.toString();
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

  // Scriptlets/src/scriptlets/prevent-addEventListener.js
  function preventAddEventListener(source, typeSearch, listenerSearch, additionalArgName, additionalArgValue) {
    const typeSearchRegexp = toRegExp(typeSearch);
    const listenerSearchRegexp = toRegExp(listenerSearch);
    let elementToMatch;
    if (additionalArgName) {
      if (additionalArgName !== "elements") {
        logMessage(source, `Invalid "additionalArgName": ${additionalArgName}
Only "elements" is supported.`);
        return;
      }
      if (!additionalArgValue) {
        logMessage(source, '"additionalArgValue" is required.');
        return;
      }
      elementToMatch = additionalArgValue;
    }
    const elementMatches = (element) => {
      if (elementToMatch === void 0) {
        return true;
      }
      if (elementToMatch === "window") {
        return element === window;
      }
      if (elementToMatch === "document") {
        return element === document;
      }
      if (element && element.matches && element.matches(elementToMatch)) {
        return true;
      }
      return false;
    };
    const nativeAddEventListener = window.EventTarget.prototype.addEventListener;
    function addEventListenerWrapper(type, listener, ...args) {
      let shouldPrevent = false;
      if (validateType(type) && validateListener(listener)) {
        shouldPrevent = typeSearchRegexp.test(type.toString()) && listenerSearchRegexp.test(listenerToString(listener)) && elementMatches(this);
      }
      if (shouldPrevent) {
        hit(source);
        return void 0;
      }
      let context = this;
      if (this && this.constructor?.name === "Window" && this !== window) {
        context = window;
      }
      return nativeAddEventListener.apply(context, [type, listener, ...args]);
    }
    const descriptor = {
      configurable: true,
      set: () => {
      },
      get: () => addEventListenerWrapper
    };
    Object.defineProperty(window.EventTarget.prototype, "addEventListener", descriptor);
    Object.defineProperty(window, "addEventListener", descriptor);
    Object.defineProperty(document, "addEventListener", descriptor);
  }
  var preventAddEventListenerNames = [
    "prevent-addEventListener",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "addEventListener-defuser.js",
    "ubo-addEventListener-defuser.js",
    "aeld.js",
    "ubo-aeld.js",
    "ubo-addEventListener-defuser",
    "ubo-aeld",
    "abp-prevent-listener"
  ];
  preventAddEventListener.primaryName = preventAddEventListenerNames[0];
  preventAddEventListener.injections = [
    hit,
    toRegExp,
    validateType,
    validateListener,
    listenerToString,
    logMessage
  ];
  return __toCommonJS(prevent_addEventListener_exports);
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
    console.warn("No callable function found for scriptlet module: prevent-addEventListener");
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
