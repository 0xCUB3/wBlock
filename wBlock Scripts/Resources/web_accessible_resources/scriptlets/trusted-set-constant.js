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

  // Scriptlets/src/scriptlets/trusted-set-constant.js
  var trusted_set_constant_exports = {};
  __export(trusted_set_constant_exports, {
    trustedSetConstant: () => trustedSetConstant,
    trustedSetConstantNames: () => trustedSetConstantNames
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

  // Scriptlets/src/helpers/noop-utils.ts
  var noopFunc = () => {
  };
  var noopCallbackFunc = () => noopFunc;
  var trueFunc = () => true;
  var falseFunc = () => false;
  var noopArray = () => [];
  var noopObject = () => ({});
  var throwFunc = () => {
    throw new Error();
  };
  var noopPromiseReject = () => Promise.reject();
  var noopPromiseResolve = (responseBody = "{}", responseUrl = "", responseType = "basic") => {
    if (typeof Response === "undefined") {
      return;
    }
    const response = new Response(responseBody, {
      headers: {
        "Content-Length": `${responseBody.length}`
      },
      status: 200,
      statusText: "OK"
    });
    if (responseType === "opaque") {
      Object.defineProperties(response, {
        body: { value: null },
        status: { value: 0 },
        ok: { value: false },
        statusText: { value: "" },
        url: { value: "" },
        type: { value: responseType }
      });
    } else {
      Object.defineProperties(response, {
        url: { value: responseUrl },
        type: { value: responseType }
      });
    }
    return Promise.resolve(response);
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
  function inferValue(value) {
    if (value === "undefined") {
      return void 0;
    }
    if (value === "false") {
      return false;
    }
    if (value === "true") {
      return true;
    }
    if (value === "null") {
      return null;
    }
    if (value === "NaN") {
      return NaN;
    }
    if (value.startsWith("/") && value.endsWith("/")) {
      return toRegExp(value);
    }
    const MAX_ALLOWED_NUM = 32767;
    const numVal = Number(value);
    if (!nativeIsNaN(numVal)) {
      if (Math.abs(numVal) > MAX_ALLOWED_NUM) {
        throw new Error("number values bigger than 32767 are not allowed");
      }
      return numVal;
    }
    let errorMessage = `'${value}' value type can't be inferred`;
    try {
      const parsableVal = JSON.parse(value);
      if (parsableVal instanceof Object || typeof parsableVal === "string") {
        return parsableVal;
      }
    } catch (e) {
      errorMessage += `: ${e}`;
    }
    throw new TypeError(errorMessage);
  }

  // Scriptlets/src/helpers/script-source-utils.ts
  var shouldAbortInlineOrInjectedScript = (stackMatch, stackTrace) => {
    const INLINE_SCRIPT_STRING = "inlineScript";
    const INJECTED_SCRIPT_STRING = "injectedScript";
    const INJECTED_SCRIPT_MARKER = "<anonymous>";
    const isInlineScript = (match) => match.includes(INLINE_SCRIPT_STRING);
    const isInjectedScript = (match) => match.includes(INJECTED_SCRIPT_STRING);
    if (!(isInlineScript(stackMatch) || isInjectedScript(stackMatch))) {
      return false;
    }
    let documentURL = window.location.href;
    const pos = documentURL.indexOf("#");
    if (pos !== -1) {
      documentURL = documentURL.slice(0, pos);
    }
    const stackSteps = stackTrace.split("\n").slice(2).map((line) => line.trim());
    const stackLines = stackSteps.map((line) => {
      let stack;
      const getStackTraceValues = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(line);
      if (getStackTraceValues) {
        let stackURL = getStackTraceValues[2];
        const stackLine = getStackTraceValues[3];
        const stackCol = getStackTraceValues[4];
        if (stackURL?.startsWith("(")) {
          stackURL = stackURL.slice(1);
        }
        if (stackURL?.startsWith(INJECTED_SCRIPT_MARKER)) {
          stackURL = INJECTED_SCRIPT_STRING;
          let stackFunction = getStackTraceValues[1] !== void 0 ? getStackTraceValues[1].slice(0, -1) : line.slice(0, getStackTraceValues.index).trim();
          if (stackFunction?.startsWith("at")) {
            stackFunction = stackFunction.slice(2).trim();
          }
          stack = `${stackFunction} ${stackURL}${stackLine}${stackCol}`.trim();
        } else if (stackURL === documentURL) {
          stack = `${INLINE_SCRIPT_STRING}${stackLine}${stackCol}`.trim();
        } else {
          stack = `${stackURL}${stackLine}${stackCol}`.trim();
        }
      } else {
        stack = line;
      }
      return stack;
    });
    if (stackLines) {
      for (let index = 0; index < stackLines.length; index += 1) {
        if (isInlineScript(stackMatch) && stackLines[index].startsWith(INLINE_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
          return true;
        }
        if (isInjectedScript(stackMatch) && stackLines[index].startsWith(INJECTED_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
          return true;
        }
      }
    }
    return false;
  };

  // Scriptlets/src/helpers/regexp-utils.ts
  var getNativeRegexpTest = () => {
    const descriptor = Object.getOwnPropertyDescriptor(RegExp.prototype, "test");
    const nativeRegexTest = descriptor?.value;
    if (descriptor && typeof descriptor.value === "function") {
      return nativeRegexTest;
    }
    throw new Error("RegExp.prototype.test is not a function");
  };
  var backupRegExpValues = () => {
    try {
      const arrayOfRegexpValues = [];
      for (let index = 1; index < 10; index += 1) {
        const value = `$${index}`;
        if (!RegExp[value]) {
          break;
        }
        arrayOfRegexpValues.push(RegExp[value]);
      }
      return arrayOfRegexpValues;
    } catch (error) {
      return [];
    }
  };
  var restoreRegExpValues = (array) => {
    if (!array.length) {
      return;
    }
    try {
      let stringPattern = "";
      if (array.length === 1) {
        stringPattern = `(${array[0]})`;
      } else {
        stringPattern = array.reduce((accumulator, currentValue, currentIndex) => {
          if (currentIndex === 1) {
            return `(${accumulator}),(${currentValue})`;
          }
          return `${accumulator},(${currentValue})`;
        });
      }
      const regExpGroup = new RegExp(stringPattern);
      array.toString().replace(regExpGroup, "");
    } catch (error) {
      const message = `Failed to restore RegExp values: ${error}`;
      console.log(message);
    }
  };

  // Scriptlets/src/helpers/match-stack.ts
  var matchStackTrace = (stackMatch, stackTrace) => {
    if (!stackMatch || stackMatch === "") {
      return true;
    }
    const regExpValues = backupRegExpValues();
    if (shouldAbortInlineOrInjectedScript(stackMatch, stackTrace)) {
      if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
        restoreRegExpValues(regExpValues);
      }
      return true;
    }
    const stackRegexp = toRegExp(stackMatch);
    const refinedStackTrace = stackTrace.split("\n").slice(2).map((line) => line.trim()).join("\n");
    if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
      restoreRegExpValues(regExpValues);
    }
    return getNativeRegexpTest().call(stackRegexp, refinedStackTrace);
  };

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

  // Scriptlets/src/scriptlets/trusted-set-constant.js
  function trustedSetConstant(source, property, value, stack) {
    if (!property || !matchStackTrace(stack, new Error().stack)) {
      return;
    }
    let constantValue;
    try {
      constantValue = inferValue(value);
    } catch (e) {
      logMessage(source, e);
      return;
    }
    let canceled = false;
    const mustCancel = (value2) => {
      if (canceled) {
        return canceled;
      }
      canceled = value2 !== void 0 && constantValue !== void 0 && typeof value2 !== typeof constantValue && value2 !== null;
      return canceled;
    };
    const trapProp = (base, prop, configurable, handler) => {
      if (!handler.init(base[prop])) {
        return false;
      }
      const origDescriptor = Object.getOwnPropertyDescriptor(base, prop);
      let prevSetter;
      if (origDescriptor instanceof Object) {
        if (!origDescriptor.configurable) {
          const message = `Property '${prop}' is not configurable`;
          logMessage(source, message);
          return false;
        }
        base[prop] = constantValue;
        if (origDescriptor.set instanceof Function) {
          prevSetter = origDescriptor.set;
        }
      }
      Object.defineProperty(base, prop, {
        configurable,
        get() {
          return handler.get();
        },
        set(a) {
          if (prevSetter !== void 0) {
            prevSetter(a);
          }
          handler.set(a);
        }
      });
      return true;
    };
    const setChainPropAccess = (owner, property2) => {
      const chainInfo = getPropertyInChain(owner, property2);
      const { base } = chainInfo;
      const { prop, chain } = chainInfo;
      const inChainPropHandler = {
        factValue: void 0,
        init(a) {
          this.factValue = a;
          return true;
        },
        get() {
          return this.factValue;
        },
        set(a) {
          if (this.factValue === a) {
            return;
          }
          this.factValue = a;
          if (a instanceof Object) {
            setChainPropAccess(a, chain);
          }
        }
      };
      const endPropHandler = {
        init(a) {
          if (mustCancel(a)) {
            return false;
          }
          return true;
        },
        get() {
          return constantValue;
        },
        set(a) {
          if (!mustCancel(a)) {
            return;
          }
          constantValue = a;
        }
      };
      if (!chain) {
        const isTrapped = trapProp(base, prop, false, endPropHandler);
        if (isTrapped) {
          hit(source);
        }
        return;
      }
      if (base !== void 0 && base[prop] === null) {
        trapProp(base, prop, true, inChainPropHandler);
        return;
      }
      if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
        trapProp(base, prop, true, inChainPropHandler);
      }
      const propValue = owner[prop];
      if (propValue instanceof Object || typeof propValue === "object" && propValue !== null) {
        setChainPropAccess(propValue, chain);
      }
      trapProp(base, prop, true, inChainPropHandler);
    };
    setChainPropAccess(window, property);
  }
  var trustedSetConstantNames = [
    "trusted-set-constant"
    // trusted scriptlets support no aliases
  ];
  trustedSetConstant.primaryName = trustedSetConstantNames[0];
  trustedSetConstant.injections = [
    hit,
    inferValue,
    logMessage,
    noopArray,
    noopObject,
    noopFunc,
    noopCallbackFunc,
    trueFunc,
    falseFunc,
    throwFunc,
    noopPromiseReject,
    noopPromiseResolve,
    getPropertyInChain,
    setPropertyAccess,
    toRegExp,
    matchStackTrace,
    nativeIsNaN,
    isEmptyObject,
    getNativeRegexpTest,
    // following helpers should be imported and injected
    // because they are used by helpers above
    shouldAbortInlineOrInjectedScript,
    backupRegExpValues,
    restoreRegExpValues
  ];
  return __toCommonJS(trusted_set_constant_exports);
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
    console.warn("No callable function found for scriptlet module: trusted-set-constant");
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
