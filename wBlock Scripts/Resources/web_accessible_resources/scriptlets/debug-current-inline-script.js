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

  // Scriptlets/src/scriptlets/debug-current-inline-script.js
  var debug_current_inline_script_exports = {};
  __export(debug_current_inline_script_exports, {
    debugCurrentInlineScript: () => debugCurrentInlineScript,
    debugCurrentInlineScriptNames: () => debugCurrentInlineScriptNames
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
  var isEmptyObject = (obj) => {
    return Object.keys(obj).length === 0 && !obj.prototype;
  };
  function setPropertyAccess(object, property, descriptor) {
    const currentDescriptor = Object.getOwnPropertyDescriptor(object, property);
    if (currentDescriptor && !currentDescriptor.configurable) {
      return false;
    }
    Object.defineProperty(object, property, descriptor);
    return true;
  }

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

  // Scriptlets/src/helpers/random-id.ts
  function randomId() {
    return Math.random().toString(36).slice(2, 9);
  }

  // Scriptlets/src/helpers/create-on-error-handler.ts
  function createOnErrorHandler(rid) {
    const nativeOnError = window.onerror;
    return function onError(error, ...args) {
      if (typeof error === "string" && error.includes(rid)) {
        return true;
      }
      if (nativeOnError instanceof Function) {
        return nativeOnError.apply(window, [error, ...args]);
      }
      return false;
    };
  }

  // Scriptlets/src/helpers/get-property-in-chain.ts
  function getPropertyInChain(base, chain) {
    const pos = chain.indexOf(".");
    if (pos === -1) {
      return { base, prop: chain };
    }
    const prop = chain.slice(0, pos);
    if (base === null) {
      return { base, prop, chain };
    }
    const nextBase = base[prop];
    chain = chain.slice(pos + 1);
    if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
      return { base, prop, chain };
    }
    if (nextBase === null) {
      return { base, prop, chain };
    }
    if (nextBase !== void 0) {
      return getPropertyInChain(nextBase, chain);
    }
    Object.defineProperty(base, prop, { configurable: true });
    return { base, prop, chain };
  }

  // Scriptlets/src/scriptlets/debug-current-inline-script.js
  function debugCurrentInlineScript(source, property, search) {
    const searchRegexp = toRegExp(search);
    const rid = randomId();
    const getCurrentScript = () => {
      if ("currentScript" in document) {
        return document.currentScript;
      }
      const scripts = document.getElementsByTagName("script");
      return scripts[scripts.length - 1];
    };
    const ourScript = getCurrentScript();
    const abort = () => {
      const scriptEl = getCurrentScript();
      if (!scriptEl) {
        return;
      }
      let content = scriptEl.textContent;
      try {
        const textContentGetter = Object.getOwnPropertyDescriptor(Node.prototype, "textContent").get;
        content = textContentGetter.call(scriptEl);
      } catch (e) {
      }
      if (scriptEl instanceof HTMLScriptElement && content.length > 0 && scriptEl !== ourScript && searchRegexp.test(content)) {
        hit(source);
        debugger;
      }
    };
    const setChainPropAccess = (owner, property2) => {
      const chainInfo = getPropertyInChain(owner, property2);
      let { base } = chainInfo;
      const { prop, chain } = chainInfo;
      if (base instanceof Object === false && base === null) {
        const props = property2.split(".");
        const propIndex = props.indexOf(prop);
        const baseName = props[propIndex - 1];
        const message = `The scriptlet had been executed before the ${baseName} was loaded.`;
        logMessage(message, source.verbose);
        return;
      }
      if (chain) {
        const setter = (a) => {
          base = a;
          if (a instanceof Object) {
            setChainPropAccess(a, chain);
          }
        };
        Object.defineProperty(owner, prop, {
          get: () => base,
          set: setter
        });
        return;
      }
      let currentValue = base[prop];
      setPropertyAccess(base, prop, {
        set: (value) => {
          abort();
          currentValue = value;
        },
        get: () => {
          abort();
          return currentValue;
        }
      });
    };
    setChainPropAccess(window, property);
    window.onerror = createOnErrorHandler(rid).bind();
  }
  var debugCurrentInlineScriptNames = [
    "debug-current-inline-script"
  ];
  debugCurrentInlineScript.primaryName = debugCurrentInlineScriptNames[0];
  debugCurrentInlineScript.injections = [
    randomId,
    setPropertyAccess,
    getPropertyInChain,
    toRegExp,
    createOnErrorHandler,
    hit,
    logMessage,
    isEmptyObject
  ];
  return __toCommonJS(debug_current_inline_script_exports);
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
    console.warn("No callable function found for scriptlet module: debug-current-inline-script");
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
