import Foundation
import Darwin

actor CompletionFlag {
    private(set) var completed = false

    func markCompleted() {
        completed = true
    }
}

@main
struct SharedAutoUpdateLeaseTests {
    static func main() async throws {
        let groupIdentifier = "group.skula.wBlock"
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            throw TestError("shared container unavailable")
        }
        let lockURL = containerURL.appendingPathComponent("auto-update.run.lock")
        let readyURL = containerURL.appendingPathComponent("lease-test.ready")
        try? FileManager.default.removeItem(at: readyURL)

        if CommandLine.arguments.contains("--hold-lock") {
            let descriptor = open(lockURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
            precondition(descriptor >= 0, "could not open lease file")
            precondition(flock(descriptor, LOCK_EX | LOCK_NB) == 0, "could not hold lease")
            try Data("ready".utf8).write(to: readyURL)
            dispatchMain()
        }

        do {
            let initial = await SharedAutoUpdateLease.acquire(
                groupIdentifier: groupIdentifier,
                timeout: 0.5
            )
            precondition(initial != nil, "uncontended async acquisition must succeed")
        }

        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--hold-lock"]
        try child.run()
        defer {
            if child.isRunning { child.terminate() }
            try? FileManager.default.removeItem(at: readyURL)
        }

        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: readyURL.path) {
            guard Date() < deadline else { throw TestError("lease holder did not start") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let progress = CompletionFlag()
        let progressTask = Task {
            try await Task.sleep(nanoseconds: 50_000_000)
            await progress.markCompleted()
        }
        let started = Date()
        let contended = await SharedAutoUpdateLease.acquire(
            groupIdentifier: groupIdentifier,
            timeout: 0.2
        )
        let elapsed = Date().timeIntervalSince(started)
        _ = try? await progressTask.value

        precondition(contended == nil, "contended async acquisition must time out")
        let didProgress = await progress.completed
        precondition(didProgress, "async polling must not block other tasks")
        precondition(elapsed >= 0.15 && elapsed < 0.8, "unexpected timeout duration: \(elapsed)")

        child.terminate()
        child.waitUntilExit()
        let released = await SharedAutoUpdateLease.acquire(
            groupIdentifier: groupIdentifier,
            timeout: 0.5
        )
        precondition(released != nil, "acquisition must succeed after holder exits")
        print("PASS: async lease acquisition avoids thread blocking and preserves ownership")
    }

    struct TestError: Error, CustomStringConvertible {
        let description: String

        init(_ description: String) {
            self.description = description
        }
    }
}
