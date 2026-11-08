import Foundation

/// Diagnostics other processes leave in the app group until the app's log view
/// reads them. Past the limit only the newest half is kept.
enum SharedLogFile {
    static let byteLimit = 256 * 1024

    static func append(_ line: String, to filename: String, containerURL: URL? = nil) {
        guard let url = (containerURL ?? FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value
        ))?.appendingPathComponent(filename) else { return }
        let data = Data("[\(Date().ISO8601Format())] \(line)\n".utf8)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? data.write(to: url)
            return
        }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd(), (try? handle.write(contentsOf: data)) != nil,
              end + UInt64(data.count) > byteLimit, let log = try? Data(contentsOf: url) else { return }
        let tail = log.suffix(byteLimit / 2)
        let start = tail.firstIndex(of: 0x0A).map { $0 + 1 } ?? tail.startIndex
        try? Data(tail[start...]).write(to: url, options: .atomic)
    }
}
