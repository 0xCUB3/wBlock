import Foundation
import wBlockCoreService

@main
struct Test {
    static func main() throws {
        func require(_ condition: Bool, _ message: String) {
            guard condition else {
                fputs("FAIL: \(message)\n", stderr)
                exit(1)
            }
        }

        if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "--child" {
            let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            let now = TimeInterval(CommandLine.arguments[3])!
            let startAt = TimeInterval(CommandLine.arguments[4])!
            while Date().timeIntervalSince1970 < startAt {
                usleep(1_000)
            }
            let allowed = HeadlessLaunch.consumeAutoRebuildLaunchSlot(now: now, gateDirectory: directory)
            print(allowed ? "1" : "0")
            return
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-headless-gate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now: TimeInterval = 10_000
        require(
            HeadlessLaunch.isAutoRebuildLaunchAllowed(now: now, state: nil),
            "missing gate state should allow the first staged rebuild launch"
        )

        let launched = HeadlessLaunch.AutoRebuildGateState(
            lastAttemptAt: now - HeadlessLaunch.autoRebuildCooldownSeconds + 1,
            failureCount: 0,
            lastOutcome: HeadlessLaunch.AutoRebuildLaunchOutcome.launched.rawValue
        )
        require(
            !HeadlessLaunch.isAutoRebuildLaunchAllowed(now: now, state: launched),
            "a recent launch attempt should be cooldown-limited even before the app reports a result"
        )
        require(
            HeadlessLaunch.isAutoRebuildLaunchAllowed(
                now: now,
                state: HeadlessLaunch.AutoRebuildGateState(
                    lastAttemptAt: now - HeadlessLaunch.autoRebuildCooldownSeconds,
                    failureCount: 0,
                    lastOutcome: HeadlessLaunch.AutoRebuildLaunchOutcome.rebuildSucceeded.rawValue
                )
            ),
            "successful rebuilds should return to the base cooldown"
        )

        let firstFailureDelay = HeadlessLaunch.autoRebuildDelay(forFailureCount: 1)
        let thirdFailureDelay = HeadlessLaunch.autoRebuildDelay(forFailureCount: 3)
        require(firstFailureDelay == HeadlessLaunch.autoRebuildCooldownSeconds, "first failure uses base delay")
        require(thirdFailureDelay == HeadlessLaunch.autoRebuildCooldownSeconds * 4, "failures use exponential backoff")
        require(
            HeadlessLaunch.autoRebuildDelay(forFailureCount: 99) == HeadlessLaunch.autoRebuildMaximumBackoffSeconds,
            "backoff is capped"
        )

        let failed = HeadlessLaunch.AutoRebuildGateState(
            lastAttemptAt: now - thirdFailureDelay + 1,
            failureCount: 3,
            lastOutcome: HeadlessLaunch.AutoRebuildLaunchOutcome.rebuildFailed.rawValue
        )
        require(
            !HeadlessLaunch.isAutoRebuildLaunchAllowed(now: now, state: failed),
            "recent rebuild failures should hold the longer backoff"
        )
        require(
            HeadlessLaunch.isAutoRebuildLaunchAllowed(now: now + 1, state: failed),
            "launch should reopen after the failure backoff expires"
        )

        let decisionDirectory = root.appendingPathComponent("decisions", isDirectory: true)
        require(
            HeadlessLaunch.consumeAutoRebuildLaunchSlot(now: now, gateDirectory: decisionDirectory),
            "first launch slot should be persisted and allowed"
        )
        require(
            !HeadlessLaunch.consumeAutoRebuildLaunchSlot(
                now: now + HeadlessLaunch.autoRebuildCooldownSeconds - 1,
                gateDirectory: decisionDirectory
            ),
            "persisted launch slot should block another launch inside cooldown"
        )
        require(
            HeadlessLaunch.loadAutoRebuildGateState(gateDirectory: decisionDirectory) == HeadlessLaunch.AutoRebuildGateState(
                lastAttemptAt: now,
                failureCount: 1,
                lastOutcome: HeadlessLaunch.AutoRebuildLaunchOutcome.launched.rawValue
            ),
            "blocked decisions should not rewrite the persisted launch attempt"
        )

        require(
            HeadlessLaunch.consumeAutoRebuildLaunchSlot(
                now: now + HeadlessLaunch.autoRebuildCooldownSeconds,
                gateDirectory: decisionDirectory
            ),
            "a missing result after cooldown should be treated as a crashed attempt and allow one retry"
        )
        let crashedOnce = HeadlessLaunch.loadAutoRebuildGateState(gateDirectory: decisionDirectory)
        require(crashedOnce?.failureCount == 2, "crashed attempts should increase the persisted failure count")
        require(
            !HeadlessLaunch.consumeAutoRebuildLaunchSlot(
                now: now + HeadlessLaunch.autoRebuildCooldownSeconds * 3 - 1,
                gateDirectory: decisionDirectory
            ),
            "repeated crash attempts should move onto exponential backoff"
        )

        require(
            HeadlessLaunch.recordAutoRebuildLaunchOutcome(
                .rebuildSucceeded,
                now: now + HeadlessLaunch.autoRebuildCooldownSeconds * 4,
                gateDirectory: decisionDirectory
            ),
            "recording rebuild success should persist"
        )
        let succeeded = HeadlessLaunch.loadAutoRebuildGateState(gateDirectory: decisionDirectory)
        require(succeeded?.failureCount == 0, "success should clear the persisted failure count")
        require(
            succeeded?.lastOutcome == HeadlessLaunch.AutoRebuildLaunchOutcome.rebuildSucceeded.rawValue,
            "success should persist its outcome"
        )

        let blockedPath = root.appendingPathComponent("not-a-directory", isDirectory: false)
        try Data().write(to: blockedPath)
        require(
            !HeadlessLaunch.consumeAutoRebuildLaunchSlot(now: now, gateDirectory: blockedPath),
            "failed persistence should not grant a launch slot"
        )

        let concurrentDirectory = root.appendingPathComponent("concurrent", isDirectory: true)
        try FileManager.default.createDirectory(at: concurrentDirectory, withIntermediateDirectories: true)
        let childCount = 10
        let startAt = Date().timeIntervalSince1970 + 0.25
        let children = try (0..<childCount).map { _ -> (process: Process, output: Pipe) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = [
                "--child",
                concurrentDirectory.path,
                String(now),
                String(startAt)
            ]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            try process.run()
            return (process, output)
        }
        let allowedCount = children.reduce(into: 0) { count, child in
            child.process.waitUntilExit()
            require(child.process.terminationStatus == 0, "child gate process should exit cleanly")
            let output = child.output.fileHandleForReading.readDataToEndOfFile()
            if String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "1" {
                count += 1
            }
        }
        require(allowedCount == 1, "serialized gate should allow exactly one concurrent process")

        print("PASS test_issue_729_headless_rebuild_gate")
    }
}
