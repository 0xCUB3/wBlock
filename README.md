<div align="center">

<picture>
  <img src="docs/media/img/wblock_logo.png" alt="wBlock logo" width="112" />
</picture>

# wBlock

Safari ad blocking without the weird tradeoffs.

<a href="https://apps.apple.com/us/app/wblock/id6746388723?itscg=30200&itsct=apps_box_badge&mttnsubad=6746388723">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/white/en-us?releaseDate=1760313600" width="220" height="74" />
    <source media="(prefers-color-scheme: light)" srcset="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/en-us?releaseDate=1760313600" width="220" height="74" />
    <img src="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/en-us?releaseDate=1760313600" alt="Download on the App Store" width="220" height="74" />
  </picture>
</a>

![Version](https://img.shields.io/github/v/release/0xCUB3/wBlock?style=flat&label=version&color=gray)
![Platform](https://img.shields.io/badge/macOS_12.3+_|_iOS_15.4+-gray?style=flat&logo=apple&logoColor=white)
![License](https://img.shields.io/badge/GPL--3.0-gray?style=flat&label=license)
[![Join Discord](https://img.shields.io/badge/Join-Discord-5865F2?style=flat&logo=discord&logoColor=white)](https://discord.gg/Y3yTFPpbXr)

</div>

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/hero_image_dark.png" width="900" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/hero_image_light.png" width="900" />
    <img src="docs/media/img/hero_image_light.png" alt="wBlock interface" width="900" />
  </picture>
</div>

wBlock is a native Safari content blocker for macOS, iOS, and iPadOS. It keeps Safari's fast declarative blocking model, then adds the tools Safari users usually lose: custom lists, userscripts, userstyles, an element zapper, per-site controls, iCloud sync, and a macOS request logger.

For a detailed look at the tradeoffs between Safari blockers, read the [Safari ad blocker comparison](Adblock_Comparison.md).

## What you get

- Up to 750,000 compiled Safari rules across five blockers.
- Around 40 MB at idle in my local checks. Safari does the rule matching, so wBlock doesn't need to sit on every request.
- Filter data is stored as Protocol Buffers and compressed with LZ4. Boring plumbing, but it keeps big lists quick to load.
- Updates can run hourly, weekly, or anywhere in between. If the server supports `ETag` or `If-Modified-Since`, wBlock asks for only what changed.
- Bring your own AdGuard-compatible lists by URL, paste, or file.
- Run userscripts with common Greasemonkey APIs, including storage and `GM_xmlhttpRequest`.
- Install userstyles as CSS, not JavaScript wrappers.
- Flip blocking, userscripts, zapper rules, and trusted domains per site.
- Regional filters are suggested from your locale, but you can choose manually.
- Install macOS builds from Homebrew if you don't want the App Store.

## Screenshots

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/userscripts_macos_dark.png" width="760" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/userscripts_macos_light.png" width="760" />
    <img src="docs/media/img/userscripts_macos_light.png" alt="Userscript management in wBlock" width="760" />
  </picture>
  <br>
  <sub>Manage built-in and custom userscripts.</sub>
</div>

<br>

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/settings_macos_dark.png" width="760" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/settings_macos_light.png" width="760" />
    <img src="docs/media/img/settings_macos_light.png" alt="wBlock settings on macOS" width="760" />
  </picture>
  <br>
  <sub>Set update intervals, notifications, and app behavior.</sub>
</div>

<br>

<table>
<tr>
<td align="center" width="50%">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/filters_ios_dark.png" width="320" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/filters_ios_light.png" width="320" />
    <img src="docs/media/img/filters_ios_light.png" alt="wBlock filters on iOS" width="320" />
  </picture>
  <br>
  <sub>Full filter management on iPhone.</sub>
</td>
<td align="center" width="50%">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/filters_ipados_dark.png" width="520" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/filters_ipados_light.png" width="520" />
    <img src="docs/media/img/filters_ipados_light.png" alt="wBlock filters on iPadOS" width="520" />
  </picture>
  <br>
  <sub>The same controls on iPad.</sub>
</td>
</tr>
</table>

## Install

### App Store

The App Store build is the easiest option and includes automatic app updates.

<a href="https://apps.apple.com/us/app/wblock/id6746388723?itscg=30200&itsct=apps_box_badge&mttnsubad=6746388723">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/white/en-us?releaseDate=1760313600" width="180" height="60" />
    <source media="(prefers-color-scheme: light)" srcset="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/en-us?releaseDate=1760313600" width="180" height="60" />
    <img src="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/en-us?releaseDate=1760313600" alt="Download on the App Store" width="180" height="60" />
  </picture>
</a>

### Homebrew

```bash
brew tap 0xcub3/wblock
brew install --cask wblock
```

### Direct download

Download the latest DMG from [GitHub Releases](https://github.com/0xCUB3/wBlock/releases). The DMG/Homebrew build has the same features as the App Store build.

## How it works

Safari content blockers are fast: Safari applies compiled rules inside the browser engine. They also have a hard edge: they can't inspect every request at runtime like classic uBlock Origin. wBlock keeps that native path for static rules and uses wBlock Scripts for page fixes: cosmetic filtering, scriptlets, userscripts, URL tracking-parameter stripping, and the element zapper.

The moving parts:

- SafariConverterLib converts AdGuard rules into Safari content blocker rules.
- Five blocker extensions give wBlock the maximum Safari rule capacity it can use per platform.
- Swift concurrency keeps filtering, updates, and rebuilds off the main UI path.
- SwiftProtobuf and LZ4 keep stored filter data compact and quick to read.
- The macOS logger shows blocked requests when you need to debug a site.

## FAQ

<details>
<summary>How does wBlock compare to other ad blockers?</summary>

Read the [Safari ad blocker comparison](Adblock_Comparison.md) for notes on wBlock, uBlock Origin Lite, Wipr 2, and AdGuard's Safari apps.
</details>

<details>
<summary>Should I install wBlock from the App Store or the DMG/Homebrew release?</summary>

The App Store version is usually the better default because it handles app updates for you. The DMG/Homebrew release has the same features and is there if you prefer installing outside the App Store.
</details>

<details>
<summary>Can I use my own filter lists?</summary>

Yes. You can add any AdGuard-compatible filter list by URL, paste rules directly, or import from a file.
</details>

<details>
<summary>Should I enable more filter lists for better blocking?</summary>

Most of the time, no. The defaults already cover most ads and trackers, and many general-purpose lists overlap with them. Extra lists mostly spend rule capacity and can break sites. Annoyances filters and regional filters are the useful exceptions because they cover things the defaults often miss.
</details>

<details>
<summary>Does wBlock slow down Safari?</summary>

No in normal use. wBlock uses Safari's native declarative content blocking API, which applies rules outside the app process. My local idle checks sit around 40 MB, and page loading stays on Safari's native blocker path.
</details>

<details>
<summary>Do userscripts work on iOS and iPadOS?</summary>

Yes. The userscript engine implements common Greasemonkey APIs on iOS, iPadOS, and macOS through Safari Web Extensions.
</details>

<details>
<summary>How do I block Twitch ads?</summary>

wBlock bundles the AdGuard Extra userscript, which can help with Twitch ads by talking to Twitch's GraphQL API (`gql.twitch.tv`). It's off by default.

1. Open wBlock and go to Userscripts.
2. Find AdGuard Extra in the built-in list and turn it on.
3. Reload any open Twitch tabs.

Twitch changes its ad delivery often, so this can break until the userscript is updated.
</details>

<details>
<summary>How often do filters update?</summary>

Auto-update intervals are configurable from one hour to seven days, or you can update manually. On macOS, a bundled launch agent can keep checking while the app is closed. On iOS and iPadOS, background checks are best-effort and may wait until the system wakes wBlock or you reopen it. Opening Safari doesn't trigger updates.
</details>

<details>
<summary>Is the element zapper available on iOS and iPadOS?</summary>

Yes. Open the wBlock extension popup in Safari and tap Activate Element Zapper.
</details>

## Support development

wBlock is free and open source. If you want to support the project, donations go through Open Collective.

<div align="center">
  <a href="https://opencollective.com/skula/projects/wblock">
    <img src="https://opencollective.com/about-this-hack/donate/button@2x.png?color=blue" alt="Donate Button" width="230" />
  </a>
</div>

## Credits

Thanks to [@arjpar](https://github.com/arjpar), [@ameshkov](https://github.com/ameshkov/safari-blocker), and [@shindgewongxj](https://github.com/shindgewongxj).

[![Discord](https://img.shields.io/badge/Discord-Community-5865F2?style=flat&logo=discord&logoColor=white)](https://discord.gg/Y3yTFPpbXr)
[![Privacy](https://img.shields.io/badge/Privacy-Policy-gray?style=flat)](https://github.com/0xCUB3/wBlock/blob/main/PRIVACY_POLICY.md)
[![Issues](https://img.shields.io/badge/Report-Issues-orange?style=flat&logo=github)](https://github.com/0xCUB3/wBlock/issues)

Developed by [0xCUB3](https://github.com/0xCUB3).

<details>
<summary>Star history</summary>

<div align="center">
  <a href="https://www.star-history.com/?repos=0xCUB3%2FwBlock&type=date&legend=bottom-right">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=0xCUB3/wBlock&type=date&theme=dark&legend=bottom-right" />
      <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=0xCUB3/wBlock&type=date&legend=bottom-right" />
      <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=0xCUB3/wBlock&type=date&legend=bottom-right" />
    </picture>
  </a>
</div>

</details>
