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

public final class FilterUpdateClient {
    public static let shared = FilterUpdateClient()
    private init() {}

    // Adopt a bundle-identifier-like service name for the XPC service target
    // When you add the XPC Service target, set its bundle identifier to this value.
    public let serviceName = "skula.wBlock.FilterUpdateService"

    /// Calls the XPC service to run an update, returning true on success.
    /// If the service is missing or fails to respond within the timeout, returns false.
    public func updateFilters(timeout seconds: TimeInterval = 2.0) async -> Bool {
        let log = OSLog(subsystem: "wBlockCoreService", category: "FilterUpdateXPC")
        guard seconds.isFinite, seconds >= 0 else {
            os_log("Invalid XPC timeout: %.2fs", log: log, type: .error, seconds)
            return false
        }

        let timeoutNanoseconds = if seconds == 0 {
            UInt64.zero
        } else {
            min(UInt64.max, UInt64((seconds * 1_000_000_000).rounded()))
        }

        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let connection = NSXPCConnection(serviceName: serviceName)
            connection.remoteObjectInterface = NSXPCInterface(with: FilterUpdateProtocol.self)
            let stateLock = NSLock()
            var finished = false

            func markFinished() -> Bool {
                stateLock.lock()
                defer { stateLock.unlock() }
                if finished {
                    return false
                }
                finished = true
                return true
            }

            connection.invalidationHandler = {
                if markFinished() {
                    os_log("XPC connection invalidated", log: log, type: .error)
                    cont.resume(returning: false)
                }
            }
            connection.interruptionHandler = {
                if markFinished() {
                    os_log("XPC connection interrupted", log: log, type: .error)
                    cont.resume(returning: false)
                }
            }

            connection.resume()

            // Timeout guard
            Task { [weak connection] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                if markFinished() {
                    os_log("XPC request timed out after %.2fs", log: log, type: .error, seconds)
                    connection?.invalidate()
                    cont.resume(returning: false)
                }
            }

            guard let proxy = connection.remoteObjectProxy as? FilterUpdateProtocol else {
                os_log("Failed to obtain remoteObjectProxy for XPC service", log: log, type: .error)
                if markFinished() {
                    connection.invalidate()
                    cont.resume(returning: false)
                }
                return
            }

            proxy.updateFilters { success in
                if markFinished() {
                    connection.invalidate()
                    cont.resume(returning: success)
                }
            }
        }
    }
}
#endif
