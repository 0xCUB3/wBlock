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

  // Scriptlets/src/scriptlets/abort-current-inline-script.js
  var abort_current_inline_script_exports = {};
  __export(abort_current_inline_script_exports, {
    abortCurrentInlineScript: () => abortCurrentInlineScript,
    abortCurrentInlineScriptNames: () => abortCurrentInlineScriptNames
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

  // Scriptlets/src/helpers/get-descriptor-addon.ts
  function getDescriptorAddon() {
    return {
      isAbortingSuspended: false,
      isolateCallback(cb, ...args) {
        this.isAbortingSuspended = true;
        try {
          const result = cb(...args);
          this.isAbortingSuspended = false;
          return result;
        } catch {
          const rid = randomId();
          this.isAbortingSuspended = false;
          throw new ReferenceError(rid);
        }
      }
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

  // Scriptlets/src/scriptlets/abort-current-inline-script.js
  function abortCurrentInlineScript(source, property, search) {
    const searchRegexp = toRegExp(search);
    const rid = randomId();
    const SRC_DATA_MARKER = "data:text/javascript;base64,";
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
      if (content.length === 0 && typeof scriptEl.src !== "undefined" && scriptEl.src?.startsWith(SRC_DATA_MARKER)) {
        const encodedContent = scriptEl.src.slice(SRC_DATA_MARKER.length);
        content = window.atob(encodedContent);
      }
      if (scriptEl instanceof HTMLScriptElement && content.length > 0 && scriptEl !== ourScript && searchRegexp.test(content)) {
        hit(source);
        throw new ReferenceError(rid);
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
        logMessage(source, message);
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
      let origDescriptor = Object.getOwnPropertyDescriptor(base, prop);
      if (origDescriptor instanceof Object === false || origDescriptor.get instanceof Function === false) {
        currentValue = base[prop];
        origDescriptor = void 0;
      }
      const descriptorWrapper = Object.assign(getDescriptorAddon(), {
        currentValue,
        get() {
          if (!this.isAbortingSuspended) {
            this.isolateCallback(abort);
          }
          if (origDescriptor instanceof Object) {
            return origDescriptor.get.call(base);
          }
          return this.currentValue;
        },
        set(newValue) {
          if (!this.isAbortingSuspended) {
            this.isolateCallback(abort);
          }
          if (origDescriptor instanceof Object) {
            origDescriptor.set.call(base, newValue);
          } else {
            this.currentValue = newValue;
          }
        }
      });
      setPropertyAccess(base, prop, {
        // Call wrapped getter and setter to keep isAbortingSuspended & isolateCallback values
        get() {
          return descriptorWrapper.get.call(descriptorWrapper);
        },
        set(newValue) {
          descriptorWrapper.set.call(descriptorWrapper, newValue);
        }
      });
    };
    setChainPropAccess(window, property);
    window.onerror = createOnErrorHandler(rid).bind();
  }
  var abortCurrentInlineScriptNames = [
    "abort-current-inline-script",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "abort-current-script.js",
    "ubo-abort-current-script.js",
    "acs.js",
    "ubo-acs.js",
    // "ubo"-aliases with no "js"-ending
    "ubo-abort-current-script",
    "ubo-acs",
    // obsolete but supported aliases
    "abort-current-inline-script.js",
    "ubo-abort-current-inline-script.js",
    "acis.js",
    "ubo-acis.js",
    "ubo-abort-current-inline-script",
    "ubo-acis",
    "abp-abort-current-inline-script"
  ];
  abortCurrentInlineScript.primaryName = abortCurrentInlineScriptNames[0];
  abortCurrentInlineScript.injections = [
    randomId,
    setPropertyAccess,
    getPropertyInChain,
    toRegExp,
    createOnErrorHandler,
    hit,
    logMessage,
    isEmptyObject,
    getDescriptorAddon
  ];
  return __toCommonJS(abort_current_inline_script_exports);
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
    console.warn("No callable function found for scriptlet module: abort-current-inline-script");
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
