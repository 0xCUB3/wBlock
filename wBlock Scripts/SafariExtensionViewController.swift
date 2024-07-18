//  SafariExtensionViewController.swift
//  wBlock Scripts
//
//  Created by Alexander Skula on 7/18/24.
//

import SafariServices
import SwiftUI
import os.log

class SafariExtensionViewController: SFSafariExtensionViewController {
    
    private let logger = Logger(subsystem: "app.netlify.0xcube.wBlock.wBlock-Scripts", category: "ScriptInjection")
    
    static let shared: SafariExtensionViewController = {
        let shared = SafariExtensionViewController()
        shared.preferredContentSize = NSSize(width: 320, height: 240)
        return shared
    }()

    override func loadView() {
        view = NSHostingView(rootView: ContentView())
        logger.log("SafariExtensionViewController loadView called")
    }
}

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Hello World")
                .font(.largeTitle)
                .padding()
        }
        .frame(width: 320, height: 240)
    }
}
