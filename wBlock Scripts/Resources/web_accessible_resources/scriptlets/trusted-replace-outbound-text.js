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

  // Scriptlets/src/scriptlets/trusted-replace-outbound-text.ts
  var trusted_replace_outbound_text_exports = {};
  __export(trusted_replace_outbound_text_exports, {
    trustedReplaceOutboundText: () => trustedReplaceOutboundText,
    trustedReplaceOutboundTextNames: () => trustedReplaceOutboundTextNames
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

  // Scriptlets/src/helpers/get-wildcard-property-in-chain.ts
  function isKeyInObject(baseObj, path, valueToCheck) {
    const parts = path.split(".");
    const check = (targetObject, pathSegments) => {
      if (pathSegments.length === 0) {
        if (valueToCheck !== void 0) {
          if (typeof targetObject === "string" && valueToCheck instanceof RegExp) {
            return valueToCheck.test(targetObject);
          }
          return targetObject === valueToCheck;
        }
        return true;
      }
      const current = pathSegments[0];
      const rest = pathSegments.slice(1);
      if (current === "*" || current === "[]") {
        if (Array.isArray(targetObject)) {
          return targetObject.some((item) => check(item, rest));
        }
        if (typeof targetObject === "object" && targetObject !== null) {
          return Object.keys(targetObject).some((key) => check(targetObject[key], rest));
        }
      }
      if (Object.prototype.hasOwnProperty.call(targetObject, current)) {
        return check(targetObject[current], rest);
      }
      return false;
    };
    return check(baseObj, parts);
  }
  function getWildcardPropertyInChain(base, chain, lookThrough = false, output = [], valueToCheck) {
    const pos = chain.indexOf(".");
    if (pos === -1) {
      if (chain === "*" || chain === "[]") {
        for (const key in base) {
          if (Object.prototype.hasOwnProperty.call(base, key)) {
            if (valueToCheck !== void 0) {
              const objectValue = base[key];
              if (typeof objectValue === "string" && valueToCheck instanceof RegExp) {
                if (valueToCheck.test(objectValue)) {
                  output.push({ base, prop: key });
                }
              } else if (objectValue === valueToCheck) {
                output.push({ base, prop: key });
              }
            } else {
              output.push({ base, prop: key });
            }
          }
        }
      } else if (valueToCheck !== void 0) {
        const objectValue = base[chain];
        if (typeof objectValue === "string" && valueToCheck instanceof RegExp) {
          if (valueToCheck.test(objectValue)) {
            output.push({ base, prop: chain });
          }
        } else if (base[chain] === valueToCheck) {
          output.push({ base, prop: chain });
        }
      } else {
        output.push({ base, prop: chain });
      }
      return output;
    }
    const prop = chain.slice(0, pos);
    const shouldLookThrough = prop === "[]" && Array.isArray(base) || prop === "*" && base instanceof Object || prop === "[-]" && Array.isArray(base) || prop === "{-}" && base instanceof Object;
    if (shouldLookThrough) {
      const nextProp = chain.slice(pos + 1);
      const baseKeys = Object.keys(base);
      if (prop === "{-}" || prop === "[-]") {
        const type = Array.isArray(base) ? "array" : "object";
        const shouldRemove = !!(prop === "{-}" && type === "object") || !!(prop === "[-]" && type === "array");
        if (!shouldRemove) {
          return output;
        }
        baseKeys.forEach((key) => {
          const item = base[key];
          if (isKeyInObject(item, nextProp, valueToCheck)) {
            output.push({ base, prop: key });
          }
        });
        return output;
      }
      baseKeys.forEach((key) => {
        const item = base[key];
        getWildcardPropertyInChain(item, nextProp, lookThrough, output, valueToCheck);
      });
    }
    if (Array.isArray(base)) {
      base.forEach((key) => {
        const nextBase2 = key;
        if (nextBase2 !== void 0) {
          getWildcardPropertyInChain(nextBase2, chain, lookThrough, output, valueToCheck);
        }
      });
    }
    const nextBase = base[prop];
    chain = chain.slice(pos + 1);
    if (nextBase !== void 0) {
      getWildcardPropertyInChain(nextBase, chain, lookThrough, output, valueToCheck);
    }
    return output;
  }

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

  // Scriptlets/src/scriptlets/trusted-replace-outbound-text.ts
  function trustedReplaceOutboundText(source, methodPath, textToReplace = "", replacement = "", decodeMethod = "", stack = "", logContent = "") {
    if (!methodPath) {
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
    const isValidBase64 = (str) => {
      try {
        if (str === "") {
          return false;
        }
        const decodedString = atob(str);
        const encodedString = btoa(decodedString);
        const stringWithoutPadding = str.replace(/=+$/, "");
        const encodedStringWithoutPadding = encodedString.replace(/=+$/, "");
        return encodedStringWithoutPadding === stringWithoutPadding;
      } catch (e) {
        return false;
      }
    };
    const decodeAndReplaceContent = (content, pattern, textReplacement, decode, log) => {
      switch (decode) {
        case "base64":
          try {
            if (!isValidBase64(content)) {
              logMessage(source, `Text content is not a valid base64 encoded string: ${content}`);
              return content;
            }
            const decodedContent = atob(content);
            if (log) {
              logMessage(source, `Decoded text content: ${decodedContent}`);
            }
            const modifiedContent = textToReplace ? decodedContent.replace(pattern, textReplacement) : decodedContent;
            if (log) {
              const message = modifiedContent !== decodedContent ? `Modified decoded text content: ${modifiedContent}` : "Decoded text content was not modified";
              logMessage(source, message);
            }
            const encodedContent = btoa(modifiedContent);
            return encodedContent;
          } catch (e) {
            return content;
          }
        default:
          return content.replace(pattern, textReplacement);
      }
    };
    const logOriginalContent = !textToReplace || !!logContent;
    const logModifiedContent = !!logContent;
    const logDecodedContent = !!decodeMethod && !!logContent;
    let isMatchingSuspended = false;
    const objectWrapper = (target, thisArg, argumentsList) => {
      if (isMatchingSuspended) {
        return Reflect.apply(target, thisArg, argumentsList);
      }
      isMatchingSuspended = true;
      hit(source);
      const result = Reflect.apply(target, thisArg, argumentsList);
      if (stack && !matchStackTrace(stack, new Error().stack || "")) {
        return result;
      }
      if (typeof result === "string") {
        if (logOriginalContent) {
          logMessage(source, `Original text content: ${result}`);
        }
        const patternRegexp = toRegExp(textToReplace);
        const modifiedContent = textToReplace || logDecodedContent ? decodeAndReplaceContent(result, patternRegexp, replacement, decodeMethod, logContent) : result;
        if (logModifiedContent) {
          const message = modifiedContent !== result ? `Modified text content: ${modifiedContent}` : "Text content was not modified";
          logMessage(source, message);
        }
        isMatchingSuspended = false;
        return modifiedContent;
      }
      isMatchingSuspended = false;
      logMessage(source, "Content is not a string");
      return result;
    };
    const objectHandler = {
      apply: objectWrapper
    };
    base[prop] = new Proxy(nativeMethod, objectHandler);
  }
  var trustedReplaceOutboundTextNames = [
    "trusted-replace-outbound-text"
    // trusted scriptlets support no aliases
  ];
  trustedReplaceOutboundText.primaryName = trustedReplaceOutboundTextNames[0];
  trustedReplaceOutboundText.injections = [
    hit,
    matchStackTrace,
    getPropertyInChain,
    getWildcardPropertyInChain,
    logMessage,
    // following helpers are needed for helpers above
    shouldAbortInlineOrInjectedScript,
    getNativeRegexpTest,
    toRegExp,
    isEmptyObject,
    backupRegExpValues,
    restoreRegExpValues,
    isKeyInObject
  ];
  return __toCommonJS(trusted_replace_outbound_text_exports);
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
    console.warn("No callable function found for scriptlet module: trusted-replace-outbound-text");
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
