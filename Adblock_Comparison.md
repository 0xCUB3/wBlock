# Overview
*Jump to the [feature comparison table](#feature-comparison) if you prefer to peruse the technical details first.*

## wBlock

wBlock is what Safari ad blocking arguably ought to be. Setup is efficient: enable all the Safari extensions, follow the onboarding, and you’re running. 

The interface is clean and native, built with SwiftUI. Both the iOS and macOS version employ Content Blocker Extensions, which are Apple's remarkably efficient frameworks for static ad blocking. Since they run in near constant time, memory usage doesn't balloon with large lists as it might with other content blockers. Indeed, on my M2 Pro MacBook Pro, wBlock consumes little more than a few dozen megabytes of memory at any time. 

You can examine detailed statistics for source rules and how they’re converted for Safari, complete with conversion and reload times.

<img width="882" height="802" alt="image" src="https://github.com/user-attachments/assets/bd3ca8aa-ee72-44e6-8b1c-7a5563c25976" />

<img width="812" height="732" alt="image" src="https://github.com/user-attachments/assets/db0d8dcb-9ed3-4f7c-9efb-53d1079514b0" />

You can see exactly what's happening with detailed statistics showing X source rules converted to Y Safari rules, complete with conversion and reload times. If you're into these kind of things, it's great to have the numbers right in front of you.

The main settings screen shows your enabled filter lists with toggle switches. Each list shows rule counts, and you can see categories like Ads, Privacy, and Security clearly organized. wBlock Advanced (macOS only) also has a nice popover that informs you of how many requests are blocked, as well as a few customization options.

<img width="318" height="326" alt="CleanShot 2025-08-20 at 18 18 11" src="https://github.com/user-attachments/assets/3bf5b7ed-a0d6-49e1-b729-a32033fff59c" />

What sets wBlock apart is the advanced features. The element zapper runs on macOS, iOS, iPadOS, and visionOS with scroll tracking and parent/child element navigation: point, click, BAM! Gone. The userscript support lets you run custom JavaScript that normally requires additional extensions like Tampermonkey (most of which are not supported on Safari anyway). By default, you have Return YouTube Dislike and Bypass Paywalls Clean, but you can add almost any script you want!

Other recent additions include iCloud sync for filter selections, custom lists, userscripts, and whitelist across all your devices; configurable auto-updates from every hour to every 7 days with HTTP conditional requests to minimize bandwidth; a filter preprocessor that handles AdGuard's `!#include` directives; and auto-detection of custom filter list titles from `! Title` metadata.

The app is developed just by [me](https://github.com/0xCUB3), though a few people have contributed changes. If you want power-user features in a native interface, wBlock is a breath of fresh air.

Sources: [wBlock GitHub](https://github.com/0xCUB3/wBlock), [wBlock Wiki](https://github.com/0xCUB3/wBlock/wiki)

---

## uBlock Origin Lite

uBlock Origin Lite is the lobotomized version of uBlock Origin, rebuilt from scratch for Manifest V3. Contrary to their similar naming, the two extensions function quite differently, and you can thank Google for the fact that uBlock Origin Lite generally will not be as performant or efficient at blocking ads. It is worth noting that Safari is not restricted to Manifest v3, so uBlock Origin Lite's tradeoffs are not necessary on Apple's browser. For instance, all of uBlock Lite's "filterlists" are actually scripts, which, while bypassing Manifest v3's new restrictions, are much less efficient for static ads. Thankfully, installation is as simple as with wBlock: one click from App Store and you're protected with sensible defaults.

The interface keeps things simple. The main popup has an intuitive blocking level slider where you can adjust from "basic" to "optimal" to "complete" without understanding technical details, though its lack of verbosity leaves something to be desired for more advanced users. This is marginally more approachable than original uBlock Origin's power-user matrix interface.

<img width="1112" height="762" alt="image" src="https://github.com/user-attachments/assets/79f99d54-a6b6-4c54-b9d4-51fa57c34865" />

The popup shows real-time blocking stats when you're on a website. You can see it actively blocking content with clear indicators for different blocked content types, though just like with wBlock, the toolbar item doesn't update immediately. Settings are cleanly organized with categorized filter lists you can toggle based on your needs, though as a webpage rather than an app.

Filter management is straightforward, covering most blocking needs without overwhelming choices. You can enable regional lists and specialized filters with toggles similar to wBlock's. Importantly, you cannot add your own filter lists, a concession to Manifest v3, and list updates depend on app updates, which can be a bottleneck, though the app is blessed with frequent updates. 

Performance is solid, though using only script-based ads lends itself to more RAM usage. The declarative Manifest V3 approach means no background processes, though, so system impact is still minimal. Pages load noticeably faster with ads blocked, and site breakage is rare.

The tradeoff is missing power-user features from the original uBlock Origin: no dynamic filtering, no element picker, no real-time rule editing, and a few more minor features. But for most users, the streamlined experience enough to say that it is worth it. Updates happen automatically, and you rarely need to think about it.

Sources: [Chrome Web Store](https://chromewebstore.google.com/detail/ublock-origin-lite/ddkjiahejlhfcafbddmgiahcphecmpfh), [uBlock Origin Official](https://ublockorigin.com)

---

## Wipr 2

Wipr 2 is tailored for users seeking no-config, dependable ad blocking. Installation from the App Store is frictionless; enable the content blockers in Safari settings and operation is immediate.

The interface is intentionally simple with clean SwiftUI design. The setup screens have friendly copy like "Welcome to Wipr!" with clear explanations.

<img width="908" height="578" alt="CleanShot 2025-08-20 at 18 28 16" src="https://github.com/user-attachments/assets/e28bd3a2-276d-43ac-9870-965fcdd7eb92" />

Wipr dynamically allocates rule lists across multiple extensions (Wipr 1–3 and Extra) to accommodate Safari’s 150,000-rule ceiling. This process is handled automatically, requiring no intervention.

The blocking test results show effectiveness with clean statistics. You can see 135/135 items blocked with simple, clear presentation without overwhelming technical details. Automatic filter updates happen twice weekly in the background with zero user intervention. With that said, like with uBlock Origin Lite, filterlist updates are contingent on the developer's release schedule, and unlike with uBlock Origin Lite, Wipr is developed by a [single developer](https://kaylees.site), much like wBlock. 

Performance is excellent: 50MB RAM usage on an M2 Pro MacBook Pro, minimal battery impact, and genuinely faster page loading. Par for the course for such a simple app. Although it is the only paid option on this list, the universal purchase covers iPhone, iPad, Mac, and Vision Pro.

The limitation is customization. If you want fine-grained control, element zapping, userscripts, or custom filters, Wipr feels very constraining. But if you don't care about tweaking your ad blocking settings and value simplicity, Wipr 2 is well-suited.

Sources: [App Store](https://apps.apple.com/us/app/wipr-2/id1662217862), [All About Cookies Review](https://allaboutcookies.org/wipr-review), [Reddit Discussion](https://www.reddit.com/r/macapps/comments/1gpc5e7/wipr_2_has_officially_released/)

---

## AdGuard Mini (formerly AdGuard for Safari)

AdGuard Mini represents a major rework of AdGuard for Safari, released in December 2025 with significant improvements. The rebranding clarifies AdGuard's product line: "Mini" denotes browser extension-based blockers, while "AdGuard Ad Blocker" refers to system-wide apps. Note that AdGuard Mini is macOS-only; AdGuard for iOS is a separate product.

<img width="1536" height="1184" alt="image" src="https://github.com/user-attachments/assets/6a768683-5abf-4334-88ac-70b0dd49e722" />

The Safari Extensions panel shows seven different extensions working together, each handling different rule categories to work within Safari's per-extension limits while maximizing total filtering capacity—very similar to wBlock's setup. The interface is feature-rich with statistics, logging, custom filter editing, element blocking tools, and configuration aplenty. Multi-language support remains impressive with 20+ language filter lists.

The most significant change is the UI framework migration from Electron to Sciter, which dramatically improves performance. Filter conversion is now up to 5x faster thanks to updated SafariConverterLib (~40s → ~15s for full rule application). The Sciter framework uses 5-7x less RAM than Electron, addressing the memory issues that plagued the old version.

New Pro features (requiring an AdGuard license) include AdGuard Extra for fighting tricky ads and anti-adblock measures, real-time filter updates, and a custom rules constructor for building filtering rules without technical knowledge. Core blocking features remain free.

For users seeking granular control with improved performance, AdGuard Mini is a compelling option—especially now that the major performance issues have been addressed.

Sources: [AdGuard Mini](https://adguard.com/en/adguard-safari/overview.html), [AdGuard Mini Announcement](https://adguard.com/en/blog/adguard-mini-for-mac.html), [GitHub](https://github.com/AdguardTeam/AdGuardForSafari)

---

# Feature Comparison

| Feature                 | wBlock<sup>1</sup>                | uBlock Origin Lite<sup>2</sup> | Wipr 2<sup>3</sup>                 | AdGuard Mini<sup>4</sup>     |
|-------------------------|-----------------------------------|----------------------|-----------------------|-----------------------|
| macOS Support           | ✅      | ✅          | ✅               | ✅               |
| iOS Support             | ✅      | ✅          | ✅               | ❌<sup>20</sup>               |
| RAM Usage (MB)          | 40MB<sup>6</sup>                  | 120MB<sup>6</sup>   | 50MB<sup>6</sup>     | ~100MB<sup>6</sup>     |
| Total Rule Capacity     | 750,000 <sup>7</sup> | N/A                 | 900,000 macOS / 300,000 iOS | 1,050,000 macOS |
| GitHub Stars            | 2,300                              | 2,600                | N/A                   | 1,200                |
| Open Source             | ✅                                 | ✅                    | ❌                    | ✅                    |
| License<sup>18</sup>    | GPL-3.0                           | GPL-3.0              | Proprietary           | GPL-3.0              |
| Primary Language<sup>19</sup>        | Swift                | JavaScript   | Swift          | TypeScript/Swift   |
| Secondary Language      | Swift                             | CSS                  | N/A (Closed)          | HTML/CSS    |
| Extension Architecture<sup>8</sup>   | Content Blocker + App (macOS) / Web (iOS) | Manifest V3 Web Extension | Content Blocker + Web Extension | Content Blocker + Web Extension |
| Manifest Version<sup>9</sup>         | Safari Native                     | V3                   | Safari Native         | Safari Native        |
| Filterlist Storage Database<sup>10</sup> | Protobuf                        | IndexedDB + JSON     | Unknown               | SQLite + JSON        |
| Element Zapper<sup>11</sup>          | ✅                                 | ✅                    | ❌                    | ✅                    |
| Custom Filters          | ✅                                 | ❌                   | ❌                    | ✅ (Mac app only)     |
| Dynamic Filtering<sup>12</sup>       | ✅                                 | ❌ MV3 limited        | ❌                    | ✅                   |
| YouTube Ad Blocking     | ✅                                 | ✅                   | ✅                    | ✅                   |
| Script Injection<sup>13</sup>        | ✅                                 | ✅                   | ❌                    | ✅                   |
| Filter List Updates     | Automatic (1h-7d configurable) | Extension updates only | Semi-automatic (≈2×/week)| Automatic (real-time with Pro)            |
| Userscripts Support<sup>14</sup>     | ✅                                 | ❌                   | ❌                    | ❌ (Mac app only)<sup>15</sup>   |
| User Interface          | SwiftUI – extensive               | JS – Popup/web panel | SwiftUI – minimal     | Sciter – extensive |
| Customization Level     | High                              | Medium               | None                  | High                 |
| Setup Complexity        | Easy                              | Easy                 | Very Easy             | Moderate             |
| Multi-Device Sync       | ✅ iCloud                          | ❌                   | ✅ Universal purchase  | ❌                   |
| [AdBlock Tester](https://adblock-tester.com) Score<sup>16</sup>    | 100/100                             | 100/100               | 96/100                | 94/100               |
| Cost                    | Free                              | Free                 | $4.99 one-time        | Free (Pro available)                 |
| Subscription Model      | ❌                                 | ❌                   | ❌                    | ❌                   |
| Active Development      | ✅                                 | ✅                   | ✅                    | ✅                   |
| Community Size          | Growing (2.3k stars)              | Large (cross-browser)| Small/Independent     | Large (35M users)    |
| Per-Site Disable        | ✅                                 | ✅                   | ✅                    | ✅                   |
| Whitelist Management    | ✅                                 | ✅                   | ✅                    | ✅                   |
| Logging/Debugging       | ✅                                 | ❌                   | ❌                    | ✅                   |
| Foreign Lang. Filter Support<sup>17</sup> | ✅ 10+ (more addable manually; app in English) | ✅ 15+         | ✅ Unknown            | ✅ 20+ Languages     |

---

## Superscript Glossary & Explanations

<sup>1</sup> **wBlock:** Focuses on Safari, open-source, optimized for latest Safari API features.  
<sup>2</sup> **uBlock Origin Lite:** Chromium Manifest V3 extension translated to Safari.
<sup>3</sup> **Wipr 2:** Closed-source, paid, lightweight, Safari-only ad blocker.  
<sup>4</sup> **AdGuard Mini:** Formerly AdGuard for Safari; major Dec 2025 rework with Sciter UI framework, 5x faster filter conversion, and Pro features.

<sup>5</sup> **App Store**: https://apps.apple.com/app/wblock/id6746388723

<sup>6</sup> **RAM Usage Measurement**:
Numbers were measured on a 2023 M2 Pro MacBook Pro 14" with 16GB RAM, 5 tabs open, only one ad blocker active. Actual memory usage can **vary widely** based on hardware, browser version, tab contents, number of active extensions, and enabled filter lists. Lower-spec Macs and iOS devices will observe different numbers. AdGuard Mini's estimate reflects the migration from Electron to Sciter (which uses 5-7x less RAM).

<sup>7</sup> **Rule Capacity**:  
Safari limits rule sets to about 150,000 per content blocker. Blockers work around this by using multiple bundled extensions (slots)—the numbers listed reflect the combined total when all are enabled.

<sup>8</sup> **Extension Architecture**:  
How the ad blocker is built and operates in browsers.  
- Content Blocker Extension: Apple's highly sandboxed, fast native API; strict limits on scripting and dynamic features.  
- Manifest V3 Web Extension: Chrome extensions using Manifest V3 format, restricting many dynamic filtering and scripting features for privacy reasons; not natively supported by Safari.  
- Web Extension: Cross-browser format for Chrome, Firefox, Edge; not always fully compatible with Safari.  

<sup>9</sup> **Manifest Version**:  
The extension standard used. Safari uses its own native extension system (Safari App Extensions), while Chrome/Chromium uses Manifest V3, which is more restrictive on blocking and scripting for privacy/security.

<sup>10</sup> **Filterlist Storage Database**:  
Where and how filtering rules/lists are stored:  
- Protobuf: Efficient, binary (fast load/save, reduced disk space), used by wBlock.  
- IndexedDB + JSON: JavaScript-based, built into web browsers (used by uBlock Origin Lite, cross-browser).  
- SQLite + JSON: Lightweight database (efficient for large sets), preferred by AdGuard.  
- Unknown: Wipr is closed source.

<sup>11</sup> **Element Zapper**:
Lets users click and instantly hide page elements (ads, overlays, popups) in real time, no filter editing required. wBlock's element zapper runs on macOS, iOS, iPadOS, and visionOS with scroll tracking and parent/child element navigation. Absent in Wipr, which is more designed to be simple and don't-touch.

<sup>12</sup> **Dynamic Filtering**:
Advanced feature letting users interactively allow/block domains/scripts/network requests per-site (similar to uMatrix and original uBlock Origin dynamic filtering). Rare with Safari content blockers, available only via [clever workarounds](#How-wBlock-Achieves-Dynamic-Filtering-in-Safari) in wBlock/AdGuard Mini.

<sup>13</sup> **Script Injection**:
Lets extension run built-in or custom JavaScript on web pages (for ad removal, circumvention, UI fixes, etc.). Only available in web/app extensions, so only wBlock (and AdGuard Mini / AdGuard for Mac) provide true script injection. Most Chrome extensions do, but only within Manifest V3's security limits as of 2025.

<sup>14</sup> **Userscripts Support**:
Allows running or installing custom scripts (like Greasemonkey/Tampermonkey)—for automation, customization, or advanced blocking. Only wBlock (and AdGuard for Mac) support this natively. Safari App Store policies restrict this in other extensions.

<sup>15</sup> AdGuard's userscript support is available only in its paid standalone AdGuard for Mac application, not in AdGuard Mini (the Safari browser extension).

<sup>16</sup> **AdBlock Tester Score**:  
AdBlock Tester scores (adblocktester.com, etc.) depend mostly on which filter lists you enable—extension features matter less. Even simple ad blockers can score 100/100 if using up-to-date and comprehensive lists; heavy, feature-rich blockers may score lower if filters are incomplete or outdated.

<sup>17</sup> **Foreign Language Filter Support**:
Reflects whether ad blockers have official filter lists for multiple languages/regions. AdGuard Mini supports 20+ languages with official filters; uBlock Origin Lite permits more than 15; wBlock can load manual lists but the app itself is limited to English for now.

<sup>18</sup> **License**:  
Describes the legal terms governing code and usage:  
- GPL-3.0: Open-source license allowing code modification and redistribution as long as further releases are also open source.  
- Proprietary: Closed source, so users cannot view or modify the code at all. 

<sup>19</sup> **Primary Language**:
Refers to the main programming language(s) used.
- Swift: Indicates a native Apple/macOS/iOS app/extension, making it fully native and optimized for Apple devices.
- JavaScript/TypeScript: Indicates a web-based or cross-browser extension (more universal, usually less efficient).
- Objective-C: The predecessor to Swift. Also technically native, but archaic.

<sup>20</sup> **AdGuard Mini iOS**: AdGuard Mini is macOS-only. For iOS ad blocking, AdGuard offers a separate [AdGuard for iOS](https://adguard.com/en/adguard-ios/overview.html) app.

---

# How wBlock Achieves Dynamic Filtering in Safari

Safari’s native content blocker API is designed for static filtering, but I've implemented some tricks into wBlock to approximate dynamic filtering:

## 1. Per-Site Disable with `ignore-previous-rules`

When you toggle blocking for a specific site, wBlock appends a rule like:

```json
{
  "action": {"type": "ignore-previous-rules"},
  "trigger": {
    "url-filter": ".",
    "if-domain": ["site.com", ".site.com"]
  }
}
```

This tells Safari to *ignore all previous blocking rules* for that domain, effectively unblocking it in real time.

## 2. Fast Content Blocker Rebuilds

wBlock uses modular storage and fast update logic to "fake" fast content blocker reloads. If possible, only the affected category or site rules are rebuilt and reloaded, eliminating the need for a full extension reload.

## 3. Userscript & Script Injection

For dynamic element/blocking behavior (e.g., YouTube ad blocking, element zapper), wBlock injects userscripts. These scripts manipulate the DOM on demand, going beyond what static rules can do.

## 4. Category-Based Rule Management

wBlock tracks unapplied changes and only processes updates to the necessary filter sets, further speeding up dynamic-like behaviors.

## Limitations

- **True request-level dynamic filtering** (deciding on each request in real time) is *not possible* in Safari, as all changes require a rebuild of the static rules.
- wBlock’s approach makes user adjustments feel nearly as fast and flexible as other browsers, but is ultimately bounded by Safari’s extension API constraints.
