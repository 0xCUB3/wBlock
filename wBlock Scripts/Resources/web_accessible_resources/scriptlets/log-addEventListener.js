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

  // Scriptlets/src/scriptlets/log-addEventListener.js
  var log_addEventListener_exports = {};
  __export(log_addEventListener_exports, {
    logAddEventListener: () => logAddEventListener,
    logAddEventListenerNames: () => logAddEventListenerNames
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

  // Scriptlets/src/helpers/attribute-utils.ts
  var getElementAttributesWithValues = (element) => {
    if (!element || !(element instanceof Element) || !element.attributes || !element.nodeName) {
      return "";
    }
    const attributes = element.attributes;
    const nodeName = element.nodeName.toLowerCase();
    let result = nodeName;
    for (let i = 0; i < attributes.length; i += 1) {
      const attr = attributes[i];
      result += `[${attr.name}="${attr.value}"]`;
    }
    return result;
  };

  // Scriptlets/src/helpers/object-utils.ts
  var isEmptyObject = (obj) => {
    return Object.keys(obj).length === 0 && !obj.prototype;
  };

  // Scriptlets/src/helpers/string-utils.ts
  function objectToString(obj) {
    if (!obj || typeof obj !== "object") {
      return String(obj);
    }
    if (isEmptyObject(obj)) {
      return "{}";
    }
    return Object.entries(obj).map((pair) => {
      const key = pair[0];
      const value = pair[1];
      let recordValueStr = value;
      if (value instanceof Object) {
        recordValueStr = `{ ${objectToString(value)} }`;
      }
      return `${key}:"${recordValueStr}"`;
    }).join(" ");
  }
  var convertTypeToString = (value) => {
    let output;
    if (typeof value === "undefined") {
      output = "undefined";
    } else if (typeof value === "object") {
      if (value === null) {
        output = "null";
      } else {
        output = objectToString(value);
      }
    } else {
      output = String(value);
    }
    return output;
  };

  // Scriptlets/src/scriptlets/log-addEventListener.js
  function logAddEventListener(source) {
    const nativeAddEventListener = window.EventTarget.prototype.addEventListener;
    function addEventListenerWrapper(type, listener, ...args) {
      if (validateType(type) && validateListener(listener)) {
        let targetElement;
        let targetElementInfo;
        const listenerInfo = listenerToString(listener);
        if (this) {
          if (this instanceof Window) {
            targetElementInfo = "window";
          } else if (this instanceof Document) {
            targetElementInfo = "document";
          } else if (this instanceof Element) {
            targetElement = this;
            targetElementInfo = getElementAttributesWithValues(this);
          }
        }
        if (targetElementInfo) {
          const message = `addEventListener("${type}", ${listenerInfo})
Element: ${targetElementInfo}`;
          logMessage(source, message, true);
          if (targetElement) {
            console.log("log-addEventListener Element:", targetElement);
          }
        } else {
          const message = `addEventListener("${type}", ${listenerInfo})`;
          logMessage(source, message, true);
        }
        hit(source);
      } else {
        const message = `Invalid event type or listener passed to addEventListener:
        type: ${convertTypeToString(type)}
        listener: ${convertTypeToString(listener)}`;
        logMessage(source, message, true);
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
  var logAddEventListenerNames = [
    "log-addEventListener",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "addEventListener-logger.js",
    "ubo-addEventListener-logger.js",
    "aell.js",
    "ubo-aell.js",
    "ubo-addEventListener-logger",
    "ubo-aell"
  ];
  logAddEventListener.primaryName = logAddEventListenerNames[0];
  logAddEventListener.injections = [
    hit,
    validateType,
    validateListener,
    listenerToString,
    convertTypeToString,
    logMessage,
    objectToString,
    isEmptyObject,
    getElementAttributesWithValues
  ];
  return __toCommonJS(log_addEventListener_exports);
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
    console.warn("No callable function found for scriptlet module: log-addEventListener");
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
