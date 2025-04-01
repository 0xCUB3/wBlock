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

  // Scriptlets/src/scriptlets/prevent-xhr.js
  var prevent_xhr_exports = {};
  __export(prevent_xhr_exports, {
    preventXHR: () => preventXHR,
    preventXHRNames: () => preventXHRNames
  });

  // Scriptlets/src/helpers/number-utils.ts
  var nativeIsNaN = (num) => {
    const native = Number.isNaN || window.isNaN;
    return native(num);
  };
  var nativeIsFinite = (num) => {
    const native = Number.isFinite || window.isFinite;
    return native(num);
  };
  var getNumberFromString = (rawString) => {
    const parsedDelay = parseInt(rawString, 10);
    const validDelay = nativeIsNaN(parsedDelay) ? null : parsedDelay;
    return validDelay;
  };
  function getRandomIntInclusive(min, max) {
    min = Math.ceil(min);
    max = Math.floor(max);
    return Math.floor(Math.random() * (max - min + 1) + min);
  }

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
  var escapeRegExp = (str) => str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
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
  var isValidStrPattern = (input) => {
    const FORWARD_SLASH = "/";
    let str = escapeRegExp(input);
    if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
      str = input.slice(1, -1);
    }
    let isValid;
    try {
      isValid = new RegExp(str);
      isValid = true;
    } catch (e) {
      isValid = false;
    }
    return isValid;
  };
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
  function getRandomStrByLength(length) {
    let result = "";
    const characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+=~";
    const charactersLength = characters.length;
    for (let i = 0; i < length; i += 1) {
      result += characters.charAt(Math.floor(Math.random() * charactersLength));
    }
    return result;
  }
  function generateRandomResponse(customResponseText) {
    let customResponse = customResponseText;
    if (customResponse === "true") {
      customResponse = Math.random().toString(36).slice(-10);
      return customResponse;
    }
    customResponse = customResponse.replace("length:", "");
    const rangeRegex = /^\d+-\d+$/;
    if (!rangeRegex.test(customResponse)) {
      return null;
    }
    let rangeMin = getNumberFromString(customResponse.split("-")[0]);
    let rangeMax = getNumberFromString(customResponse.split("-")[1]);
    if (!nativeIsFinite(rangeMin) || !nativeIsFinite(rangeMax)) {
      return null;
    }
    if (rangeMin > rangeMax) {
      const temp = rangeMin;
      rangeMin = rangeMax;
      rangeMax = temp;
    }
    const LENGTH_RANGE_LIMIT = 500 * 1e3;
    if (rangeMax > LENGTH_RANGE_LIMIT) {
      return null;
    }
    const length = getRandomIntInclusive(rangeMin, rangeMax);
    customResponse = getRandomStrByLength(length);
    return customResponse;
  }

  // Scriptlets/src/helpers/request-utils.ts
  var getRequestProps = () => {
    return [
      "url",
      "method",
      "headers",
      "body",
      "credentials",
      "cache",
      "redirect",
      "referrer",
      "referrerPolicy",
      "integrity",
      "keepalive",
      "signal",
      "mode"
    ];
  };
  var getXhrData = (method, url, async, user, password) => {
    return {
      method,
      url,
      async,
      user,
      password
    };
  };
  var parseMatchProps = (propsToMatchStr) => {
    const PROPS_DIVIDER = " ";
    const PAIRS_MARKER = ":";
    const isRequestProp = (prop) => {
      return getRequestProps().includes(prop);
    };
    const propsObj = {};
    const props = propsToMatchStr.split(PROPS_DIVIDER);
    props.forEach((prop) => {
      const dividerInd = prop.indexOf(PAIRS_MARKER);
      const key = prop.slice(0, dividerInd);
      if (isRequestProp(key)) {
        const value = prop.slice(dividerInd + 1);
        propsObj[key] = value;
      } else {
        propsObj.url = prop;
      }
    });
    return propsObj;
  };
  var isValidParsedData = (data) => {
    return Object.values(data).every((value) => isValidStrPattern(value));
  };
  var getMatchPropsData = (data) => {
    const matchData = {};
    const dataKeys = Object.keys(data);
    dataKeys.forEach((key) => {
      matchData[key] = toRegExp(data[key]);
    });
    return matchData;
  };

  // Scriptlets/src/helpers/match-request-props.ts
  var matchRequestProps = (source, propsToMatch, requestData) => {
    if (propsToMatch === "" || propsToMatch === "*") {
      return true;
    }
    let isMatched;
    const parsedData = parseMatchProps(propsToMatch);
    if (!isValidParsedData(parsedData)) {
      logMessage(source, `Invalid parameter: ${propsToMatch}`);
      isMatched = false;
    } else {
      const matchData = getMatchPropsData(parsedData);
      const matchKeys = Object.keys(matchData);
      isMatched = matchKeys.every((matchKey) => {
        const matchValue = matchData[matchKey];
        const dataValue = requestData[matchKey];
        return Object.prototype.hasOwnProperty.call(requestData, matchKey) && typeof dataValue === "string" && matchValue?.test(dataValue);
      });
    }
    return isMatched;
  };

  // Scriptlets/src/scriptlets/prevent-xhr.js
  function preventXHR(source, propsToMatch, customResponseText) {
    if (typeof Proxy === "undefined") {
      return;
    }
    const nativeOpen = window.XMLHttpRequest.prototype.open;
    const nativeGetResponseHeader = window.XMLHttpRequest.prototype.getResponseHeader;
    const nativeGetAllResponseHeaders = window.XMLHttpRequest.prototype.getAllResponseHeaders;
    let xhrData;
    let modifiedResponse = "";
    let modifiedResponseText = "";
    const openWrapper = (target, thisArg, args) => {
      xhrData = getXhrData.apply(null, args);
      if (typeof propsToMatch === "undefined") {
        logMessage(source, `xhr( ${objectToString(xhrData)} )`, true);
        hit(source);
      } else if (matchRequestProps(source, propsToMatch, xhrData)) {
        thisArg.shouldBePrevented = true;
        thisArg.xhrData = xhrData;
      }
      if (thisArg.shouldBePrevented) {
        thisArg.collectedHeaders = [];
        const setRequestHeaderWrapper = (target2, thisArg2, args2) => {
          thisArg2.collectedHeaders.push(args2);
          return Reflect.apply(target2, thisArg2, args2);
        };
        const setRequestHeaderHandler = {
          apply: setRequestHeaderWrapper
        };
        thisArg.setRequestHeader = new Proxy(thisArg.setRequestHeader, setRequestHeaderHandler);
      }
      return Reflect.apply(target, thisArg, args);
    };
    const sendWrapper = (target, thisArg, args) => {
      if (!thisArg.shouldBePrevented) {
        return Reflect.apply(target, thisArg, args);
      }
      if (thisArg.responseType === "blob") {
        modifiedResponse = new Blob();
      }
      if (thisArg.responseType === "arraybuffer") {
        modifiedResponse = new ArrayBuffer();
      }
      if (customResponseText) {
        const randomText = generateRandomResponse(customResponseText);
        if (randomText) {
          modifiedResponse = randomText;
          modifiedResponseText = randomText;
        } else {
          logMessage(source, `Invalid randomize parameter: '${customResponseText}'`);
        }
      }
      const forgedRequest = new XMLHttpRequest();
      const transitionReadyState = (state) => {
        if (state === 4) {
          const {
            responseURL,
            responseXML
          } = forgedRequest;
          Object.defineProperties(thisArg, {
            readyState: { value: 4, writable: false },
            statusText: { value: "OK", writable: false },
            responseURL: { value: responseURL || thisArg.xhrData.url, writable: false },
            responseXML: { value: responseXML, writable: false },
            status: { value: 200, writable: false },
            response: { value: modifiedResponse, writable: false },
            responseText: { value: modifiedResponseText, writable: false }
          });
          hit(source);
        } else {
          Object.defineProperty(thisArg, "readyState", {
            value: state,
            writable: true,
            configurable: true
          });
        }
        const stateEvent = new Event("readystatechange");
        thisArg.dispatchEvent(stateEvent);
      };
      forgedRequest.addEventListener("readystatechange", () => {
        transitionReadyState(1);
        const loadStartEvent = new ProgressEvent("loadstart");
        thisArg.dispatchEvent(loadStartEvent);
        transitionReadyState(2);
        transitionReadyState(3);
        const progressEvent = new ProgressEvent("progress");
        thisArg.dispatchEvent(progressEvent);
        transitionReadyState(4);
      });
      setTimeout(() => {
        const loadEvent = new ProgressEvent("load");
        thisArg.dispatchEvent(loadEvent);
        const loadEndEvent = new ProgressEvent("loadend");
        thisArg.dispatchEvent(loadEndEvent);
      }, 1);
      nativeOpen.apply(forgedRequest, [thisArg.xhrData.method, thisArg.xhrData.url]);
      thisArg.collectedHeaders.forEach((header) => {
        const name = header[0];
        const value = header[1];
        forgedRequest.setRequestHeader(name, value);
      });
      return void 0;
    };
    const getHeaderWrapper = (target, thisArg, args) => {
      if (!thisArg.shouldBePrevented) {
        return nativeGetResponseHeader.apply(thisArg, args);
      }
      if (!thisArg.collectedHeaders.length) {
        return null;
      }
      const searchHeaderName = args[0].toLowerCase();
      const matchedHeader = thisArg.collectedHeaders.find((header) => {
        const headerName = header[0].toLowerCase();
        return headerName === searchHeaderName;
      });
      return matchedHeader ? matchedHeader[1] : null;
    };
    const getAllHeadersWrapper = (target, thisArg) => {
      if (!thisArg.shouldBePrevented) {
        return nativeGetAllResponseHeaders.call(thisArg);
      }
      if (!thisArg.collectedHeaders.length) {
        return "";
      }
      const allHeadersStr = thisArg.collectedHeaders.map((header) => {
        const headerName = header[0];
        const headerValue = header[1];
        return `${headerName.toLowerCase()}: ${headerValue}`;
      }).join("\r\n");
      return allHeadersStr;
    };
    const openHandler = {
      apply: openWrapper
    };
    const sendHandler = {
      apply: sendWrapper
    };
    const getHeaderHandler = {
      apply: getHeaderWrapper
    };
    const getAllHeadersHandler = {
      apply: getAllHeadersWrapper
    };
    XMLHttpRequest.prototype.open = new Proxy(XMLHttpRequest.prototype.open, openHandler);
    XMLHttpRequest.prototype.send = new Proxy(XMLHttpRequest.prototype.send, sendHandler);
    XMLHttpRequest.prototype.getResponseHeader = new Proxy(
      XMLHttpRequest.prototype.getResponseHeader,
      getHeaderHandler
    );
    XMLHttpRequest.prototype.getAllResponseHeaders = new Proxy(
      XMLHttpRequest.prototype.getAllResponseHeaders,
      getAllHeadersHandler
    );
  }
  var preventXHRNames = [
    "prevent-xhr",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "no-xhr-if.js",
    "ubo-no-xhr-if.js",
    "ubo-no-xhr-if"
  ];
  preventXHR.primaryName = preventXHRNames[0];
  preventXHR.injections = [
    hit,
    objectToString,
    generateRandomResponse,
    matchRequestProps,
    getXhrData,
    logMessage,
    toRegExp,
    isValidStrPattern,
    escapeRegExp,
    isEmptyObject,
    getNumberFromString,
    nativeIsFinite,
    nativeIsNaN,
    parseMatchProps,
    isValidParsedData,
    getMatchPropsData,
    getRequestProps,
    getRandomIntInclusive,
    getRandomStrByLength
  ];
  return __toCommonJS(prevent_xhr_exports);
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
    console.warn("No callable function found for scriptlet module: prevent-xhr");
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
