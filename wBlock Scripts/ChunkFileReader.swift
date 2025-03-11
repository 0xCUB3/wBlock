// Fully from WebShield

import Foundation

final class ChunkFileReader {
    private let fileURL: URL
    private let chunkSize: Int
    private let totalSize: UInt64
    private var currentOffset: UInt64 = 0
    private var fileHandle: FileHandle

    init(fileURL: URL, chunkSize: Int = 32768) throws {
        self.fileURL = fileURL
        self.chunkSize = chunkSize
        self.totalSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64 ?? 0
        // Open the file handle once and store it.
        self.fileHandle = try FileHandle(forReadingFrom: fileURL)
    }

    deinit {
        // Ensure the file handle is closed when the actor is deallocated.
        try? fileHandle.close()
    }

    /// Reads the next chunk from the file as a UTF-8 String.
    func nextChunk() -> String? {
        // If we've reached or exceeded the total file size, there's nothing more to read.
        guard currentOffset < totalSize else { return nil }

        do {
            // Seek to the current offset.
            try fileHandle.seek(toOffset: currentOffset)
            // Read the next chunk.
            if let data = try fileHandle.read(upToCount: chunkSize), !data.isEmpty {
                // Update the offset based on the number of bytes actually read.
                currentOffset += UInt64(data.count)
                return String(decoding: data, as: UTF8.self)
            } else {
                return nil
            }
        } catch {
            print("Error reading chunk: \(error)")
            return nil
        }
    }

    /// Resets the file reading to the beginning.
    func rewind() {
        currentOffset = 0
        do {
            try fileHandle.seek(toOffset: 0)
        } catch {
            print("Error rewinding: \(error)")
        }
    }

    /// Returns the progress of file reading as a fraction between 0 and 1.
    var progress: Double {
        return Double(currentOffset) / Double(totalSize)
    }
}
