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

![Version](https://img.shields.io/badge/v1.0.1-gray?style=flat&label=version)
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
A Safari content blocker for macOS, iOS, and iPadOS utilizing declarative content blocking rules.<br>
Supports 750,000 rules across 5 extensions with Protocol Buffer storage and LZ4 compression.
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

### Performance Architecture
- **750,000 rule capacity** utilizing 5 Safari content blocking extensions per platform (150k rules each)
- **~40 MB RAM footprint** at idle via Safari's native content blocking API
- **Protocol Buffers serialization** with LZ4 compression for filter storage
- **Off-thread I/O operations** with streaming serialization to minimize main thread blocking
- **HTTP conditional requests** (If-Modified-Since/ETag) for efficient filter update detection

### Content Modification
- **Element Zapper** (macOS only) generates persistent CSS selectors for manual element removal
- **Userscript engine** implements Greasemonkey API (GM_getValue, GM_setValue, GM_xmlhttpRequest)
- **Custom filter list ingestion** supports AdGuard-syntax blocklists via URL import
- **Category-based filter organization** with per-list toggle and automatic rule distribution
- **Filter list validation** with automatic disabling on Safari's 150k rule limit per extension

</td>
<td width="50%" valign="top">

### Blocking Capabilities
- **Network request blocking** via declarative content blocking rules (advertisements, trackers)
- **Cookie and local storage filtering** through Safari content blocker rule actions
- **CSS injection** for cosmetic filtering and element hiding
- **Script blocking** for unwanted software and JavaScript execution
- **Pop-up and redirect prevention** using Safari content blocking patterns

### Configuration & Management
- **Configurable auto-update intervals** from 1 hour to 7 days with background refresh
- **Per-site blocking controls** through Safari's content blocker enable/disable API
- **Whitelist management** for trusted domains with Safari extension state persistence
- **Regional filter support** with preset lists for language-specific content blocking
- **Filter compilation monitoring** with real-time rule count and compilation status
- **Background update notifications** (optional) for filter list refresh events

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
- SafariConverterLib v4.0.4 for AdGuard to Safari rule conversion
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

wBlock is free and open-source software. Financial contributions support ongoing development and maintenance:

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
Yes! wBlock supports any AdGuard-compatible filter list. Add the URL in Custom Filter Lists.
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
Not yet.
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
