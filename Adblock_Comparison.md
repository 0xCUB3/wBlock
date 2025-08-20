# Overview
-# For the detailed feature comparison, see [here](hyperlink to feature comparison). 

## wBlock

wBlock feels like what Safari ad blocking should have been from the start. When you install it from TestFlight, setup is straightforward: enable the Safari extensions and you're running[11].

The interface is clean and native, built with SwiftUI. What's immediately impressive is the transparency - you can see exactly what's happening with detailed statistics showing 143,573 source rules converted to 117,369 Safari rules, complete with conversion and reload times[22]. If you're technically minded, this level of detail is great.

[22][40]

The main settings screen shows your enabled filter lists with responsive toggle switches. Each list shows rule counts, and you can see categories like Ads, Privacy, and Security clearly organized[40]. The blocking test interface shows a large percentage indicator with detailed breakdowns of what's being blocked[23].

What sets wBlock apart is the advanced features. The element zapper works as expected - point and click to remove annoying page elements. The userscript support is impressive for Safari, letting you run custom JavaScript that normally requires extensions like Tampermonkey. Performance is solid - 40MB RAM usage is lightweight, and Protobuf storage keeps everything fast[13].

The downside? It's TestFlight only, so you can't grab it from the App Store. Some features assume technical knowledge. But if you want power-user features in a native interface, wBlock delivers.

Sources: [wBlock GitHub](https://github.com/0xCUB3/wBlock)[13], [wBlock Wiki](https://github.com/0xCUB3/wBlock/wiki)[11]

---

## uBlock Origin Lite

uBlock Origin Lite is the Chrome version of uBlock Origin, redesigned for Manifest V3. Installation is simple - one click from Chrome Web Store and you're protected with sensible defaults[48].

The interface keeps things simple. The main popup has an intuitive blocking level slider where you can adjust from "basic" to "optimal" to "complete" without understanding technical details[33]. This is much more approachable than original uBlock Origin's power-user matrix interface.

[41]

The popup shows real-time blocking stats when you're on a website. You can see it actively blocking content with clear indicators for different blocked content types[41]. Settings are cleanly organized with categorized filter lists you can toggle based on your needs.

Filter management is straightforward - EasyList, EasyPrivacy, and Peter Lowe's blocklist come enabled by default, covering most blocking needs without overwhelming choices[48]. You can add regional lists and specialized filters with simple toggles.

Performance is solid with 120MB RAM usage, reasonable for a cross-browser extension. The declarative Manifest V3 approach means no background processes, so minimal system impact. Pages load noticeably faster with ads blocked, and site breakage is rare.

The tradeoff is missing power-user features from the original - no dynamic filtering, no element picker, no real-time rule editing[33]. But for most users, the streamlined experience is better. Updates happen automatically, and you rarely need to think about it.

Sources: [Chrome Web Store](https://chromewebstore.google.com/detail/ublock-origin-lite/ddkjiahejlhfcafbddmgiahcphecmpfh)[48], [uBlock Origin Official](https://ublockorigin.com)[45]

---

## Wipr 2

Wipr 2 is designed for users who want things to work without configuration. App Store installation is effortless, and onboarding is minimal - activate the content blockers in Safari settings and you're done[37].

The interface is intentionally simple with clean SwiftUI design. The setup screens have friendly copy like "Welcome to Wipr!" with clear explanations[24]. This isn't a limitation but a design choice - simplicity over feature bloat.

[24][42]

Behind this simplicity is clever engineering. Wipr splits rules across multiple content blockers (Wipr 1, 2, 3, and Wipr Extra in Safari settings) to work around Safari's 150,000 rule limit per extension. The app handles this complexity automatically - you enable all blockers and let Wipr handle the rest[32].

The blocking test results show effectiveness with clean statistics. You can see 135/135 items blocked with simple, clear presentation without overwhelming technical details[42]. Automatic filter updates happen twice weekly in the background with zero user intervention.

Performance is excellent - 50MB RAM usage, minimal battery impact, and genuinely faster page loading. Sites that normally load slowly with ads and tracking feel noticeably snappier. Universal purchase covers iPhone, iPad, Mac, and Vision Pro[37].

The limitation is customization. If you want fine-grained control, element zapping, or custom filters, Wipr feels constraining. But if you prioritize reliability and simplicity, it's nearly perfect.

Sources: [App Store](https://apps.apple.com/us/app/wipr-2/id1662217862)[37], [All About Cookies Review](https://allaboutcookies.org/wipr-review)[34], [Reddit Discussion](https://www.reddit.com/r/macapps/comments/1gpc5e7/wipr_2_has_officially_released/)[32]

---

## AdGuard for Safari

AdGuard for Safari brings enterprise-level filtering to Safari, but with complexity. Installation requires enabling multiple content blockers - AdGuard General, AdGuard Privacy, AdGuard Social, AdGuard Security, AdGuard Custom, AdGuard Other, plus the main AdGuard for Safari extension[27].

The Safari Extensions panel shows seven different extensions working together. Each handles different rule categories to work within Safari's per-extension limits while maximizing total filtering capacity[25][27]. The interface shows version numbers, permissions required, and configuration options for each component.

[25][27]

The main AdGuard interface (toolbar icon) is feature-rich but can feel overwhelming. You get statistics, logging, custom filter editing, element blocking tools, and extensive configuration. Multi-language support is impressive with 20+ language filter lists and official translations.

Performance is challenging. The 600MB RAM usage reflects the comprehensive filtering approach. With seven extensions loaded and extensive filter lists, memory footprint can impact performance, especially on older Macs or limited RAM devices[6].

However, blocking effectiveness is excellent once configured. Element zapper works well, custom filter support lets you create precise rules, and logging provides detailed debugging. Integration with AdGuard's ecosystem (DNS filtering, VPN) offers comprehensive privacy solutions.

The complexity is both strength and weakness. Power users appreciate granular control and extensive features, but mainstream users may find setup daunting and interface cluttered. Occasional bugginess with many filter lists can frustrate users expecting simpler alternatives' polish.

If you're willing to invest configuration time and have sufficient system resources, AdGuard provides the most comprehensive blocking available. But the learning curve and resource requirements make it less suitable for casual users or older hardware.

Sources: Screenshots from Safari Extensions panel[25][27]



# Feature Comparison

| Feature                 | wBlock<sup>1</sup>                | uBlock Origin Lite<sup>2</sup> | Wipr 2<sup>3</sup>                 | AdGuard for Safari<sup>4</sup>     |
|-------------------------|-----------------------------------|----------------------|-----------------------|-----------------------|
| macOS Support           | ✅ TestFlight only<sup>5</sup>     | ✅          | ✅               | ✅               |
| iOS Support             | ✅ TestFlight only<sup>5</sup>     | ✅          | ✅               | ✅               |
| RAM Usage (MB)          | 40MB<sup>6</sup>                  | 120MB<sup>6</sup>   | 50MB<sup>6</sup>     | 600MB<sup>6</sup>     |
| Total Rule Capacity     | 750,000 macOS / 450,000 iOS<sup>7</sup> | N/A                 | 900,000 macOS / 300,000 iOS | 1,050,000 macOS / 350,000 iOS |
| GitHub Stars            | 1,400                              | 2,600                | N/A                   | 1,100                |
| Open Source             | ✅                                 | ✅                    | ❌                    | ✅                    |
| License<sup>18</sup>    | GPL-3.0                           | GPL-3.0              | Proprietary           | GPL-3.0              |
| Primary Language<sup>19</sup>        | Swift                | JavaScript   | Swift          | Obj-C/Swift   |
| Secondary Language      | Swift                             | CSS                  | N/A (Closed)          | Objective-C/Swift    |
| Extension Architecture<sup>8</sup>   | Content Blocker + App (macOS) / Web (iOS) | Manifest V3 Web Extension | Content Blocker + Web Extension | Content Blocker + Web Extension |
| Manifest Version<sup>9</sup>         | Safari Native                     | V3                   | Safari Native         | Safari Native        |
| Filterlist Storage Database<sup>10</sup> | Protobuf                        | IndexedDB + JSON     | Unknown               | SQLite + JSON        |
| Element Zapper<sup>11</sup>          | ✅                                 | ✅                    | ❌                    | ✅                    |
| Custom Filters          | ✅                                 | ❌                   | ❌                    | ✅ (Mac app only)     |
| Dynamic Filtering<sup>12</sup>       | ✅                                 | ❌ MV3 limited        | ❌                    | ✅                   |
| YouTube Ad Blocking     | ✅                                 | ✅                   | ✅                    | ✅                   |
| Script Injection<sup>13</sup>        | ✅                                 | ✅                   | ❌                    | ✅                   |
| Filter List Updates     | Manual (Auto coming)              | Extension updates only | Automatic (≈2×/week)| Automatic            |
| Userscripts Support<sup>14</sup>     | ✅                                 | ❌                   | ❌                    | ❌ (Mac app only)<sup>15</sup>   |
| User Interface          | SwiftUI – extensive               | JS – Popup/web panel | SwiftUI – minimal     | Obj-C/Swift – extensive, but buggy |
| Customization Level     | High                              | Medium               | None                  | High                 |
| Setup Complexity        | Easy                              | Easy                 | Very Easy             | Moderate             |
| Multi-Device Sync       | ❌                                 | ❌                   | ✅ Universal purchase  | ❌                   |
| AdBlock Tester Score<sup>16</sup>    | 100/100                             | 97/100               | 96/100                | 94/100               |
| Cost                    | Free                              | Free                 | $4.99 one-time        | Free                 |
| Subscription Model      | ❌                                 | ❌                   | ❌                    | ❌                   |
| Active Development      | ✅                                 | ✅                   | ✅                    | ✅                   |
| Community Size          | Growing (1.4k stars)              | Large (cross-browser)| Small/Independent     | Large (35M users)    |
| Per-Site Disable        | ✅                                 | ✅                   | ✅                    | ✅                   |
| Whitelist Management    | ✅                                 | ✅                   | ✅                    | ✅                   |
| Logging/Debugging       | ✅                                 | ❌                   | ❌                    | ✅                   |
| Foreign Lang. Filter Support<sup>17</sup> | ✅ 10+ (more addable manually; app in English) | ✅ 15+         | ✅ Unknown            | ✅ 20+ Languages     |

---

## Superscript Glossary & Explanations

<sup>1</sup> **wBlock:** Focuses on Safari, open-source, optimized for latest Safari API features.  
<sup>2</sup> **uBlock Origin Lite:** Chromium-only Manifest V3 extension. Not available for Safari.  
<sup>3</sup> **Wipr 2:** Closed-source, paid, lightweight, Safari-only ad blocker.  
<sup>4</sup> **AdGuard for Safari:** Safari extension by AdGuard (with separate paid Mac/iOS apps).

<sup>5</sup> *TestFlight only*: wBlock is distributed on iOS and sometimes macOS via TestFlight, Apple's developer beta platform, not through the public App Store.

<sup>6</sup> **RAM Usage Measurement**:  
Numbers were measured on a 2023 M2 Pro MacBook Pro 14" with 16GB RAM, 5 tabs open, only one ad blocker active. Actual memory usage can **vary widely** based on hardware, browser version, tab contents, number of active extensions, and enabled filter lists. Lower-spec Macs and iOS devices will observe different numbers.

<sup>7</sup> *Rule Capacity*:  
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
Lets users click and instantly hide page elements (ads, overlays, popups) in real time, no filter editing required. Absent in Wipr, which is more designed to be simple and don't-touch. 

<sup>12</sup> **Dynamic Filtering**:  
Advanced feature letting users interactively allow/block domains/scripts/network requests per-site (similar to uMatrix and original uBlock Origin dynamic filtering). Rare with Safari content blockers, available only via clever workarounds in wBlock/AdGuard.

<sup>13</sup> **Script Injection**:  
Lets extension run built-in or custom JavaScript on web pages (for ad removal, circumvention, UI fixes, etc.). Only available in web/app extensions, so only wBlock (and AdGuard for paid Mac app) provide true script injection. Most Chrome extensions do, but only within Manifest V3’s security limits as of 2025.

<sup>14</sup> **Userscripts Support**:  
Allows running or installing custom scripts (like Greasemonkey/Tampermonkey)—for automation, customization, or advanced blocking. Only wBlock (and AdGuard paid Mac app) support this natively. Safari App Store policies restrict this in other extensions.

<sup>15</sup> AdGuard's userscript support is available only in its paid standalone Mac application, not the Safari browser extension.

<sup>16</sup> **AdBlock Tester Score**:  
AdBlock Tester scores (adblocktester.com, etc.) depend mostly on which filter lists you enable—extension features matter less. Even simple ad blockers can score 100/100 if using up-to-date and comprehensive lists; heavy, feature-rich blockers may score lower if filters are incomplete or outdated.

<sup>17</sup> **Foreign Language Filter Support**:  
Reflects whether ad blockers have official filter lists for multiple languages/regions. AdGuard supports 20+ languages with official filters; uBlock Origin Lite permits more than 15; wBlock can load manual lists but the app itself is limited to English for now.

<sup>18</sup> **License**:  
Describes the legal terms governing code and usage:  
- GPL-3.0: Open-source license allowing code modification and redistribution as long as further releases are also open source.  
- Proprietary: Closed source, so users cannot view or modify the code at all. 

<sup>19</sup> **Primary Language**:  
Refers to the main programming language(s) used.  
- Swift: Indicates a native Apple/macOS/iOS app/extension, making it fully native and optimized for Apple devices. 
- JavaScript: Indicates a web-based or cross-browser extension (more universal, usually less efficient).  
- Objective-C: The predecessor to Swift. Also technically native, but very archaic. In AdGuard's case, there are often memory leaks that lead to ballooning memory usage. 

---
