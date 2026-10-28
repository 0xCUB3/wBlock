(function (browser) {
  'use strict';

  /**
   * @file Contains the implementation of the content script.
   *
   * protectStyleElementContent is adapted from AdGuard SafariConverterLib's
   * extension (GPL-3.0).
   */
  /**
   * Protects specified style element from changes to the current document
   * Add a mutation observer, which is adds our rules again if it was removed
   *
   * @param {HTMLElement} protectStyleEl protected style element.
   */
  const protectStyleElementContent = protectStyleEl => {
    const {
      MutationObserver
    } = window;
    if (!MutationObserver) {
      return;
    }
    // Observer, which observe protectStyleEl inner changes, without deleting
    // styleEl.
    const innerObserver = new MutationObserver(mutations => {
      for (let i = 0; i < mutations.length; i += 1) {
        const m = mutations[i];
        if (protectStyleEl.hasAttribute('mod') && protectStyleEl.getAttribute('mod') === 'inner') {
          protectStyleEl.removeAttribute('mod');
          break;
        }
        protectStyleEl.setAttribute('mod', 'inner');
        let isProtectStyleElModified = false;
        // There are two mutually exclusive situations:
        //
        // 1. There were changes to the inner text of protectStyleEl.
        // 2. The whole "text" element of protectStyleEl was removed.
        if (m.removedNodes.length > 0) {
          for (let j = 0; j < m.removedNodes.length; j += 1) {
            isProtectStyleElModified = true;
            protectStyleEl.appendChild(m.removedNodes[j]);
          }
        } else if (m.oldValue) {
          isProtectStyleElModified = true;
          // eslint-disable-next-line no-param-reassign
          protectStyleEl.textContent = m.oldValue;
        }
        if (!isProtectStyleElModified) {
          protectStyleEl.removeAttribute('mod');
        }
      }
    });
    innerObserver.observe(protectStyleEl, {
      childList: true,
      characterData: true,
      subtree: true,
      characterDataOldValue: true
    });
  };
  /**
   * @file Defines message interface.
   */
  /**
   * Represents a type of message.
   */
  var MessageType;
  (function (MessageType) {
    MessageType["InitContentScript"] = "InitContentScript";
  })(MessageType || (MessageType = {}));

  /**
   * @file Content script for the WebExtension.
   *
   * This script runs in the context of a frame, and it's responsible for:
   * - Notifying the background script that the frame is available.
   * - Exposing content script to other scripts in the ISOLATED world, so that
   *   they were used by scripts injected by `browser.scripting.executeScript`.
   */
  if (!browser || !browser.runtime || !browser.runtime.sendMessage) return;
  // Cloudflare's "Verify you are human" managed-challenge interstitial and its
  // Turnstile widget frame are sensitive to same-page URL rewrites. The Scripts
  // extension runs at document_start in every frame, including the Turnstile
  // iframe served from challenges.cloudflare.com. Rewriting its URL makes
  // Cloudflare treat the verification as tampered and reload the challenge
  // page in a loop (issue #476). Detect these contexts early and bail out so
  // the extension is effectively absent on challenge pages.
  let cloudflareChallengeContext = false;
  const cloudflareChallengeTitleRegex = /just a moment|verifying you are human|attention required|enable cookies/i;
  const cloudflareChallengeTitle = title => cloudflareChallengeTitleRegex.test(title || "");
  const markCloudflareChallenge = () => {
    if (cloudflareChallengeContext) return;
    cloudflareChallengeContext = true;
    console.info("[wBlock] Cloudflare challenge context detected — skipping content script.");
  };
  const isCloudflareChallengeFrameNow = () => {
    try {
      const host = window.location && typeof window.location.hostname === "string" ? window.location.hostname : "";
      const path = window.location && typeof window.location.pathname === "string" ? window.location.pathname : "";
      if (host === "challenges.cloudflare.com") return true;
      if (path.startsWith("/cdn-cgi/challenge-platform")) return true;
      if (path.startsWith("/cdn-cgi/challenge")) return true;
    } catch (_) {}
    return false;
  };
  // The main interstitial is served from the visited host, so its URL does not
  // identify it. Its orchestration <script src="/cdn-cgi/challenge-platform/...">
  // and challenge markers appear during parsing, so watch for them before
  // applying configuration or rewriting the URL.
  const startCloudflareChallengeWatch = () => {
    if (cloudflareChallengeContext) return;
    if (cloudflareChallengeTitle(document.title)) {
      markCloudflareChallenge();
      return;
    }
    const root = typeof document !== "undefined" ? document.documentElement : null;
    if (!root || typeof MutationObserver === "undefined") {
      return;
    }
    // The interstitial is a real http(s) document; blank and srcdoc frames
    // never carry it.
    if (!/^https?:$/i.test((window.location && window.location.protocol) || "")) return;
    const challengeSelector = 'script[src^="/cdn-cgi/challenge-platform"],script[src*="challenges.cloudflare.com"],#challenge-form,#challenge-stage,#challenge-runner';
    // Inspect only what was added. Re-querying the whole document on every
    // mutation made DOM-heavy pages pay five full searches per change.
    const isChallengeNode = node => node.nodeType === 1
      && (node.matches(challengeSelector) || !!node.querySelector(challengeSelector)
        || (node.tagName === "TITLE" && cloudflareChallengeTitle(document.title)));
    try {
      const observer = new MutationObserver(mutations => {
        if (cloudflareChallengeContext) {
          observer.disconnect();
          return;
        }
        for (const mutation of mutations) {
          const titleText = mutation.target.nodeName === "TITLE";
          for (const node of mutation.addedNodes) {
            if ((titleText && cloudflareChallengeTitle(document.title)) || isChallengeNode(node)) {
              stop();
              markCloudflareChallenge();
              return;
            }
          }
        }
      });
      const stop = () => {
        observer.disconnect();
        document.removeEventListener("DOMContentLoaded", finish);
      };
      // The markers arrive while the document parses, so one last full check
      // at DOMContentLoaded ends the watch, even after the observer timed out.
      const finish = () => {
        stop();
        if (!cloudflareChallengeContext
          && (document.querySelector(challengeSelector) || cloudflareChallengeTitle(document.title))) {
          markCloudflareChallenge();
        }
      };
      observer.observe(root, { childList: true, subtree: true });
      document.addEventListener("DOMContentLoaded", finish);
      setTimeout(() => observer.disconnect(), 5000);
    } catch (_) {}
  };
  if (isCloudflareChallengeFrameNow()) {
    markCloudflareChallenge();
  } else {
    startCloudflareChallengeWatch();
  }
  /**
   * Applies a payload in this frame when the background page could not, which
   * is the case for blank frames. Filters come from procedural.js, which is
   * loaded as a content script ahead of this file.
   *
   * @param configuration Payload from the native handler.
   */
  const applyConfiguration = configuration => {
    try {
      const selectors = configuration.css || [];
      if (selectors.length > 0) {
        const style = document.createElement('style');
        style.setAttribute('type', 'text/css');
        style.textContent = selectors.map(selector => `${selector} { display: none !important; }`).join('\n');
        (document.head || document.documentElement).appendChild(style);
        protectStyleElementContent(style);
      }
      if (configuration.procedural && configuration.procedural.length > 0) {
        window.wbeProcedural.apply(configuration.procedural);
      }
      // Scriptlets need the background's page-world injection (see
      // runScriptlets), which blank frames cannot get.
    } catch (error) {
      console.error(`[wBlock] Failed to apply configuration in content script: ${(error && error.stack) || error}`);
    }
  };
  /**
   * Main entry point function for the content script.
   *
   * This function:
   * 1. Notifies the background page of the page that is loading. Background page
   *    will handle this event and insert necessary CSS and JS to this frame.
   * 2. When the background page responds, cancels any delayed events and flushes
   *    captured events.
   */
  let initializationStatePromise;
  const INIT_RETRY_DELAYS_MS = [250, 1000, 3000];
  const stateFromInitResponse = response => {
    if (response && response.state === "error") {
      return Promise.resolve(true);
    }
    // Every InitContentScript response carries native state; treat a
    // response without it as unknown and leave the page alone.
    return Promise.resolve(!(response && typeof response.disabled === "boolean"
      && typeof response.paused === "boolean")
      || response.disabled || response.paused);
  };
  const main = async () => {
    if (cloudflareChallengeContext) return;
    const message = {
      type: MessageType.InitContentScript
    };
    // A failed lookup (native timeout, background waking up) is not a
    // disabled site; retry it so the document still gets its rules.
    const requestInitialization = async () => {
      for (let attempt = 0; ; attempt += 1) {
        const response = await browser.runtime.sendMessage(message).catch(error => ({
          type: MessageType.InitContentScript,
          state: "error",
          error: String(error && error.message ? error.message : error)
        }));
        if (!(response && response.state === "error")
          || attempt >= INIT_RETRY_DELAYS_MS.length
          || cloudflareChallengeContext) {
          return response;
        }
        await new Promise(resolve => setTimeout(resolve, INIT_RETRY_DELAYS_MS[attempt]));
      }
    };
    const configPromise = requestInitialization();
    initializationStatePromise = configPromise.then(stateFromInitResponse);
    const response = await configPromise;
    if (await initializationStatePromise) return;
    // Its markup can arrive while the native response is pending.
    if (cloudflareChallengeContext) return;
    // If the background page returned payload with configuration, it means
    // that it cannot apply it on its own and commands the content script
    // to do that.
    if (response !== null && response !== void 0 && response.payload) {
      applyConfiguration(response.payload);
    }
  };
  // Execute the main function and catch any runtime errors.
  main().catch(error => {
    console.error(`[wBlock] Error in content script: ${(error && error.stack) || error}`);
  });
  // Best-effort top-frame URL cleanup fallback for Safari builds where
  // declarativeNetRequest redirect/queryTransform does not run for main_frame
  // requests. The background page uses the same generated $removeparam rules as
  // the DNR installer, then this content script strips tracking parameters in-place
  // via history.replaceState as early as Safari allows content scripts to run
  // without triggering a document reload or navigation loop.
  //
  // Skipped on whitelisted sites: URL modification is detectable by anti-adblock
  // walls even when content blockers are off (issue #445).
  (async () => {
    try {
      // Never rewrite Cloudflare challenge pages: stripping the challenge token
      // or redirecting mid-verification makes the interstitial reload in a loop
      // (issue #476).
      if (cloudflareChallengeContext) return;
      if (await (initializationStatePromise || Promise.resolve(false))) return;
      if (window.top !== window) return;
      if (!/^https?:/i.test(window.location.href)) return;
      if (typeof browser === "undefined" || !browser.runtime || !browser.runtime.sendMessage) return;
      const response = await browser.runtime.sendMessage({
        action: "wblock:getCleanURL",
        url: window.location.href
      });
      let cleanUrl = response && typeof response.cleanUrl === "string" ? response.cleanUrl : "";
      if (!cleanUrl || cleanUrl === window.location.href) {
        const fallbackUrl = new URL(window.location.href);
        let changed = false;
        for (const key of Array.from(fallbackUrl.searchParams.keys())) {
          if (/^(utm_|fbclid$|gclid$|dclid$|gbraid$|wbraid$|msclkid$|mc_cid$|mc_eid$|igshid$|yclid$|_hsenc$|_hsmi$|mkt_tok$|vero_id$|oly_anon_id$|oly_enc_id$)/i.test(key)) {
            fallbackUrl.searchParams.delete(key);
            changed = true;
          }
        }
        if (changed) {
          cleanUrl = fallbackUrl.href;
        }
      }
      if (cleanUrl && cleanUrl !== window.location.href) {
        if (cloudflareChallengeContext) return;
        console.info("[wBlock] Removing tracking parameters:", window.location.href, "→", cleanUrl);
        if (typeof history !== "undefined" && typeof history.replaceState === "function") {
          history.replaceState(history.state, "", cleanUrl);
        }
      }
    } catch (error) {
      try {
        const fallbackUrl = new URL(window.location.href);
        let changed = false;
        for (const key of Array.from(fallbackUrl.searchParams.keys())) {
          if (/^(utm_|fbclid$|gclid$|dclid$|gbraid$|wbraid$|msclkid$|mc_cid$|mc_eid$|igshid$|yclid$|_hsenc$|_hsmi$|mkt_tok$|vero_id$|oly_anon_id$|oly_enc_id$)/i.test(key)) {
            fallbackUrl.searchParams.delete(key);
            changed = true;
          }
        }
        if (changed && fallbackUrl.href !== window.location.href) {
          if (cloudflareChallengeContext) return;
          console.info("[wBlock] Removing common tracking parameters:", window.location.href, "→", fallbackUrl.href);
          if (typeof history !== "undefined" && typeof history.replaceState === "function") {
            history.replaceState(history.state, "", fallbackUrl.href);
          }
        }
      } catch (_fallbackError) {
        console.warn("[wBlock] URL cleanup fallback failed:", error);
      }
    }
  })();
})(typeof browser === "undefined" ? undefined : browser);
