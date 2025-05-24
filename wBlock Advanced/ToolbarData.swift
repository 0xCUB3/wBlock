//
//  ToolbarData.swift
//  safari-blocker
//
//  Created by Andrey Meshkov on 02/02/2025.
//
//  This file manages the tracking and persistence of blocked network
//  requests on Safari tabs. It groups rapid updates together, evicts stale
//  data after a given time period, and safely coordinates access using an actor.
import Foundation
import SafariServices

/// An actor that tracks the number of blocked requests per Safari tab.
/// Using an actor ensures that our state is safe from concurrent modifications.
actor ToolbarData {
    // Define how long an entry stays before it's considered outdated.
    private static let evictionDelay: Double = 24 * 60 * 60  // 24 hours

    // Delay used to batch disk writes (persisting data) to avoid writing too often.
    private static let flushDelay: UInt64 = 5 * 1_000_000_000  // 5 seconds

    // The key under which the blocked requests data will be stored in UserDefaults.
    private static let userDefaultsKey = "tabBlockedRequests"

    // Singleton instance for shared access to ToolbarData.
    public static let shared = ToolbarData()

    /// A simple structure to keep track of data for each tab.
    /// It is Codable so that it can be easily saved to and restored from UserDefaults.
    struct TabData: Codable {
        // Unique identifier for the tab.
        var key: String = ""
        // The number of blocked network requests on the tab.
        var blockedCount: Int = 0
        // The URL of the tab (stored as a string).
        var url: String = ""
        // A timestamp indicating when the data was last updated.
        var lastTimeUpdated: Double = Date().timeIntervalSince1970
    }

    // A dictionary mapping each tab's unique key to its corresponding TabData.
    private var tabBlockedRequests: [String: TabData] = [:]
    // A flag to indicate that there are changes that haven't yet been saved.
    private var tabBlockedRequestsDirty: Bool = false

    /// Private initializer, which attempts to restore previously saved data
    /// from UserDefaults so that the app can continue from its last state.
    private init() {
        // Attempt to load persisted data using the predefined key.
        if let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
            let dictionary = try? JSONDecoder().decode([String: TabData].self, from: data)
        {
            tabBlockedRequests = dictionary
        }
    }

    /// Schedules saving of the tab blocked requests data after a flush delay.
    ///
    /// This debouncing technique batches quick, successive updates and avoids
    /// frequent writes to UserDefaults.
    func scheduleSaveTabBlockedRequests() {
        Task {
            // Wait for the flushDelay (5 seconds) before proceeding.
            try? await Task.sleep(nanoseconds: Self.flushDelay)
            // If there are no pending changes, exit early.
            if !tabBlockedRequestsDirty {
                return
            }
            // Mark that changes are now being saved.
            tabBlockedRequestsDirty = false
            saveTabBlockedRequests()
        }
    }

    /// Serializes the current tab data and persists it to UserDefaults.
    ///
    /// Before saving, it cleans-up entries that are older than evictionDelay,
    /// ensuring that stale data does not accumulate.
    func saveTabBlockedRequests() {
        let now = Date().timeIntervalSince1970

        // Iterating over a copy of the keys to safely remove outdated entries.
        for key in Array(tabBlockedRequests.keys) {
            if let value = tabBlockedRequests[key], now - value.lastTimeUpdated > Self.evictionDelay
            {
                tabBlockedRequests.removeValue(forKey: key)
            }
        }

        // Encode the dictionary and save to persistent storage.
        if let data = try? JSONEncoder().encode(tabBlockedRequests) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    /// Updates the blocked request count on a given Safari page.
    ///
    /// It retrieves the tab's unique identifier and data, and either increments an
    /// existing count (if the URL hasn't changed) or resets the count for a new URL.
    /// It then marks the data as dirty and schedules a save.
    ///
    /// - Parameters:
    ///   - page: The Safari page on which a request was blocked.
    ///   - count: The number of blocked requests to account for.
    func trackBlocked(on page: SFSafariPage, count: Int) async {
        let tab = await page.containingTab()

        // Retrieve the current data for the specified tab.
        guard var tabData = await getTabData(for: tab) else {
            return
        }

        // Compare with any previously stored data for consistency.
        if let currentTabData = tabBlockedRequests[tabData.key],
            tabData.url == currentTabData.url
        {
            tabData.blockedCount = currentTabData.blockedCount + count
        } else {
            tabData.blockedCount = count
        }

        // Update the stored data for this tab.
        tabBlockedRequests[tabData.key] = tabData

        // Mark that our data is modified and that we need to persist these changes.
        tabBlockedRequestsDirty = true
        scheduleSaveTabBlockedRequests()
    }

    /// Resets the blocked request count for the given page.
    ///
    /// This reset is applied only if the page is confirmed to be the active page
    /// in its containing tab. After a reset, scheduling persists the updated state.
    ///
    /// - Parameter page: The Safari page to reset.
    func resetBlocked(on page: SFSafariPage) async {
        let tab = await page.containingTab()
        let activePage = await tab.activePage()

        // Only proceed if the page being reset is the tab's active page.
        if page == activePage {
            if let tabData = await getTabData(for: tab) {
                tabBlockedRequests[tabData.key] = tabData

                // Mark and schedule a save to update the persisted data.
                tabBlockedRequestsDirty = true
                scheduleSaveTabBlockedRequests()
            }
        }
    }

    /// Retrieves the number of blocked requests for the current active tab
    /// within a given Safari window.
    ///
    /// - Parameter window: The Safari window from which to obtain the active tab.
    /// - Returns: The blocked request count for the active tab; returns 0 if not found.
    func getBlockedOnActiveTab(in window: SFSafariWindow) async -> Int {
        guard let tab = await window.activeTab() else {
            return 0
        }

        let tabKey = tab.tabKey()
        return tabBlockedRequests[tabKey]?.blockedCount ?? 0
    }

    /// Fetches the current state for a given tab and packages it into TabData.
    ///
    /// This method gathers the tab's unique key and the URL from its active page,
    /// and also resets the timestamp to the current time.
    ///
    /// - Parameter tab: The Safari tab for which the data is needed.
    /// - Returns: TabData representing the current state of the tab.
    private func getTabData(for tab: SFSafariTab) async -> TabData? {
        let activePage = await tab.activePage()
        let props = await activePage?.properties()

        var tabData = TabData()
        tabData.url = props?.url?.absoluteString ?? ""
        tabData.key = tab.tabKey()

        return tabData
    }
}

// MARK: - SFSafariTab Extension to Generate Unique Key

extension SFSafariTab {
    /// Generates a unique key for the Safari tab.
    ///
    /// The key is generated by archiving the tab (using secure coding) and then
    /// converting the data to a Base64 encoded string. This key is used in our
    /// data dictionary to uniquely identify each tab across sessions.
    ///
    /// - Returns: A Base64 encoded string that uniquely represents the tab.
    func tabKey() -> String {
        if let archivedData = try? NSKeyedArchiver.archivedData(
            withRootObject: self,
            requiringSecureCoding: true
        ) {
            return archivedData.base64EncodedString(options: [])
        }
        return ""
    }
}
