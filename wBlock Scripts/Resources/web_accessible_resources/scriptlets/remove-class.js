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

  // Scriptlets/src/scriptlets/remove-class.js
  var remove_class_exports = {};
  __export(remove_class_exports, {
    removeClass: () => removeClass,
    removeClassNames: () => removeClassNames
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

  // Scriptlets/src/helpers/parse-flags.ts
  var parseFlags = (flags) => {
    const FLAGS_DIVIDER = " ";
    const ASAP_FLAG = "asap";
    const COMPLETE_FLAG = "complete";
    const STAY_FLAG = "stay";
    const VALID_FLAGS = /* @__PURE__ */ new Set([ASAP_FLAG, COMPLETE_FLAG, STAY_FLAG]);
    const passedFlags = new Set(
      flags.trim().split(FLAGS_DIVIDER).filter((flag) => VALID_FLAGS.has(flag))
    );
    return {
      ASAP: ASAP_FLAG,
      COMPLETE: COMPLETE_FLAG,
      STAY: STAY_FLAG,
      hasFlag: (flag) => passedFlags.has(flag)
    };
  };

  // Scriptlets/src/scriptlets/remove-class.js
  function removeClass(source, classNames, selector, applying = "asap stay") {
    if (!classNames) {
      return;
    }
    classNames = classNames.split(/\s*\|\s*/);
    let selectors = [];
    if (!selector) {
      selectors = classNames.map((className) => {
        return `.${className}`;
      });
    }
    const removeClassHandler = () => {
      const nodes = /* @__PURE__ */ new Set();
      if (selector) {
        let foundNodes = [];
        try {
          foundNodes = [].slice.call(document.querySelectorAll(selector));
        } catch (e) {
          logMessage(source, `Invalid selector arg: '${selector}'`);
        }
        foundNodes.forEach((n) => nodes.add(n));
      } else if (selectors.length > 0) {
        selectors.forEach((s) => {
          const elements = document.querySelectorAll(s);
          for (let i = 0; i < elements.length; i += 1) {
            const element = elements[i];
            nodes.add(element);
          }
        });
      }
      let removed = false;
      nodes.forEach((node) => {
        classNames.forEach((className) => {
          if (node.classList.contains(className)) {
            node.classList.remove(className);
            removed = true;
          }
        });
      });
      if (removed) {
        hit(source);
      }
    };
    const CLASS_ATTR_NAME = ["class"];
    const flags = parseFlags(applying);
    const run = () => {
      removeClassHandler();
      if (!flags.hasFlag(flags.STAY)) {
        return;
      }
      observeDOMChanges(removeClassHandler, true, CLASS_ATTR_NAME);
    };
    if (flags.hasFlag(flags.ASAP)) {
      if (document.readyState === "loading") {
        window.addEventListener("DOMContentLoaded", removeClassHandler, { once: true });
      } else {
        removeClassHandler();
      }
    }
    if (document.readyState !== "complete" && flags.hasFlag(flags.COMPLETE)) {
      window.addEventListener("load", run, { once: true });
    } else if (flags.hasFlag(flags.STAY)) {
      if (!applying.includes(" ")) {
        removeClassHandler();
      }
      observeDOMChanges(removeClassHandler, true, CLASS_ATTR_NAME);
    }
  }
  var removeClassNames = [
    "remove-class",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "remove-class.js",
    "ubo-remove-class.js",
    "rc.js",
    "ubo-rc.js",
    "ubo-remove-class",
    "ubo-rc"
  ];
  removeClass.primaryName = removeClassNames[0];
  removeClass.injections = [
    hit,
    logMessage,
    observeDOMChanges,
    parseFlags,
    // following helpers should be imported and injected
    // because they are used by helpers above
    throttle
  ];
  return __toCommonJS(remove_class_exports);
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
    console.warn("No callable function found for scriptlet module: remove-class");
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
