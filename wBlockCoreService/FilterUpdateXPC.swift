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

        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let connection = NSXPCConnection(serviceName: serviceName)
            connection.remoteObjectInterface = NSXPCInterface(with: FilterUpdateProtocol.self)

            var finished = false

            connection.invalidationHandler = {
                if !finished { os_log("XPC connection invalidated", log: log, type: .error) }
            }
            connection.interruptionHandler = {
                if !finished { os_log("XPC connection interrupted", log: log, type: .error) }
            }

            connection.resume()

            // Timeout guard
            Task { [weak connection] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if !finished {
                    os_log("XPC request timed out after %.2fs", log: log, type: .error, seconds)
                    finished = true
                    connection?.invalidate()
                    cont.resume(returning: false)
                }
            }

            guard let proxy = connection.remoteObjectProxy as? FilterUpdateProtocol else {
                os_log("Failed to obtain remoteObjectProxy for XPC service", log: log, type: .error)
                finished = true
                connection.invalidate()
                cont.resume(returning: false)
                return
            }

            proxy.updateFilters { success in
                if !finished {
                    finished = true
                    connection.invalidate()
                    cont.resume(returning: success)
                }
            }
        }
    }
}
#endif

