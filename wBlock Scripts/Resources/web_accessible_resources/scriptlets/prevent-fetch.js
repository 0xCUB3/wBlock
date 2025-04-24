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

  // Scriptlets/src/scriptlets/prevent-fetch.js
  var prevent_fetch_exports = {};
  __export(prevent_fetch_exports, {
    preventFetch: () => preventFetch,
    preventFetchNames: () => preventFetchNames
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

  // Scriptlets/src/helpers/noop-utils.ts
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

  // Scriptlets/src/helpers/response-utils.ts
  var modifyResponse = (origResponse, replacement = {
    body: "{}"
  }) => {
    const headers = {};
    origResponse?.headers?.forEach((value, key) => {
      headers[key] = value;
    });
    const modifiedResponse = new Response(replacement.body, {
      status: origResponse.status,
      statusText: origResponse.statusText,
      headers
    });
    Object.defineProperties(modifiedResponse, {
      url: {
        value: origResponse.url
      },
      type: {
        value: replacement.type || origResponse.type
      }
    });
    return modifiedResponse;
  };

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
  var getRequestData = (request) => {
    const requestInitOptions = getRequestProps();
    const entries = requestInitOptions.map((key) => {
      const value = request[key];
      return [key, value];
    });
    return Object.fromEntries(entries);
  };
  var getFetchData = (args, nativeRequestClone) => {
    const fetchPropsObj = {};
    const resource = args[0];
    let fetchUrl;
    let fetchInit;
    if (resource instanceof Request) {
      const realData = nativeRequestClone.call(resource);
      const requestData = getRequestData(realData);
      fetchUrl = requestData.url;
      fetchInit = requestData;
    } else {
      fetchUrl = resource;
      fetchInit = args[1];
    }
    fetchPropsObj.url = fetchUrl;
    if (fetchInit instanceof Object) {
      const props = Object.keys(fetchInit);
      props.forEach((prop) => {
        fetchPropsObj[prop] = fetchInit[prop];
      });
    }
    return fetchPropsObj;
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

  // Scriptlets/src/scriptlets/prevent-fetch.js
  function preventFetch(source, propsToMatch, responseBody = "emptyObj", responseType) {
    if (typeof fetch === "undefined" || typeof Proxy === "undefined" || typeof Response === "undefined") {
      return;
    }
    const nativeRequestClone = Request.prototype.clone;
    let strResponseBody;
    if (responseBody === "" || responseBody === "emptyObj") {
      strResponseBody = "{}";
    } else if (responseBody === "emptyArr") {
      strResponseBody = "[]";
    } else if (responseBody === "emptyStr") {
      strResponseBody = "";
    } else if (responseBody === "true" || responseBody.match(/^length:\d+-\d+$/)) {
      strResponseBody = generateRandomResponse(responseBody);
    } else {
      logMessage(source, `Invalid responseBody parameter: '${responseBody}'`);
      return;
    }
    const isResponseTypeSpecified = typeof responseType !== "undefined";
    const isResponseTypeSupported = (responseType2) => {
      const SUPPORTED_TYPES = [
        "basic",
        "cors",
        "opaque"
      ];
      return SUPPORTED_TYPES.includes(responseType2);
    };
    if (isResponseTypeSpecified && !isResponseTypeSupported(responseType)) {
      logMessage(source, `Invalid responseType parameter: '${responseType}'`);
      return;
    }
    const getResponseType = (request) => {
      try {
        const { mode } = request;
        if (mode === void 0 || mode === "cors" || mode === "no-cors") {
          const fetchURL = new URL(request.url);
          if (fetchURL.origin === document.location.origin) {
            return "basic";
          }
          return mode === "no-cors" ? "opaque" : "cors";
        }
      } catch (error) {
        logMessage(source, `Could not determine response type: ${error}`);
      }
      return void 0;
    };
    const handlerWrapper = async (target, thisArg, args) => {
      let shouldPrevent = false;
      const fetchData = getFetchData(args, nativeRequestClone);
      if (typeof propsToMatch === "undefined") {
        logMessage(source, `fetch( ${objectToString(fetchData)} )`, true);
        hit(source);
        return Reflect.apply(target, thisArg, args);
      }
      shouldPrevent = matchRequestProps(source, propsToMatch, fetchData);
      if (shouldPrevent) {
        hit(source);
        let finalResponseType;
        try {
          finalResponseType = responseType || getResponseType(fetchData);
          const origResponse = await Reflect.apply(target, thisArg, args);
          if (!origResponse.ok) {
            return noopPromiseResolve(strResponseBody, fetchData.url, finalResponseType);
          }
          return modifyResponse(
            origResponse,
            {
              body: strResponseBody,
              type: finalResponseType
            }
          );
        } catch (ex) {
          return noopPromiseResolve(strResponseBody, fetchData.url, finalResponseType);
        }
      }
      return Reflect.apply(target, thisArg, args);
    };
    const fetchHandler = {
      apply: handlerWrapper
    };
    fetch = new Proxy(fetch, fetchHandler);
  }
  var preventFetchNames = [
    "prevent-fetch",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "prevent-fetch.js",
    "ubo-prevent-fetch.js",
    "ubo-prevent-fetch",
    "no-fetch-if.js",
    "ubo-no-fetch-if.js",
    "ubo-no-fetch-if"
  ];
  preventFetch.primaryName = preventFetchNames[0];
  preventFetch.injections = [
    hit,
    getFetchData,
    objectToString,
    matchRequestProps,
    logMessage,
    noopPromiseResolve,
    modifyResponse,
    toRegExp,
    isValidStrPattern,
    escapeRegExp,
    isEmptyObject,
    getRequestData,
    getRequestProps,
    parseMatchProps,
    isValidParsedData,
    getMatchPropsData,
    generateRandomResponse,
    nativeIsFinite,
    nativeIsNaN,
    getNumberFromString,
    getRandomIntInclusive,
    getRandomStrByLength
  ];
  return __toCommonJS(prevent_fetch_exports);
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
    console.warn("No callable function found for scriptlet module: prevent-fetch");
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
