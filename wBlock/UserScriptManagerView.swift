//
//  UserScriptManagerView.swift
//  wBlock
//
//  Created by Alexander Skula on 6/7/25.
//

import SwiftUI
import wBlockCoreService
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct UserScriptManagerView: View {
    @ObservedObject var userScriptManager: UserScriptManager

    @State private var scripts: [UserScript] = []
    @State private var isLoading: Bool = false
    @State private var isRefreshing: Bool = false
    @State private var refreshProgress: Double = 0.0
    @State private var refreshStatus: String = ""
    @State private var showingRefreshProgress = false
    @State private var statusDescription: String = ""
    @State private var showingAddScriptSheet = false
    @State private var selectedScript: UserScript?
    @State private var showOnlyEnabled = false

    private var totalScriptsCount: Int {
        scripts.count
    }

    private var enabledScriptsCount: Int {
        scripts.filter(\.isEnabled).count
    }

    private var displayedScripts: [UserScript] {
        showOnlyEnabled ? scripts.filter(\.isEnabled) : scripts
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Stats cards
                statsCardsView

                // Scripts list
                if scripts.isEmpty {
                    emptyStateView
                        .padding(.top, 40)
                } else {
                    scriptsListView
                }

                Spacer(minLength: 20)
            }
            .padding(.vertical)
        }
        #if os(iOS)
        .padding(.horizontal, 16)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    if !scripts.filter(\.isDownloaded).isEmpty {
                        Button {
                            refreshAllUserScripts()
                        } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                        .disabled(isRefreshing)
                    }
                    Button {
                        showingAddScriptSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button {
                        showOnlyEnabled.toggle()
                    } label: {
                        Image(systemName: showOnlyEnabled ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        #elseif os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if !scripts.filter(\.isDownloaded).isEmpty {
                    Button {
                        refreshAllUserScripts()
                    } label: {
                        Label("Check for Updates", systemImage: "arrow.down.circle")
                    }
                    .disabled(isRefreshing)
                }

                Button {
                    showingAddScriptSheet = true
                } label: {
                    Label("Add Userscript", systemImage: "plus")
                }

                Button {
                    showOnlyEnabled.toggle()
                } label: {
                    Label("Show Enabled Only", systemImage: showOnlyEnabled ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
        #endif
        .sheet(isPresented: $showingAddScriptSheet, onDismiss: {
            refreshScripts()
        }) {
            AddUserScriptView(userScriptManager: userScriptManager, onScriptAdded: {
                refreshScripts()
            })
        }
        .sheet(item: $selectedScript) { script in
            UserScriptContentView(script: script)
        }
        .onAppear {
            refreshScripts()
        }
        .alert("Duplicate Userscripts Found", isPresented: $userScriptManager.showingDuplicatesAlert) {
            Button("Remove Older Versions", role: .destructive) {
                userScriptManager.confirmDuplicateRemoval()
                refreshScripts()
            }
            Button("Keep All", role: .cancel) {
                userScriptManager.cancelDuplicateRemoval()
            }
        } message: {
            Text(userScriptManager.duplicatesMessage)
        }
        .overlay {
            if showingRefreshProgress {
                ZStack {
                    Color.black.opacity(0.1).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView(value: refreshProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                        Text(refreshStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(Int(refreshProgress * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 10)
                }
            }
        }
    }

    private func refreshScripts() {
        scripts = userScriptManager.userScripts
        statusDescription = userScriptManager.statusDescription
        isLoading = userScriptManager.isLoading
    }

    private func refreshAllUserScripts() {
        let downloadedScripts = scripts.filter { $0.isDownloaded }
        guard !downloadedScripts.isEmpty else { return }

        isRefreshing = true
        showingRefreshProgress = true
        refreshProgress = 0.0
        refreshStatus = "Starting refresh..."

        Task {
            await ConcurrentLogManager.shared.info(.userScript, "Starting userscript refresh", metadata: ["count": "\(downloadedScripts.count)"])

            for (index, script) in downloadedScripts.enumerated() {
                await MainActor.run {
                    refreshStatus = "Updating \(script.name)..."
                    refreshProgress = Double(index) / Double(downloadedScripts.count)
                }

                await ConcurrentLogManager.shared.debug(.userScript, "Updating userscript", metadata: ["script": script.name])
                await userScriptManager.updateUserScript(script)

                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            await MainActor.run {
                refreshProgress = 1.0
                refreshStatus = "Refresh complete!"

                scripts = userScriptManager.userScripts
                statusDescription = userScriptManager.statusDescription
                isLoading = userScriptManager.isLoading
            }

            await ConcurrentLogManager.shared.info(.userScript, "Userscript refresh completed successfully", metadata: [:])

            try? await Task.sleep(nanoseconds: 1_000_000_000)

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    showingRefreshProgress = false
                    isRefreshing = false
                }
            }
        }
    }

    private var statsCardsView: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Scripts",
                value: "\(totalScriptsCount)",
                icon: "doc.text",
                pillColor: .clear,
                valueColor: .primary
            )

            StatCard(
                title: "Enabled",
                value: "\(enabledScriptsCount)",
                icon: "checkmark.circle",
                pillColor: .clear,
                valueColor: .primary
            )
        }
        .padding(.horizontal)
    }

    private var scriptsListView: some View {
        LazyVStack(spacing: 16) {
            VStack(spacing: 0) {
                ForEach(Array(displayedScripts.enumerated()), id: \.element.id) { index, script in
                    scriptRowView(script: script)

                    if index < displayedScripts.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
    }

    private func scriptRowView(script: UserScript) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(script.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !script.description.isEmpty {
                    Text(script.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 4) {
                    if !script.version.isEmpty {
                        Text("Version \(script.version)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    if let lastUpdated = script.lastUpdatedFormatted {
                        if !script.version.isEmpty {
                            Text("·")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        Text(lastUpdated)
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !script.isDownloaded {
                    Text("Not Downloaded")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(4)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if script.isDownloaded {
                    Button {
                        Task {
                            await ConcurrentLogManager.shared.debug(.userScript, "Updating userscript", metadata: ["script": script.name])
                            await userScriptManager.updateUserScript(script)
                            await ConcurrentLogManager.shared.info(.userScript, "Successfully updated userscript", metadata: ["script": script.name])
                            refreshScripts()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    #if os(macOS)
                    .help("Update Script")
                    #endif
                }

                Toggle("", isOn: Binding(
                    get: { script.isEnabled },
                    set: { _ in
                        Task {
                            await ConcurrentLogManager.shared.debug(.userScript, "Toggling userscript", metadata: ["script": script.name])
                            await userScriptManager.toggleUserScript(script)
                            await MainActor.run {
                                refreshScripts()
                            }
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!script.isDownloaded)
                .frame(alignment: .center)
            }
        }
        .padding(16)
        .id(script.id)
        .contentShape(.interaction, Rectangle())
        .onTapGesture {
            if script.isDownloaded {
                selectedScript = script
            }
        }
        .contextMenu {
            #if os(macOS)
            if script.isDownloaded {
                Button {
                    selectedScript = script
                } label: {
                    Label("View Content", systemImage: "doc.text")
                }
            }
            #endif
            if script.isDownloaded {
                Button {
                    Task {
                        await userScriptManager.updateUserScript(script)
                        refreshScripts()
                    }
                } label: {
                    Label("Update", systemImage: "arrow.clockwise")
                }
            }
            Button(role: .destructive) {
                Task {
                    await ConcurrentLogManager.shared.info(.userScript, "Removing userscript", metadata: ["script": script.name])
                }
                userScriptManager.removeUserScript(script)
                refreshScripts()
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.6))
            Text("No Userscripts")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Add userscripts to customize your browsing experience")
                .font(.body)
                .foregroundColor(.secondary)
            Button {
                showingAddScriptSheet = true
            } label: {
                Label("Add Userscript", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - UserScriptInfoSidebar Subviews

private struct ScriptNameAndDescriptionView: View {
    let script: UserScript
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(script.name).font(.title2).fontWeight(.semibold).foregroundColor(.primary).textSelection(.enabled)
            if !script.description.isEmpty {
                Text(script.description).font(.body).foregroundColor(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ScriptStatusBadgesView: View {
    let script: UserScript
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if !script.version.isEmpty {
                    Badge(text: "v\(script.version)", color: .blue)
                }
                Badge(text: script.isEnabled ? "Enabled" : "Disabled", color: script.isEnabled ? .green : .secondary)
            }
            if !script.isDownloaded {
                Badge(text: "Not Downloaded", color: .red)
            } else {
                Badge(text: "Downloaded", color: .green)
            }
        }
    }
}

private struct ScriptFileInfoView: View {
    let script: UserScript
    let formatFileSize: (Int) -> String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("File Information").font(.caption).fontWeight(.medium).foregroundColor(.secondary)
            HStack {
                Text("Size:").font(.caption2).foregroundColor(.secondary)
                Text(formatFileSize(script.content.count)).font(.caption).fontWeight(.medium).foregroundColor(.primary)
                Spacer()
            }.padding(.horizontal, 8).padding(.vertical, 6).cornerRadius(6)
        }
    }
}

private struct ScriptURLView: View {
    let script: UserScript
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Source URL").font(.caption).fontWeight(.medium).foregroundColor(.secondary)
            Text(script.url?.absoluteString ?? "N/A").font(.caption).foregroundColor(.blue).textSelection(.enabled).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ScriptMatchPatternRowView: View {
    let index: Int
    let pattern: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(index + 1).")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 18, alignment: .trailing)

            Text(pattern)
                .font(.caption)
                .foregroundColor(.orange)
                .textSelection(.enabled)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

private struct ScriptMatchPatternsView: View {
    let script: UserScript
    @Binding var isPatternsExpanded: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPatternsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text("URL Patterns (\(script.matches.count))")
                        .font(.caption).fontWeight(.medium).foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: isPatternsExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain).padding(.horizontal, 8).padding(.vertical, 6).cornerRadius(6).onHover { _ in }

            if isPatternsExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(script.matches.enumerated()), id: \.offset) { indexInForEach, patternInForEach in
                            ScriptMatchPatternRowView(index: indexInForEach, pattern: patternInForEach)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxHeight: 200)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5), lineWidth: 0.5))
            }
        }
    }
}


struct UserScriptInfoSidebar: View {
    let script: UserScript
    @Binding var isPatternsExpanded: Bool
    let formatFileSize: (Int) -> String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScriptNameAndDescriptionView(script: script)
            ScriptStatusBadgesView(script: script)
            if !script.content.isEmpty { ScriptFileInfoView(script: script, formatFileSize: formatFileSize) }
            if script.url != nil { ScriptURLView(script: script) }
            if !script.matches.isEmpty { ScriptMatchPatternsView(script: script, isPatternsExpanded: $isPatternsExpanded) }
            Spacer()
        }
    }
}

#if os(macOS)
struct ScriptContentMainView: View {
    let script: UserScript
    @Binding var displayedContent: String
    @Binding var isLoadingContent: Bool
    @Binding var showFullContent: Bool
    let previewLength: Int
    let formatFileSize: (Int) -> String
    let toggleContentViewAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Script Content").font(.headline).fontWeight(.medium)
                    if !script.content.isEmpty && script.content.count > previewLength && !showFullContent {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle").font(.caption2).foregroundColor(.orange)
                            Text("Showing preview (\(formatFileSize(previewLength)) of \(formatFileSize(script.content.count)))")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    } else if showFullContent && script.content.count > previewLength {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle").font(.caption2).foregroundColor(.green)
                            Text("Full content loaded").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
                HStack(spacing: 12) {
                    if !script.content.isEmpty && script.content.count > previewLength {
                        Button { toggleContentViewAction() } label: {
                            HStack(spacing: 6) {
                                if isLoadingContent { ProgressView().scaleEffect(0.8).frame(width: 12, height: 12) }
                                else { Image(systemName: showFullContent ? "eye.slash" : "eye") }
                                Text(showFullContent ? "Show Preview" : "Show All")
                            }
                        }.buttonStyle(.borderless).disabled(isLoadingContent)
                         .help(showFullContent ? "Show preview only" : "Load full content")
                    }
                }
            }.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            if script.content.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text").font(.system(size: 48)).foregroundColor(.secondary.opacity(0.6))
                    Text("No Content Available").font(.headline).foregroundColor(.secondary)
                    Text("This script hasn't been downloaded yet.").font(.body).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text(displayedContent).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    }
                }
                .overlay( Group {
                    if script.content.count > 100000 && showFullContent {
                        VStack { Spacer(); HStack { Spacer()
                            HStack(spacing: 6) { Image(systemName: "info.circle.fill").foregroundColor(.orange)
                                Text("Large file - scrolling may be slow")
                            }.padding(.horizontal, 8).padding(.vertical, 4).background(Color.orange.opacity(0.1)).cornerRadius(6).padding()
                        }}
                    }
                }, alignment: .bottomTrailing)
            }
        }
    }
}
#endif

struct UserScriptContentView: View {
    let script: UserScript
    @Environment(\.dismiss) private var dismiss
    @State private var displayedContent: String = ""
    @State private var isLoadingContent = false
    @State private var showFullContent = false
    @State private var sidebarWidth: CGFloat = 280
    @State private var isPatternsExpanded = false

    private let previewLength = 10000
    #if os(macOS)
    private let minSidebarWidth: CGFloat = 250
    private let maxSidebarWidth: CGFloat = 500
    #endif

    var body: some View {
        #if os(iOS)
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    UserScriptInfoSidebar(
                        script: script,
                        isPatternsExpanded: $isPatternsExpanded,
                        formatFileSize: formatFileSize
                    )
                    .padding(.horizontal)

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Script Content")
                            .font(.headline)
                            .fontWeight(.medium)

                        if script.content.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary.opacity(0.6))
                                Text("No Content Available")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("This script hasn't been downloaded yet.")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            Text(displayedContent)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle(script.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { loadInitialContent() }
        #else
        HSplitView {
            UserScriptInfoSidebar(
                script: script,
                isPatternsExpanded: $isPatternsExpanded,
                formatFileSize: formatFileSize
            )
            .frame(minWidth: minSidebarWidth, idealWidth: sidebarWidth, maxWidth: maxSidebarWidth)
            .padding(20)

            ScriptContentMainView(
                script: script,
                displayedContent: $displayedContent,
                isLoadingContent: $isLoadingContent,
                showFullContent: $showFullContent,
                previewLength: previewLength,
                formatFileSize: formatFileSize,
                toggleContentViewAction: toggleContentView
            )
            .frame(minWidth: 400)
        }
        .navigationTitle("")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .frame(width: 1000, height: 700)
        .onAppear { loadInitialContent() }
        #endif
    }

    private func loadInitialContent() {
        if script.content.isEmpty { displayedContent = ""; return }
        if script.content.count <= previewLength {
            displayedContent = script.content; showFullContent = true
        } else {
            displayedContent = String(script.content.prefix(previewLength)); showFullContent = false
        }
    }

    private func toggleContentView() {
        if showFullContent {
            displayedContent = String(script.content.prefix(previewLength))
            showFullContent = false
        } else {
            isLoadingContent = true

            DispatchQueue.global(qos: .userInitiated).async {
                let fullContent = script.content

                DispatchQueue.main.async {
                    displayedContent = fullContent
                    showFullContent = true
                    isLoadingContent = false
                }
            }
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter(); formatter.allowedUnits = [.useKB, .useMB]; formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15)).foregroundColor(color).cornerRadius(4)
    }
}

struct AddUserScriptView: View {
    var userScriptManager: UserScriptManager
    var onScriptAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlInput: String = ""
    @State private var validationState: ValidationState = .idle
    @State private var isAdding: Bool = false
    @State private var showHints: Bool = false
    @FocusState private var urlFieldFocused: Bool

    var body: some View {
        SheetContainer {
            SheetHeader(title: "Add Userscript", isLoading: isAdding) {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    entryCard
                    requirementsCard
                }
                .padding(.horizontal, SheetDesign.contentHorizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }

            SheetBottomToolbar {
                cancelButton
                Spacer()
                addButton
            }
        }
        .interactiveDismissDisabled(isAdding)
        .onAppear {
            urlFieldFocused = true
        }
        .onChange(of: urlInput) { _, newValue in
            validateInput(newValue)
        }
    }

    // MARK: - UI Sections

    private var entryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Script URL")
                    .font(.headline)
                Text("Paste the direct .user.js link. wBlock will download and install it for you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                TextField("https://example.com/script.user.js", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .focused($urlFieldFocused)

                HStack(spacing: 12) {
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            urlInput = ""
                        }
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(urlInput.isEmpty)

                    Spacer()

                    validationBadge
                }
            }

            validationMessage
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var requirementsCard: some View {
        DisclosureGroup(isExpanded: $showHints.animation(.easeInOut(duration: 0.2))) {
            VStack(alignment: .leading, spacing: 8) {
                requirementRow(icon: "link", text: "Starts with https://")
                requirementRow(icon: "doc.text", text: "Ends with .user.js")
                requirementRow(icon: "checkmark.shield", text: "Hosted on a trusted source")
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("URL requirements")
                        .font(.headline)
                    Text("Tap to review userscript guidelines.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var validationBadge: some View {
        Group {
            switch validationState {
            case .idle:
                EmptyView()
            case .invalid:
                Label("Invalid", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .valid:
                Label("Ready", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: validationState)
    }

    private var validationMessage: some View {
        Group {
            switch validationState {
            case .idle:
                Text("We’ll fetch the script and enable it automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .invalid(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .valid:
                Text("Looks good! Tap Add Script to continue.")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: validationState)
    }

    private func requirementRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var cancelButton: some View {
        Button("Cancel") {
            dismiss()
        }
        .secondaryActionButtonStyle()
        .disabled(isAdding)
        .keyboardShortcut(.cancelAction)
    }

    private var addButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if isAdding {
                    ProgressView()
                        .scaleEffect(0.9)
                }
                Text(isAdding ? "Adding…" : "Add Script")
                    .fontWeight(.semibold)
            }
        }
        .primaryActionButtonStyle()
        .disabled(!canSubmit)
        .keyboardShortcut(.defaultAction)
    }

    // MARK: - Submission

    private var canSubmit: Bool {
        switch validationState {
        case .valid: return !isAdding
        default: return false
        }
    }

    private func submit() {
        guard case .valid(let url) = validationState else { return }

        isAdding = true

        Task(priority: .userInitiated) {
            await ConcurrentLogManager.shared.info(.userScript, "Adding new userscript from URL", metadata: ["url": url.absoluteString])
            await userScriptManager.addUserScript(from: url)
            await ConcurrentLogManager.shared.info(.userScript, "Successfully added userscript from URL", metadata: ["url": url.absoluteString])

            await MainActor.run {
                isAdding = false
                onScriptAdded()
                dismiss()
            }
        }
    }

    // MARK: - Validation & Utilities

    private func validateInput(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            validationState = .idle
            return
        }

        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = components.host,
              !host.isEmpty,
              trimmed.lowercased().hasSuffix(".user.js"),
              let url = components.url else {
            validationState = .invalid("Provide a valid https:// link ending in .user.js")
            return
        }

        validationState = .valid(url)
    }

    private func pasteFromClipboard() {
        #if os(iOS)
        if let string = UIPasteboard.general.string {
            urlInput = string
        }
        #elseif os(macOS)
        if let string = NSPasteboard.general.string(forType: .string) {
            urlInput = string
        }
        #endif
    }

    // MARK: - Types

    private enum ValidationState: Equatable {
        case idle
        case invalid(String)
        case valid(URL)
    }

}
