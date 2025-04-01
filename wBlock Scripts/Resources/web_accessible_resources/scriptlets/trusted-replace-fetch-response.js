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

  // Scriptlets/src/scriptlets/trusted-replace-fetch-response.js
  var trusted_replace_fetch_response_exports = {};
  __export(trusted_replace_fetch_response_exports, {
    trustedReplaceFetchResponse: () => trustedReplaceFetchResponse,
    trustedReplaceFetchResponseNames: () => trustedReplaceFetchResponseNames
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

  // Scriptlets/src/helpers/response-utils.ts
  var forgeResponse = (response, textContent) => {
    const {
      bodyUsed,
      headers,
      ok,
      redirected,
      status,
      statusText,
      type,
      url
    } = response;
    const forgedResponse = new Response(textContent, {
      status,
      statusText,
      headers
    });
    Object.defineProperties(forgedResponse, {
      url: { value: url },
      type: { value: type },
      ok: { value: ok },
      bodyUsed: { value: bodyUsed },
      redirected: { value: redirected }
    });
    return forgedResponse;
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

  // Scriptlets/src/scriptlets/trusted-replace-fetch-response.js
  function trustedReplaceFetchResponse(source, pattern = "", replacement = "", propsToMatch = "", verbose = false) {
    if (typeof fetch === "undefined" || typeof Proxy === "undefined" || typeof Response === "undefined") {
      return;
    }
    if (pattern === "" && replacement !== "") {
      logMessage(source, "Pattern argument should not be empty string");
      return;
    }
    const shouldLog = pattern === "" && replacement === "";
    const shouldLogContent = verbose === "true";
    const nativeRequestClone = Request.prototype.clone;
    const nativeFetch = fetch;
    let shouldReplace = false;
    let fetchData;
    const handlerWrapper = (target, thisArg, args) => {
      fetchData = getFetchData(args, nativeRequestClone);
      if (shouldLog) {
        logMessage(source, `fetch( ${objectToString(fetchData)} )`, true);
        hit(source);
        return Reflect.apply(target, thisArg, args);
      }
      shouldReplace = matchRequestProps(source, propsToMatch, fetchData);
      if (!shouldReplace) {
        return Reflect.apply(target, thisArg, args);
      }
      return nativeFetch.apply(null, args).then((response) => {
        return response.text().then((bodyText) => {
          const patternRegexp = pattern === "*" ? /(\n|.)*/ : toRegExp(pattern);
          if (shouldLogContent) {
            logMessage(source, `Original text content: ${bodyText}`);
          }
          const modifiedTextContent = bodyText.replace(patternRegexp, replacement);
          if (shouldLogContent) {
            logMessage(source, `Modified text content: ${modifiedTextContent}`);
          }
          const forgedResponse = forgeResponse(response, modifiedTextContent);
          hit(source);
          return forgedResponse;
        }).catch(() => {
          const fetchDataStr = objectToString(fetchData);
          const message = `Response body can't be converted to text: ${fetchDataStr}`;
          logMessage(source, message);
          return Reflect.apply(target, thisArg, args);
        });
      }).catch(() => Reflect.apply(target, thisArg, args));
    };
    const fetchHandler = {
      apply: handlerWrapper
    };
    fetch = new Proxy(fetch, fetchHandler);
  }
  var trustedReplaceFetchResponseNames = [
    "trusted-replace-fetch-response"
    // trusted scriptlets support no aliases
  ];
  trustedReplaceFetchResponse.primaryName = trustedReplaceFetchResponseNames[0];
  trustedReplaceFetchResponse.injections = [
    hit,
    logMessage,
    getFetchData,
    objectToString,
    matchRequestProps,
    forgeResponse,
    toRegExp,
    isValidStrPattern,
    escapeRegExp,
    isEmptyObject,
    getRequestData,
    getRequestProps,
    parseMatchProps,
    isValidParsedData,
    getMatchPropsData
  ];
  return __toCommonJS(trusted_replace_fetch_response_exports);
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
    console.warn("No callable function found for scriptlet module: trusted-replace-fetch-response");
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
