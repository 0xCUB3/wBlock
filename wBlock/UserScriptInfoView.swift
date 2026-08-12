import SwiftUI
import wBlockCoreService

struct UserScriptInfoView: View {
    let scriptId: UUID
    var userScriptManager: UserScriptManager

    @Environment(\.dismiss) private var dismiss
    @State private var script: UserScript?
    @State private var isPatternsExpanded = false
    @State private var isLoading = true

    var body: some View {
        Group {
            if let script {
                #if os(iOS)
                NavigationView {
                    ScrollView {
                        UserScriptInfoSidebar(
                            script: script,
                            contentLength: script.content.count,
                            isPatternsExpanded: $isPatternsExpanded,
                            formatFileSize: formatFileSize,
                            isBundled: userScriptManager.isBundled(for: script),
                            isBuiltIn: userScriptManager.isDefaultUserScript(script),
                            isBeta: userScriptManager.isBeta(for: script),
                            onUpdatesAutomaticallyChanged: setUpdatesAutomatically
                        )
                        .padding()
                    }
                    .navigationTitle(script.localizedDisplayName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { dismiss() }
                        }
                    }
                }
                #else
                UserScriptInfoSidebar(
                    script: script,
                    contentLength: script.content.count,
                    isPatternsExpanded: $isPatternsExpanded,
                    formatFileSize: formatFileSize,
                    isBundled: userScriptManager.isBundled(for: script),
                    isBuiltIn: userScriptManager.isDefaultUserScript(script),
                    isBeta: userScriptManager.isBeta(for: script),
                    onUpdatesAutomaticallyChanged: setUpdatesAutomatically
                )
                .padding(20)
                .frame(width: 460, height: 620)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                #endif
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Unable to load script")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: scriptId) {
            isLoading = true
            script = await userScriptManager.userScriptEditorSnapshot(withId: scriptId)
            isLoading = false
        }
    }

    private func setUpdatesAutomatically(_ updatesAutomatically: Bool) {
        guard var currentScript = script else { return }
        currentScript.updatesAutomatically = updatesAutomatically
        script = currentScript
        Task {
            await userScriptManager.setUserScript(currentScript, updatesAutomatically: updatesAutomatically)
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
