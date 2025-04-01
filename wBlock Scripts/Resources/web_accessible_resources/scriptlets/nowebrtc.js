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

  // Scriptlets/src/scriptlets/nowebrtc.js
  var nowebrtc_exports = {};
  __export(nowebrtc_exports, {
    nowebrtc: () => nowebrtc,
    nowebrtcNames: () => nowebrtcNames
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

  // Scriptlets/src/helpers/noop-utils.ts
  var noopFunc = () => {
  };

  // Scriptlets/src/helpers/string-utils.ts
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

  // Scriptlets/src/scriptlets/nowebrtc.js
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
  return __toCommonJS(nowebrtc_exports);
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
    console.warn("No callable function found for scriptlet module: nowebrtc");
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
