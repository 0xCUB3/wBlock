//
//  UpdateController.swift
//  wBlock
//
//  Created by Alexander Skula on 7/20/24.
//

import Foundation
import SwiftUI
import UserNotifications
import os.log

@MainActor
class UpdateController: ObservableObject {
    static let shared = UpdateController()
       
    private let versionURL = "https://raw.githubusercontent.com/0xCUB3/Website/main/content/wBlock.txt"
    private let releasesURL = "https://github.com/0xCUB3/wBlock/releases"
    private let logger = Logger(subsystem: "com.0xcube.wBlock", category: "UpdateController")
       
    @Published var isCheckingForUpdates = false
    @Published var updateAvailable = false
    @Published var latestVersion: String?
       
    private var updateTimer: DispatchSourceTimer?
       
    private init() {}
       
    /// Schedules background updates for filter lists
    func scheduleBackgroundUpdates(filterListManager: FilterListManager) async {
        // Cancel existing timer if any
        updateTimer?.cancel()
        updateTimer = nil

        // Get the selected update interval
        let interval = UserDefaults.standard.double(forKey: "updateInterval")
        let updateInterval = interval > 0 ? interval : 86400 // Default to 1 day if not set

        // Log that we're scheduling background updates
        filterListManager.appendLog("Scheduling background updates with interval: \(updateInterval) seconds")

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(deadline: .now() + updateInterval, repeating: updateInterval)
        timer.setEventHandler { [weak self] in
            Task {
                await filterListManager.appendLog("Automatic update check started.")
                let updatedFilters = await filterListManager.autoUpdateFilters()
                if !updatedFilters.isEmpty {
                    await self?.sendUpdateNotification(updatedFilters: updatedFilters)
                } else {
                    await filterListManager.appendLog("No updates found during automatic update check.")
                }
            }
        }
        timer.resume()
        updateTimer = timer
    }
       
    /// Sends a user notification listing the updated filters
    private func sendUpdateNotification(updatedFilters: [FilterList]) async {
        let filterNames = updatedFilters.map { $0.name }.joined(separator: ", ")
        let content = UNMutableNotificationContent()
        content.title = "wBlock Filters Updated"
        content.body = "The following filters have been updated: \(filterNames)"
        content.sound = .default
           
        // Create the notification request
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
           
        // Schedule the notification
        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.debug("Notification scheduled successfully.")
        } catch {
            logger.error("Failed to schedule notification: \(error.localizedDescription)")
        }
    }
       
    /// Fetches the latest version string from the server
    private func fetchLatestVersion() async throws -> String {
        guard var urlComponents = URLComponents(string: versionURL) else {
            throw URLError(.badURL)
        }
           
        // Add a timestamp to prevent caching
        urlComponents.queryItems = [URLQueryItem(name: "t", value: "\(Date().timeIntervalSince1970)")]
           
        guard let url = urlComponents.url else {
            throw URLError(.badURL)
        }
           
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
           
        let (data, response) = try await URLSession.shared.data(for: request)
           
        if let httpResponse = response as? HTTPURLResponse {
            logger.debug("HTTP Status Code: \(httpResponse.statusCode)")
        }
           
        guard let versionString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw NSError(domain: "UpdateController", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse version data"])
        }
           
        return versionString
    }
       
    /// Opens the releases page in the default browser
    func openReleasesPage() {
        guard let url = URL(string: releasesURL) else {
            logger.error("Invalid releases URL")
            return
        }
           
        NSWorkspace.shared.open(url)
    }
}
