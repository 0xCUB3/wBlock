| Feature                 | wBlock<sup>1</sup>                | uBlock Origin Lite<sup>2</sup> | Wipr 2<sup>3</sup>                 | AdGuard for Safari<sup>4</sup>     |
|-------------------------|-----------------------------------|----------------------|-----------------------|-----------------------|
| macOS Support           | ✅ TestFlight only<sup>5</sup>     | ✅          | ✅               | ✅               |
| iOS Support             | ✅ TestFlight only<sup>5</sup>     | ✅          | ✅               | ✅               |
| RAM Usage (MB)          | 40MB<sup>6</sup>                  | 120MB<sup>6</sup>   | 50MB<sup>6</sup>     | 600MB<sup>6</sup>     |
| Total Rule Capacity     | 750,000 macOS / 450,000 iOS<sup>7</sup> | N/A                 | 900,000 macOS / 300,000 iOS | 1,050,000 macOS / 350,000 iOS |
| GitHub Stars            | 1,400                              | 2,600                | N/A                   | 1,100                |
| Open Source             | ✅                                 | ✅                    | ❌                    | ✅                    |
| License                 | GPL-3.0                           | GPL-3.0              | Proprietary           | GPL-3.0              |
| Primary Language        | JavaScript (80.8%)                | JavaScript (96.5%)   | N/A (Closed)          | JavaScript (78.8%)   |
| Secondary Language      | Swift (18.9%)                     | CSS (3.3%)           | N/A (Closed)          | Objective-C (14.4%)  |
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

<sup>1</sup> **wBlock:** Focuses on Safari, open-source, optimized for latest Safari API features.  
<sup>2</sup> **uBlock Origin Lite:** Chromium-only Manifest V3 extension. Not available for Safari.  
<sup>3</sup> **Wipr 2:** Closed-source, paid, lightweight, Safari-only ad blocker.  
<sup>4</sup> **AdGuard for Safari:** Safari extension by AdGuard (with separate paid Mac/iOS apps).

<sup>5</sup> *TestFlight only*: wBlock is distributed on iOS and sometimes macOS via TestFlight, Apple's developer beta platform, not through the public App Store.

<sup>6</sup> **RAM Usage Measurement**:  
These figures were measured on a 2023 M2 Pro MacBook Pro 14" with 16GB RAM, five average web tabs open, and only the respective ad blocker enabled (others disabled). RAM usage can **vary significantly** by device (CPU architecture and memory), Safari version, number/kind of open tabs, loaded filter lists, and other running extensions; true RAM use seen in Activity Monitor may differ on lower-end or older Macs and on iOS.

<sup>7</sup> *Rule Capacity*:  
Safari limits rule sets to about 150,000 per content blocker. Blockers work around this by using multiple bundled extensions (slots)—the numbers listed reflect the combined total when all are enabled.

<sup>8</sup> **Extension Architecture**:  
How the ad blocker is built and operates in Safari/other browsers.  
- Content Blocker Extension: Uses Apple's highly sandboxed, fast native API; strict limits on scripting.  
- Manifest V3 Web Extension: Used by Chrome, limits dynamic content/script injection for privacy; not supported natively in Safari.  
- Web Extension: Cross-browser format for Chrome, Firefox, Edge (not always fully compatible with Safari).

<sup>9</sup> **Manifest Version**:  
Shows underlying browser extension standard. Chrome/Chromium uses Manifest V3 (security improvements, reduced extension script power). Safari uses its own native extension system, with differing capabilities (e.g., more restricted scripting).

<sup>10</sup> **Filterlist Storage Database**:  
How filtering rules/lists are saved on disk for fast access:  
- Protobuf: Efficient binary format, used by wBlock for speed and reduced storage.  
- IndexedDB + JSON: Browsers' built-in structured storage, preferred by uBlock Origin Lite for cross-browser compatibility.  
- SQLite + JSON: Relational database format, preferred by AdGuard for scaling with massive filter lists.  
- Unknown: Wipr is closed source.

<sup>11</sup> **Element Zapper**:  
Lets users instantly hide any on-page item (ad, overlay, popup) by clicking, without editing code or rules. Helpful for "annoyance" removal—absent in Wipr for simplicity.

<sup>12</sup> **Dynamic Filtering**:  
Advanced user feature: interactively block/allow domains/scripts per-site (like uMatrix, classic uBlock dynamic filtering). Rare in Safari, partly available in wBlock and AdGuard as workarounds.

<sup>13</sup> **Script Injection**:  
Lets extension run custom or pre-made JavaScript on sites for advanced ad/tracker removal, DOM tweaks, or circumvention. Only wBlock (and AdGuard paid Mac app) support full custom scripting in Safari; uBlock Origin Lite scriptlets only work in Chromium, not Safari.

<sup>14</sup> **Userscripts Support**:  
Allows importing/writing Greasemonkey/Tampermonkey scripts (custom automation, ad circumvention, UI fixes) in the blocker. A wBlock/AdGuard Mac feature—most Safari blockers don’t support this due to Apple’s security sandboxing.

<sup>15</sup> *AdGuard for Mac app only*:  
Full userscript support is ONLY available in AdGuard's paid Mac application, not in the Safari extension version.

<sup>16</sup> **AdBlock Tester Score**:  
This score comes from synthetic test sites (adblocktester.com, etc). **Most strongly affected by filter lists enabled, not blocker code**: a minimal blocker with updated, thorough lists will perform just as well as a heavyweight blocker with out-of-date or inadequate lists. The scores reflect filtering coverage, update rate, filter syntax completeness, and optimal filter list selection.

<sup>17</sup> **Foreign Language Filter Support**:  
Measures official or supported filter lists for languages/regions.  
- AdGuard has 20+ language filters by default, the most.  
- uBlock Origin Lite allows 15+ languages.  
- wBlock and Wipr can load third-party lists if found, but only English in the app UI.

---
