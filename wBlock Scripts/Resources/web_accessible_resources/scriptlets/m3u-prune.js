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

  // Scriptlets/src/scriptlets/m3u-prune.js
  var m3u_prune_exports = {};
  __export(m3u_prune_exports, {
    m3uPrune: () => m3uPrune,
    m3uPruneNames: () => m3uPruneNames
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

  // Scriptlets/src/scriptlets/m3u-prune.js
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
    const isPruningNeeded = (text, regexp) => isM3U(text) && regexp.test(text);
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
          shouldPruneResponse = isPruningNeeded(response, removeM3ULineRegexp);
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
        if (isPruningNeeded(responseText, removeM3ULineRegexp)) {
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
  return __toCommonJS(m3u_prune_exports);
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
    console.warn("No callable function found for scriptlet module: m3u-prune");
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
