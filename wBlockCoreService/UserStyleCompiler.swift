//
//  UserStyleCompiler.swift
//  wBlockCoreService
//
//  Offline Less 4.9.0 compiler bridge. Each render uses a fresh JavaScriptCore
//  context with no host objects exposed; the bundle is vendored in Resources.
//

import Foundation
import JavaScriptCore

enum UserStyleCompiler {
    struct CompilationError: Error, LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }
    }

    private static let renderLock = NSLock()
    static let maximumSourceBytes = 2 * 1024 * 1024
    static let maximumOutputBytes = 10 * 1024 * 1024

#if DEBUG
    // Test-only injection keeps the compiler test independent of Bundle layout.
    static var compilerSourceOverride: String?
#endif

    static func compile(_ source: String, variables: [UserStyleSupport.Variable]) throws -> String {
        renderLock.lock()
        defer { renderLock.unlock() }

        guard source.utf8.count <= maximumSourceBytes else {
            throw CompilationError(message: String(localized: "Less source exceeds the 2 MiB limit.", comment: "Userstyle compiler source size error"))
        }

#if DEBUG
        let bundle = compilerSourceOverride ?? loadCompilerBundle()
#else
        let bundle = loadCompilerBundle()
#endif
        guard let bundle else {
            throw CompilationError(message: String(localized: "Less compiler resource is missing.", comment: "Userstyle compiler resource error"))
        }

        let context = JSContext()!
        context.exceptionHandler = { _, exception in
            // The render callback carries the useful Less location; this handler
            // only prevents an uncaught bootstrap exception from being swallowed.
            _ = exception
        }

        // Deliberately provide only inert values needed by Less's browser wrapper.
        context.evaluateScript("""
            var window = this;
            var globalThis = this;
            var location = { href: 'file:///userstyle.less', hash: '' };
            var document = { currentScript: null, getElementsByTagName: function() { return []; } };
            var navigator = {};
            var XMLHttpRequest = undefined;
            var fetch = undefined;
            var WebSocket = undefined;
            var setTimeout = undefined;
            var clearTimeout = undefined;
            var setInterval = undefined;
            var clearInterval = undefined;
            var less = { onReady: false, env: 'production' };
        """)
        context.evaluateScript(bundle)
        if let exception = context.exception {
            throw CompilationError(message: exception.toString())
        }

        var globals: [String: String] = [:]
        for variable in variables {
            globals[variable.name] = variable.value
        }
        let request: [String: Any] = ["source": source, "variables": globals]
        guard let requestData = try? JSONSerialization.data(withJSONObject: request),
              let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw CompilationError(message: String(localized: "Less compiler input could not be serialized.", comment: "Userstyle compiler input serialization error"))
        }

        // The request is a JSON literal, so JavaScript sees only ordinary JS strings
        // and objects. No native bridge object crosses the bridge.
        let script = """
            (function(request) {
                var result = null;
                var failure = null;
                less.render(request.source, {
                    filename: 'file:///userstyle.less',
                    javascriptEnabled: false,
                    processImports: false,
                    globalVars: request.variables
                }, function(error, output) {
                    if (error) { failure = error; }
                    else { result = output && output.css; }
                });
                if (failure) {
                    return JSON.stringify({ error: (failure.message || String(failure)), line: failure.line, column: failure.column });
                }
                return JSON.stringify({ css: result });
            })(\(requestJSON))
        """
        guard let value = context.evaluateScript(script)?.toString(),
              let data = value.data(using: .utf8),
              let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            throw CompilationError(message: context.exception?.toString() ?? String(localized: "Less compilation failed.", comment: "Userstyle compiler failure"))
        }

        if let error = result["error"] as? String {
            let line = result["line"] as? Int
            let column = result["column"] as? Int
            let location = [
                line.map { String(localized: "line %@", comment: "Less compiler diagnostic line").replacingOccurrences(of: "%@", with: String($0)) },
                column.map { String(localized: "column %@", comment: "Less compiler diagnostic column").replacingOccurrences(of: "%@", with: String($0)) }
            ].compactMap { $0 }.joined(separator: ", ")
            throw CompilationError(message: location.isEmpty ? error : "\(location): \(error)")
        }
        guard let css = result["css"] as? String else {
            throw CompilationError(message: String(localized: "Less compiler returned no CSS.", comment: "Userstyle compiler empty output error"))
        }
        guard css.utf8.count <= maximumOutputBytes else {
            throw CompilationError(message: String(localized: "Less compiler output exceeds the 10 MiB limit.", comment: "Userstyle compiler output size error"))
        }
        return css
    }

    private static func loadCompilerBundle() -> String? {
        let bundleURL = Bundle(for: BundleMarker.self).url(
            forResource: "less.min", withExtension: "js", subdirectory: "UserStyleCompiler"
        ) ?? Bundle(for: BundleMarker.self).url(forResource: "less.min", withExtension: "js")
        guard let bundleURL else { return nil }
        return try? String(contentsOf: bundleURL, encoding: .utf8)
    }

    private final class BundleMarker: NSObject {}
}
