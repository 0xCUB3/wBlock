import Foundation

#if os(macOS)
import AppKit
import Darwin
#endif

/// Coordinates the macOS headless launch of the containing app (#528).
///
/// When the background agent is off, the Safari extension can still download
/// changed filter lists, but only the app can rebuild them and reload Safari.
/// Rather than ask the user to open the app, the extension launches it with a
/// marker argument. The app then runs as an accessory process (no Dock icon,
/// no window), performs the rebuild, and terminates itself.
public enum HeadlessLaunch {
    public struct AutoRebuildGateState: Codable, Equatable, Sendable {
        public var lastAttemptAt: TimeInterval
        public var failureCount: Int
        public var lastOutcome: String

        public init(lastAttemptAt: TimeInterval = 0, failureCount: Int = 0, lastOutcome: String = "") {
            self.lastAttemptAt = lastAttemptAt
            self.failureCount = failureCount
            self.lastOutcome = lastOutcome
        }
    }

    public enum AutoRebuildLaunchOutcome: String, Sendable {
        case launched
        case launchFailed
        case rebuildSucceeded
        case rebuildFailed
    }

    public static let autoRebuildCooldownSeconds: TimeInterval = 15 * 60
    public static let autoRebuildMaximumBackoffSeconds: TimeInterval = 6 * 60 * 60
    public static let autoRebuildMaximumTrackedFailures = 9
    public static let autoRebuildGateFilename = "headless-auto-rebuild-gate.json"
    private static let autoRebuildGateLockFilename = "headless-auto-rebuild-gate.lock"
    private static let autoRebuildGateLockTimeoutSeconds: TimeInterval = 2
    private static let autoRebuildGateLockRetryMicroseconds: UInt32 = 20_000

    public enum Reason: String, Sendable {
        case popupUpdate = "popup-update"
        case stagedDownloads = "staged-downloads"
    }

    public static let argument = "--wblock-headless-update"
    public static let containingAppBundleIdentifier = "skula.wBlock"

    public static func arguments(for reason: Reason) -> [String] {
        [argument, reason.rawValue]
    }

    /// The reason encoded in the current process's launch arguments, if any.
    public static func reason(in arguments: [String] = ProcessInfo.processInfo.arguments) -> Reason? {
        guard let index = arguments.firstIndex(of: argument) else { return nil }
        let next = arguments.indices.contains(index + 1) ? arguments[index + 1] : ""
        return Reason(rawValue: next) ?? .popupUpdate
    }

    public static var isHeadlessProcess: Bool {
        reason() != nil
    }

    #if os(macOS)
    /// The containing app for an extension bundle at
    /// wBlock.app/Contents/PlugIns/<name>.appex.
    public static func containingAppURL(from bundleURL: URL = Bundle.main.bundleURL) -> URL? {
        var url = bundleURL
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" {
                return url
            }
            url.deleteLastPathComponent()
        }
        return nil
    }

    /// True when the extension has staged downloads and no resident process
    /// will pick them up: the app is closed and the background agent is off.
    /// The positive decision is persisted as an attempt so repeated extension
    /// events cannot launch invisible app instances without a cooldown.
    public static func shouldAutoRebuildAfterStaging() async -> Bool {
        guard await ProtobufDataManager.shared.backgroundAgentDisabled else { return false }
        guard !isContainingAppRunning() else { return false }
        return consumeAutoRebuildLaunchSlot()
    }

    @discardableResult
    public static func recordAutoRebuildLaunchOutcome(
        _ outcome: AutoRebuildLaunchOutcome,
        now: TimeInterval = Date().timeIntervalSince1970,
        gateDirectory: URL? = nil
    ) -> Bool {
        guard let gateDirectory = gateDirectory ?? autoRebuildGateDirectory() else { return false }
        return updateAutoRebuildGateState(gateDirectory: gateDirectory) { state in
            switch outcome {
            case .launched:
                state.failureCount = failureCountForReservedLaunch(after: state)
                state.lastAttemptAt = now
                state.lastOutcome = outcome.rawValue
            case .launchFailed, .rebuildFailed:
                state.failureCount = failureCountForCompletedFailure(after: state)
                state.lastAttemptAt = now
                state.lastOutcome = outcome.rawValue
            case .rebuildSucceeded:
                state.failureCount = 0
                state.lastAttemptAt = now
                state.lastOutcome = outcome.rawValue
            }
            return true
        }
    }

    public static func isAutoRebuildLaunchAllowed(
        now: TimeInterval,
        state: AutoRebuildGateState?
    ) -> Bool {
        guard let state, state.lastAttemptAt > 0 else { return true }
        guard now >= state.lastAttemptAt else { return false }
        return now - state.lastAttemptAt >= autoRebuildDelay(forFailureCount: state.failureCount)
    }

    public static func autoRebuildDelay(forFailureCount failureCount: Int) -> TimeInterval {
        let safeFailureCount = boundedAutoRebuildFailureCount(failureCount)
        guard safeFailureCount > 0 else { return autoRebuildCooldownSeconds }
        let multiplier = pow(2.0, Double(safeFailureCount - 1))
        return min(autoRebuildMaximumBackoffSeconds, autoRebuildCooldownSeconds * multiplier)
    }

    public static func loadAutoRebuildGateState(
        groupIdentifier: String = GroupIdentifier.shared.value
    ) -> AutoRebuildGateState? {
        guard let url = autoRebuildGateURL(groupIdentifier: groupIdentifier) else { return nil }
        return loadAutoRebuildGateState(at: url)
    }

    public static func loadAutoRebuildGateState(gateDirectory: URL) -> AutoRebuildGateState? {
        loadAutoRebuildGateState(at: autoRebuildGateURL(gateDirectory: gateDirectory))
    }

    @discardableResult
    public static func consumeAutoRebuildLaunchSlot(
        now: TimeInterval = Date().timeIntervalSince1970,
        gateDirectory: URL
    ) -> Bool {
        var allowed = false
        let persisted = updateAutoRebuildGateState(gateDirectory: gateDirectory) { state in
            allowed = isAutoRebuildLaunchAllowed(now: now, state: state)
            guard allowed else { return false }
            state.failureCount = failureCountForReservedLaunch(after: state)
            state.lastAttemptAt = now
            state.lastOutcome = AutoRebuildLaunchOutcome.launched.rawValue
            return true
        }
        return allowed && persisted
    }

    @discardableResult
    private static func consumeAutoRebuildLaunchSlot() -> Bool {
        guard let gateDirectory = autoRebuildGateDirectory() else { return false }
        return consumeAutoRebuildLaunchSlot(gateDirectory: gateDirectory)
    }

    private static func updateAutoRebuildGateState(
        gateDirectory: URL,
        _ update: (inout AutoRebuildGateState) -> Bool
    ) -> Bool {
        do {
            return try withAutoRebuildGateLock(gateDirectory: gateDirectory) {
                var state = loadAutoRebuildGateState(gateDirectory: gateDirectory) ?? AutoRebuildGateState()
                let shouldSave = update(&state)
                guard shouldSave else { return true }
                try saveAutoRebuildGateState(state, gateDirectory: gateDirectory)
                return true
            }
        } catch {
            return false
        }
    }

    private static func saveAutoRebuildGateState(
        _ state: AutoRebuildGateState,
        gateDirectory: URL
    ) throws {
        let data = try JSONEncoder().encode(state)
        try data.write(to: autoRebuildGateURL(gateDirectory: gateDirectory), options: .atomic)
    }

    private static func loadAutoRebuildGateState(at url: URL) -> AutoRebuildGateState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AutoRebuildGateState.self, from: data)
    }

    private static func autoRebuildGateDirectory(
        groupIdentifier: String = GroupIdentifier.shared.value
    ) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    private static func autoRebuildGateURL(groupIdentifier: String) -> URL? {
        autoRebuildGateDirectory(groupIdentifier: groupIdentifier)
            .map { autoRebuildGateURL(gateDirectory: $0) }
    }

    private static func autoRebuildGateURL(gateDirectory: URL) -> URL {
        gateDirectory.appendingPathComponent(autoRebuildGateFilename, isDirectory: false)
    }

    private static func failureCountForReservedLaunch(after state: AutoRebuildGateState) -> Int {
        let failureCount = boundedAutoRebuildFailureCount(state.failureCount)
        guard state.lastAttemptAt > 0 else { return 1 }
        if state.lastOutcome == AutoRebuildLaunchOutcome.rebuildSucceeded.rawValue {
            return 1
        }
        return incrementedAutoRebuildFailureCount(failureCount)
    }

    private static func failureCountForCompletedFailure(after state: AutoRebuildGateState) -> Int {
        let failureCount = boundedAutoRebuildFailureCount(state.failureCount)
        if state.lastOutcome == AutoRebuildLaunchOutcome.launched.rawValue {
            return max(1, failureCount)
        }
        return incrementedAutoRebuildFailureCount(failureCount)
    }

    private static func boundedAutoRebuildFailureCount(_ failureCount: Int) -> Int {
        min(max(0, failureCount), autoRebuildMaximumTrackedFailures)
    }

    private static func incrementedAutoRebuildFailureCount(_ failureCount: Int) -> Int {
        min(boundedAutoRebuildFailureCount(failureCount) + 1, autoRebuildMaximumTrackedFailures)
    }

    private static func withAutoRebuildGateLock<T>(
        gateDirectory: URL,
        _ operation: () throws -> T
    ) throws -> T {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: gateDirectory, withIntermediateDirectories: true)
        let lockURL = gateDirectory.appendingPathComponent(autoRebuildGateLockFilename, isDirectory: false)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            let error = errno
            throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
        }
        do {
            try lockAutoRebuildGate(descriptor: descriptor)
        } catch {
            close(descriptor)
            throw error
        }
        defer {
            _ = flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        return try operation()
    }

    private static func lockAutoRebuildGate(descriptor: Int32) throws {
        let deadline = Date().timeIntervalSince1970 + autoRebuildGateLockTimeoutSeconds
        while true {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                return
            }
            let error = errno
            guard error == EWOULDBLOCK || error == EAGAIN else {
                throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
            }
            guard Date().timeIntervalSince1970 < deadline else {
                throw POSIXError(.ETIMEDOUT)
            }
            usleep(autoRebuildGateLockRetryMicroseconds)
        }
    }

    public static func isContainingAppRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: containingAppBundleIdentifier)
            .contains { !$0.isTerminated }
    }
    #endif
}
