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

  // Scriptlets/src/scriptlets/trusted-dispatch-event.ts
  var trusted_dispatch_event_exports = {};
  __export(trusted_dispatch_event_exports, {
    trustedDispatchEvent: () => trustedDispatchEvent,
    trustedDispatchEventNames: () => trustedDispatchEventNames
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

  // Scriptlets/src/scriptlets/trusted-dispatch-event.ts
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
  return __toCommonJS(trusted_dispatch_event_exports);
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
    console.warn("No callable function found for scriptlet module: trusted-dispatch-event");
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
