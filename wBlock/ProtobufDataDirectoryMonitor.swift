import Foundation
import Darwin

/// Monitors the protobuf data directory and coalesces filesystem events.
@MainActor
final class ProtobufDataDirectoryMonitor {
    private let queue: DispatchQueue
    private var source: DispatchSourceFileSystemObject?
    private var pendingTask: Task<Void, Never>?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    @discardableResult
    func start(directoryURL: URL, onChange: @escaping @MainActor @Sendable () -> Void) -> Bool {
        stop()
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return false }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .attrib, .extend],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pendingTask?.cancel()
                self.pendingTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled else { return }
                    onChange()
                    self?.pendingTask = nil
                }
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        self.source = source
        source.resume()
        return true
    }

    func stop() {
        pendingTask?.cancel()
        pendingTask = nil
        source?.cancel()
        source = nil
    }

    deinit {
        pendingTask?.cancel()
        source?.cancel()
    }
}
