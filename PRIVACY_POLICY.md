# Privacy Policy for wBlock

Last updated: October 2026

## Introduction

wBlock is a privacy-focused content blocker for Safari on macOS, iOS, and iPadOS. This Privacy Policy explains how wBlock collects, uses, and protects your information. wBlock is designed with privacy as a core principle and operates entirely on your device without sending your browsing data to external servers.

If you turn on iCloud Sync, wBlock stores a copy of your configuration in your private iCloud database using Apple's CloudKit so it can sync across your devices. That database belongs to your Apple ID. The developer cannot read it.

## Developer Information

- **App Name:** wBlock
- **Developer:** Alexander Skula
- **Contact:** [Discord Server](https://discord.gg/5kmuEbwsut) or [GitHub Issues](https://github.com/0xCUB3/wBlock/issues)

## Information We Do NOT Collect

wBlock does not include its own analytics or crash-reporting service. The statements below describe the app's own data handling; Apple's separate [TestFlight collection](#testflight-beta-testing) applies to beta testing. wBlock does NOT collect, store, or transmit:

- Your browsing history
- Websites you visit
- Personal identifying information
- Usage analytics or telemetry
- Crash reports
- Device identifiers
- Location data
- Search queries

## Data Processed Locally on Your Device

wBlock processes the following data entirely on your device:

### 1. Content Blocking Rules
- **What:** Filter lists downloaded from third-party sources (AdGuard, EasyList, etc.)
- **Purpose:** To block ads, trackers, and unwanted content on websites you visit
- **Storage:** Stored locally in the app's shared container on your device
- **Processing:** Converted to Safari content blocking format locally on your device

### 2. Filter List Configuration
- **What:** Your selected filter lists, custom filters, and whitelist preferences
- **Purpose:** To remember your blocking preferences and apply them consistently
- **Storage:** Stored locally using Protocol Buffers format in the app's shared container
- **Sharing:** Not shared with the developer. If iCloud Sync is enabled, your configuration is stored in your private iCloud database for syncing.

### 3. Userscripts and Userstyles
- **What:** Userscripts and userstyles you add or enable, their per-site access settings, and preferences for built-in scripts (for example Tube Cleaner, DeArrow, and Player Cleaner feature switches)
- **Purpose:** To add features to the websites you choose
- **Storage:** Stored locally in the app's shared container
- **Downloads:** When you add a userscript, wBlock downloads it directly from the source URL you provide or select
- **Sharing:** Not shared with the developer. If iCloud Sync is enabled, script URLs, settings, and the content of scripts you imported from a file are stored in your private iCloud database for syncing.

### 4. Per-Site Settings
- **What:** Websites where you have disabled wBlock, content filtering, userscripts, or autoplay blocking, and sites where you allow or block autoplay
- **Purpose:** To respect your per-site preferences
- **Storage:** Stored locally in the app's shared container
- **Sharing:** Not shared with the developer. If iCloud Sync is enabled, these lists are stored in your private iCloud database for syncing.

### 5. Application Logs
- **What:** Debugging and diagnostic logs for troubleshooting
- **Purpose:** To help you diagnose issues with filter updates and script loading
- **Storage:** Stored locally on your device
- **Sharing:** Logs remain on your device and can be manually exported by you if needed for support
- **Content:** May include filter list names and URLs, userscript URLs, timestamps, and error messages, but not your browsing history or personal data

### 6. Element Zapper Data
- **What:** Elements you've chosen to permanently remove from websites, stored as the site's host name and a CSS selector
- **Purpose:** To remember your element blocking preferences
- **Storage:** Stored locally on your device
- **Sharing:** Not shared with the developer. If iCloud Sync is enabled, these rules are stored in your private iCloud database for syncing.

### 7. Onboarding and Settings
- **What:** Your app preferences, including onboarding status, notification preferences, auto-update settings, the toolbar badge counter, and appearance
- **Purpose:** To provide a personalized app experience
- **Storage:** Stored locally using Protocol Buffers in the app's shared container
- **Sharing:** Not shared with the developer. If iCloud Sync is enabled, your configuration is stored in your private iCloud database for syncing.

### 8. Settings Backups
- **What:** A backup file containing your filter selections, custom filter lists, per-site settings, Element Zapper rules, userscripts, and preferences
- **When:** Only when you export or import a backup in Settings
- **Storage:** Saved wherever you choose. wBlock does not upload backups anywhere.
- **SponsorBlock import:** If you import settings from the SponsorBlock extension, wBlock keeps only the skip categories, notice, minimum duration, and excluded channels. Anything else in that file, including your SponsorBlock user ID, is discarded.

## Network Requests Made by wBlock

wBlock makes network requests only for the following purposes:

### 1. Filter List Updates
- **What:** Downloads filter lists from public sources (e.g., AdGuard, EasyList)
- **When:** Only when you manually update filters or enable auto-update
- **Data Sent:** HTTP requests to filter list URLs (e.g., `https://filters.adtidy.org/`, `https://raw.githubusercontent.com/`)
- **Data Received:** Filter list content in text format
- **Mirrors:** If a list's primary source is unreachable, wBlock may retry a public mirror of the same file, such as jsDelivr or AdGuard's filter server. The Bypass Paywalls Clean filter list is served from a Cloudflare R2 bucket run by the developer, with a Cloudflare Worker as a fallback. These are plain file downloads with no identifiers attached, and the worker keeps no record of who downloaded the list.
- **Privacy:** Like any web request, the server can see your IP address and the file being requested. These requests do not include your browsing history or personal information

### 2. Userscript Downloads
- **What:** Downloads userscripts from public sources you specify
- **When:** Only when you add or update a userscript
- **Data Sent:** HTTP requests to userscript URLs (e.g., `https://userscripts.adtidy.org/`, `https://raw.githubusercontent.com/`, etc.)
- **Data Received:** JavaScript userscript content
- **Privacy:** These requests do not include your browsing history or personal information

### 3. @require Dependencies
- **What:** Downloads library dependencies required by userscripts
- **When:** Automatically downloaded when you add a userscript that declares @require directives
- **Data Sent:** HTTP requests to library URLs specified in the userscript
- **Data Received:** JavaScript library code
- **Privacy:** These requests do not include your browsing history or personal information

### 4. Built-In Script Services (Optional)
Some built-in userscripts contact third-party services while you browse the sites they work on. They are off by default and only run after you enable them:

- **Tube Cleaner** (SponsorBlock skipping) asks `sponsor.ajay.app` for skip segments using only the first characters of a hash of the YouTube video ID, not the ID itself
- **DeArrow** asks `sponsor.ajay.app` for titles using a hash prefix of the video ID and loads replacement thumbnails from `dearrow-thumb.ajay.app` using the video ID
- **Return YouTube Dislike** sends the video ID to `returnyoutubedislikeapi.com` to fetch like and dislike counts
- Userscripts can also make network requests allowed by their `@connect` rules

These services are run by third parties with their own privacy policies. wBlock does not send them any other data about you.

### 5. iCloud Sync (Optional)
- **What:** Syncs your wBlock configuration across devices using Apple CloudKit
- **When:** Only if you enable iCloud Sync in Settings
- **Data Sent:** Your selected filter lists, custom filter list URLs, userscript URLs and settings (and content for scripts imported from a file), per-site settings, autoplay settings, Element Zapper rules, and related app preferences
- **Data Received:** The same configuration data from your other devices
- **Privacy:** Stored in your private iCloud database under your Apple ID and not shared with the developer
- **Turning it off:** Turning off iCloud Sync stops syncing. The last synced copy stays in your iCloud account until you delete it in your Apple ID's iCloud settings

## Background Tasks

wBlock may perform background tasks on your device:

### Auto-Update Service (Optional)
- **What:** Automatic filter list checks and downloads
- **When:** If enabled by you, macOS can use a bundled launch agent and background update service while the app is closed. On iOS and iPadOS, checks use Apple's background task system, which is best-effort and may be delayed until the system wakes wBlock or you reopen it
- **Privacy:** Update checks are simple HTTP requests to filter list URLs and do not transmit your browsing data

### Launch Agent (macOS)
- **What:** A bundled launch agent that triggers the background filter update service
- **When:** Registered only while auto-update is enabled
- **Privacy:** Operates locally on your device without transmitting your data

## Third-Party Filter Lists

wBlock allows you to download and use filter lists from third-party sources including:

- AdGuard
- EasyList
- EasyPrivacy
- Fanboy's lists
- Peter Lowe's List
- Bypass Paywalls Clean
- And other community-maintained filter lists

**Important:** These filter lists are downloaded from their respective maintainers. wBlock is not responsible for the content or privacy practices of these third-party sources. The filter lists themselves do not track your browsing; they are simply rule sets that tell Safari what to block.

## Third-Party Userscripts

wBlock allows you to download and run userscripts from third-party sources. **Important considerations:**

- Userscripts are JavaScript code that runs in the context of web pages
- wBlock offers built-in userscripts including Tube Cleaner, DeArrow, Player Cleaner, Dark Reader, Return YouTube Dislike, Bypass Paywalls Clean, AdGuard Extra, TwitchAdSolutions, tinyShield, and AdGuard Popup Blocker. tinyShield is enabled by default on new installs. The others are off until you enable them
- You can add custom userscripts from any source
- **Privacy Warning:** Userscripts have access to web pages according to their @match patterns. Carefully review userscripts before enabling them
- wBlock is not responsible for the behavior or privacy practices of third-party userscripts
- You should only enable userscripts from sources you trust

## Safari Content Blocking API

wBlock uses Apple's Safari Content Blocking API:

- Content blocking rules are processed by Safari, not wBlock
- Safari handles all content blocking locally on your device
- wBlock's Safari web extension (used for userscripts, the Element Zapper, and the toolbar menu) runs only on sites you grant it access to in Safari, and it keeps what it sees on your device
- No data about your browsing is sent to the developer

## Data Sharing and Third Parties

wBlock does NOT:

- Sell your data to third parties
- Share your data with advertisers
- Transmit your browsing history to any server
- Use analytics or tracking services
- Include third-party advertising SDKs

## App Group Container

wBlock uses an App Group Container (`group.skula.wBlock`) to share data between:

- The main wBlock app
- Safari content blocker extensions
- The background filter update service

This sharing happens only locally on your device and is necessary for the app to function. No data leaves your device through this mechanism.

## Open Source

wBlock is open source software. You can review the source code at:
- **GitHub:** [https://github.com/0xCUB3/wBlock](https://github.com/0xCUB3/wBlock)

This transparency allows anyone to verify that wBlock operates as described in this privacy policy.

## Children's Privacy

wBlock does not knowingly collect or process information from children under 13 years of age. Since wBlock does not collect personal information at all, it can be safely used by users of all ages.

## Data Retention

wBlock does not upload your local configuration to the developer. Apple's retention of TestFlight data is described [below](#testflight-beta-testing). Filter lists, preferences, and userscripts stay on your device until you:

- Manually delete the data within the app
- Uninstall wBlock from your device
- Clear the app's data through device settings

If you used iCloud Sync, the synced copy stays in your private iCloud database until you delete it through your Apple ID's iCloud settings.

## Your Rights and Control

You have complete control over your data in wBlock:

- **Access:** All your data is stored locally and accessible within the app
- **Modification:** You can modify any settings, filter lists, or userscripts at any time
- **Deletion:** You can clear logs, remove filter lists, delete userscripts, or uninstall the app to delete all data
- **Export:** You can export logs for troubleshooting and export your settings as a backup file

## International Users

wBlock is designed to work globally. Processing happens locally on your device, and the developer runs no servers that store your data. If you turn on iCloud Sync, Apple stores your configuration under its iCloud terms.

## Compliance with Privacy Regulations

wBlock is designed to comply with major privacy regulations including:

- **GDPR (General Data Protection Regulation):** No personal data is collected or processed
- **CCPA (California Consumer Privacy Act):** No personal information is sold or shared
- **COPPA (Children's Online Privacy Protection Act):** No collection of children's data

Since wBlock does not collect personal information, most privacy regulation requirements are not applicable.

## Changes to This Privacy Policy

We may update this Privacy Policy from time to time. Changes will be posted in this document with an updated "Last Updated" date. Continued use of wBlock after changes constitutes acceptance of the revised Privacy Policy.

For major changes affecting how data is processed, we will make reasonable efforts to notify users through release notes and announcements in the Discord community.

## TestFlight Beta Testing

TestFlight is Apple's optional service for distributing signed beta builds and gathering feedback before a stable release. You can use the stable App Store or macOS DMG/Homebrew release without joining TestFlight.

[Apple's TestFlight privacy notice](https://www.apple.com/legal/privacy/data/en/test-flight/) says crash logs and usage information are automatically collected by Apple and shared with the developer. You cannot opt out of this collection while testing. This is separate from wBlock's own data handling.

Apple says your name and email address are not visible to the developer if you join through a public link only. You can still disclose personal information in feedback. Comments and screenshots you submit through TestFlight are shared with Apple and the developer. Apple can associate that feedback with your Apple Account.

Apple describes symbolicated crash logs and beta usage information, but does not guarantee that reports cannot contain sensitive content. Screenshots and comments you send can include private webpage content or other personal information. Review them before submitting. These documents do not establish routine collection of the webpages wBlock filters.

Apple says it retains beta feedback for one year and may retain crash logs and usage data until bugs are resolved. [Stopping testing](https://testflight.apple.com/) ends your participation; it is not a promise to delete previously collected data.

## Contact Information

If you have questions or concerns about this Privacy Policy or wBlock's privacy practices:

- **Discord:** [https://discord.gg/5kmuEbwsut](https://discord.gg/5kmuEbwsut)
- **GitHub Issues:** [https://github.com/0xCUB3/wBlock/issues](https://github.com/0xCUB3/wBlock/issues)

## Acknowledgments

wBlock is built on the work of many open-source projects and filter list maintainers:

- AdGuard filter lists and conversion libraries
- EasyList and other community filter lists
- Safari content blocking framework by Apple
- Third-party userscript developers

We are grateful to these contributors who make privacy-focused browsing possible.

---

## Summary

In simple terms, wBlock works on your device. It downloads the filter lists and userscripts you choose and applies them locally. It never sends your browsing history to the developer. If you opt in, iCloud Sync stores your settings in your own iCloud account, and a few built-in scripts ask their own services about the YouTube video you're watching. TestFlight beta testing has separate automatic crash-log and usage collection as described above.
