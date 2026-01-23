//
//  SafariExtensionViewController.swift
//  wBlock Advanced
//
//  Created by Alexander Skula on 5/23/25.
//

import AppKit
import SafariServices
import SwiftUI
import wBlockCoreService

class SafariExtensionViewController: SFSafariExtensionViewController {
    // MARK: - Properties

    /// The shared instance of the view controller
    static let shared: SafariExtensionViewController = {
        let shared = SafariExtensionViewController()
        // Leave extra vertical room for optional sections (logger + zapper rules).
        shared.preferredContentSize = NSSize(width: 320, height: 420)
        return shared
    }()

    private var hostingView: NSHostingView<PopoverView>!
    private var viewModel: PopoverViewModel!

    // MARK: - Lifecycle

    /// Called when the view is loaded
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        Task { await self.viewModel.loadState() }
    }

    // MARK: - Public Methods

    /// Updates the blocked count and refreshes the UI
    ///
    /// - Parameter count: The number of blocked requests
    func updateBlockedCount(_ count: Int) {
        viewModel.blockedCount = count
    }
    
    /// Updates the blocked request URL log for the active tab.
    func updateBlockedRequests(_ urls: [String]) {
        viewModel.blockedRequests = urls
    }

    // MARK: - UI Setup

    /// Embeds modern SwiftUI popover UI
    private func setupUI() {
        viewModel = PopoverViewModel()
        let popoverRoot = PopoverView(viewModel: viewModel)
        hostingView = NSHostingView(rootView: popoverRoot)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    // Legacy loadCurrentSiteState removed; state handled via ViewModel within SwiftUI view
}
