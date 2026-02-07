//
//  ContentView.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)

                Text("wBlock")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Spacer(minLength: 0)

                Button(action: openSafariExtensionsSettings) {
                    Label("Open Safari Settings", systemImage: "gear")
                }
                .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Finish setup")
                    .font(.headline)

                #if os(macOS)
                Text("1. Safari → Settings → Extensions")
                #else
                Text("1. Settings → Apps → Safari → Extensions")
                #endif

                (
                    Text("2. Enable ")
                    + Text("wBlock").fontWeight(.semibold)
                    + Text(" and set it to ")
                    + Text("Always Allow on All Websites").fontWeight(.semibold)
                    + Text(".")
                )
                .fixedSize(horizontal: false, vertical: true)
            }

            Text("Ads and trackers are blocked directly by the Safari WebExtension.")
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func openSafariExtensionsSettings() {
        #if os(macOS)
        let runningApps = NSWorkspace.shared.runningApplications
        if let safariApp = runningApps.first(where: { $0.bundleIdentifier == "com.apple.Safari" }) {
            safariApp.activate()

            let script = """
            tell application \"Safari\"
                activate
            end tell
            tell application \"System Events\"
                tell process \"Safari\"
                    click menu item \"Settings…\" of menu \"Safari\" of menu bar 1
                end tell
            end tell
            """

            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if error != nil {
                    safariApp.activate()
                }
            }
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Safari.app"))
        }
        #else
        if let url = URL(string: "App-prefs:SAFARI&path=EXTENSIONS") {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "App-prefs:") {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

#Preview {
    ContentView()
}
