//
//  UserScriptManagerView.swift
//  wBlock
//
//  Created by Alexander Skula on 6/7/25.
//

import SwiftUI
import wBlockCoreService

struct UserScriptManagerView: View {
    var userScriptManager: UserScriptManager
    
    @State private var scripts: [UserScript] = []
    @State private var isLoading: Bool = false
    @State private var isRefreshing: Bool = false
    @State private var refreshProgress: Double = 0.0
    @State private var refreshStatus: String = ""
    @State private var showingRefreshProgress = false
    @State private var statusDescription: String = ""
    @State private var showingAddScriptSheet = false
    @State private var selectedScript: UserScript?
    @Environment(\.dismiss) private var dismiss
    
    private var totalScriptsTitle: String {
        #if os(macOS)
        return "Total Scripts"
        #else
        return "Scripts"
        #endif
    }
    
    private var totalScriptsCount: Int {
        scripts.count
    }
    
    private var enabledScriptsCount: Int {
        scripts.filter(\.isEnabled).count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("User Scripts")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding([.top, .horizontal])
            
            headerView
            
            if scripts.isEmpty {
                emptyStateView
            } else {
                scriptsList
            }
            
            bottomToolbar
        }
        .sheet(isPresented: $showingAddScriptSheet, onDismiss: {
            refreshScripts()
        }) {
            AddUserScriptView(userScriptManager: userScriptManager, onScriptAdded: {
                refreshScripts()
            })
        }
        #if os(macOS)
        .sheet(item: $selectedScript) { script in
            UserScriptContentView(script: script)
        }
        #endif
        .onAppear {
            refreshScripts()
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
            await ConcurrentLogManager.shared.log("🔄 Starting userscript refresh for \(downloadedScripts.count) scripts")
            
            for (index, script) in downloadedScripts.enumerated() {
                await MainActor.run {
                    refreshStatus = "Updating \(script.name)..."
                    refreshProgress = Double(index) / Double(downloadedScripts.count)
                }
                
                await ConcurrentLogManager.shared.log("📝 Updating userscript: \(script.name)")
                await userScriptManager.updateUserScript(script)
                
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
            
            await MainActor.run {
                refreshProgress = 1.0
                refreshStatus = "Refresh complete!"
                
                scripts = userScriptManager.userScripts
                statusDescription = userScriptManager.statusDescription
                isLoading = userScriptManager.isLoading
            }
            
            await ConcurrentLogManager.shared.log("✅ Userscript refresh completed successfully")

            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    showingRefreshProgress = false
                    isRefreshing = false
                }
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                StatCard(
                    title: totalScriptsTitle,
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
            
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 16, height: 16)
                    Text(statusDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    private var scriptsList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(scripts, id: \.id) { script in
                    UserScriptRowView(
                        script: script,
                        onTap: {
                            #if os(macOS)
                            selectedScript = script
                            #endif
                        },
                        onToggle: {
                            Task {
                                await ConcurrentLogManager.shared.log("🔄 Toggling userscript: \(script.name) to \(script.isEnabled ? "disabled" : "enabled")")
                                await userScriptManager.toggleUserScript(script)
                                await MainActor.run {
                                    refreshScripts()
                                }
                            }
                        },
                        onUpdate: {
                            Task {
                                await ConcurrentLogManager.shared.log("📝 Updating userscript: \(script.name)")
                                await userScriptManager.updateUserScript(script)
                                await ConcurrentLogManager.shared.log("✅ Successfully updated userscript: \(script.name)")
                                refreshScripts()
                            }
                        },
                        onRemove: {
                            Task {
                                await ConcurrentLogManager.shared.log("🗑️ Removing userscript: \(script.name)")
                            }
                            userScriptManager.removeUserScript(script)
                            refreshScripts()
                        }
                    )
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("No User Scripts")
                    .font(.title2)
                    .fontWeight(.medium)
                
                Text("Add userscripts to customize your browsing experience")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                showingAddScriptSheet = true
            } label: {
                Label("Add User Script", systemImage: "plus")
                    .font(.body)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    .frame(maxWidth: .infinity)
    .padding(.vertical)
    }
    
    private var bottomToolbar: some View {
        VStack(spacing: 0) {
            // Progress bar for refresh
            if showingRefreshProgress {
                VStack(spacing: 8) {
                    HStack {
                        Text(refreshStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(refreshProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    ProgressView(value: refreshProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.05))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Button toolbar
            HStack(spacing: 16) {
                Button {
                    refreshAllUserScripts()
                } label: {
                    HStack(spacing: 6) {
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text("Update All")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing || scripts.filter(\.isDownloaded).isEmpty)
                
                Button {
                    showingAddScriptSheet = true
                } label: {
                    Label("Add Script", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            #if os(macOS)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
            #else
            .background(Color(.systemBackground).opacity(0.8))
            #endif
        }
    }
}

struct UserScriptRowView: View {
    let script: UserScript
    let onTap: () -> Void
    let onToggle: () -> Void
    let onUpdate: () -> Void
    let onRemove: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: script.isDownloaded ? "doc.text.fill" : "doc.text")
                        .foregroundColor(script.isDownloaded ? .blue : .secondary)
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(script.name)
                            .font(.headline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        if !script.description.isEmpty {
                            Text(script.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        HStack(spacing: 8) {
                            if !script.version.isEmpty {
                                Text("v\(script.version)")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.gray)
                            }
                            if !script.version.isEmpty && !script.matches.isEmpty {
                                Text("·")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            if !script.matches.isEmpty {
                                Text("\(script.matches.count) pattern\(script.matches.count == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.gray)
                            }
                            if let lastUpdated = script.lastUpdatedFormatted {
                                if (!script.version.isEmpty || !script.matches.isEmpty) {
                                    Text("·")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                Text("Updated \(lastUpdated.lowercased())")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            if !script.isDownloaded {
                                Badge(text: "Not Downloaded", color: .red)
                            }
                        }
                    }
                    Spacer()
                }
            }
            Spacer()
            HStack(spacing: 12) {
                if script.isDownloaded {
                    Button { onUpdate() } label: { Image(systemName: "arrow.clockwise").font(.body) }
                    .buttonStyle(.borderless).help("Update Script")
                }
                Toggle("", isOn: Binding(get: { script.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden().disabled(!script.isDownloaded)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        #if os(macOS)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture { onTap() }
        #endif
        .contextMenu {
            #if os(macOS)
            if script.isDownloaded { Button { onTap() } label: { Label("View Content", systemImage: "doc.text") } }
            #endif
            if script.isDownloaded { Button { onUpdate() } label: { Label("Update", systemImage: "arrow.clockwise") } }
            Button(role: .destructive) { onRemove() } label: { Label("Remove", systemImage: "trash") }
        }
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

#if os(macOS)

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
                if !script.version.isEmpty { Badge(text: "v\(script.version)", color: .blue) } // Corrected
                Badge(text: script.isEnabled ? "Enabled" : "Disabled", color: script.isEnabled ? .green : .secondary)
            }
            if !script.isDownloaded { Badge(text: "Not Downloaded", color: .red) } else { Badge(text: "Downloaded", color: .green) }
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

// NEW Struct for individual match pattern row
private struct ScriptMatchPatternRowView: View {
    let index: Int
    let pattern: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index + 1).") // Corrected
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .leading)

            Text(pattern)
                .font(.caption)
                .foregroundColor(.orange)
                .textSelection(.enabled)
                .lineLimit(nil)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .cornerRadius(4)
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
                    Text("URL Patterns (\(script.matches.count))") // Corrected
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
                        // Use the new ScriptMatchPatternRowView here
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
                            Text("Showing preview (\(formatFileSize(previewLength)) of \(formatFileSize(script.content.count)))") // Corrected
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

struct UserScriptContentView: View {
    let script: UserScript
    @Environment(\.dismiss) private var dismiss
    @State private var displayedContent: String = ""
    @State private var isLoadingContent = false
    @State private var showFullContent = false
    @State private var sidebarWidth: CGFloat = 280
    @State private var isPatternsExpanded = false
    
    private let previewLength = 10000
    private let minSidebarWidth: CGFloat = 250
    private let maxSidebarWidth: CGFloat = 500
    
    private var splitViewContent: some View { // Extracted for clarity/compiler
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
    }

    var body: some View {
        splitViewContent
            .navigationTitle("")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .frame(width: 1000, height: 700)
            .onAppear { loadInitialContent() }
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
            
            // Move heavy computation off main thread
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
#endif

struct AddUserScriptView: View {
    var userScriptManager: UserScriptManager
    var onScriptAdded: () -> Void
    @State private var urlString = ""
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                VStack(spacing: 20) {
                    Text("Add Userscript")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("Enter the URL of a userscript (ending in .user.js)")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                VStack(spacing: 16) {
                    TextField("https://example.com/script.user.js", text: $urlString)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                    
                    VStack(spacing: 12) {
                        Button(action: addScript) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .frame(width: 16, height: 16)
                                    Text("Adding...")
                                } else {
                                    Text("Add Script")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                        
                        Button("Cancel") {
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("")
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
        }
    }
    
    private func addScript() {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        
        isLoading = true
        
        Task {
            await ConcurrentLogManager.shared.log("📥 Adding new userscript from URL: \(url.absoluteString)")
            await userScriptManager.addUserScript(from: url)
            await ConcurrentLogManager.shared.log("✅ Successfully added userscript from URL: \(url.absoluteString)")
            
            await MainActor.run {
                isLoading = false
                onScriptAdded()
                dismiss()
            }
        }
    }
}

