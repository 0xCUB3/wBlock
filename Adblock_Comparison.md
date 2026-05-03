# Safari ad blocker comparison

_Last reviewed: May 3, 2026._

This is a practical comparison of four Safari blockers I have used or tested against current public docs: wBlock, uBlock Origin Lite, Wipr 2, and AdGuard Mini. If you only want the checklist, jump to the [feature comparison](#feature-comparison).

## wBlock

wBlock is my take on what a Safari ad blocker should feel like: native, fast, and still useful if you want to tinker. Setup is the usual Safari dance. Install the app, enable the bundled Safari extensions, run onboarding, and apply filters.

The app is SwiftUI on macOS, iOS, and iPadOS. Blocking uses Apple's Content Blocker Extensions, so Safari handles the static rules out of process instead of keeping a JavaScript blocker awake on every page. The current design spreads rules across five content blocker slots per platform, for a total capacity of 750,000 Safari rules. Filter storage uses Protocol Buffers with LZ4 compression, which keeps the app responsive even with large lists.

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/apply_changes_dark.png" width="700" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/apply_changes_light.png" width="700" />
    <img src="docs/media/img/apply_changes_light.png" alt="Apply Changes Screenshot" width="700" />
  </picture>
</div>

The main screen shows enabled filter lists, rule counts, conversion results, and reload timing. That matters because Safari's rule limit is not theoretical. If a blocker silently drops rules, you will eventually notice weird misses. wBlock tries to show what happened instead of hiding it.

wBlock Scripts adds the pieces static rules cannot cover: cosmetic filtering, scriptlets, userscripts, and the element zapper. The zapper works across macOS, iOS, iPadOS, and visionOS. It supports scroll tracking and parent/child navigation, so you can walk up from a bad element to its container without writing a rule by hand.

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/zapper_dark.png" width="350" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/zapper_light.png" width="350" />
    <img src="docs/media/img/zapper_light.png" alt="Element Zapper" width="350" />
  </picture>
</div>

The userscript engine is the unusual part for Safari. wBlock can install and run userscripts with a growing Greasemonkey compatibility layer, including storage, resources, menu commands, and GM XHR support. It is not a full Tampermonkey clone yet, but it is enough for many Safari use cases where there otherwise is no good option.

Other current features include iCloud sync for filter selections, custom lists, userscripts, and whitelist; configurable auto-updates from hourly to weekly; HTTP conditional requests for filter downloads; AdGuard `!#include` preprocessing; custom filter title detection; Homebrew distribution for macOS; and a macOS blocked-request logger.

wBlock is still a small project. That has upsides and downsides. Features move quickly, but regressions are possible, especially around userscript compatibility. If you want a simple install-and-forget blocker, Wipr may be calmer. If you want a native Safari blocker with custom lists, userscripts, and visible internals, wBlock is the one I would pick.

Sources: [wBlock GitHub](https://github.com/0xCUB3/wBlock), [wBlock App Store](https://apps.apple.com/us/app/wblock/id6746388723)

---

## uBlock Origin Lite

uBlock Origin Lite, often shortened to uBOL, is not regular uBlock Origin with a lighter UI. It is a separate Manifest V3 blocker built around declarative rules. The upside is low overhead: the browser enforces the rules, and the extension does not need a permanent background process for normal blocking. The downside is that many classic uBlock Origin features do not map cleanly to MV3.

On Safari, uBOL is now available from the App Store for iPhone, iPad, Mac, and Vision Pro. Apple's listing says Safari converts updated DNR rulesets into its native content blocking rules after extension updates. That explains both the good and the annoying parts: filtering is efficient once loaded, but filter lists update when the extension package updates, not whenever the user hits an update button.

<div align="center">
  <img src="docs/media/img/adblock_comparison/ublock_origin_lite.png" alt="uBlock Origin Lite Screenshot" width="700" />
</div>

The popup is simple. You choose a filtering mode such as basic, optimal, or complete, and the options page lets you enable more rulesets. The default ruleset tracks uBlock Origin's default filter set: uBO built-ins, EasyList, EasyPrivacy, and Peter Lowe's list.

Power-user features are still the tradeoff. uBOL does not have uBO's dynamic filtering, dynamic URL filtering, no-scripting switch, or the full custom-list workflow. Newer builds do have a custom filters pane, mostly for cosmetic filters created through the element picker flow, but it is not the same as maintaining arbitrary network filter lists in uBO.

For a lot of people, that is fine. uBOL is free, open source, actively maintained, and has a good privacy posture: Apple's App Store page says the developer does not collect data. If you used uBO as a set-and-forget blocker and do not need advanced controls, uBOL is a reasonable Safari option. If you rely on dynamic filtering or custom lists, it will feel boxed in.

Sources: [uBOL GitHub](https://github.com/uBlockOrigin/uBOL-home), [uBOL FAQ](https://github.com/uBlockOrigin/uBOL-home/wiki/Frequently-asked-questions-(FAQ)), [uBOL App Store](https://apps.apple.com/us/app/ublock-origin-lite/id6745342698)

---

## Wipr 2

Wipr 2 is the quiet option. It is paid, native, and designed so most users never open it after setup. Enable the four Wipr blocklist extensions and Wipr Extra in Safari, then let it run.

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/adblock_comparison/wipr_2_dark.png" width="700" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/adblock_comparison/wipr_2_light.png" width="700" />
    <img src="docs/media/img/adblock_comparison/wipr_2_light.png" alt="Wipr 2 Screenshot" width="700" />
  </picture>
</div>

The App Store page says Wipr blocks ads, popups, trackers, cookie warnings, and other annoyances. It also says its blocklist updates twice a week automatically. The app is universal across iPhone, iPad, Mac, and Vision Pro with a single purchase. It supports a long list of language-specific blocklists, selected from the device's preferred languages.

Wipr's help page confirms the architecture: all versions use Safari's Content Blocking Extensions API, while Wipr Extra uses the Safari Web Extensions API for cases where static rules are not enough. Extra is optional because it needs broader page access. Kaylee, the developer, is blunt about that tradeoff, which I appreciate.

Wipr is not for people who want knobs. There are no custom filter lists, no rule editor, no visible request logger, and no element zapper. The app also avoids block statistics by design. That is either refreshing or frustrating, depending on how you use blockers.

At $4.99 with optional tips, Wipr 2 is easy to recommend to someone who wants Safari cleaned up with as little maintenance as possible. I would not recommend it to someone who wants to debug filters or install userscripts.

Sources: [Wipr 2 App Store](https://apps.apple.com/us/app/wipr-2/id1662217862), [Wipr Help](https://kaylees.site/wipr-help.html)

---

## AdGuard Mini

AdGuard Mini is the renamed and rebuilt AdGuard for Safari. It is macOS-only; AdGuard's iOS blocker is a separate app. Mini protects Safari, not the whole Mac. If you want system-wide filtering, AdGuard points users to the full AdGuard for Mac app.

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/adblock_comparison/adguard_mini_dark.png" width="700" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/adblock_comparison/adguard_mini_light.png" width="700" />
    <img src="docs/media/img/adblock_comparison/adguard_mini_light.png" alt="AdGuard Mini Screenshot" width="700" />
  </picture>
</div>

AdGuard Mini uses Safari's Content Blocking API and splits rules across six content blockers: General, Privacy, Social, Security, Other, and Custom. AdGuard's own knowledge base lists the total capacity as 900,000 Safari rules, with the usual 150,000-rule limit per content-blocking extension.

The app has more controls than Wipr and uBOL: filter categories, custom filters, user rules, element blocking, issue reporting, and an advanced rule editor. The App Store page lists English plus 33 other languages, and the AdGuard filter ecosystem is still one of its strengths.

The Pro split is worth noting. Core Safari blocking is free. Pro features require an AdGuard license or in-app purchase and include real-time filter updates, AdGuard Extra for anti-adblock and difficult ads, and advanced custom filters. Version 2.1.4 is current on the App Store at the time of writing, with 2.2.0 in beta on GitHub.

AdGuard Mini is the best fit here if you want a mature filter ecosystem and a lot of UI around filter editing, but only on macOS. It is less appealing if you need one app for iPhone and iPad too, or if you dislike subscriptions around advanced features.

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

Safari's native content blocker API is built for static rules. wBlock cannot inspect every network request and make a live per-request decision the way classic uBlock Origin can. It uses a few Safari-friendly workarounds instead.

## 1. Per-site disable with `ignore-previous-rules`

When you disable blocking for a site, wBlock adds a rule like this:

```json
{
  "action": {"type": "ignore-previous-rules"},
  "trigger": {
    "url-filter": ".",
    "if-domain": ["site.com", ".site.com"]
  }
}
```

Safari then ignores earlier blocking rules for that domain.

## 2. Fast content blocker rebuilds

wBlock stores filter data in a format that can be rebuilt quickly. When possible, it updates only the affected rules instead of forcing a full rebuild of everything.

## 3. Scripts for page-level behavior

For things static rules cannot handle, such as the element zapper or some YouTube fixes, wBlock uses scripts. That is separate from Safari's network blocking layer.

## 4. Category-based rule management

wBlock tracks pending changes by filter category and target extension. This helps avoid unnecessary reloads.

## Limits

This is still not true live request filtering. Safari requires content blocker rules to be compiled and reloaded before they apply. wBlock can make that feel quick in common cases, but Safari sets the boundaries.
