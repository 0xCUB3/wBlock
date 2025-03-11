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

  // src/scriptlets/remove-node-text.js
  var remove_node_text_exports = {};
  __export(remove_node_text_exports, {
    removeNodeText: () => removeNodeText,
    removeNodeTextNames: () => removeNodeTextNames
  });

  // src/helpers/array-utils.ts
  var nodeListToArray = (nodeList) => {
    const nodes = [];
    for (let i = 0; i < nodeList.length; i += 1) {
      nodes.push(nodeList[i]);
    }
    return nodes;
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

  // src/helpers/string-utils.ts
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

  // src/helpers/observer.ts
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
  return __toCommonJS(remove_node_text_exports);
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
    console.warn("No callable function found for scriptlet module: remove-node-text");
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