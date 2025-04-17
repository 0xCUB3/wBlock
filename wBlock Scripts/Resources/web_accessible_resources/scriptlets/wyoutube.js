//
//  wYouTube.js
//  
//
//  Created by Alexander Skula on 4/17/25.
//

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

  // Define hit helper (standard in AdGuard scriptlets)
  var hit = (source) => {
    const ADGUARD_PREFIX = "[wBlock Scripts wYouTube]"; // Specific prefix
    if (!source?.verbose) { // Check if source and verbose exist
      return;
    }
    try {
      const trace = console.trace?.bind(console); // Optional chaining for console.trace
      let label = `${ADGUARD_PREFIX} HIT `;
      if (source.engine === "corelibs") {
         label += source.ruleText || '[No Rule Text]';
      } else {
        if (source.domainName) {
          label += `${source.domainName} `;
        }
        if (source.args && source.args.length > 0) {
          label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
        } else {
          label += `#%#//scriptlet('${source.name}')`;
        }
      }
      if (trace) {
        trace(label);
      } else {
        console.log(label); // Fallback if trace is not available
      }
    } catch (e) {
       console.warn(`${ADGUARD_PREFIX} Error in hit function:`, e);
    }
    // AdGuard's debug function integration (if needed)
    if (typeof window.__debug === "function") {
      try {
        window.__debug(source);
      } catch (debugErr) {
        console.warn(`${ADGUARD_PREFIX} Error calling window.__debug:`, debugErr);
      }
    }
  };

  var wYouTube_exports = {};
  __export(wYouTube_exports, {
    wYouTube: () => wYouTube,
    wYouTubeNames: () => wYouTubeNames
  });

  // Zeblock's static ad selectors
  const staticAds = [".ytd-companion-slot-renderer", ".ytd-action-companion-ad-renderer", // in-feed video ads
                   ".ytd-watch-next-secondary-results-renderer.sparkles-light-cta", ".ytd-unlimited-offer-module-renderer", // similar components
                   ".ytp-ad-overlay-image", ".ytp-ad-text-overlay", // deprecated overlay ads (04-06-2023)
                   "div#root.style-scope.ytd-display-ad-renderer.yt-simple-endpoint", "div#sparkles-container.style-scope.ytd-promoted-sparkles-web-renderer",
                   ".ytd-display-ad-renderer", ".ytd-statement-banner-renderer", ".ytd-in-feed-ad-layout-renderer", // homepage ads
                   "div#player-ads.style-scope.ytd-watch-flexy, div#panels.style-scope.ytd-watch-flexy", // sponsors
                   ".ytd-banner-promo-renderer", ".ytd-video-masthead-ad-v3-renderer", ".ytd-primetime-promo-renderer" // subscribe for premium & youtube tv ads
                  ];

  // Zeblock's main ad-blocking logic function
  const taimuRipu = async (source) => {
     // Helper moved inside to ensure it's defined in scope
     const hideElementsBySelector = (selector) => {
         try {
             document.querySelectorAll(selector).forEach(
                 (el) => { if (el && el.style) el.style.display = "none"; } // Add checks for el and el.style
             );
         } catch (e) {
             console.warn(`[wBlock Scripts wYouTube] Error hiding selector "${selector}":`, e);
         }
     };

     const checkAndBlock = () => {
         return new Promise((resolve) => {
             const videoContainer = document.getElementById("movie_player");

             const setTimeoutHandler = () => {
                 try {
                     const isAd = videoContainer?.classList.contains("ad-interrupting") || videoContainer?.classList.contains("ad-showing");
                     const skipLock = document.querySelector(".ytp-ad-preview-text")?.innerText;
                     const surveyLock = document.querySelector(".ytp-ad-survey")?.length > 0;

                     if (isAd && skipLock) {
                         const videoPlayer = document.getElementsByClassName("video-stream")[0];
                         // Check if videoPlayer exists and has a valid duration before manipulating
                         if (videoPlayer && typeof videoPlayer.duration === 'number' && isFinite(videoPlayer.duration) && videoPlayer.duration > 0) {
                             videoPlayer.muted = true;
                             videoPlayer.currentTime = videoPlayer.duration - 0.1;
                             if (videoPlayer.paused) {
                                 videoPlayer.play().catch(e => console.warn('[wBlock Scripts wYouTube] Playback prevented:', e));
                             }
                             document.querySelector(".ytp-ad-skip-button")?.click();
                             document.querySelector(".ytp-ad-skip-button-modern")?.click();
                             // console.info('[wBlock Scripts wYouTube] Skipped video ad');
                             hit(source); // Log a hit when an action is taken
                         } else {
                            // console.warn('[wBlock Scripts wYouTube] Video player or duration not ready for ad skip.');
                         }
                     } else if (isAd && surveyLock) {
                         document.querySelector(".ytp-ad-skip-button")?.click();
                         document.querySelector(".ytp-ad-skip-button-modern")?.click();
                         // console.info('[wBlock Scripts wYouTube] Skipped survey');
                         hit(source); // Log a hit when an action is taken
                     }

                     // Static ad hiding
                     staticAds.forEach((ad) => {
                         hideElementsBySelector(ad);
                     });

                 } catch (e) {
                     console.error('[wBlock Scripts wYouTube] Error in setTimeoutHandler:', e);
                 } finally {
                     resolve(); // Resolve the promise after the check
                 }
             };

             // Use requestAnimationFrame for smoother performance and better timing with rendering cycles
             requestAnimationFrame(setTimeoutHandler);
         });
     };

     // Keep checking periodically
     while (true) {
         await checkAndBlock();
         // Wait a short interval before checking again to avoid busy-waiting
         await new Promise(resolve => setTimeout(resolve, 150)); // e.g., check every 150ms
     }
  };

  // The main function executed when the scriptlet is called by the filter rule
  function wYouTube(source) {
     // Log execution start
     console.info('[wBlock Scripts wYouTube] Scriptlet executing.');
     if (source?.verbose) {
         hit(source); // Log detailed hit if verbose
     }

     // Start the ad-blocking loop. No need to await here as it runs indefinitely.
     taimuRipu(source).catch(e => {
        console.error('[wBlock Scripts wYouTube] Uncaught error in taimuRipu loop:', e);
     });
  }

  // Metadata for the scriptlet
  var wYouTubeNames = ["wyoutube"]; // The name used in filter rules and registry.json
  wYouTube.primaryName = wYouTubeNames[0];
  wYouTube.injections = [hit]; // Declare 'hit' as a dependency

  return __toCommonJS(wYouTube_exports);
})();

// Standard registration IIFE - registers the scriptlet function with the ad blocker
;(function(){
  // Ensure the scriptlet environment exists
  window.adguardScriptlets = window.adguardScriptlets || {};
  var fn = null;
  var primaryName = null;

  // Find the exported function and its primary name
  if (main && typeof main.wYouTube === 'function' && main.wYouTube.primaryName) {
      fn = main.wYouTube;
      primaryName = main.wYouTube.primaryName;
  } else {
      // Fallback logic if the structure is different
      for (var key in main) {
          if (main.hasOwnProperty(key) && typeof main[key] === 'function' && main[key].primaryName) {
              fn = main[key];
              primaryName = main[key].primaryName;
              break;
          }
      }
  }

  if (!fn) {
    console.warn("[wBlock Scripts] No callable function with primaryName found for scriptlet module: wYouTube");
    return; // Stop if no function to register
  }

  // Collect all aliases defined in the scriptlet module (usually an array named '*Names')
  var aliases = [];
  if (main && Array.isArray(main.wYouTubeNames)) {
       aliases = main.wYouTubeNames;
  } else if (primaryName) {
      aliases.push(primaryName); // Fallback to primaryName if Names array convention isn't used
  }


  // Register the function under all its names/aliases
  aliases.forEach(function(alias) {
    if (typeof alias === 'string' && alias.length > 0) {
        if (window.adguardScriptlets[alias]) {
             console.warn(`[wBlock Scripts] Overwriting existing scriptlet: ${alias} for wYouTube`);
        }
        window.adguardScriptlets[alias] = fn;
    } else {
        console.warn("[wBlock Scripts] Invalid alias detected during registration for wYouTube:", alias);
    }
  });

   // Ensure the primary name is registered if somehow missed (should be covered by aliases loop)
  if (primaryName && !window.adguardScriptlets[primaryName]) {
      console.warn(`[wBlock Scripts] Primary name ${primaryName} was not registered via aliases, registering now.`);
      window.adguardScriptlets[primaryName] = fn;
  }

   // console.info('[wBlock Scripts] Registered scriptlet: wYouTube');

})();
