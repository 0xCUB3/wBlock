import Foundation

enum UserScriptUpdateOperation {
    /// Runs one remote update transaction. A superseded operation never reaches commit,
    /// and commit is responsible for returning true only after durable persistence.
    @MainActor
    static func run<Downloaded, Prepared>(
        downloadURL: URL,
        fetch: (URL) async throws -> Downloaded,
        isCurrent: () -> Bool,
        prepare: (Downloaded) async throws -> Prepared,
        commit: (Prepared) async throws -> Bool
    ) async rethrows -> Bool {
        guard !Task.isCancelled, isCurrent() else { return false }
        let downloaded = try await fetch(downloadURL)
        guard !Task.isCancelled, isCurrent() else { return false }

        let prepared = try await prepare(downloaded)
        guard !Task.isCancelled, isCurrent() else { return false }

        return try await commit(prepared)
    }
}
