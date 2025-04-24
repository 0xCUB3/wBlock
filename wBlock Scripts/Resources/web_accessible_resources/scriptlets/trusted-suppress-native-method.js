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

  // Scriptlets/src/scriptlets/trusted-suppress-native-method.ts
  var trusted_suppress_native_method_exports = {};
  __export(trusted_suppress_native_method_exports, {
    trustedSuppressNativeMethod: () => trustedSuppressNativeMethod,
    trustedSuppressNativeMethodNames: () => trustedSuppressNativeMethodNames
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

  // Scriptlets/src/helpers/object-utils.ts
  var isEmptyObject = (obj) => {
    return Object.keys(obj).length === 0 && !obj.prototype;
  };
  function isArbitraryObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value) && !(value instanceof RegExp);
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
  function getAbortFunc() {
    const rid = randomId();
    let isErrorHandlerSet = false;
    return function abort() {
      if (!isErrorHandlerSet) {
        window.onerror = createOnErrorHandler(rid);
        isErrorHandlerSet = true;
      }
      throw new ReferenceError(rid);
    };
  }

  // Scriptlets/src/helpers/get-error-message.ts
  var getErrorMessage = (error) => {
    const isErrorWithMessage = (e) => typeof e === "object" && e !== null && "message" in e && typeof e.message === "string";
    if (isErrorWithMessage(error)) {
      return error.message;
    }
    try {
      return new Error(JSON.stringify(error)).message;
    } catch {
      return new Error(String(error)).message;
    }
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

  // Scriptlets/src/helpers/value-matchers.ts
  function isValueMatched(value, matcher) {
    if (typeof value === "function") {
      return false;
    }
    if (nativeIsNaN(value)) {
      return nativeIsNaN(matcher);
    }
    if (value === null || typeof value === "undefined" || typeof value === "number" || typeof value === "boolean") {
      return value === matcher;
    }
    if (typeof value === "string") {
      if (typeof matcher === "string" || matcher instanceof RegExp) {
        return isStringMatched(value, matcher);
      }
      return false;
    }
    if (Array.isArray(value) && Array.isArray(matcher)) {
      return isArrayMatched(value, matcher);
    }
    if (isArbitraryObject(value) && isArbitraryObject(matcher)) {
      return isObjectMatched(value, matcher);
    }
    return false;
  }
  function isStringMatched(str, matcher) {
    if (typeof matcher === "string") {
      if (matcher === "") {
        return str === matcher;
      }
      return str.includes(matcher);
    }
    if (matcher instanceof RegExp) {
      return matcher.test(str);
    }
    return false;
  }
  function isObjectMatched(obj, matcher) {
    const matcherKeys = Object.keys(matcher);
    for (let i = 0; i < matcherKeys.length; i += 1) {
      const key = matcherKeys[i];
      const value = obj[key];
      if (!isValueMatched(value, matcher[key])) {
        return false;
      }
      continue;
    }
    return true;
  }
  function isArrayMatched(array, matcher) {
    if (array.length === 0) {
      return matcher.length === 0;
    }
    if (matcher.length === 0) {
      return false;
    }
    for (let i = 0; i < matcher.length; i += 1) {
      const matcherValue = matcher[i];
      const isMatching = array.some((arrItem) => isValueMatched(arrItem, matcherValue));
      if (!isMatching) {
        return false;
      }
      continue;
    }
    return true;
  }

  // Scriptlets/src/scriptlets/trusted-suppress-native-method.ts
  function trustedSuppressNativeMethod(source, methodPath, signatureStr, how = "abort", stack = "") {
    if (!methodPath || !signatureStr) {
      return;
    }
    const IGNORE_ARG_SYMBOL = " ";
    const suppress = how === "abort" ? getAbortFunc() : () => {
    };
    let signatureMatcher;
    try {
      signatureMatcher = signatureStr.split("|").map((value) => {
        return value === IGNORE_ARG_SYMBOL ? value : inferValue(value);
      });
    } catch (e) {
      logMessage(source, `Could not parse the signature matcher: ${getErrorMessage(e)}`);
      return;
    }
    const getPathParts = getPropertyInChain;
    const { base, chain, prop } = getPathParts(window, methodPath);
    if (typeof chain !== "undefined") {
      logMessage(source, `Could not reach the end of the prop chain: ${methodPath}`);
      return;
    }
    const nativeMethod = base[prop];
    if (!nativeMethod || typeof nativeMethod !== "function") {
      logMessage(source, `Could not retrieve the method: ${methodPath}`);
      return;
    }
    function matchMethodCall(nativeArguments, matchArguments) {
      return matchArguments.every((matcher, i) => {
        if (matcher === IGNORE_ARG_SYMBOL) {
          return true;
        }
        const argument = nativeArguments[i];
        return isValueMatched(argument, matcher);
      });
    }
    let isMatchingSuspended = false;
    function apply(target, thisArg, argumentsList) {
      if (isMatchingSuspended) {
        return Reflect.apply(target, thisArg, argumentsList);
      }
      isMatchingSuspended = true;
      if (stack && !matchStackTrace(stack, new Error().stack || "")) {
        isMatchingSuspended = false;
        return Reflect.apply(target, thisArg, argumentsList);
      }
      const isMatching = matchMethodCall(argumentsList, signatureMatcher);
      isMatchingSuspended = false;
      if (isMatching) {
        hit(source);
        return suppress();
      }
      return Reflect.apply(target, thisArg, argumentsList);
    }
    base[prop] = new Proxy(nativeMethod, { apply });
  }
  var trustedSuppressNativeMethodNames = [
    "trusted-suppress-native-method"
  ];
  trustedSuppressNativeMethod.primaryName = trustedSuppressNativeMethodNames[0];
  trustedSuppressNativeMethod.injections = [
    hit,
    logMessage,
    getPropertyInChain,
    inferValue,
    isValueMatched,
    getAbortFunc,
    matchStackTrace,
    getErrorMessage,
    // following helpers should be imported and injected
    // because they are used by helpers above
    shouldAbortInlineOrInjectedScript,
    getNativeRegexpTest,
    toRegExp,
    nativeIsNaN,
    randomId,
    createOnErrorHandler,
    isEmptyObject,
    isArbitraryObject,
    isStringMatched,
    isArrayMatched,
    isObjectMatched,
    backupRegExpValues,
    restoreRegExpValues
  ];
  return __toCommonJS(trusted_suppress_native_method_exports);
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
    console.warn("No callable function found for scriptlet module: trusted-suppress-native-method");
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
