//
//  LogErrorDescriber.swift
//  wBlockCoreService
//
//  Formats any Swift Error into a single log-friendly string that keeps the
//  pieces needed to diagnose it: the domain and code for NSErrors, the
//  human description, and any underlying error chain. Prefer this over
//  `error.localizedDescription` when writing to the app log, because the
//  latter collapses most Foundation and WebKit errors into "The operation
//  couldn't be completed."
//

import Foundation

public enum LogErrorDescriber {
    /// Maximum depth of the underlying-error chain that is rendered.
    private static let maxUnderlyingDepth = 3

    /// One-line description such as
    /// `WKErrorDomain 6: Could not access the rules file (NSPOSIXErrorDomain 2: No such file or directory)`.
    public static func describe(_ error: Error) -> String {
        var parts: [String] = []
        var current: Error? = error
        var depth = 0
        while let error = current, depth < maxUnderlyingDepth {
            parts.append(describeSingle(error))
            current = underlyingError(of: error)
            depth += 1
        }
        guard let first = parts.first else { return "\(error)" }
        if parts.count == 1 { return first }
        return first + " (" + parts.dropFirst().joined(separator: " <- ") + ")"
    }

    private static func describeSingle(_ error: Error) -> String {
        let nsError = error as NSError
        let description = bestDescription(for: error, nsError: nsError)
        let isSwiftError = nsError.domain.hasSuffix(".\(String(describing: type(of: error)))")
            || nsError.domain.contains("Swift") && nsError.code == 1
        if isSwiftError {
            // Swift-native errors carry no meaningful domain/code; use the type
            // name so the source of the error stays visible.
            let typeName = String(describing: type(of: error))
            if description.isEmpty || description == typeName {
                return "\(typeName): \(String(describing: error))"
            }
            return "\(typeName): \(description)"
        }
        if description.isEmpty {
            return "\(nsError.domain) \(nsError.code)"
        }
        return "\(nsError.domain) \(nsError.code): \(description)"
    }

    private static func bestDescription(for error: Error, nsError: NSError) -> String {
        if let localized = error as? LocalizedError,
           let text = localized.errorDescription, !text.isEmpty {
            return text
        }
        if let failure = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String, !failure.isEmpty {
            return failure
        }
        if let debug = nsError.userInfo[NSDebugDescriptionErrorKey] as? String, !debug.isEmpty {
            return debug
        }
        if nsError.domain == NSPOSIXErrorDomain {
            // POSIX errors localize to "Error Domain=... Code=..." noise; strerror is the useful part.
            return String(cString: strerror(Int32(nsError.code)))
        }
        let generic = nsError.localizedDescription
        // Foundation's fallback text hides the real problem. The domain and
        // code are already in the line, so prefer any descriptive userInfo
        // string and otherwise drop the placeholder rather than dump the
        // whole NSError.
        if generic.hasPrefix("The operation couldn") || generic.hasPrefix("The operation could not")
            || generic.hasPrefix("Error Domain=") {
            if let recovery = nsError.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String, !recovery.isEmpty {
                return recovery
            }
            if let description = nsError.userInfo[NSLocalizedDescriptionKey] as? String, !description.isEmpty {
                return description
            }
            return ""
        }
        return generic
    }

    private static func underlyingError(of error: Error) -> Error? {
        let nsError = error as NSError
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return underlying
        }
        if #available(macOS 11.3, iOS 14.5, *),
           let list = nsError.userInfo[NSMultipleUnderlyingErrorsKey] as? [Error],
           let first = list.first {
            return first
        }
        return nil
    }
}
