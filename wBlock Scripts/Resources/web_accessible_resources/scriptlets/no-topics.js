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

  // Scriptlets/src/scriptlets/no-topics.js
  var no_topics_exports = {};
  __export(no_topics_exports, {
    noTopics: () => noTopics,
    noTopicsNames: () => noTopicsNames
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

  // Scriptlets/src/scriptlets/no-topics.js
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
  return __toCommonJS(no_topics_exports);
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
    console.warn("No callable function found for scriptlet module: no-topics");
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
