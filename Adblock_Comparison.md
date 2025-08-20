| Feature                 | wBlock<sup>1</sup>                | uBlock Origin Lite<sup>2</sup> | Wipr 2<sup>3</sup>                 | AdGuard for Safari<sup>4</sup>     |
|-------------------------|-----------------------------------|----------------------|-----------------------|-----------------------|
| macOS Support           | ✅ Full                            | ❌ No Safari          | ✅ Full               | ✅ Full               |
| iOS Support             | ❌ TestFlight only<sup>5</sup>     | ❌ No Safari          | ✅ Full               | ✅ Full               |
| Safari Support          | ✅ Primary focus                   | ❌ No Safari support  | ✅ Excellent          | ✅ Excellent          |
| Chrome Support          | ❌                                 | ✅ Primary            | ❌                    | ❌ Separate ext       |
| Firefox Support         | ❌                                 | ✅ Limited            | ❌                    | ❌ Separate ext       |
| RAM Usage (MB)          | 40MB                               | 120MB                | 50MB                  | 600MB<sup>6</sup>     |
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

---

### Glossary

<sup>1</sup> **wBlock:** Focuses on Safari, open-source, optimized for latest Safari API features.  
<sup>2</sup> **uBlock Origin Lite:** Chromium-only Manifest V3 extension. Not available for Safari.  
<sup>3</sup> **Wipr 2:** Closed-source, paid, lightweight, Safari-only ad blocker.  
<sup>4</sup> **AdGuard for Safari:** Safari extension by AdGuard (with separate paid Mac/iOS apps).

<sup>5</sup> wBlock iOS version is only distributed via TestFlight (Apple’s developer beta platform), not the public App Store.  
<sup>6</sup> AdGuard for Safari’s RAM usage is an outlier due to multiple content blocker components and aggressive filter loading.  
<sup>7</sup> Rule capacity depends on how the extension splits filter lists into multiple content blockers. Safari allows max 150,000 rules per content blocker, so blockers like AdGuard and Wipr split lists across multiple extensions to surpass a single extension’s limits.  
<sup>8</sup> **Extension Architecture:**  
Describes how the ad blocker runs in Safari or other browsers.  
- Content Blocker Extension: Uses Safari’s native blocking API; efficient, privacy-focused, but limited in dynamic interaction and scripting.  
- Manifest V3: Used by Chrome extensions, allowing more dynamic control but with increased privacy restrictions starting in Manifest V3.  
- Web Extension: Runs via a browser’s cross-compatible extension API (e.g., Chrome, Firefox, Edge).  
  
<sup>9</sup> **Manifest Version:**  
Safari uses its own native extension system, while Chrome/Chromium browsers use Manifest V3, which changes extension access to requests and filtering for security. Dynamic capabilities are more restricted in Manifest V3 compared to Safari Native.

<sup>10</sup> **Filterlist Storage Database:**  
How rules are stored and managed on disk.  
- Protobuf: Efficient, binary storage (fast load/save, low disk usage).  
- IndexedDB/JSON: Browser-provided database APIs (structured storage, easy for web extensions).  
- SQLite: Relational database, flexible but larger footprint.  
- Unknown: Wipr is closed source, so details aren’t public.

<sup>11</sup> **Element Zapper:**  
Lets users click on page elements to hide them instantly, even if there’s no ad filter rule. Useful for overlays, nags, popups. Not offered in Wipr, a simplicity-focused ad blocker.

<sup>12</sup> **Dynamic Filtering:**  
Lets users block domains/scripts/network requests dynamically (site-by-site, not just static rules). Safari Content Blockers rarely allow this natively; wBlock and AdGuard have workarounds. Manifest V3 restricts dynamic filtering compared to previous Chrome extension versions.

<sup>13</sup> **Script Injection:**  
Ability to execute custom or built-in JavaScript on web pages. This is limited on Safari for security reasons, but wBlock and (sometimes) AdGuard enable it via native app integration. Chrome extensions generally have greater scripting support.

<sup>14</sup> **Userscripts Support:**  
Ability to write and run custom userscripts/scripts (similar to Greasemonkey/Tampermonkey). Only wBlock (and paid AdGuard on Mac app, not extension) supports this fully in Safari—making it a standout for advanced customization. Others either lack it or only offer partial support via scriptlets.

<sup>15</sup> AdGuard’s userscript support is only available in the paid standalone Mac app, not the Safari browser extension.

<sup>16</sup> **AdBlock Tester Score:**  
This tester score (from adblocktester.com/adblock-tester.com) mostly reflects which filter lists are enabled, update speed, and completeness of rules—not the ad blocker’s codebase itself. For example, a simple extension can achieve nearly perfect scores with optimized, current blocklists, while heavier, feature-rich blockers can score lower if filters are out of date or not configured. So, filter choice is the main driver.

<sup>17</sup> **Foreign Language Filter Support:**  
Indicates how many languages and regions are served by dedicated filterlists. AdGuard offers the most, with 20+ language filters. uBlock Origin Lite can enable 15+ official lists. wBlock and Wipr support custom language lists, but only English is the official app language, and support depends on manual configuration.

---
