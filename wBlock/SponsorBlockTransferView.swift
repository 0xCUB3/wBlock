import SwiftUI
import UniformTypeIdentifiers
import wBlockCoreService

struct SponsorBlockTransferButton: View {
    let scriptID: UUID
    @State private var showingTransfer = false

    var body: some View {
        Button { showingTransfer = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.badge.gearshape")
                    .imageScale(.small)
                Text("SponsorBlock Backups")
                    .fontWeight(.medium)
                    .lineLimit(1)
                Image(systemName: "chevron.forward")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .noFocusRingCompat()
        .sheet(isPresented: $showingTransfer) {
            SponsorBlockTransferView(scriptID: scriptID)
        }
    }
}

private struct SponsorBlockSettingsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct SponsorBlockTransferView: View {
    let scriptID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var exporting = false
    @State private var busy = false
    @State private var pending: SponsorBlockSettingsTransfer.Settings?
    @State private var confirming = false
    @State private var document: SponsorBlockSettingsDocument?
    @State private var status: LocalizedStringKey = ""
    @State private var showingStatus = false

    private var form: some View {
        Form {
            Section {
                Text("Transfers category choices, skip notices, minimum segment length, and legacy channel allowlists. Private user IDs, contributions, and per-channel profiles are excluded. Seek-bar-only categories become Disabled.")
                Text("Use Tube Cleaner 0.1.36 or later. Reload YouTube after importing; open a video before exporting settings changed in Safari.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Import SponsorBlock Settings") { importing = true }
                Button("Export SponsorBlock Settings") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            guard let settings = try await SponsorBlockSettingsTransfer.settings(scriptID: scriptID) else {
                                notify("No synced SponsorBlock settings yet. Open YouTube with Tube Cleaner enabled, then try again.")
                                return
                            }
                            document = SponsorBlockSettingsDocument(data: try SponsorBlockSettingsTransfer.exportData(settings))
                            exporting = true
                        } catch { transferFailed() }
                    }
                }
            }
            .disabled(busy)
            if busy { ProgressView() }
        }
        .groupedFormStyleCompat()
    }

    var body: some View {
        SheetContainer {
            SheetHeader(title: "SponsorBlock Backups", isLoading: busy) { dismiss() }
            form
        }
        #if os(macOS)
        .frame(width: 520, height: 420)
        #endif
        .interactiveDismissDisabled(busy)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                busy = true
                Task {
                    defer { busy = false }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        // Bound the read itself, not just JSON parsing. Never save
                        // or log the original file, which may contain a private ID.
                        let handle = try FileHandle(forReadingFrom: url)
                        defer { try? handle.close() }
                        let data = try handle.read(upToCount: SponsorBlockSettingsTransfer.maximumBytes + 1) ?? Data()
                        let current = try await SponsorBlockSettingsTransfer.settings(scriptID: scriptID)
                        pending = try SponsorBlockSettingsTransfer.parse(data, current: current ?? .init())
                        confirming = true
                    } catch { transferFailed() }
                }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { transferFailed() }
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: "wBlock-SponsorBlock-settings") { result in
            if case .failure(let error) = result, (error as NSError).code != NSUserCancelledError { transferFailed() }
            document = nil
        }
        .confirmationDialog("Replace SponsorBlock settings?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Import") {
                guard let settings = pending else { return }
                pending = nil
                busy = true
                Task {
                    defer { busy = false }
                    do {
                        try await SponsorBlockSettingsTransfer.save(settings, scriptID: scriptID)
                        notify("Settings imported. Reload YouTube to apply them.")
                    } catch { transferFailed() }
                }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        }
        .alert("SponsorBlock Backups", isPresented: $showingStatus) {
            Button("OK") {}
        } message: { Text(status) }
    }

    private func notify(_ message: LocalizedStringKey) { status = message; showingStatus = true }
    private func transferFailed() {
        pending = nil
        notify("Could not transfer SponsorBlock settings. Use a valid settings JSON file and check available storage.")
    }
}
