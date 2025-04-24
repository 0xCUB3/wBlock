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

  // Scriptlets/src/scriptlets/prevent-element-src-loading.js
  var prevent_element_src_loading_exports = {};
  __export(prevent_element_src_loading_exports, {
    preventElementSrcLoading: () => preventElementSrcLoading,
    preventElementSrcLoadingNames: () => preventElementSrcLoadingNames
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

  // Scriptlets/src/helpers/object-utils.ts
  var safeGetDescriptor = (obj, prop) => {
    const descriptor = Object.getOwnPropertyDescriptor(obj, prop);
    if (descriptor && descriptor.configurable) {
      return descriptor;
    }
    return null;
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

  // Scriptlets/src/helpers/trusted-types-utils.ts
  var getTrustedTypesApi = (source) => {
    const policyApi = source?.api?.policy;
    if (policyApi) {
      return policyApi;
    }
    const POLICY_NAME = "AGPolicy";
    const trustedTypesWindow = window;
    const trustedTypes = trustedTypesWindow.trustedTypes;
    const isSupported = !!trustedTypes;
    const TrustedTypeEnum = {
      HTML: "TrustedHTML",
      Script: "TrustedScript",
      ScriptURL: "TrustedScriptURL"
    };
    if (!isSupported) {
      return {
        name: POLICY_NAME,
        isSupported,
        TrustedType: TrustedTypeEnum,
        createHTML: (input) => input,
        createScript: (input) => input,
        createScriptURL: (input) => input,
        create: (type, input) => input,
        getAttributeType: () => null,
        convertAttributeToTrusted: (tagName, attribute, value) => value,
        getPropertyType: () => null,
        convertPropertyToTrusted: (tagName, property, value) => value,
        isHTML: () => false,
        isScript: () => false,
        isScriptURL: () => false
      };
    }
    const policy = trustedTypes.createPolicy(POLICY_NAME, {
      createHTML: (input) => input,
      createScript: (input) => input,
      createScriptURL: (input) => input
    });
    const createHTML = (input) => policy.createHTML(input);
    const createScript = (input) => policy.createScript(input);
    const createScriptURL = (input) => policy.createScriptURL(input);
    const create = (type, input) => {
      switch (type) {
        case TrustedTypeEnum.HTML:
          return createHTML(input);
        case TrustedTypeEnum.Script:
          return createScript(input);
        case TrustedTypeEnum.ScriptURL:
          return createScriptURL(input);
        default:
          return input;
      }
    };
    const getAttributeType = trustedTypes.getAttributeType.bind(trustedTypes);
    const convertAttributeToTrusted = (tagName, attribute, value, elementNS, attrNS) => {
      const type = getAttributeType(tagName, attribute, elementNS, attrNS);
      return type ? create(type, value) : value;
    };
    const getPropertyType = trustedTypes.getPropertyType.bind(trustedTypes);
    const convertPropertyToTrusted = (tagName, property, value, elementNS) => {
      const type = getPropertyType(tagName, property, elementNS);
      return type ? create(type, value) : value;
    };
    const isHTML = trustedTypes.isHTML.bind(trustedTypes);
    const isScript = trustedTypes.isScript.bind(trustedTypes);
    const isScriptURL = trustedTypes.isScriptURL.bind(trustedTypes);
    return {
      name: POLICY_NAME,
      isSupported,
      TrustedType: TrustedTypeEnum,
      createHTML,
      createScript,
      createScriptURL,
      create,
      getAttributeType,
      convertAttributeToTrusted,
      getPropertyType,
      convertPropertyToTrusted,
      isHTML,
      isScript,
      isScriptURL
    };
  };

  // Scriptlets/src/scriptlets/prevent-element-src-loading.js
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
    const policy = getTrustedTypesApi(source);
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
    noopFunc,
    getTrustedTypesApi
  ];
  return __toCommonJS(prevent_element_src_loading_exports);
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
    console.warn("No callable function found for scriptlet module: prevent-element-src-loading");
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
