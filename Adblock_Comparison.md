| Feature                 | wBlock<sup>1</sup>                  | uBlock Origin Lite<sup>2</sup> | Wipr 2<sup>3</sup>             | AdGuard for Safari<sup>4</sup>     |
|-------------------------|-------------------------------------|----------------------|-----------------------|-----------------------|
| macOS Support           | ✅ Full                              | ❌ No Safari          | ✅ Full               | ✅ Full               |
| iOS Support             | ❌ TestFlight only<sup>A</sup>       | ❌ No Safari          | ✅ Full               | ✅ Full               |
| Safari Support          | ✅ Primary focus                     | ❌ No Safari support  | ✅ Excellent          | ✅ Excellent          |
| Chrome Support          | ❌                                   | ✅ Primary            | ❌                    | ❌ Separate ext       |
| Firefox Support         | ❌                                   | ✅ Limited            | ❌                    | ❌ Separate ext       |
| RAM Usage (MB)          | 40MB                                 | 120MB                | 50MB                  | 600MB<sup>B</sup>     |
| Total Rule Capacity     | 750,000 macOS / 450,000 iOS<sup>C</sup> | N/A                 | 900,000 macOS / 300,000 iOS | 1,050,000 macOS / 350,000 iOS |
| GitHub Stars            | 1,400                                | 2,600                | N/A                   | 1,100                |
| Open Source             | ✅                                   | ✅                    | ❌                    | ✅                    |
| License                 | GPL-3.0                             | GPL-3.0              | Proprietary           | GPL-3.0              |
| Primary Language        | JavaScript (80.8%)                  | JavaScript (96.5%)   | N/A (Closed)          | JavaScript (78.8%)   |
| Secondary Language      | Swift (18.9%)                       | CSS (3.3%)           | N/A (Closed)          | Objective-C (14.4%)  |
| Extension Architecture<sub>a</sub>  | Content Blocker + App (macOS) / Web (iOS) | Manifest V3 Web Extension | Content Blocker + Web Extension | Content Blocker + Web Extension |
| Manifest Version<sub>b</sub>        | Safari Native                       | V3                   | Safari Native         | Safari Native        |
| Filterlist Storage Database<sub>c</sub> | Protobuf                        | IndexedDB + JSON     | Unknown               | SQLite + JSON        |
| Element Zapper<sub>d</sub>          | ✅                                   | ✅                    | ❌                    | ✅                    |
| Custom Filters          | ✅                                   | ❌                   | ❌                    | ✅ (only on Mac app)  |
| Dynamic Filtering<sub>e</sub>       | ✅                                   | ❌ MV3 limited        | ❌                    | ✅                   |
| YouTube Ad Blocking     | ✅                                   | ✅                   | ✅                    | ✅                   |
| Script Injection<sub>f</sub>        | ✅                                   | ✅                   | ❌                    | ✅                   |
| Filter List Updates     | Manual (Auto coming)                | Extension updates only | Automatic (≈2×/week)| Automatic            |
| Userscripts Support<sub>g</sub>     | ✅                                   | ❌                   | ❌                    | ❌ (Mac app only)<sup>E</sup>   |
| User Interface          | SwiftUI – extensive                 | JS – Popup/web panel | SwiftUI – minimal     | Obj-C/Swift – extensive, but buggy |
| Customization Level     | High                                | Medium               | None                  | High                 |
| Setup Complexity        | Easy                                | Easy                 | Very Easy             | Moderate             |
| Multi-Device Sync       | ❌                                   | ❌                   | ✅ Universal purchase  | ❌                   |
| AdBlock Tester Score<sub>h</sub>    | 100/100                             | 97/100               | 96/100                | 94/100               |
| Cost                    | Free                                | Free                 | $4.99 one-time        | Free                 |
| Subscription Model      | ❌                                   | ❌                   | ❌                    | ❌                   |
| Active Development      | ✅                                   | ✅                   | ✅                    | ✅                   |
| Community Size          | Growing (1.4k stars)                | Large (cross-browser) | Small/Independent    | Large (35M users)    |
| Per-Site Disable        | ✅                                   | ✅                   | ✅                    | ✅                   |
| Whitelist Management    | ✅                                   | ✅                   | ✅                    | ✅                   |
| Logging/Debugging       | ✅                                   | ❌                   | ❌                    | ✅                   |
| Foreign Lang. Filter Support<sub>i</sub> | ✅ 10+ (more addable manually; app in English) | ✅ 15+         | ✅ Unknown            | ✅ 20+ Languages     |

---

### General Footnotes

<sup>1</sup> **wBlock:** Focuses on Safari, open-source, and aims for maximum compatibility with the latest macOS/iOS Safari APIs.  
<sup>2</sup> **uBlock Origin Lite:** Only works on Chromium browsers, not available for Safari. "Lite" version is a Manifest V3 rewrite for Chrome.  
<sup>3</sup> **Wipr 2:** A paid, closed-source Safari-only ad blocker with a reputation for being lightweight and easy for non-technical users.  
<sup>4</sup> **AdGuard for Safari:** The official AdGuard extension for Safari. AdGuard also makes standalone Mac and iOS apps, which may offer additional features.

<sup>A</sup> *wBlock iOS*: Only available via TestFlight as of August 2025, not general public App Store release.  
<sup>B</sup> *AdGuard for Safari RAM*: AdGuard’s RAM usage is a major outlier, explained by splitting filtering rules into multiple separate extensions for Safari’s Content Blocker architecture, preloading extensive filter lists, and supporting more granular filtering.  
<sup>C</sup> *Rule Capacity*: Per-extension rule limits set by Safari (usually 150,000 rules each) force blockers to split into multiple content blocker extensions if their rule sets exceed the limit. This explains why AdGuard/Safari and Wipr list higher rule capacities.

<sup>E</sup> *Userscripts Support Outlier*: Only wBlock (and paid AdGuard Mac app, not browser extension) offers true userscript support, letting users create custom scripts run on web pages. Most Safari extensions cannot inject custom user scripts due to Apple's security restrictions.

---

### Subscript Glossary & Explanations

<sub>a</sub> **Extension Architecture**:  
Safari permits "Content Blocker" extensions that run using Apple’s native content blocking API with rule-based filtering, and separately, "Web Extensions" (usually for Chrome/Firefox compatibility, more features, fewer rules).  
- wBlock and Wipr are Safari-native Content Blockers (with some support for Web Extensions or communication apps for custom rules/scripts).  
- uBlock Origin Lite is a "Manifest V3 Web Extension," only compatible with Chromium browsers, not Safari (hence no direct support).

<sub>b</sub> **Manifest Version**:  
Ad blockers in Chrome use the Manifest V3 API, which restricts many advanced capabilities compared to V2, especially dynamic rule changes and network request modification. Safari uses a "Safari Native" system for extensions, which is more efficient but limits flexibility (e.g., script injection is rare, but wBlock enables it through a custom bridge).

<sub>c</sub> **Filterlist Storage Database**:  
Blocking rules are stored in various formats:  
- wBlock uses efficient Protobuf binary format for rule lists.  
- AdGuard stores in SQLite with JSON for speed and scale.  
- uBlock Origin Lite uses IndexedDB and JSON to store filterlists for fast lookups in Chromium browsers.  
- Wipr’s storage is closed-source/unknown but likely Apple’s property lists or local files.

<sub>d</sub> **Element Zapper**:  
Allows users to click and hide page elements (e.g., overlays, ads, cookie notices) without editing filters.  
- Provided by wBlock, uBlock Origin Lite, and AdGuard, not Wipr.

<sub>e</sub> **Dynamic Filtering**:  
Lets advanced users control domains/scripts on-the-fly (similar to uMatrix, classic uBlock Origin "dynamic filtering") to allow/block network requests, cookies, scripts per-site.  
- Safari restricts these features; wBlock and AdGuard find workarounds. uBlock Origin Lite is “limited” since Manifest V3 now restricts dynamic scripting.

<sub>f</sub> **Script Injection**:  
Refers to ability to run custom or built-in code (JavaScript) on web pages, typically for ad circumvention, element removal, tracking control, etc.  
- Most Safari blockers don’t allow “free” injection for App Store policies.  
- wBlock is an outlier with real user script support. uBlock Origin Lite supports scriptlets but ONLY on Chromium, not Safari.

<sub>g</sub> **User Script Support** (Outlier):  
Only wBlock (and paid standalone AdGuard for Mac app) let users write and use their own scripts (similar to Greasemonkey/Tampermonkey), enhancing flexibility but making review and safe usage harder in Safari.

<sub>h</sub> **AdBlock Tester Score**:  
This score (from adblocktester.com and similar sites) varies much less due to the extension, and far more due to what filter lists the user enables. A lightweight adblocker with excellent filter lists can often match or exceed the blocking capabilities of heavier blockers. Scores reflect not just the engine, but update frequency, specific filtering lists, and filter syntax support. So, high scores often indicate active maintenance, broad filter coverage, and user customization—more than technical blocker architecture itself.

<sub>i</sub> **Foreign Language Filter Support**:  
Indicates how many languages have filterlists available for blocking region-specific ads and trackers.  
- AdGuard leads with broad language support and official lists.  
- uBlock Origin Lite also supports many languages, but effect depends on which lists are active.  
- wBlock and Wipr can manually add new lists, but official app language is usually only English.

---
