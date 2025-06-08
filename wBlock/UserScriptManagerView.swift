//
//  UserScriptManagerView.swift
//  wBlock
//
//  Created by Alexander Skula on 6/7/25.
//

import SwiftUI
import wBlockCoreService

struct UserScriptManagerView: View {
    @ObservedObject var userScriptManager: UserScriptManager
    @State private var showingAddScriptSheet = false
    @State private var selectedScript: UserScript?
    @State private var showingScriptContent = false
    @Environment(\.dismiss) private var dismiss
    
    private var totalScriptsTitle: String {
        #if os(macOS)
        return "Total Scripts"
        #else
        return "Scripts"
        #endif
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Scripts list
            if userScriptManager.userScripts.isEmpty {
                emptyStateView
            } else {
                scriptsList
            }
        }
        .navigationTitle("User Scripts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddScriptSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add User Script")
            }
        }
        .sheet(isPresented: $showingAddScriptSheet) {
            AddUserScriptView(userScriptManager: userScriptManager)
        }
        #if os(macOS)
        .sheet(item: $selectedScript) { script in
            UserScriptContentView(script: script)
        }
        #endif
    }
    
    private var headerView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                StatCard(
                    title: totalScriptsTitle,
                    value: "\(userScriptManager.userScripts.count)",
                    icon: "doc.text",
                    pillColor: .blue.opacity(0.1),
                    valueColor: .blue
                )
                
                StatCard(
                    title: "Enabled",
                    value: "\(userScriptManager.userScripts.filter(\.isEnabled).count)",
                    icon: "checkmark.circle.fill",
                    pillColor: .green.opacity(0.1),
                    valueColor: .green
                )
            }
            
            if userScriptManager.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(userScriptManager.statusDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(.systemGroupedBackground))
    }
    
    private var scriptsList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(userScriptManager.userScripts, id: \.id) { script in
                    UserScriptRowView(
                        script: script,
                        onTap: {
                            #if os(macOS)
                            selectedScript = script
                            showingScriptContent = true
                            #endif
                        },
                        onToggle: {
                            userScriptManager.toggleUserScript(script)
                        },
                        onUpdate: {
                            Task {
                                await userScriptManager.updateUserScript(script)
                            }
                        },
                        onRemove: {
                            userScriptManager.removeUserScript(script)
                        }
                    )
                }
                
                // Add Script button at the bottom of the list
                Button {
                    showingAddScriptSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.body)
                        Text("Add Script")
                            .font(.body)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            .blendMode(.overlay)
                    )
                }
                .buttonStyle(.plain)
                .help("Add a new userscript")
                .padding(.top, 1)
            }
        }
        .background(Color(.systemGroupedBackground))
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
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
            // Script icon and info
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
                    }
                    
                    Spacer()
                }
                
                // Status badges
                HStack(spacing: 8) {
                    if !script.version.isEmpty {
                        Badge(text: "v\(script.version)", color: .blue)
                    }
                    
                    if !script.matches.isEmpty {
                        Badge(text: "\(script.matches.count) pattern\(script.matches.count == 1 ? "" : "s")", color: .orange)
                    }
                    
                    if !script.isDownloaded {
                        Badge(text: "Not Downloaded", color: .red)
                    }
                }
            }
            
            Spacer()
            
            // Controls
            HStack(spacing: 12) {
                // Update button (if downloaded)
                if script.isDownloaded {
                    Button {
                        onUpdate()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.body)
                    }
                    .buttonStyle(.borderless)
                    .help("Update Script")
                }
                
                // Toggle
                Toggle("", isOn: Binding(
                    get: { script.isEnabled },
                    set: { _ in onToggle() }
                ))
                .labelsHidden()
                .disabled(!script.isDownloaded)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Color(.systemGroupedBackground)
                .overlay(
                    isHovered ? Color.primary.opacity(0.05) : Color.clear
                )
        )
        #if os(macOS)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        #endif
        #if os(macOS)
        .onTapGesture {
            onTap()
        }
        #endif
        .contextMenu {
            #if os(macOS)
            if script.isDownloaded {
                Button {
                    onTap()
                } label: {
                    Label("View Content", systemImage: "doc.text")
                }
            }
            #endif
            
            if script.isDownloaded {
                Button {
                    onUpdate()
                } label: {
                    Label("Update", systemImage: "arrow.clockwise")
                }
            }
            
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

struct Badge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

#if os(macOS)
struct UserScriptContentView: View {
    let script: UserScript
    @Environment(\.dismiss) private var dismiss
    @State private var selectedText: String = ""
    @State private var displayedContent: String = ""
    @State private var isLoadingContent = false
    @State private var showFullContent = false
    @State private var sidebarWidth: CGFloat = 280
    @State private var isPatternsExpanded = false
    
    private let previewLength = 10000 // Show first 10k characters initially
    private let minSidebarWidth: CGFloat = 250
    private let maxSidebarWidth: CGFloat = 500
    
    var body: some View {
        HSplitView {
            // Left sidebar with script info
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(script.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                    
                    if !script.description.isEmpty {
                        Text(script.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                // Status badges
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if !script.version.isEmpty {
                            Badge(text: "v\(script.version)", color: .blue)
                        }
                        
                        Badge(
                            text: script.isEnabled ? "Enabled" : "Disabled",
                            color: script.isEnabled ? .green : .secondary
                        )
                    }
                    
                    if !script.isDownloaded {
                        Badge(text: "Not Downloaded", color: .red)
                    } else {
                        Badge(text: "Downloaded", color: .green)
                    }
                }
                
                // File size info
                if !script.content.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("File Information")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Size:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(formatFileSize(script.content.count))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(6)
                    }
                }
                
                // URL
                if let url = script.url {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Source URL")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Text(url.absoluteString)
                            .font(.caption)
                            .foregroundColor(.blue)
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                // Match patterns
                if !script.matches.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isPatternsExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text("URL Patterns (\(script.matches.count))")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Image(systemName: isPatternsExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .rotationEffect(.degrees(isPatternsExpanded ? 0 : 0))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(6)
                        .onHover { hovering in
                            // Add subtle hover effect
                        }
                        
                        if isPatternsExpanded {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(Array(script.matches.enumerated()), id: \.offset) { index, pattern in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("\(index + 1).")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .frame(width: 20, alignment: .leading)
                                            
                                            Text(pattern)
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                                .textSelection(.enabled)
                                                .lineLimit(nil)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            index % 2 == 0 
                                            ? Color.clear 
                                            : Color(.tertiarySystemGroupedBackground)
                                        )
                                        .cornerRadius(4)
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                            .frame(maxHeight: 200) // Limit height to prevent sidebar overflow
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.separator), lineWidth: 0.5)
                            )
                        }
                    }
                }
                
                Spacer()
            }
            .frame(minWidth: minSidebarWidth, idealWidth: sidebarWidth, maxWidth: maxSidebarWidth)
            .padding(20)
            .background(Color(.systemGroupedBackground))
            
            // Right content area
            VStack(spacing: 0) {
                // Content header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Script Content")
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        if !script.content.isEmpty && script.content.count > previewLength && !showFullContent {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Text("Showing preview (\(formatFileSize(previewLength)) of \(formatFileSize(script.content.count)))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else if showFullContent && script.content.count > previewLength {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                Text("Full content loaded")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        // Show more/less button for large files
                        if !script.content.isEmpty && script.content.count > previewLength {
                            Button {
                                toggleContentView()
                            } label: {
                                HStack(spacing: 6) {
                                    if isLoadingContent {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .frame(width: 12, height: 12)
                                    } else {
                                        Image(systemName: showFullContent ? "eye.slash" : "eye")
                                    }
                                    Text(showFullContent ? "Show Preview" : "Show All")
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(isLoadingContent)
                            .help(showFullContent ? "Show preview only to improve performance" : "Load full content (may cause lag for very large files)")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(.systemGroupedBackground))
                
                Divider()
                
                // Script content
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            Text(displayedContent)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20)
                        }
                    }
                    .background(Color(.systemBackground))
                    .overlay(
                        // Performance indicator for large files
                        Group {
                            if script.content.count > 100000 && showFullContent {
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        HStack(spacing: 6) {
                                            Image(systemName: "info.circle.fill")
                                                .font(.caption2)
                                                .foregroundColor(.orange)
                                            Text("Large file - scrolling may be slow")
                                                .font(.caption2)
                                                .foregroundColor(.orange)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.orange.opacity(0.1))
                                        .cornerRadius(6)
                                        .padding()
                                    }
                                }
                            }
                        }, alignment: .bottomTrailing
                    )
                }
            }
            .frame(minWidth: 400)
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .frame(width: 1000, height: 700)
        .onAppear {
            loadInitialContent()
        }
    }
    
    private func loadInitialContent() {
        if script.content.isEmpty {
            displayedContent = ""
            return
        }
        
        // For small files, show everything immediately
        if script.content.count <= previewLength {
            displayedContent = script.content
            showFullContent = true
        } else {
            // For large files, show preview first
            displayedContent = String(script.content.prefix(previewLength))
            showFullContent = false
        }
    }
    
    private func toggleContentView() {
        if showFullContent {
            // Switch to preview
            displayedContent = String(script.content.prefix(previewLength))
            showFullContent = false
        } else {
            // Load full content asynchronously with better performance handling
            isLoadingContent = true
            
            // Use a slight delay to show loading state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                DispatchQueue.global(qos: .userInitiated).async {
                    let fullContent = script.content
                    
                    DispatchQueue.main.async {
                        // Update in chunks for very large files to maintain responsiveness
                        if fullContent.count > 500000 {
                            // For very large files, update incrementally
                            let chunkSize = 50000
                            var currentIndex = fullContent.startIndex
                            var chunks: [String] = []
                            
                            while currentIndex < fullContent.endIndex {
                                let endIndex = fullContent.index(currentIndex, offsetBy: chunkSize, limitedBy: fullContent.endIndex) ?? fullContent.endIndex
                                let chunk = String(fullContent[currentIndex..<endIndex])
                                chunks.append(chunk)
                                currentIndex = endIndex
                            }
                            
                            displayedContent = chunks.joined()
                        } else {
                            displayedContent = fullContent
                        }
                        
                        showFullContent = true
                        isLoadingContent = false
                    }
                }
            }
        }
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
#endif

struct AddUserScriptView: View {
    @ObservedObject var userScriptManager: UserScriptManager
    @State private var urlString = ""
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add User Script")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Enter the URL of a userscript (ending in .user.js)")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                TextField("https://example.com/script.user.js", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Adaptive button layout
            if horizontalSizeClass == .compact {
                // Vertical layout for narrow screens (iPhone)
                VStack(spacing: 12) {
                    Button {
                        addScript()
                    } label: {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Adding...")
                            } else {
                                Text("Add Script")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
            } else {
                // Horizontal layout for wide screens (iPad, macOS)
                HStack(spacing: 16) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button {
                        addScript()
                    } label: {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Adding...")
                            } else {
                                Text("Add Script")
                            }
                        }
                        .frame(minWidth: 100)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
            
            Spacer(minLength: 20)
        }
        .padding(adaptivePadding)
        .frame(
            maxWidth: adaptiveMaxWidth,
            maxHeight: adaptiveMaxHeight
        )
    }
    
    private var adaptivePadding: CGFloat {
        horizontalSizeClass == .compact ? 20 : 30
    }
    
    private var adaptiveMaxWidth: CGFloat? {
        horizontalSizeClass == .compact ? nil : 500
    }
    
    private var adaptiveMaxHeight: CGFloat? {
        horizontalSizeClass == .compact ? nil : 250
    }
    
    private func addScript() {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }
        
        isLoading = true
        
        Task {
            await userScriptManager.addUserScript(from: url)
            await MainActor.run {
                isLoading = false
                dismiss()
            }
        }
    }
}
