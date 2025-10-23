<div align="center">

<img src="https://github.com/user-attachments/assets/eaa6e163-0230-4458-a690-5c67e03df46a" alt="wBlock" width="120"/>

# wBlock

**The end of Safari ad-blocking B.S.**

<br>

[![Download on App Store](https://img.shields.io/badge/Download_on-App_Store-black?style=flat&logo=apple&logoColor=white)](https://apps.apple.com/app/wblock/id6746388723)
[![Join Discord](https://img.shields.io/badge/Join-Discord-5865F2?style=flat&logo=discord&logoColor=white)](https://discord.gg/Y3yTFPpbXr)

![Version](https://img.shields.io/badge/v1.0.1-gray?style=flat&label=version)
![Platform](https://img.shields.io/badge/macOS_14+_|_iOS_17+-gray?style=flat&logo=apple&logoColor=white)
![License](https://img.shields.io/badge/GPL--3.0-gray?style=flat&label=license)

</div>

<br>
<br>

<div align="center">
<img src="https://github.com/user-attachments/assets/3fd411ac-f781-4db5-bd4e-4cea82edf3d7" alt="wBlock Interface" width="900"/>
</div>

<br>

<p align="center">
A powerful content blocker for macOS, iOS, and iPadOS that cuts through the noise of the modern web.<br>
High performance, low energy usage, maximum blocking.
</p>

<br>

<div align="center">

## ✨ Features

</div>

<table>
<tr>
<td width="50%" valign="top">

### 🚀 Performance
- **750,000 rules** on macOS & iOS
- **~40 MB RAM** at idle
- **Protocol Buffers** storage
- **LZ4 compression** for speed

### 🎯 Power Tools
- **Element Zapper** with CSS selector
- **Userscripts** with Greasemonkey API
- **Custom filter lists** support
- **Category-based** management

</td>
<td width="50%" valign="top">

### 🛡️ Protection
- **Ad blocking** across all sites
- **Tracker prevention**
- **Malware protection**
- **Annoyance filtering**

### ⚙️ Control
- **Auto-updates** (1hr - 7 days)
- **Per-site toggle**
- **Whitelist manager**
- **Regional filters**

</td>
</tr>
</table>

<br>

<div align="center">

> **Want to see how wBlock stacks up?** Check out our [comparison guide](Adblock_Comparison.md) vs uBlock Origin Lite, AdGuard, and Wipr.

</div>

<br>

---

<br>

<div align="center">

## 📸 Screenshots

<br>

<table>
<tr>
<td align="center">
<img src="https://github.com/user-attachments/assets/09c4cec5-14a0-4d12-a0de-1f6544162ceb" alt="Filter Management" width="700"/>
<br><br>
<strong>Filter Management</strong><br>
<em>Organize by category with individual list toggling</em>
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

## 📥 Download

<br>

### iOS

[![App Store](https://img.shields.io/badge/Download-App_Store-black?style=for-the-badge&logo=apple&logoColor=white)](https://apps.apple.com/app/wblock/id6746388723)

<br>

### macOS

> **Note:** Apple is currently blocking the App Store release. The public TestFlight is broken. There is currently no reliable way to run wBlock. Hopefully, the app review process will be finished soon. 

</div>

<br>

---

<br>

<div align="center">

## 🏗️ Technical Highlights

</div>

<table>
<tr>
<td width="50%">

**Performance & Architecture**
- Protocol Buffers with LZ4 compression
- Off-thread serialization
- Streaming I/O for memory efficiency
- 5 extensions per platform (max capacity)

</td>
<td width="50%">

**Modern Stack**
- SafariConverterLib v4.0.4
- AdGuard Scriptlets v2.2.9
- Swift async/await concurrency
- Full VoiceOver accessibility

</td>
</tr>
</table>

---

<br>

<div align="center">

## 💖 Support Development

wBlock is free and open-source. If you find it valuable, consider supporting its development:

<br>

<a href="https://opencollective.com/skula/projects/wblock">
  <img src="https://opencollective.com/about-this-hack/donate/button@2x.png?color=blue" width="250" />
</a>

</div>

<br>

---

<br>

<div align="center">

## ❓ FAQ

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
No. Uses Safari's native content blocking API (~40 MB RAM at idle, minimal performance impact).
</details>

<details>
<summary><b>Do userscripts work on iOS?</b></summary>
<br>
Yes! Full Greasemonkey API support on both iOS and macOS.
</details>

<details>
<summary><b>How often do filters update?</b></summary>
<br>
Configure auto-updates from 1 hour to 7 days, or manually. Uses HTTP headers for efficient change detection.
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

### 🙏 Credits

**[@arjpar](https://github.com/arjpar)** · **[@ameshkov](https://github.com/ameshkov/safari-blocker)** · **[@shindgewongxj](https://github.com/shindgewongxj)**

<br>

[![Discord](https://img.shields.io/badge/Discord-Community-5865F2?style=flat&logo=discord&logoColor=white)](https://discord.gg/Y3yTFPpbXr)
[![Privacy](https://img.shields.io/badge/Privacy-Policy-gray?style=flat)](https://github.com/0xCUB3/wBlock/blob/main/PRIVACY.md)
[![Issues](https://img.shields.io/badge/Report-Issues-orange?style=flat&logo=github)](https://github.com/0xCUB3/wBlock/issues)

<br>

## ⭐ Star History

[![Star History Chart](https://api.star-history.com/svg?repos=0xCUB3/wBlock&type=Date)](https://star-history.com/#0xCUB3/wBlock&Date)

<br>

Made with ❤️ by [0xCUB3](https://github.com/0xCUB3)

</div>
