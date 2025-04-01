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

  // Scriptlets/src/scriptlets/log-on-stack-trace.js
  var log_on_stack_trace_exports = {};
  __export(log_on_stack_trace_exports, {
    logOnStackTrace: () => logOnStackTrace,
    logOnStackTraceNames: () => logOnStackTraceNames
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

  // Scriptlets/src/helpers/regexp-utils.ts
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

  // Scriptlets/src/scriptlets/log-on-stack-trace.js
  function logOnStackTrace(source, property) {
    if (!property) {
      return;
    }
    const refineStackTrace = (stackString) => {
      const regExpValues = backupRegExpValues();
      const stackSteps = stackString.split("\n").slice(2).map((line) => line.replace(/ {4}at /, ""));
      const logInfoArray = stackSteps.map((line) => {
        let funcName;
        let funcFullPath;
        const reg = /\(([^\)]+)\)/;
        const regFirefox = /(.*?@)(\S+)(:\d+):\d+\)?$/;
        if (line.match(reg)) {
          funcName = line.split(" ").slice(0, -1).join(" ");
          funcFullPath = line.match(reg)[1];
        } else if (line.match(regFirefox)) {
          funcName = line.split("@").slice(0, -1).join(" ");
          funcFullPath = line.match(regFirefox)[2];
        } else {
          funcName = "function name is not available";
          funcFullPath = line;
        }
        return [funcName, funcFullPath];
      });
      const logInfoObject = {};
      logInfoArray.forEach((pair) => {
        logInfoObject[pair[0]] = pair[1];
      });
      if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
        restoreRegExpValues(regExpValues);
      }
      return logInfoObject;
    };
    const setChainPropAccess = (owner, property2) => {
      const chainInfo = getPropertyInChain(owner, property2);
      let { base } = chainInfo;
      const { prop, chain } = chainInfo;
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
      let value = base[prop];
      setPropertyAccess(base, prop, {
        get() {
          hit(source);
          logMessage(source, `Get ${prop}`, true);
          console.table(refineStackTrace(new Error().stack));
          return value;
        },
        set(newValue) {
          hit(source);
          logMessage(source, `Set ${prop}`, true);
          console.table(refineStackTrace(new Error().stack));
          value = newValue;
        }
      });
    };
    setChainPropAccess(window, property);
  }
  var logOnStackTraceNames = [
    "log-on-stack-trace"
  ];
  logOnStackTrace.primaryName = logOnStackTraceNames[0];
  logOnStackTrace.injections = [
    getPropertyInChain,
    setPropertyAccess,
    hit,
    logMessage,
    isEmptyObject,
    backupRegExpValues,
    restoreRegExpValues
  ];
  return __toCommonJS(log_on_stack_trace_exports);
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
    console.warn("No callable function found for scriptlet module: log-on-stack-trace");
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
