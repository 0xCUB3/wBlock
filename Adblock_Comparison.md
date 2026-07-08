# Safari ad blocker comparison

_Last reviewed: July 8, 2026._

Safari blockers don't work like classic uBlock Origin on Firefox. With Apple's Content Blocking API, an app gives Safari a compiled rule list and Safari applies it inside the browser engine. Privacy improves because Safari doesn't have to ask the app what to do while a page loads.

Anything more hands-on, cosmetic filtering, scriptlets, element picking, YouTube workarounds, per-page controls, ends up in a Safari Web Extension or injected script. This guide compares wBlock, uBlock Origin Lite, Wipr 2, and AdGuard's Safari apps: AdGuard Mini on macOS and AdGuard for iOS on iPhone and iPad.

## Short version

- wBlock is the choice if you want to see what is happening: custom lists, userscripts, userstyles, rule counts, iCloud sync, and debugging tools.
- uBlock Origin Lite is for uBO-style defaults in a declarative MV3 package. It isn't classic uBO, although newer builds now have custom filters and external subscriptions in a constrained way.
- Wipr 2 is the quiet option. Enable its blocklists and Wipr Extra, then leave it alone. Newer Wipr builds also offer Filtr for system-level URL filtering on supported Apple OS versions.
- AdGuard Mini and AdGuard for iOS are the established, configurable choice, especially if you already trust AdGuard's filters or pay for the advanced pieces.

## At a glance

|Area|wBlock|uBlock Origin Lite|Wipr 2|AdGuard Mini / iOS|
|-|-|-|-|-|
|Best fit|Control and visibility|uBO-style defaults|Set and forget|AdGuard ecosystem|
|Cost|Free|Free|Paid one-time, optional tips|Free tier, Pro/license for advanced features|
|Open source|Yes|Yes|No|Yes, license differs by app|
|License|GPL-3.0|GPL-3.0|Proprietary|Mini: AdGuard source license; iOS: GPL-3.0|
|macOS support|Yes|Yes|Yes|Yes via Mini|
|iOS / iPadOS support|Yes|Yes|Yes|Yes via AdGuard for iOS|
|visionOS support|Extension pieces|Yes|Yes|No|
|Static rule capacity|750,000 compiled Safari rules|DNR-based, browser-dependent|4 blocklist extensions, total not published|900,000 Mini; iOS uses six 150k slots|
|Custom filter lists|Yes|Yes, newer support with MV3 constraints|No|Yes|
|Userscripts|Yes|No|No|No in Mini / iOS|
|Element picker|Yes|Cosmetic picker|No|Yes|
|Logging|macOS|No|No|Yes|
|Sync|iCloud for filters and settings|No|Settings only|No|

## wBlock

wBlock is a native Safari blocker for macOS, iOS, and iPadOS. It uses five Safari content blocker extensions per platform, giving it five 150,000-rule slots and a 750,000-rule ceiling when all slots are available. That number is the compiled Safari rule count, not the raw number of filter-list lines. A single AdGuard rule can expand, collapse, or disappear during conversion depending on what Safari can express.

Filter metadata and compiled data use Protocol Buffers and LZ4 compression. Filter lists are big, repetitive, and updated often; the app still needs to feel instant when a user enables a list or imports a custom subscription. Updates use `ETag` and `If-Modified-Since`, so a scheduled refresh can skip the full download when the server says nothing changed.

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/apply_changes_dark.png" width="760" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/apply_changes_light.png" width="760" />
    <img src="docs/media/img/apply_changes_light.png" alt="wBlock apply changes view" width="760" />
  </picture>
</div>

Static blocking only gets wBlock so far. wBlock Scripts handles the pieces Safari content blockers can't express cleanly: cosmetic selectors, scriptlets, userscripts, userstyles, URL tracking-parameter stripping, and the element zapper. The zapper works in Safari extension contexts across macOS, iOS, iPadOS, and visionOS, and lets the user move up and down the DOM selection so the rule can target the real ad container instead of a nested icon or span.

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/zapper_dark.png" width="360" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/zapper_light.png" width="360" />
    <img src="docs/media/img/zapper_light.png" alt="wBlock element zapper" width="360" />
  </picture>
</div>

Userscripts are where wBlock stretches the furthest. Safari doesn't have the userscript extension ecosystem Chromium and Firefox users are used to, so wBlock ships its own Greasemonkey-style layer. The current implementation covers storage, resources, menu commands, GM XHR, and both legacy `GM_*` and modern `GM.*` forms for common APIs. Safari users can run scripts that would otherwise need a separate userscript manager. Scripts that depend on obscure Tampermonkey behavior may still need fixes.

The debugging view is deliberately detailed. It reports source rule counts, converted Safari rule counts, conversion time, reload time, and the categories touched by a change. Per-site disabling uses Safari-compatible exception rules and targeted rebuilds instead of live request interception, because Safari doesn't allow live interception through the content blocker API.

Pick wBlock if you want custom subscriptions, userscripts, conversion output, per-site settings, iCloud sync, and debugging tools in one Safari-native app. The rough edge is compatibility: basic blocking is straightforward, but userscripts have a long tail.

Sources: [wBlock GitHub](https://github.com/0xCUB3/wBlock), [wBlock App Store](https://apps.apple.com/us/app/wblock/id6746388723), [Apple content blocker docs](https://developer.apple.com/documentation/safariservices/creating-a-content-blocker)

## uBlock Origin Lite

uBlock Origin Lite isn't classic uBlock Origin with a smaller UI. It's a separate Manifest V3 project built around declarative filtering. In Chrome that means `declarativeNetRequest`; in Safari's App Store build, Apple still has its own extension packaging and conversion path. Either way, rules are prepared ahead of time and enforced by the browser instead of by a persistent request-filtering background page.

The uBOL README describes it as an MV3 content blocker that operates entirely declaratively. The browser handles network filtering and CSS/JS injection, so uBOL doesn't need a permanent filtering process. Its default ruleset includes uBlock Origin's built-in lists, EasyList, EasyPrivacy, and Peter Lowe's ad and tracking server list, and the options page exposes additional rulesets.

<div align="center">
  <img src="docs/media/img/adblock_comparison/ublock_origin_lite.png" alt="uBlock Origin Lite screenshot" width="760" />
</div>

The appeal is simple: low background overhead, a lot of inherited filter knowledge from uBlock Origin, and App Store builds for iPhone, iPad, Mac, and Vision Pro. The popup's basic, optimal, and complete modes are presets for how much filtering the extension is allowed to do on the current site.

Classic uBO's power comes from decisions the extension can make at runtime. MV3 moves much of that decision-making into the browser. The uBOL FAQ lists several features that don't map cleanly to MV3/DNR, including dynamic filtering, dynamic URL filtering, response-body replacement, some `removeparam` cases, and many regex-heavy rules. It also notes that generic cosmetic filtering isn't enabled by default; Complete mode is needed for that.

A 2026 FAQ edit changes the old answer on customization: custom filters and external filter subscriptions are now available in a way meant to respect uBOL's declarative design. It still doesn't make uBOL classic uBO. It's a low-maintenance declarative blocker, not a full runtime filtering workbench.

Sources: [uBOL GitHub](https://github.com/uBlockOrigin/uBOL-home), [uBOL README](https://github.com/uBlockOrigin/uBOL-home/blob/main/README.md), [uBOL FAQ](https://github.com/uBlockOrigin/uBOL-home/wiki/Frequently-asked-questions-(FAQ)), [uBOL App Store](https://apps.apple.com/us/app/ublock-origin-lite/id6745342698)

## Wipr 2

Wipr 2 is almost the opposite of wBlock. It's a paid native Safari blocker with very few knobs. You enable the four Wipr blocklist extensions and Wipr Extra, then mostly leave the app alone. There is no public custom filter workflow, no user rule editor, no element picker, no request log, and no visible rule-conversion report.

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/adblock_comparison/wipr_2_dark.png" width="760" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/adblock_comparison/wipr_2_light.png" width="760" />
    <img src="docs/media/img/adblock_comparison/wipr_2_light.png" alt="Wipr 2 screenshot" width="760" />
  </picture>
</div>

Wipr is still Safari-native. The main Wipr blocklists use Safari content blockers, while Wipr Extra is a Safari Web Extension for cases where static rules are not enough, such as YouTube ads, extra cookie-warning handling, and some anti-adblock behavior. Extra asks for broader website access because it has to see and modify page content. Static blockers are narrow and private; web extensions can do more, but they need more trust.

Regional support is automatic. Instead of asking the user to pick filter subscriptions, Wipr selects enhanced blocklists based on the device's preferred languages. Updates run automatically, but the help page warns iOS/iPadOS users not to force-quit the app because that can prevent refreshes until Wipr is opened again.

Wipr's help now documents Filtr, a separate in-app purchase that uses Apple's newer URL Filters API on iOS/macOS 26. Filtr isn't a VPN and isn't DNS blocking; it blocks at the URL level system-wide without routing traffic through a third-party server. Useful, but separate from Wipr's Safari blocker story and limited to newer OS versions.

Pick Wipr if you don't want to manage a blocker. The drawback: there is nowhere to go when you want to inspect a false positive, add a niche filter list, or debug a site-specific miss yourself. Wipr's own feature-request answer says custom filters and block-page-elements are not planned because the product intentionally has no configuration.

Sources: [Wipr 2 App Store](https://apps.apple.com/us/app/wipr-2/id1662217862), [Wipr Help](https://kaylees.site/wipr-help.html)

## AdGuard Mini and AdGuard for iOS

AdGuard's Safari apps are split across products. AdGuard Mini is the macOS Safari app formerly called AdGuard for Safari. AdGuard for iOS is the iPhone and iPad app. The full AdGuard for Mac app is a different product: system-wide, paid, and outside this comparison.

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/adblock_comparison/adguard_mini_dark.png" width="760" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/adblock_comparison/adguard_mini_light.png" width="760" />
    <img src="docs/media/img/adblock_comparison/adguard_mini_light.png" alt="AdGuard Mini screenshot" width="760" />
  </picture>
</div>

Mini uses six Safari content blockers: General, Privacy, Social, Security, Other, and Custom. With Safari's 150,000-rule limit per content blocker, Mini has a published ceiling of 900,000 compiled rules. It's more configurable than Wipr and more traditional than uBOL: filter categories, custom filters, user rules, element blocking, issue reporting, and an advanced rule editor. The free version covers basic Safari blocking. Pro unlocks real-time filter updates, AdGuard Extra for harder anti-adblock and ad cases, and a few other advanced filtering features.

AdGuard for iOS follows the same shape, adapted to iPhone and iPad. It has six content blockers named General, Privacy, Social, Security, Custom, and Other. Safari protection includes filter groups, user rules, an allowlist, and custom filter URLs. The Safari Web Extension adds the in-browser controls: toggle protection for the current site, manually block an element, report a filtering issue, and apply advanced filtering rules, CSS rules, Extended CSS selectors, and scriptlets when Premium is enabled.

DNS protection is separate from Safari filtering. It can catch domain-level ad and tracking hosts outside Safari, usually through a local VPN-style setup on iOS, but it only sees hostnames. It can't hide page elements or make path-level HTTPS decisions after the connection is established. Safari content blockers handle page filtering, the Web Extension handles advanced page behavior, and DNS filtering catches domain-level hosts across the device.

AdGuard also has both AdGuard and AdGuard Pro in the iOS App Store. They used to differ because App Store rules changed over time; today they are effectively parallel ways to get the same advanced iOS feature set. You don't need to install both.

AdGuard has the deepest filter ecosystem here. Regional coverage is broad, the rule syntax has been around for years, and the reporting flow is solid. The awkward part is the product split, plus the cost of the most advanced features.

Sources: [AdGuard Mini](https://adguard.com/en/adguard-mini-mac/overview.html), [AdGuard Mini App Store](https://apps.apple.com/pl/app/adguard-mini/id1440147259?mt=12), [AdGuard Mini GitHub](https://github.com/AdguardTeam/AdGuardMiniForMac), [AdGuard rule limit KB](https://adguard.com/kb/adguard-mini-for-mac/solving-problems/rule-limit/), [AdGuard for iOS](https://adguard.com/en/adguard-ios/overview.html), [AdGuard for iOS GitHub](https://github.com/AdguardTeam/AdguardForiOS), [AdGuard iOS Safari protection KB](https://adguard.com/kb/adguard-for-ios/features/safari-protection/), [AdGuard iOS Web Extension KB](https://adguard.com/kb/adguard-for-ios/web-extension/), [AdGuard and AdGuard Pro KB](https://adguard.com/kb/adguard-for-ios/adguard-and-adguard-pro/)

## Feature details

### Platform, project, and cost

|Feature|wBlock|uBlock Origin Lite|Wipr 2|AdGuard Mini / iOS|
|-|-|-|-|-|
|macOS support|Yes|Yes|Yes|Yes via Mini|
|iOS / iPadOS support|Yes|Yes|Yes|Yes via AdGuard for iOS|
|visionOS support|Extension pieces|Yes|Yes|No|
|Open source|Yes|Yes|No|Yes, license differs by app|
|License|GPL-3.0|GPL-3.0|Proprietary|Mini: AdGuard source license; iOS: GPL-3.0|
|Main implementation|Swift + JavaScript|JavaScript|Swift|Swift + web UI|
|GitHub stars, checked July 8, 2026|2,645|3,509 for uBOL|N/A|1,176 Mini / 1,678 iOS|
|App Store privacy label|Data Not Collected|Data Not Collected|Data Not Collected|Data Not Collected|
|Cost|Free|Free|Paid one-time purchase, optional tips|Free tier, Pro subscription/license for advanced features|
|Interface style|Native, detailed|Popup + web options|Native, minimal|Detailed AdGuard apps|
|Natural fit|Safari users who want control and visibility|Users who want uBO-style defaults without classic uBO complexity|Users who do not want to configure anything|Users comfortable with AdGuard's filter ecosystem|

### Blocking model

|Feature|wBlock|uBlock Origin Lite|Wipr 2|AdGuard Mini / iOS|
|-|-|-|-|-|
|Static rule capacity|750,000 compiled Safari rules|DNR-based, browser-dependent|4 blocklist extensions, total not published|900,000 Mini; iOS uses six 150k slots|
|Static blocking model|Safari content blockers|Packaged declarative rulesets|Safari content blockers|Safari content blockers|
|Page-level model|Safari Web Extension scripts|Extension content scripts|Wipr Extra Web Extension|Safari Web Extension / AdGuard Extra|
|Script injection / scriptlets|Yes|Limited scriptlet support|Wipr Extra only|Yes|
|CSS injection / cosmetic filtering|Yes|Yes, depends on mode|Yes through blocklists / Extra|Yes|
|YouTube ad blocking|Yes|Yes, changes often|Yes via Wipr Extra|Yes, stronger with Pro Extra|
|Dynamic filtering|Safari-compatible approximation|No classic uBO dynamic filtering|No|Limited, not uBO-style|
|URL tracking-parameter stripping|Yes|Yes via `removeparam` rules|No|Yes via `$removeparam` rules|
|DNS-level blocking|No|No|No|iOS AdGuard has DNS protection; Mini does not|
|System-level URL filtering|No|No|Filtr on iOS/macOS 26 as an IAP|No in Mini; AdGuard's full products differ|

### Control and debugging

|Feature|wBlock|uBlock Origin Lite|Wipr 2|AdGuard Mini / iOS|
|-|-|-|-|-|
|Custom filter lists|Yes|Yes, newer support with declarative constraints|No|Yes|
|User rule editor|Yes|Custom filters, not classic dynamic rules|No|Yes|
|Userscript support|Yes|No|No|No in Mini / iOS|
|Userstyle support|Yes|No|No|No in Mini / iOS|
|Element zapper / picker|Yes|Cosmetic picker|No|Yes|
|Per-site disable|Yes|Yes|Yes through Safari/Wipr controls|Yes|
|Whitelist / allowlist|Yes|Yes|Yes|Yes|
|Logging / debugging|macOS only|No|No|Yes|
|Filter updates|Automatic, 1h to 7d configurable|Bundled rulesets update with extension releases; custom/external support is newer and constrained|Automatic, schedule handled by Wipr|Automatic; real-time updates require Pro|
|Multi-device sync|iCloud|No|Settings only, no custom filter sync|No|
|Regional / language filters|Yes, plus manual lists|Bundled rulesets|Automatic language variants|Broad AdGuard filter catalog|
|Filter storage|Protocol Buffers + LZ4|Packaged DNR rulesets + extension storage|Closed source|App storage + JSON/rules files|
|RAM usage measured locally|~40 MB|~120 MB|~50 MB|~100 MB Mini|

## Notes

### wBlock App Store

wBlock's App Store page is <https://apps.apple.com/app/wblock/id6746388723>.

### RAM usage

These are local spot checks on a 2023 M2 Pro MacBook Pro with a small tab set and only one blocker active. Treat them as rough numbers, not benchmarks. Browser version, enabled filters, tabs, and websites can move the numbers a lot.

### Rule capacity

Safari content blocker extensions are capped at about 150,000 compiled rules each on current Apple platforms. wBlock ships five content blocker slots, for 750,000 total. AdGuard Mini ships six, for 900,000 total. AdGuard for iOS also uses six content blockers on iOS 15 and later. Wipr documents four blocklist extensions but does not publish a single total rule count. uBOL uses packaged declarative rulesets, so its limits depend on the browser's declarative ruleset handling rather than Safari content blocker slots alone.

### Content Blocker Extension

Apple's native declarative filtering API is fast and private because Safari applies compiled rules internally. The tradeoff is that a content blocker cannot behave like a live request-filtering engine.

### Manifest V3

Manifest V3 is Chrome's newer extension model. uBOL is built around MV3's declarativeNetRequest approach. Safari can run WebExtensions, but it still has its own extension packaging, permissions, and content-blocking behavior.

### Filter storage

Closed-source apps do not publish enough implementation detail to compare storage formats precisely. wBlock's Protocol Buffer + LZ4 storage and uBOL's packaged DNR rulesets are explicit project details; Wipr's internal storage is not public.

### Element zapper / picker

An element zapper or picker is a UI for selecting page elements and hiding them. uBOL's picker is mainly for cosmetic filters, while wBlock and AdGuard expose broader element-blocking tools. Wipr intentionally does not expose custom element blocking.

### Dynamic filtering

Classic uBO-style dynamic request filtering is not available through Safari's static content blocker API. wBlock approximates part of that workflow with per-site disable rules, fast rebuilds, and scripts. AdGuard's Safari apps have custom rules and element blocking, but they are not uBO's dynamic filtering matrix.

### Script injection

Static content blockers cannot do everything. Web extensions or app extensions inject scripts for cosmetic fixes, anti-adblock handling, YouTube workarounds, and site-specific behavior. That extra power usually requires broader website permissions.

### Userscripts

Greasemonkey/Tampermonkey-style user JavaScript is a wBlock feature in this comparison. The paid standalone AdGuard for Mac app supports userscripts, but AdGuard Mini and AdGuard for iOS do not advertise general userscript installation.

### URL parameter removal

Safari's content blocker API cannot rewrite a request URL, only block or ignore it. Removing UTM and other tracking parameters has to happen in a Safari Web Extension content script that rewrites the link or redirect before navigation. wBlock does this in wBlock Scripts with a bundled URL tracking protection list enabled by default. AdGuard implements the equivalent through `$removeparam` rules converted for its Safari Web Extension, and uBOL uses MV3 `removeparam` or redirect rules handled by the browser. Wipr's own help says it does not remove UTM or similar tracking tokens.

### Language support

Wipr chooses language-specific blocklists from the device's preferred languages. AdGuard has a large regional filter catalog and broad app localization. uBOL and wBlock both support regional filter coverage, but they expose it differently.

### License

GitHub reports GPL-3.0 for wBlock, uBOL, and AdGuard for iOS. Wipr is closed source. AdGuard Mini is source-available/open on GitHub, but GitHub reports a nonstandard license.

### Implementation language

GitHub language stats can be misleading because bundled JavaScript rules and generated resources count heavily. The table describes the practical app architecture rather than raw repository percentages.

### AdGuard iOS

AdGuard for iOS is a separate app with Safari content blockers, a Safari Web Extension, DNS protection, user rules, an allowlist, and custom filters. AdGuard and AdGuard Pro for iOS are effectively parallel ways to get the same advanced iOS feature set today; you do not need both.

### AdBlock Tester scores

The old hard-coded score row is intentionally gone. Those sites mostly measure enabled filter lists, not blocker quality. The result can change with one list update and should not be treated as a serious benchmark.

## How wBlock approximates dynamic filtering in Safari

Safari's content blocker API starts from compiled static rules. wBlock cannot inspect each request at runtime and make request-by-request decisions the way classic uBlock Origin can. The workaround is to use the parts of Safari that are dynamic enough: exception rules, quick rebuilds, and page scripts.

### Per-site disable with `ignore-previous-rules`

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

### Fast content blocker rebuilds

wBlock stores filter data in a format that can be read, changed, and written without turning every update into a full app-sized rebuild. When a change only affects a category or a site exception, the app can limit the work to the relevant targets. Safari still has to reload the compiled rule sets before the new behavior applies; that part is unavoidable.

### Scripts for page-level behavior

Some annoyances are better handled after the page loads. Cosmetic filtering, scriptlets, userscripts, the element zapper, and some YouTube fixes run through scripts because static network rules cannot select arbitrary DOM nodes or patch page JavaScript behavior.

### Category-based rule management

wBlock tracks pending changes by category and target extension. That bookkeeping lets the app avoid rebuilding unrelated blockers when a small setting changes. It also makes the UI's rule counts more useful because the user can see which part of the rule set actually changed.

### Limits

This is still Safari. Content blocker rules must be compiled and reloaded before they apply, and no Safari app can recreate classic uBO's request-by-request dynamic filtering through the content blocker API alone.

## Sources checked

- [Apple: Creating a content blocker](https://developer.apple.com/documentation/safariservices/creating-a-content-blocker)
- [uBOL README](https://github.com/uBlockOrigin/uBOL-home/blob/main/README.md) and [uBOL FAQ](https://github.com/uBlockOrigin/uBOL-home/wiki/Frequently-asked-questions-(FAQ))
- [Wipr Help](https://kaylees.site/wipr-help.html)
- [AdGuard Mini overview](https://adguard.com/en/adguard-mini-mac/overview.html), [rule limit KB](https://adguard.com/kb/adguard-mini-for-mac/solving-problems/rule-limit/), [AdGuard for iOS overview](https://adguard.com/en/adguard-ios/overview.html), [Safari protection KB](https://adguard.com/kb/adguard-for-ios/features/safari-protection/), and [Safari Web Extension KB](https://adguard.com/kb/adguard-for-ios/web-extension/)
- GitHub API responses for [wBlock](https://api.github.com/repos/0xCUB3/wBlock), [uBOL](https://api.github.com/repos/uBlockOrigin/uBOL-home), [AdGuard Mini](https://api.github.com/repos/AdguardTeam/AdGuardMiniForMac), and [AdGuard for iOS](https://api.github.com/repos/AdguardTeam/AdguardForiOS)
