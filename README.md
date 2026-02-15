<div align="center">

<img src="https://github.com/user-attachments/assets/eaa6e163-0230-4458-a690-5c67e03df46a" alt="wBlock" width="120"/>

# wBlock

**The end of Safari ad-blocking B.S.**

<br>

<a href="https://apps.apple.com/app/wblock/id6746388723">
  <img src="https://upload.wikimedia.org/wikipedia/commons/3/3c/Download_on_the_App_Store_Badge.svg" alt="Download on the App Store" width="240"/>
</a>

<br>
<br>

![Version](https://img.shields.io/github/v/release/0xCUB3/wBlock?style=flat&label=version&color=gray)
![Platform](https://img.shields.io/badge/macOS_14+_|_iOS_17+-gray?style=flat&logo=apple&logoColor=white)
![License](https://img.shields.io/badge/GPL--3.0-gray?style=flat&label=license)

[![Join Discord](https://img.shields.io/badge/Join-Discord-5865F2?style=flat&logo=discord&logoColor=white)](https://discord.gg/Y3yTFPpbXr)

</div>

<br>
<br>

<div align="center">
<img src="https://github.com/user-attachments/assets/3fd411ac-f781-4db5-bd4e-4cea82edf3d7" alt="wBlock Interface" width="900"/>
</div>

<br>

<p align="center">
A Safari content blocker for macOS, iOS, and iPadOS.<br>
750,000 rules across 5 extensions, Protocol Buffer storage, LZ4 compression, iCloud sync.
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
- **Userscript engine** with Greasemonkey API (GM_getValue, GM_setValue, GM_xmlhttpRequest)
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

### Configuration
- **Auto-updates** from every hour to every 7 days, or manual — with background refresh on iOS
- **Per-site controls** — disable blocking on specific sites from the Safari toolbar
- **Blocked request logger** (macOS) — see what's being blocked on each page
- **Whitelist** for trusted domains
- **Regional filters** with auto-detection based on your locale
- **Homebrew cask** for macOS: `brew tap 0xcub3/wblock https://github.com/0xCUB3/wBlock && brew install --cask wblock`

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
<img src="https://github.com/user-attachments/assets/09c4cec5-14a0-4d12-a0de-1f6544162ceb" alt="Userscript Management" width="700"/>
<br><br>
<strong>Userscript Management</strong><br>
<em>Manage paywalls, YouTube Dislikes, and more</em>
</td>
</tr>
<tr>
<td align="center">
<img src="https://github.com/user-attachments/assets/0a9d0da5-b94a-42e6-880c-f0f9425b38a2" alt="Settings" width="700"/>
<br><br>
<strong>Settings & Customization</strong><br>
<em>Configure auto-updates, notifications, and preferences</em>
</td>
</tr>
<tr>
<td align="center">
<img src="https://github.com/user-attachments/assets/d8aafe2d-8ec2-493e-9a04-aa6d7bf9fb1f" alt="iOS" width="350"/>
<br><br>
<strong>iOS Interface</strong><br>
<em>Full-featured blocking on iPhone and iPad</em>
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
<td width="50%">

**Core Architecture**
- Protocol Buffers (libprotobuf) with LZ4 compression for filter serialization
- Asynchronous I/O with Swift concurrency (async/await, Task, Actor isolation)
- Streaming serialization to disk minimizes peak memory usage during compilation
- 5 Safari content blocking extensions per platform (maximum Safari API capacity)
- SafariServices framework integration for declarative content blocking

</td>
<td width="50%">

**Dependencies & Standards**
- SafariConverterLib v4.1.0 for AdGuard to Safari rule conversion
- AdGuard Scriptlets v2.2.9 for advanced blocking techniques
- Swift 5.9+ with strict concurrency checking enabled
- WCAG 2.1 AA compliance with full VoiceOver and Dynamic Type support
- SwiftProtobuf for cross-platform filter storage format

</td>
</tr>
</table>

---

<br>

<div align="center">

## Support Development

wBlock is free and open source. If you want to support the project:

<br>

<a href="https://opencollective.com/skula/projects/wblock">
  <img src="https://opencollective.com/about-this-hack/donate/button@2x.png?color=blue" width="250" />
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
Check out our <a href="Adblock_Comparison.md">comparison guide</a> vs uBlock Origin Lite, AdGuard, and Wipr.
</details>

<details>
<summary><b>Can I use my own filter lists?</b></summary>
<br>
Yes. You can add any AdGuard-compatible filter list by URL, paste rules directly, or import from a file.
</details>

<details>
<summary><b>Does wBlock slow down Safari?</b></summary>
<br>
No. wBlock uses Safari's native declarative content blocking API, which processes rules in a separate process. Memory overhead is ~40 MB at idle with no measurable impact on page load times.
</details>

<details>
<summary><b>Do userscripts work on iOS?</b></summary>
<br>
Yes. The userscript engine implements the Greasemonkey API (GM_getValue, GM_setValue, GM_xmlhttpRequest, GM_addStyle) on both iOS and macOS via Safari Web Extensions.
</details>

<details>
<summary><b>How often do filters update?</b></summary>
<br>
Auto-update intervals are configurable from 1 hour to 7 days, or manually triggered. Updates use HTTP conditional requests (If-Modified-Since/ETag headers) to minimize bandwidth usage.
</details>

<details>
<summary><b>Is the element zapper available on iOS?</b></summary>
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

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=0xCUB3/wBlock&type=Date)](https://star-history.com/#0xCUB3/wBlock&Date)

<br>

Developed by [0xCUB3](https://github.com/0xCUB3)

</div>
