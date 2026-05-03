# Safari ad blocker comparison

_Last reviewed: May 3, 2026._

Safari ad blocking is a strange little world. On Chrome and Firefox, the usual comparison starts with uBlock Origin and works outward from there. On Safari, everything is filtered through Apple's extension APIs, App Store rules, content blocker limits, and the fact that iPhone and iPad support matter just as much as the Mac. This guide compares four blockers that are relevant in that ecosystem today: wBlock, uBlock Origin Lite, Wipr 2, and AdGuard Mini.

If you only want the checklist, jump to the [feature comparison](#feature-comparison). The sections before it explain the tradeoffs, because the table alone makes these apps look more interchangeable than they actually are.

## wBlock

wBlock is my take on what a Safari ad blocker should feel like: native, fast, transparent, and still flexible enough for people who want to bring their own lists or scripts. Setup follows the usual Safari routine. You install the app, enable the bundled Safari extensions, complete onboarding, and apply your selected filters. Once that is done, the app feels more like a native system utility than a ported browser extension.

The macOS, iOS, and iPadOS app is built with SwiftUI, while blocking is handled through Apple's Content Blocker Extensions. That distinction matters. Static network rules are compiled and handed to Safari, so the browser can enforce them without keeping a JavaScript filtering engine alive on every page. wBlock currently spreads rules across five content blocker slots per platform, giving it a total capacity of 750,000 Safari rules. Filter data is stored with Protocol Buffers and LZ4 compression, which keeps load and save operations manageable even when the enabled lists get large.

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/apply_changes_dark.png" width="700" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/apply_changes_light.png" width="700" />
    <img src="docs/media/img/apply_changes_light.png" alt="Apply Changes Screenshot" width="700" />
  </picture>
</div>

The app is also unusually explicit about what it is doing. When you apply changes, you can see source rule counts, converted Safari rule counts, conversion time, reload time, and which filter categories are affected. That may sound like developer trivia, but Safari's 150,000-rule-per-content-blocker limit is a real operational constraint. If a blocker silently overfills a rule slot, some rules may not apply. wBlock tries to make that visible instead of treating the conversion step as a black box.

wBlock Scripts covers the parts of ad blocking that static rules cannot handle well: cosmetic filtering, scriptlets, userscripts, and the element zapper. The zapper works across macOS, iOS, iPadOS, and visionOS. It tracks scroll position and lets you move between parent and child elements, so you can hide the right container instead of playing whack-a-mole with individual nodes.

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/zapper_dark.png" width="350" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/zapper_light.png" width="350" />
    <img src="docs/media/img/zapper_light.png" alt="Element Zapper" width="350" />
  </picture>
</div>

The userscript engine is probably the most unusual part of wBlock. Safari does not have the same userscript ecosystem that Chrome and Firefox users get through Tampermonkey, Violentmonkey, or Greasemonkey, so wBlock includes its own compatibility layer. It supports storage, resources, menu commands, GM XHR, and the common legacy and modern GM API shapes. It is not a perfect Tampermonkey replacement, and some large scripts still expose compatibility gaps, but it gives Safari users an option that otherwise mostly does not exist.

Current quality-of-life features include iCloud sync for filter selections, custom lists, userscripts, and whitelist; configurable auto-updates from hourly to weekly; HTTP conditional requests for efficient filter downloads; preprocessing for AdGuard `!#include` directives; custom filter title detection; Homebrew distribution on macOS; and a macOS blocked-request logger. The result is a blocker that can be simple if you leave it alone, but does not hide the machinery when you want to inspect or change it.

The caveat is that wBlock is still a small project. That is part of why it moves quickly, but it also means some advanced features, especially userscript compatibility, are still being hardened in public. If you want the calmest possible install-and-forget blocker, Wipr 2 is easier to recommend. If you want a native Safari blocker with custom lists, userscripts, diagnostics, and a real app around it, wBlock is the one I would choose.

Sources: [wBlock GitHub](https://github.com/0xCUB3/wBlock), [wBlock App Store](https://apps.apple.com/us/app/wblock/id6746388723)

---

## uBlock Origin Lite

uBlock Origin Lite, often shortened to uBOL, is easy to misunderstand because of the name. It is not classic uBlock Origin with a smaller interface. It is a separate Manifest V3 blocker built around declarative rules. The browser enforces those rules directly, which means uBOL does not need a permanent background process for normal blocking. That is good for reliability and overhead, but it also means many classic uBO features cannot be carried over cleanly.

On Safari, uBOL is now available through the App Store for iPhone, iPad, Mac, and Vision Pro. Apple's listing notes that after extension updates, Safari needs time to convert the updated DNR rulesets into native content blocking rules. In practice, that explains the shape of the product: once the rules are loaded, filtering is efficient and mostly invisible, but filter updates arrive with extension updates rather than through a user-triggered filter refresh.

<div align="center">
  <img src="docs/media/img/adblock_comparison/ublock_origin_lite.png" alt="uBlock Origin Lite Screenshot" width="700" />
</div>

The popup keeps the control model approachable. Instead of presenting uBO's full dynamic filtering matrix, uBOL offers filtering modes such as basic, optimal, and complete, plus an options page where additional rulesets can be enabled. The default ruleset tracks uBlock Origin's default filter set: uBO's built-in lists, EasyList, EasyPrivacy, and Peter Lowe's ad and tracking server list.

The limits show up once you expect it to behave like full uBO. uBOL does not provide uBO's dynamic filtering, dynamic URL filtering, per-site no-scripting switch, or normal custom filter list workflow. Newer versions do include a custom filters pane, mostly for cosmetic filters created through the element picker path, but that is still not the same thing as maintaining arbitrary network filters and custom lists. uBOL's own FAQ is clear about the tradeoff: the declarative model is deliberate, and the missing features are not just UI omissions.

For many users, that tradeoff is acceptable. uBOL is free, open source, actively maintained, and Apple's App Store page says the developer does not collect data. If you used uBlock Origin as a set-and-forget blocker and rarely touched advanced settings, uBOL is probably the closest Safari-friendly descendant. If you used uBO as a power tool, especially for dynamic filtering, uBOL will feel constrained.

Sources: [uBOL GitHub](https://github.com/uBlockOrigin/uBOL-home), [uBOL FAQ](https://github.com/uBlockOrigin/uBOL-home/wiki/Frequently-asked-questions-(FAQ)), [uBOL App Store](https://apps.apple.com/us/app/ublock-origin-lite/id6745342698)

---

## Wipr 2

Wipr 2 is the quiet, polished option. It is paid, native, and intentionally light on knobs. The setup is simple: enable the four Wipr blocklist extensions and Wipr Extra in Safari, then let the app do its work. You do not manage filter subscriptions, edit rules, inspect logs, or tune blocking categories. That is the point.

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/adblock_comparison/wipr_2_dark.png" width="700" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/adblock_comparison/wipr_2_light.png" width="700" />
    <img src="docs/media/img/adblock_comparison/wipr_2_light.png" alt="Wipr 2 Screenshot" width="700" />
  </picture>
</div>

The App Store description says Wipr blocks ads, popups, trackers, cookie warnings, and other web annoyances. Its blocklist updates twice a week automatically, and the app includes enhanced blocklists for a long list of languages. Those language-specific variants are selected from the device's preferred languages, so most users do not need to think about regional filters at all. Wipr 2 is also a universal purchase across iPhone, iPad, Mac, and Vision Pro, with optional tips as in-app purchases.

Wipr's help page gives a useful look at the architecture. The main blocklists use Safari's Content Blocking Extensions API, while Wipr Extra uses the Safari Web Extensions API for cases static rules cannot handle well. Extra is optional because it needs broader website access. Kaylee, the developer, is refreshingly direct about that privacy tradeoff: if you want the stronger blocking, enable Extra; if you want the narrowest possible access, leave it off.

The limitation is customization. Wipr does not offer custom filter lists, a rule editor, block statistics, a visible request logger, or an element zapper. The app is designed around trust: trust the developer, trust the update schedule, and trust that the defaults are good enough. For some people, that is exactly what ad blocking should be. For others, it will feel like driving a car with the hood welded shut.

At $4.99, Wipr 2 is easy to recommend to someone who wants Safari cleaned up with almost no maintenance. It is much harder to recommend to someone who wants to debug breakage, write rules, or install userscripts. In this comparison, Wipr is the least flexible blocker, but also the least fussy.

Sources: [Wipr 2 App Store](https://apps.apple.com/us/app/wipr-2/id1662217862), [Wipr Help](https://kaylees.site/wipr-help.html)

---

## AdGuard Mini

AdGuard Mini is the renamed and rebuilt AdGuard for Safari. It is macOS-only, and that is an important distinction: AdGuard's iPhone and iPad blocker is a separate product, while the full AdGuard for Mac app is the system-wide option. Mini is focused on Safari, not on filtering every app on the machine.

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/adblock_comparison/adguard_mini_dark.png" width="700" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/adblock_comparison/adguard_mini_light.png" width="700" />
    <img src="docs/media/img/adblock_comparison/adguard_mini_light.png" alt="AdGuard Mini Screenshot" width="700" />
  </picture>
</div>

AdGuard Mini uses Safari's Content Blocking API and splits rules across six content blockers: General, Privacy, Social, Security, Other, and Custom. AdGuard's own knowledge base lists the combined capacity as 900,000 filtering rules, with the familiar Safari limit of 150,000 rules per content-blocking extension. That gives Mini more static-rule headroom than wBlock's current five-slot layout, though real-world coverage still depends on which filters are enabled and how rules are distributed.

The app sits on the opposite end of the spectrum from Wipr. It exposes filter categories, custom filters, user rules, element blocking, issue reporting, and an advanced rule editor. The App Store page lists English plus 33 other app languages, and AdGuard's filter ecosystem remains one of the strongest reasons to use it. If you already know AdGuard syntax or rely on AdGuard-maintained regional filters, Mini will feel familiar.

The Pro model is the main thing to understand before installing it. Core Safari blocking is free. Advanced features require an AdGuard license or in-app purchase, including real-time filter updates, AdGuard Extra for anti-adblock and difficult ads, and advanced custom filters. At the time of writing, version 2.1.4 is current on the App Store, while 2.2.0 is available as a beta on GitHub.

AdGuard Mini is the best fit here for macOS users who want a mature filter ecosystem, a detailed app, and built-in tools for writing or managing rules. It is less compelling if you need the same product on iPhone and iPad, or if you dislike having advanced ad-blocking features split behind a Pro license. It also competes with AdGuard's own full Mac app, which is more powerful because it is not limited to Safari.

Sources: [AdGuard Mini](https://adguard.com/en/adguard-mini-mac/overview.html), [AdGuard Mini App Store](https://apps.apple.com/pl/app/adguard-mini/id1440147259?mt=12), [AdGuard Mini GitHub](https://github.com/AdguardTeam/AdGuardMiniForMac), [AdGuard rule limit KB](https://adguard.com/kb/adguard-mini-for-mac/solving-problems/rule-limit/)

---

# Feature comparison

| **Feature** | **wBlock**<sup>1</sup> | **uBlock Origin Lite**<sup>2</sup> | **Wipr 2**<sup>3</sup> | **AdGuard Mini**<sup>4</sup> |
|:--|:--:|:--:|:--:|:--:|
| macOS support | ✅ | ✅ | ✅ | ✅ |
| iOS / iPadOS support | ✅ | ✅ | ✅ | ❌<sup>20</sup> |
| visionOS support | ✅ extension pieces | ✅ | ✅ | ❌ |
| RAM usage measured locally | ~40 MB<sup>6</sup> | ~120 MB<sup>6</sup> | ~50 MB<sup>6</sup> | ~100 MB<sup>6</sup> |
| Static rule capacity | 750,000<sup>7</sup> | DNR-based, browser-dependent<sup>7</sup> | 4 blocklist extensions, capacity not published<sup>7</sup> | 900,000<sup>7</sup> |
| GitHub stars | ~2.5k | ~3.3k for uBOL | N/A | ~1.2k |
| Open source | ✅ | ✅ | ❌ | ✅ |
| License | GPL-3.0 | GPL-3.0 | Proprietary | Other / AdGuard source license |
| Main implementation | Swift + JS | JavaScript | Swift | Swift + web UI |
| Extension architecture | Content Blocker + Web Extension | MV3 declarative extension | Content Blocker + Web Extension | Content Blocker + Web Extension |
| Filter storage | Protocol Buffers + LZ4 | Packaged DNR rulesets + extension storage | Closed source | App storage + JSON/rules files |
| Element zapper / picker | ✅ | ✅ for cosmetic filters | ❌ | ✅ |
| Custom filter lists | ✅ | ❌ full lists; limited cosmetic custom filters | ❌ | ✅ |
| User rule editor | ✅ | Limited | ❌ | ✅ |
| Dynamic filtering | Limited Safari workaround<sup>12</sup> | ❌ | ❌ | Limited, not uBO-style<sup>12</sup> |
| YouTube ad blocking | ✅ | ✅ / varies by site changes | ✅ via Wipr Extra | ✅, stronger with Pro Extra |
| Script injection / scriptlets | ✅ | Declarative scriptlets | Wipr Extra only | ✅ |
| Userscript support | ✅ | ❌ | ❌ | ❌ in Mini<sup>15</sup> |
| Filter updates | Automatic, 1h to 7d configurable | Extension updates only | Automatic, twice weekly | Automatic; real-time updates require Pro |
| Multi-device sync | ✅ iCloud | ❌ | ❌ settings sync, universal purchase | ❌ |
| Per-site disable | ✅ | ✅ | ✅ through Safari/Wipr Extra controls | ✅ |
| Whitelist / allowlist | ✅ | ✅ | ✅ | ✅ |
| Logging / debugging | ✅ macOS logger | ❌ | ❌ | ✅ |
| Regional / language filters | ✅, plus manual lists | ✅ rulesets | ✅ 30+ language variants | ✅ 34 app languages and many filters |
| Interface style | Native, detailed | Popup + web options | Native, minimal | Detailed macOS app |
| Cost | Free | Free | $4.99 one-time, optional tips | Free, Pro subscription / license |
| Best fit | Safari power users | Set-and-forget uBO users | People who want no knobs | macOS users who want mature AdGuard tools |

---

## Notes

<sup>1</sup> **wBlock:** Safari-focused, open source, and native to Apple platforms. Current public docs list 750,000 rule capacity, Protocol Buffer storage, LZ4 compression, iCloud sync, custom lists, element zapper, and userscripts.

<sup>2</sup> **uBlock Origin Lite:** MV3 version of uBlock Origin. It is designed to be declarative and low-overhead. It is not a drop-in replacement for classic uBO.

<sup>3</sup> **Wipr 2:** Paid, closed-source Safari blocker by Kaylee Calderolla. It uses Safari content blockers plus Wipr Extra for harder cases.

<sup>4</sup> **AdGuard Mini:** Formerly AdGuard for Safari. It is macOS-only and separate from AdGuard for iOS and the full AdGuard for Mac app.

<sup>5</sup> **wBlock App Store:** https://apps.apple.com/app/wblock/id6746388723

<sup>6</sup> **RAM usage:** These are local spot checks on a 2023 M2 Pro MacBook Pro with a small tab set and only one blocker active. Treat them as rough numbers, not benchmarks. Browser version, enabled filters, tabs, and websites can move the numbers a lot.

<sup>7</sup> **Rule capacity:** Safari content blocker extensions are capped at about 150,000 rules each. wBlock ships five content blocker slots, for 750,000 total. AdGuard says Mini has six content blockers, for 900,000 total. Wipr documents four blocklist extensions but does not publish a single total rule count. uBOL uses packaged declarative rulesets; its FAQ says rules are compiled into declarative rulesets and scripts when the extension package is built.

<sup>8</sup> **Content Blocker Extension:** Apple's native declarative filtering API. It is fast and private, but less flexible than a live request-filtering engine.

<sup>9</sup> **Manifest V3:** Chrome's newer extension model. uBOL is built around MV3's declarativeNetRequest API. Safari can run WebExtensions, but Safari still has its own conversion and extension rules.

<sup>10</sup> **Filter storage:** Closed-source apps do not publish enough implementation detail to compare storage formats precisely.

<sup>11</sup> **Element zapper / picker:** A UI for selecting page elements and hiding them. The exact behavior differs by app. uBOL's picker is mainly for cosmetic filters; wBlock and AdGuard expose broader element blocking tools.

<sup>12</sup> **Dynamic filtering:** Classic uBO-style dynamic request filtering is not available through Safari's static content blocker API. wBlock approximates some dynamic behavior through per-site disable rules, fast rebuilds, and scripts. AdGuard Mini has custom rules and element blocking, but it is not uBO's dynamic filtering matrix.

<sup>13</sup> **Script injection:** Static content blockers cannot do everything. Web extensions or app extensions can inject scripts for cosmetic fixes, anti-adblock handling, or site-specific behavior.

<sup>14</sup> **Userscripts:** Greasemonkey/Tampermonkey-style user JavaScript. wBlock supports this directly. The compatibility layer is still growing.

<sup>15</sup> **AdGuard userscripts:** The paid standalone AdGuard for Mac app supports userscripts. AdGuard Mini does not advertise general userscript installation.

<sup>16</sup> **AdBlock Tester:** I removed the old hard-coded score row because those sites mostly measure enabled filter lists, not blocker quality. The result can change with one list update and should not be treated as a serious benchmark.

<sup>17</sup> **Language support:** Wipr's App Store page lists enhanced blocklists for 30+ languages. AdGuard Mini's App Store page lists English plus 33 more app languages. uBOL and wBlock both support regional filter coverage, but the UI/localization story differs.

<sup>18</sup> **License:** GitHub reports GPL-3.0 for wBlock and uBOL. Wipr is closed source. AdGuard Mini is source-available/open on GitHub, but GitHub reports a nonstandard license.

<sup>19</sup> **Implementation language:** GitHub language stats can be misleading because bundled JavaScript rules and generated resources count heavily. The table describes the practical app architecture rather than raw repository percentages.

<sup>20</sup> **AdGuard Mini iOS:** AdGuard Mini is only for macOS. For iPhone and iPad, AdGuard offers [AdGuard for iOS](https://adguard.com/en/adguard-ios/overview.html).

---

# How wBlock approximates dynamic filtering in Safari

Safari's content blocker API is built around compiled static rules. That makes it fast and private, but it also means wBlock cannot inspect every request in real time and decide what to do the way classic uBlock Origin can. Instead, wBlock combines a few Safari-compatible techniques that cover the common cases without pretending the browser exposes an API it does not.

## 1. Per-site disable with `ignore-previous-rules`

When you disable blocking for a site, wBlock adds an `ignore-previous-rules` entry for that domain:

```json
{
  "action": {"type": "ignore-previous-rules"},
  "trigger": {
    "url-filter": ".",
    "if-domain": ["site.com", ".site.com"]
  }
}
```

Safari interprets that as an instruction to ignore earlier blocking rules for the matching domain. It is not the same as a live request filter, but for per-site disable it gets close to the user experience people expect.

## 2. Fast content blocker rebuilds

wBlock stores filters in a format that can be read, changed, and rebuilt quickly. When a change only affects one category or site-specific override, the app tries to avoid rebuilding every target from scratch. That matters because Safari still has to reload compiled rule sets before changes take effect.

## 3. Scripts for page-level behavior

Some annoyances are better handled after the page exists. The element zapper, some cosmetic fixes, and certain YouTube-related workarounds happen through scripts rather than through Safari's static network rules. This is also where userscripts and scriptlets fit into the design.

## 4. Category-based rule management

wBlock tracks pending changes by category and target extension. That bookkeeping is not glamorous, but it keeps common operations from turning into full rebuilds when only a smaller slice of the rules changed.

## Limits

This is still bounded by Safari. Content blocker rules have to be compiled and reloaded before they apply, and no amount of clever storage changes that. wBlock can make common adjustments feel quick, especially per-site controls and targeted rebuilds, but it cannot offer true uBO-style request-by-request dynamic filtering inside Safari's native content blocker model.
