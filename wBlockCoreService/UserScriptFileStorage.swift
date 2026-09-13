import Foundation

/// Shared files precede process-private fallbacks so app updates reach extensions.
enum UserScriptFileStorage {
    nonisolated static func read<Value>(
        fileName: String,
        directories: [URL],
        decode: (Data) -> Value?
    ) -> Value? {
        for (index, directory) in directories.enumerated() {
            let file = directory.appendingPathComponent(fileName)
            guard let data = try? Data(contentsOf: file), let value = decode(data) else { continue }
            if index > 0, let shared = directories.first {
                // Migrate legacy private files only when no shared file exists.
                // copyItem refuses to overwrite a concurrent app update.
                try? FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
                try? FileManager.default.copyItem(at: file, to: shared.appendingPathComponent(fileName))
            }
            return value
        }
        return nil
    }
}
