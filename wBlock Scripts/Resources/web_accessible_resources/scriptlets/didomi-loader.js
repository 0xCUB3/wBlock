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

  // Scriptlets/src/scriptlets/didomi-loader.ts
  var didomi_loader_exports = {};
  __export(didomi_loader_exports, {
    DidomiLoader: () => DidomiLoader,
    DidomiLoaderNames: () => DidomiLoaderNames
  });

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
  var trueFunc = () => true;
  var falseFunc = () => false;
  var noopArray = () => [];

  // Scriptlets/src/redirects/didomi-loader.js
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
  return __toCommonJS(didomi_loader_exports);
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
    console.warn("No callable function found for scriptlet module: didomi-loader");
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
