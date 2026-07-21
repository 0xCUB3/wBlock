<div align="center">

<picture>
  <img src="docs/media/img/wblock_logo.png" alt="wBlock Logo" width="120" />
</picture>

# wBlock

**The end of Safari ad-blocking B.S.**

<br>

<a href="https://apps.apple.com/us/app/wblock/id6746388723?itscg=30200&itsct=apps_box_badge&mttnsubad=6746388723">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/white/en-us?releaseDate=1760313600" width="245" height="82" />
    <source media="(prefers-color-scheme: light)" srcset="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/en-us?releaseDate=1760313600" width="245" height="82" />
    <img src="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/en-us?releaseDate=1760313600" alt="Download on the App Store" width="245" height="82" />
  </picture>
</a>
    

<br>
<br>

![Version](https://img.shields.io/github/v/release/0xCUB3/wBlock?style=flat&label=version&color=gray)
![Platform](https://img.shields.io/badge/macOS_12.3+_|_iOS_15.4+-gray?style=flat&logo=apple&logoColor=white)
![License](https://img.shields.io/badge/GPL--3.0-gray?style=flat&label=license)

[![Join Discord](https://img.shields.io/badge/Join-Discord-5865F2?style=flat&logo=discord&logoColor=white)](https://discord.gg/Y3yTFPpbXr)

</div>

<br>
<br>

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/hero_image_dark.png" width="900" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/hero_image_light.png" width="900" />
    <img src="docs/media/img/hero_image_light.png" alt="wBlock Interface" width="900" />
  </picture>
</div>

<br>

<p align="center">
A Safari content blocker for macOS, iOS, and iPadOS.<br>
750,000 rules across 5 extensions, Protocol Buffer storage, LZ4 compression, and iCloud sync.
</p>

<br>

> [!NOTE]
> **Looking for a detailed comparison?** Check out my [comparison guide](Adblock_Comparison.md) to see how wBlock stacks up against other Safari content blockers.

<br>

<div align="center">

## Features

</div>

<table align="center">
<tr>
<td width="50%" valign="top">

### Performance
- **750,000 rule capacity** across 5 Safari content blocking extensions per platform (150k each)
- **~40 MB RAM** at idle — Safari's native content blocking API runs rules out-of-process
- **Protocol Buffers + LZ4** for filter storage; streaming I/O keeps memory low during compilation
- **HTTP conditional requests** (If-Modified-Since/ETag) so updates only download what changed
- **iCloud sync** for filter selections, custom lists, userscripts, and whitelist across devices

### Content modification
- **Element Zapper** (macOS, iOS, iPadOS, visionOS) — visually select and hide page elements in Safari
- **Tube Cleaner & Player Cleaner** — optional built-in userscripts that turn existing media elements into native Safari players before first paint, restoring Picture-in-Picture and background playback; wBlock's content-blocking rules handle ads separately
- **Userscript engine** with Greasemonkey API (GM_getValue, GM_setValue, GM_xmlhttpRequest)
- **Userstyle support** — install UserCSS themes (.user.css) applied natively as CSS, no JS wrapper needed
- **Custom filter lists** via URL, paste, or file import — supports any AdGuard-syntax blocklist
- **Toolbar search** for quickly finding filters and userscripts
- **Automatic rule distribution** across all 5 content blocker slots for maximum coverage

</td>
<td width="50%" valign="top">

### Blocking
- **Network request blocking** — ads, trackers, cookie banners, annoyances
- **CSS injection** for cosmetic filtering and element hiding
- **Script blocking** for unwanted JavaScript
- **Pop-up and redirect prevention**
- **URL tracking-parameter stripping** — removes UTM and other tracking params, unwraps shortener/redirect URLs (enabled by default via wBlock Scripts)

### Configuration
- **Auto-updates** from every hour to every 7 days, or manual. macOS can keep checking through a bundled launch agent and background update service, iOS background checks are best-effort
- **Per-site controls** — disable blocking on specific sites from the Safari toolbar
- **Blocked request logger** (macOS) — see what's being blocked on each page
- **Per-site settings** — whitelist trusted domains, toggle userscripts per site, and switch element zapper rules on or off per domain
- **Regional filters** with auto-detection based on your locale
- **Homebrew cask** for macOS: `brew tap 0xcub3/wblock && brew install --cask wblock`

</td>
</tr>
</table>

<br>

---

<br>

<div align="center">

## Screenshots

<br>

<table>
<tr>
<td align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/userscripts_macos_dark.png" width="700" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/userscripts_macos_light.png" width="700" />
    <img src="docs/media/img/userscripts_macos_light.png" alt="Userscript Management Screenshot" width="700" />
  </picture>
<br>
<strong>Userscript Management</strong><br>
<em>Manage paywalls, YouTube Dislikes, and more</em>
<br><br>
</td>
</tr>
<tr>
<td align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/settings_macos_dark.png" width="700" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/settings_macos_light.png" width="700" />
    <img src="docs/media/img/settings_macos_light.png" alt="Settings Screenshot" width="700" />
  </picture>
<br>
<strong>Settings & Customization</strong><br>
<em>Configure auto-updates, notifications, and preferences</em>
<br><br>
</td>
</tr>
<tr>
<td align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/filters_ios_dark.png" width="350" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/filters_ios_light.png" width="350" />
    <img src="docs/media/img/filters_ios_light.png" alt="iOS Screenshot" width="350" />
  </picture>
<br><br>
<strong>iOS Interface</strong><br>
<em>Full-featured blocking on iPhone</em>
<br><br>
</td>
</tr>
<tr>
<td align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/img/filters_ipados_dark.png" width="700" />
    <source media="(prefers-color-scheme: light)" srcset="docs/media/img/filters_ipados_light.png" width="700" />
    <img src="docs/media/img/filters_ipados_light.png" alt="iPadOS Screenshot" width="700" />
  </picture>
<br><br>
<strong>iPadOS Interface</strong><br>
<em>Full-featured blocking on iPad</em>
<br><br>
</td>
</tr>
</table>

</div>

<br>

---

<br>

<div align="center">

## Technical Implementation

</div>

<table>
<tr>
<td width="50%" valign="top">

**Core Architecture**
- Protocol Buffers (libprotobuf) with LZ4 compression for filter serialization
- Asynchronous I/O with Swift concurrency (async/await, Task, Actor isolation)
- Streaming serialization to disk minimizes peak memory usage during compilation
- 5 Safari content blocking extensions per platform (maximum Safari API capacity)
- SafariServices framework integration for declarative content blocking

</td>
<td width="50%" valign="top">

**Dependencies & Standards**
- SafariConverterLib v4.3.0 for AdGuard to Safari rule conversion
- Bundled AdGuard scriptlet engine for advanced blocking techniques
- Swift concurrency (async/await, Task, Actor isolation) with project-level Swift 5 settings
- VoiceOver and Dynamic Type support throughout the SwiftUI app
- SwiftProtobuf for cross-platform filter storage format

</td>
</tr>
</table>

---

<br>

<div align="center">

## Support Development

wBlock is free and open source.<br>
If you want to support the project:

<br>

<a href="https://opencollective.com/skula/projects/wblock">
  <img src="https://opencollective.com/about-this-hack/donate/button@2x.png?color=blue" alt="Donate Button" width="250" />
</a>

</div>

<br>

---

<br>

<div align="center">

## FAQ

</div>

<details>
<summary><b>How does wBlock compare to other ad blockers?</b></summary>
<br>
Check out our <a href="Adblock_Comparison.md">comparison guide</a> vs uBlock Origin Lite, Wipr 2, and AdGuard's Safari apps.
</details>

<details>
<summary><b>Should I install wBlock from the App Store or the DMG/Homebrew release?</b></summary>
<br>
The App Store version is usually preferred because it handles app updates automatically. The DMG/Homebrew release has the same features and is available for users who prefer installing outside the App Store.
</details>

<details>
<summary><b>Should I use wBlock alongside another ad blocker?</b></summary>
<br>

<b>No. Use one general-purpose content blocker at a time.</b>

There is no controlled study proving that every possible combination of ad blockers harms every page. However, browser architecture and extension documentation support avoiding overlapping blockers:

- <b>Extensions can make conflicting changes.</b> Mozilla documents that when two extensions attempt conflicting modifications to the same response header, only one change may succeed. Multiple blockers can therefore produce order-dependent behavior rather than a predictable combination of their protections. See <a href="https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/webRequest/onHeadersReceived">Mozilla’s webRequest documentation</a>.

- <b>Request interception has measurable computational costs.</b> Chromium describes serialization, inter-process communication, persistent-process, and extension-response processing costs associated with blocking request handlers. Running redundant filtering systems duplicates at least some rule evaluation and page-processing work. See <a href="https://blog.chromium.org/2019/06/web-request-and-declarative-net-request.html">Chromium’s explanation of Web Request and Declarative Net Request</a> and <a href="https://developer.chrome.com/docs/extensions/develop/migrate/what-is-mv3">Chrome’s Manifest V3 overview</a>.

- <b>Major blocker maintainers explicitly advise against stacking.</b> The official uBlock Origin README states: “Do NOT use uBO with any other content blocker.” It explains that another blocker can prevent uBO’s privacy or anti-blocker-defusing features from working correctly. See <a href="https://github.com/gorhill/ublock#all-programs">uBlock Origin’s official documentation</a>.

- <b>Documented failure modes include slower loading and broken functionality.</b> AdGuard warns that two blockers may compete over the same requests, causing slower page loading, broken websites, or video-playback problems. See <a href="https://adguard.com/en/adguard-browser-extension/opera/overview.html">AdGuard’s guidance</a>.

For wBlock specifically, another blocker also makes troubleshooting impossible as well. When an advertisement survives or a site breaks, either blocker’s network rules, cosmetic rules, scriptlets, exceptions, or execution order may be responsible. The second blocker is therefore a confounding variable. Disable all other content blockers before reporting a wBlock issue.

<br>

<img width="1560" height="176" alt="Skill Issue" src="https://github.com/user-attachments/assets/b9c519bf-bbc7-40c0-bc4c-6a6d1fccb488" />

Installing redundant blockers is not defense in depth when both tools compete at the same interception layer. It is an uncontrolled experiment with no control group.

</details>

<details>
<summary><b>Can I use my own filter lists?</b></summary>
<br>
Yes. You can add any AdGuard-compatible filter list by URL, paste rules directly, or import from a file.
</details>

<details>
<summary><b>Should I enable more filter lists for better blocking?</b></summary>
<br>
Usually not. The recommended defaults already cover most ads and trackers, and most other general-purpose lists overlap with them. Enabling more mainly uses up Safari's rule limit and increases the chance of site breakage. The exceptions are Annoyances filters (cookie banners, popups, social widgets) and regional filters for non-English sites, which cover things the defaults do not.
</details>

<details>
<summary><b>Does wBlock slow down Safari?</b></summary>
<br>
No in normal use. wBlock uses Safari's native declarative content blocking API, which applies compiled rules outside the app process. Local idle checks sit around ~40 MB, and page loading stays on Safari's native blocker path.
</details>

<details>
<summary><b>Do userscripts work on iOS and iPadOS?</b></summary>
<br>
Yes. The userscript engine implements common Greasemonkey APIs (GM_getValue, GM_setValue, GM_xmlhttpRequest, GM_addStyle) on iOS, iPadOS, and macOS via Safari Web Extensions.
</details>

<details>
<summary><b>How do I block Twitch ads?</b></summary>
<br>
wBlock bundles the <b>AdGuard Extra</b> userscript, which can help with Twitch ads by talking to Twitch's GraphQL API (gql.twitch.tv) — the same general approach uBlock Origin users rely on. It ships <b>disabled by default</b>, so enable it for Twitch:
<br><br>
1. Open wBlock and go to the <i>Userscripts</i> section.<br>
2. Find <b>AdGuard Extra</b> in the built-in list and toggle it on.<br>
3. Reload any open Twitch tabs.
<br><br>
This is best-effort, community-style ad blocking: Twitch frequently changes how ads are served, so it may occasionally break until the userscript is updated. There is no guarantee every ad is removed.
</details>

<details>
<summary><b>What are Tube Cleaner and Player Cleaner?</b></summary>
<br>
They are optional built-in userscripts, inspired by Vinegar and Baking Soda, that expose Safari's native controls on a site's existing media element. They ship disabled by default; enable them in the <i>Userscripts</i> section.
<br><br>
<b>Tube Cleaner</b> targets YouTube (including embeds). It lets YouTube create and initialize its own <code>&lt;video&gt;</code> and SABR/MSE stream, then applies native controls and hides YouTube's custom chrome before it can paint. Reusing the same media element preserves buffering and adaptive playback while restoring Picture-in-Picture and background playback. On iPhone and iPad, it leaves the interaction surface entirely to Safari's native controls and YouTube's adaptive quality, while preserving the remote-playback restriction WebKit requires for YouTube's ManagedMediaSource stream; the custom quality/audio-only toolbar remains a macOS feature. It also follows the active player as YouTube retains offscreen Shorts. Ads remain the responsibility of wBlock's content-blocking rules.
<br><br>
<b>Player Cleaner</b> targets custom players on other websites (video.js, JW Player, Plyr, Flowplayer, MediaElement, Clappr, Media Chrome/Mux, and more), including shadow-root players such as Archive.org's <code>&lt;play-av&gt;</code>. It enables native controls immediately. When a safe direct source is available in the light DOM, it removes the custom chrome while retaining the original media element; shadow components and opaque HLS/DASH/MSE pipelines remain intact and continue using the site's stream machinery. If a site misbehaves, disable Player Cleaner for that site from the wBlock toolbar.
</details>

<details>
<summary><b>Where do I find them, and what can I test them on?</b></summary>
<br>
Both ship disabled. Open the <i>Userscripts</i> tab: <i>Tube Cleaner</i> and <i>Player Cleaner</i> sit at the top of the <i>General</i> section. Switch one on, then reload the page you want to test. If they are not in the list, you are running a wBlock build from before this change — quit wBlock and run this branch from Xcode (a Homebrew or release install cannot contain branch code).
<br><br>
Tube Cleaner (YouTube and embeds):
<br>• <a href="https://www.youtube.com/watch?v=aqz-KE-bpKQ">Big Buck Bunny</a> — long, many qualities, good for the quality menu
<br>• <a href="https://www.youtube.com/watch?v=eRsGyueVLvQ">Sintel</a>
<br>• <a href="https://www.youtube.com/watch?v=R6MlUcmOul8">Tears of Steel</a>
<br>• Embeds: <a href="https://www.youtube.com/embed/aqz-KE-bpKQ">youtube.com/embed</a> and <a href="https://www.youtube-nocookie.com/embed/aqz-KE-bpKQ">youtube-nocookie.com/embed</a>
<br>Check that native controls appear without a flash of YouTube chrome, that the quality and audio-only controls work, that Picture-in-Picture works, and that audio keeps playing in another tab. Ad behavior depends on the enabled wBlock filter lists.
<br><br>
Player Cleaner (other sites' custom players), one demo per supported library:
<br>• video.js / Media Chrome — <a href="https://videojs.org/">videojs.org</a>
<br>• Plyr — <a href="https://plyr.io/">plyr.io</a>
<br>• JW Player — <a href="https://developer-tools.jwplayer.com/stream-tester">stream tester</a> and <a href="https://jwplayer.github.io/jwplayer/">demo</a>
<br>• Archive.org shadow-root JW Player — <a href="https://archive.org/details/gov.ntis.ava15996vnb1/0.theater.hd.splice.avi">FedFlix sample</a>
<br>• Clappr — <a href="http://clappr.io/">clappr.io</a> and <a href="http://cdn.clappr.io/">cdn.clappr.io</a>
<br>• MediaElement — <a href="https://www.mediaelementjs.com/">mediaelementjs.com</a>
<br>• hls.js — <a href="https://hlsjs.video-dev.org/demo/">hls.js demo</a>
<br>• dash.js — <a href="https://reference.dashif.org/dash.js/latest/samples/dash-if-reference-player/index.html">DASH reference player</a>
<br>Check that native controls appear promptly, Picture-in-Picture and fullscreen work, and playback does not restart when the custom chrome disappears. HLS/DASH/blob players may retain their stream pipeline while using native controls. If a site misbehaves, disable Player Cleaner for that site from the wBlock toolbar.
</details>

<details>
<summary><b>How often do filters update?</b></summary>
<br>
Auto-update intervals are configurable from 1 hour to 7 days, or manually triggered. On macOS, enabling auto-update registers a bundled launch agent that can keep checking while the app is closed through a background update service. On iOS and iPadOS, background checks are best-effort and may wait until the system wakes wBlock or you reopen it. Opening Safari does not trigger updates. Updates use HTTP conditional requests (If-Modified-Since/ETag headers) when servers support them, which reduces unnecessary downloads.
</details>

<details>
<summary><b>Is the element zapper available on iOS and iPadOS?</b></summary>
<br>
Yes. Open the wBlock extension popup in Safari and tap <i>Activate Element Zapper</i>.
</details>

<br>

---

<br>

<div align="center">

### Credits

**[@arjpar](https://github.com/arjpar)** · **[@ameshkov](https://github.com/ameshkov/safari-blocker)** · **[@shindgewongxj](https://github.com/shindgewongxj)**

<br>

[![Discord](https://img.shields.io/badge/Discord-Community-5865F2?style=flat&logo=discord&logoColor=white)](https://discord.gg/Y3yTFPpbXr)
[![Privacy](https://img.shields.io/badge/Privacy-Policy-gray?style=flat)](https://github.com/0xCUB3/wBlock/blob/main/PRIVACY_POLICY.md)
[![Issues](https://img.shields.io/badge/Report-Issues-orange?style=flat&logo=github)](https://github.com/0xCUB3/wBlock/issues)

<br>

Developed by [0xCUB3](https://github.com/0xCUB3)

<br>

</div>

---

<br>

<div align="center">

<a href="https://www.star-history.com/?repos=0xCUB3%2FwBlock&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=0xCUB3/wBlock&type=date&theme=dark&legend=top-left&sealed_token=hydrib30YBgUlJtwcs44Z07mfNGx1vckqpSj8pv-Emn7KxE5_VkKm30UqSh5heg8Exywqlnvluddhrev19za98t3LaTAfw3r-HRKoCEQXxWOau__ClFgyc7-fatyZrCg_SY_RkxP9viKeVLL8rOwmJ8Ihfi5EqV3urXIKtnrDVeDooGayP7uim27sLTY" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=0xCUB3/wBlock&type=date&legend=top-left&sealed_token=hydrib30YBgUlJtwcs44Z07mfNGx1vckqpSj8pv-Emn7KxE5_VkKm30UqSh5heg8Exywqlnvluddhrev19za98t3LaTAfw3r-HRKoCEQXxWOau__ClFgyc7-fatyZrCg_SY_RkxP9viKeVLL8rOwmJ8Ihfi5EqV3urXIKtnrDVeDooGayP7uim27sLTY" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=0xCUB3/wBlock&type=date&legend=top-left&sealed_token=hydrib30YBgUlJtwcs44Z07mfNGx1vckqpSj8pv-Emn7KxE5_VkKm30UqSh5heg8Exywqlnvluddhrev19za98t3LaTAfw3r-HRKoCEQXxWOau__ClFgyc7-fatyZrCg_SY_RkxP9viKeVLL8rOwmJ8Ihfi5EqV3urXIKtnrDVeDooGayP7uim27sLTY" />
 </picture>
</a>

</div>
