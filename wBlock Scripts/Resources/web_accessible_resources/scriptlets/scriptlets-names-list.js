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

  // src/scriptlets/scriptlets-names-list.ts
  var scriptlets_names_list_exports = {};
  __export(scriptlets_names_list_exports, {
    AmazonApstagNames: () => AmazonApstagNames,
    DidomiLoaderNames: () => DidomiLoaderNames,
    Fingerprintjs2Names: () => Fingerprintjs2Names,
    Fingerprintjs3Names: () => Fingerprintjs3Names,
    GemiusNames: () => GemiusNames,
    GoogleAnalyticsGaNames: () => GoogleAnalyticsGaNames,
    GoogleAnalyticsNames: () => GoogleAnalyticsNames,
    GoogleIma3Names: () => GoogleIma3Names,
    GoogleSyndicationAdsByGoogleNames: () => GoogleSyndicationAdsByGoogleNames,
    GoogleTagServicesGptNames: () => GoogleTagServicesGptNames,
    MatomoNames: () => MatomoNames,
    NaverWcslogNames: () => NaverWcslogNames,
    PardotNames: () => PardotNames,
    PrebidNames: () => PrebidNames,
    ScoreCardResearchBeaconNames: () => ScoreCardResearchBeaconNames,
    abortCurrentInlineScriptNames: () => abortCurrentInlineScriptNames,
    abortOnPropertyReadNames: () => abortOnPropertyReadNames,
    abortOnPropertyWriteNames: () => abortOnPropertyWriteNames,
    abortOnStackTraceNames: () => abortOnStackTraceNames,
    adjustSetIntervalNames: () => adjustSetIntervalNames,
    adjustSetTimeoutNames: () => adjustSetTimeoutNames,
    callNoThrowNames: () => callNoThrowNames,
    debugCurrentInlineScriptNames: () => debugCurrentInlineScriptNames,
    debugOnPropertyReadNames: () => debugOnPropertyReadNames,
    debugOnPropertyWriteNames: () => debugOnPropertyWriteNames,
    dirStringNames: () => dirStringNames,
    disableNewtabLinksNames: () => disableNewtabLinksNames,
    evalDataPruneNames: () => evalDataPruneNames,
    forceWindowCloseNames: () => forceWindowCloseNames,
    hideInShadowDomNames: () => hideInShadowDomNames,
    hrefSanitizerNames: () => hrefSanitizerNames,
    injectCssInShadowDomNames: () => injectCssInShadowDomNames,
    jsonPruneFetchResponseNames: () => jsonPruneFetchResponseNames,
    jsonPruneNames: () => jsonPruneNames,
    jsonPruneXhrResponseNames: () => jsonPruneXhrResponseNames,
    logAddEventListenerNames: () => logAddEventListenerNames,
    logEvalNames: () => logEvalNames,
    logNames: () => logNames,
    logOnStackTraceNames: () => logOnStackTraceNames,
    m3uPruneNames: () => m3uPruneNames,
    metrikaYandexTagNames: () => metrikaYandexTagNames,
    metrikaYandexWatchNames: () => metrikaYandexWatchNames,
    noProtectedAudienceNames: () => noProtectedAudienceNames,
    noTopicsNames: () => noTopicsNames,
    noevalNames: () => noevalNames,
    nowebrtcNames: () => nowebrtcNames,
    preventAddEventListenerNames: () => preventAddEventListenerNames,
    preventAdflyNames: () => preventAdflyNames,
    preventBabNames: () => preventBabNames,
    preventCanvasNames: () => preventCanvasNames,
    preventElementSrcLoadingNames: () => preventElementSrcLoadingNames,
    preventEvalIfNames: () => preventEvalIfNames,
    preventFabNames: () => preventFabNames,
    preventFetchNames: () => preventFetchNames,
    preventPopadsNetNames: () => preventPopadsNetNames,
    preventRefreshNames: () => preventRefreshNames,
    preventRequestAnimationFrameNames: () => preventRequestAnimationFrameNames,
    preventSetIntervalNames: () => preventSetIntervalNames,
    preventSetTimeoutNames: () => preventSetTimeoutNames,
    preventWindowOpenNames: () => preventWindowOpenNames,
    preventXHRNames: () => preventXHRNames,
    removeAttrNames: () => removeAttrNames,
    removeClassNames: () => removeClassNames,
    removeCookieNames: () => removeCookieNames,
    removeInShadowDomNames: () => removeInShadowDomNames,
    removeNodeTextNames: () => removeNodeTextNames,
    setAttrNames: () => setAttrNames,
    setConstantNames: () => setConstantNames,
    setCookieNames: () => setCookieNames,
    setCookieReloadNames: () => setCookieReloadNames,
    setLocalStorageItemNames: () => setLocalStorageItemNames,
    setPopadsDummyNames: () => setPopadsDummyNames,
    setSessionStorageItemNames: () => setSessionStorageItemNames,
    spoofCSSNames: () => spoofCSSNames,
    trustedClickElementNames: () => trustedClickElementNames,
    trustedCreateElementNames: () => trustedCreateElementNames,
    trustedDispatchEventNames: () => trustedDispatchEventNames,
    trustedPruneInboundObjectNames: () => trustedPruneInboundObjectNames,
    trustedReplaceFetchResponseNames: () => trustedReplaceFetchResponseNames,
    trustedReplaceNodeTextNames: () => trustedReplaceNodeTextNames,
    trustedReplaceOutboundTextNames: () => trustedReplaceOutboundTextNames,
    trustedReplaceXhrResponseNames: () => trustedReplaceXhrResponseNames,
    trustedSetAttrNames: () => trustedSetAttrNames,
    trustedSetConstantNames: () => trustedSetConstantNames,
    trustedSetCookieNames: () => trustedSetCookieNames,
    trustedSetCookieReloadNames: () => trustedSetCookieReloadNames,
    trustedSetLocalStorageItemNames: () => trustedSetLocalStorageItemNames,
    trustedSetSessionStorageItemNames: () => trustedSetSessionStorageItemNames,
    trustedSuppressNativeMethodNames: () => trustedSuppressNativeMethodNames,
    xmlPruneNames: () => xmlPruneNames
  });

  // src/helpers/add-event-listener-utils.ts
  var validateType = (type) => {
    return typeof type !== "undefined";
  };
  var validateListener = (listener) => {
    return typeof listener !== "undefined" && (typeof listener === "function" || typeof listener === "object" && listener !== null && "handleEvent" in listener && typeof listener.handleEvent === "function");
  };
  var listenerToString = (listener) => {
    return typeof listener === "function" ? listener.toString() : listener.handleEvent.toString();
  };

  // src/helpers/number-utils.ts
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

  // src/helpers/adjust-set-utils.ts
  var shouldMatchAnyDelay = (delay) => delay === "*";
  var getMatchDelay = (delay) => {
    const DEFAULT_DELAY = 1e3;
    const parsedDelay = parseInt(delay, 10);
    const delayMatch = nativeIsNaN(parsedDelay) ? DEFAULT_DELAY : parsedDelay;
    return delayMatch;
  };
  var isDelayMatched = (inputDelay, realDelay) => {
    return shouldMatchAnyDelay(inputDelay) || realDelay === getMatchDelay(inputDelay);
  };
  var getBoostMultiplier = (boost) => {
    const DEFAULT_MULTIPLIER = 0.05;
    const MIN_MULTIPLIER = 1e-3;
    const MAX_MULTIPLIER = 50;
    const parsedBoost = parseFloat(boost);
    let boostMultiplier = nativeIsNaN(parsedBoost) || !nativeIsFinite(parsedBoost) ? DEFAULT_MULTIPLIER : parsedBoost;
    if (boostMultiplier < MIN_MULTIPLIER) {
      boostMultiplier = MIN_MULTIPLIER;
    }
    if (boostMultiplier > MAX_MULTIPLIER) {
      boostMultiplier = MAX_MULTIPLIER;
    }
    return boostMultiplier;
  };

  // src/helpers/array-utils.ts
  var flatten = (input) => {
    const stack = [];
    input.forEach((el) => stack.push(el));
    const res = [];
    while (stack.length) {
      const next = stack.pop();
      if (Array.isArray(next)) {
        next.forEach((el) => stack.push(el));
      } else {
        res.push(next);
      }
    }
    return res.reverse();
  };
  var nodeListToArray = (nodeList) => {
    const nodes = [];
    for (let i = 0; i < nodeList.length; i += 1) {
      nodes.push(nodeList[i]);
    }
    return nodes;
  };

  // src/helpers/log-message.ts
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

  // src/helpers/hit.ts
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

  // src/helpers/attribute-utils.ts
  var defaultAttributeSetter = (elem, attribute, value) => elem.setAttribute(attribute, value);
  var setAttributeBySelector = (source, selector, attribute, value, attributeSetter = defaultAttributeSetter) => {
    let elements;
    try {
      elements = document.querySelectorAll(selector);
    } catch {
      logMessage(source, `Failed to find elements matching selector "${selector}"`);
      return;
    }
    if (!elements || elements.length === 0) {
      return;
    }
    try {
      elements.forEach((elem) => attributeSetter(elem, attribute, value));
      hit(source);
    } catch {
      logMessage(source, `Failed to set [${attribute}="${value}"] to each of selected elements.`);
    }
  };
  var parseAttributePairs = (input) => {
    if (!input) {
      return [];
    }
    const NAME_VALUE_SEPARATOR = "=";
    const PAIRS_SEPARATOR = " ";
    const SINGLE_QUOTE = "'";
    const DOUBLE_QUOTE = '"';
    const BACKSLASH = "\\";
    const pairs = [];
    for (let i = 0; i < input.length; i += 1) {
      let name = "";
      let value = "";
      while (i < input.length && input[i] !== NAME_VALUE_SEPARATOR && input[i] !== PAIRS_SEPARATOR) {
        name += input[i];
        i += 1;
      }
      if (i < input.length && input[i] === NAME_VALUE_SEPARATOR) {
        i += 1;
        let quote = null;
        if (input[i] === SINGLE_QUOTE || input[i] === DOUBLE_QUOTE) {
          quote = input[i];
          i += 1;
          for (; i < input.length; i += 1) {
            if (input[i] === quote) {
              if (input[i - 1] === BACKSLASH) {
                value = `${value.slice(0, -1)}${quote}`;
              } else {
                i += 1;
                quote = null;
                break;
              }
            } else {
              value += input[i];
            }
          }
          if (quote !== null) {
            throw new Error(`Unbalanced quote for attribute value: '${input}'`);
          }
        } else {
          throw new Error(`Attribute value should be quoted: "${input.slice(i)}"`);
        }
      }
      name = name.trim();
      value = value.trim();
      if (!name) {
        if (!value) {
          continue;
        }
        throw new Error(`Attribute name before '=' should be specified: '${input}'`);
      }
      pairs.push({
        name,
        value
      });
      if (input[i] && input[i] !== PAIRS_SEPARATOR) {
        throw new Error(`No space before attribute: '${input.slice(i)}'`);
      }
    }
    return pairs;
  };

  // src/helpers/cookie-utils.ts
  var isValidCookiePath = (rawPath) => rawPath === "/" || rawPath === "none";
  var getCookiePath = (rawPath) => {
    if (rawPath === "/") {
      return "path=/";
    }
    return "";
  };
  var serializeCookie = (name, rawValue, rawPath, domainValue = "", shouldEncodeValue = true) => {
    const HOST_PREFIX = "__Host-";
    const SECURE_PREFIX = "__Secure-";
    const COOKIE_BREAKER = ";";
    if (!shouldEncodeValue && `${rawValue}`.includes(COOKIE_BREAKER) || name.includes(COOKIE_BREAKER)) {
      return null;
    }
    const value = shouldEncodeValue ? encodeURIComponent(rawValue) : rawValue;
    let resultCookie = `${name}=${value}`;
    if (name.startsWith(HOST_PREFIX)) {
      resultCookie += "; path=/; secure";
      if (domainValue) {
        console.debug(
          `Domain value: "${domainValue}" has been ignored, because is not allowed for __Host- prefixed cookies`
        );
      }
      return resultCookie;
    }
    const path = getCookiePath(rawPath);
    if (path) {
      resultCookie += `; ${path}`;
    }
    if (name.startsWith(SECURE_PREFIX)) {
      resultCookie += "; secure";
    }
    if (domainValue) {
      resultCookie += `; domain=${domainValue}`;
    }
    return resultCookie;
  };
  var getLimitedCookieValue = (value) => {
    if (!value) {
      return null;
    }
    const allowedCookieValues = /* @__PURE__ */ new Set([
      "true",
      "t",
      "false",
      "f",
      "yes",
      "y",
      "no",
      "n",
      "ok",
      "on",
      "off",
      "accept",
      "accepted",
      "notaccepted",
      "reject",
      "rejected",
      "allow",
      "allowed",
      "disallow",
      "deny",
      "enable",
      "enabled",
      "disable",
      "disabled",
      "necessary",
      "required",
      "hide",
      "hidden",
      "essential",
      "nonessential",
      "checked",
      "unchecked",
      "forbidden",
      "forever"
    ]);
    let validValue;
    if (allowedCookieValues.has(value.toLowerCase())) {
      validValue = value;
    } else if (/^\d+$/.test(value)) {
      validValue = parseFloat(value);
      if (nativeIsNaN(validValue)) {
        return null;
      }
      if (Math.abs(validValue) < 0 || Math.abs(validValue) > 32767) {
        return null;
      }
    } else {
      return null;
    }
    return validValue;
  };
  var parseCookieString = (cookieString) => {
    const COOKIE_DELIMITER = "=";
    const COOKIE_PAIRS_DELIMITER = ";";
    const cookieChunks = cookieString.split(COOKIE_PAIRS_DELIMITER);
    const cookieData = {};
    cookieChunks.forEach((singleCookie) => {
      let cookieKey;
      let cookieValue = "";
      const delimiterIndex = singleCookie.indexOf(COOKIE_DELIMITER);
      if (delimiterIndex === -1) {
        cookieKey = singleCookie.trim();
      } else {
        cookieKey = singleCookie.slice(0, delimiterIndex).trim();
        cookieValue = singleCookie.slice(delimiterIndex + 1);
      }
      cookieData[cookieKey] = cookieValue || null;
    });
    return cookieData;
  };
  var isCookieSetWithValue = (cookieString, name, value) => {
    return cookieString.split(";").some((cookieStr) => {
      const pos = cookieStr.indexOf("=");
      if (pos === -1) {
        return false;
      }
      const cookieName = cookieStr.slice(0, pos).trim();
      const cookieValue = cookieStr.slice(pos + 1).trim();
      return name === cookieName && value === cookieValue;
    });
  };
  var getTrustedCookieOffsetMs = (offsetExpiresSec) => {
    const ONE_YEAR_EXPIRATION_KEYWORD = "1year";
    const ONE_DAY_EXPIRATION_KEYWORD = "1day";
    const MS_IN_SEC = 1e3;
    const SECONDS_IN_YEAR = 365 * 24 * 60 * 60;
    const SECONDS_IN_DAY = 24 * 60 * 60;
    let parsedSec;
    if (offsetExpiresSec === ONE_YEAR_EXPIRATION_KEYWORD) {
      parsedSec = SECONDS_IN_YEAR;
    } else if (offsetExpiresSec === ONE_DAY_EXPIRATION_KEYWORD) {
      parsedSec = SECONDS_IN_DAY;
    } else {
      parsedSec = Number.parseInt(offsetExpiresSec, 10);
      if (Number.isNaN(parsedSec)) {
        return null;
      }
    }
    return parsedSec * MS_IN_SEC;
  };

  // src/helpers/noop-utils.ts
  var noopFunc = () => {
  };
  var noopCallbackFunc = () => noopFunc;
  var noopNull = () => null;
  var trueFunc = () => true;
  var falseFunc = () => false;
  function noopThis() {
    return this;
  }
  var noopStr = () => "";
  var noopArray = () => [];
  var noopObject = () => ({});
  var throwFunc = () => {
    throw new Error();
  };
  var noopResolveVoid = () => Promise.resolve(void 0);
  var noopResolveNull = () => Promise.resolve(null);
  var noopPromiseReject = () => Promise.reject();
  var noopPromiseResolve = (responseBody = "{}", responseUrl = "", responseType = "basic") => {
    if (typeof Response === "undefined") {
      return;
    }
    const response = new Response(responseBody, {
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

  // src/helpers/object-utils.ts
  var isEmptyObject = (obj) => {
    return Object.keys(obj).length === 0 && !obj.prototype;
  };
  var safeGetDescriptor = (obj, prop) => {
    const descriptor = Object.getOwnPropertyDescriptor(obj, prop);
    if (descriptor && descriptor.configurable) {
      return descriptor;
    }
    return null;
  };
  function setPropertyAccess(object, property, descriptor) {
    const currentDescriptor = Object.getOwnPropertyDescriptor(object, property);
    if (currentDescriptor && !currentDescriptor.configurable) {
      return false;
    }
    Object.defineProperty(object, property, descriptor);
    return true;
  }
  function isArbitraryObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value) && !(value instanceof RegExp);
  }

  // src/helpers/string-utils.ts
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
  var substringAfter = (str, separator) => {
    if (!str) {
      return str;
    }
    const index = str.indexOf(separator);
    return index < 0 ? "" : str.substring(index + separator.length);
  };
  var substringBefore = (str, separator) => {
    if (!str || !separator) {
      return str;
    }
    const index = str.indexOf(separator);
    return index < 0 ? str : str.substring(0, index);
  };
  var convertRtcConfigToString = (config) => {
    const UNDEF_STR = "undefined";
    let str = UNDEF_STR;
    if (config === null) {
      str = "null";
    } else if (config instanceof Object) {
      const SERVERS_PROP_NAME = "iceServers";
      const URLS_PROP_NAME = "urls";
      if (Object.prototype.hasOwnProperty.call(config, SERVERS_PROP_NAME) && config[SERVERS_PROP_NAME] && Object.prototype.hasOwnProperty.call(config[SERVERS_PROP_NAME][0], URLS_PROP_NAME) && !!config[SERVERS_PROP_NAME][0][URLS_PROP_NAME]) {
        str = config[SERVERS_PROP_NAME][0][URLS_PROP_NAME].toString();
      }
    }
    return str;
  };
  var isValidMatchStr = (match) => {
    const INVERT_MARKER = "!";
    let str = match;
    if (match?.startsWith(INVERT_MARKER)) {
      str = match.slice(1);
    }
    return isValidStrPattern(str);
  };
  var isValidMatchNumber = (match) => {
    const INVERT_MARKER = "!";
    let str = match;
    if (match?.startsWith(INVERT_MARKER)) {
      str = match.slice(1);
    }
    const num = parseFloat(str);
    return !nativeIsNaN(num) && nativeIsFinite(num);
  };
  var parseMatchArg = (match) => {
    const INVERT_MARKER = "!";
    const isInvertedMatch = match ? match?.startsWith(INVERT_MARKER) : false;
    const matchValue = isInvertedMatch ? match.slice(1) : match;
    const matchRegexp = toRegExp(matchValue);
    return { isInvertedMatch, matchRegexp, matchValue };
  };
  var parseDelayArg = (delay) => {
    const INVERT_MARKER = "!";
    const isInvertedDelayMatch = delay?.startsWith(INVERT_MARKER);
    const delayValue = isInvertedDelayMatch ? delay.slice(1) : delay;
    const parsedDelay = parseInt(delayValue, 10);
    const delayMatch = nativeIsNaN(parsedDelay) ? null : parsedDelay;
    return { isInvertedDelayMatch, delayMatch };
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
  var convertTypeToString = (value) => {
    let output;
    if (typeof value === "undefined") {
      output = "undefined";
    } else if (typeof value === "object") {
      if (value === null) {
        output = "null";
      } else {
        output = objectToString(value);
      }
    } else {
      output = String(value);
    }
    return output;
  };
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

  // src/helpers/script-source-utils.ts
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

  // src/helpers/open-shadow-dom-utils.ts
  var findHostElements = (rootElement) => {
    const hosts = [];
    if (rootElement) {
      const domElems = rootElement.querySelectorAll("*");
      domElems.forEach((el) => {
        if (el.shadowRoot) {
          hosts.push(el);
        }
      });
    }
    return hosts;
  };
  var pierceShadowDom = (selector, hostElements) => {
    let targets = [];
    const innerHostsAcc = [];
    hostElements.forEach((host) => {
      const simpleElems = host.querySelectorAll(selector);
      targets = targets.concat([].slice.call(simpleElems));
      const shadowRootElem = host.shadowRoot;
      const shadowChildren = shadowRootElem.querySelectorAll(selector);
      targets = targets.concat([].slice.call(shadowChildren));
      innerHostsAcc.push(findHostElements(shadowRootElem));
    });
    const innerHosts = flatten(innerHostsAcc);
    return { targets, innerHosts };
  };
  function doesElementContainText(element, matchRegexp) {
    const { textContent } = element;
    if (!textContent) {
      return false;
    }
    return matchRegexp.test(textContent);
  }
  function findElementWithText(rootElement, selector, matchRegexp) {
    const elements = rootElement.querySelectorAll(selector);
    for (let i = 0; i < elements.length; i += 1) {
      if (doesElementContainText(elements[i], matchRegexp)) {
        return elements[i];
      }
    }
    return null;
  }
  function queryShadowSelector(selector, context = document.documentElement, textContent = null) {
    const SHADOW_COMBINATOR = " >>> ";
    const pos = selector.indexOf(SHADOW_COMBINATOR);
    if (pos === -1) {
      if (textContent) {
        return findElementWithText(context, selector, textContent);
      }
      return context.querySelector(selector);
    }
    const shadowHostSelector = selector.slice(0, pos).trim();
    const elem = context.querySelector(shadowHostSelector);
    if (!elem || !elem.shadowRoot) {
      return null;
    }
    const shadowRootSelector = selector.slice(pos + SHADOW_COMBINATOR.length).trim();
    return queryShadowSelector(shadowRootSelector, elem.shadowRoot, textContent);
  }

  // src/helpers/prevent-utils.ts
  var isValidCallback = (callback) => {
    return callback instanceof Function || typeof callback === "string";
  };
  var parseRawDelay = (delay) => {
    const parsedDelay = Math.floor(parseInt(delay, 10));
    return typeof parsedDelay === "number" && !nativeIsNaN(parsedDelay) ? parsedDelay : delay;
  };
  var isPreventionNeeded = ({
    callback,
    delay,
    matchCallback,
    matchDelay
  }) => {
    if (!isValidCallback(callback)) {
      return false;
    }
    if (!isValidMatchStr(matchCallback) || matchDelay && !isValidMatchNumber(matchDelay)) {
      return false;
    }
    const { isInvertedMatch, matchRegexp } = parseMatchArg(matchCallback);
    const { isInvertedDelayMatch, delayMatch } = parseDelayArg(matchDelay);
    const parsedDelay = parseRawDelay(delay);
    let shouldPrevent = false;
    const callbackStr = String(callback);
    if (delayMatch === null) {
      shouldPrevent = matchRegexp.test(callbackStr) !== isInvertedMatch;
    } else if (!matchCallback) {
      shouldPrevent = parsedDelay === delayMatch !== isInvertedDelayMatch;
    } else {
      shouldPrevent = matchRegexp.test(callbackStr) !== isInvertedMatch && parsedDelay === delayMatch !== isInvertedDelayMatch;
    }
    return shouldPrevent;
  };

  // src/helpers/prevent-window-open-utils.ts
  var handleOldReplacement = (replacement) => {
    let result;
    if (!replacement) {
      result = noopFunc;
    } else if (replacement === "trueFunc") {
      result = trueFunc;
    } else if (replacement.includes("=")) {
      const isProp = replacement.startsWith("{") && replacement.endsWith("}");
      if (isProp) {
        const propertyPart = replacement.slice(1, -1);
        const propertyName = substringBefore(propertyPart, "=");
        const propertyValue = substringAfter(propertyPart, "=");
        if (propertyValue === "noopFunc") {
          result = {};
          result[propertyName] = noopFunc;
        }
      }
    }
    return result;
  };
  var createDecoy = (args) => {
    let TagName;
    ((TagName2) => {
      TagName2["Object"] = "object";
      TagName2["Iframe"] = "iframe";
    })(TagName || (TagName = {}));
    let UrlPropNameOf;
    ((UrlPropNameOf2) => {
      UrlPropNameOf2["Object"] = "data";
      UrlPropNameOf2["Iframe"] = "src";
    })(UrlPropNameOf || (UrlPropNameOf = {}));
    const { replacement, url, delay } = args;
    let tag;
    if (replacement === "obj") {
      tag = "object" /* Object */;
    } else {
      tag = "iframe" /* Iframe */;
    }
    const decoy = document.createElement(tag);
    if (decoy instanceof HTMLObjectElement) {
      decoy["data" /* Object */] = url;
    } else if (decoy instanceof HTMLIFrameElement) {
      decoy["src" /* Iframe */] = url;
    }
    decoy.style.setProperty("height", "1px", "important");
    decoy.style.setProperty("position", "fixed", "important");
    decoy.style.setProperty("top", "-1px", "important");
    decoy.style.setProperty("width", "1px", "important");
    document.body.appendChild(decoy);
    setTimeout(() => decoy.remove(), delay * 1e3);
    return decoy;
  };
  var getPreventGetter = (nativeGetter) => {
    const preventGetter = (target, prop) => {
      if (prop && prop === "closed") {
        return false;
      }
      if (typeof nativeGetter === "function") {
        return noopFunc;
      }
      return prop && target[prop];
    };
    return preventGetter;
  };

  // src/helpers/get-wildcard-property-in-chain.ts
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

  // src/helpers/regexp-utils.ts
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

  // src/helpers/match-stack.ts
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

  // src/helpers/prune-utils.ts
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
          if (ownerObj !== void 0 && ownerObj.base) {
            if (Array.isArray(ownerObj.base)) {
              try {
                const index = Number(ownerObj.prop);
                ownerObj.base.splice(index, 1);
              } catch (error) {
                console.error("Error while deleting array element", error);
              }
            } else {
              delete ownerObj.base[ownerObj.prop];
            }
            hit(source);
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

  // src/helpers/response-utils.ts
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

  // src/helpers/request-utils.ts
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

  // src/helpers/storage-utils.ts
  var setStorageItem = (source, storage, key, value) => {
    try {
      storage.setItem(key, value);
    } catch (e) {
      const message = `Unable to set storage item due to: ${e.message}`;
      logMessage(source, message);
    }
  };
  var removeStorageItem = (source, storage, key) => {
    try {
      if (key.startsWith("/") && (key.endsWith("/") || key.endsWith("/i")) && isValidStrPattern(key)) {
        const regExpKey = toRegExp(key);
        const storageKeys = Object.keys(storage);
        storageKeys.forEach((storageKey) => {
          if (regExpKey.test(storageKey)) {
            storage.removeItem(storageKey);
          }
        });
      } else {
        storage.removeItem(key);
      }
    } catch (e) {
      const message = `Unable to remove storage item due to: ${e.message}`;
      logMessage(source, message);
    }
  };
  var getLimitedStorageItemValue = (value) => {
    if (typeof value !== "string") {
      throw new Error("Invalid value");
    }
    const allowedStorageValues = /* @__PURE__ */ new Set([
      "undefined",
      "false",
      "true",
      "null",
      "",
      "yes",
      "no",
      "on",
      "off",
      "accept",
      "accepted",
      "reject",
      "rejected",
      "allowed",
      "denied",
      "forbidden",
      "forever"
    ]);
    let validValue;
    if (allowedStorageValues.has(value.toLowerCase())) {
      validValue = value;
    } else if (value === "emptyArr") {
      validValue = "[]";
    } else if (value === "emptyObj") {
      validValue = "{}";
    } else if (/^\d+$/.test(value)) {
      validValue = parseFloat(value);
      if (nativeIsNaN(validValue)) {
        throw new Error("Invalid value");
      }
      if (Math.abs(validValue) > 32767) {
        throw new Error("Invalid value");
      }
    } else if (value === "$remove$") {
      validValue = "$remove$";
    } else {
      throw new Error("Invalid value");
    }
    return validValue;
  };

  // src/helpers/random-id.ts
  function randomId() {
    return Math.random().toString(36).slice(2, 9);
  }

  // src/helpers/create-on-error-handler.ts
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

  // src/helpers/get-descriptor-addon.ts
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

  // src/helpers/get-error-message.ts
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

  // src/helpers/get-property-in-chain.ts
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

  // src/helpers/match-request-props.ts
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

  // src/helpers/throttle.ts
  var throttle = (cb, delay) => {
    let wait = false;
    let savedArgs;
    const wrapper = (...args) => {
      if (wait) {
        savedArgs = args;
        return;
      }
      cb(...args);
      wait = true;
      setTimeout(() => {
        wait = false;
        if (savedArgs) {
          wrapper(...savedArgs);
          savedArgs = null;
        }
      }, delay);
    };
    return wrapper;
  };

  // src/helpers/observer.ts
  var observeDOMChanges = (callback, observeAttrs = false, attrsToObserve = []) => {
    const THROTTLE_DELAY_MS = 20;
    const observer = new MutationObserver(throttle(callbackWrapper, THROTTLE_DELAY_MS));
    const connect = () => {
      if (attrsToObserve.length > 0) {
        observer.observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: observeAttrs,
          attributeFilter: attrsToObserve
        });
      } else {
        observer.observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: observeAttrs
        });
      }
    };
    const disconnect = () => {
      observer.disconnect();
    };
    function callbackWrapper() {
      disconnect();
      callback();
      connect();
    }
    connect();
  };
  var getAddedNodes = (mutations) => {
    const nodes = [];
    for (let i = 0; i < mutations.length; i += 1) {
      const { addedNodes } = mutations[i];
      for (let j = 0; j < addedNodes.length; j += 1) {
        nodes.push(addedNodes[j]);
      }
    }
    return nodes;
  };
  var observeDocumentWithTimeout = (callback, options = { subtree: true, childList: true }, timeout = 1e4) => {
    const documentObserver = new MutationObserver((mutations, observer) => {
      observer.disconnect();
      callback(mutations, observer);
      observer.observe(document.documentElement, options);
    });
    documentObserver.observe(document.documentElement, options);
    if (typeof timeout === "number") {
      setTimeout(() => documentObserver.disconnect(), timeout);
    }
  };

  // src/helpers/parse-flags.ts
  var parseFlags = (flags) => {
    const FLAGS_DIVIDER = " ";
    const ASAP_FLAG = "asap";
    const COMPLETE_FLAG = "complete";
    const STAY_FLAG = "stay";
    const VALID_FLAGS = /* @__PURE__ */ new Set([ASAP_FLAG, COMPLETE_FLAG, STAY_FLAG]);
    const passedFlags = new Set(
      flags.trim().split(FLAGS_DIVIDER).filter((flag) => VALID_FLAGS.has(flag))
    );
    return {
      ASAP: ASAP_FLAG,
      COMPLETE: COMPLETE_FLAG,
      STAY: STAY_FLAG,
      hasFlag: (flag) => passedFlags.has(flag)
    };
  };

  // src/helpers/parse-keyword-value.ts
  var parseKeywordValue = (rawValue) => {
    const NOW_VALUE_KEYWORD = "$now$";
    const CURRENT_DATE_KEYWORD = "$currentDate$";
    const CURRENT_ISO_DATE_KEYWORD = "$currentISODate$";
    let parsedValue = rawValue;
    if (rawValue === NOW_VALUE_KEYWORD) {
      parsedValue = Date.now().toString();
    } else if (rawValue === CURRENT_DATE_KEYWORD) {
      parsedValue = Date();
    } else if (rawValue === CURRENT_ISO_DATE_KEYWORD) {
      parsedValue = (/* @__PURE__ */ new Date()).toISOString();
    }
    return parsedValue;
  };

  // src/helpers/shadow-dom-utils.ts
  var hijackAttachShadow = (context, hostSelector, callback) => {
    const handlerWrapper = (target, thisArg, args) => {
      const shadowRoot = Reflect.apply(target, thisArg, args);
      if (thisArg && thisArg.matches(hostSelector || "*")) {
        callback(shadowRoot);
      }
      return shadowRoot;
    };
    const attachShadowHandler = {
      apply: handlerWrapper
    };
    context.Element.prototype.attachShadow = new Proxy(
      context.Element.prototype.attachShadow,
      attachShadowHandler
    );
  };

  // src/helpers/node-text-utils.ts
  var handleExistingNodes = (selector, handler, parentSelector) => {
    const processNodes = (parent) => {
      if (selector === "#text") {
        const textNodes = nodeListToArray(parent.childNodes).filter((node) => node.nodeType === Node.TEXT_NODE);
        handler(textNodes);
      } else {
        const nodes = nodeListToArray(parent.querySelectorAll(selector));
        handler(nodes);
      }
    };
    const parents = parentSelector ? document.querySelectorAll(parentSelector) : [document];
    parents.forEach((parent) => processNodes(parent));
  };
  var handleMutations = (mutations, handler, selector, parentSelector) => {
    const addedNodes = getAddedNodes(mutations);
    if (selector && parentSelector) {
      addedNodes.forEach(() => {
        handleExistingNodes(selector, handler, parentSelector);
      });
    } else {
      handler(addedNodes);
    }
  };
  var isTargetNode = (node, nodeNameMatch, textContentMatch) => {
    const { nodeName, textContent } = node;
    const nodeNameLowerCase = nodeName.toLowerCase();
    return textContent !== null && textContent !== "" && (nodeNameMatch instanceof RegExp ? nodeNameMatch.test(nodeNameLowerCase) : nodeNameMatch === nodeNameLowerCase) && (textContentMatch instanceof RegExp ? textContentMatch.test(textContent) : textContent.includes(textContentMatch));
  };
  var replaceNodeText = (source, node, pattern, replacement) => {
    const { textContent } = node;
    if (textContent) {
      if (node.nodeName === "SCRIPT" && window.trustedTypes && window.trustedTypes.createPolicy) {
        const policy = window.trustedTypes.createPolicy("AGPolicy", {
          createScript: (string) => string
        });
        const modifiedText = textContent.replace(pattern, replacement);
        const trustedReplacement = policy.createScript(modifiedText);
        node.textContent = trustedReplacement;
      } else {
        node.textContent = textContent.replace(pattern, replacement);
      }
      hit(source);
    }
  };
  var parseNodeTextParams = (nodeName, textMatch, pattern = null) => {
    const REGEXP_START_MARKER = "/";
    const isStringNameMatch = !(nodeName.startsWith(REGEXP_START_MARKER) && nodeName.endsWith(REGEXP_START_MARKER));
    const selector = isStringNameMatch ? nodeName : "*";
    const nodeNameMatch = isStringNameMatch ? nodeName : toRegExp(nodeName);
    const textContentMatch = !textMatch.startsWith(REGEXP_START_MARKER) ? textMatch : toRegExp(textMatch);
    let patternMatch;
    if (pattern) {
      patternMatch = !pattern.startsWith(REGEXP_START_MARKER) ? pattern : toRegExp(pattern);
    }
    return {
      selector,
      nodeNameMatch,
      textContentMatch,
      patternMatch
    };
  };

  // src/helpers/value-matchers.ts
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

  // src/scriptlets/trusted-click-element.ts
  function trustedClickElement(source, selectors, extraMatch = "", delay = NaN, reload = "") {
    if (!selectors) {
      return;
    }
    const SHADOW_COMBINATOR = " >>> ";
    const OBSERVER_TIMEOUT_MS = 1e4;
    const THROTTLE_DELAY_MS = 20;
    const STATIC_CLICK_DELAY_MS = 150;
    const STATIC_RELOAD_DELAY_MS = 500;
    const COOKIE_MATCH_MARKER = "cookie:";
    const LOCAL_STORAGE_MATCH_MARKER = "localStorage:";
    const TEXT_MATCH_MARKER = "containsText:";
    const RELOAD_ON_FINAL_CLICK_MARKER = "reloadAfterClick";
    const SELECTORS_DELIMITER = ",";
    const COOKIE_STRING_DELIMITER = ";";
    const COLON = ":";
    const EXTRA_MATCH_DELIMITER = /(,\s*){1}(?=!?cookie:|!?localStorage:|containsText:)/;
    const sleep = (delayMs) => {
      return new Promise((resolve) => {
        setTimeout(resolve, delayMs);
      });
    };
    if (selectors.includes(SHADOW_COMBINATOR)) {
      const attachShadowWrapper = (target, thisArg, argumentsList) => {
        const mode = argumentsList[0]?.mode;
        if (mode === "closed") {
          argumentsList[0].mode = "open";
        }
        return Reflect.apply(target, thisArg, argumentsList);
      };
      const attachShadowHandler = {
        apply: attachShadowWrapper
      };
      window.Element.prototype.attachShadow = new Proxy(window.Element.prototype.attachShadow, attachShadowHandler);
    }
    let parsedDelay;
    if (delay) {
      parsedDelay = parseInt(String(delay), 10);
      const isValidDelay = !Number.isNaN(parsedDelay) || parsedDelay < OBSERVER_TIMEOUT_MS;
      if (!isValidDelay) {
        const message = `Passed delay '${delay}' is invalid or bigger than ${OBSERVER_TIMEOUT_MS} ms`;
        logMessage(source, message);
        return;
      }
    }
    let canClick = !parsedDelay;
    const cookieMatches = [];
    const localStorageMatches = [];
    let textMatches = "";
    let isInvertedMatchCookie = false;
    let isInvertedMatchLocalStorage = false;
    if (extraMatch) {
      const parsedExtraMatch = extraMatch.split(EXTRA_MATCH_DELIMITER).map((matchStr) => matchStr.trim());
      parsedExtraMatch.forEach((matchStr) => {
        if (matchStr.includes(COOKIE_MATCH_MARKER)) {
          const { isInvertedMatch, matchValue } = parseMatchArg(matchStr);
          isInvertedMatchCookie = isInvertedMatch;
          const cookieMatch = matchValue.replace(COOKIE_MATCH_MARKER, "");
          cookieMatches.push(cookieMatch);
        }
        if (matchStr.includes(LOCAL_STORAGE_MATCH_MARKER)) {
          const { isInvertedMatch, matchValue } = parseMatchArg(matchStr);
          isInvertedMatchLocalStorage = isInvertedMatch;
          const localStorageMatch = matchValue.replace(LOCAL_STORAGE_MATCH_MARKER, "");
          localStorageMatches.push(localStorageMatch);
        }
        if (matchStr.includes(TEXT_MATCH_MARKER)) {
          const { matchValue } = parseMatchArg(matchStr);
          const textMatch = matchValue.replace(TEXT_MATCH_MARKER, "");
          textMatches = textMatch;
        }
      });
    }
    if (cookieMatches.length > 0) {
      const parsedCookieMatches = parseCookieString(cookieMatches.join(COOKIE_STRING_DELIMITER));
      const parsedCookies = parseCookieString(document.cookie);
      const cookieKeys = Object.keys(parsedCookies);
      if (cookieKeys.length === 0) {
        return;
      }
      const cookiesMatched = Object.keys(parsedCookieMatches).every((key) => {
        const valueMatch = parsedCookieMatches[key] ? toRegExp(parsedCookieMatches[key]) : null;
        const keyMatch = toRegExp(key);
        return cookieKeys.some((cookieKey) => {
          const keysMatched = keyMatch.test(cookieKey);
          if (!keysMatched) {
            return false;
          }
          if (!valueMatch) {
            return true;
          }
          const parsedCookieValue = parsedCookies[cookieKey];
          if (!parsedCookieValue) {
            return false;
          }
          return valueMatch.test(parsedCookieValue);
        });
      });
      const shouldRun = cookiesMatched !== isInvertedMatchCookie;
      if (!shouldRun) {
        return;
      }
    }
    if (localStorageMatches.length > 0) {
      const localStorageMatched = localStorageMatches.every((str) => {
        const itemValue = window.localStorage.getItem(str);
        return itemValue || itemValue === "";
      });
      const shouldRun = localStorageMatched !== isInvertedMatchLocalStorage;
      if (!shouldRun) {
        return;
      }
    }
    const textMatchRegexp = textMatches ? toRegExp(textMatches) : null;
    let selectorsSequence = selectors.split(SELECTORS_DELIMITER).map((selector) => selector.trim());
    const createElementObj = (element, selector) => {
      return {
        element: element || null,
        clicked: false,
        selectorText: selector || null
      };
    };
    const elementsSequence = Array(selectorsSequence.length).fill(createElementObj(null));
    const findAndClickElement = (elementObj) => {
      try {
        if (!elementObj.selectorText) {
          return;
        }
        const element = queryShadowSelector(elementObj.selectorText);
        if (!element) {
          logMessage(source, `Could not find element: '${elementObj.selectorText}'`);
          return;
        }
        element.click();
        elementObj.clicked = true;
      } catch (error) {
        logMessage(source, `Could not click element: '${elementObj.selectorText}'`);
      }
    };
    let shouldReloadAfterClick = false;
    let reloadDelayMs = STATIC_RELOAD_DELAY_MS;
    if (reload) {
      const reloadSplit = reload.split(COLON);
      const reloadMarker = reloadSplit[0];
      const reloadValue = reloadSplit[1];
      if (reloadMarker !== RELOAD_ON_FINAL_CLICK_MARKER) {
        logMessage(source, `Passed reload option '${reload}' is invalid`);
        return;
      }
      if (reloadValue) {
        const passedReload = Number(reloadValue);
        if (Number.isNaN(passedReload)) {
          logMessage(source, `Passed reload delay value '${passedReload}' is invalid`);
          return;
        }
        if (passedReload > OBSERVER_TIMEOUT_MS) {
          logMessage(source, `Passed reload delay value '${passedReload}' is bigger than maximum ${OBSERVER_TIMEOUT_MS} ms`);
          return;
        }
        reloadDelayMs = passedReload;
      }
      shouldReloadAfterClick = true;
    }
    let canReload = true;
    const clickElementsBySequence = async () => {
      for (let i = 0; i < elementsSequence.length; i += 1) {
        const elementObj = elementsSequence[i];
        if (i >= 1) {
          await sleep(STATIC_CLICK_DELAY_MS);
        }
        if (!elementObj.element) {
          break;
        }
        if (!elementObj.clicked) {
          if (elementObj.element.isConnected) {
            elementObj.element.click();
            elementObj.clicked = true;
          } else {
            findAndClickElement(elementObj);
          }
        }
      }
      const allElementsClicked = elementsSequence.every((elementObj) => elementObj.clicked === true);
      if (allElementsClicked) {
        if (shouldReloadAfterClick && canReload) {
          canReload = false;
          setTimeout(() => {
            window.location.reload();
          }, reloadDelayMs);
        }
        hit(source);
      }
    };
    const handleElement = (element, i, selector) => {
      const elementObj = createElementObj(element, selector);
      elementsSequence[i] = elementObj;
      if (canClick) {
        clickElementsBySequence();
      }
    };
    const fulfillAndHandleSelectors = () => {
      const fulfilledSelectors = [];
      selectorsSequence.forEach((selector, i) => {
        if (!selector) {
          return;
        }
        const element = queryShadowSelector(selector, document.documentElement, textMatchRegexp);
        if (!element) {
          return;
        }
        handleElement(element, i, selector);
        fulfilledSelectors.push(selector);
      });
      selectorsSequence = selectorsSequence.map((selector) => {
        return selector && fulfilledSelectors.includes(selector) ? null : selector;
      });
      return selectorsSequence;
    };
    const findElements = (mutations, observer) => {
      selectorsSequence = fulfillAndHandleSelectors();
      const allSelectorsFulfilled = selectorsSequence.every((selector) => selector === null);
      if (allSelectorsFulfilled) {
        observer.disconnect();
      }
    };
    const initializeMutationObserver = () => {
      const observer = new MutationObserver(throttle(findElements, THROTTLE_DELAY_MS));
      observer.observe(document.documentElement, {
        attributes: true,
        childList: true,
        subtree: true
      });
      setTimeout(() => observer.disconnect(), OBSERVER_TIMEOUT_MS);
    };
    const checkInitialElements = () => {
      const foundElements = selectorsSequence.every((selector) => {
        if (!selector) {
          return false;
        }
        const element = queryShadowSelector(selector, document.documentElement, textMatchRegexp);
        return !!element;
      });
      if (foundElements) {
        fulfillAndHandleSelectors();
      } else {
        initializeMutationObserver();
      }
    };
    checkInitialElements();
    if (parsedDelay) {
      setTimeout(() => {
        clickElementsBySequence();
        canClick = true;
      }, parsedDelay);
    }
  }
  var trustedClickElementNames = [
    "trusted-click-element"
    // trusted scriptlets support no aliases
  ];
  trustedClickElement.primaryName = trustedClickElementNames[0];
  trustedClickElement.injections = [
    hit,
    toRegExp,
    parseCookieString,
    throttle,
    logMessage,
    parseMatchArg,
    queryShadowSelector,
    doesElementContainText,
    findElementWithText
  ];

  // src/scriptlets/abort-on-property-read.js
  function abortOnPropertyRead(source, property) {
    if (!property) {
      return;
    }
    const rid = randomId();
    const abort = () => {
      hit(source);
      throw new ReferenceError(rid);
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
      setPropertyAccess(base, prop, {
        get: abort,
        set: () => {
        }
      });
    };
    setChainPropAccess(window, property);
    window.onerror = createOnErrorHandler(rid).bind();
  }
  var abortOnPropertyReadNames = [
    "abort-on-property-read",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "abort-on-property-read.js",
    "ubo-abort-on-property-read.js",
    "aopr.js",
    "ubo-aopr.js",
    "ubo-abort-on-property-read",
    "ubo-aopr",
    "abp-abort-on-property-read"
  ];
  abortOnPropertyRead.primaryName = abortOnPropertyReadNames[0];
  abortOnPropertyRead.injections = [
    randomId,
    setPropertyAccess,
    getPropertyInChain,
    createOnErrorHandler,
    hit,
    isEmptyObject
  ];

  // src/scriptlets/abort-on-property-write.js
  function abortOnPropertyWrite(source, property) {
    if (!property) {
      return;
    }
    const rid = randomId();
    const abort = () => {
      hit(source);
      throw new ReferenceError(rid);
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
      setPropertyAccess(base, prop, { set: abort });
    };
    setChainPropAccess(window, property);
    window.onerror = createOnErrorHandler(rid).bind();
  }
  var abortOnPropertyWriteNames = [
    "abort-on-property-write",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "abort-on-property-write.js",
    "ubo-abort-on-property-write.js",
    "aopw.js",
    "ubo-aopw.js",
    "ubo-abort-on-property-write",
    "ubo-aopw",
    "abp-abort-on-property-write"
  ];
  abortOnPropertyWrite.primaryName = abortOnPropertyWriteNames[0];
  abortOnPropertyWrite.injections = [
    randomId,
    setPropertyAccess,
    getPropertyInChain,
    createOnErrorHandler,
    hit,
    isEmptyObject
  ];

  // src/scriptlets/prevent-setTimeout.js
  function preventSetTimeout(source, matchCallback, matchDelay) {
    const shouldLog = typeof matchCallback === "undefined" && typeof matchDelay === "undefined";
    const handlerWrapper = (target, thisArg, args) => {
      const callback = args[0];
      const delay = args[1];
      let shouldPrevent = false;
      if (shouldLog) {
        hit(source);
        logMessage(source, `setTimeout(${String(callback)}, ${delay})`, true);
      } else {
        shouldPrevent = isPreventionNeeded({
          callback,
          delay,
          matchCallback,
          matchDelay
        });
      }
      if (shouldPrevent) {
        hit(source);
        args[0] = noopFunc;
      }
      return target.apply(thisArg, args);
    };
    const setTimeoutHandler = {
      apply: handlerWrapper
    };
    window.setTimeout = new Proxy(window.setTimeout, setTimeoutHandler);
  }
  var preventSetTimeoutNames = [
    "prevent-setTimeout",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "no-setTimeout-if.js",
    // new implementation of setTimeout-defuser.js
    "ubo-no-setTimeout-if.js",
    "nostif.js",
    // new short name of no-setTimeout-if
    "ubo-nostif.js",
    "ubo-no-setTimeout-if",
    "ubo-nostif",
    // old scriptlet names which should be supported as well.
    // should be removed eventually.
    // do not remove until other filter lists maintainers use them
    "setTimeout-defuser.js",
    "ubo-setTimeout-defuser.js",
    "ubo-setTimeout-defuser",
    "std.js",
    "ubo-std.js",
    "ubo-std"
  ];
  preventSetTimeout.primaryName = preventSetTimeoutNames[0];
  preventSetTimeout.injections = [
    hit,
    noopFunc,
    isPreventionNeeded,
    logMessage,
    // following helpers should be injected as helpers above use them
    parseMatchArg,
    parseDelayArg,
    toRegExp,
    nativeIsNaN,
    isValidCallback,
    isValidMatchStr,
    escapeRegExp,
    isValidStrPattern,
    nativeIsFinite,
    isValidMatchNumber,
    parseRawDelay
  ];

  // src/scriptlets/prevent-setInterval.js
  function preventSetInterval(source, matchCallback, matchDelay) {
    const shouldLog = typeof matchCallback === "undefined" && typeof matchDelay === "undefined";
    const handlerWrapper = (target, thisArg, args) => {
      const callback = args[0];
      const delay = args[1];
      let shouldPrevent = false;
      if (shouldLog) {
        hit(source);
        logMessage(source, `setInterval(${String(callback)}, ${delay})`, true);
      } else {
        shouldPrevent = isPreventionNeeded({
          callback,
          delay,
          matchCallback,
          matchDelay
        });
      }
      if (shouldPrevent) {
        hit(source);
        args[0] = noopFunc;
      }
      return target.apply(thisArg, args);
    };
    const setIntervalHandler = {
      apply: handlerWrapper
    };
    window.setInterval = new Proxy(window.setInterval, setIntervalHandler);
  }
  var preventSetIntervalNames = [
    "prevent-setInterval",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "no-setInterval-if.js",
    // new implementation of setInterval-defuser.js
    "ubo-no-setInterval-if.js",
    "setInterval-defuser.js",
    // old name should be supported as well
    "ubo-setInterval-defuser.js",
    "nosiif.js",
    // new short name of no-setInterval-if
    "ubo-nosiif.js",
    "sid.js",
    // old short scriptlet name
    "ubo-sid.js",
    "ubo-no-setInterval-if",
    "ubo-setInterval-defuser",
    "ubo-nosiif",
    "ubo-sid"
  ];
  preventSetInterval.primaryName = preventSetIntervalNames[0];
  preventSetInterval.injections = [
    hit,
    noopFunc,
    isPreventionNeeded,
    logMessage,
    // following helpers should be injected as helpers above use them
    toRegExp,
    nativeIsNaN,
    parseMatchArg,
    parseDelayArg,
    isValidCallback,
    isValidMatchStr,
    isValidStrPattern,
    escapeRegExp,
    nativeIsFinite,
    isValidMatchNumber,
    parseRawDelay
  ];

  // src/scriptlets/prevent-window-open.js
  function preventWindowOpen(source, match = "*", delay, replacement) {
    const nativeOpen = window.open;
    const isNewSyntax = match !== "0" && match !== "1";
    const oldOpenWrapper = (str, ...args) => {
      match = Number(match) > 0;
      if (!isValidStrPattern(delay)) {
        logMessage(source, `Invalid parameter: ${delay}`);
        return nativeOpen.apply(window, [str, ...args]);
      }
      const searchRegexp = toRegExp(delay);
      if (match !== searchRegexp.test(str)) {
        return nativeOpen.apply(window, [str, ...args]);
      }
      hit(source);
      return handleOldReplacement(replacement);
    };
    const newOpenWrapper = (url, ...args) => {
      const shouldLog = replacement && replacement.includes("log");
      if (shouldLog) {
        const argsStr = args && args.length > 0 ? `, ${args.join(", ")}` : "";
        const message = `${url}${argsStr}`;
        logMessage(source, message, true);
        hit(source);
      }
      let shouldPrevent = false;
      if (match === "*") {
        shouldPrevent = true;
      } else if (isValidMatchStr(match)) {
        const { isInvertedMatch, matchRegexp } = parseMatchArg(match);
        shouldPrevent = matchRegexp.test(url) !== isInvertedMatch;
      } else {
        logMessage(source, `Invalid parameter: ${match}`);
        shouldPrevent = false;
      }
      if (shouldPrevent) {
        const parsedDelay = parseInt(delay, 10);
        let result;
        if (nativeIsNaN(parsedDelay)) {
          result = noopNull();
        } else {
          const decoyArgs = { replacement, url, delay: parsedDelay };
          const decoy = createDecoy(decoyArgs);
          let popup = decoy.contentWindow;
          if (typeof popup === "object" && popup !== null) {
            Object.defineProperty(popup, "closed", { value: false });
            Object.defineProperty(popup, "opener", { value: window });
            Object.defineProperty(popup, "frameElement", { value: null });
          } else {
            const nativeGetter = decoy.contentWindow && decoy.contentWindow.get;
            Object.defineProperty(decoy, "contentWindow", {
              get: getPreventGetter(nativeGetter)
            });
            popup = decoy.contentWindow;
          }
          result = popup;
        }
        hit(source);
        return result;
      }
      return nativeOpen.apply(window, [url, ...args]);
    };
    window.open = isNewSyntax ? newOpenWrapper : oldOpenWrapper;
    window.open.toString = nativeOpen.toString.bind(nativeOpen);
  }
  var preventWindowOpenNames = [
    "prevent-window-open",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "window.open-defuser.js",
    "ubo-window.open-defuser.js",
    "ubo-window.open-defuser",
    "nowoif.js",
    "ubo-nowoif.js",
    "ubo-nowoif",
    "no-window-open-if.js",
    "ubo-no-window-open-if.js",
    "ubo-no-window-open-if"
  ];
  preventWindowOpen.primaryName = preventWindowOpenNames[0];
  preventWindowOpen.injections = [
    hit,
    isValidStrPattern,
    escapeRegExp,
    isValidMatchStr,
    toRegExp,
    nativeIsNaN,
    parseMatchArg,
    handleOldReplacement,
    createDecoy,
    getPreventGetter,
    noopNull,
    logMessage,
    noopFunc,
    trueFunc,
    substringBefore,
    substringAfter
  ];

  // src/scriptlets/abort-current-inline-script.js
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

  // src/scriptlets/set-constant.js
  function setConstant(source, property, value, stack = "", valueWrapper = "", setProxyTrap = false) {
    const uboAliases = [
      "set-constant.js",
      "ubo-set-constant.js",
      "set.js",
      "ubo-set.js",
      "ubo-set-constant",
      "ubo-set"
    ];
    if (uboAliases.includes(source.name)) {
      if (stack.length !== 1 && !getNumberFromString(stack)) {
        valueWrapper = stack;
      }
      stack = void 0;
    }
    if (!property || !matchStackTrace(stack, new Error().stack)) {
      return;
    }
    let isProxyTrapSet = false;
    const emptyArr = noopArray();
    const emptyObj = noopObject();
    let constantValue;
    if (value === "undefined") {
      constantValue = void 0;
    } else if (value === "false") {
      constantValue = false;
    } else if (value === "true") {
      constantValue = true;
    } else if (value === "null") {
      constantValue = null;
    } else if (value === "emptyArr") {
      constantValue = emptyArr;
    } else if (value === "emptyObj") {
      constantValue = emptyObj;
    } else if (value === "noopFunc") {
      constantValue = noopFunc;
    } else if (value === "noopCallbackFunc") {
      constantValue = noopCallbackFunc;
    } else if (value === "trueFunc") {
      constantValue = trueFunc;
    } else if (value === "falseFunc") {
      constantValue = falseFunc;
    } else if (value === "throwFunc") {
      constantValue = throwFunc;
    } else if (value === "noopPromiseResolve") {
      constantValue = noopPromiseResolve;
    } else if (value === "noopPromiseReject") {
      constantValue = noopPromiseReject;
    } else if (/^\d+$/.test(value)) {
      constantValue = parseFloat(value);
      if (nativeIsNaN(constantValue)) {
        return;
      }
      if (Math.abs(constantValue) > 32767) {
        return;
      }
    } else if (value === "-1") {
      constantValue = -1;
    } else if (value === "") {
      constantValue = "";
    } else if (value === "yes") {
      constantValue = "yes";
    } else if (value === "no") {
      constantValue = "no";
    } else {
      return;
    }
    const valueWrapperNames = [
      "asFunction",
      "asCallback",
      "asResolved",
      "asRejected"
    ];
    if (valueWrapperNames.includes(valueWrapper)) {
      const valueWrappersMap = {
        asFunction(v) {
          return () => v;
        },
        asCallback(v) {
          return () => () => v;
        },
        asResolved(v) {
          return Promise.resolve(v);
        },
        asRejected(v) {
          return Promise.reject(v);
        }
      };
      constantValue = valueWrappersMap[valueWrapper](constantValue);
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
        if (base[prop]) {
          base[prop] = constantValue;
        }
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
          if (a instanceof Object) {
            const propertiesToCheck = property.split(".").slice(1);
            if (setProxyTrap && !isProxyTrapSet) {
              isProxyTrapSet = true;
              a = new Proxy(a, {
                get: (target, propertyKey, val) => {
                  propertiesToCheck.reduce((object, currentProp, index, array) => {
                    const currentObj = object?.[currentProp];
                    if (index === array.length - 1 && currentObj !== constantValue) {
                      object[currentProp] = constantValue;
                    }
                    return currentObj || object;
                  }, target);
                  return Reflect.get(target, propertyKey, val);
                }
              });
            }
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
  var setConstantNames = [
    "set-constant",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "set-constant.js",
    "ubo-set-constant.js",
    "set.js",
    "ubo-set.js",
    "ubo-set-constant",
    "ubo-set",
    "abp-override-property-read"
  ];
  setConstant.primaryName = setConstantNames[0];
  setConstant.injections = [
    hit,
    logMessage,
    getNumberFromString,
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
    matchStackTrace,
    nativeIsNaN,
    isEmptyObject,
    // following helpers should be imported and injected
    // because they are used by helpers above
    shouldAbortInlineOrInjectedScript,
    getNativeRegexpTest,
    setPropertyAccess,
    toRegExp,
    backupRegExpValues,
    restoreRegExpValues
  ];

  // src/scriptlets/remove-cookie.js
  function removeCookie(source, match) {
    const matchRegexp = toRegExp(match);
    const removeCookieFromHost = (cookieName, hostName) => {
      const cookieSpec = `${cookieName}=`;
      const domain1 = `; domain=${hostName}`;
      const domain2 = `; domain=.${hostName}`;
      const path = "; path=/";
      const expiration = "; expires=Thu, 01 Jan 1970 00:00:00 GMT";
      document.cookie = cookieSpec + expiration;
      document.cookie = cookieSpec + domain1 + expiration;
      document.cookie = cookieSpec + domain2 + expiration;
      document.cookie = cookieSpec + path + expiration;
      document.cookie = cookieSpec + domain1 + path + expiration;
      document.cookie = cookieSpec + domain2 + path + expiration;
      hit(source);
    };
    const rmCookie = () => {
      document.cookie.split(";").forEach((cookieStr) => {
        const pos = cookieStr.indexOf("=");
        if (pos === -1) {
          return;
        }
        const cookieName = cookieStr.slice(0, pos).trim();
        if (!matchRegexp.test(cookieName)) {
          return;
        }
        const hostParts = document.location.hostname.split(".");
        for (let i = 0; i <= hostParts.length - 1; i += 1) {
          const hostName = hostParts.slice(i).join(".");
          if (hostName) {
            removeCookieFromHost(cookieName, hostName);
          }
        }
      });
    };
    rmCookie();
    window.addEventListener("beforeunload", rmCookie);
  }
  var removeCookieNames = [
    "remove-cookie",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "cookie-remover.js",
    "ubo-cookie-remover.js",
    "ubo-cookie-remover",
    "remove-cookie.js",
    "ubo-remove-cookie.js",
    "ubo-remove-cookie",
    "abp-cookie-remover"
  ];
  removeCookie.primaryName = removeCookieNames[0];
  removeCookie.injections = [toRegExp, hit];

  // src/scriptlets/prevent-addEventListener.js
  function preventAddEventListener(source, typeSearch, listenerSearch) {
    const typeSearchRegexp = toRegExp(typeSearch);
    const listenerSearchRegexp = toRegExp(listenerSearch);
    const nativeAddEventListener = window.EventTarget.prototype.addEventListener;
    function addEventListenerWrapper(type, listener, ...args) {
      let shouldPrevent = false;
      if (validateType(type) && validateListener(listener)) {
        shouldPrevent = typeSearchRegexp.test(type.toString()) && listenerSearchRegexp.test(listenerToString(listener));
      }
      if (shouldPrevent) {
        hit(source);
        return void 0;
      }
      let context = this;
      if (this && this.constructor?.name === "Window" && this !== window) {
        context = window;
      }
      return nativeAddEventListener.apply(context, [type, listener, ...args]);
    }
    const descriptor = {
      configurable: true,
      set: () => {
      },
      get: () => addEventListenerWrapper
    };
    Object.defineProperty(window.EventTarget.prototype, "addEventListener", descriptor);
    Object.defineProperty(window, "addEventListener", descriptor);
    Object.defineProperty(document, "addEventListener", descriptor);
  }
  var preventAddEventListenerNames = [
    "prevent-addEventListener",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "addEventListener-defuser.js",
    "ubo-addEventListener-defuser.js",
    "aeld.js",
    "ubo-aeld.js",
    "ubo-addEventListener-defuser",
    "ubo-aeld",
    "abp-prevent-listener"
  ];
  preventAddEventListener.primaryName = preventAddEventListenerNames[0];
  preventAddEventListener.injections = [
    hit,
    toRegExp,
    validateType,
    validateListener,
    listenerToString
  ];

  // src/scriptlets/prevent-bab.js
  function preventBab(source) {
    const nativeSetTimeout = window.setTimeout;
    const babRegex = /\.bab_elementid.$/;
    const timeoutWrapper = (callback, ...args) => {
      if (typeof callback !== "string" || !babRegex.test(callback)) {
        return nativeSetTimeout.apply(window, [callback, ...args]);
      }
      hit(source);
    };
    window.setTimeout = timeoutWrapper;
    const signatures = [
      ["blockadblock"],
      ["babasbm"],
      [/getItem\('babn'\)/],
      [
        "getElementById",
        "String.fromCharCode",
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789",
        "charAt",
        "DOMContentLoaded",
        "AdBlock",
        "addEventListener",
        "doScroll",
        "fromCharCode",
        "<<2|r>>4",
        "sessionStorage",
        "clientWidth",
        "localStorage",
        "Math",
        "random"
      ]
    ];
    const check = (str) => {
      if (typeof str !== "string") {
        return false;
      }
      for (let i = 0; i < signatures.length; i += 1) {
        const tokens = signatures[i];
        let match = 0;
        for (let j = 0; j < tokens.length; j += 1) {
          const token = tokens[j];
          const found = token instanceof RegExp ? token.test(str) : str.includes(token);
          if (found) {
            match += 1;
          }
        }
        if (match / tokens.length >= 0.8) {
          return true;
        }
      }
      return false;
    };
    const nativeEval = window.eval;
    const evalWrapper = (str) => {
      if (!check(str)) {
        return nativeEval(str);
      }
      hit(source);
      const bodyEl = document.body;
      if (bodyEl) {
        bodyEl.style.removeProperty("visibility");
      }
      const el = document.getElementById("babasbmsgx");
      if (el) {
        el.parentNode.removeChild(el);
      }
    };
    window.eval = evalWrapper.bind(window);
    window.eval.toString = nativeEval.toString.bind(nativeEval);
  }
  var preventBabNames = [
    "prevent-bab"
    // there are no aliases for this scriptlet
  ];
  preventBab.primaryName = preventBabNames[0];
  preventBab.injections = [hit];

  // src/scriptlets/nowebrtc.js
  function nowebrtc(source) {
    let propertyName = "";
    if (window.RTCPeerConnection) {
      propertyName = "RTCPeerConnection";
    } else if (window.webkitRTCPeerConnection) {
      propertyName = "webkitRTCPeerConnection";
    }
    if (propertyName === "") {
      return;
    }
    const rtcReplacement = (config) => {
      const message = `Document tried to create an RTCPeerConnection: ${convertRtcConfigToString(config)}`;
      logMessage(source, message);
      hit(source);
    };
    rtcReplacement.prototype = {
      close: noopFunc,
      createDataChannel: noopFunc,
      createOffer: noopFunc,
      setRemoteDescription: noopFunc
    };
    const rtc = window[propertyName];
    window[propertyName] = rtcReplacement;
    if (rtc.prototype) {
      rtc.prototype.createDataChannel = function(a, b) {
        return {
          close: noopFunc,
          send: noopFunc
        };
      }.bind(null);
    }
  }
  var nowebrtcNames = [
    "nowebrtc",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "nowebrtc.js",
    "ubo-nowebrtc.js",
    "ubo-nowebrtc"
  ];
  nowebrtc.primaryName = nowebrtcNames[0];
  nowebrtc.injections = [
    hit,
    noopFunc,
    logMessage,
    convertRtcConfigToString
  ];

  // src/scriptlets/log-addEventListener.js
  function logAddEventListener(source) {
    const nativeAddEventListener = window.EventTarget.prototype.addEventListener;
    function addEventListenerWrapper(type, listener, ...args) {
      if (validateType(type) && validateListener(listener)) {
        const message = `addEventListener("${type}", ${listenerToString(listener)})`;
        logMessage(source, message, true);
        hit(source);
      } else {
        const message = `Invalid event type or listener passed to addEventListener:
        type: ${convertTypeToString(type)}
        listener: ${convertTypeToString(listener)}`;
        logMessage(source, message, true);
      }
      let context = this;
      if (this && this.constructor?.name === "Window" && this !== window) {
        context = window;
      }
      return nativeAddEventListener.apply(context, [type, listener, ...args]);
    }
    const descriptor = {
      configurable: true,
      set: () => {
      },
      get: () => addEventListenerWrapper
    };
    Object.defineProperty(window.EventTarget.prototype, "addEventListener", descriptor);
    Object.defineProperty(window, "addEventListener", descriptor);
    Object.defineProperty(document, "addEventListener", descriptor);
  }
  var logAddEventListenerNames = [
    "log-addEventListener",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "addEventListener-logger.js",
    "ubo-addEventListener-logger.js",
    "aell.js",
    "ubo-aell.js",
    "ubo-addEventListener-logger",
    "ubo-aell"
  ];
  logAddEventListener.primaryName = logAddEventListenerNames[0];
  logAddEventListener.injections = [
    hit,
    validateType,
    validateListener,
    listenerToString,
    convertTypeToString,
    logMessage,
    objectToString,
    isEmptyObject
  ];

  // src/scriptlets/log-eval.js
  function logEval(source) {
    const nativeEval = window.eval;
    function evalWrapper(str) {
      hit(source);
      logMessage(source, `eval("${str}")`, true);
      return nativeEval(str);
    }
    window.eval = evalWrapper;
    const nativeFunction = window.Function;
    function FunctionWrapper(...args) {
      hit(source);
      logMessage(source, `new Function(${args.join(", ")})`, true);
      return nativeFunction.apply(this, [...args]);
    }
    FunctionWrapper.prototype = Object.create(nativeFunction.prototype);
    FunctionWrapper.prototype.constructor = FunctionWrapper;
    window.Function = FunctionWrapper;
  }
  var logEvalNames = [
    "log-eval"
  ];
  logEval.primaryName = logEvalNames[0];
  logEval.injections = [hit, logMessage];

  // src/scriptlets/log.js
  function log(...args) {
    console.log(args);
  }
  var logNames = [
    "log",
    "abp-log"
  ];
  log.primaryName = logNames[0];

  // src/scriptlets/noeval.js
  function noeval(source) {
    window.eval = function evalWrapper(s) {
      hit(source);
      logMessage(source, `AdGuard has prevented eval:
${s}`, true);
    }.bind();
  }
  var noevalNames = [
    "noeval",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "noeval.js",
    "silent-noeval.js",
    "ubo-noeval.js",
    "ubo-silent-noeval.js",
    "ubo-noeval",
    "ubo-silent-noeval"
  ];
  noeval.primaryName = noevalNames[0];
  noeval.injections = [hit, logMessage];

  // src/scriptlets/prevent-eval-if.js
  function preventEvalIf(source, search) {
    const searchRegexp = toRegExp(search);
    const nativeEval = window.eval;
    window.eval = function(payload) {
      if (!searchRegexp.test(payload.toString())) {
        return nativeEval.call(window, payload);
      }
      hit(source, payload);
      return void 0;
    }.bind(window);
    window.eval.toString = nativeEval.toString.bind(nativeEval);
  }
  var preventEvalIfNames = [
    "prevent-eval-if",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "noeval-if.js",
    "ubo-noeval-if.js",
    "ubo-noeval-if"
  ];
  preventEvalIf.primaryName = preventEvalIfNames[0];
  preventEvalIf.injections = [toRegExp, hit];

  // src/scriptlets/prevent-fab-3.2.0.js
  function preventFab(source) {
    hit(source);
    const Fab = function() {
    };
    Fab.prototype.check = noopFunc;
    Fab.prototype.clearEvent = noopFunc;
    Fab.prototype.emitEvent = noopFunc;
    Fab.prototype.on = function(a, b) {
      if (!a) {
        b();
      }
      return this;
    };
    Fab.prototype.onDetected = noopThis;
    Fab.prototype.onNotDetected = function(a) {
      a();
      return this;
    };
    Fab.prototype.setOption = noopFunc;
    Fab.prototype.options = {
      set: noopFunc,
      get: noopFunc
    };
    const fab = new Fab();
    const getSetFab = {
      get() {
        return Fab;
      },
      set() {
      }
    };
    const getsetfab = {
      get() {
        return fab;
      },
      set() {
      }
    };
    if (Object.prototype.hasOwnProperty.call(window, "FuckAdBlock")) {
      window.FuckAdBlock = Fab;
    } else {
      Object.defineProperty(window, "FuckAdBlock", getSetFab);
    }
    if (Object.prototype.hasOwnProperty.call(window, "BlockAdBlock")) {
      window.BlockAdBlock = Fab;
    } else {
      Object.defineProperty(window, "BlockAdBlock", getSetFab);
    }
    if (Object.prototype.hasOwnProperty.call(window, "SniffAdBlock")) {
      window.SniffAdBlock = Fab;
    } else {
      Object.defineProperty(window, "SniffAdBlock", getSetFab);
    }
    if (Object.prototype.hasOwnProperty.call(window, "fuckAdBlock")) {
      window.fuckAdBlock = fab;
    } else {
      Object.defineProperty(window, "fuckAdBlock", getsetfab);
    }
    if (Object.prototype.hasOwnProperty.call(window, "blockAdBlock")) {
      window.blockAdBlock = fab;
    } else {
      Object.defineProperty(window, "blockAdBlock", getsetfab);
    }
    if (Object.prototype.hasOwnProperty.call(window, "sniffAdBlock")) {
      window.sniffAdBlock = fab;
    } else {
      Object.defineProperty(window, "sniffAdBlock", getsetfab);
    }
  }
  var preventFabNames = [
    "prevent-fab-3.2.0",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "nofab.js",
    "ubo-nofab.js",
    "fuckadblock.js-3.2.0",
    "ubo-fuckadblock.js-3.2.0",
    "ubo-nofab"
  ];
  preventFab.primaryName = preventFabNames[0];
  preventFab.injections = [hit, noopFunc, noopThis];

  // src/scriptlets/set-popads-dummy.js
  function setPopadsDummy(source) {
    delete window.PopAds;
    delete window.popns;
    Object.defineProperties(window, {
      PopAds: {
        get: () => {
          hit(source);
          return {};
        }
      },
      popns: {
        get: () => {
          hit(source);
          return {};
        }
      }
    });
  }
  var setPopadsDummyNames = [
    "set-popads-dummy",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "popads-dummy.js",
    "ubo-popads-dummy.js",
    "ubo-popads-dummy"
  ];
  setPopadsDummy.primaryName = setPopadsDummyNames[0];
  setPopadsDummy.injections = [hit];

  // src/scriptlets/prevent-popads-net.js
  function preventPopadsNet(source) {
    const rid = randomId();
    const throwError = () => {
      throw new ReferenceError(rid);
    };
    delete window.PopAds;
    delete window.popns;
    Object.defineProperties(window, {
      PopAds: { set: throwError },
      popns: { set: throwError }
    });
    window.onerror = createOnErrorHandler(rid).bind();
    hit(source);
  }
  var preventPopadsNetNames = [
    "prevent-popads-net",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "popads.net.js",
    "ubo-popads.net.js",
    "ubo-popads.net"
  ];
  preventPopadsNet.primaryName = preventPopadsNetNames[0];
  preventPopadsNet.injections = [createOnErrorHandler, randomId, hit];

  // src/scriptlets/prevent-adfly.js
  function preventAdfly(source) {
    const isDigit = (data) => /^\d$/.test(data);
    const handler = function(encodedURL) {
      let evenChars = "";
      let oddChars = "";
      for (let i = 0; i < encodedURL.length; i += 1) {
        if (i % 2 === 0) {
          evenChars += encodedURL.charAt(i);
        } else {
          oddChars = encodedURL.charAt(i) + oddChars;
        }
      }
      let data = (evenChars + oddChars).split("");
      for (let i = 0; i < data.length; i += 1) {
        if (isDigit(data[i])) {
          for (let ii = i + 1; ii < data.length; ii += 1) {
            if (isDigit(data[ii])) {
              const temp = parseInt(data[i], 10) ^ parseInt(data[ii], 10);
              if (temp < 10) {
                data[i] = temp.toString();
              }
              i = ii;
              break;
            }
          }
        }
      }
      data = data.join("");
      const decodedURL = window.atob(data).slice(16, -16);
      if (window.stop) {
        window.stop();
      }
      window.onbeforeunload = null;
      window.location.href = decodedURL;
    };
    let val;
    let applyHandler = true;
    const result = setPropertyAccess(window, "ysmm", {
      configurable: false,
      set: (value) => {
        if (applyHandler) {
          applyHandler = false;
          try {
            if (typeof value === "string") {
              handler(value);
            }
          } catch (err) {
          }
        }
        val = value;
      },
      get: () => val
    });
    if (result) {
      hit(source);
    } else {
      logMessage(source, "Failed to set up prevent-adfly scriptlet");
    }
  }
  var preventAdflyNames = [
    "prevent-adfly"
    // there are no aliases for this scriptlet
  ];
  preventAdfly.primaryName = preventAdflyNames[0];
  preventAdfly.injections = [
    setPropertyAccess,
    hit,
    logMessage
  ];

  // src/scriptlets/debug-on-property-read.js
  function debugOnPropertyRead(source, property) {
    if (!property) {
      return;
    }
    const rid = randomId();
    const abort = () => {
      hit(source);
      debugger;
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
      setPropertyAccess(base, prop, {
        get: abort,
        set: noopFunc
      });
    };
    setChainPropAccess(window, property);
    window.onerror = createOnErrorHandler(rid).bind();
  }
  var debugOnPropertyReadNames = [
    "debug-on-property-read"
  ];
  debugOnPropertyRead.primaryName = debugOnPropertyReadNames[0];
  debugOnPropertyRead.injections = [
    randomId,
    setPropertyAccess,
    getPropertyInChain,
    createOnErrorHandler,
    hit,
    noopFunc,
    isEmptyObject
  ];

  // src/scriptlets/debug-on-property-write.js
  function debugOnPropertyWrite(source, property) {
    if (!property) {
      return;
    }
    const rid = randomId();
    const abort = () => {
      hit(source);
      debugger;
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
      setPropertyAccess(base, prop, { set: abort });
    };
    setChainPropAccess(window, property);
    window.onerror = createOnErrorHandler(rid).bind();
  }
  var debugOnPropertyWriteNames = [
    "debug-on-property-write"
  ];
  debugOnPropertyWrite.primaryName = debugOnPropertyWriteNames[0];
  debugOnPropertyWrite.injections = [
    randomId,
    setPropertyAccess,
    getPropertyInChain,
    createOnErrorHandler,
    hit,
    isEmptyObject
  ];

  // src/scriptlets/debug-current-inline-script.js
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

  // src/scriptlets/remove-attr.js
  function removeAttr(source, attrs, selector, applying = "asap stay") {
    if (!attrs) {
      return;
    }
    attrs = attrs.split(/\s*\|\s*/);
    if (!selector) {
      selector = `[${attrs.join("],[")}]`;
    }
    const rmattr = () => {
      let nodes = [];
      try {
        nodes = [].slice.call(document.querySelectorAll(selector));
      } catch (e) {
        logMessage(source, `Invalid selector arg: '${selector}'`);
      }
      let removed = false;
      nodes.forEach((node) => {
        attrs.forEach((attr) => {
          node.removeAttribute(attr);
          removed = true;
        });
      });
      if (removed) {
        hit(source);
      }
    };
    const flags = parseFlags(applying);
    const run = () => {
      rmattr();
      if (!flags.hasFlag(flags.STAY)) {
        return;
      }
      observeDOMChanges(rmattr, true);
    };
    if (flags.hasFlag(flags.ASAP)) {
      if (document.readyState === "loading") {
        window.addEventListener("DOMContentLoaded", rmattr, { once: true });
      } else {
        rmattr();
      }
    }
    if (document.readyState !== "complete" && flags.hasFlag(flags.COMPLETE)) {
      window.addEventListener("load", run, { once: true });
    } else if (flags.hasFlag(flags.STAY)) {
      if (!applying.includes(" ")) {
        rmattr();
      }
      observeDOMChanges(rmattr, true);
    }
  }
  var removeAttrNames = [
    "remove-attr",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "remove-attr.js",
    "ubo-remove-attr.js",
    "ra.js",
    "ubo-ra.js",
    "ubo-remove-attr",
    "ubo-ra"
  ];
  removeAttr.primaryName = removeAttrNames[0];
  removeAttr.injections = [
    hit,
    observeDOMChanges,
    parseFlags,
    logMessage,
    // following helpers should be imported and injected
    // because they are used by helpers above
    throttle
  ];

  // src/scriptlets/set-attr.js
  function setAttr(source, selector, attr, value = "") {
    if (!selector || !attr) {
      return;
    }
    const allowedValues = ["true", "false"];
    const shouldCopyValue = value.startsWith("[") && value.endsWith("]");
    const isValidValue = value.length === 0 || !nativeIsNaN(parseInt(value, 10)) && parseInt(value, 10) >= 0 && parseInt(value, 10) <= 32767 || allowedValues.includes(value.toLowerCase());
    if (!shouldCopyValue && !isValidValue) {
      logMessage(source, `Invalid attribute value provided: '${convertTypeToString(value)}'`);
      return;
    }
    let attributeHandler;
    if (shouldCopyValue) {
      attributeHandler = (elem, attr2, value2) => {
        const valueToCopy = elem.getAttribute(value2.slice(1, -1));
        if (valueToCopy === null) {
          logMessage(source, `No element attribute found to copy value from: ${value2}`);
        }
        elem.setAttribute(attr2, valueToCopy);
      };
    }
    setAttributeBySelector(source, selector, attr, value, attributeHandler);
    observeDOMChanges(() => setAttributeBySelector(source, selector, attr, value, attributeHandler), true);
  }
  var setAttrNames = [
    "set-attr",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "set-attr.js",
    "ubo-set-attr.js",
    "ubo-set-attr"
  ];
  setAttr.primaryName = setAttrNames[0];
  setAttr.injections = [
    setAttributeBySelector,
    observeDOMChanges,
    nativeIsNaN,
    convertTypeToString,
    // following helpers should be imported and injected
    // because they are used by helpers above
    defaultAttributeSetter,
    logMessage,
    throttle,
    hit
  ];

  // src/scriptlets/remove-class.js
  function removeClass(source, classNames, selector, applying = "asap stay") {
    if (!classNames) {
      return;
    }
    classNames = classNames.split(/\s*\|\s*/);
    let selectors = [];
    if (!selector) {
      selectors = classNames.map((className) => {
        return `.${className}`;
      });
    }
    const removeClassHandler = () => {
      const nodes = /* @__PURE__ */ new Set();
      if (selector) {
        let foundNodes = [];
        try {
          foundNodes = [].slice.call(document.querySelectorAll(selector));
        } catch (e) {
          logMessage(source, `Invalid selector arg: '${selector}'`);
        }
        foundNodes.forEach((n) => nodes.add(n));
      } else if (selectors.length > 0) {
        selectors.forEach((s) => {
          const elements = document.querySelectorAll(s);
          for (let i = 0; i < elements.length; i += 1) {
            const element = elements[i];
            nodes.add(element);
          }
        });
      }
      let removed = false;
      nodes.forEach((node) => {
        classNames.forEach((className) => {
          if (node.classList.contains(className)) {
            node.classList.remove(className);
            removed = true;
          }
        });
      });
      if (removed) {
        hit(source);
      }
    };
    const CLASS_ATTR_NAME = ["class"];
    const flags = parseFlags(applying);
    const run = () => {
      removeClassHandler();
      if (!flags.hasFlag(flags.STAY)) {
        return;
      }
      observeDOMChanges(removeClassHandler, true, CLASS_ATTR_NAME);
    };
    if (flags.hasFlag(flags.ASAP)) {
      if (document.readyState === "loading") {
        window.addEventListener("DOMContentLoaded", removeClassHandler, { once: true });
      } else {
        removeClassHandler();
      }
    }
    if (document.readyState !== "complete" && flags.hasFlag(flags.COMPLETE)) {
      window.addEventListener("load", run, { once: true });
    } else if (flags.hasFlag(flags.STAY)) {
      if (!applying.includes(" ")) {
        removeClassHandler();
      }
      observeDOMChanges(removeClassHandler, true, CLASS_ATTR_NAME);
    }
  }
  var removeClassNames = [
    "remove-class",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "remove-class.js",
    "ubo-remove-class.js",
    "rc.js",
    "ubo-rc.js",
    "ubo-remove-class",
    "ubo-rc"
  ];
  removeClass.primaryName = removeClassNames[0];
  removeClass.injections = [
    hit,
    logMessage,
    observeDOMChanges,
    parseFlags,
    // following helpers should be imported and injected
    // because they are used by helpers above
    throttle
  ];

  // src/scriptlets/disable-newtab-links.js
  function disableNewtabLinks(source) {
    document.addEventListener("click", (ev) => {
      let { target } = ev;
      while (target !== null) {
        if (target.localName === "a" && target.hasAttribute("target")) {
          ev.stopPropagation();
          ev.preventDefault();
          hit(source);
          break;
        }
        target = target.parentNode;
      }
    });
  }
  var disableNewtabLinksNames = [
    "disable-newtab-links",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "disable-newtab-links.js",
    "ubo-disable-newtab-links.js",
    "ubo-disable-newtab-links"
  ];
  disableNewtabLinks.primaryName = disableNewtabLinksNames[0];
  disableNewtabLinks.injections = [
    hit
  ];

  // src/scriptlets/adjust-setInterval.js
  function adjustSetInterval(source, matchCallback, matchDelay, boost) {
    const nativeSetInterval = window.setInterval;
    const matchRegexp = toRegExp(matchCallback);
    const intervalWrapper = (callback, delay, ...args) => {
      if (!isValidCallback(callback)) {
        const message = `Scriptlet can't be applied because of invalid callback: '${String(callback)}'`;
        logMessage(source, message);
      } else if (matchRegexp.test(callback.toString()) && isDelayMatched(matchDelay, delay)) {
        delay *= getBoostMultiplier(boost);
        hit(source);
      }
      return nativeSetInterval.apply(window, [callback, delay, ...args]);
    };
    window.setInterval = intervalWrapper;
  }
  var adjustSetIntervalNames = [
    "adjust-setInterval",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "nano-setInterval-booster.js",
    "ubo-nano-setInterval-booster.js",
    "nano-sib.js",
    "ubo-nano-sib.js",
    "adjust-setInterval.js",
    "ubo-adjust-setInterval.js",
    "ubo-nano-setInterval-booster",
    "ubo-nano-sib",
    "ubo-adjust-setInterval"
  ];
  adjustSetInterval.primaryName = adjustSetIntervalNames[0];
  adjustSetInterval.injections = [
    hit,
    isValidCallback,
    toRegExp,
    getBoostMultiplier,
    isDelayMatched,
    logMessage,
    // following helpers should be injected as helpers above use them
    nativeIsNaN,
    nativeIsFinite,
    getMatchDelay,
    shouldMatchAnyDelay
  ];

  // src/scriptlets/adjust-setTimeout.js
  function adjustSetTimeout(source, matchCallback, matchDelay, boost) {
    const nativeSetTimeout = window.setTimeout;
    const matchRegexp = toRegExp(matchCallback);
    const timeoutWrapper = (callback, delay, ...args) => {
      if (!isValidCallback(callback)) {
        const message = `Scriptlet can't be applied because of invalid callback: '${String(callback)}'`;
        logMessage(source, message);
      } else if (matchRegexp.test(callback.toString()) && isDelayMatched(matchDelay, delay)) {
        delay *= getBoostMultiplier(boost);
        hit(source);
      }
      return nativeSetTimeout.apply(window, [callback, delay, ...args]);
    };
    window.setTimeout = timeoutWrapper;
  }
  var adjustSetTimeoutNames = [
    "adjust-setTimeout",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "adjust-setTimeout.js",
    "ubo-adjust-setTimeout.js",
    "nano-setTimeout-booster.js",
    "ubo-nano-setTimeout-booster.js",
    "nano-stb.js",
    "ubo-nano-stb.js",
    "ubo-adjust-setTimeout",
    "ubo-nano-setTimeout-booster",
    "ubo-nano-stb"
  ];
  adjustSetTimeout.primaryName = adjustSetTimeoutNames[0];
  adjustSetTimeout.injections = [
    hit,
    isValidCallback,
    toRegExp,
    getBoostMultiplier,
    isDelayMatched,
    logMessage,
    // following helpers should be injected as helpers above use them
    nativeIsNaN,
    nativeIsFinite,
    getMatchDelay,
    shouldMatchAnyDelay
  ];

  // src/scriptlets/dir-string.js
  function dirString(source, times) {
    const { dir } = console;
    times = parseInt(times, 10);
    function dirWrapper(object) {
      let temp;
      for (let i = 0; i < times; i += 1) {
        temp = `${object}`;
      }
      if (typeof dir === "function") {
        dir.call(this, object);
      }
      hit(source, temp);
    }
    console.dir = dirWrapper;
  }
  var dirStringNames = [
    "dir-string"
  ];
  dirString.primaryName = dirStringNames[0];
  dirString.injections = [hit];

  // src/scriptlets/json-prune.js
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

  // src/scriptlets/prevent-requestAnimationFrame.js
  function preventRequestAnimationFrame(source, match) {
    const nativeRequestAnimationFrame = window.requestAnimationFrame;
    const shouldLog = typeof match === "undefined";
    const { isInvertedMatch, matchRegexp } = parseMatchArg(match);
    const rafWrapper = (callback, ...args) => {
      let shouldPrevent = false;
      if (shouldLog) {
        hit(source);
        logMessage(source, `requestAnimationFrame(${String(callback)})`, true);
      } else if (isValidCallback(callback) && isValidStrPattern(match)) {
        shouldPrevent = matchRegexp.test(callback.toString()) !== isInvertedMatch;
      }
      if (shouldPrevent) {
        hit(source);
        return nativeRequestAnimationFrame(noopFunc);
      }
      return nativeRequestAnimationFrame.apply(window, [callback, ...args]);
    };
    window.requestAnimationFrame = rafWrapper;
  }
  var preventRequestAnimationFrameNames = [
    "prevent-requestAnimationFrame",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "no-requestAnimationFrame-if.js",
    "ubo-no-requestAnimationFrame-if.js",
    "norafif.js",
    "ubo-norafif.js",
    "ubo-no-requestAnimationFrame-if",
    "ubo-norafif"
  ];
  preventRequestAnimationFrame.primaryName = preventRequestAnimationFrameNames[0];
  preventRequestAnimationFrame.injections = [
    hit,
    noopFunc,
    parseMatchArg,
    isValidStrPattern,
    isValidCallback,
    logMessage,
    // following helpers should be injected as helpers above use them
    escapeRegExp,
    toRegExp
  ];

  // src/scriptlets/set-cookie.js
  function setCookie(source, name, value, path = "/", domain = "") {
    const validValue = getLimitedCookieValue(value);
    if (validValue === null) {
      logMessage(source, `Invalid cookie value: '${validValue}'`);
      return;
    }
    if (!isValidCookiePath(path)) {
      logMessage(source, `Invalid cookie path: '${path}'`);
      return;
    }
    if (!document.location.origin.includes(domain)) {
      logMessage(source, `Cookie domain not matched by origin: '${domain}'`);
      return;
    }
    const cookieToSet = serializeCookie(name, validValue, path, domain);
    if (!cookieToSet) {
      logMessage(source, "Invalid cookie name or value");
      return;
    }
    hit(source);
    document.cookie = cookieToSet;
  }
  var setCookieNames = [
    "set-cookie",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "set-cookie.js",
    "ubo-set-cookie.js",
    "ubo-set-cookie"
  ];
  setCookie.primaryName = setCookieNames[0];
  setCookie.injections = [
    hit,
    logMessage,
    nativeIsNaN,
    isCookieSetWithValue,
    getLimitedCookieValue,
    serializeCookie,
    isValidCookiePath,
    getCookiePath
  ];

  // src/scriptlets/set-cookie-reload.js
  function setCookieReload(source, name, value, path = "/", domain = "") {
    if (isCookieSetWithValue(document.cookie, name, value)) {
      return;
    }
    const validValue = getLimitedCookieValue(value);
    if (validValue === null) {
      logMessage(source, `Invalid cookie value: '${value}'`);
      return;
    }
    if (!isValidCookiePath(path)) {
      logMessage(source, `Invalid cookie path: '${path}'`);
      return;
    }
    if (!document.location.origin.includes(domain)) {
      logMessage(source, `Cookie domain not matched by origin: '${domain}'`);
      return;
    }
    const cookieToSet = serializeCookie(name, validValue, path, domain);
    if (!cookieToSet) {
      logMessage(source, "Invalid cookie name or value");
      return;
    }
    document.cookie = cookieToSet;
    hit(source);
    if (isCookieSetWithValue(document.cookie, name, value)) {
      window.location.reload();
    }
  }
  var setCookieReloadNames = [
    "set-cookie-reload",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "set-cookie-reload.js",
    "ubo-set-cookie-reload.js",
    "ubo-set-cookie-reload"
  ];
  setCookieReload.primaryName = setCookieReloadNames[0];
  setCookieReload.injections = [
    hit,
    logMessage,
    nativeIsNaN,
    isCookieSetWithValue,
    getLimitedCookieValue,
    serializeCookie,
    isValidCookiePath,
    getCookiePath
  ];

  // src/scriptlets/hide-in-shadow-dom.js
  function hideInShadowDom(source, selector, baseSelector) {
    if (!Element.prototype.attachShadow) {
      return;
    }
    const hideElement = (targetElement) => {
      const DISPLAY_NONE_CSS = "display:none!important;";
      targetElement.style.cssText = DISPLAY_NONE_CSS;
    };
    const hideHandler = () => {
      let hostElements = !baseSelector ? findHostElements(document.documentElement) : document.querySelectorAll(baseSelector);
      while (hostElements.length !== 0) {
        let isHidden = false;
        const { targets, innerHosts } = pierceShadowDom(selector, hostElements);
        targets.forEach((targetEl) => {
          hideElement(targetEl);
          isHidden = true;
        });
        if (isHidden) {
          hit(source);
        }
        hostElements = innerHosts;
      }
    };
    hideHandler();
    observeDOMChanges(hideHandler, true);
  }
  var hideInShadowDomNames = [
    "hide-in-shadow-dom"
  ];
  hideInShadowDom.primaryName = hideInShadowDomNames[0];
  hideInShadowDom.injections = [
    hit,
    observeDOMChanges,
    findHostElements,
    pierceShadowDom,
    // following helpers should be imported and injected
    // because they are used by helpers above
    flatten,
    throttle
  ];

  // src/scriptlets/remove-in-shadow-dom.js
  function removeInShadowDom(source, selector, baseSelector) {
    if (!Element.prototype.attachShadow) {
      return;
    }
    const removeElement = (targetElement) => {
      targetElement.remove();
    };
    const removeHandler = () => {
      let hostElements = !baseSelector ? findHostElements(document.documentElement) : document.querySelectorAll(baseSelector);
      while (hostElements.length !== 0) {
        let isRemoved = false;
        const { targets, innerHosts } = pierceShadowDom(selector, hostElements);
        targets.forEach((targetEl) => {
          removeElement(targetEl);
          isRemoved = true;
        });
        if (isRemoved) {
          hit(source);
        }
        hostElements = innerHosts;
      }
    };
    removeHandler();
    observeDOMChanges(removeHandler, true);
  }
  var removeInShadowDomNames = [
    "remove-in-shadow-dom"
  ];
  removeInShadowDom.primaryName = removeInShadowDomNames[0];
  removeInShadowDom.injections = [
    hit,
    observeDOMChanges,
    findHostElements,
    pierceShadowDom,
    // following helpers should be imported and injected
    // because they are used by helpers above
    flatten,
    throttle
  ];

  // src/scriptlets/prevent-fetch.js
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
    getMatchPropsData
  ];

  // src/scriptlets/set-local-storage-item.js
  function setLocalStorageItem(source, key, value) {
    if (typeof key === "undefined") {
      logMessage(source, "Item key should be specified.");
      return;
    }
    let validValue;
    try {
      validValue = getLimitedStorageItemValue(value);
    } catch {
      logMessage(source, `Invalid storage item value: '${value}'`);
      return;
    }
    const { localStorage } = window;
    if (validValue === "$remove$") {
      removeStorageItem(source, localStorage, key);
    } else {
      setStorageItem(source, localStorage, key, validValue);
    }
    hit(source);
  }
  var setLocalStorageItemNames = [
    "set-local-storage-item",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "set-local-storage-item.js",
    "ubo-set-local-storage-item.js",
    "ubo-set-local-storage-item"
  ];
  setLocalStorageItem.primaryName = setLocalStorageItemNames[0];
  setLocalStorageItem.injections = [
    hit,
    logMessage,
    nativeIsNaN,
    setStorageItem,
    removeStorageItem,
    getLimitedStorageItemValue,
    // following helpers are needed for helpers above
    isValidStrPattern,
    toRegExp,
    escapeRegExp
  ];

  // src/scriptlets/set-session-storage-item.js
  function setSessionStorageItem(source, key, value) {
    if (typeof key === "undefined") {
      logMessage(source, "Item key should be specified.");
      return;
    }
    let validValue;
    try {
      validValue = getLimitedStorageItemValue(value);
    } catch {
      logMessage(source, `Invalid storage item value: '${value}'`);
      return;
    }
    const { sessionStorage } = window;
    if (validValue === "$remove$") {
      removeStorageItem(source, sessionStorage, key);
    } else {
      setStorageItem(source, sessionStorage, key, validValue);
    }
    hit(source);
  }
  var setSessionStorageItemNames = [
    "set-session-storage-item",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "set-session-storage-item.js",
    "ubo-set-session-storage-item.js",
    "ubo-set-session-storage-item"
  ];
  setSessionStorageItem.primaryName = setSessionStorageItemNames[0];
  setSessionStorageItem.injections = [
    hit,
    logMessage,
    nativeIsNaN,
    setStorageItem,
    removeStorageItem,
    getLimitedStorageItemValue,
    // following helpers are needed for helpers above
    isValidStrPattern,
    toRegExp,
    escapeRegExp
  ];

  // src/scriptlets/abort-on-stack-trace.js
  function abortOnStackTrace(source, property, stack) {
    if (!property || !stack) {
      return;
    }
    const rid = randomId();
    const abort = () => {
      hit(source);
      throw new ReferenceError(rid);
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
      if (!stack.match(/^(inlineScript|injectedScript)$/) && !isValidStrPattern(stack)) {
        logMessage(source, `Invalid parameter: ${stack}`);
        return;
      }
      const descriptorWrapper = Object.assign(getDescriptorAddon(), {
        value: base[prop],
        get() {
          if (!this.isAbortingSuspended && this.isolateCallback(matchStackTrace, stack, new Error().stack)) {
            abort();
          }
          return this.value;
        },
        set(newValue) {
          if (!this.isAbortingSuspended && this.isolateCallback(matchStackTrace, stack, new Error().stack)) {
            abort();
          }
          this.value = newValue;
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
  var abortOnStackTraceNames = [
    "abort-on-stack-trace",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "abort-on-stack-trace.js",
    "ubo-abort-on-stack-trace.js",
    "aost.js",
    "ubo-aost.js",
    "ubo-abort-on-stack-trace",
    "ubo-aost",
    "abp-abort-on-stack-trace"
  ];
  abortOnStackTrace.primaryName = abortOnStackTraceNames[0];
  abortOnStackTrace.injections = [
    randomId,
    setPropertyAccess,
    getPropertyInChain,
    createOnErrorHandler,
    hit,
    isValidStrPattern,
    escapeRegExp,
    matchStackTrace,
    getDescriptorAddon,
    logMessage,
    toRegExp,
    isEmptyObject,
    getNativeRegexpTest,
    shouldAbortInlineOrInjectedScript,
    backupRegExpValues,
    restoreRegExpValues
  ];

  // src/scriptlets/log-on-stack-trace.js
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

  // src/scriptlets/prevent-xhr.js
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

  // src/scriptlets/close-window.js
  function forceWindowClose(source, path = "") {
    if (typeof window.close !== "function") {
      const message = "window.close() is not a function so 'close-window' scriptlet is unavailable";
      logMessage(source, message);
      return;
    }
    const closeImmediately = () => {
      try {
        hit(source);
        window.close();
      } catch (e) {
        logMessage(source, e);
      }
    };
    const closeByExtension = () => {
      const extCall = () => {
        dispatchEvent(new Event("adguard:scriptlet-close-window"));
      };
      window.addEventListener("adguard:subscribed-to-close-window", extCall, { once: true });
      setTimeout(() => {
        window.removeEventListener("adguard:subscribed-to-close-window", extCall, { once: true });
      }, 5e3);
    };
    const shouldClose = () => {
      if (path === "") {
        return true;
      }
      const pathRegexp = toRegExp(path);
      const currentPath = `${window.location.pathname}${window.location.search}`;
      return pathRegexp.test(currentPath);
    };
    if (shouldClose()) {
      closeImmediately();
      if (navigator.userAgent.includes("Chrome")) {
        closeByExtension();
      }
    }
  }
  var forceWindowCloseNames = [
    "close-window",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "window-close-if.js",
    "ubo-window-close-if.js",
    "ubo-window-close-if",
    "close-window.js",
    "ubo-close-window.js",
    "ubo-close-window"
  ];
  forceWindowClose.primaryName = forceWindowCloseNames[0];
  forceWindowClose.injections = [
    hit,
    toRegExp,
    logMessage
  ];

  // src/scriptlets/prevent-refresh.js
  function preventRefresh(source, delaySec) {
    const getMetaElements = () => {
      let metaNodes = [];
      try {
        metaNodes = document.querySelectorAll('meta[http-equiv="refresh" i][content]');
      } catch (e) {
        try {
          metaNodes = document.querySelectorAll('meta[http-equiv="refresh"][content]');
        } catch (e2) {
          logMessage(source, e2);
        }
      }
      return Array.from(metaNodes);
    };
    const getMetaContentDelay = (metaElements) => {
      const delays = metaElements.map((meta) => {
        const contentString = meta.getAttribute("content");
        if (contentString.length === 0) {
          return null;
        }
        let contentDelay;
        const limiterIndex = contentString.indexOf(";");
        if (limiterIndex !== -1) {
          const delaySubstring = contentString.substring(0, limiterIndex);
          contentDelay = getNumberFromString(delaySubstring);
        } else {
          contentDelay = getNumberFromString(contentString);
        }
        return contentDelay;
      }).filter((delay) => delay !== null);
      if (!delays.length) {
        return null;
      }
      const minDelay = delays.reduce((a, b) => Math.min(a, b));
      return minDelay;
    };
    const stop = () => {
      const metaElements = getMetaElements();
      if (metaElements.length === 0) {
        return;
      }
      let secondsToRun = getNumberFromString(delaySec);
      if (secondsToRun === null) {
        secondsToRun = getMetaContentDelay(metaElements);
      }
      if (secondsToRun === null) {
        return;
      }
      const delayMs = secondsToRun * 1e3;
      setTimeout(() => {
        window.stop();
        hit(source);
      }, delayMs);
    };
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", stop, { once: true });
    } else {
      stop();
    }
  }
  var preventRefreshNames = [
    "prevent-refresh",
    // Aliases are needed for matching the related scriptlet converted into our syntax
    // These are used by UBO rules syntax
    // https://github.com/gorhill/uBlock/wiki/Resources-Library#general-purpose-scriptlets
    "prevent-refresh.js",
    "refresh-defuser.js",
    "refresh-defuser",
    // Prefix 'ubo-' is required to run converted rules
    "ubo-prevent-refresh.js",
    "ubo-prevent-refresh",
    "ubo-refresh-defuser.js",
    "ubo-refresh-defuser"
  ];
  preventRefresh.primaryName = preventRefreshNames[0];
  preventRefresh.injections = [
    hit,
    getNumberFromString,
    logMessage,
    nativeIsNaN
  ];

  // src/scriptlets/prevent-element-src-loading.js
  function preventElementSrcLoading(source, tagName, match) {
    if (typeof Proxy === "undefined" || typeof Reflect === "undefined") {
      return;
    }
    const srcMockData = {
      // "KCk9Pnt9" = "()=>{}"
      script: "data:text/javascript;base64,KCk9Pnt9",
      // Empty 1x1 image
      img: "data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==",
      // Empty h1 tag
      iframe: "data:text/html;base64, PGRpdj48L2Rpdj4=",
      // Empty data
      link: "data:text/plain;base64,"
    };
    let instance;
    if (tagName === "script") {
      instance = HTMLScriptElement;
    } else if (tagName === "img") {
      instance = HTMLImageElement;
    } else if (tagName === "iframe") {
      instance = HTMLIFrameElement;
    } else if (tagName === "link") {
      instance = HTMLLinkElement;
    } else {
      return;
    }
    const hasTrustedTypes = window.trustedTypes && typeof window.trustedTypes.createPolicy === "function";
    let policy;
    if (hasTrustedTypes) {
      policy = window.trustedTypes.createPolicy("AGPolicy", {
        createScriptURL: (arg) => arg
      });
    }
    const SOURCE_PROPERTY_NAME = tagName === "link" ? "href" : "src";
    const ONERROR_PROPERTY_NAME = "onerror";
    const searchRegexp = toRegExp(match);
    const setMatchedAttribute = (elem) => elem.setAttribute(source.name, "matched");
    const setAttributeWrapper = (target, thisArg, args) => {
      if (!args[0] || !args[1]) {
        return Reflect.apply(target, thisArg, args);
      }
      const nodeName = thisArg.nodeName.toLowerCase();
      const attrName = args[0].toLowerCase();
      const attrValue = args[1];
      const isMatched = attrName === SOURCE_PROPERTY_NAME && tagName.toLowerCase() === nodeName && srcMockData[nodeName] && searchRegexp.test(attrValue);
      if (!isMatched) {
        return Reflect.apply(target, thisArg, args);
      }
      hit(source);
      setMatchedAttribute(thisArg);
      return Reflect.apply(target, thisArg, [attrName, srcMockData[nodeName]]);
    };
    const setAttributeHandler = {
      apply: setAttributeWrapper
    };
    instance.prototype.setAttribute = new Proxy(Element.prototype.setAttribute, setAttributeHandler);
    const origSrcDescriptor = safeGetDescriptor(instance.prototype, SOURCE_PROPERTY_NAME);
    if (!origSrcDescriptor) {
      return;
    }
    Object.defineProperty(instance.prototype, SOURCE_PROPERTY_NAME, {
      enumerable: true,
      configurable: true,
      get() {
        return origSrcDescriptor.get.call(this);
      },
      set(urlValue) {
        const nodeName = this.nodeName.toLowerCase();
        const isMatched = tagName.toLowerCase() === nodeName && srcMockData[nodeName] && searchRegexp.test(urlValue);
        if (!isMatched) {
          origSrcDescriptor.set.call(this, urlValue);
          return true;
        }
        if (policy && urlValue instanceof TrustedScriptURL) {
          const trustedSrc = policy.createScriptURL(urlValue);
          origSrcDescriptor.set.call(this, trustedSrc);
          hit(source);
          return;
        }
        setMatchedAttribute(this);
        origSrcDescriptor.set.call(this, srcMockData[nodeName]);
        hit(source);
      }
    });
    const origOnerrorDescriptor = safeGetDescriptor(HTMLElement.prototype, ONERROR_PROPERTY_NAME);
    if (!origOnerrorDescriptor) {
      return;
    }
    Object.defineProperty(HTMLElement.prototype, ONERROR_PROPERTY_NAME, {
      enumerable: true,
      configurable: true,
      get() {
        return origOnerrorDescriptor.get.call(this);
      },
      set(cb) {
        const isMatched = this.getAttribute(source.name) === "matched";
        if (!isMatched) {
          origOnerrorDescriptor.set.call(this, cb);
          return true;
        }
        origOnerrorDescriptor.set.call(this, noopFunc);
        return true;
      }
    });
    const addEventListenerWrapper = (target, thisArg, args) => {
      if (!args[0] || !args[1] || !thisArg) {
        return Reflect.apply(target, thisArg, args);
      }
      const eventName = args[0];
      const isMatched = typeof thisArg.getAttribute === "function" && thisArg.getAttribute(source.name) === "matched" && eventName === "error";
      if (isMatched) {
        return Reflect.apply(target, thisArg, [eventName, noopFunc]);
      }
      return Reflect.apply(target, thisArg, args);
    };
    const addEventListenerHandler = {
      apply: addEventListenerWrapper
    };
    EventTarget.prototype.addEventListener = new Proxy(EventTarget.prototype.addEventListener, addEventListenerHandler);
    const preventInlineOnerror = (tagName2, src) => {
      window.addEventListener("error", (event) => {
        if (!event.target || !event.target.nodeName || event.target.nodeName.toLowerCase() !== tagName2 || !event.target.src || !src.test(event.target.src)) {
          return;
        }
        hit(source);
        if (typeof event.target.onload === "function") {
          event.target.onerror = event.target.onload;
          return;
        }
        event.target.onerror = noopFunc;
      }, true);
    };
    preventInlineOnerror(tagName, searchRegexp);
  }
  var preventElementSrcLoadingNames = [
    "prevent-element-src-loading"
  ];
  preventElementSrcLoading.primaryName = preventElementSrcLoadingNames[0];
  preventElementSrcLoading.injections = [
    hit,
    toRegExp,
    safeGetDescriptor,
    noopFunc
  ];

  // src/scriptlets/no-topics.js
  function noTopics(source) {
    const TOPICS_PROPERTY_NAME = "browsingTopics";
    if (Document instanceof Object === false) {
      return;
    }
    if (!Object.prototype.hasOwnProperty.call(Document.prototype, TOPICS_PROPERTY_NAME) || Document.prototype[TOPICS_PROPERTY_NAME] instanceof Function === false) {
      return;
    }
    Document.prototype[TOPICS_PROPERTY_NAME] = () => noopPromiseResolve("[]");
    hit(source);
  }
  var noTopicsNames = [
    "no-topics"
  ];
  noTopics.primaryName = noTopicsNames[0];
  noTopics.injections = [
    hit,
    noopPromiseResolve
  ];

  // src/scriptlets/trusted-replace-xhr-response.js
  function trustedReplaceXhrResponse(source, pattern = "", replacement = "", propsToMatch = "", verbose = false) {
    if (typeof Proxy === "undefined") {
      return;
    }
    if (pattern === "" && replacement !== "") {
      const message = "Pattern argument should not be empty string.";
      logMessage(source, message);
      return;
    }
    const shouldLog = pattern === "" && replacement === "";
    const shouldLogContent = verbose === "true";
    const nativeOpen = window.XMLHttpRequest.prototype.open;
    const nativeSend = window.XMLHttpRequest.prototype.send;
    let xhrData;
    const openWrapper = (target, thisArg, args) => {
      xhrData = getXhrData.apply(null, args);
      if (shouldLog) {
        const message = `xhr( ${objectToString(xhrData)} )`;
        logMessage(source, message, true);
        hit(source);
        return Reflect.apply(target, thisArg, args);
      }
      if (matchRequestProps(source, propsToMatch, xhrData)) {
        thisArg.shouldBePrevented = true;
        thisArg.headersReceived = !!thisArg.headersReceived;
      }
      if (thisArg.shouldBePrevented && !thisArg.headersReceived) {
        thisArg.headersReceived = true;
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
      const forgedRequest = new XMLHttpRequest();
      forgedRequest.addEventListener("readystatechange", () => {
        if (forgedRequest.readyState !== 4) {
          return;
        }
        const {
          readyState,
          response,
          responseText,
          responseURL,
          responseXML,
          status,
          statusText
        } = forgedRequest;
        const content = responseText || response;
        if (typeof content !== "string") {
          return;
        }
        const patternRegexp = pattern === "*" ? /(\n|.)*/ : toRegExp(pattern);
        if (shouldLogContent) {
          logMessage(source, `Original text content: ${content}`);
        }
        const modifiedContent = content.replace(patternRegexp, replacement);
        if (shouldLogContent) {
          logMessage(source, `Modified text content: ${modifiedContent}`);
        }
        Object.defineProperties(thisArg, {
          // original values
          readyState: { value: readyState, writable: false },
          responseURL: { value: responseURL, writable: false },
          responseXML: { value: responseXML, writable: false },
          status: { value: status, writable: false },
          statusText: { value: statusText, writable: false },
          // modified values
          response: { value: modifiedContent, writable: false },
          responseText: { value: modifiedContent, writable: false }
        });
        setTimeout(() => {
          const stateEvent = new Event("readystatechange");
          thisArg.dispatchEvent(stateEvent);
          const loadEvent = new Event("load");
          thisArg.dispatchEvent(loadEvent);
          const loadEndEvent = new Event("loadend");
          thisArg.dispatchEvent(loadEndEvent);
        }, 1);
        hit(source);
      });
      nativeOpen.apply(forgedRequest, [xhrData.method, xhrData.url]);
      thisArg.collectedHeaders.forEach((header) => {
        const name = header[0];
        const value = header[1];
        forgedRequest.setRequestHeader(name, value);
      });
      thisArg.collectedHeaders = [];
      try {
        nativeSend.call(forgedRequest, args);
      } catch {
        return Reflect.apply(target, thisArg, args);
      }
      return void 0;
    };
    const openHandler = {
      apply: openWrapper
    };
    const sendHandler = {
      apply: sendWrapper
    };
    XMLHttpRequest.prototype.open = new Proxy(XMLHttpRequest.prototype.open, openHandler);
    XMLHttpRequest.prototype.send = new Proxy(XMLHttpRequest.prototype.send, sendHandler);
  }
  var trustedReplaceXhrResponseNames = [
    "trusted-replace-xhr-response"
    // trusted scriptlets support no aliases
  ];
  trustedReplaceXhrResponse.primaryName = trustedReplaceXhrResponseNames[0];
  trustedReplaceXhrResponse.injections = [
    hit,
    logMessage,
    toRegExp,
    objectToString,
    matchRequestProps,
    getXhrData,
    getMatchPropsData,
    getRequestProps,
    isValidParsedData,
    parseMatchProps,
    isValidStrPattern,
    escapeRegExp,
    isEmptyObject
  ];

  // src/scriptlets/xml-prune.js
  function xmlPrune(source, propsToRemove, optionalProp = "", urlToMatch = "", verbose = false) {
    if (typeof Reflect === "undefined" || typeof fetch === "undefined" || typeof Proxy === "undefined" || typeof Response === "undefined") {
      return;
    }
    let shouldPruneResponse = false;
    const shouldLogContent = verbose === "true";
    const urlMatchRegexp = toRegExp(urlToMatch);
    const XPATH_MARKER = "xpath(";
    const isXpath = propsToRemove && propsToRemove.startsWith(XPATH_MARKER);
    const getXPathElements = (contextNode) => {
      const matchedElements = [];
      try {
        const elementsToRemove = propsToRemove.slice(XPATH_MARKER.length, -1);
        const xpathResult = contextNode.evaluate(
          elementsToRemove,
          contextNode,
          null,
          XPathResult.UNORDERED_NODE_SNAPSHOT_TYPE,
          null
        );
        for (let i = 0; i < xpathResult.snapshotLength; i += 1) {
          matchedElements.push(xpathResult.snapshotItem(i));
        }
      } catch (ex) {
        const message = `Invalid XPath parameter: ${propsToRemove}
${ex}`;
        logMessage(source, message);
      }
      return matchedElements;
    };
    const xPathPruning = (xPathElements) => {
      xPathElements.forEach((element) => {
        if (element.nodeType === 1) {
          element.remove();
        } else if (element.nodeType === 2) {
          element.ownerElement.removeAttribute(element.nodeName);
        }
      });
    };
    const isXML = (text) => {
      if (typeof text === "string") {
        const trimmedText = text.trim();
        if (trimmedText.startsWith("<") && trimmedText.endsWith(">")) {
          return true;
        }
      }
      return false;
    };
    const createXMLDocument = (text) => {
      const xmlParser = new DOMParser();
      const xmlDocument = xmlParser.parseFromString(text, "text/xml");
      return xmlDocument;
    };
    const isPruningNeeded2 = (response, propsToRemove2) => {
      if (!isXML(response)) {
        return false;
      }
      const docXML = createXMLDocument(response);
      return isXpath ? getXPathElements(docXML) : !!docXML.querySelector(propsToRemove2);
    };
    const pruneXML = (text) => {
      if (!isXML(text)) {
        shouldPruneResponse = false;
        return text;
      }
      const xmlDoc = createXMLDocument(text);
      const errorNode = xmlDoc.querySelector("parsererror");
      if (errorNode) {
        return text;
      }
      if (optionalProp !== "" && xmlDoc.querySelector(optionalProp) === null) {
        shouldPruneResponse = false;
        return text;
      }
      const elements = isXpath ? getXPathElements(xmlDoc) : xmlDoc.querySelectorAll(propsToRemove);
      if (!elements.length) {
        shouldPruneResponse = false;
        return text;
      }
      if (shouldLogContent) {
        const cloneXmlDoc = xmlDoc.cloneNode(true);
        logMessage(source, "Original xml:");
        logMessage(source, cloneXmlDoc, true, false);
      }
      if (isXpath) {
        xPathPruning(elements);
      } else {
        elements.forEach((elem) => {
          elem.remove();
        });
      }
      if (shouldLogContent) {
        logMessage(source, "Modified xml:");
        logMessage(source, xmlDoc, true, false);
      }
      const serializer = new XMLSerializer();
      text = serializer.serializeToString(xmlDoc);
      return text;
    };
    const nativeOpen = window.XMLHttpRequest.prototype.open;
    const nativeSend = window.XMLHttpRequest.prototype.send;
    let xhrData;
    const openWrapper = (target, thisArg, args) => {
      xhrData = getXhrData.apply(null, args);
      if (matchRequestProps(source, urlToMatch, xhrData)) {
        thisArg.shouldBePruned = true;
      }
      if (thisArg.shouldBePruned) {
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
      const allowedResponseTypeValues = ["", "text"];
      if (!thisArg.shouldBePruned || !allowedResponseTypeValues.includes(thisArg.responseType)) {
        return Reflect.apply(target, thisArg, args);
      }
      const forgedRequest = new XMLHttpRequest();
      forgedRequest.addEventListener("readystatechange", () => {
        if (forgedRequest.readyState !== 4) {
          return;
        }
        const {
          readyState,
          response,
          responseText,
          responseURL,
          responseXML,
          status,
          statusText
        } = forgedRequest;
        const content = responseText || response;
        if (typeof content !== "string") {
          return;
        }
        if (!propsToRemove) {
          if (isXML(response)) {
            const message = `XMLHttpRequest.open() URL: ${responseURL}
response: ${response}`;
            logMessage(source, message);
            logMessage(source, createXMLDocument(response), true, false);
          }
        } else {
          shouldPruneResponse = isPruningNeeded2(response, propsToRemove);
        }
        const responseContent = shouldPruneResponse ? pruneXML(response) : response;
        Object.defineProperties(thisArg, {
          // original values
          readyState: { value: readyState, writable: false },
          responseURL: { value: responseURL, writable: false },
          responseXML: { value: responseXML, writable: false },
          status: { value: status, writable: false },
          statusText: { value: statusText, writable: false },
          // modified values
          response: { value: responseContent, writable: false },
          responseText: { value: responseContent, writable: false }
        });
        setTimeout(() => {
          const stateEvent = new Event("readystatechange");
          thisArg.dispatchEvent(stateEvent);
          const loadEvent = new Event("load");
          thisArg.dispatchEvent(loadEvent);
          const loadEndEvent = new Event("loadend");
          thisArg.dispatchEvent(loadEndEvent);
        }, 1);
        hit(source);
      });
      nativeOpen.apply(forgedRequest, [xhrData.method, xhrData.url]);
      thisArg.collectedHeaders.forEach((header) => {
        const name = header[0];
        const value = header[1];
        forgedRequest.setRequestHeader(name, value);
      });
      thisArg.collectedHeaders = [];
      try {
        nativeSend.call(forgedRequest, args);
      } catch {
        return Reflect.apply(target, thisArg, args);
      }
      return void 0;
    };
    const openHandler = {
      apply: openWrapper
    };
    const sendHandler = {
      apply: sendWrapper
    };
    XMLHttpRequest.prototype.open = new Proxy(XMLHttpRequest.prototype.open, openHandler);
    XMLHttpRequest.prototype.send = new Proxy(XMLHttpRequest.prototype.send, sendHandler);
    const nativeFetch = window.fetch;
    const fetchWrapper = async (target, thisArg, args) => {
      const fetchURL = args[0] instanceof Request ? args[0].url : args[0];
      if (typeof fetchURL !== "string" || fetchURL.length === 0) {
        return Reflect.apply(target, thisArg, args);
      }
      if (urlMatchRegexp.test(fetchURL)) {
        const response = await nativeFetch(...args);
        const clonedResponse = response.clone();
        const responseText = await response.text();
        shouldPruneResponse = isPruningNeeded2(responseText, propsToRemove);
        if (!shouldPruneResponse) {
          const message = `fetch URL: ${fetchURL}
response text: ${responseText}`;
          logMessage(source, message);
          logMessage(source, createXMLDocument(responseText), true, false);
          return clonedResponse;
        }
        const prunedText = pruneXML(responseText);
        if (shouldPruneResponse) {
          hit(source);
          return new Response(prunedText, {
            status: response.status,
            statusText: response.statusText,
            headers: response.headers
          });
        }
        return clonedResponse;
      }
      return Reflect.apply(target, thisArg, args);
    };
    const fetchHandler = {
      apply: fetchWrapper
    };
    window.fetch = new Proxy(window.fetch, fetchHandler);
  }
  var xmlPruneNames = [
    "xml-prune",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "xml-prune.js",
    "ubo-xml-prune.js",
    "ubo-xml-prune"
  ];
  xmlPrune.primaryName = xmlPruneNames[0];
  xmlPrune.injections = [
    hit,
    logMessage,
    toRegExp,
    getXhrData,
    objectToString,
    matchRequestProps,
    getMatchPropsData,
    getRequestProps,
    isValidParsedData,
    parseMatchProps,
    isValidStrPattern,
    escapeRegExp,
    isEmptyObject
  ];

  // src/scriptlets/m3u-prune.js
  function m3uPrune(source, propsToRemove, urlToMatch = "", verbose = false) {
    if (typeof Reflect === "undefined" || typeof fetch === "undefined" || typeof Proxy === "undefined" || typeof Response === "undefined") {
      return;
    }
    let shouldPruneResponse = false;
    const shouldLogContent = verbose === "true";
    const urlMatchRegexp = toRegExp(urlToMatch);
    const SEGMENT_MARKER = "#";
    const AD_MARKER = {
      ASSET: "#EXT-X-ASSET:",
      CUE: "#EXT-X-CUE:",
      CUE_IN: "#EXT-X-CUE-IN",
      DISCONTINUITY: "#EXT-X-DISCONTINUITY",
      EXTINF: "#EXTINF",
      EXTM3U: "#EXTM3U",
      SCTE35: "#EXT-X-SCTE35:"
    };
    const COMCAST_AD_MARKER = {
      AD: "-AD-",
      VAST: "-VAST-",
      VMAP_AD: "-VMAP-AD-",
      VMAP_AD_BREAK: "#EXT-X-VMAP-AD-BREAK:"
    };
    const TAGS_ALLOWLIST = [
      "#EXT-X-TARGETDURATION",
      "#EXT-X-MEDIA-SEQUENCE",
      "#EXT-X-DISCONTINUITY-SEQUENCE",
      "#EXT-X-ENDLIST",
      "#EXT-X-PLAYLIST-TYPE",
      "#EXT-X-I-FRAMES-ONLY",
      "#EXT-X-MEDIA",
      "#EXT-X-STREAM-INF",
      "#EXT-X-I-FRAME-STREAM-INF",
      "#EXT-X-SESSION-DATA",
      "#EXT-X-SESSION-KEY",
      "#EXT-X-INDEPENDENT-SEGMENTS",
      "#EXT-X-START"
    ];
    const isAllowedTag = (str) => {
      return TAGS_ALLOWLIST.some((el) => str.startsWith(el));
    };
    const pruneExtinfFromVmapBlock = (lines, i) => {
      let array = lines.slice();
      let index = i;
      if (array[index].includes(AD_MARKER.EXTINF)) {
        array[index] = void 0;
        index += 1;
        if (array[index].includes(AD_MARKER.DISCONTINUITY)) {
          array[index] = void 0;
          index += 1;
          const prunedExtinf = pruneExtinfFromVmapBlock(array, index);
          array = prunedExtinf.array;
          index = prunedExtinf.index;
        }
      }
      return { array, index };
    };
    const pruneVmapBlock = (lines) => {
      let array = lines.slice();
      for (let i = 0; i < array.length - 1; i += 1) {
        if (array[i].includes(COMCAST_AD_MARKER.VMAP_AD) || array[i].includes(COMCAST_AD_MARKER.VAST) || array[i].includes(COMCAST_AD_MARKER.AD)) {
          array[i] = void 0;
          if (array[i + 1].includes(AD_MARKER.EXTINF)) {
            i += 1;
            const prunedExtinf = pruneExtinfFromVmapBlock(array, i);
            array = prunedExtinf.array;
            i = prunedExtinf.index - 1;
          }
        }
      }
      return array;
    };
    const pruneSpliceoutBlock = (line, index, array) => {
      if (!line.startsWith(AD_MARKER.CUE)) {
        return line;
      }
      line = void 0;
      index += 1;
      if (array[index].startsWith(AD_MARKER.ASSET)) {
        array[index] = void 0;
        index += 1;
      }
      if (array[index].startsWith(AD_MARKER.SCTE35)) {
        array[index] = void 0;
        index += 1;
      }
      if (array[index].startsWith(AD_MARKER.CUE_IN)) {
        array[index] = void 0;
        index += 1;
      }
      if (array[index].startsWith(AD_MARKER.SCTE35)) {
        array[index] = void 0;
      }
      return line;
    };
    const removeM3ULineRegexp = toRegExp(propsToRemove);
    const pruneInfBlock = (line, index, array) => {
      if (!line.startsWith(AD_MARKER.EXTINF)) {
        return line;
      }
      if (!removeM3ULineRegexp.test(array[index + 1])) {
        return line;
      }
      if (!isAllowedTag(array[index])) {
        array[index] = void 0;
      }
      index += 1;
      if (!isAllowedTag(array[index])) {
        array[index] = void 0;
      }
      index += 1;
      if (array[index].startsWith(AD_MARKER.DISCONTINUITY)) {
        array[index] = void 0;
      }
      return line;
    };
    const pruneSegments = (lines) => {
      for (let i = 0; i < lines.length - 1; i += 1) {
        if (lines[i]?.startsWith(SEGMENT_MARKER) && removeM3ULineRegexp.test(lines[i])) {
          const segmentName = lines[i].substring(0, lines[i].indexOf(":"));
          if (!segmentName) {
            return lines;
          }
          lines[i] = void 0;
          i += 1;
          for (let j = i; j < lines.length; j += 1) {
            if (!lines[j].includes(segmentName) && !isAllowedTag(lines[j])) {
              lines[j] = void 0;
            } else {
              i = j - 1;
              break;
            }
          }
        }
      }
      return lines;
    };
    const isM3U = (text) => {
      if (typeof text === "string") {
        const trimmedText = text.trim();
        return trimmedText.startsWith(AD_MARKER.EXTM3U) || trimmedText.startsWith(COMCAST_AD_MARKER.VMAP_AD_BREAK);
      }
      return false;
    };
    const isPruningNeeded2 = (text, regexp) => isM3U(text) && regexp.test(text);
    const pruneM3U = (text) => {
      if (shouldLogContent) {
        logMessage(source, `Original M3U content:
${text}`);
      }
      let lines = text.split(/\r?\n/);
      if (text.includes(COMCAST_AD_MARKER.VMAP_AD_BREAK)) {
        lines = pruneVmapBlock(lines);
        lines = lines.filter((l) => !!l).join("\n");
        if (shouldLogContent) {
          logMessage(source, `Modified M3U content:
${lines}`);
        }
        return lines;
      }
      lines = pruneSegments(lines);
      lines = lines.map((line, index, array) => {
        if (typeof line === "undefined") {
          return line;
        }
        line = pruneSpliceoutBlock(line, index, array);
        if (typeof line !== "undefined") {
          line = pruneInfBlock(line, index, array);
        }
        return line;
      }).filter((l) => !!l).join("\n");
      if (shouldLogContent) {
        logMessage(source, `Modified M3U content:
${lines}`);
      }
      return lines;
    };
    const nativeOpen = window.XMLHttpRequest.prototype.open;
    const nativeSend = window.XMLHttpRequest.prototype.send;
    let xhrData;
    const openWrapper = (target, thisArg, args) => {
      xhrData = getXhrData.apply(null, args);
      if (matchRequestProps(source, urlToMatch, xhrData)) {
        thisArg.shouldBePruned = true;
      }
      if (thisArg.shouldBePruned) {
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
      const allowedResponseTypeValues = ["", "text"];
      if (!thisArg.shouldBePruned || !allowedResponseTypeValues.includes(thisArg.responseType)) {
        return Reflect.apply(target, thisArg, args);
      }
      const forgedRequest = new XMLHttpRequest();
      forgedRequest.addEventListener("readystatechange", () => {
        if (forgedRequest.readyState !== 4) {
          return;
        }
        const {
          readyState,
          response,
          responseText,
          responseURL,
          responseXML,
          status,
          statusText
        } = forgedRequest;
        const content = responseText || response;
        if (typeof content !== "string") {
          return;
        }
        if (!propsToRemove) {
          if (isM3U(response)) {
            const message = `XMLHttpRequest.open() URL: ${responseURL}
response: ${response}`;
            logMessage(source, message);
          }
        } else {
          shouldPruneResponse = isPruningNeeded2(response, removeM3ULineRegexp);
        }
        const responseContent = shouldPruneResponse ? pruneM3U(response) : response;
        Object.defineProperties(thisArg, {
          // original values
          readyState: { value: readyState, writable: false },
          responseURL: { value: responseURL, writable: false },
          responseXML: { value: responseXML, writable: false },
          status: { value: status, writable: false },
          statusText: { value: statusText, writable: false },
          // modified values
          response: { value: responseContent, writable: false },
          responseText: { value: responseContent, writable: false }
        });
        setTimeout(() => {
          const stateEvent = new Event("readystatechange");
          thisArg.dispatchEvent(stateEvent);
          const loadEvent = new Event("load");
          thisArg.dispatchEvent(loadEvent);
          const loadEndEvent = new Event("loadend");
          thisArg.dispatchEvent(loadEndEvent);
        }, 1);
        hit(source);
      });
      nativeOpen.apply(forgedRequest, [xhrData.method, xhrData.url]);
      thisArg.collectedHeaders.forEach((header) => {
        const name = header[0];
        const value = header[1];
        forgedRequest.setRequestHeader(name, value);
      });
      thisArg.collectedHeaders = [];
      try {
        nativeSend.call(forgedRequest, args);
      } catch {
        return Reflect.apply(target, thisArg, args);
      }
      return void 0;
    };
    const openHandler = {
      apply: openWrapper
    };
    const sendHandler = {
      apply: sendWrapper
    };
    XMLHttpRequest.prototype.open = new Proxy(XMLHttpRequest.prototype.open, openHandler);
    XMLHttpRequest.prototype.send = new Proxy(XMLHttpRequest.prototype.send, sendHandler);
    const nativeFetch = window.fetch;
    const fetchWrapper = async (target, thisArg, args) => {
      const fetchURL = args[0] instanceof Request ? args[0].url : args[0];
      if (typeof fetchURL !== "string" || fetchURL.length === 0) {
        return Reflect.apply(target, thisArg, args);
      }
      if (urlMatchRegexp.test(fetchURL)) {
        const response = await nativeFetch(...args);
        const clonedResponse = response.clone();
        const responseText = await response.text();
        if (!propsToRemove && isM3U(responseText)) {
          const message = `fetch URL: ${fetchURL}
response text: ${responseText}`;
          logMessage(source, message);
          return clonedResponse;
        }
        if (isPruningNeeded2(responseText, removeM3ULineRegexp)) {
          const prunedText = pruneM3U(responseText);
          hit(source);
          return new Response(prunedText, {
            status: response.status,
            statusText: response.statusText,
            headers: response.headers
          });
        }
        return clonedResponse;
      }
      return Reflect.apply(target, thisArg, args);
    };
    const fetchHandler = {
      apply: fetchWrapper
    };
    window.fetch = new Proxy(window.fetch, fetchHandler);
  }
  var m3uPruneNames = [
    "m3u-prune",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "m3u-prune.js",
    "ubo-m3u-prune.js",
    "ubo-m3u-prune"
  ];
  m3uPrune.primaryName = m3uPruneNames[0];
  m3uPrune.injections = [
    hit,
    toRegExp,
    logMessage,
    getXhrData,
    objectToString,
    matchRequestProps,
    getMatchPropsData,
    getRequestProps,
    isValidParsedData,
    parseMatchProps,
    isValidStrPattern,
    escapeRegExp,
    isEmptyObject
  ];

  // src/scriptlets/trusted-set-cookie.js
  function trustedSetCookie(source, name, value, offsetExpiresSec = "", path = "/", domain = "") {
    if (typeof name === "undefined") {
      logMessage(source, "Cookie name should be specified");
      return;
    }
    if (typeof value === "undefined") {
      logMessage(source, "Cookie value should be specified");
      return;
    }
    const parsedValue = parseKeywordValue(value);
    if (!isValidCookiePath(path)) {
      logMessage(source, `Invalid cookie path: '${path}'`);
      return;
    }
    if (!document.location.origin.includes(domain)) {
      logMessage(source, `Cookie domain not matched by origin: '${domain}'`);
      return;
    }
    let cookieToSet = serializeCookie(name, parsedValue, path, domain, false);
    if (!cookieToSet) {
      logMessage(source, "Invalid cookie name or value");
      return;
    }
    if (offsetExpiresSec) {
      const parsedOffsetMs = getTrustedCookieOffsetMs(offsetExpiresSec);
      if (!parsedOffsetMs) {
        logMessage(source, `Invalid offsetExpiresSec value: ${offsetExpiresSec}`);
        return;
      }
      const expires = Date.now() + parsedOffsetMs;
      cookieToSet += `; expires=${new Date(expires).toUTCString()}`;
    }
    document.cookie = cookieToSet;
    hit(source);
  }
  var trustedSetCookieNames = [
    "trusted-set-cookie"
    // trusted scriptlets support no aliases
  ];
  trustedSetCookie.primaryName = trustedSetCookieNames[0];
  trustedSetCookie.injections = [
    hit,
    logMessage,
    nativeIsNaN,
    isCookieSetWithValue,
    serializeCookie,
    isValidCookiePath,
    getTrustedCookieOffsetMs,
    parseKeywordValue,
    getCookiePath
  ];

  // src/scriptlets/trusted-set-cookie-reload.js
  function trustedSetCookieReload(source, name, value, offsetExpiresSec = "", path = "/", domain = "") {
    if (typeof name === "undefined") {
      logMessage(source, "Cookie name should be specified");
      return;
    }
    if (typeof value === "undefined") {
      logMessage(source, "Cookie value should be specified");
      return;
    }
    if (isCookieSetWithValue(document.cookie, name, value)) {
      return;
    }
    const parsedValue = parseKeywordValue(value);
    if (!isValidCookiePath(path)) {
      logMessage(source, `Invalid cookie path: '${path}'`);
      return;
    }
    if (!document.location.origin.includes(domain)) {
      logMessage(source, `Cookie domain not matched by origin: '${domain}'`);
      return;
    }
    let cookieToSet = serializeCookie(name, parsedValue, path, domain, false);
    if (!cookieToSet) {
      logMessage(source, "Invalid cookie name or value");
      return;
    }
    if (offsetExpiresSec) {
      const parsedOffsetMs = getTrustedCookieOffsetMs(offsetExpiresSec);
      if (!parsedOffsetMs) {
        logMessage(source, `Invalid offsetExpiresSec value: ${offsetExpiresSec}`);
        return;
      }
      const expires = Date.now() + parsedOffsetMs;
      cookieToSet += `; expires=${new Date(expires).toUTCString()}`;
    }
    document.cookie = cookieToSet;
    hit(source);
    const cookieValueToCheck = parseCookieString(document.cookie)[name];
    if (isCookieSetWithValue(document.cookie, name, cookieValueToCheck)) {
      window.location.reload();
    }
  }
  var trustedSetCookieReloadNames = [
    "trusted-set-cookie-reload"
    // trusted scriptlets support no aliases
  ];
  trustedSetCookieReload.primaryName = trustedSetCookieReloadNames[0];
  trustedSetCookieReload.injections = [
    hit,
    logMessage,
    nativeIsNaN,
    isCookieSetWithValue,
    serializeCookie,
    isValidCookiePath,
    getTrustedCookieOffsetMs,
    parseKeywordValue,
    parseCookieString,
    getCookiePath
  ];

  // src/scriptlets/trusted-replace-fetch-response.js
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

  // src/scriptlets/trusted-set-local-storage-item.js
  function trustedSetLocalStorageItem(source, key, value) {
    if (typeof key === "undefined") {
      logMessage(source, "Item key should be specified");
      return;
    }
    if (typeof value === "undefined") {
      logMessage(source, "Item value should be specified");
      return;
    }
    const parsedValue = parseKeywordValue(value);
    const { localStorage } = window;
    setStorageItem(source, localStorage, key, parsedValue);
    hit(source);
  }
  var trustedSetLocalStorageItemNames = [
    "trusted-set-local-storage-item"
    // trusted scriptlets support no aliases
  ];
  trustedSetLocalStorageItem.primaryName = trustedSetLocalStorageItemNames[0];
  trustedSetLocalStorageItem.injections = [
    hit,
    logMessage,
    nativeIsNaN,
    setStorageItem,
    parseKeywordValue
  ];

  // src/scriptlets/trusted-set-session-storage-item.ts
  function trustedSetSessionStorageItem(source, key, value) {
    if (typeof key === "undefined") {
      logMessage(source, "Item key should be specified");
      return;
    }
    if (typeof value === "undefined") {
      logMessage(source, "Item value should be specified");
      return;
    }
    const parsedValue = parseKeywordValue(value);
    const { sessionStorage } = window;
    setStorageItem(source, sessionStorage, key, parsedValue);
    hit(source);
  }
  var trustedSetSessionStorageItemNames = [
    "trusted-set-session-storage-item"
    // trusted scriptlets support no aliases
  ];
  trustedSetSessionStorageItem.primaryName = trustedSetSessionStorageItemNames[0];
  trustedSetSessionStorageItem.injections = [
    hit,
    logMessage,
    nativeIsNaN,
    setStorageItem,
    parseKeywordValue
  ];

  // src/scriptlets/trusted-set-constant.js
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

  // src/scriptlets/inject-css-in-shadow-dom.js
  function injectCssInShadowDom(source, cssRule, hostSelector = "") {
    if (!Element.prototype.attachShadow || typeof Proxy === "undefined" || typeof Reflect === "undefined") {
      return;
    }
    if (cssRule.match(/(url|image-set)\(.*\)/i)) {
      logMessage(source, '"url()" function is not allowed for css rules');
      return;
    }
    const callback = (shadowRoot) => {
      try {
        const stylesheet = new CSSStyleSheet();
        try {
          stylesheet.insertRule(cssRule);
        } catch (e) {
          logMessage(source, `Unable to apply the rule '${cssRule}' due to: 
'${e.message}'`);
          return;
        }
        shadowRoot.adoptedStyleSheets = [...shadowRoot.adoptedStyleSheets, stylesheet];
      } catch {
        const styleTag = document.createElement("style");
        styleTag.innerText = cssRule;
        shadowRoot.appendChild(styleTag);
      }
      hit(source);
    };
    hijackAttachShadow(window, hostSelector, callback);
  }
  var injectCssInShadowDomNames = [
    "inject-css-in-shadow-dom"
  ];
  injectCssInShadowDom.primaryName = injectCssInShadowDomNames[0];
  injectCssInShadowDom.injections = [
    hit,
    logMessage,
    hijackAttachShadow
  ];

  // src/scriptlets/remove-node-text.js
  function removeNodeText(source, nodeName, textMatch, parentSelector) {
    const {
      selector,
      nodeNameMatch,
      textContentMatch
    } = parseNodeTextParams(nodeName, textMatch);
    const handleNodes = (nodes) => nodes.forEach((node) => {
      const shouldReplace = isTargetNode(
        node,
        nodeNameMatch,
        textContentMatch
      );
      if (shouldReplace) {
        const ALL_TEXT_PATTERN = /^.*$/s;
        const REPLACEMENT = "";
        replaceNodeText(source, node, ALL_TEXT_PATTERN, REPLACEMENT);
      }
    });
    if (document.documentElement) {
      handleExistingNodes(selector, handleNodes, parentSelector);
    }
    observeDocumentWithTimeout((mutations) => handleMutations(mutations, handleNodes, selector, parentSelector));
  }
  var removeNodeTextNames = [
    "remove-node-text",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "remove-node-text.js",
    "ubo-remove-node-text.js",
    "rmnt.js",
    "ubo-rmnt.js",
    "ubo-remove-node-text",
    "ubo-rmnt"
  ];
  removeNodeText.primaryName = removeNodeTextNames[0];
  removeNodeText.injections = [
    observeDocumentWithTimeout,
    handleExistingNodes,
    handleMutations,
    replaceNodeText,
    isTargetNode,
    parseNodeTextParams,
    // following helpers should be imported and injected
    // because they are used by helpers above
    hit,
    nodeListToArray,
    getAddedNodes,
    toRegExp
  ];

  // src/scriptlets/trusted-replace-node-text.js
  function trustedReplaceNodeText(source, nodeName, textMatch, pattern, replacement, ...extraArgs) {
    const {
      selector,
      nodeNameMatch,
      textContentMatch,
      patternMatch
    } = parseNodeTextParams(nodeName, textMatch, pattern);
    const shouldLog = extraArgs.includes("verbose");
    const handleNodes = (nodes) => nodes.forEach((node) => {
      const shouldReplace = isTargetNode(
        node,
        nodeNameMatch,
        textContentMatch
      );
      if (shouldReplace) {
        if (shouldLog) {
          const originalText = node.textContent;
          if (originalText) {
            logMessage(source, `Original text content: ${originalText}`);
          }
        }
        replaceNodeText(source, node, patternMatch, replacement);
        if (shouldLog) {
          const modifiedText = node.textContent;
          if (modifiedText) {
            logMessage(source, `Modified text content: ${modifiedText}`);
          }
        }
      }
    });
    if (document.documentElement) {
      handleExistingNodes(selector, handleNodes);
    }
    observeDocumentWithTimeout((mutations) => handleMutations(mutations, handleNodes));
  }
  var trustedReplaceNodeTextNames = [
    "trusted-replace-node-text"
    // trusted scriptlets support no aliases
  ];
  trustedReplaceNodeText.primaryName = trustedReplaceNodeTextNames[0];
  trustedReplaceNodeText.injections = [
    observeDocumentWithTimeout,
    handleExistingNodes,
    handleMutations,
    replaceNodeText,
    isTargetNode,
    parseNodeTextParams,
    logMessage,
    // following helpers should be imported and injected
    // because they are used by helpers above
    hit,
    nodeListToArray,
    getAddedNodes,
    toRegExp
  ];

  // src/scriptlets/evaldata-prune.js
  function evalDataPrune(source, propsToRemove, requiredInitialProps, stack) {
    const prunePaths = getPrunePath(propsToRemove);
    const requiredPaths = getPrunePath(requiredInitialProps);
    const nativeObjects = {
      nativeStringify: window.JSON.stringify
    };
    const evalWrapper = (target, thisArg, args) => {
      let data = Reflect.apply(target, thisArg, args);
      if (typeof data === "object") {
        data = jsonPruner(source, data, prunePaths, requiredPaths, stack, nativeObjects);
      }
      return data;
    };
    const evalHandler = {
      apply: evalWrapper
    };
    window.eval = new Proxy(window.eval, evalHandler);
  }
  var evalDataPruneNames = [
    "evaldata-prune",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "evaldata-prune.js",
    "ubo-evaldata-prune.js",
    "ubo-evaldata-prune"
  ];
  evalDataPrune.primaryName = evalDataPruneNames[0];
  evalDataPrune.injections = [
    hit,
    matchStackTrace,
    getWildcardPropertyInChain,
    logMessage,
    toRegExp,
    isPruningNeeded,
    jsonPruner,
    getPrunePath,
    // following helpers are needed for helpers above
    getNativeRegexpTest,
    shouldAbortInlineOrInjectedScript,
    backupRegExpValues,
    restoreRegExpValues,
    isKeyInObject
  ];

  // src/scriptlets/trusted-prune-inbound-object.js
  function trustedPruneInboundObject(source, functionName, propsToRemove, requiredInitialProps, stack = "") {
    if (!functionName) {
      return;
    }
    const nativeObjects = {
      nativeStringify: window.JSON.stringify
    };
    const { base, prop } = getPropertyInChain(window, functionName);
    if (!base || !prop || typeof base[prop] !== "function") {
      const message = `${functionName} is not a function`;
      logMessage(source, message);
      return;
    }
    const prunePaths = getPrunePath(propsToRemove);
    const requiredPaths = getPrunePath(requiredInitialProps);
    const objectWrapper = (target, thisArg, args) => {
      let data = args[0];
      if (typeof data === "object") {
        data = jsonPruner(source, data, prunePaths, requiredPaths, stack, nativeObjects);
        args[0] = data;
      }
      return Reflect.apply(target, thisArg, args);
    };
    const objectHandler = {
      apply: objectWrapper
    };
    base[prop] = new Proxy(base[prop], objectHandler);
  }
  var trustedPruneInboundObjectNames = [
    "trusted-prune-inbound-object"
    // trusted scriptlets support no aliases
  ];
  trustedPruneInboundObject.primaryName = trustedPruneInboundObjectNames[0];
  trustedPruneInboundObject.injections = [
    hit,
    matchStackTrace,
    getPropertyInChain,
    getWildcardPropertyInChain,
    logMessage,
    isPruningNeeded,
    jsonPruner,
    getPrunePath,
    // following helpers are needed for helpers above
    toRegExp,
    getNativeRegexpTest,
    shouldAbortInlineOrInjectedScript,
    isEmptyObject,
    backupRegExpValues,
    restoreRegExpValues,
    isKeyInObject
  ];

  // src/scriptlets/trusted-set-attr.js
  function trustedSetAttr(source, selector, attr, value = "") {
    if (!selector || !attr) {
      return;
    }
    setAttributeBySelector(source, selector, attr, value);
    observeDOMChanges(() => setAttributeBySelector(source, selector, attr, value), true);
  }
  var trustedSetAttrNames = [
    "trusted-set-attr"
    // trusted scriptlets support no aliases
  ];
  trustedSetAttr.primaryName = trustedSetAttrNames[0];
  trustedSetAttr.injections = [
    setAttributeBySelector,
    observeDOMChanges,
    nativeIsNaN,
    // following helpers should be imported and injected
    // because they are used by helpers above
    defaultAttributeSetter,
    logMessage,
    throttle,
    hit
  ];

  // src/scriptlets/spoof-css.js
  function spoofCSS(source, selectors, cssPropertyName, cssPropertyValue) {
    if (!selectors) {
      return;
    }
    const uboAliases = [
      "spoof-css.js",
      "ubo-spoof-css.js",
      "ubo-spoof-css"
    ];
    function convertToCamelCase(cssProperty) {
      if (!cssProperty.includes("-")) {
        return cssProperty;
      }
      const splittedProperty = cssProperty.split("-");
      const firstPart = splittedProperty[0];
      const secondPart = splittedProperty[1];
      return `${firstPart}${secondPart[0].toUpperCase()}${secondPart.slice(1)}`;
    }
    const shouldDebug = !!(cssPropertyName === "debug" && cssPropertyValue);
    const propToValueMap = /* @__PURE__ */ new Map();
    if (uboAliases.includes(source.name)) {
      const { args } = source;
      let arrayOfProperties = [];
      const isDebug = args.at(-2);
      if (isDebug === "debug") {
        arrayOfProperties = args.slice(1, -2);
      } else {
        arrayOfProperties = args.slice(1);
      }
      for (let i = 0; i < arrayOfProperties.length; i += 2) {
        if (arrayOfProperties[i] === "") {
          break;
        }
        propToValueMap.set(convertToCamelCase(arrayOfProperties[i]), arrayOfProperties[i + 1]);
      }
    } else if (cssPropertyName && cssPropertyValue && !shouldDebug) {
      propToValueMap.set(convertToCamelCase(cssPropertyName), cssPropertyValue);
    }
    const spoofStyle = (cssProperty, realCssValue) => {
      return propToValueMap.has(cssProperty) ? propToValueMap.get(cssProperty) : realCssValue;
    };
    const setRectValue = (rect, prop, value) => {
      Object.defineProperty(
        rect,
        prop,
        {
          value: parseFloat(value)
        }
      );
    };
    const getter = (target, prop, receiver) => {
      hit(source);
      if (prop === "toString") {
        return target.toString.bind(target);
      }
      return Reflect.get(target, prop, receiver);
    };
    const getComputedStyleWrapper = (target, thisArg, args) => {
      if (shouldDebug) {
        debugger;
      }
      const style = Reflect.apply(target, thisArg, args);
      if (!args[0].matches(selectors)) {
        return style;
      }
      const proxiedStyle = new Proxy(style, {
        get(target2, prop) {
          const CSSStyleProp = target2[prop];
          if (typeof CSSStyleProp !== "function") {
            return spoofStyle(prop, CSSStyleProp || "");
          }
          if (prop !== "getPropertyValue") {
            return CSSStyleProp.bind(target2);
          }
          const getPropertyValueFunc = new Proxy(CSSStyleProp, {
            apply(target3, thisArg2, args2) {
              const cssName = args2[0];
              const cssValue = thisArg2[cssName];
              return spoofStyle(cssName, cssValue);
            },
            get: getter
          });
          return getPropertyValueFunc;
        },
        getOwnPropertyDescriptor(target2, prop) {
          if (propToValueMap.has(prop)) {
            return {
              configurable: true,
              enumerable: true,
              value: propToValueMap.get(prop),
              writable: true
            };
          }
          return Reflect.getOwnPropertyDescriptor(target2, prop);
        }
      });
      hit(source);
      return proxiedStyle;
    };
    const getComputedStyleHandler = {
      apply: getComputedStyleWrapper,
      get: getter
    };
    window.getComputedStyle = new Proxy(window.getComputedStyle, getComputedStyleHandler);
    const getBoundingClientRectWrapper = (target, thisArg, args) => {
      if (shouldDebug) {
        debugger;
      }
      const rect = Reflect.apply(target, thisArg, args);
      if (!thisArg.matches(selectors)) {
        return rect;
      }
      const {
        top,
        bottom,
        height,
        width,
        left,
        right
      } = rect;
      const newDOMRect = new window.DOMRect(rect.x, rect.y, top, bottom, width, height, left, right);
      if (propToValueMap.has("top")) {
        setRectValue(newDOMRect, "top", propToValueMap.get("top"));
      }
      if (propToValueMap.has("bottom")) {
        setRectValue(newDOMRect, "bottom", propToValueMap.get("bottom"));
      }
      if (propToValueMap.has("left")) {
        setRectValue(newDOMRect, "left", propToValueMap.get("left"));
      }
      if (propToValueMap.has("right")) {
        setRectValue(newDOMRect, "right", propToValueMap.get("right"));
      }
      if (propToValueMap.has("height")) {
        setRectValue(newDOMRect, "height", propToValueMap.get("height"));
      }
      if (propToValueMap.has("width")) {
        setRectValue(newDOMRect, "width", propToValueMap.get("width"));
      }
      hit(source);
      return newDOMRect;
    };
    const getBoundingClientRectHandler = {
      apply: getBoundingClientRectWrapper,
      get: getter
    };
    window.Element.prototype.getBoundingClientRect = new Proxy(
      window.Element.prototype.getBoundingClientRect,
      getBoundingClientRectHandler
    );
  }
  var spoofCSSNames = [
    "spoof-css",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "spoof-css.js",
    "ubo-spoof-css.js",
    "ubo-spoof-css"
  ];
  spoofCSS.primaryName = spoofCSSNames[0];
  spoofCSS.injections = [
    hit
  ];

  // src/scriptlets/call-nothrow.js
  function callNoThrow(source, functionName) {
    if (!functionName) {
      return;
    }
    const { base, prop } = getPropertyInChain(window, functionName);
    if (!base || !prop || typeof base[prop] !== "function") {
      const message = `${functionName} is not a function`;
      logMessage(source, message);
      return;
    }
    const objectWrapper = (...args) => {
      let result;
      try {
        result = Reflect.apply(...args);
      } catch (e) {
        const message = `Error calling ${functionName}: ${e.message}`;
        logMessage(source, message);
      }
      hit(source);
      return result;
    };
    const objectHandler = {
      apply: objectWrapper
    };
    base[prop] = new Proxy(base[prop], objectHandler);
  }
  var callNoThrowNames = [
    "call-nothrow",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "call-nothrow.js",
    "ubo-call-nothrow.js",
    "ubo-call-nothrow"
  ];
  callNoThrow.primaryName = callNoThrowNames[0];
  callNoThrow.injections = [
    hit,
    getPropertyInChain,
    logMessage,
    // following helpers are needed for helpers above
    isEmptyObject
  ];

  // src/scriptlets/trusted-create-element.ts
  function trustedCreateElement(source, parentSelector, tagName, attributePairs = "", textContent = "", cleanupDelayMs = NaN) {
    if (!parentSelector || !tagName) {
      return;
    }
    const IFRAME_WINDOW_NAME = "trusted-create-element-window";
    if (window.name === IFRAME_WINDOW_NAME) {
      return;
    }
    const logError = (prefix, error) => {
      logMessage(source, `${prefix} due to ${getErrorMessage(error)}`);
    };
    let element;
    try {
      element = document.createElement(tagName);
      element.textContent = textContent;
    } catch (e) {
      logError(`Cannot create element with tag name '${tagName}'`, e);
      return;
    }
    let attributes = [];
    try {
      attributes = parseAttributePairs(attributePairs);
    } catch (e) {
      logError(`Cannot parse attributePairs param: '${attributePairs}'`, e);
      return;
    }
    attributes.forEach((attr) => {
      try {
        element.setAttribute(attr.name, attr.value);
      } catch (e) {
        logError(`Cannot set attribute '${attr.name}' with value '${attr.value}'`, e);
      }
    });
    let timerId;
    let elementCreated = false;
    let elementRemoved = false;
    const findParentAndAppendEl = (parentElSelector, el, removeElDelayMs) => {
      let parentEl;
      try {
        parentEl = document.querySelector(parentElSelector);
      } catch (e) {
        logError(`Cannot find parent element by selector '${parentElSelector}'`, e);
        return false;
      }
      if (!parentEl) {
        logMessage(source, `No parent element found by selector: '${parentElSelector}'`);
        return false;
      }
      try {
        if (!parentEl.contains(el)) {
          parentEl.append(el);
        }
        if (el instanceof HTMLIFrameElement && el.contentWindow) {
          el.contentWindow.name = IFRAME_WINDOW_NAME;
        }
        elementCreated = true;
        hit(source);
      } catch (e) {
        logError(`Cannot append child to parent by selector '${parentElSelector}'`, e);
        return false;
      }
      if (!nativeIsNaN(removeElDelayMs)) {
        timerId = setTimeout(() => {
          el.remove();
          elementRemoved = true;
          clearTimeout(timerId);
        }, removeElDelayMs);
      }
      return true;
    };
    if (!findParentAndAppendEl(parentSelector, element, cleanupDelayMs)) {
      observeDocumentWithTimeout((mutations, observer) => {
        if (elementRemoved || elementCreated || findParentAndAppendEl(parentSelector, element, cleanupDelayMs)) {
          observer.disconnect();
        }
      });
    }
  }
  var trustedCreateElementNames = [
    "trusted-create-element"
    // trusted scriptlets support no aliases
  ];
  trustedCreateElement.primaryName = trustedCreateElementNames[0];
  trustedCreateElement.injections = [
    hit,
    logMessage,
    observeDocumentWithTimeout,
    nativeIsNaN,
    parseAttributePairs,
    getErrorMessage
  ];

  // src/scriptlets/href-sanitizer.ts
  function hrefSanitizer(source, selector, attribute = "text", transform = "") {
    if (!selector) {
      logMessage(source, "Selector is required.");
      return;
    }
    const BASE64_DECODE_TRANSFORM_MARKER = "base64decode";
    const REMOVE_HASH_TRANSFORM_MARKER = "removeHash";
    const REMOVE_PARAM_TRANSFORM_MARKER = "removeParam";
    const MARKER_SEPARATOR = ":";
    const COMMA = ",";
    const regexpNotValidAtStart = /^[^\x21-\x7e\p{Letter}]+/u;
    const regexpNotValidAtEnd = /[^\x21-\x7e\p{Letter}]+$/u;
    const extractNewHref = (anchor, attr) => {
      if (attr === "text") {
        if (!anchor.textContent) {
          return "";
        }
        return anchor.textContent.replace(regexpNotValidAtStart, "").replace(regexpNotValidAtEnd, "");
      }
      if (attr.startsWith("?")) {
        try {
          const url = new URL(anchor.href, document.location.href);
          return url.searchParams.get(attr.slice(1)) || "";
        } catch (ex) {
          logMessage(
            source,
            `Cannot retrieve the parameter '${attr.slice(1)}' from the URL '${anchor.href}`
          );
          return "";
        }
      }
      if (attr.startsWith("[") && attr.endsWith("]")) {
        return anchor.getAttribute(attr.slice(1, -1)) || "";
      }
      return "";
    };
    const isValidURL = (url) => {
      try {
        new URL(url);
        return true;
      } catch {
        return false;
      }
    };
    const getValidURL = (text) => {
      if (!text) {
        return null;
      }
      try {
        const { href, protocol } = new URL(text, document.location.href);
        if (protocol !== "http:" && protocol !== "https:") {
          logMessage(source, `Protocol not allowed: "${protocol}", from URL: "${href}"`);
          return null;
        }
        return href;
      } catch {
        return null;
      }
    };
    const isSanitizableAnchor = (element) => {
      return element.nodeName.toLowerCase() === "a" && element.hasAttribute("href");
    };
    const extractURLFromObject = (obj) => {
      for (const key in obj) {
        if (!Object.prototype.hasOwnProperty.call(obj, key)) {
          continue;
        }
        const value = obj[key];
        if (typeof value === "string" && isValidURL(value)) {
          return value;
        }
        if (typeof value === "object" && value !== null) {
          const result = extractURLFromObject(value);
          if (result) {
            return result;
          }
        }
      }
      return null;
    };
    const isStringifiedObject = (content) => content.startsWith("{") && content.endsWith("}");
    const decodeBase64SeveralTimes = (text, times) => {
      let result = text;
      for (let i = 0; i < times; i += 1) {
        try {
          result = atob(result);
        } catch (e) {
          if (result === text) {
            return "";
          }
        }
      }
      if (isValidURL(result)) {
        return result;
      }
      if (isStringifiedObject(result)) {
        try {
          const parsedResult = JSON.parse(result);
          return extractURLFromObject(parsedResult);
        } catch (ex) {
          return "";
        }
      }
      logMessage(source, `Failed to decode base64 string: ${text}`);
      return "";
    };
    const SEARCH_QUERY_MARKER = "?";
    const SEARCH_PARAMS_MARKER = "&";
    const HASHBANG_MARKER = "#!";
    const ANCHOR_MARKER = "#";
    const DECODE_ATTEMPTS_NUMBER = 10;
    const decodeSearchString = (search) => {
      const searchString = search.replace(SEARCH_QUERY_MARKER, "");
      let decodedParam;
      let validEncodedParam;
      if (searchString.includes(SEARCH_PARAMS_MARKER)) {
        const searchParamsArray = searchString.split(SEARCH_PARAMS_MARKER);
        searchParamsArray.forEach((param) => {
          decodedParam = decodeBase64SeveralTimes(param, DECODE_ATTEMPTS_NUMBER);
          if (decodedParam && decodedParam.length > 0) {
            validEncodedParam = decodedParam;
          }
        });
        return validEncodedParam;
      }
      return decodeBase64SeveralTimes(searchString, DECODE_ATTEMPTS_NUMBER);
    };
    const decodeHashString = (hash) => {
      let validEncodedHash = "";
      if (hash.includes(HASHBANG_MARKER)) {
        validEncodedHash = hash.replace(HASHBANG_MARKER, "");
      } else if (hash.includes(ANCHOR_MARKER)) {
        validEncodedHash = hash.replace(ANCHOR_MARKER, "");
      }
      return validEncodedHash ? decodeBase64SeveralTimes(validEncodedHash, DECODE_ATTEMPTS_NUMBER) : "";
    };
    const removeHash = (url) => {
      const urlObj = new URL(url, window.location.origin);
      if (!urlObj.hash) {
        return "";
      }
      urlObj.hash = "";
      return urlObj.toString();
    };
    const removeParam = (url, transformValue) => {
      const urlObj = new URL(url, window.location.origin);
      const paramNamesToRemoveStr = transformValue.split(MARKER_SEPARATOR)[1];
      if (!paramNamesToRemoveStr) {
        urlObj.search = "";
        return urlObj.toString();
      }
      const initSearchParamsLength = urlObj.searchParams.toString().length;
      const removeParams = paramNamesToRemoveStr.split(COMMA);
      removeParams.forEach((param) => {
        if (urlObj.searchParams.has(param)) {
          urlObj.searchParams.delete(param);
        }
      });
      if (initSearchParamsLength === urlObj.searchParams.toString().length) {
        return "";
      }
      return urlObj.toString();
    };
    const decodeBase64URL = (url) => {
      const { search, hash } = new URL(url, document.location.href);
      if (search.length > 0) {
        return decodeSearchString(search);
      }
      if (hash.length > 0) {
        return decodeHashString(hash);
      }
      logMessage(source, `Failed to execute base64 from URL: ${url}`);
      return null;
    };
    const base64Decode = (href) => {
      if (isValidURL(href)) {
        return decodeBase64URL(href) || "";
      }
      return decodeBase64SeveralTimes(href, DECODE_ATTEMPTS_NUMBER) || "";
    };
    const sanitize = (elementSelector) => {
      let elements;
      try {
        elements = document.querySelectorAll(elementSelector);
      } catch (e) {
        logMessage(source, `Invalid selector "${elementSelector}"`);
        return;
      }
      elements.forEach((elem) => {
        try {
          if (!isSanitizableAnchor(elem)) {
            logMessage(source, `${elem} is not a valid element to sanitize`);
            return;
          }
          let newHref = extractNewHref(elem, attribute);
          if (transform) {
            switch (true) {
              case transform === BASE64_DECODE_TRANSFORM_MARKER:
                newHref = base64Decode(newHref);
                break;
              case transform === REMOVE_HASH_TRANSFORM_MARKER:
                newHref = removeHash(newHref);
                break;
              case transform.startsWith(REMOVE_PARAM_TRANSFORM_MARKER): {
                newHref = removeParam(newHref, transform);
                break;
              }
              default:
                logMessage(source, `Invalid transform option: "${transform}"`);
                return;
            }
          }
          const newValidHref = getValidURL(newHref);
          if (!newValidHref) {
            logMessage(source, `Invalid URL: ${newHref}`);
            return;
          }
          const oldHref = elem.href;
          elem.setAttribute("href", newValidHref);
          if (newValidHref !== oldHref) {
            logMessage(source, `Sanitized "${oldHref}" to "${newValidHref}".`);
          }
        } catch (ex) {
          logMessage(source, `Failed to sanitize ${elem}.`);
        }
      });
      hit(source);
    };
    const run = () => {
      sanitize(selector);
      observeDOMChanges(() => sanitize(selector), true);
    };
    if (document.readyState === "loading") {
      window.addEventListener("DOMContentLoaded", run, { once: true });
    } else {
      run();
    }
  }
  var hrefSanitizerNames = [
    "href-sanitizer",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "href-sanitizer.js",
    "ubo-href-sanitizer.js",
    "ubo-href-sanitizer"
  ];
  hrefSanitizer.primaryName = hrefSanitizerNames[0];
  hrefSanitizer.injections = [
    observeDOMChanges,
    hit,
    logMessage,
    // following helpers should be imported and injected
    // because they are used by helpers above
    throttle
  ];

  // src/scriptlets/json-prune-fetch-response.ts
  function jsonPruneFetchResponse(source, propsToRemove, obligatoryProps, propsToMatch = "", stack = "") {
    if (typeof fetch === "undefined" || typeof Proxy === "undefined" || typeof Response === "undefined") {
      return;
    }
    const prunePaths = getPrunePath(propsToRemove);
    const requiredPaths = getPrunePath(obligatoryProps);
    const nativeStringify = window.JSON.stringify;
    const nativeRequestClone = window.Request.prototype.clone;
    const nativeResponseClone = window.Response.prototype.clone;
    const nativeFetch = window.fetch;
    const fetchHandlerWrapper = async (target, thisArg, args) => {
      const fetchData = getFetchData(args, nativeRequestClone);
      if (!matchRequestProps(source, propsToMatch, fetchData)) {
        return Reflect.apply(target, thisArg, args);
      }
      let originalResponse;
      let clonedResponse;
      try {
        originalResponse = await nativeFetch.apply(null, args);
        clonedResponse = nativeResponseClone.call(originalResponse);
      } catch {
        logMessage(source, `Could not make an original fetch request: ${fetchData.url}`);
        return Reflect.apply(target, thisArg, args);
      }
      let json;
      try {
        json = await originalResponse.json();
      } catch (e) {
        const message = `Response body can't be converted to json: ${objectToString(fetchData)}`;
        logMessage(source, message);
        return clonedResponse;
      }
      const modifiedJson = jsonPruner(source, json, prunePaths, requiredPaths, stack, {
        nativeStringify,
        nativeRequestClone,
        nativeResponseClone,
        nativeFetch
      });
      const forgedResponse = forgeResponse(
        originalResponse,
        nativeStringify(modifiedJson)
      );
      hit(source);
      return forgedResponse;
    };
    const fetchHandler = {
      apply: fetchHandlerWrapper
    };
    window.fetch = new Proxy(window.fetch, fetchHandler);
  }
  var jsonPruneFetchResponseNames = [
    "json-prune-fetch-response",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "json-prune-fetch-response.js",
    "ubo-json-prune-fetch-response.js",
    "ubo-json-prune-fetch-response"
  ];
  jsonPruneFetchResponse.primaryName = jsonPruneFetchResponseNames[0];
  jsonPruneFetchResponse.injections = [
    hit,
    logMessage,
    getFetchData,
    objectToString,
    matchRequestProps,
    jsonPruner,
    getPrunePath,
    forgeResponse,
    isPruningNeeded,
    matchStackTrace,
    toRegExp,
    isValidStrPattern,
    escapeRegExp,
    isEmptyObject,
    getRequestData,
    getRequestProps,
    parseMatchProps,
    isValidParsedData,
    getMatchPropsData,
    getWildcardPropertyInChain,
    shouldAbortInlineOrInjectedScript,
    getNativeRegexpTest,
    backupRegExpValues,
    restoreRegExpValues,
    isKeyInObject
  ];

  // src/scriptlets/no-protected-audience.ts
  function noProtectedAudience(source) {
    if (Document instanceof Object === false) {
      return;
    }
    const protectedAudienceMethods = {
      joinAdInterestGroup: noopResolveVoid,
      runAdAuction: noopResolveNull,
      leaveAdInterestGroup: noopResolveVoid,
      clearOriginJoinedAdInterestGroups: noopResolveVoid,
      createAuctionNonce: noopStr,
      updateAdInterestGroups: noopFunc
    };
    for (const key of Object.keys(protectedAudienceMethods)) {
      const methodName = key;
      const prototype = Navigator.prototype;
      if (!Object.prototype.hasOwnProperty.call(prototype, methodName) || prototype[methodName] instanceof Function === false) {
        continue;
      }
      prototype[methodName] = protectedAudienceMethods[methodName];
    }
    hit(source);
  }
  var noProtectedAudienceNames = [
    "no-protected-audience"
  ];
  noProtectedAudience.primaryName = noProtectedAudienceNames[0];
  noProtectedAudience.injections = [
    hit,
    noopStr,
    noopFunc,
    noopResolveVoid,
    noopResolveNull
  ];

  // src/scriptlets/trusted-suppress-native-method.ts
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

  // src/scriptlets/json-prune-xhr-response.ts
  function jsonPruneXhrResponse(source, propsToRemove, obligatoryProps, propsToMatch = "", stack = "") {
    if (typeof Proxy === "undefined") {
      return;
    }
    const shouldLog = !propsToRemove && !obligatoryProps;
    const prunePaths = getPrunePath(propsToRemove);
    const requiredPaths = getPrunePath(obligatoryProps);
    const nativeParse = window.JSON.parse;
    const nativeStringify = window.JSON.stringify;
    const nativeOpen = window.XMLHttpRequest.prototype.open;
    const nativeSend = window.XMLHttpRequest.prototype.send;
    const setRequestHeaderWrapper = (setRequestHeader, thisArgument, argsList) => {
      thisArgument.collectedHeaders.push(argsList);
      return Reflect.apply(setRequestHeader, thisArgument, argsList);
    };
    const setRequestHeaderHandler = {
      apply: setRequestHeaderWrapper
    };
    let xhrData;
    const openWrapper = (target, thisArg, args) => {
      xhrData = getXhrData.apply(null, args);
      if (matchRequestProps(source, propsToMatch, xhrData) || shouldLog) {
        thisArg.xhrShouldBePruned = true;
        thisArg.headersReceived = !!thisArg.headersReceived;
      }
      if (thisArg.xhrShouldBePruned && !thisArg.headersReceived) {
        thisArg.headersReceived = true;
        thisArg.collectedHeaders = [];
        thisArg.setRequestHeader = new Proxy(thisArg.setRequestHeader, setRequestHeaderHandler);
      }
      return Reflect.apply(target, thisArg, args);
    };
    const sendWrapper = (target, thisArg, args) => {
      const stackTrace = new Error().stack || "";
      if (!thisArg.xhrShouldBePruned || stack && !matchStackTrace(stack, stackTrace)) {
        return Reflect.apply(target, thisArg, args);
      }
      const forgedRequest = new XMLHttpRequest();
      forgedRequest.addEventListener("readystatechange", () => {
        if (forgedRequest.readyState !== 4) {
          return;
        }
        const {
          readyState,
          response,
          responseText,
          responseURL,
          responseXML,
          status,
          statusText
        } = forgedRequest;
        const content = responseText || response;
        if (typeof content !== "string" && typeof content !== "object") {
          return;
        }
        let modifiedContent;
        if (typeof content === "string") {
          try {
            const jsonContent = nativeParse(content);
            if (shouldLog) {
              logMessage(source, `${window.location.hostname}
${nativeStringify(jsonContent, null, 2)}
Stack trace:
${stackTrace}`, true);
              logMessage(source, jsonContent, true, false);
              modifiedContent = content;
            } else {
              modifiedContent = jsonPruner(
                source,
                jsonContent,
                prunePaths,
                requiredPaths,
                stack = "",
                {
                  nativeStringify
                }
              );
              try {
                const { responseType } = thisArg;
                switch (responseType) {
                  case "":
                  case "text":
                    modifiedContent = nativeStringify(modifiedContent);
                    break;
                  case "arraybuffer":
                    modifiedContent = new TextEncoder().encode(nativeStringify(modifiedContent)).buffer;
                    break;
                  case "blob":
                    modifiedContent = new Blob([nativeStringify(modifiedContent)]);
                    break;
                  default:
                    break;
                }
              } catch (error) {
                const message = `Response body cannot be converted to reponse type: '${content}'`;
                logMessage(source, message);
                modifiedContent = content;
              }
            }
          } catch (error) {
            const message = `Response body cannot be converted to json: '${content}'`;
            logMessage(source, message);
            modifiedContent = content;
          }
        }
        Object.defineProperties(thisArg, {
          // original values
          readyState: { value: readyState, writable: false },
          responseURL: { value: responseURL, writable: false },
          responseXML: { value: responseXML, writable: false },
          status: { value: status, writable: false },
          statusText: { value: statusText, writable: false },
          // modified values
          response: { value: modifiedContent, writable: false },
          responseText: { value: modifiedContent, writable: false }
        });
        setTimeout(() => {
          const stateEvent = new Event("readystatechange");
          thisArg.dispatchEvent(stateEvent);
          const loadEvent = new Event("load");
          thisArg.dispatchEvent(loadEvent);
          const loadEndEvent = new Event("loadend");
          thisArg.dispatchEvent(loadEndEvent);
        }, 1);
        hit(source);
      });
      nativeOpen.apply(forgedRequest, [xhrData.method, xhrData.url, Boolean(xhrData.async)]);
      thisArg.collectedHeaders.forEach((header) => {
        forgedRequest.setRequestHeader(header[0], header[1]);
      });
      thisArg.collectedHeaders = [];
      try {
        nativeSend.call(forgedRequest, args);
      } catch {
        return Reflect.apply(target, thisArg, args);
      }
      return void 0;
    };
    const openHandler = {
      apply: openWrapper
    };
    const sendHandler = {
      apply: sendWrapper
    };
    XMLHttpRequest.prototype.open = new Proxy(XMLHttpRequest.prototype.open, openHandler);
    XMLHttpRequest.prototype.send = new Proxy(XMLHttpRequest.prototype.send, sendHandler);
  }
  var jsonPruneXhrResponseNames = [
    "json-prune-xhr-response",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "json-prune-xhr-response.js",
    "ubo-json-prune-xhr-response.js",
    "ubo-json-prune-xhr-response"
  ];
  jsonPruneXhrResponse.primaryName = jsonPruneXhrResponseNames[0];
  jsonPruneXhrResponse.injections = [
    hit,
    logMessage,
    toRegExp,
    jsonPruner,
    getPrunePath,
    objectToString,
    matchRequestProps,
    getXhrData,
    isPruningNeeded,
    matchStackTrace,
    getMatchPropsData,
    getRequestProps,
    isValidParsedData,
    parseMatchProps,
    isValidStrPattern,
    escapeRegExp,
    isEmptyObject,
    getWildcardPropertyInChain,
    shouldAbortInlineOrInjectedScript,
    getNativeRegexpTest,
    backupRegExpValues,
    restoreRegExpValues,
    isKeyInObject
  ];

  // src/scriptlets/trusted-dispatch-event.ts
  function trustedDispatchEvent(source, event, target) {
    if (!event) {
      return;
    }
    let hasBeenDispatched = false;
    let eventTarget = document;
    if (target === "window") {
      eventTarget = window;
    }
    const events = /* @__PURE__ */ new Set();
    const dispatch = () => {
      const customEvent = new Event(event);
      if (typeof target === "string" && target !== "window") {
        eventTarget = document.querySelector(target);
      }
      const isEventAdded = events.has(event);
      if (!hasBeenDispatched && isEventAdded && eventTarget) {
        hasBeenDispatched = true;
        hit(source);
        eventTarget.dispatchEvent(customEvent);
      }
    };
    const wrapper = (eventListener, thisArg, args) => {
      const eventName = args[0];
      if (thisArg && eventName) {
        events.add(eventName);
        setTimeout(() => {
          dispatch();
        }, 1);
      }
      return Reflect.apply(eventListener, thisArg, args);
    };
    const handler = {
      apply: wrapper
    };
    EventTarget.prototype.addEventListener = new Proxy(EventTarget.prototype.addEventListener, handler);
  }
  var trustedDispatchEventNames = [
    "trusted-dispatch-event"
  ];
  trustedDispatchEvent.primaryName = trustedDispatchEventNames[0];
  trustedDispatchEvent.injections = [
    hit
  ];

  // src/scriptlets/trusted-replace-outbound-text.ts
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
    const decodeAndReplaceContent = (content, pattern, textReplacement, decode, log2) => {
      switch (decode) {
        case "base64":
          try {
            if (!isValidBase64(content)) {
              logMessage(source, `Text content is not a valid base64 encoded string: ${content}`);
              return content;
            }
            const decodedContent = atob(content);
            if (log2) {
              logMessage(source, `Decoded text content: ${decodedContent}`);
            }
            const modifiedContent = textToReplace ? decodedContent.replace(pattern, textReplacement) : decodedContent;
            if (log2) {
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

  // src/scriptlets/prevent-canvas.ts
  function preventCanvas(source, contextType) {
    const handlerWrapper = (target, thisArg, argumentsList) => {
      const type = argumentsList[0];
      let shouldPrevent = false;
      if (!contextType) {
        shouldPrevent = true;
      } else if (isValidMatchStr(contextType)) {
        const { isInvertedMatch, matchRegexp } = parseMatchArg(contextType);
        shouldPrevent = matchRegexp.test(type) !== isInvertedMatch;
      } else {
        logMessage(source, `Invalid contextType parameter: ${contextType}`);
        shouldPrevent = false;
      }
      if (shouldPrevent) {
        hit(source);
        return null;
      }
      return Reflect.apply(target, thisArg, argumentsList);
    };
    const canvasHandler = {
      apply: handlerWrapper
    };
    window.HTMLCanvasElement.prototype.getContext = new Proxy(
      window.HTMLCanvasElement.prototype.getContext,
      canvasHandler
    );
  }
  var preventCanvasNames = [
    "prevent-canvas",
    // aliases are needed for matching the related scriptlet converted into our syntax
    "prevent-canvas.js",
    "ubo-prevent-canvas.js",
    "ubo-prevent-canvas"
  ];
  preventCanvas.primaryName = preventCanvasNames[0];
  preventCanvas.injections = [
    hit,
    logMessage,
    parseMatchArg,
    isValidMatchStr,
    toRegExp,
    escapeRegExp,
    isValidStrPattern
  ];

  // src/redirects/amazon-apstag.js
  function AmazonApstag(source) {
    const apstagWrapper = {
      fetchBids(a, b) {
        if (typeof b === "function") {
          b([]);
        }
      },
      init: noopFunc,
      setDisplayBids: noopFunc,
      targetingKeys: noopFunc
    };
    window.apstag = apstagWrapper;
    hit(source);
  }
  var AmazonApstagNames = [
    "amazon-apstag",
    "ubo-amazon_apstag.js",
    "amazon_apstag.js"
  ];
  AmazonApstag.primaryName = AmazonApstagNames[0];
  AmazonApstag.injections = [hit, noopFunc];

  // src/redirects/didomi-loader.js
  function DidomiLoader(source) {
    function UserConsentStatusForVendorSubscribe() {
    }
    UserConsentStatusForVendorSubscribe.prototype.filter = function() {
      return new UserConsentStatusForVendorSubscribe();
    };
    UserConsentStatusForVendorSubscribe.prototype.subscribe = noopFunc;
    function UserConsentStatusForVendor() {
    }
    UserConsentStatusForVendor.prototype.first = function() {
      return new UserConsentStatusForVendorSubscribe();
    };
    UserConsentStatusForVendor.prototype.filter = function() {
      return new UserConsentStatusForVendorSubscribe();
    };
    UserConsentStatusForVendor.prototype.subscribe = noopFunc;
    const DidomiWrapper = {
      isConsentRequired: falseFunc,
      getUserConsentStatusForPurpose: trueFunc,
      getUserConsentStatus: trueFunc,
      getUserStatus: noopFunc,
      getRequiredPurposes: noopArray,
      getUserConsentStatusForVendor: trueFunc,
      Purposes: {
        Cookies: "cookies"
      },
      notice: {
        configure: noopFunc,
        hide: noopFunc,
        isVisible: falseFunc,
        show: noopFunc,
        showDataProcessing: trueFunc
      },
      isUserConsentStatusPartial: falseFunc,
      on() {
        return {
          actions: {},
          emitter: {},
          services: {},
          store: {}
        };
      },
      shouldConsentBeCollected: falseFunc,
      getUserConsentStatusForAll: noopFunc,
      getObservableOnUserConsentStatusForVendor() {
        return new UserConsentStatusForVendor();
      }
    };
    window.Didomi = DidomiWrapper;
    const didomiStateWrapper = {
      didomiExperimentId: "",
      didomiExperimentUserGroup: "",
      didomiGDPRApplies: 1,
      didomiIABConsent: "",
      didomiPurposesConsent: "",
      didomiPurposesConsentDenied: "",
      didomiPurposesConsentUnknown: "",
      didomiVendorsConsent: "",
      didomiVendorsConsentDenied: "",
      didomiVendorsConsentUnknown: "",
      didomiVendorsRawConsent: "",
      didomiVendorsRawConsentDenied: "",
      didomiVendorsRawConsentUnknown: ""
    };
    window.didomiState = didomiStateWrapper;
    const tcData = {
      eventStatus: "tcloaded",
      gdprApplies: false,
      listenerId: noopFunc,
      vendor: {
        consents: []
      },
      purpose: {
        consents: []
      }
    };
    const __tcfapiWrapper = function(command, version, callback) {
      if (typeof callback !== "function" || command === "removeEventListener") {
        return;
      }
      callback(tcData, true);
    };
    window.__tcfapi = __tcfapiWrapper;
    const didomiEventListenersWrapper = {
      stub: true,
      push: noopFunc
    };
    window.didomiEventListeners = didomiEventListenersWrapper;
    const didomiOnReadyWrapper = {
      stub: true,
      push(arg) {
        if (typeof arg !== "function") {
          return;
        }
        if (document.readyState !== "complete") {
          window.addEventListener("load", () => {
            setTimeout(arg(window.Didomi));
          });
        } else {
          setTimeout(arg(window.Didomi));
        }
      }
    };
    window.didomiOnReady = window.didomiOnReady || didomiOnReadyWrapper;
    if (Array.isArray(window.didomiOnReady)) {
      window.didomiOnReady.forEach((arg) => {
        if (typeof arg === "function") {
          try {
            setTimeout(arg(window.Didomi));
          } catch (e) {
          }
        }
      });
    }
    hit(source);
  }
  var DidomiLoaderNames = [
    "didomi-loader"
  ];
  DidomiLoader.primaryName = DidomiLoaderNames[0];
  DidomiLoader.injections = [
    hit,
    noopFunc,
    noopArray,
    trueFunc,
    falseFunc
  ];

  // src/redirects/fingerprintjs2.js
  function Fingerprintjs2(source) {
    let browserId = "";
    for (let i = 0; i < 8; i += 1) {
      browserId += (Math.random() * 65536 + 4096).toString(16).slice(-4);
    }
    const Fingerprint2 = function() {
    };
    Fingerprint2.get = function(options, callback) {
      if (!callback) {
        callback = options;
      }
      setTimeout(() => {
        if (callback) {
          callback(browserId, []);
        }
      }, 1);
    };
    Fingerprint2.prototype = {
      get: Fingerprint2.get
    };
    window.Fingerprint2 = Fingerprint2;
    hit(source);
  }
  var Fingerprintjs2Names = [
    "fingerprintjs2",
    // redirect aliases are needed for conversion:
    // prefixed for us
    "ubo-fingerprint2.js",
    // original ubo name
    "fingerprint2.js"
  ];
  Fingerprintjs2.primaryName = Fingerprintjs2Names[0];
  Fingerprintjs2.injections = [hit];

  // src/redirects/fingerprintjs3.js
  function Fingerprintjs3(source) {
    const visitorId = (() => {
      let id = "";
      for (let i = 0; i < 8; i += 1) {
        id += (Math.random() * 65536 + 4096).toString(16).slice(-4);
      }
      return id;
    })();
    const FingerprintJS = function() {
    };
    FingerprintJS.prototype = {
      load() {
        return Promise.resolve(new FingerprintJS());
      },
      get() {
        return Promise.resolve({
          visitorId
        });
      },
      hashComponents: noopStr
    };
    window.FingerprintJS = new FingerprintJS();
    hit(source);
  }
  var Fingerprintjs3Names = [
    "fingerprintjs3",
    // redirect aliases are needed for conversion:
    // prefixed for us
    "ubo-fingerprint3.js",
    // original ubo name
    "fingerprint3.js"
  ];
  Fingerprintjs3.primaryName = Fingerprintjs3Names[0];
  Fingerprintjs3.injections = [hit, noopStr];

  // src/redirects/gemius.js
  function Gemius(source) {
    const GemiusPlayer = function() {
    };
    GemiusPlayer.prototype = {
      setVideoObject: noopFunc,
      newProgram: noopFunc,
      programEvent: noopFunc,
      newAd: noopFunc,
      adEvent: noopFunc
    };
    window.GemiusPlayer = GemiusPlayer;
    hit(source);
  }
  var GemiusNames = [
    "gemius"
  ];
  Gemius.primaryName = GemiusNames[0];
  Gemius.injections = [hit, noopFunc];

  // src/redirects/google-analytics.js
  function GoogleAnalytics(source) {
    const Tracker = function() {
    };
    const proto = Tracker.prototype;
    proto.get = noopFunc;
    proto.set = noopFunc;
    proto.send = noopFunc;
    const googleAnalyticsName = window.GoogleAnalyticsObject || "ga";
    const queue = window[googleAnalyticsName]?.q;
    function ga(a) {
      const len = arguments.length;
      if (len === 0) {
        return;
      }
      const lastArg = arguments[len - 1];
      let replacer;
      if (lastArg instanceof Object && lastArg !== null && typeof lastArg.hitCallback === "function") {
        replacer = lastArg.hitCallback;
      } else if (typeof lastArg === "function") {
        replacer = () => {
          lastArg(ga.create());
        };
      }
      try {
        setTimeout(replacer, 1);
      } catch (ex) {
      }
    }
    ga.create = () => new Tracker();
    ga.getByName = () => new Tracker();
    ga.getAll = () => [new Tracker()];
    ga.remove = noopFunc;
    ga.loaded = true;
    window[googleAnalyticsName] = ga;
    if (Array.isArray(queue)) {
      const push = (arg) => {
        ga(...arg);
      };
      queue.push = push;
      queue.forEach(push);
    }
    const { dataLayer, google_optimize } = window;
    if (dataLayer instanceof Object === false) {
      return;
    }
    if (dataLayer.hide instanceof Object && typeof dataLayer.hide.end === "function") {
      dataLayer.hide.end();
    }
    const handleCallback = (dataObj, funcName) => {
      if (dataObj && typeof dataObj[funcName] === "function") {
        setTimeout(dataObj[funcName]);
      }
    };
    if (typeof dataLayer.push === "function") {
      dataLayer.push = (data) => {
        if (data instanceof Object) {
          handleCallback(data, "eventCallback");
          for (const key in data) {
            handleCallback(data[key], "event_callback");
          }
          if (!data.hasOwnProperty("eventCallback") && !data.hasOwnProperty("eventCallback")) {
            [].push.call(window.dataLayer, data);
          }
        }
        if (Array.isArray(data)) {
          data.forEach((arg) => {
            handleCallback(arg, "callback");
          });
        }
        return noopFunc;
      };
    }
    if (google_optimize instanceof Object && typeof google_optimize.get === "function") {
      const googleOptimizeWrapper = {
        get: noopFunc
      };
      window.google_optimize = googleOptimizeWrapper;
    }
    hit(source);
  }
  var GoogleAnalyticsNames = [
    "google-analytics",
    "ubo-google-analytics_analytics.js",
    "google-analytics_analytics.js",
    // https://github.com/AdguardTeam/Scriptlets/issues/127
    "googletagmanager-gtm",
    "ubo-googletagmanager_gtm.js",
    "googletagmanager_gtm.js"
  ];
  GoogleAnalytics.primaryName = GoogleAnalyticsNames[0];
  GoogleAnalytics.injections = [
    hit,
    noopFunc,
    noopNull,
    noopArray
  ];

  // src/redirects/google-analytics-ga.js
  function GoogleAnalyticsGa(source) {
    function Gaq() {
    }
    Gaq.prototype.Na = noopFunc;
    Gaq.prototype.O = noopFunc;
    Gaq.prototype.Sa = noopFunc;
    Gaq.prototype.Ta = noopFunc;
    Gaq.prototype.Va = noopFunc;
    Gaq.prototype._createAsyncTracker = noopFunc;
    Gaq.prototype._getAsyncTracker = noopFunc;
    Gaq.prototype._getPlugin = noopFunc;
    Gaq.prototype.push = (data) => {
      if (typeof data === "function") {
        data();
        return;
      }
      if (Array.isArray(data) === false) {
        return;
      }
      if (typeof data[0] === "string" && /(^|\.)_link$/.test(data[0]) && typeof data[1] === "string") {
        window.location.assign(data[1]);
      }
      if (data[0] === "_set" && data[1] === "hitCallback" && typeof data[2] === "function") {
        data[2]();
      }
    };
    const gaq = new Gaq();
    const asyncTrackers = window._gaq || [];
    if (Array.isArray(asyncTrackers)) {
      while (asyncTrackers[0]) {
        gaq.push(asyncTrackers.shift());
      }
    }
    window._gaq = gaq.qf = gaq;
    function Gat() {
    }
    const api = [
      "_addIgnoredOrganic",
      "_addIgnoredRef",
      "_addItem",
      "_addOrganic",
      "_addTrans",
      "_clearIgnoredOrganic",
      "_clearIgnoredRef",
      "_clearOrganic",
      "_cookiePathCopy",
      "_deleteCustomVar",
      "_getName",
      "_setAccount",
      "_getAccount",
      "_getClientInfo",
      "_getDetectFlash",
      "_getDetectTitle",
      "_getLinkerUrl",
      "_getLocalGifPath",
      "_getServiceMode",
      "_getVersion",
      "_getVisitorCustomVar",
      "_initData",
      "_link",
      "_linkByPost",
      "_setAllowAnchor",
      "_setAllowHash",
      "_setAllowLinker",
      "_setCampContentKey",
      "_setCampMediumKey",
      "_setCampNameKey",
      "_setCampNOKey",
      "_setCampSourceKey",
      "_setCampTermKey",
      "_setCampaignCookieTimeout",
      "_setCampaignTrack",
      "_setClientInfo",
      "_setCookiePath",
      "_setCookiePersistence",
      "_setCookieTimeout",
      "_setCustomVar",
      "_setDetectFlash",
      "_setDetectTitle",
      "_setDomainName",
      "_setLocalGifPath",
      "_setLocalRemoteServerMode",
      "_setLocalServerMode",
      "_setReferrerOverride",
      "_setRemoteServerMode",
      "_setSampleRate",
      "_setSessionTimeout",
      "_setSiteSpeedSampleRate",
      "_setSessionCookieTimeout",
      "_setVar",
      "_setVisitorCookieTimeout",
      "_trackEvent",
      "_trackPageLoadTime",
      "_trackPageview",
      "_trackSocial",
      "_trackTiming",
      "_trackTrans",
      "_visitCode"
    ];
    const tracker = api.reduce((res, funcName) => {
      res[funcName] = noopFunc;
      return res;
    }, {});
    tracker._getLinkerUrl = (a) => a;
    tracker._link = (url) => {
      if (typeof url !== "string") {
        return;
      }
      try {
        window.location.assign(url);
      } catch (e) {
        logMessage(source, e);
      }
    };
    Gat.prototype._anonymizeIP = noopFunc;
    Gat.prototype._createTracker = noopFunc;
    Gat.prototype._forceSSL = noopFunc;
    Gat.prototype._getPlugin = noopFunc;
    Gat.prototype._getTracker = () => tracker;
    Gat.prototype._getTrackerByName = () => tracker;
    Gat.prototype._getTrackers = noopFunc;
    Gat.prototype.aa = noopFunc;
    Gat.prototype.ab = noopFunc;
    Gat.prototype.hb = noopFunc;
    Gat.prototype.la = noopFunc;
    Gat.prototype.oa = noopFunc;
    Gat.prototype.pa = noopFunc;
    Gat.prototype.u = noopFunc;
    const gat = new Gat();
    window._gat = gat;
    hit(source);
  }
  var GoogleAnalyticsGaNames = [
    "google-analytics-ga",
    "ubo-google-analytics_ga.js",
    "google-analytics_ga.js"
  ];
  GoogleAnalyticsGa.primaryName = GoogleAnalyticsGaNames[0];
  GoogleAnalyticsGa.injections = [
    hit,
    noopFunc,
    logMessage
  ];

  // src/redirects/google-ima3.js
  function GoogleIma3(source) {
    const VERSION = "3.453.0";
    const ima = {};
    const AdDisplayContainer = function(containerElement) {
      const divElement = document.createElement("div");
      divElement.style.setProperty("display", "none", "important");
      divElement.style.setProperty("visibility", "collapse", "important");
      if (containerElement) {
        containerElement.appendChild(divElement);
      }
    };
    AdDisplayContainer.prototype.destroy = noopFunc;
    AdDisplayContainer.prototype.initialize = noopFunc;
    const ImaSdkSettings = function() {
    };
    ImaSdkSettings.CompanionBackfillMode = {
      ALWAYS: "always",
      ON_MASTER_AD: "on_master_ad"
    };
    ImaSdkSettings.VpaidMode = {
      DISABLED: 0,
      ENABLED: 1,
      INSECURE: 2
    };
    ImaSdkSettings.prototype = {
      c: true,
      f: {},
      i: false,
      l: "",
      p: "",
      r: 0,
      t: "",
      v: "",
      getCompanionBackfill: noopFunc,
      getDisableCustomPlaybackForIOS10Plus() {
        return this.i;
      },
      getDisabledFlashAds: () => true,
      getFeatureFlags() {
        return this.f;
      },
      getLocale() {
        return this.l;
      },
      getNumRedirects() {
        return this.r;
      },
      getPlayerType() {
        return this.t;
      },
      getPlayerVersion() {
        return this.v;
      },
      getPpid() {
        return this.p;
      },
      getVpaidMode() {
        return this.C;
      },
      isCookiesEnabled() {
        return this.c;
      },
      isVpaidAdapter() {
        return this.M;
      },
      setCompanionBackfill: noopFunc,
      setAutoPlayAdBreaks(a) {
        this.K = a;
      },
      setCookiesEnabled(c) {
        this.c = !!c;
      },
      setDisableCustomPlaybackForIOS10Plus(i) {
        this.i = !!i;
      },
      setDisableFlashAds: noopFunc,
      setFeatureFlags(f) {
        this.f = !!f;
      },
      setIsVpaidAdapter(a) {
        this.M = a;
      },
      setLocale(l) {
        this.l = !!l;
      },
      setNumRedirects(r) {
        this.r = !!r;
      },
      setPageCorrelator(a) {
        this.R = a;
      },
      setPlayerType(t) {
        this.t = !!t;
      },
      setPlayerVersion(v) {
        this.v = !!v;
      },
      setPpid(p) {
        this.p = !!p;
      },
      setVpaidMode(a) {
        this.C = a;
      },
      setSessionId: noopFunc,
      setStreamCorrelator: noopFunc,
      setVpaidAllowed: noopFunc,
      CompanionBackfillMode: {
        ALWAYS: "always",
        ON_MASTER_AD: "on_master_ad"
      },
      VpaidMode: {
        DISABLED: 0,
        ENABLED: 1,
        INSECURE: 2
      }
    };
    const EventHandler = function() {
      this.listeners = /* @__PURE__ */ new Map();
      this._dispatch = function(e) {
        let listeners = this.listeners.get(e.type);
        listeners = listeners ? listeners.values() : [];
        for (const listener of Array.from(listeners)) {
          try {
            listener(e);
          } catch (r) {
            logMessage(source, r);
          }
        }
      };
      this.addEventListener = function(types, callback, options, context) {
        if (!Array.isArray(types)) {
          types = [types];
        }
        for (let i = 0; i < types.length; i += 1) {
          const type = types[i];
          if (!this.listeners.has(type)) {
            this.listeners.set(type, /* @__PURE__ */ new Map());
          }
          this.listeners.get(type).set(callback, callback.bind(context || this));
        }
      };
      this.removeEventListener = function(types, callback) {
        if (!Array.isArray(types)) {
          types = [types];
        }
        for (let i = 0; i < types.length; i += 1) {
          const type = types[i];
          this.listeners.get(type)?.delete(callback);
        }
      };
    };
    const AdsManager = new EventHandler();
    AdsManager.volume = 1;
    AdsManager.collapse = noopFunc;
    AdsManager.configureAdsManager = noopFunc;
    AdsManager.destroy = noopFunc;
    AdsManager.discardAdBreak = noopFunc;
    AdsManager.expand = noopFunc;
    AdsManager.focus = noopFunc;
    AdsManager.getAdSkippableState = () => false;
    AdsManager.getCuePoints = () => [0];
    AdsManager.getCurrentAd = () => currentAd;
    AdsManager.getCurrentAdCuePoints = () => [];
    AdsManager.getRemainingTime = () => 0;
    AdsManager.getVolume = function() {
      return this.volume;
    };
    AdsManager.init = noopFunc;
    AdsManager.isCustomClickTrackingUsed = () => false;
    AdsManager.isCustomPlaybackUsed = () => false;
    AdsManager.pause = noopFunc;
    AdsManager.requestNextAdBreak = noopFunc;
    AdsManager.resize = noopFunc;
    AdsManager.resume = noopFunc;
    AdsManager.setVolume = function(v) {
      this.volume = v;
    };
    AdsManager.skip = noopFunc;
    AdsManager.start = function() {
      for (const type of [
        AdEvent.Type.ALL_ADS_COMPLETED,
        AdEvent.Type.CONTENT_RESUME_REQUESTED
      ]) {
        try {
          this._dispatch(new ima.AdEvent(type));
        } catch (e) {
          logMessage(source, e);
        }
      }
    };
    AdsManager.stop = noopFunc;
    AdsManager.updateAdsRenderingSettings = noopFunc;
    const manager = Object.create(AdsManager);
    const AdsManagerLoadedEvent = function(type, adsRequest, userRequestContext) {
      this.type = type;
      this.adsRequest = adsRequest;
      this.userRequestContext = userRequestContext;
    };
    AdsManagerLoadedEvent.prototype = {
      getAdsManager: () => manager,
      getUserRequestContext() {
        if (this.userRequestContext) {
          return this.userRequestContext;
        }
        return {};
      }
    };
    AdsManagerLoadedEvent.Type = {
      ADS_MANAGER_LOADED: "adsManagerLoaded"
    };
    const AdsLoader = EventHandler;
    AdsLoader.prototype.settings = new ImaSdkSettings();
    AdsLoader.prototype.contentComplete = noopFunc;
    AdsLoader.prototype.destroy = noopFunc;
    AdsLoader.prototype.getSettings = function() {
      return this.settings;
    };
    AdsLoader.prototype.getVersion = () => VERSION;
    AdsLoader.prototype.requestAds = function(adsRequest, userRequestContext) {
      requestAnimationFrame(() => {
        const { ADS_MANAGER_LOADED } = AdsManagerLoadedEvent.Type;
        const event = new ima.AdsManagerLoadedEvent(
          ADS_MANAGER_LOADED,
          adsRequest,
          userRequestContext
        );
        this._dispatch(event);
      });
      const e = new ima.AdError(
        "adPlayError",
        1205,
        1205,
        "The browser prevented playback initiated without user interaction.",
        adsRequest,
        userRequestContext
      );
      requestAnimationFrame(() => {
        this._dispatch(new ima.AdErrorEvent(e));
      });
    };
    const AdsRenderingSettings = noopFunc;
    const AdsRequest = function() {
    };
    AdsRequest.prototype = {
      setAdWillAutoPlay: noopFunc,
      setAdWillPlayMuted: noopFunc,
      setContinuousPlayback: noopFunc
    };
    const AdPodInfo = function() {
    };
    AdPodInfo.prototype = {
      getAdPosition: () => 1,
      getIsBumper: () => false,
      getMaxDuration: () => -1,
      getPodIndex: () => 1,
      getTimeOffset: () => 0,
      getTotalAds: () => 1
    };
    const UniversalAdIdInfo = function() {
    };
    UniversalAdIdInfo.prototype.getAdIdRegistry = function() {
      return "";
    };
    UniversalAdIdInfo.prototype.getAdIsValue = function() {
      return "";
    };
    const Ad = function() {
    };
    Ad.prototype = {
      pi: new AdPodInfo(),
      getAdId: () => "",
      getAdPodInfo() {
        return this.pi;
      },
      getAdSystem: () => "",
      getAdvertiserName: () => "",
      getApiFramework: () => null,
      getCompanionAds: () => [],
      getContentType: () => "",
      getCreativeAdId: () => "",
      getDealId: () => "",
      getDescription: () => "",
      getDuration: () => 8.5,
      getHeight: () => 0,
      getMediaUrl: () => null,
      getMinSuggestedDuration: () => -2,
      getSkipTimeOffset: () => -1,
      getSurveyUrl: () => null,
      getTitle: () => "",
      getTraffickingParametersString: () => "",
      getUiElements: () => [""],
      getUniversalAdIdRegistry: () => "unknown",
      getUniversalAdIds: () => [new UniversalAdIdInfo()],
      getUniversalAdIdValue: () => "unknown",
      getVastMediaBitrate: () => 0,
      getVastMediaHeight: () => 0,
      getVastMediaWidth: () => 0,
      getWidth: () => 0,
      getWrapperAdIds: () => [""],
      getWrapperAdSystems: () => [""],
      getWrapperCreativeIds: () => [""],
      isLinear: () => true,
      isSkippable() {
        return true;
      }
    };
    const CompanionAd = function() {
    };
    CompanionAd.prototype = {
      getAdSlotId: () => "",
      getContent: () => "",
      getContentType: () => "",
      getHeight: () => 1,
      getWidth: () => 1
    };
    const AdError = function(type, code, vast, message, adsRequest, userRequestContext) {
      this.errorCode = code;
      this.message = message;
      this.type = type;
      this.adsRequest = adsRequest;
      this.userRequestContext = userRequestContext;
      this.getErrorCode = function() {
        return this.errorCode;
      };
      this.getInnerError = function() {
        return null;
      };
      this.getMessage = function() {
        return this.message;
      };
      this.getType = function() {
        return this.type;
      };
      this.getVastErrorCode = function() {
        return this.vastErrorCode;
      };
      this.toString = function() {
        return `AdError ${this.errorCode}: ${this.message}`;
      };
    };
    AdError.ErrorCode = {};
    AdError.Type = {};
    const isEngadget = () => {
      try {
        for (const ctx of Object.values(window.vidible._getContexts())) {
          if (ctx.getPlayer()?.div?.innerHTML.includes("www.engadget.com")) {
            return true;
          }
        }
      } catch (e) {
      }
      return false;
    };
    const currentAd = isEngadget() ? void 0 : new Ad();
    const AdEvent = function(type) {
      this.type = type;
    };
    AdEvent.prototype = {
      getAd: () => currentAd,
      getAdData: () => {
      }
    };
    AdEvent.Type = {
      AD_BREAK_READY: "adBreakReady",
      AD_BUFFERING: "adBuffering",
      AD_CAN_PLAY: "adCanPlay",
      AD_METADATA: "adMetadata",
      AD_PROGRESS: "adProgress",
      ALL_ADS_COMPLETED: "allAdsCompleted",
      CLICK: "click",
      COMPLETE: "complete",
      CONTENT_PAUSE_REQUESTED: "contentPauseRequested",
      CONTENT_RESUME_REQUESTED: "contentResumeRequested",
      DURATION_CHANGE: "durationChange",
      EXPANDED_CHANGED: "expandedChanged",
      FIRST_QUARTILE: "firstQuartile",
      IMPRESSION: "impression",
      INTERACTION: "interaction",
      LINEAR_CHANGE: "linearChange",
      LINEAR_CHANGED: "linearChanged",
      LOADED: "loaded",
      LOG: "log",
      MIDPOINT: "midpoint",
      PAUSED: "pause",
      RESUMED: "resume",
      SKIPPABLE_STATE_CHANGED: "skippableStateChanged",
      SKIPPED: "skip",
      STARTED: "start",
      THIRD_QUARTILE: "thirdQuartile",
      USER_CLOSE: "userClose",
      VIDEO_CLICKED: "videoClicked",
      VIDEO_ICON_CLICKED: "videoIconClicked",
      VIEWABLE_IMPRESSION: "viewable_impression",
      VOLUME_CHANGED: "volumeChange",
      VOLUME_MUTED: "mute"
    };
    const AdErrorEvent = function(error) {
      this.error = error;
      this.type = "adError";
      this.getError = function() {
        return this.error;
      };
      this.getUserRequestContext = function() {
        if (this.error?.userRequestContext) {
          return this.error.userRequestContext;
        }
        return {};
      };
    };
    AdErrorEvent.Type = {
      AD_ERROR: "adError"
    };
    const CustomContentLoadedEvent = function() {
    };
    CustomContentLoadedEvent.Type = {
      CUSTOM_CONTENT_LOADED: "deprecated-event"
    };
    const CompanionAdSelectionSettings = function() {
    };
    CompanionAdSelectionSettings.CreativeType = {
      ALL: "All",
      FLASH: "Flash",
      IMAGE: "Image"
    };
    CompanionAdSelectionSettings.ResourceType = {
      ALL: "All",
      HTML: "Html",
      IFRAME: "IFrame",
      STATIC: "Static"
    };
    CompanionAdSelectionSettings.SizeCriteria = {
      IGNORE: "IgnoreSize",
      SELECT_EXACT_MATCH: "SelectExactMatch",
      SELECT_NEAR_MATCH: "SelectNearMatch"
    };
    const AdCuePoints = function() {
    };
    AdCuePoints.prototype = {
      getCuePoints: () => [],
      getAdIdRegistry: () => "",
      getAdIdValue: () => ""
    };
    const AdProgressData = noopFunc;
    Object.assign(ima, {
      AdCuePoints,
      AdDisplayContainer,
      AdError,
      AdErrorEvent,
      AdEvent,
      AdPodInfo,
      AdProgressData,
      AdsLoader,
      AdsManager: manager,
      AdsManagerLoadedEvent,
      AdsRenderingSettings,
      AdsRequest,
      CompanionAd,
      CompanionAdSelectionSettings,
      CustomContentLoadedEvent,
      gptProxyInstance: {},
      ImaSdkSettings,
      OmidAccessMode: {
        DOMAIN: "domain",
        FULL: "full",
        LIMITED: "limited"
      },
      OmidVerificationVendor: {
        1: "OTHER",
        2: "MOAT",
        3: "DOUBLEVERIFY",
        4: "INTEGRAL_AD_SCIENCE",
        5: "PIXELATE",
        6: "NIELSEN",
        7: "COMSCORE",
        8: "MEETRICS",
        9: "GOOGLE",
        OTHER: 1,
        MOAT: 2,
        DOUBLEVERIFY: 3,
        INTEGRAL_AD_SCIENCE: 4,
        PIXELATE: 5,
        NIELSEN: 6,
        COMSCORE: 7,
        MEETRICS: 8,
        GOOGLE: 9
      },
      settings: new ImaSdkSettings(),
      UiElements: {
        AD_ATTRIBUTION: "adAttribution",
        COUNTDOWN: "countdown"
      },
      UniversalAdIdInfo,
      VERSION,
      ViewMode: {
        FULLSCREEN: "fullscreen",
        NORMAL: "normal"
      }
    });
    if (!window.google) {
      window.google = {};
    }
    if (window.google.ima?.dai) {
      ima.dai = window.google.ima.dai;
    }
    window.google.ima = ima;
    hit(source);
  }
  var GoogleIma3Names = [
    "google-ima3",
    // prefixed name
    "ubo-google-ima.js",
    // original ubo name
    "google-ima.js"
  ];
  GoogleIma3.primaryName = GoogleIma3Names[0];
  GoogleIma3.injections = [
    hit,
    noopFunc,
    logMessage
  ];

  // src/redirects/googlesyndication-adsbygoogle.js
  function GoogleSyndicationAdsByGoogle(source) {
    window.adsbygoogle = {
      // https://github.com/AdguardTeam/Scriptlets/issues/113
      // length: 0,
      loaded: true,
      // https://github.com/AdguardTeam/Scriptlets/issues/184
      push(arg) {
        if (typeof this.length === "undefined") {
          this.length = 0;
          this.length += 1;
        }
        if (arg !== null && arg instanceof Object && arg.constructor.name === "Object") {
          for (const key of Object.keys(arg)) {
            if (typeof arg[key] === "function") {
              try {
                arg[key].call(this, {});
              } catch {
              }
            }
          }
        }
      }
    };
    const adElems = document.querySelectorAll(".adsbygoogle");
    const css = "height:1px!important;max-height:1px!important;max-width:1px!important;width:1px!important;";
    const statusAttrName = "data-adsbygoogle-status";
    const ASWIFT_IFRAME_MARKER = "aswift_";
    const GOOGLE_ADS_IFRAME_MARKER = "google_ads_iframe_";
    let executed = false;
    for (let i = 0; i < adElems.length; i += 1) {
      const adElemChildNodes = adElems[i].childNodes;
      const childNodesQuantity = adElemChildNodes.length;
      let areIframesDefined = false;
      if (childNodesQuantity > 0) {
        areIframesDefined = childNodesQuantity === 2 && adElemChildNodes[0].nodeName.toLowerCase() === "iframe" && adElemChildNodes[0].id.includes(ASWIFT_IFRAME_MARKER) && adElemChildNodes[1].nodeName.toLowerCase() === "iframe" && adElemChildNodes[1].id.includes(GOOGLE_ADS_IFRAME_MARKER);
      }
      if (!areIframesDefined) {
        adElems[i].setAttribute(statusAttrName, "done");
        const aswiftIframe = document.createElement("iframe");
        aswiftIframe.id = `${ASWIFT_IFRAME_MARKER}${i}`;
        aswiftIframe.style = css;
        adElems[i].appendChild(aswiftIframe);
        const innerAswiftIframe = document.createElement("iframe");
        aswiftIframe.contentWindow.document.body.appendChild(innerAswiftIframe);
        const googleadsIframe = document.createElement("iframe");
        googleadsIframe.id = `${GOOGLE_ADS_IFRAME_MARKER}${i}`;
        googleadsIframe.style = css;
        adElems[i].appendChild(googleadsIframe);
        const innerGoogleadsIframe = document.createElement("iframe");
        googleadsIframe.contentWindow.document.body.appendChild(innerGoogleadsIframe);
        executed = true;
      }
    }
    if (executed) {
      hit(source);
    }
  }
  var GoogleSyndicationAdsByGoogleNames = [
    "googlesyndication-adsbygoogle",
    "ubo-googlesyndication_adsbygoogle.js",
    "googlesyndication_adsbygoogle.js"
  ];
  GoogleSyndicationAdsByGoogle.primaryName = GoogleSyndicationAdsByGoogleNames[0];
  GoogleSyndicationAdsByGoogle.injections = [
    hit
  ];

  // src/redirects/googletagservices-gpt.js
  function GoogleTagServicesGpt(source) {
    const slots = /* @__PURE__ */ new Map();
    const slotsById = /* @__PURE__ */ new Map();
    const slotsPerPath = /* @__PURE__ */ new Map();
    const slotCreatives = /* @__PURE__ */ new Map();
    const eventCallbacks = /* @__PURE__ */ new Map();
    const gTargeting = /* @__PURE__ */ new Map();
    const addEventListener = function(name, listener) {
      if (!eventCallbacks.has(name)) {
        eventCallbacks.set(name, /* @__PURE__ */ new Set());
      }
      eventCallbacks.get(name).add(listener);
      return this;
    };
    const removeEventListener = function(name, listener) {
      if (eventCallbacks.has(name)) {
        return eventCallbacks.get(name).delete(listener);
      }
      return false;
    };
    const fireSlotEvent = (name, slot) => {
      return new Promise((resolve) => {
        requestAnimationFrame(() => {
          const size = [0, 0];
          const callbacksSet = eventCallbacks.get(name) || [];
          const callbackArray = Array.from(callbacksSet);
          for (let i = 0; i < callbackArray.length; i += 1) {
            callbackArray[i]({ isEmpty: true, size, slot });
          }
          resolve();
        });
      });
    };
    const emptySlotElement = (slot) => {
      const node = document.getElementById(slot.getSlotElementId());
      while (node?.lastChild) {
        node.lastChild.remove();
      }
    };
    const recreateIframeForSlot = (slot) => {
      const eid = `google_ads_iframe_${slot.getId()}`;
      document.getElementById(eid)?.remove();
      const node = document.getElementById(slot.getSlotElementId());
      if (node) {
        const f = document.createElement("iframe");
        f.id = eid;
        f.srcdoc = "<body></body>";
        f.style = "position:absolute; width:0; height:0; left:0; right:0; z-index:-1; border:0";
        f.setAttribute("width", 0);
        f.setAttribute("height", 0);
        f.setAttribute("data-load-complete", true);
        f.setAttribute("data-google-container-id", true);
        f.setAttribute("sandbox", "");
        node.appendChild(f);
      }
    };
    const displaySlot = (slot) => {
      if (!slot) {
        return;
      }
      const id = slot.getSlotElementId();
      if (!document.getElementById(id)) {
        return;
      }
      const parent = document.getElementById(id);
      if (parent) {
        parent.appendChild(document.createElement("div"));
      }
      emptySlotElement(slot);
      recreateIframeForSlot(slot);
      fireSlotEvent("slotRenderEnded", slot);
      fireSlotEvent("slotRequested", slot);
      fireSlotEvent("slotResponseReceived", slot);
      fireSlotEvent("slotOnload", slot);
      fireSlotEvent("impressionViewable", slot);
    };
    const companionAdsService = {
      addEventListener,
      removeEventListener,
      enableSyncLoading: noopFunc,
      setRefreshUnfilledSlots: noopFunc,
      getSlots: noopArray
    };
    const contentService = {
      addEventListener,
      removeEventListener,
      setContent: noopFunc
    };
    function PassbackSlot() {
    }
    PassbackSlot.prototype.display = noopFunc;
    PassbackSlot.prototype.get = noopNull;
    PassbackSlot.prototype.set = noopThis;
    PassbackSlot.prototype.setClickUrl = noopThis;
    PassbackSlot.prototype.setTagForChildDirectedTreatment = noopThis;
    PassbackSlot.prototype.setTargeting = noopThis;
    PassbackSlot.prototype.updateTargetingFromMap = noopThis;
    function SizeMappingBuilder() {
    }
    SizeMappingBuilder.prototype.addSize = noopThis;
    SizeMappingBuilder.prototype.build = noopNull;
    const getTargetingValue = (v) => {
      if (typeof v === "string") {
        return [v];
      }
      try {
        return Array.prototype.flat.call(v);
      } catch {
      }
      return [];
    };
    const updateTargeting = (targeting, map) => {
      if (typeof map === "object") {
        for (const key in map) {
          if (Object.prototype.hasOwnProperty.call(map, key)) {
            targeting.set(key, getTargetingValue(map[key]));
          }
        }
      }
    };
    const defineSlot = (adUnitPath, creatives, optDiv) => {
      if (slotsById.has(optDiv)) {
        document.getElementById(optDiv)?.remove();
        return slotsById.get(optDiv);
      }
      const attributes = /* @__PURE__ */ new Map();
      const targeting = /* @__PURE__ */ new Map();
      const exclusions = /* @__PURE__ */ new Set();
      const response = {
        advertiserId: void 0,
        campaignId: void 0,
        creativeId: void 0,
        creativeTemplateId: void 0,
        lineItemId: void 0
      };
      const sizes = [
        {
          getHeight: () => 2,
          getWidth: () => 2
        }
      ];
      const num = (slotsPerPath.get(adUnitPath) || 0) + 1;
      slotsPerPath.set(adUnitPath, num);
      const id = `${adUnitPath}_${num}`;
      let clickUrl = "";
      let collapseEmptyDiv = null;
      const services = /* @__PURE__ */ new Set();
      const slot = {
        addService(e) {
          services.add(e);
          return slot;
        },
        clearCategoryExclusions: noopThis,
        clearTargeting(k) {
          if (k === void 0) {
            targeting.clear();
          } else {
            targeting.delete(k);
          }
        },
        defineSizeMapping(mapping) {
          slotCreatives.set(optDiv, mapping);
          return this;
        },
        get: (k) => attributes.get(k),
        getAdUnitPath: () => adUnitPath,
        getAttributeKeys: () => Array.from(attributes.keys()),
        getCategoryExclusions: () => Array.from(exclusions),
        getClickUrl: () => clickUrl,
        getCollapseEmptyDiv: () => collapseEmptyDiv,
        getContentUrl: () => "",
        getDivStartsCollapsed: () => null,
        getDomId: () => optDiv,
        getEscapedQemQueryId: () => "",
        getFirstLook: () => 0,
        getId: () => id,
        getHtml: () => "",
        getName: () => id,
        getOutOfPage: () => false,
        getResponseInformation: () => response,
        getServices: () => Array.from(services),
        getSizes: () => sizes,
        getSlotElementId: () => optDiv,
        getSlotId: () => slot,
        getTargeting: (k) => targeting.get(k) || gTargeting.get(k) || [],
        getTargetingKeys: () => Array.from(
          new Set(Array.of(...gTargeting.keys(), ...targeting.keys()))
        ),
        getTargetingMap: () => Object.assign(
          Object.fromEntries(gTargeting.entries()),
          Object.fromEntries(targeting.entries())
        ),
        set(k, v) {
          attributes.set(k, v);
          return slot;
        },
        setCategoryExclusion(e) {
          exclusions.add(e);
          return slot;
        },
        setClickUrl(u) {
          clickUrl = u;
          return slot;
        },
        setCollapseEmptyDiv(v) {
          collapseEmptyDiv = !!v;
          return slot;
        },
        setSafeFrameConfig: noopThis,
        setTagForChildDirectedTreatment: noopThis,
        setTargeting(k, v) {
          targeting.set(k, getTargetingValue(v));
          return slot;
        },
        toString: () => id,
        updateTargetingFromMap(map) {
          updateTargeting(targeting, map);
          return slot;
        }
      };
      slots.set(adUnitPath, slot);
      slotsById.set(optDiv, slot);
      slotCreatives.set(optDiv, creatives);
      return slot;
    };
    const pubAdsService = {
      addEventListener,
      removeEventListener,
      clear: noopFunc,
      clearCategoryExclusions: noopThis,
      clearTagForChildDirectedTreatment: noopThis,
      clearTargeting(k) {
        if (k === void 0) {
          gTargeting.clear();
        } else {
          gTargeting.delete(k);
        }
      },
      collapseEmptyDivs: noopFunc,
      defineOutOfPagePassback() {
        return new PassbackSlot();
      },
      definePassback() {
        return new PassbackSlot();
      },
      disableInitialLoad: noopFunc,
      display: noopFunc,
      enableAsyncRendering: noopFunc,
      enableLazyLoad: noopFunc,
      enableSingleRequest: noopFunc,
      enableSyncRendering: noopFunc,
      enableVideoAds: noopFunc,
      get: noopNull,
      getAttributeKeys: noopArray,
      getTargeting: noopArray,
      getTargetingKeys: noopArray,
      getSlots: noopArray,
      isInitialLoadDisabled: trueFunc,
      refresh: noopFunc,
      set: noopThis,
      setCategoryExclusion: noopThis,
      setCentering: noopFunc,
      setCookieOptions: noopThis,
      setForceSafeFrame: noopThis,
      setLocation: noopThis,
      setPrivacySettings: noopThis,
      setPublisherProvidedId: noopThis,
      setRequestNonPersonalizedAds: noopThis,
      setSafeFrameConfig: noopThis,
      setTagForChildDirectedTreatment: noopThis,
      setTargeting: noopThis,
      setVideoContent: noopThis,
      updateCorrelator: noopFunc
    };
    const { googletag = {} } = window;
    const { cmd = [] } = googletag;
    googletag.apiReady = true;
    googletag.cmd = [];
    googletag.cmd.push = (a) => {
      try {
        a();
      } catch (ex) {
      }
      return 1;
    };
    googletag.companionAds = () => companionAdsService;
    googletag.content = () => contentService;
    googletag.defineOutOfPageSlot = defineSlot;
    googletag.defineSlot = defineSlot;
    googletag.destroySlots = function() {
      slots.clear();
      slotsById.clear();
    };
    googletag.disablePublisherConsole = noopFunc;
    googletag.display = function(arg) {
      let id;
      if (arg?.getSlotElementId) {
        id = arg.getSlotElementId();
      } else if (arg?.nodeType) {
        id = arg.id;
      } else {
        id = String(arg);
      }
      displaySlot(slotsById.get(id));
    };
    googletag.enableServices = noopFunc;
    googletag.getVersion = noopStr;
    googletag.pubads = () => pubAdsService;
    googletag.pubadsReady = true;
    googletag.setAdIframeTitle = noopFunc;
    googletag.sizeMapping = () => new SizeMappingBuilder();
    window.googletag = googletag;
    while (cmd.length !== 0) {
      googletag.cmd.push(cmd.shift());
    }
    hit(source);
  }
  var GoogleTagServicesGptNames = [
    "googletagservices-gpt",
    "ubo-googletagservices_gpt.js",
    "googletagservices_gpt.js"
  ];
  GoogleTagServicesGpt.primaryName = GoogleTagServicesGptNames[0];
  GoogleTagServicesGpt.injections = [
    hit,
    noopFunc,
    noopThis,
    noopNull,
    noopArray,
    noopStr,
    trueFunc
  ];

  // src/redirects/matomo.js
  function Matomo(source) {
    const Tracker = function() {
    };
    Tracker.prototype.setDoNotTrack = noopFunc;
    Tracker.prototype.setDomains = noopFunc;
    Tracker.prototype.setCustomDimension = noopFunc;
    Tracker.prototype.trackPageView = noopFunc;
    const AsyncTracker = function() {
    };
    AsyncTracker.prototype.addListener = noopFunc;
    const matomoWrapper = {
      getTracker: Tracker,
      getAsyncTracker: AsyncTracker
    };
    window.Piwik = matomoWrapper;
    hit(source);
  }
  var MatomoNames = ["matomo"];
  Matomo.primaryName = MatomoNames[0];
  Matomo.injections = [hit, noopFunc];

  // src/redirects/metrika-yandex-tag.js
  function metrikaYandexTag(source) {
    const asyncCallbackFromOptions = (id, param, options = {}) => {
      let { callback } = options;
      const { ctx } = options;
      if (typeof callback === "function") {
        callback = ctx !== void 0 ? callback.bind(ctx) : callback;
        setTimeout(() => callback());
      }
    };
    const addFileExtension = noopFunc;
    const extLink = asyncCallbackFromOptions;
    const file = asyncCallbackFromOptions;
    const getClientID = (id, cb) => {
      if (!cb) {
        return;
      }
      setTimeout(cb(null));
    };
    const hitFunc = asyncCallbackFromOptions;
    const notBounce = asyncCallbackFromOptions;
    const params = noopFunc;
    const reachGoal = (id, target, params2, callback, ctx) => {
      asyncCallbackFromOptions(null, null, { callback, ctx });
    };
    const setUserID = noopFunc;
    const userParams = noopFunc;
    const destruct = noopFunc;
    const api = {
      addFileExtension,
      extLink,
      file,
      getClientID,
      hit: hitFunc,
      notBounce,
      params,
      reachGoal,
      setUserID,
      userParams,
      destruct
    };
    function init(id) {
      window[`yaCounter${id}`] = api;
      document.dispatchEvent(new Event(`yacounter${id}inited`));
    }
    function ym(id, funcName, ...args) {
      if (funcName === "init") {
        return init(id);
      }
      return api[funcName] && api[funcName](id, ...args);
    }
    if (typeof window.ym === "undefined") {
      window.ym = ym;
      ym.a = [];
    } else if (window.ym && window.ym.a) {
      ym.a = window.ym.a;
      window.ym = ym;
      window.ym.a.forEach((params2) => {
        const id = params2[0];
        init(id);
      });
    }
    hit(source);
  }
  var metrikaYandexTagNames = [
    "metrika-yandex-tag"
  ];
  metrikaYandexTag.primaryName = metrikaYandexTagNames[0];
  metrikaYandexTag.injections = [hit, noopFunc];

  // src/redirects/metrika-yandex-watch.js
  function metrikaYandexWatch(source) {
    const cbName = "yandex_metrika_callbacks";
    const asyncCallbackFromOptions = (options = {}) => {
      let { callback } = options;
      const { ctx } = options;
      if (typeof callback === "function") {
        callback = ctx !== void 0 ? callback.bind(ctx) : callback;
        setTimeout(() => callback());
      }
    };
    function Metrika() {
    }
    Metrika.counters = noopArray;
    Metrika.prototype.addFileExtension = noopFunc;
    Metrika.prototype.getClientID = noopFunc;
    Metrika.prototype.setUserID = noopFunc;
    Metrika.prototype.userParams = noopFunc;
    Metrika.prototype.params = noopFunc;
    Metrika.prototype.counters = noopArray;
    Metrika.prototype.extLink = (url, options) => {
      asyncCallbackFromOptions(options);
    };
    Metrika.prototype.file = (url, options) => {
      asyncCallbackFromOptions(options);
    };
    Metrika.prototype.hit = (url, options) => {
      asyncCallbackFromOptions(options);
    };
    Metrika.prototype.reachGoal = (target, params, cb, ctx) => {
      asyncCallbackFromOptions({ callback: cb, ctx });
    };
    Metrika.prototype.notBounce = asyncCallbackFromOptions;
    if (window.Ya) {
      window.Ya.Metrika = Metrika;
    } else {
      window.Ya = { Metrika };
    }
    if (window[cbName] && Array.isArray(window[cbName])) {
      window[cbName].forEach((func) => {
        if (typeof func === "function") {
          func();
        }
      });
    }
    hit(source);
  }
  var metrikaYandexWatchNames = [
    "metrika-yandex-watch"
  ];
  metrikaYandexWatch.primaryName = metrikaYandexWatchNames[0];
  metrikaYandexWatch.injections = [hit, noopFunc, noopArray];

  // src/redirects/naver-wcslog.js
  function NaverWcslog(source) {
    window.wcs_add = {};
    window.wcs_do = noopFunc;
    window.wcs = {
      inflow: noopFunc
    };
    hit(source);
  }
  var NaverWcslogNames = ["naver-wcslog"];
  NaverWcslog.primaryName = NaverWcslogNames[0];
  NaverWcslog.injections = [hit, noopFunc];

  // src/redirects/pardot-1.0.js
  function Pardot(source) {
    window.piVersion = "1.0.2";
    window.piScriptNum = 0;
    window.piScriptObj = [];
    window.checkNamespace = noopFunc;
    window.getPardotUrl = noopStr;
    window.piGetParameter = noopNull;
    window.piSetCookie = noopFunc;
    window.piGetCookie = noopStr;
    function piTracker() {
      window.pi = {
        tracker: {
          visitor_id: "",
          visitor_id_sign: "",
          pi_opt_in: "",
          campaign_id: ""
        }
      };
      window.piScriptNum += 1;
    }
    window.piResponse = noopFunc;
    window.piTracker = piTracker;
    piTracker();
    hit(source);
  }
  var PardotNames = ["pardot-1.0"];
  Pardot.primaryName = PardotNames[0];
  Pardot.injections = [
    hit,
    noopFunc,
    noopStr,
    noopNull
  ];

  // src/redirects/prebid.js
  function Prebid(source) {
    const pushFunction = function(arg) {
      if (typeof arg === "function") {
        try {
          arg.call();
        } catch (ex) {
        }
      }
    };
    const pbjsWrapper = {
      addAdUnits() {
      },
      adServers: {
        dfp: {
          // https://docs.prebid.org/dev-docs/publisher-api-reference/adServers.dfp.buildVideoUrl.html
          // returns ad URL
          buildVideoUrl: noopStr
        }
      },
      adUnits: [],
      aliasBidder() {
      },
      cmd: [],
      enableAnalytics() {
      },
      getHighestCpmBids: noopArray,
      libLoaded: true,
      que: [],
      requestBids(arg) {
        if (arg instanceof Object && arg.bidsBackHandler) {
          try {
            arg.bidsBackHandler.call();
          } catch (ex) {
          }
        }
      },
      removeAdUnit() {
      },
      setBidderConfig() {
      },
      setConfig() {
      },
      setTargetingForGPTAsync() {
      }
    };
    pbjsWrapper.cmd.push = pushFunction;
    pbjsWrapper.que.push = pushFunction;
    window.pbjs = pbjsWrapper;
    hit(source);
  }
  var PrebidNames = ["prebid"];
  Prebid.primaryName = PrebidNames[0];
  Prebid.injections = [hit, noopFunc, noopStr, noopArray];

  // src/redirects/scorecardresearch-beacon.js
  function ScoreCardResearchBeacon(source) {
    window.COMSCORE = {
      purge() {
        window._comscore = [];
      },
      beacon() {
      }
    };
    hit(source);
  }
  var ScoreCardResearchBeaconNames = [
    "scorecardresearch-beacon",
    "ubo-scorecardresearch_beacon.js",
    "scorecardresearch_beacon.js"
  ];
  ScoreCardResearchBeacon.primaryName = ScoreCardResearchBeaconNames[0];
  ScoreCardResearchBeacon.injections = [
    hit
  ];
  return __toCommonJS(scriptlets_names_list_exports);
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
    console.warn("No callable function found for scriptlet module: scriptlets-names-list");
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