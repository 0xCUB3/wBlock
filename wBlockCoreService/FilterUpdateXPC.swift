//
//  FilterUpdateXPC.swift
//  wBlockCoreService
//
//  Defines the XPC interface and a lightweight client to talk to a future
//  macOS XPC service that performs background filter updates.
//

import Foundation
import os.log

#if os(macOS)
@objc public protocol FilterUpdateProtocol {
    func updateFilters(_ reply: @escaping (Bool) -> Void)
}

public enum FilterUpdateClientResult: Sendable {
    case succeeded
    case unavailable
    case timedOut
}

public final class FilterUpdateClient {
    public static let shared = FilterUpdateClient()
    private init() {}

    // Adopt a bundle-identifier-like service name for the XPC service target
    // When you add the XPC Service target, set its bundle identifier to this value.
    public let serviceName = "skula.wBlock.FilterUpdateService"

    /// Calls the XPC service to run an update.
    /// A timeout is distinct from an unavailable service because the remote
    /// update may still be running after the client stops waiting.
    public func updateFilters(timeout seconds: TimeInterval = 180.0) async -> FilterUpdateClientResult {
        let log = OSLog(subsystem: "wBlockCoreService", category: "FilterUpdateXPC")
        guard seconds.isFinite, seconds >= 0 else {
            os_log("Invalid XPC timeout: %.2fs", log: log, type: .error, seconds)
            return .unavailable
        }

        let timeoutNanoseconds = if seconds == 0 {
            UInt64.zero
        } else {
            min(UInt64.max, UInt64((seconds * 1_000_000_000).rounded()))
        }

        return await withCheckedContinuation { (cont: CheckedContinuation<FilterUpdateClientResult, Never>) in
            let connection = NSXPCConnection(serviceName: serviceName)
            connection.remoteObjectInterface = NSXPCInterface(with: FilterUpdateProtocol.self)
            let stateLock = NSLock()
            var timeoutTask: Task<Void, Never>?
            var finished = false

            func markFinished() -> Bool {
                stateLock.lock()
                defer { stateLock.unlock() }
                if finished {
                    return false
                }
                finished = true
                timeoutTask?.cancel()
                timeoutTask = nil
                return true
            }

            connection.invalidationHandler = {
                if markFinished() {
                    os_log("XPC connection invalidated", log: log, type: .error)
                    cont.resume(returning: .unavailable)
                }
            }
            connection.interruptionHandler = {
                if markFinished() {
                    os_log("XPC connection interrupted", log: log, type: .error)
                    cont.resume(returning: .unavailable)
                }
            }

            connection.resume()

            // Timeout guard
            timeoutTask = Task { [weak connection] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                if markFinished() {
                    os_log("XPC request timed out after %.2fs", log: log, type: .error, seconds)
                    connection?.invalidate()
                    cont.resume(returning: .timedOut)
                }
            }

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                if markFinished() {
                    os_log("Failed to obtain remoteObjectProxy for XPC service: %{public}@", log: log, type: .error, error.localizedDescription)
                    connection.invalidate()
                    cont.resume(returning: .unavailable)
                }
            }

            guard let filterProxy = proxy as? FilterUpdateProtocol else {
                os_log("Failed to cast remoteObjectProxy to FilterUpdateProtocol", log: log, type: .error)
                if markFinished() {
                    connection.invalidate()
                    cont.resume(returning: .unavailable)
                }
                return
            }

            filterProxy.updateFilters { success in
                if markFinished() {
                    connection.invalidate()
                    cont.resume(returning: success ? .succeeded : .unavailable)
                }
            }
        }
    }
}
#endif
