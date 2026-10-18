import Foundation
import os.log

enum CoordinatedDiskAccess {
    static func withWriteAccess<T>(
        for dataURL: URL,
        fileManager: FileManager,
        logger: Logger,
        fallbackError: @autoclosure () -> Error,
        _ operation: () throws -> T
    ) throws -> T {
        let directoryURL = dataURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        let coordinationURL = fileManager.fileExists(atPath: dataURL.path) ? dataURL : directoryURL
        let startedAt = Date()
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationResult: Result<T, Error>?

        coordinator.coordinate(writingItemAt: coordinationURL, options: [], error: &coordinationError) { _ in
            operationResult = Result { try operation() }
        }

        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        if durationMs >= 100 {
            logger.warning(
                "File coordination held for \(durationMs) ms: \(dataURL.lastPathComponent)"
            )
        }

        if let operationResult {
            return try operationResult.get()
        }

        if let coordinationError {
            throw coordinationError
        }

        throw fallbackError()
    }
}
