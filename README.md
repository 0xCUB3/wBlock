<div align="center">

<img src="docs/media/img/wblock_logo.png" alt="wBlock logo" width="112" />

# wBlock

### The end of Safari ad-blocking B.S.

A free, open-source ad blocker for Safari on Mac, iPhone, iPad, and Apple Vision Pro.


<a href="https://apps.apple.com/us/app/wblock/id6746388723?itscg=30200&itsct=apps_box_badge&mttnsubad=6746388723">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/white/en-us?releaseDate=1760313600" width="220" />
    <source media="(prefers-color-scheme: light)" srcset="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/en-us?releaseDate=1760313600" width="220" />
    <img src="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/en-us?releaseDate=1760313600" alt="Download on the App Store" width="220" />
  </picture>
</a>

<br>
<br>

[![Version](https://img.shields.io/github/v/release/0xCUB3/wBlock?style=flat&label=version&color=gray)](https://github.com/0xCUB3/wBlock/releases/latest)
![Platforms](https://img.shields.io/badge/macOS_12.3+_|_iOS_15.4+_|_visionOS_1.0+-gray?style=flat&logo=apple&logoColor=white)
![License](https://img.shields.io/badge/GPL--3.0-gray?style=flat&label=license)
[![Discord](https://img.shields.io/badge/Discord-5865F2?style=flat&logo=discord&logoColor=white)](https://discord.gg/Y3yTFPpbXr)
[![Featured on FMHY](https://img.shields.io/badge/featured_on-FMHY-3E1E56?style=flat&logo=data:image/svg%2bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0id2hpdGUiIGQ9Ik01IDIuNSAyMSAxMiA1IDIxLjV6Ii8+PC9zdmc+)](https://fmhy.net/beginners-guide#browsers)
[![Mentioned in Open-Source iOS Apps](https://awesome.re/mentioned-badge.svg)](https://github.com/dkhamsing/open-source-ios-apps)

<br>

<img src="docs/media/img/hero_image.png" alt="wBlock on macOS in light and dark mode" width="900" />

<br>
<br>

[Features](#features) · [Screenshots](#screenshots) · [Install](#install) · [How it works](#how-it-works) · [FAQ](#faq) · [Support](#support)

</div>

## Features

### Blocking

Up to 750,000 Safari rules across five content blockers, with recommended lists, regional lists picked for you, and optional annoyance and cookie-banner filters.

<details>
<summary>More about blocking</summary>
<br>

- AdGuard-compatible filter lists compiled into Safari's native rules and spread across five content blockers, with a limit of 150,000 rules each. Safari applies the rules outside the app process.
- Recommended default lists, automatic regional filter selection, and optional annoyance and cookie-banner filters. Add custom lists by URL, pasted text, or file import.
- Scheduled updates from hourly to weekly, with incremental downloads for lists that support them. On macOS, a launch agent checks for updates while the app is closed.
- Tracking-parameter removal, including `utm_*`, and link-shortener resolution. Both are on by default.
- A capacity indicator and a rules viewer that shows compiled rules, unsupported entries, duplicate rules, rules handled by the scripts extension, and changes from the latest update.

</details>

### Userscripts

A Greasemonkey-compatible engine, UserCSS themes, and a built-in catalog with Tube Cleaner, DeArrow, Dark Reader, and more.

<details>
<summary>More about userscripts</summary>
<br>

- A separate scripts extension supports scriptlets, cosmetic filtering, userscripts, userstyles, and element hiding.
- A Greasemonkey-compatible engine supporting `GM_*` and `GM.*` APIs. `GM_xmlhttpRequest` is restricted to hosts declared in a script's `@connect` metadata.
- UserCSS themes (`.user.css`) with Less and Stylus support. See [docs/USERSTYLES.md](docs/USERSTYLES.md).
- A built-in catalog with Tube Cleaner, Player Cleaner, DeArrow, Dark Reader, Return YouTube Dislike, Bypass Paywalls Clean, AdGuard Extra, AdGuard Popup Blocker, and TwitchAdSolutions. Catalog scripts are off by default except tinyShield, which handles anti-adblock checks.

</details>

### Native video

Tube Cleaner and Player Cleaner give videos Safari's own controls, with Picture-in-Picture, background audio, and SponsorBlock.

<details>
<summary>More about native video</summary>
<br>

Tube Cleaner and Player Cleaner turn on Safari's native controls for existing video elements before the page renders, including Picture-in-Picture, background audio, fullscreen playback, and Now Playing.

Tube Cleaner works on YouTube and keeps its original video stream. It puts chapters and captions into Safari's native menus and skips sponsors with SponsorBlock, with settings per category. DeArrow is available separately for alternative titles and thumbnails.

Player Cleaner supports video.js, JW Player, Plyr, Flowplayer, MediaElement, Clappr, Media Chrome, and shadow-root players such as Archive.org's. It saves playback speed, volume, captions, and position per site.

Both scripts update from [wBlock-userscripts](https://github.com/0xCUB3/wBlock-userscripts) independently of app releases. Ad blocking stays with the filter lists.

</details>

### Per-site controls and sync

The Safari popup turns filtering, userscripts, and autoplay on or off for each site, and the Element Zapper hides anything else. Lists, scripts, and settings sync through iCloud.

<details>
<summary>More about per-site controls and sync</summary>
<br>

The Safari toolbar popup has separate switches for filtering, userscripts, and autoplay, plus the Element Zapper. Filter lists and userscripts can be limited to selected sites or excluded from specific domains. Zapper rules can be edited in Settings.

wBlock runs on macOS, iOS, iPadOS, and visionOS. iCloud sync covers filter lists, custom filters, userscripts, the allowlist, and settings. Local backup export is also available.

</details>

### Private by design

wBlock collects no data. Safari applies the rules outside the app, and idle memory is about 40 MB.

> [!TIP]
> The [comparison guide](Adblock_Comparison.md) covers wBlock, uBlock Origin Lite, Wipr, and AdGuard.

## Screenshots

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/filters_macos_dark.png" />
    <img src="docs/media/img/filters_macos_light.png" alt="Filters on macOS" width="760" />
  </picture>
  <br><sub>Filters on macOS</sub>
</p>

<br>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/scripts_popup_ios_dark.png" />
    <img src="docs/media/img/scripts_popup_ios_light.png" alt="The Safari popup on iPhone" height="560" />
  </picture>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="docs/media/img/tube_cleaner_sponsorblock.png" alt="SponsorBlock settings in Tube Cleaner" height="560" />
  <br><br><sub>The Safari popup on iPhone, and SponsorBlock in Tube Cleaner</sub>
</p>

<br>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/userscripts_macos_dark.png" />
    <img src="docs/media/img/userscripts_macos_light.png" alt="Userscripts on macOS" width="760" />
  </picture>
  <br><sub>Userscripts on macOS</sub>
</p>

<br>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/settings_macos_dark.png" />
    <img src="docs/media/img/settings_macos_light.png" alt="Settings on macOS" width="760" />
  </picture>
  <br><sub>Settings on macOS</sub>
</p>

## Install

Get it on the [App Store](https://apps.apple.com/us/app/wblock/id6746388723) for automatic updates, download the DMG from the [latest release](https://github.com/0xCUB3/wBlock/releases/latest), or use Homebrew:

```sh
brew tap 0xcub3/wblock && brew install --cask wblock
```

On first launch, wBlock walks you through turning on its extensions in Safari.

## How it works

The app downloads filter lists and converts them with [SafariConverterLib](https://github.com/AdguardTeam/SafariConverterLib) 4.3.0. Rules are spread across five content blockers: Ads, Privacy, Security, Foreign, and Custom. Safari compiles and applies them independently of the app. The wBlock Scripts extension handles what static rules can't express.

Filter data is stored in Protocol Buffers with LZ4 compression, and streaming writes keep peak memory low during compilation. Changing a list rebuilds only the affected content blockers. Safari must reload the updated rule sets before changes take effect.

The [comparison guide](Adblock_Comparison.md#how-wblock-works-around-static-rules) includes the rule used to turn off filtering for a specific site.

## FAQ

<details>
<summary>Should wBlock be used alongside another ad blocker?</summary>
<br>

No. Use one general-purpose content blocker at a time.

Multiple blockers can make conflicting changes to the same page or request. Mozilla's [webRequest documentation](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/webRequest/onHeadersReceived) describes how conflicting response modifications may allow only one extension's change to succeed. The [uBlock Origin documentation](https://github.com/gorhill/ublock#all-programs) advises against using another content blocker alongside it. [AdGuard's guidance](https://adguard.com/en/adguard-browser-extension/opera/overview.html) identifies slower loading, broken sites, and video-playback problems as possible consequences.

Disable other ad blockers before reporting a wBlock issue. This allows the cause of a blocking failure or site compatibility problem to be isolated.

<img width="1560" height="176" alt="Skill Issue" src="https://github.com/user-attachments/assets/b9c519bf-bbc7-40c0-bc4c-6a6d1fccb488" />

</details>

<details>
<summary>Should additional filter lists be enabled?</summary>
<br>

The recommended defaults cover most ads and trackers. Additional general-purpose lists often duplicate existing rules, consume Safari's rule capacity, and increase the risk of site compatibility problems. Annoyance lists provide coverage for cookie banners, popups, and social widgets. Regional lists provide additional coverage for non-English sites.

</details>

<details>
<summary>Does wBlock slow down Safari?</summary>
<br>

Not in normal use. Safari applies compiled rules outside the wBlock app process, so page loading does not wait for the app. Idle memory usage is approximately 40 MB.

</details>

<details>
<summary>How can Twitch ads be blocked?</summary>
<br>

Enable TwitchAdSolutions (vaft) or AdGuard Extra in the Userscripts tab, then reload Twitch. TwitchAdSolutions is the dedicated option. Use only one of these scripts at a time. Twitch frequently changes its ad delivery, so blocking may be temporarily affected until the script is updated.

</details>

<details>
<summary>Why are cookie-banner filters or scriptlets not working in Private Browsing?</summary>
<br>

Safari requires explicit permission for extensions to run in Private Browsing. Most cookie-banner filters rely on scriptlets provided by wBlock Scripts. In Safari → Settings → Extensions, enable Allow in Private Browsing for wBlock Scripts and all five content blockers, then reload the private window.

A stored consent cookie may explain why a banner is absent in a normal window. Clear the site's cookies before comparing normal and private browsing behavior.

</details>

<details>
<summary>How are userscript network requests handled?</summary>
<br>

`GM_xmlhttpRequest` requires `@grant GM_xmlhttpRequest` or `@grant GM.xmlHttpRequest`. Requests are restricted to hosts declared in the script's `@connect` metadata. A bare host permits that host and its subdomains; `localhost`, `self`, and `*` are also supported. Without `@connect`, requests are limited to the current host. Per-domain permission prompts are not currently available.

Only HTTP and HTTPS are supported. Redirect destinations are checked before the request follows them. If Safari does not expose a redirect destination to the extension, the request fails rather than bypassing the host restrictions. Requests do not include browser cookies or saved credentials. Requests marked `anonymous` also exclude cookies supplied by the script.

</details>

<details>
<summary>Where are Tube Cleaner and Player Cleaner located?</summary>
<br>

Both scripts are listed at the top of the General section in the Userscripts tab and are disabled by default. After enabling a script, individual features such as chapters, captions, and SponsorBlock can be configured separately. Player Cleaner can be disabled for a specific site through the Safari toolbar popup if compatibility issues occur.

</details>

<details>
<summary>How often do filters update, and must wBlock remain open?</summary>
<br>

Updates can be scheduled from hourly to weekly or performed manually. The app does not need to remain open. On macOS, a launch agent checks for updates while the app is closed; this behavior can be disabled in Settings.

On iOS and iPadOS, background updates are scheduled by the operating system. Disabling Background App Refresh or force-quitting wBlock from the app switcher may reduce update frequency or delay updates until the app is opened.

</details>

## Support

<div align="center">

wBlock is free and open source. If it's useful to you, you can support development on Open Collective.

<br>

<a href="https://opencollective.com/skula/projects/wblock">
  <img src="https://opencollective.com/about-this-hack/donate/button@2x.png?color=blue" alt="Donate on Open Collective" width="220" />
</a>

<br>
<br>

[Report a bug or request a feature](https://github.com/0xCUB3/wBlock/issues) · [Join the Discord](https://discord.gg/Y3yTFPpbXr) · [Privacy policy](PRIVACY_POLICY.md)

</div>

## Credits

<div align="center">

<sub>Contributors include [@arjpar](https://github.com/arjpar), [@ameshkov](https://github.com/ameshkov), and [@shindgew](https://github.com/shindgew). Rule conversion and scriptlets come from [AdGuard](https://github.com/AdguardTeam). SponsorBlock and DeArrow data come from [Ajay Ramachandran's](https://sponsor.ajay.app/) projects under CC BY-NC-SA 4.0.</sub>

<br>
<br>

</div>

<div align="center">

<a href="https://www.star-history.com/?repos=0xCUB3%2FwBlock&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=0xCUB3/wBlock&type=date&theme=dark&legend=top-left&sealed_token=FHF3tvPu6mhBn3K4_1fpH1nj2W36bTa6aW6_u-990mCb5zN_PRort245hoHzQEhFBRJo38qUYoOzU1huHG4_mHDsYpO7YxzKOIJEUaQI4NQNRDSdt9aZ_T1PVVSIaXqpdYnrBTTIlKhCEkYdneNsXEnpXhiUB3GW2F-tnsMNC4DPQJUKAmJK90omDnb2" />
   <img alt="Star history" src="https://api.star-history.com/chart?repos=0xCUB3/wBlock&type=date&legend=top-left&sealed_token=FHF3tvPu6mhBn3K4_1fpH1nj2W36bTa6aW6_u-990mCb5zN_PRort245hoHzQEhFBRJo38qUYoOzU1huHG4_mHDsYpO7YxzKOIJEUaQI4NQNRDSdt9aZ_T1PVVSIaXqpdYnrBTTIlKhCEkYdneNsXEnpXhiUB3GW2F-tnsMNC4DPQJUKAmJK90omDnb2" />
 </picture>
</a>

</div>
