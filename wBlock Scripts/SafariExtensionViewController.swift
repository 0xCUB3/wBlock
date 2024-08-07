//  SafariExtensionViewController.swift
//  wBlock Scripts
//
//  Created by Alexander Skula on 7/18/24.
//

import SafariServices
import SwiftUI
import os.log

class SafariExtensionViewController: SFSafariExtensionViewController {
    
    private let logger = Logger(subsystem: "app.netlify.0xcube.wBlock.wBlockScripts", category: "ScriptInjection")
    
    static let shared: SafariExtensionViewController = {
        let shared = SafariExtensionViewController()
        shared.preferredContentSize = NSSize(width: 240, height: 150)
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
            Text("Script injection is working!")
                .font(.largeTitle)
                .padding()
            Text("Script injection is for blocking extra pesky ads, particularly on YouTube.")
                .font(.footnote)
                .padding()
        }
        .frame(width: 240, height: 150)
    }
}
