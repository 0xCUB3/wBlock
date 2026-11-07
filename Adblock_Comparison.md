# Safari ad blocker comparison

_Last checked September 24, 2026, against wBlock 3.1, uBlock Origin Lite, Wipr 2, AdGuard Mini, and AdGuard for iOS._

A Safari blocker is not uBlock Origin on Firefox. The app gives Safari a compiled rule list up front, and Safari enforces it inside the browser engine without asking the app anything during a page load. It's fast and private, but the blocker can't make a call on each request. Cosmetic filtering, scriptlets, element picking, YouTube fixes, and per-site switches all need a separate Safari Web Extension running next to the rules.

Every app below mixes those two halves differently. What sets them apart is how much of each you get and how much the app lets you see.

## Short version

If you want to control everything, use wBlock. It has custom lists, userscripts and userstyles, native video players, per-site switches, and iCloud sync, and it shows you what every list compiled into.

If you ran uBlock Origin on defaults and never opened its settings, uBlock Origin Lite will feel familiar. It's light and declarative, and it isn't classic uBO.

If you never want to open the app again, get Wipr 2. It has almost no settings, and that's deliberate.

If you already trust AdGuard's filters and don't mind paying for the advanced parts, use AdGuard Mini on the Mac or AdGuard for iOS.

## At a glance

| | wBlock | uBlock Origin Lite | Wipr 2 | AdGuard Mini / iOS |
|-|-|-|-|-|
| Good for | Control | uBO defaults | Set and forget | AdGuard users |
| Price | Free | Free | One-time purchase | Free, Pro for extras |
| Source | GPL-3.0 | GPL-3.0 | Closed | Mini source-available, iOS GPL-3.0 |
| Platforms | macOS, iOS, iPadOS, visionOS | macOS, iOS, iPadOS, visionOS | macOS, iOS, iPadOS, visionOS | Mini on Mac, iOS app elsewhere |
| Rule capacity | 750,000 | Set by the browser | Not published | 900,000 |
| Custom lists | Yes | Yes, with limits | No | Yes |
| Userscripts | Yes | No | No | No |
| Element picker | Yes | Cosmetic only | No | Yes |
| Native video | Yes | No | No | No |
| Logs | Yes | No | No | Yes |
| Sync | iCloud | No | Settings only | No |

## wBlock

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/filters_macos_dark.png" />
    <img src="docs/media/img/filters_macos_light.png" alt="wBlock filters on macOS" width="760" />
  </picture>
</div>

I make wBlock. Weigh this section with that in mind. It runs on macOS, iOS, iPadOS, and visionOS (on Vision Pro as the iPad app) with five content blockers of 150,000 rules each. That 750,000 counts compiled Safari rules. One AdGuard rule can turn into several Safari rules, or none if Safari can't express it, and wBlock shows you both counts plus every line it had to drop.

The other half is wBlock Scripts, a Web Extension for what rules can't do. It runs AdGuard scriptlets and cosmetic CSS, strips tracking parameters from links, and hosts the userscript engine and UserCSS. The element zapper lives there too. You can walk up and down the DOM with it until you're hiding the ad's container and not some span inside it.

No other Safari blocker runs userscripts. wBlock covers both `GM_*` and `GM.*` for the common APIs, and `GM_xmlhttpRequest` only reaches hosts a script declares. The built-in catalog has Tube Cleaner and Player Cleaner (native Safari video on YouTube and elsewhere, with SponsorBlock), DeArrow, Dark Reader, Return YouTube Dislike, Bypass Paywalls Clean, and two Twitch ad scripts. Scripts that depend on odd Tampermonkey behavior might still need fixes.

The toolbar popup has separate switches for filtering, userscripts, and autoplay on the current site, and you can limit lists or scripts to the sites you choose. Lists update on a schedule (hourly to weekly), use diff patches when the list publishes them, and on macOS keep updating with the app closed.

The cost is that wBlock asks more of you. There are more screens than in Wipr, and a userscript can break a site in ways a blocklist never will.

Sources: [wBlock on GitHub](https://github.com/0xCUB3/wBlock), [App Store](https://apps.apple.com/us/app/wblock/id6746388723), [Apple content blocker docs](https://developer.apple.com/documentation/safariservices/creating-a-content-blocker)

## uBlock Origin Lite

<div align="center">
  <img src="docs/media/img/adblock_comparison/ublock_origin_lite.png" alt="uBlock Origin Lite" width="760" />
</div>

uBlock Origin Lite is its own Manifest V3 project, not uBO with a smaller UI. Rules are prepared ahead of time and the browser enforces them, with nothing filtering in the background. It ships with uBO's own lists, EasyList, EasyPrivacy, and Peter Lowe's list, and there are App Store builds for Mac, iPhone, iPad, and Vision Pro. The popup's Basic, Optimal, and Complete modes decide how much it can do on the current site.

Classic uBO is powerful because it decides at runtime, and MV3 takes most of that away. The uBOL FAQ lists what doesn't carry over (dynamic filtering, rewriting response bodies, some `removeparam` cases, many regex rules). Generic cosmetic filtering stays off unless you pick Complete.

In June 2026 the FAQ started saying custom filters and external list subscriptions work now, within the declarative model. That closes part of the gap. It's still a blocker you set up once and mostly forget.

Sources: [uBOL on GitHub](https://github.com/uBlockOrigin/uBOL-home), [README](https://github.com/uBlockOrigin/uBOL-home/blob/main/README.md), [FAQ](https://github.com/uBlockOrigin/uBOL-home/wiki/Frequently-asked-questions-(FAQ)), [App Store](https://apps.apple.com/us/app/ublock-origin-lite/id6745342698)

## Wipr 2

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/adblock_comparison/wipr_2_dark.png" />
    <img src="docs/media/img/adblock_comparison/wipr_2_light.png" alt="Wipr 2" width="760" />
  </picture>
</div>

Wipr 2 is nearly the opposite of wBlock. You pay once, turn on four blocklist extensions and Wipr Extra, and leave it alone. There's no custom list, rule editor, element picker, or log, and Wipr's FAQ says custom filters and element blocking aren't coming because having nothing to configure is the point.

It's still a real Safari blocker. The blocklists are content blockers, and Wipr Extra is a Web Extension that handles YouTube ads, cookie warnings, and anti-adblock (it needs broader site access for that). Regional lists get picked from your device languages. Wipr's help pages say it doesn't strip UTM parameters, and they ask iOS users not to force-quit the app because updates can stall.

Filtr is a separate in-app purchase built on Apple's URL Filters API for iOS and macOS 26. It blocks URLs system-wide without a VPN or DNS server. That's handy, but it lives outside the Safari blocker and needs the new OS.

If Wipr misses an ad or breaks a site, you don't have anything to adjust.

Sources: [Wipr 2 on the App Store](https://apps.apple.com/us/app/wipr-2/id1662217862), [Wipr Help](https://kaylees.site/wipr-help.html)

## AdGuard Mini and AdGuard for iOS

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/adblock_comparison/adguard_mini_dark.png" />
    <img src="docs/media/img/adblock_comparison/adguard_mini_light.png" alt="AdGuard Mini" width="760" />
  </picture>
</div>

AdGuard splits Safari across two apps. AdGuard Mini (it used to be AdGuard for Safari) is the Mac one, and AdGuard for iOS covers iPhone, iPad, and Vision. The full AdGuard for Mac is a separate paid, system-wide product, and I'm leaving it out.

Mini has six content blockers (General, Privacy, Social, Security, Other, Custom) for a ceiling of 900,000 rules. Filter categories, custom lists, user rules, element blocking, and issue reporting are free. Pro adds real-time filter updates, AdGuard Extra for harder anti-adblock cases, and a few advanced filtering features.

AdGuard for iOS has the same six blockers plus a Web Extension for per-site toggles and element blocking. Premium adds advanced rules and scriptlets. There's also DNS protection. It catches ad and tracker domains in other apps, but it only sees hostnames and can't hide anything on a page. AdGuard and AdGuard Pro on the iOS App Store unlock the same features now, and you only need one of them.

AdGuard has the deepest filter ecosystem here, and most of these apps (wBlock included) build on its rule syntax. What gets in the way is the two-app split and paying for the good parts.

Sources: [AdGuard Mini](https://adguard.com/en/adguard-mini-mac/overview.html), [Mini on GitHub](https://github.com/AdguardTeam/AdGuardMiniForMac), [rule limit](https://adguard.com/kb/adguard-mini-for-mac/solving-problems/rule-limit/), [AdGuard for iOS](https://adguard.com/en/adguard-ios/overview.html), [iOS on GitHub](https://github.com/AdguardTeam/AdguardForiOS), [Safari protection](https://adguard.com/kb/adguard-for-ios/features/safari-protection/), [Web Extension](https://adguard.com/kb/adguard-for-ios/web-extension/), [AdGuard vs AdGuard Pro](https://adguard.com/kb/adguard-for-ios/adguard-and-adguard-pro/)

## Feature by feature

### Blocking

| | wBlock | uBlock Origin Lite | Wipr 2 | AdGuard Mini / iOS |
|-|-|-|-|-|
| Page scripts | wBlock Scripts | Content scripts | Wipr Extra | Web Extension |
| Scriptlets | Yes | Some | Wipr Extra only | Yes, Premium on iOS |
| Cosmetic filtering | Yes | Depends on mode | Yes | Yes |
| YouTube ads | Yes | Yes, breaks often | Yes, via Wipr Extra | Yes, better with Pro |
| Twitch ads | Opt-in scripts | No dedicated option | Not documented | AdGuard Extra (Pro) |
| Strips `utm_*` | Yes, by default | Yes | No | Yes |
| System-wide | No | No | Filtr (paid, OS 26) | DNS on iOS |

### Control

| | wBlock | uBlock Origin Lite | Wipr 2 | AdGuard Mini / iOS |
|-|-|-|-|-|
| Custom lists | URL, paste, or file | Yes, with limits | No | Yes |
| User rules | Yes | Custom filters | No | Yes |
| Userscripts | Yes | No | No | No |
| Userstyles | Yes | No | No | No |
| Element picker | Yes, rules editable | Cosmetic only | No | Yes |
| Per-site switches | Filtering, scripts, autoplay | Filtering mode | On/off | On/off |
| Lists for chosen sites | Yes | No | No | No |
| Updates | Hourly to weekly | With extension updates | Automatic | Automatic, real-time with Pro |
| Sync | iCloud | No | Settings only | No |
| Logs | Yes | No | No | Yes |

### Project

| | wBlock | uBlock Origin Lite | Wipr 2 | AdGuard Mini / iOS |
|-|-|-|-|-|
| Written in | Swift, JavaScript | JavaScript | Swift | Swift, web UI |
| GitHub stars | 2,943 | 3,804 | n/a | 1,185 / 1,703 |
| Privacy label | Data Not Collected | Data Not Collected | Data Not Collected | Data Not Collected |
| Idle RAM | ~40 MB | ~120 MB | ~50 MB | ~100 MB (Mini) |

Star counts are from September 24, 2026. I measured RAM roughly on a 2023 M2 Pro MacBook Pro with a few tabs open and one blocker active. Lists, tabs, and sites move it a lot. Treat it as a ballpark.

## How wBlock works around static rules

Classic uBO looks at each request and decides on the spot. A Safari app can't do that through the content blocker API. wBlock gets as close as Safari lets it with exception rules, targeted rebuilds, and page scripts.

When you turn filtering off for a site, wBlock appends one rule:

```json
{
  "action": { "type": "ignore-previous-rules" },
  "trigger": { "url-filter": ".*", "if-domain": ["*site.com"] }
}
```

Safari then ignores every blocking rule before it on that domain. That's coarser than uBO's dynamic matrix, but it's a real off switch with nothing running in the background. Userscripts and autoplay have their own per-site switches in the extension, and turning filtering off leaves them alone.

wBlock tracks changes per list and per blocker. If you toggle one list, only the blockers it feeds get recompiled. An `@@` exception also stays in the same blocker as the rule it cancels, even if the two lists would otherwise land in different blockers. Safari still reloads the affected rule sets before a change shows up. There's no way around that.

Anything a network rule can't express goes to wBlock Scripts (cosmetic CSS, scriptlets, userscripts, the zapper, URL cleanup). Safari's content blocker API can block a request but can't rewrite its URL. Stripping `utm_*` has to happen in a script before the navigation.

## Notes

Safari caps each content blocker at 150,000 compiled rules. wBlock has five, AdGuard six, and Wipr four without publishing a total. uBOL's limits come from how the browser handles declarative rulesets, not from content blocker slots.

The paid standalone AdGuard for Mac does run userscripts. AdGuard Mini and AdGuard for iOS don't.

GitHub's language bars count bundled filter data. The "Written in" row describes the apps as built, not the repo percentages.

I left out ad-block tester scores on purpose. Those sites mostly measure which lists you have on, and one list update can change the result.

## Sources

- [Apple: Creating a content blocker](https://developer.apple.com/documentation/safariservices/creating-a-content-blocker)
- [uBOL README](https://github.com/uBlockOrigin/uBOL-home/blob/main/README.md) and [FAQ](https://github.com/uBlockOrigin/uBOL-home/wiki/Frequently-asked-questions-(FAQ))
- [Wipr Help](https://kaylees.site/wipr-help.html)
- [AdGuard Mini](https://adguard.com/en/adguard-mini-mac/overview.html), [rule limit](https://adguard.com/kb/adguard-mini-for-mac/solving-problems/rule-limit/), [AdGuard for iOS](https://adguard.com/en/adguard-ios/overview.html), [Safari protection](https://adguard.com/kb/adguard-for-ios/features/safari-protection/), [Web Extension](https://adguard.com/kb/adguard-for-ios/web-extension/)
- GitHub API for [wBlock](https://api.github.com/repos/0xCUB3/wBlock), [uBOL](https://api.github.com/repos/uBlockOrigin/uBOL-home), [AdGuard Mini](https://api.github.com/repos/AdguardTeam/AdGuardMiniForMac), and [AdGuard for iOS](https://api.github.com/repos/AdguardTeam/AdguardForiOS)
