# Privacy Policy for wBlock

**Last Updated:** October 2025

## Introduction

wBlock is a privacy-focused content blocker for Safari on macOS, iOS, and iPadOS. This Privacy Policy explains how wBlock collects, uses, and protects your information. wBlock is designed with privacy as a core principle and operates entirely on your device without sending your browsing data to external servers.

If you enable **iCloud Sync**, wBlock will store and transmit a copy of your configuration using Apple’s iCloud/CloudKit so it can sync across your devices. This data is stored in your private iCloud database under your Apple ID.

## Developer Information

- **App Name:** wBlock
- **Developer:** Alexander Skula
- **Contact:** [Discord Server](https://discord.gg/5kmuEbwsut)

## Information We Do NOT Collect

wBlock is designed to respect your privacy. We do NOT collect, store, or transmit:

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

### 3. Userscript Data
- **What:** Userscripts you choose to download and enable (e.g., Return YouTube Dislike, Bypass Paywalls Clean)
- **Purpose:** To enhance your browsing experience with additional functionality
- **Storage:** Stored locally in the app's userscripts directory
- **Downloads:** When you add a userscript, wBlock downloads it directly from the source URL you provide or select

### 4. Whitelist and Disabled Sites
- **What:** List of websites where you have disabled wBlock
- **Purpose:** To respect your per-site preferences
- **Storage:** Stored locally in UserDefaults within the app's shared container
- **Sharing:** Not shared with the developer. If iCloud Sync is enabled, your configuration is stored in your private iCloud database for syncing.

### 5. Application Logs
- **What:** Debugging and diagnostic logs for troubleshooting
- **Purpose:** To help you diagnose issues with filter updates and script loading
- **Storage:** Stored locally on your device
- **Sharing:** Logs remain on your device and can be manually exported by you if needed for support
- **Content:** May include filter names, timestamps, error messages, but NO browsing history or personal data

### 6. Element Zapper Data
- **What:** Elements you've chosen to permanently remove from websites
- **Purpose:** To remember your element blocking preferences
- **Storage:** Stored locally on your device
- **Sharing:** Never shared or transmitted

### 7. Onboarding and Settings
- **What:** Your app preferences including whether you've completed onboarding, notification preferences, and auto-update settings
- **Purpose:** To provide a personalized app experience
- **Storage:** Stored locally using Protocol Buffers in the app's shared container
- **Sharing:** Not shared with the developer. If iCloud Sync is enabled, your configuration is stored in your private iCloud database for syncing.

## Network Requests Made by wBlock

wBlock makes network requests only for the following purposes:

### 1. Filter List Updates
- **What:** Downloads filter lists from public sources (e.g., AdGuard, EasyList)
- **When:** Only when you manually update filters or enable auto-update
- **Data Sent:** HTTP requests to filter list URLs (e.g., `https://filters.adtidy.org/`)
- **Data Received:** Filter list content in text format
- **Privacy:** These requests are standard HTTP/HTTPS requests and do not include your browsing history or personal information

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

### 4. iCloud Sync (Optional)
- **What:** Syncs your wBlock configuration across devices using Apple CloudKit
- **When:** Only if you enable iCloud Sync in Settings
- **Data Sent:** Your selected filter lists, custom filter list URLs, userscripts configuration (and content for local/imported scripts), whitelist domains, and related app preferences
- **Data Received:** The same configuration data from your other devices
- **Privacy:** Stored in your private iCloud database under your Apple ID and not shared with the developer

## Background Tasks

wBlock may perform background tasks on your device:

### Auto-Update Service (Optional)
- **What:** Automatic filter list updates
- **When:** If enabled by you, wBlock can check for filter updates in the background
- **Privacy:** Update checks are simple HTTP requests to filter list URLs and do not transmit your browsing data

### Launch Agent (macOS)
- **What:** Background filter update process on macOS
- **When:** Runs when auto-update is enabled
- **Privacy:** Operates locally on your device without transmitting your data

## Third-Party Filter Lists

wBlock allows you to download and use filter lists from third-party sources including:

- AdGuard
- EasyList
- EasyPrivacy
- Fanboy's Lists
- Peter Lowe's List
- And other community-maintained filter lists

**Important:** These filter lists are downloaded from their respective maintainers. wBlock is not responsible for the content or privacy practices of these third-party sources. The filter lists themselves do not track your browsing; they are simply rule sets that tell Safari what to block.

## Third-Party Userscripts

wBlock allows you to download and run userscripts from third-party sources. **Important considerations:**

- Userscripts are JavaScript code that runs in the context of web pages
- wBlock provides default userscripts (disabled by default) including Return YouTube Dislike, Bypass Paywalls Clean, YouTube Classic, and AdGuard Extra
- You can add custom userscripts from any source
- **Privacy Warning:** Userscripts have access to web pages according to their @match patterns. Carefully review userscripts before enabling them
- wBlock is not responsible for the behavior or privacy practices of third-party userscripts
- You should only enable userscripts from sources you trust

## Safari Content Blocking API

wBlock uses Apple's Safari Content Blocking API:

- Content blocking rules are processed by Safari, not wBlock
- wBlock cannot see which websites you visit or what content is blocked
- Safari handles all content blocking locally on your device
- No data about your browsing is sent to wBlock or any external server

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

Since wBlock does not collect or transmit your personal data, there is no data retention policy for user information. All data (filter lists, preferences, userscripts) is stored locally on your device and remains there until you:

- Manually delete the data within the app
- Uninstall wBlock from your device
- Clear the app's data through device settings

## Your Rights and Control

You have complete control over your data in wBlock:

- **Access:** All your data is stored locally and accessible within the app
- **Modification:** You can modify any settings, filter lists, or userscripts at any time
- **Deletion:** You can clear logs, remove filter lists, delete userscripts, or uninstall the app to delete all data
- **Export:** You can export logs for troubleshooting purposes

## International Users

wBlock is designed to work globally. Since all processing happens locally on your device:

- No data is transferred internationally
- No data is stored on servers in any jurisdiction
- You maintain complete control over your data regardless of your location

## Compliance with Privacy Regulations

wBlock is designed to comply with major privacy regulations including:

- **GDPR (General Data Protection Regulation):** No personal data is collected or processed
- **CCPA (California Consumer Privacy Act):** No personal information is sold or shared
- **COPPA (Children's Online Privacy Protection Act):** No collection of children's data

Since wBlock does not collect personal information, most privacy regulation requirements are not applicable.

## Changes to This Privacy Policy

We may update this Privacy Policy from time to time. Changes will be posted in this document with an updated "Last Updated" date. Continued use of wBlock after changes constitutes acceptance of the revised Privacy Policy.

For major changes affecting how data is processed, we will make reasonable efforts to notify users through:
- Update notes in the app
- Announcements in the Discord community

## TestFlight Beta Testing

If you participate in wBlock's TestFlight beta program:

- Apple may collect crash logs and diagnostic data according to Apple's TestFlight privacy policy
- This is managed by Apple, not wBlock
- You can control TestFlight data sharing in your device settings

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

**In simple terms:** wBlock is a privacy-first app that works entirely on your device. It downloads filter lists and userscripts you choose, applies them locally, and never sends your browsing data anywhere. You maintain complete control over all data, and nothing about your web browsing leaves your device.
