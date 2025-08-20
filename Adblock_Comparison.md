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
Reflects whether ad blockers have official filter lists for multiple languages/regions. AdGuard supports 20+ languages with official filters; uBlock Origin Lite permits more than 15; wBlock and Wipr can load manual lists but are limited to English UI.

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
