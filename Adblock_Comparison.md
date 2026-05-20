# Safari ad blocker comparison

_Last reviewed: May 20, 2026._

Safari ad blockers all have the same issue. Safari is not Chrome, and it is definitely not Firefox with classic uBlock Origin. The easiest option is Apple's Content Blocking API, where an app gives Safari a declarative rule list that Safari compiles and applies inside the browser engine. That is good for privacy and battery life, but the extension cannot sit on every request and decide what to do at runtime. Anything more flexible has to happen somewhere else. Cosmetic filtering, scriptlets, element picking, YouTube workarounds, and per-page controls usually live in a Safari Web Extension or in scripts injected by one. This comparison covers wBlock, uBlock Origin Lite, Wipr 2, and AdGuard's Safari apps: AdGuard Mini on macOS and AdGuard for iOS on iPhone and iPad.

## wBlock

wBlock is a native Safari blocker for macOS, iOS, and iPadOS. It uses five Safari content blocker extensions per platform, which gives it five 150,000-rule slots and a 750,000-rule ceiling when all slots are available. That number is not the same thing as source filter lines. A single AdGuard rule can expand, collapse, or disappear during conversion depending on whether Safari can express it. wBlock exposes the final converted number to give the user an accurate sense of how many rules each list really takes up.

The app stores filter metadata and compiled data with Protocol Buffers and LZ4 compression. That is a practical choice for this kind of app, since filter lists are large, repetitive, and updated often, while the UI needs to stay responsive when the user enables a list or imports a custom subscription. Updates use HTTP conditional requests through `ETag` and `If-Modified-Since`, so a scheduled refresh does not need to download a full list when the server can prove nothing changed.

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/apply_changes_dark.png" width="700" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/apply_changes_light.png" width="700" />
    <img src="docs/media/img/apply_changes_light.png" alt="Apply Changes Screenshot" width="700" />
  </picture>
</div>

The static blocking pipeline is only half of the app. wBlock Scripts handles the parts Safari content blockers cannot express cleanly, including but not limited to cosmetic selectors, scriptlets, user scripts, and the element zapper. The zapper works in Safari extension contexts across macOS, iOS, iPadOS, and visionOS, and keeps track of page position and lets the user walk up or down the DOM selection, which is important because the clicked node is often an inner icon or text span rather than the ad container the user actually wants to hide.

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/zapper_dark.png" width="350" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/zapper_light.png" width="350" />
    <img src="docs/media/img/zapper_light.png" alt="Element Zapper" width="350" />
  </picture>
</div>

The userscript support is the most ambitious part of wBlock. Safari does not have the mature userscript extension ecosystem that Chromium and Firefox users take for granted, so wBlock ships its own Greasemonkey-style layer. The current implementation covers storage, resources, menu commands, GM XHR, and both legacy `GM_*` and modern `GM.*` forms for common APIs. That gives Safari users an option for scripts that would otherwise require a separate userscript manager, although scripts that depend on obscure Tampermonkey behavior may still need fixes.

The debugging view is where wBlock gets more opinionated. The main view reports source rule counts, converted Safari rule counts, conversion time, reload time, and the categories touched by a change. Per-site disabling is implemented with Safari-compatible exception rules and targeted rebuilds instead of live request interception, because Safari does not allow the latter through the content blocker API.

wBlock is strongest when the user wants to see and control the machinery: custom lists, userscripts, visible conversion output, iCloud sync, and debugging tools. Its tradeoff is maturity. Basic blocking is straightforward, but userscript compatibility is a long tail, and a few complicated scripts will expose missing API edges before a set-and-forget blocker would.

References: [wBlock GitHub](https://github.com/0xCUB3/wBlock), [wBlock App Store](https://apps.apple.com/us/app/wblock/id6746388723)

---

## uBlock Origin Lite

uBlock Origin Lite is not classic uBlock Origin with a smaller UI. It is a separate lobotomized Manifest V3 project built around declarative filtering to circumvent Google Chrome's new restrictions on content blocking through the depracation of Manifest V2. In Chrome terms that means `declarativeNetRequest`; in Safari's App Store build, Apple still has its own extension packaging and conversion path. The important bit is the same either way. The rules are prepared ahead of time, shipped as extension rulesets, and enforced by the browser rather than by a persistent request-filtering background page.

That architecture gives uBOL much of its appeal. It has low background overhead, it inherits a lot of filter knowledge from the uBlock Origin ecosystem, and it works on iPhone, iPad, Mac, and Vision Pro through the App Store. The popup's basic, optimal, and complete modes are really presets for how much filtering the extension is allowed to do on the current site. The options page exposes additional bundled rulesets rather than turning the app into a full filter-subscription manager.

<div align="center">
  <img src="docs/media/img/adblock_comparison/ublock_origin_lite.png" alt="uBlock Origin Lite Screenshot" width="700" />
</div>

The downside is the same one that affects every MV3-style blocker. Once the browser owns the request decision, the extension loses the freedom that made classic uBO so powerful. uBOL does not have uBO's dynamic filtering matrix, dynamic URL filtering, per-site no-scripting switch, or arbitrary filter list workflow. In other words, the only way to update filterlists is to update the app itself. Recent versions have a custom filters area for limited cases, especially cosmetic rules created through the picker flow, but that is not equivalent to maintaining a large set of network subscriptions and dynamic rules by hand.

uBOL makes the most sense for people who want uBO-flavored defaults with almost no maintenance. It is free, open source, and its App Store privacy label is Data Not Collected. If your muscle memory depends on classic uBO's advanced pane, though, uBOL will feel constrained because the browser's declarative model is doing exactly what it was designed to do.

References: [uBOL GitHub](https://github.com/uBlockOrigin/uBOL-home), [uBOL FAQ](https://github.com/uBlockOrigin/uBOL-home/wiki/Frequently-asked-questions-(FAQ)), [uBOL App Store](https://apps.apple.com/us/app/ublock-origin-lite/id6745342698)

---

## Wipr 2

Wipr 2 takes the opposite approach from wBlock. It is a paid native Safari blocker with very few knobs. The user enables the Wipr blocklist extensions and Wipr Extra, then mostly leaves the app alone. There is no public filter subscription interface, no user rule editor, no request log, and no visible rule-conversion report.

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/adblock_comparison/wipr_2_dark.png" width="700" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/adblock_comparison/wipr_2_light.png" width="700" />
    <img src="docs/media/img/adblock_comparison/wipr_2_light.png" alt="Wipr 2 Screenshot" width="700" />
  </picture>
</div>

The architecture is still Safari-native. The main Wipr blocklists use Safari content blockers, while Wipr Extra is a Safari Web Extension for cases where static rules are not enough, such as YouTube ads and some anti-adblock behavior. Extra asks for broader website access because it has to see and modify page content. That is the normal Safari permission tradeoff, since static blockers are narrow and private while web extensions can do more but need more trust.

Wipr's regional support is also automatic. Instead of asking the user to pick filter subscriptions, Wipr selects enhanced blocklists based on the device's preferred languages. Updates run automatically twice a week. The rule capacity is not published as one total, so it is hard to compare raw capacity against wBlock's five slots or AdGuard's six slots without reverse-engineering the installed blockers, though this is by design. 

This is the blocker for people who do not want to manage a blocker. That is not a backhanded compliment; there is real value in an app that stays out of the way and has a clean App Store privacy label. The cost is that there is nowhere to go when you want to inspect a false positive, add a niche filter list, or debug a site-specific miss yourself.

References: [Wipr 2 App Store](https://apps.apple.com/us/app/wipr-2/id1662217862), [Wipr Help](https://kaylees.site/wipr-help.html)

---

## AdGuard Mini and AdGuard for iOS

AdGuard's Safari suite is split across products. AdGuard Mini is the macOS Safari app formerly called AdGuard for Safari. AdGuard for iOS is the iPhone and iPad app. The full AdGuard for Mac app is a different thing again: it is the system-wide macOS product, not just a Safari content blocker, and since it is paid and roughly approximates AdGuard Mini for Safari purposes, I will exclude it from this review. 

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/adblock_comparison/adguard_mini_dark.png" width="700" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/adblock_comparison/adguard_mini_light.png" width="700" />
    <img src="docs/media/img/adblock_comparison/adguard_mini_light.png" alt="AdGuard Mini Screenshot" width="700" />
  </picture>
</div>

Mini uses six Safari content blockers: General, Privacy, Social, Security, Other, and Custom, not unlike wBlock. With Safari's 150,000-rule limit per content blocker, that gives Mini a published ceiling of 900,000 compiled rules. As with every Safari blocker, the ceiling is only meaningful after conversion. Mini is much more configurable than Wipr and more traditional than uBOL. It has filter categories, custom filters, user rules, element blocking, issue reporting, and an advanced rule editor. The free version covers basic Safari blocking. Pro unlocks real-time filter updates, AdGuard Extra for more stubborn anti-adblock and ad cases, and a few other advanced filtering features.

AdGuard for iOS follows the same broad design, adapted to iOS. It has six content blockers named General, Privacy, Social, Security, Custom, and Other. Its Safari protection includes filter groups, user rules, an allowlist, and custom filter URLs. The Safari Web Extension adds the in-browser controls: toggle protection for the current site, manually block an element, report a filtering issue, and apply advanced filtering rules and scriptlets when Premium is enabled.

The iOS app also has DNS protection, which is worth separating from Safari filtering. DNS blocking can cover more than Safari because it works at the resolver level, commonly through a local VPN-style configuration on iOS, but it only sees hostnames. It cannot hide page elements or make path-level URL decisions after an encrypted HTTPS connection is established. In practice, Safari content blockers handle page filtering, the Web Extension handles advanced page behavior, and DNS filtering catches domain-level tracking or ad hosts across the device.

AdGuard also has both AdGuard and AdGuard Pro in the iOS App Store. Historically they differed because App Store rules changed over time, but the current products are effectively parallel ways to get the same advanced iOS feature set. You do not need to install both.

AdGuard is the most mature filtering ecosystem in this comparison. It has broad regional coverage, a long-running rule syntax, and polished reporting flows. The tradeoff is product split as well as cost for the most advanced features. 

References: [AdGuard Mini](https://adguard.com/en/adguard-mini-mac/overview.html), [AdGuard Mini App Store](https://apps.apple.com/pl/app/adguard-mini/id1440147259?mt=12), [AdGuard Mini GitHub](https://github.com/AdguardTeam/AdGuardMiniForMac), [AdGuard rule limit KB](https://adguard.com/kb/adguard-mini-for-mac/solving-problems/rule-limit/), [AdGuard for iOS](https://adguard.com/en/adguard-ios/overview.html), [AdGuard for iOS GitHub](https://github.com/AdguardTeam/AdguardForiOS), [AdGuard iOS Safari protection KB](https://adguard.com/kb/adguard-for-ios/features/safari-protection/), [AdGuard iOS Web Extension KB](https://adguard.com/kb/adguard-for-ios/web-extension/), [AdGuard and AdGuard Pro KB](https://adguard.com/kb/adguard-for-ios/adguard-and-adguard-pro/)

---

# Feature comparison

| **Feature** | **wBlock** | **uBlock Origin Lite** | **Wipr 2** | **AdGuard Mini / iOS** |
|:--|:--:|:--:|:--:|:--:|
| macOS support | ✅ | ✅ | ✅ | ✅ via Mini |
| iOS / iPadOS support | ✅ | ✅ | ✅ | ✅ via AdGuard for iOS<sup>20</sup> |
| visionOS support | ✅ extension pieces | ✅ | ✅ | ❌ |
| Static rule capacity | 750,000<sup>7</sup> | DNR-based, browser-dependent<sup>7</sup> | 4 blocklist extensions, total not published<sup>7</sup> | 900,000 Mini; iOS uses six 150k slots<sup>7</sup> |
| Static blocking model | Safari content blockers | Packaged declarative rulesets | Safari content blockers | Safari content blockers |
| Page-level model | Safari Web Extension scripts | Extension content scripts | Wipr Extra Web Extension | Safari Web Extension / AdGuard Extra |
| RAM usage measured locally | ~40 MB<sup>6</sup> | ~120 MB<sup>6</sup> | ~50 MB<sup>6</sup> | ~100 MB Mini<sup>6</sup> |
| GitHub stars (not a feature, just a popularity signal) | ~2.5k | ~3.3k for uBOL | N/A | ~1.2k Mini / ~1.7k iOS |
| Open source | ✅ | ✅ | ❌ | ✅, license differs by app |
| License | GPL-3.0 | GPL-3.0 | Proprietary | Mini: AdGuard source license; iOS: GPL-3.0 |
| Main implementation | Swift + JavaScript | JavaScript | Swift | Swift + web UI |
| Filter storage | Protocol Buffers + LZ4 | Packaged DNR rulesets + extension storage | Closed source | App storage + JSON/rules files |
| Element zapper / picker | ✅ | ✅ for cosmetic filters | ❌ | ✅ |
| Custom filter lists | ✅ | Limited, not full subscription management | ❌ | ✅ |
| User rule editor | ✅ | Limited | ❌ | ✅ |
| Dynamic filtering | Safari-compatible approximation<sup>12</sup> | ❌ | ❌ | Limited, not uBO-style<sup>12</sup> |
| YouTube ad blocking | ✅ | ✅ / changes often | ✅ via Wipr Extra | ✅, stronger with Pro Extra |
| Script injection / scriptlets | ✅ | Limited scriptlet support | Wipr Extra only | ✅ |
| Userscript support | ✅ | ❌ | ❌ | ❌ in Mini / iOS<sup>15</sup> |
| Filter updates | Automatic, 1h to 7d configurable | Extension updates only | Automatic, twice weekly | Automatic; real-time updates require Pro |
| Multi-device sync | ✅ iCloud | ❌ | ❌ settings sync, universal purchase | ❌ |
| Per-site disable | ✅ | ✅ | ✅ through Safari/Wipr controls | ✅ |
| Whitelist / allowlist | ✅ | ✅ | ✅ | ✅ |
| Logging / debugging | ✅ macOS logger | ❌ | ❌ | ✅ |
| DNS-level blocking | ❌ | ❌ | ❌ | ✅ on iOS |
| Regional / language filters | ✅, plus manual lists | ✅ bundled rulesets | ✅ 30+ language variants | ✅ broad AdGuard filter catalog |
| App Store privacy label | Data Not Collected | Data Not Collected | Data Not Collected | Data Not Collected on current App Store labels |
| Interface style | Native, detailed | Popup + web options | Native, minimal | Detailed AdGuard apps |
| Cost | Free | Free | $4.99 one-time, optional tips | Free, Pro subscription / license |
| Natural fit | Safari users who want control and visibility | Users who want uBO-style defaults without classic uBO complexity | Users who do not want to configure anything | Users already comfortable with AdGuard's filter ecosystem |

---

## Notes

<sup>5</sup> **wBlock App Store:** https://apps.apple.com/app/wblock/id6746388723

<sup>6</sup> **RAM usage:** These are local spot checks on a 2023 M2 Pro MacBook Pro with a small tab set and only one blocker active. Treat them as rough numbers, not benchmarks. Browser version, enabled filters, tabs, and websites can move the numbers a lot.

<sup>7</sup> **Rule capacity:** Safari content blocker extensions are capped at about 150,000 compiled rules each on current Apple platforms. wBlock ships five content blocker slots, for 750,000 total. AdGuard Mini ships six, for 900,000 total. AdGuard for iOS also uses six content blockers on iOS 15 and later. Wipr documents four blocklist extensions but does not publish a single total rule count. uBOL uses packaged declarative rulesets, so its limits depend on the browser's declarative ruleset handling rather than Safari content blocker slots alone.

<sup>8</sup> **Content Blocker Extension:** Apple's native declarative filtering API. It is fast and private because Safari applies compiled rules internally, but it cannot behave like a live request-filtering engine.

<sup>9</sup> **Manifest V3:** Chrome's newer extension model. uBOL is built around MV3's declarativeNetRequest approach. Safari can run WebExtensions, but it still has its own extension packaging, permissions, and content-blocking behavior.

<sup>10</sup> **Filter storage:** Closed-source apps do not publish enough implementation detail to compare storage formats precisely.

<sup>11</sup> **Element zapper / picker:** A UI for selecting page elements and hiding them. uBOL's picker is mainly for cosmetic filters, while wBlock and AdGuard expose broader element-blocking tools.

<sup>12</sup> **Dynamic filtering:** Classic uBO-style dynamic request filtering is not available through Safari's static content blocker API. wBlock approximates part of the workflow with per-site disable rules, fast rebuilds, and scripts. AdGuard's Safari apps have custom rules and element blocking, but they are not uBO's dynamic filtering matrix.

<sup>13</sup> **Script injection:** Static content blockers cannot do everything. Web extensions or app extensions inject scripts for cosmetic fixes, anti-adblock handling, and site-specific behavior.

<sup>14</sup> **Userscripts:** Greasemonkey/Tampermonkey-style user JavaScript. wBlock supports this directly, although compatibility is still growing.

<sup>15</sup> **AdGuard userscripts:** The paid standalone AdGuard for Mac app supports userscripts. AdGuard Mini and AdGuard for iOS do not advertise general userscript installation.

<sup>16</sup> **AdBlock Tester:** I removed the old hard-coded score row because those sites mostly measure enabled filter lists, not blocker quality. The result can change with one list update and should not be treated as a serious benchmark.

<sup>17</sup> **Language support:** Wipr's App Store page lists enhanced blocklists for 30+ languages. AdGuard has a large regional filter catalog and broad app localization. uBOL and wBlock both support regional filter coverage, but they expose it differently.

<sup>18</sup> **License:** GitHub reports GPL-3.0 for wBlock, uBOL, and AdGuard for iOS. Wipr is closed source. AdGuard Mini is source-available/open on GitHub, but GitHub reports a nonstandard license.

<sup>19</sup> **Implementation language:** GitHub language stats can be misleading because bundled JavaScript rules and generated resources count heavily. The table describes the practical app architecture rather than raw repository percentages.

<sup>20</sup> **AdGuard iOS:** AdGuard for iOS is a separate app with Safari content blockers, a Safari Web Extension, DNS protection, user rules, an allowlist, and custom filters.

---

# How wBlock approximates dynamic filtering in Safari

Safari's content blocker API starts from compiled static rules. wBlock cannot inspect each request at runtime and make request-by-request decisions the way classic uBlock Origin can. The workaround is to use the parts of Safari that are dynamic enough: exception rules, quick rebuilds, and page scripts.

## 1. Per-site disable with `ignore-previous-rules`

When blocking is disabled for a site, wBlock adds an `ignore-previous-rules` entry for that domain:

```json
{
  "action": {"type": "ignore-previous-rules"},
  "trigger": {
    "url-filter": ".",
    "if-domain": ["site.com", ".site.com"]
  }
}
```

Safari treats this as an instruction to ignore earlier blocking rules for the matching domain. It is not as granular as uBO's dynamic matrix, but it gives Safari users a real domain-level off switch without keeping a live request interceptor running.

## 2. Fast content blocker rebuilds

wBlock stores filter data in a format that can be read, changed, and written without turning every update into a full app-sized rebuild. When a change only affects a category or a site exception, the app can limit the work to the relevant targets. Safari still has to reload the compiled rule sets before the new behavior applies; that part is unavoidable.

## 3. Scripts for page-level behavior

Some annoyances are better handled after the page loads. Cosmetic filtering, scriptlets, userscripts, the element zapper, and some YouTube fixes run through scripts because static network rules cannot select arbitrary DOM nodes or patch page JavaScript behavior.

## 4. Category-based rule management

wBlock tracks pending changes by category and target extension. That bookkeeping lets the app avoid rebuilding unrelated blockers when a small setting changes. It also makes the UI's rule counts more useful because the user can see which part of the rule set actually changed.

## Limits

This is still Safari. Content blocker rules must be compiled and reloaded before they apply, and no Safari app can recreate classic uBO's request-by-request dynamic filtering through the content blocker API alone.
