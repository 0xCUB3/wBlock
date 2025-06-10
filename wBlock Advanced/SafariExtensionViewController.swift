//
//  SafariExtensionViewController.swift
//  wBlock Advanced
//
//  Created by Alexander Skula on 5/23/25.
//

import AppKit
import SafariServices

class SafariExtensionViewController: SFSafariExtensionViewController {
    // MARK: - Properties

    /// The shared instance of the view controller
    static let shared: SafariExtensionViewController = {
        let shared = SafariExtensionViewController()
        shared.preferredContentSize = NSSize(width: 300, height: 120)
        return shared
    }()

    private let headerLabel = NSTextField()
    private let contentLabel = NSTextField()
    private var blockedCount: Int = 0

    // MARK: - Lifecycle

    /// Called when the view is loaded
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    // MARK: - Public Methods

    /// Updates the blocked count and refreshes the UI
    ///
    /// - Parameter count: The number of blocked requests
    func updateBlockedCount(_ count: Int) {
        blockedCount = count
        updateContentLabel()
    }

    // MARK: - UI Setup

    /// Sets up the UI components
    private func setupUI() {
        // Set up the background
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Set a fixed width to ensure the popover respects our preferred size
        view.setFrameSize(NSSize(width: 300, height: 120))

        // Configure header label
        configureHeaderLabel()

        // Configure content label
        configureContentLabel()

        // Add constraints
        setupConstraints()
    }

    /// Configures the header label
    private func configureHeaderLabel() {
        headerLabel.stringValue = "App Extension"
        headerLabel.font = NSFont.boldSystemFont(ofSize: 18)
        headerLabel.isBezeled = false
        headerLabel.isEditable = false
        headerLabel.isSelectable = false
        headerLabel.drawsBackground = false
        headerLabel.alignment = .center
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLabel)
    }

    /// Configures the content label
    private func configureContentLabel() {
        updateContentLabel()
        contentLabel.font = NSFont.systemFont(ofSize: 14)
        contentLabel.isBezeled = false
        contentLabel.isEditable = false
        contentLabel.isSelectable = false
        contentLabel.drawsBackground = false
        contentLabel.alignment = .center
        contentLabel.lineBreakMode = .byWordWrapping
        contentLabel.usesSingleLineMode = false
        contentLabel.cell?.wraps = true
        contentLabel.cell?.isScrollable = false
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentLabel)
    }

    /// Updates the content label with the current blocked count
    private func updateContentLabel() {
        let text: String
        if blockedCount == 0 {
            text = "No requests have been blocked on this page."
        } else if blockedCount == 1 {
            text = "1 request was blocked on this page by Safari Content Blocker."
        } else {
            text = "\(blockedCount) requests were blocked on this page by Safari Content Blocker."
        }
        contentLabel.stringValue = text
    }

    /// Sets up the layout constraints
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Header label constraints
            headerLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 15),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
            headerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -15),
            headerLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 270),

            // Content label constraints
            contentLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 10),
            contentLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
            contentLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -15),
            contentLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 270),
            contentLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: view.bottomAnchor,
                constant: -15
            ),
        ])
    }
}
