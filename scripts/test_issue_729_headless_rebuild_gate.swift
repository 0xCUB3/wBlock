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
