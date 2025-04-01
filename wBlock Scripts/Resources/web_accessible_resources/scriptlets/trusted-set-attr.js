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

  // Scriptlets/src/scriptlets/trusted-set-attr.js
  var trusted_set_attr_exports = {};
  __export(trusted_set_attr_exports, {
    trustedSetAttr: () => trustedSetAttr,
    trustedSetAttrNames: () => trustedSetAttrNames
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

  // Scriptlets/src/helpers/attribute-utils.ts
  var defaultAttributeSetter = (elem, attribute, value) => elem.setAttribute(attribute, value);
  var setAttributeBySelector = (source, selector, attribute, value, attributeSetter = defaultAttributeSetter) => {
    let elements;
    try {
      elements = document.querySelectorAll(selector);
    } catch {
      logMessage(source, `Failed to find elements matching selector "${selector}"`);
      return;
    }
    if (!elements || elements.length === 0) {
      return;
    }
    try {
      elements.forEach((elem) => attributeSetter(elem, attribute, value));
      hit(source);
    } catch {
      logMessage(source, `Failed to set [${attribute}="${value}"] to each of selected elements.`);
    }
  };

  // Scriptlets/src/helpers/throttle.ts
  var throttle = (cb, delay) => {
    let wait = false;
    let savedArgs;
    const wrapper = (...args) => {
      if (wait) {
        savedArgs = args;
        return;
      }
      cb(...args);
      wait = true;
      setTimeout(() => {
        wait = false;
        if (savedArgs) {
          wrapper(...savedArgs);
          savedArgs = null;
        }
      }, delay);
    };
    return wrapper;
  };

  // Scriptlets/src/helpers/observer.ts
  var observeDOMChanges = (callback, observeAttrs = false, attrsToObserve = []) => {
    const THROTTLE_DELAY_MS = 20;
    const observer = new MutationObserver(throttle(callbackWrapper, THROTTLE_DELAY_MS));
    const connect = () => {
      if (attrsToObserve.length > 0) {
        observer.observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: observeAttrs,
          attributeFilter: attrsToObserve
        });
      } else {
        observer.observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: observeAttrs
        });
      }
    };
    const disconnect = () => {
      observer.disconnect();
    };
    function callbackWrapper() {
      disconnect();
      callback();
      connect();
    }
    connect();
  };

  // Scriptlets/src/scriptlets/trusted-set-attr.js
  function trustedSetAttr(source, selector, attr, value = "") {
    if (!selector || !attr) {
      return;
    }
    setAttributeBySelector(source, selector, attr, value);
    observeDOMChanges(() => setAttributeBySelector(source, selector, attr, value), true);
  }
  var trustedSetAttrNames = [
    "trusted-set-attr"
    // trusted scriptlets support no aliases
  ];
  trustedSetAttr.primaryName = trustedSetAttrNames[0];
  trustedSetAttr.injections = [
    setAttributeBySelector,
    observeDOMChanges,
    nativeIsNaN,
    // following helpers should be imported and injected
    // because they are used by helpers above
    defaultAttributeSetter,
    logMessage,
    throttle,
    hit
  ];
  return __toCommonJS(trusted_set_attr_exports);
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
    console.warn("No callable function found for scriptlet module: trusted-set-attr");
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
