import Combine
import Foundation
import wBlockCoreService

@MainActor
final class URLImportReviewCoordinator: ObservableObject {
    struct Metadata: Equatable, Sendable {
        var title: String?
        var description: String?
    }

    @Published var metadata: [String: Metadata] = [:]
    @Published private(set) var isFetchingMetadata = false
    @Published private(set) var isImportingFile = false

    private let identity: (URL) -> String
    private let loadMetadata: @Sendable (URL) async -> Metadata
    private var metadataTask: Task<Void, Never>?
    private var metadataGeneration = 0
    private var importGeneration = 0

    init(
        identity: @escaping (URL) -> String = { $0.absoluteString },
        userscript: Bool = false,
        loadMetadata: (@Sendable (URL) async -> Metadata)? = nil
    ) {
        self.identity = identity
        self.loadMetadata = loadMetadata ?? { url in
            let result = try? await RemoteFilterListMetadataLoader.fetch(from: url, userscript: userscript)
            return Metadata(title: result?.title, description: result?.description)
        }
    }

    func cancelMetadata() {
        metadataTask?.cancel()
        metadataGeneration += 1
        isFetchingMetadata = false
    }

    func fetchMetadata(for urls: [URL], isReviewing: Bool) {
        cancelMetadata()
        guard isReviewing else { return }
        let targets = urls.filter { metadata[identity($0)] == nil }
        guard !targets.isEmpty else { return }
        let generation = metadataGeneration
        let loader = loadMetadata
        isFetchingMetadata = true
        metadataTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, generation == metadataGeneration else { return }
            await boundedConcurrentForEach(targets, maxConcurrent: 4, operation: { url in
                (url, await loader(url))
            }, onResult: { url, result in
                guard !Task.isCancelled, generation == self.metadataGeneration else { return }
                self.metadata[self.identity(url)] = result
            })
            if generation == metadataGeneration { isFetchingMetadata = false }
        }
    }

    func cancelFileImport() {
        importGeneration += 1
        isImportingFile = false
    }

    func importURLList(
        from url: URL,
        onSuccess: @escaping (String) -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        cancelFileImport()
        cancelMetadata()
        let generation = importGeneration
        isImportingFile = true
        let didAccess = url.startAccessingSecurityScopedResource()
        Task { @MainActor in
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try await Task.detached(priority: .userInitiated) {
                    try UserScriptURLSupport.urlListText(fromFile: url)
                }.value
                guard generation == importGeneration else { return }
                onSuccess(text)
                isImportingFile = false
            } catch {
                guard generation == importGeneration else { return }
                isImportingFile = false
                onFailure(error.localizedDescription)
            }
        }
    }
}
