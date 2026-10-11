<div align="center">

<img src="docs/media/img/wblock_logo.png" alt="wBlock logo" width="120" />

# wBlock

**The end of Safari ad-blocking B.S.**

A free, open-source ad blocker for Safari on Mac, iPhone, iPad, and Apple Vision Pro.

<br>

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
[![Mentioned in Open-Source iOS Apps](https://awesome.re/mentioned-badge.svg)](https://github.com/dkhamsing/open-source-ios-apps)

<br>

<img src="docs/media/img/hero_image.png" alt="wBlock on macOS in light and dark mode" width="900" />

</div>

<br>

Safari gives ad blockers very little room. Each content blocker gets 150,000 rules and can't touch a page's JavaScript. wBlock ships five of them (750,000 rules) plus a scripts extension for everything a rule can't do. That covers scriptlets, cosmetic filters, userscripts and userstyles, an element zapper, and native video players for YouTube and most other sites.

It's free and doesn't collect your data. If a filter list causes trouble, you can check the compiled rules and see which lines Safari couldn't use. You can also see what changed in the last update.

> [!TIP]
> Deciding between wBlock, uBlock Origin Lite, Wipr, and AdGuard? I wrote a [comparison](Adblock_Comparison.md).

<br>

## What's in it

### Blocking

- Filter lists in AdGuard syntax, converted into Safari rules across five blockers. Safari handles the blocking. wBlock uses around 40 MB when idle.
- Default lists to get you started and regional lists picked for your language. You can add cookie-banner and annoyance lists too, or import your own by URL, paste, or file.
- Updates as often as you want, from hourly to weekly. If a list offers incremental updates, wBlock only downloads what changed. On macOS a small launch agent checks for updates even when the app is closed.
- Tracking parameters like `utm_*` get stripped from links, and link shorteners get unwrapped. That's on by default.
- A capacity bar so you can see how close you are to Safari's rule limit. The rules viewer shows unsupported and duplicate rules, plus those handled by the scripts extension.

### Userscripts and userstyles

- A Greasemonkey-compatible engine with both `GM_*` and `GM.*`. `GM_xmlhttpRequest` only reaches hosts a script lists in `@connect`.
- UserCSS themes (`.user.css`), including Less, Sass, and Stylus. More in [docs/USERSTYLES.md](docs/USERSTYLES.md).
- A built-in catalog with Tube Cleaner, Player Cleaner, DeArrow, Dark Reader, Return YouTube Dislike, Bypass Paywalls Clean, AdGuard Extra, AdGuard Popup Blocker, and TwitchAdSolutions. They're all off by default except tinyShield, which deals with anti-adblock checks.

### Native video

Tube Cleaner and Player Cleaner replace a site's custom video player with Safari's native one before the page appears. You get Picture-in-Picture, background audio, fullscreen, and Now Playing, just like a plain `<video>` tag.

Tube Cleaner is for YouTube. It uses YouTube's own stream and puts chapters and captions in Safari's native menus. SponsorBlock skips sponsored segments, and you can choose which categories to skip. For better titles and thumbnails, turn on DeArrow separately.

Player Cleaner handles other sites. It works with video.js, JW Player, Plyr, Flowplayer, MediaElement, Clappr, Media Chrome, and shadow-root players like Archive.org's. It remembers your speed, volume, captions, and where you left off on each site.

Both update from [wBlock-userscripts](https://github.com/0xCUB3/wBlock-userscripts) on their own schedule, separate from the app. They don't block ads (the filter lists do that).

### Per-site control

Open the Safari toolbar popup to turn filtering, userscripts, or autoplay on or off for a site. The element zapper is there too. You can choose which sites a filter list or userscript runs on and edit your zapper rules in Settings.

### Every device

It's one app on macOS, iOS, iPadOS, and visionOS. iCloud syncs your lists, custom filters, userscripts, allowlist, and settings. If you'd rather keep things local, export a backup instead.

<br>

## Screenshots

<table>
<tr>
<td colspan="2" align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/userscripts_macos_dark.png" />
    <img src="docs/media/img/userscripts_macos_light.png" alt="Userscripts on macOS" width="760" />
  </picture>
  <br><sub>Userscripts on macOS</sub>
</td>
</tr>
<tr>
<td align="center" width="50%">
  <img src="docs/media/img/tube_cleaner_sponsorblock.png" alt="SponsorBlock settings in Tube Cleaner" width="260" />
  <br><sub>SponsorBlock in Tube Cleaner</sub>
</td>
<td align="center" width="50%">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/scripts_popup_ios_dark.png" />
    <img src="docs/media/img/scripts_popup_ios_light.png" alt="The Safari popup on iPhone" width="300" />
  </picture>
  <br><sub>The Safari popup on iPhone</sub>
</td>
</tr>
<tr>
<td colspan="2" align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/settings_macos_dark.png" />
    <img src="docs/media/img/settings_macos_light.png" alt="Settings on macOS" width="760" />
  </picture>
  <br><sub>Settings on macOS</sub>
</td>
</tr>
</table>

<br>

## Install

- [App Store](https://apps.apple.com/us/app/wblock/id6746388723). This is the easiest option if you want automatic updates.
- Homebrew: `brew tap 0xcub3/wblock && brew install --cask wblock`
- DMG from the [latest release](https://github.com/0xCUB3/wBlock/releases/latest).

On first launch wBlock walks you through turning the extensions on in Safari.

<br>

## How it works

The app downloads your filter lists and converts them with [SafariConverterLib](https://github.com/AdguardTeam/SafariConverterLib) 4.3.0. It splits the rules across five content blockers: Ads, Privacy, Security, Foreign, and Custom. Safari compiles and applies those rules itself without waiting on the app. The wBlock Scripts extension handles anything a static rule can't do.

Filter data is stored in Protocol Buffers with LZ4 compression. wBlock writes it to disk as it goes so large lists don't cause big memory spikes. When you change a list, only the blockers that use it get rebuilt. Safari still has to reload them before the change takes effect.

The [comparison](Adblock_Comparison.md#how-wblock-works-around-static-rules) shows the exact rule wBlock writes when you turn filtering off for a site.

<br>

## FAQ

<details>
<summary>Should I run wBlock alongside another ad blocker?</summary>
<br>

No. Pick one general-purpose blocker.

Two blockers can interfere with each other on the same page. Mozilla's [webRequest docs](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/webRequest/onHeadersReceived) explain one example: if two extensions change a response in conflicting ways, only one wins. uBlock Origin also [warns against using another blocker alongside it](https://github.com/gorhill/ublock#all-programs). AdGuard [warns about slow loading, broken sites, and video trouble](https://adguard.com/en/adguard-browser-extension/opera/overview.html).

Try the site with other ad blockers turned off before you file an issue. That way I can tell whether wBlock is the problem.

<img width="1560" height="176" alt="Skill Issue" src="https://github.com/user-attachments/assets/b9c519bf-bbc7-40c0-bc4c-6a6d1fccb488" />

</details>

<details>
<summary>Should I turn on more filter lists?</summary>
<br>

Usually not. The defaults already catch most ads and trackers. Other general lists mostly repeat those rules and use up more of Safari's rule limit. They can also break sites. Add annoyance lists if you want to hide cookie banners, popups, or social widgets. Regional lists help with sites in other languages.

</details>

<details>
<summary>Does wBlock slow Safari down?</summary>
<br>

Not in normal use. Safari applies the rules itself, outside wBlock, and a page load never waits on the app. It idles around 40 MB.

</details>

<details>
<summary>How do I block Twitch ads?</summary>
<br>

Turn on TwitchAdSolutions (vaft) or AdGuard Extra in the Userscripts tab and reload Twitch. vaft is the dedicated one. Don't run both. Twitch changes its ad setup often, and either script can break for a while until it catches up.

</details>

<details>
<summary>Why don't cookie banners or scriptlets work in Private Browsing?</summary>
<br>

Safari keeps extensions off in Private Browsing until you allow them. Most cookie-banner filters need scriptlets from wBlock Scripts. Go to Safari → Settings → Extensions and turn on Allow in Private Browsing for wBlock Scripts and all five blockers. Then reload the private window.

If a banner is already gone in a normal window, you may just have a consent cookie saved there. Clear the site's cookies before you compare.

</details>

<details>
<summary>How do userscript network requests work?</summary>
<br>

A script needs `@grant GM_xmlhttpRequest` (or `GM.xmlHttpRequest`). It can only reach hosts listed in its `@connect` lines. A bare host includes its subdomains. You can also use `localhost`, `self`, or `*`. Without `@connect`, requests are limited to the site the script runs on. There's no per-domain permission prompt yet.

Only HTTP and HTTPS are allowed. Redirects are checked before the request follows them. If Safari hides a redirect from the extension, the request fails rather than bypassing `@connect`. Requests don't include your browser cookies or saved logins. With `anonymous`, they also leave out cookies set by the script.

</details>

<details>
<summary>Where are Tube Cleaner and Player Cleaner?</summary>
<br>

At the top of the Userscripts tab, under General. Both are off by default. Turn one on to choose its features, including chapters, captions, and SponsorBlock. If Player Cleaner breaks a site, you can turn it off just for that site from the toolbar popup.

</details>

<details>
<summary>How often do filters update, and does wBlock need to stay open?</summary>
<br>

You can pick a schedule from hourly to weekly, or update manually. You don't need to keep wBlock open. On macOS a launch agent checks for updates while the app is closed. You can turn that off in settings.

On iPhone and iPad, iOS decides when wBlock can update in the background. Updates may happen less often or wait until you open the app if Background App Refresh is off or you've swiped wBlock away in the app switcher.

</details>

<br>

## Support

wBlock is free and it'll stay free. If you want to chip in, there's Open Collective.

<a href="https://opencollective.com/skula/projects/wblock">
  <img src="https://opencollective.com/about-this-hack/donate/button@2x.png?color=blue" alt="Donate on Open Collective" width="220" />
</a>

Bugs and feature requests go in [Issues](https://github.com/0xCUB3/wBlock/issues). For anything else, ask on [Discord](https://discord.gg/Y3yTFPpbXr). The [privacy policy](PRIVACY_POLICY.md) is short.

<br>

## Credits

Built with help from [@arjpar](https://github.com/arjpar), [@ameshkov](https://github.com/ameshkov), and [@shindgew](https://github.com/shindgew). Rule conversion and scriptlets come from [AdGuard](https://github.com/AdguardTeam). SponsorBlock and DeArrow data come from [Ajay Ramachandran's](https://sponsor.ajay.app/) projects under CC BY-NC-SA 4.0.

<br>

<div align="center">

<a href="https://www.star-history.com/?repos=0xCUB3%2FwBlock&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=0xCUB3/wBlock&type=date&theme=dark&legend=top-left&sealed_token=FHF3tvPu6mhBn3K4_1fpH1nj2W36bTa6aW6_u-990mCb5zN_PRort245hoHzQEhFBRJo38qUYoOzU1huHG4_mHDsYpO7YxzKOIJEUaQI4NQNRDSdt9aZ_T1PVVSIaXqpdYnrBTTIlKhCEkYdneNsXEnpXhiUB3GW2F-tnsMNC4DPQJUKAmJK90omDnb2" />
   <img alt="Star history" src="https://api.star-history.com/chart?repos=0xCUB3/wBlock&type=date&legend=top-left&sealed_token=FHF3tvPu6mhBn3K4_1fpH1nj2W36bTa6aW6_u-990mCb5zN_PRort245hoHzQEhFBRJo38qUYoOzU1huHG4_mHDsYpO7YxzKOIJEUaQI4NQNRDSdt9aZ_T1PVVSIaXqpdYnrBTTIlKhCEkYdneNsXEnpXhiUB3GW2F-tnsMNC4DPQJUKAmJK90omDnb2" />
 </picture>
</a>

</div>
