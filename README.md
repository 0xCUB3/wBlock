> [!WARNING]
> **For a comparison between wBlock and other mainstream Safari ad blockers like uBlock Origin Lite, AdGuard for Safari, and Wipr, see [Adblock_Comparison.md](Adblock_Comparison.md).**


<p align="center">
  <img src="https://github.com/user-attachments/assets/eaa6e163-0230-4458-a690-5c67e03df46a" alt="wBlock Logo" width="128"/>
</p>

# wBlock: The end of Safari ad-blocking B.S.

<p align="center">
  <a href="https://apps.apple.com/app/wblock/id6746388723">
    <img src="https://img.shields.io/badge/iOS-App_Store-0D96F6?style=for-the-badge&logo=app-store&logoColor=white" alt="iOS App Store"/>
  </a>
  <a href="https://discord.gg/Y3yTFPpbXr">
    <img src="https://img.shields.io/badge/Discord-Join_Us-5865F2?style=for-the-badge&logo=discord&logoColor=white" alt="Discord"/>
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.0.1-blue?style=flat-square" alt="Version"/>
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 14+"/>
  <img src="https://img.shields.io/badge/iOS-17%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="iOS 17+"/>
  <img src="https://img.shields.io/badge/license-GPL--3.0-green?style=flat-square" alt="License"/>
</p>

<img width="982" height="834" alt="image" src="https://github.com/user-attachments/assets/3fd411ac-f781-4db5-bd4e-4cea82edf3d7" />

wBlock is a powerful content blocker for macOS, iOS, and iPadOS that cuts through the noise of the modern web. It delivers a clean and private browsing experience without the hassle and battery drain. Using AdGuard's filters and more, wBlock gives you the best of all worlds: high performance, low energy usage, and maximum blocking.

## Key Features

- **Massive Filter Capacity**: Up to 750,000 rules on macOS and iOS, far exceeding Safari's default limits
- **Lightning-Fast Performance**: Optimized for speed and efficiency (~40 MB of RAM at idle)
- **Comprehensive Protection**: Blocks ads, trackers, malware, and annoyances
- **Element Zapper**: Instantly and permanently remove unwanted content (cookie banners, modals) with a single click
- **Userscript Support**: Add features like Return YouTube Dislike, Bypass Paywalls Clean, and more
- **Auto-Updates**: Background filter updates with smart scheduling and efficient change detection
- **Full User Control**: Custom filter lists, whitelist management, per-site blocking toggle
- **Modern UI**: Beautiful liquid glass design with refined visual polish

### Join the Discord server: https://discord.gg/Y3yTFPpbXr

## Detailed Features

### Power User Tools
- **750k rules on macOS / 750k on iOS**: Industry-leading filter capacity using multiple content blocker extensions
- **Element Zapper**: Visual, one-click element removal with smart CSS selector suggestions
- **Userscript Engine**: Full Greasemonkey API with `@require` support for external dependencies
- **Custom Filter Lists**: Add any AdGuard-compatible filter list via URL
- **Advanced Filtering**: Category-based management with individual filter list toggling

### Control & Customization
- **Per-Site Toggle**: Instantly disable wBlock on specific websites
- **Whitelist Management**: Dedicated UI for adding, viewing, and removing whitelisted domains
- **Auto-Update Configuration**: Set intervals from 1 hour to 7 days, or disable entirely
- **Regional Filters**: Select filters optimized for your language and location during onboarding
- **Badge Counter Toggle**: Show/hide blocked item counts in Safari toolbar

### Quality of Life
- **Streamlined Apply Flow**: Automatic update checks before applying filters
- **Progress Tracking**: Detailed phase visualization (updating, processing, applying)
- **Comprehensive Logging**: Full diagnostics with clear indicators for easy scanning
- **Filter Timestamps**: Track when your blocking rules were last refreshed
- **Smart Notifications**: Alerts for available updates and filter application issues
- **Missing Filter Detection**: Easy installation prompts for recommended but missing filters

## Screenshots

<table>
  <tr>
    <td align="center" width="33%">
      <img src="https://github.com/user-attachments/assets/09c4cec5-14a0-4d12-a0de-1f6544162ceb" alt="Filter Management" style="width: 100%; height: 382px; object-fit: cover;"/>
      <br/>
      <strong>Filter Management</strong>
      <br/>
      <em>Organize filters by category with individual list toggling</em>
    </td>
    <td align="center" width="33%">
      <img src="https://github.com/user-attachments/assets/0a9d0da5-b94a-42e6-880c-f0f9425b38a2" alt="Settings & Customization" style="width: 100%; height: 382px; object-fit: cover;"/>
      <br/>
      <strong>Settings & Customization</strong>
      <br/>
      <em>Configure auto-updates, notifications, and preferences</em>
    </td>
    <td align="center" width="33%">
      <img src="https://github.com/user-attachments/assets/d8aafe2d-8ec2-493e-9a04-aa6d7bf9fb1f" alt="iOS Interface" style="width: 100%; height: 382px; object-fit: contain;"/>
      <br/>
      <strong>iOS Interface</strong>
      <br/>
      <em>Full-featured ad blocking on iPhone and iPad</em>
    </td>
  </tr>
</table>


### Benchmark Results

![CleanShot 2025-04-24 at 16 52 36](https://github.com/user-attachments/assets/d83e7bad-6240-46e7-94d3-cf7af8be51c5)
* Better than uBlock Origin!

![CleanShot 2025-04-24 at 16 53 30](https://github.com/user-attachments/assets/5504f841-e6fb-4359-9074-7d0fc23d5c48)


## Download

### iOS - Now Available on the App Store!

**Download from the App Store**: [wBlock on iOS](https://apps.apple.com/app/wblock/id6746388723)

### macOS - TestFlight (Temporary)

Apple has been rejecting the macOS App Store submission for unclear reasons, and appeals have been met with silence. The app is currently "in review," which prevents updating the existing TestFlight build.

**The current public TestFlight build is broken.** For a functioning build, please uninstall the current version and install the **alpha version**, which is currently stable:

**Alpha TestFlight (Stable)**: [Join TestFlight](https://testflight.apple.com/join/F93erUGR)

This is the last time you'll need to re-enroll in TestFlight. The App Store release should be approved soon.

Thank you for your patience and understanding during this frustrating review process. Your support means everything!

---

## System Requirements

- **macOS**: 14 Sonoma or newer
- **iOS/iPadOS**: 17 or newer

## Technical Highlights

### Performance & Architecture
- **Protocol Buffers Storage**: Off-thread serialization with LZ4 compression for blazing-fast data operations
- **Memory-Efficient Processing**: Streaming I/O with grouped filter processing prevents excessive memory usage
- **Throttled UI Updates**: Dedicated ViewModel prevents SwiftUI re-render freezing during intensive operations
- **Multiple Extension Architecture**: 5 content blocker extensions on iOS, 5 on macOS for maximum rule capacity

### Modern Development
- **SafariConverterLib v4.0.4**: Latest AdGuard converter for optimal filter compatibility
- **AdGuard Scriptlets v2.2.9**: Up-to-date scriptlet injection for advanced blocking
- **Async/Await Throughout**: Modern Swift concurrency for responsive UI
- **Accessibility First**: VoiceOver support with comprehensive accessibility labels

## Support wBlock's Development

wBlock is a free, open-source project dedicated to improving your browsing experience. If you find it valuable, consider supporting its developer and ongoing development:

<p align="center">
  <a href="https://opencollective.com/skula/projects/wblock" target="_blank">
    <img src="https://opencollective.com/about-this-hack/donate/button@2x.png?color=blue" width=300 />
  </a>
</p>

## Credits

- **[@arjpar](https://github.com/arjpar)** - Major contributions, especially with userscripts. Check out his ad blocker [WebShield](https://github.com/arjpar/WebShield)!
- **[@ameshkov](https://github.com/ameshkov/safari-blocker)** - Demo project that formed the basis for wBlock's advanced functionality
- **[@shindgewongxj](https://github.com/shindgewongxj)** - Beautiful icon design

## Links

- **Discord Community**: [Join the server](https://discord.gg/Y3yTFPpbXr)
- **Comparison Guide**: [wBlock vs. Other Ad Blockers](Adblock_Comparison.md)
- **Privacy Policy**: [View Policy](https://github.com/0xCUB3/wBlock/blob/main/PRIVACY.md)
- **Issue Tracker**: [Report Bugs & Request Features](https://github.com/0xCUB3/wBlock/issues)

## FAQ

**Q: How does wBlock compare to other Safari ad blockers?**
A: Check out our detailed [comparison guide](Adblock_Comparison.md) comparing wBlock to uBlock Origin Lite, AdGuard for Safari, and Wipr.

**Q: Why do I need to re-enroll in TestFlight for macOS?**
A: Apple's review process has been challenging. The current public build is broken, but the alpha build is stable. This is the last time you'll need to switch—the App Store release is pending approval.

**Q: Can I use my own filter lists?**
A: Yes! wBlock supports any AdGuard-compatible filter list. Just add the URL in the Custom Filter Lists section.

**Q: Does wBlock slow down Safari?**
A: No. wBlock uses Safari's native content blocking API, which is extremely efficient. It uses only ~40 MB of RAM at idle and has minimal performance impact.

**Q: Will userscripts work on iOS?**
A: Yes! Full userscript support with the Greasemonkey API is available on both iOS and macOS.

**Q: How often do filters update?**
A: You can configure auto-updates from 1 hour to 7 days, or disable them and update manually. wBlock uses HTTP headers to check for changes efficiently.

---

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=0xCUB3/wBlock&type=Date)](https://star-history.com/#0xCUB3/wBlock&Date)

Made with ❤️ by [0xCUB3](https://github.com/0xCUB3)
