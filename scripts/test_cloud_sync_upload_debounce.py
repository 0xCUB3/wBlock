"""Exercise the production upload scheduler with a controlled sleep and upload spy."""
from pathlib import Path
import subprocess
import tempfile

source = Path("wBlock/CloudSyncManager.swift").read_text()
start = source.index("    private func scheduleUpload(trigger: String)")
end = source.index("    private func setLastSyncError", start)
method = source[start:end]
harness = r'''import Foundation
import os

@MainActor enum TaskSleep {
    static var waits: [UUID: CheckedContinuation<Void, Error>] = [:]
    static var didWait: CheckedContinuation<Void, Never>?

    static func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                waits[id] = continuation
                didWait?.resume()
                didWait = nil
            }
        } onCancel: {
            Task { @MainActor in waits.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
        }
    }

    static func waitUntilSleeping() async {
        if !waits.isEmpty { return }
        await withCheckedContinuation { didWait = $0 }
    }

    static func finish() {
        let pending = waits.values
        waits.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

@MainActor final class Harness {
    var uploadCoordinator = CloudSyncUploadCoordinator()
    var isSyncing = false
    var pendingUploadTask: Task<Void, Never>?
    var uploads: [String] = []
    let logger = Logger(subsystem: "wblock.tests", category: "upload-debounce")

    func schedule(_ trigger: String) { scheduleUpload(trigger: trigger) }
    func uploadLatestPayload(trigger: String) async { uploads.append(trigger) }
METHOD
}

@main struct Test {
    @MainActor static func main() async {
        let manager = Harness()
        manager.schedule("first")
        let first = manager.pendingUploadTask!
        await TaskSleep.waitUntilSleeping()
        manager.schedule("latest")
        let latest = manager.pendingUploadTask!
        await first.value
        require(manager.uploads.isEmpty, "replaced pending upload must not begin payload work")
        require(manager.pendingUploadTask == latest, "old task cleanup must preserve the latest handle")
        await TaskSleep.waitUntilSleeping()
        TaskSleep.finish()
        await latest.value
        require(manager.uploads == ["latest"], "latest change must upload when its debounce ends")
        require(manager.pendingUploadTask == nil, "completed task must clear its handle")

        manager.schedule("cancel-before-start")
        let cancelled = manager.pendingUploadTask!
        cancelled.cancel()
        await cancelled.value
        require(manager.uploads == ["latest"], "cancellation before the task starts must also skip upload")
        require(manager.pendingUploadTask == nil, "cancelled task must clear its own handle")

        manager.schedule("cancel-at-deadline")
        let atDeadline = manager.pendingUploadTask!
        await TaskSleep.waitUntilSleeping()
        TaskSleep.finish()
        atDeadline.cancel()
        await atDeadline.value
        require(manager.uploads == ["latest"], "cancellation after sleep resumes must still skip upload")

        manager.isSyncing = true
        manager.schedule("deferred-first")
        manager.schedule("deferred-latest")
        require(manager.pendingUploadTask == nil, "active sync must defer without starting a debounce")
        manager.isSyncing = false
        let deferred = manager.uploadCoordinator.takeDeferredTrigger()!
        manager.schedule(deferred)
        let replay = manager.pendingUploadTask!
        await TaskSleep.waitUntilSleeping()
        TaskSleep.finish()
        await replay.value
        require(manager.uploads == ["latest", "deferred-latest"], "latest deferred trigger must still replay")
        print("PASS cloud sync upload debounce")
    }

    static func require(_ value: Bool, _ message: String) {
        guard value else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
}
'''.replace("METHOD", method)
with tempfile.TemporaryDirectory(prefix="wblock-upload-debounce-") as temp:
    test = Path(temp) / "test.swift"
    test.write_text(harness)
    binary = str(Path(temp) / "test")
    subprocess.run(["swiftc", "-parse-as-library", "wBlockCoreService/AsyncConcurrency.swift", str(test), "-o", binary], check=True)
    subprocess.run([binary], check=True, timeout=15)
