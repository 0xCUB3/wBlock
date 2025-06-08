//
//  UserScriptManagerView.swift
//  wBlock
//
//  Created by GitHub Copilot on 6/7/25.
//

import SwiftUI
import wBlockCoreService // Added import

struct UserScriptManagerView: View {
    @ObservedObject var userScriptManager: UserScriptManager
    @State private var showingAddScriptSheet = false
    @State private var newScriptURL = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with stats
                headerView
                
                // Scripts list
                if userScriptManager.userScripts.isEmpty {
                    emptyStateView
                } else {
                    scriptsList
                }
                
                Spacer()
            }
            .navigationTitle("User Scripts")
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddScriptSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingAddScriptSheet = true
                    } label: {
                        Label("Add Script", systemImage: "plus")
                    }
                }
            }
            #endif
        }
        .sheet(isPresented: $showingAddScriptSheet) {
            AddUserScriptView(userScriptManager: userScriptManager)
#if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
#else
                .frame(width: 500, height: 300)
#endif
        }
        #if os(macOS)
            .frame(minWidth: 500, idealWidth: 500, minHeight: 350, idealHeight: 400)
        #endif
    }
    
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(userScriptManager.userScripts.count)")
                        .font(.title.bold())
                        .foregroundColor(.primary)
                    Text("Total Scripts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("\(userScriptManager.userScripts.filter(\.isEnabled).count)")
                        .font(.title.bold())
                        .foregroundColor(.green)
                    Text("Enabled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            #if os(iOS)
            .background(Color(UIColor.systemGroupedBackground))
            #else
            .background(Color(NSColor.controlBackgroundColor))
            #endif
            .cornerRadius(12)
            
            if userScriptManager.isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(userScriptManager.statusDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
        }
        .padding(.horizontal)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            
            VStack(spacing: 8) {
                Text("No User Scripts")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Add userscripts from URLs to enhance your browsing experience")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button {
                showingAddScriptSheet = true
            } label: {
                Label("Add Your First Script", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#if os(iOS)
        .background(Color(UIColor.systemGroupedBackground).opacity(0.3))
#else
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
#endif
    }
    
    private var scriptsList: some View {
        List {
            ForEach(userScriptManager.userScripts, id: \.id) { script in // Corrected key path
                UserScriptRow(
                    script: script,
                    onToggle: { userScriptManager.toggleUserScript(script) },
                    onUpdate: { 
                        Task {
                            await userScriptManager.updateUserScript(script)
                        }
                    },
                    onRemove: { userScriptManager.removeUserScript(script) }
                )
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }
}

struct UserScriptRow: View {
    let script: UserScript
    let onToggle: () -> Void
    let onUpdate: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(script.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if !script.description.isEmpty {
                        Text(script.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    if !script.version.isEmpty {
                        Text("v\\(script.version)")
                            .font(.caption2)
                            #if os(iOS)
                            .foregroundColor(Color(.tertiaryLabel))
                            #else
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                            #endif
                    }
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { script.isEnabled },
                    set: { _ in onToggle() }
                ))
                .labelsHidden()
                // Removed .onChange(of: script.isEnabled)
            }
            
            if !script.matches.isEmpty {
                HStack {
                    Image(systemName: "globe")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("\(script.matches.count) pattern(s)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                onUpdate()
            } label: {
                Label("Update", systemImage: "arrow.clockwise")
            }
            
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

struct AddUserScriptView: View {
    @ObservedObject var userScriptManager: UserScriptManager
    @State private var urlString = ""
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
#if os(macOS)
        macOSView
#else
        iOSView
#endif
    }
    
    // macOS-specific view without NavigationView to avoid layout conflicts
    private var macOSView: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add User Script")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Enter the URL of a userscript (ending in .user.js)")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                TextField("https://example.com/script.user.js", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .frame(height: 44)
                    .autocorrectionDisabled()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Spacer()
                
                Button {
                    addScript()
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Adding...")
                        } else {
                            Text("Add Script")
                        }
                    }
                    .frame(minWidth: 120)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                .controlSize(.large)
            }
            
            Spacer(minLength: 20)
        }
        .padding(30)
        .frame(width: 500)
        .frame(minHeight: 220)
    }
    
    // iOS-specific view with NavigationView
    private var iOSView: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Add User Script")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Enter the URL of a userscript (ending in .user.js)")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    TextField("https://example.com/script.user.js", text: $urlString)
                        .textFieldStyle(.roundedBorder)
                        .frame(height: 44)
#if os(iOS)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
#endif
                        .autocorrectionDisabled()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 16) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    
                    Button {
                        addScript()
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Adding...")
                            } else {
                                Text("Add Script")
                            }
                        }
                        .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    .controlSize(.large)
                }
                
                Spacer()
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
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

#Preview {
    UserScriptManagerView(userScriptManager: UserScriptManager())
}
