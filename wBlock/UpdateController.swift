//
//  UpdateController.swift
//  wBlock
//
//  Created by Alexander Skula on 7/20/24.
//

import Foundation
import SwiftUI

@MainActor
class UpdateController: ObservableObject {
    static let shared = UpdateController()
    
    private let versionURL = "https://raw.githubusercontent.com/0xCUB3/Website/main/content/wBlock.txt"
    private let releasesURL = "https://github.com/0xCUB3/wBlock/releases"
    
    @Published var isCheckingForUpdates = false
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    
    private init() {}
    
    func checkForUpdates() async {
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        
        do {
            let versionString = try await fetchLatestVersion()
            latestVersion = versionString
            
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            
            print("Current version: \(currentVersion)")
            print("Latest version: \(versionString)")
            
            updateAvailable = versionString.compare(currentVersion, options: .numeric) == .orderedDescending
            print(updateAvailable ? "Update available" : "No update available")
        } catch {
            print("Error checking for updates: \(error.localizedDescription)")
        }
    }
    
    private func fetchLatestVersion() async throws -> String {
        guard var urlComponents = URLComponents(string: versionURL) else {
            throw URLError(.badURL)
        }
        
        urlComponents.queryItems = [URLQueryItem(name: "t", value: "\(Date().timeIntervalSince1970)")]
        
        guard let url = urlComponents.url else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("HTTP Status Code: \(httpResponse.statusCode)")
        }
        
        guard let versionString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw NSError(domain: "UpdateController", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse version data"])
        }
        
        return versionString
    }
    
    func openReleasesPage() {
        guard let url = URL(string: releasesURL) else {
            print("Invalid releases URL")
            return
        }
        
        NSWorkspace.shared.open(url)
    }
}
