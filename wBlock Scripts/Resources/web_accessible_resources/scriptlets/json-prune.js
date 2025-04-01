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

  // Scriptlets/src/scriptlets/json-prune.js
  var json_prune_exports = {};
  __export(json_prune_exports, {
    jsonPrune: () => jsonPrune,
    jsonPruneNames: () => jsonPruneNames
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

  // Scriptlets/src/helpers/prune-utils.ts
  function isPruningNeeded(source, root, prunePaths, requiredPaths, stack, nativeObjects) {
    if (!root) {
      return false;
    }
    const { nativeStringify } = nativeObjects;
    let shouldProcess;
    const prunePathsToCheck = prunePaths.map((obj) => {
      return obj.path;
    });
    const requiredPathsToCheck = requiredPaths.map((obj) => {
      return obj.path;
    });
    if (prunePathsToCheck.length === 0 && requiredPathsToCheck.length > 0) {
      const rootString = nativeStringify(root);
      const matchRegex = toRegExp(requiredPathsToCheck.join(""));
      const shouldLog = matchRegex.test(rootString);
      if (shouldLog) {
        logMessage(
          source,
          `${window.location.hostname}
${nativeStringify(root, null, 2)}
Stack trace:
${new Error().stack}`,
          true
        );
        if (root && typeof root === "object") {
          logMessage(source, root, true, false);
        }
        shouldProcess = false;
        return shouldProcess;
      }
    }
    if (stack && !matchStackTrace(stack, new Error().stack || "")) {
      shouldProcess = false;
      return shouldProcess;
    }
    const wildcardSymbols = [".*.", "*.", ".*", ".[].", "[].", ".[]"];
    for (let i = 0; i < requiredPathsToCheck.length; i += 1) {
      const requiredPath = requiredPathsToCheck[i];
      const lastNestedPropName = requiredPath.split(".").pop();
      const hasWildcard = wildcardSymbols.some((symbol) => requiredPath.includes(symbol));
      const details = getWildcardPropertyInChain(root, requiredPath, hasWildcard);
      if (!details.length) {
        shouldProcess = false;
        return shouldProcess;
      }
      shouldProcess = !hasWildcard;
      for (let j = 0; j < details.length; j += 1) {
        const hasRequiredProp = typeof lastNestedPropName === "string" && details[j].base[lastNestedPropName] !== void 0;
        if (hasWildcard) {
          shouldProcess = hasRequiredProp || shouldProcess;
        } else {
          shouldProcess = hasRequiredProp && shouldProcess;
        }
      }
    }
    return shouldProcess;
  }
  var jsonPruner = (source, root, prunePaths, requiredPaths, stack, nativeObjects) => {
    const { nativeStringify } = nativeObjects;
    if (prunePaths.length === 0 && requiredPaths.length === 0) {
      logMessage(
        source,
        `${window.location.hostname}
${nativeStringify(root, null, 2)}
Stack trace:
${new Error().stack}`,
        true
      );
      if (root && typeof root === "object") {
        logMessage(source, root, true, false);
      }
      return root;
    }
    try {
      if (isPruningNeeded(source, root, prunePaths, requiredPaths, stack, nativeObjects) === false) {
        return root;
      }
      prunePaths.forEach((path) => {
        const pathToCheck = path.path;
        const valueToCheck = path.value;
        const ownerObjArr = getWildcardPropertyInChain(root, pathToCheck, true, [], valueToCheck);
        for (let i = ownerObjArr.length - 1; i >= 0; i -= 1) {
          const ownerObj = ownerObjArr[i];
          if (ownerObj === void 0 || !ownerObj.base) {
            continue;
          }
          hit(source);
          if (!Array.isArray(ownerObj.base)) {
            delete ownerObj.base[ownerObj.prop];
            continue;
          }
          try {
            const index = Number(ownerObj.prop);
            if (Number.isNaN(index)) {
              continue;
            }
            ownerObj.base.splice(index, 1);
          } catch (error) {
            console.error("Error while deleting array element", error);
          }
        }
      });
    } catch (e) {
      logMessage(source, e);
    }
    return root;
  };
  var getPrunePath = (props) => {
    const VALUE_MARKER = ".[=].";
    const REGEXP_START_MARKER = "/";
    const validPropsString = typeof props === "string" && props !== void 0 && props !== "";
    if (validPropsString) {
      const splitRegexp = /(?<!\.\[=\]\.\/(?:[^/]|\\.)*)\s+/;
      const parts = props.split(splitRegexp).map((part) => {
        const splitPart = part.split(VALUE_MARKER);
        const path = splitPart[0];
        let value = splitPart[1];
        if (value !== void 0) {
          if (value === "true") {
            value = true;
          } else if (value === "false") {
            value = false;
          } else if (value.startsWith(REGEXP_START_MARKER)) {
            value = toRegExp(value);
          } else if (typeof value === "string" && /^\d+$/.test(value)) {
            value = parseFloat(value);
          }
          return { path, value };
        }
        return { path };
      });
      return parts;
    }
    return [];
  };

  // Scriptlets/src/scriptlets/json-prune.js
  function jsonPrune(source, propsToRemove, requiredInitialProps, stack = "") {
    const prunePaths = getPrunePath(propsToRemove);
    const requiredPaths = getPrunePath(requiredInitialProps);
    const nativeObjects = {
      nativeStringify: window.JSON.stringify
    };
    const nativeJSONParse = JSON.parse;
    const jsonParseWrapper = (...args) => {
      const root = nativeJSONParse.apply(JSON, args);
      return jsonPruner(source, root, prunePaths, requiredPaths, stack, nativeObjects);
    };
    jsonParseWrapper.toString = nativeJSONParse.toString.bind(nativeJSONParse);
    JSON.parse = jsonParseWrapper;
    const nativeResponseJson = Response.prototype.json;
    const responseJsonWrapper = function() {
      const promise = nativeResponseJson.apply(this);
      return promise.then((obj) => {
        return jsonPruner(source, obj, prunePaths, requiredPaths, stack, nativeObjects);
      });
    };
    if (typeof Response === "undefined") {
      return;
    }
    Response.prototype.json = responseJsonWrapper;
  }
  var jsonPruneNames = [
    "json-prune",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "json-prune.js",
    "ubo-json-prune.js",
    "ubo-json-prune",
    "abp-json-prune"
  ];
  jsonPrune.primaryName = jsonPruneNames[0];
  jsonPrune.injections = [
    hit,
    matchStackTrace,
    getWildcardPropertyInChain,
    logMessage,
    isPruningNeeded,
    jsonPruner,
    getPrunePath,
    // following helpers are needed for helpers above
    toRegExp,
    getNativeRegexpTest,
    shouldAbortInlineOrInjectedScript,
    backupRegExpValues,
    restoreRegExpValues,
    nativeIsNaN,
    isKeyInObject
  ];
  return __toCommonJS(json_prune_exports);
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
    console.warn("No callable function found for scriptlet module: json-prune");
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
