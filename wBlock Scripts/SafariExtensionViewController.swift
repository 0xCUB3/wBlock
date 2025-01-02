//  SafariExtensionViewController.swift
//  wBlock Scripts
//
//  Created by Alexander Skula on 7/18/24.
//

import SafariServices
import SwiftUI
import os.log

final class SafariExtensionViewController: SFSafariExtensionViewController {
    private let logger = Logger(subsystem: "com.0xcube.wBlock.wBlockScripts", category: "ViewController")

    static let shared: SafariExtensionViewController = {
        let shared = SafariExtensionViewController()
        shared.preferredContentSize = NSSize(width: 240, height: 150)
        return shared
    }()

    override func loadView() {
        view = NSHostingView(rootView: ExtensionContentView())
        logger.debug("View loaded successfully")
    }
}

struct ExtensionContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Script injection is working!")
                .font(.headline)

            Text("Blocking extra ads on YouTube and other sites")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(width: 240, height: 150)
    }
}
