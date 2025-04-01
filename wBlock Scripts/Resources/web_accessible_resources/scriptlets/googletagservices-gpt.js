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

  // Scriptlets/src/scriptlets/googletagservices-gpt.ts
  var googletagservices_gpt_exports = {};
  __export(googletagservices_gpt_exports, {
    GoogleTagServicesGpt: () => GoogleTagServicesGpt,
    GoogleTagServicesGptNames: () => GoogleTagServicesGptNames
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
  var noopNull = () => null;
  var trueFunc = () => true;
  function noopThis() {
    return this;
  }
  var noopStr = () => "";
  var noopArray = () => [];

  // Scriptlets/src/redirects/googletagservices-gpt.js
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
  return __toCommonJS(googletagservices_gpt_exports);
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
    console.warn("No callable function found for scriptlet module: googletagservices-gpt");
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
