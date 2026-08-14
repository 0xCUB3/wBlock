//
//  UserStyleCompiler.swift
//  wBlockCoreService
//
//  Compiler-neutral UserCSS preprocessing seam. Less is the only backend shipped in
//  this phase; the request/artifact types deliberately do not expose Less details.
//

import CryptoKit
import Foundation
import JavaScriptCore

public struct UserStyleCompilationRequest: Sendable, Hashable {
    public let source: String
    public let preprocessor: String
    public let variables: [UserStyleSupport.Variable]
    public let options: [String: String]
    /// Digest of the authoritative raw source. `source` may be the metadata-stripped
    /// compiler input while this identity remains tied to the persisted source.
    public let sourceDigest: String

    public init(source: String, preprocessor: String, variables: [UserStyleSupport.Variable], options: [String: String] = [:], sourceDigest: String? = nil) {
        self.source = source
        self.preprocessor = preprocessor
        self.variables = variables
        self.options = options
        self.sourceDigest = sourceDigest ?? UserStylePreprocessorService.digest(source)
    }
}

public struct UserStyleCompiledArtifact: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let sourceDigest: String
    public let preprocessor: String
    public let compilerRevision: String
    public let optionsDigest: String
    public let compiledBodyDigest: String
    public let body: String

    public init(request: UserStyleCompilationRequest, compilerRevision: String, body: String) {
        self.schemaVersion = Self.currentSchemaVersion
        self.sourceDigest = request.sourceDigest
        self.preprocessor = UserStylePreprocessorService.normalize(request.preprocessor)
        self.compilerRevision = compilerRevision
        self.optionsDigest = UserStylePreprocessorService.optionsDigest(request.options)
        self.compiledBodyDigest = UserStylePreprocessorService.digest(body)
        self.body = body
    }
}

public protocol UserStylePreprocessorBackend: Sendable {
    var preprocessor: String { get }
    var compilerRevision: String { get }
    var maximumSourceBytes: Int { get }
    var maximumOutputBytes: Int { get }
    func compile(_ request: UserStyleCompilationRequest) throws -> String
}

public enum UserStylePreprocessorService {
    public static let lessRevision = "less-4.9.0-wblock-1"

    public static func normalize(_ preprocessor: String) -> String {
        let value = preprocessor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty ? "default" : value
    }

    public static func optionsDigest(_ options: [String: String]) -> String {
        let canonical = options.keys.sorted().map { "\($0)=\(options[$0] ?? "")" }.joined(separator: "\n")
        return digest(canonical)
    }

    public static func digest(_ source: String) -> String {
        SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func backend(for preprocessor: String) -> (any UserStylePreprocessorBackend)? {
        switch normalize(preprocessor) {
        case "less": return LessUserStylePreprocessorBackend()
        default: return nil
        }
    }

    public static func requiresCompilation(_ preprocessor: String) -> Bool {
        backend(for: preprocessor) != nil
    }

    public static func compilerRevision(for preprocessor: String) -> String? {
        backend(for: preprocessor)?.compilerRevision
    }

    public static func limits(for preprocessor: String) -> (source: Int, output: Int)? {
        guard let backend = backend(for: preprocessor) else { return nil }
        return (backend.maximumSourceBytes, backend.maximumOutputBytes)
    }

    public static func request(source: String, authoritativeContent: String, preprocessor: String, variables: [UserStyleSupport.Variable], options: [String: String] = [:]) -> UserStyleCompilationRequest {
        UserStyleCompilationRequest(source: source, preprocessor: preprocessor, variables: variables, options: options, sourceDigest: digest(authoritativeContent))
    }

    public static func validate(_ artifact: UserStyleCompiledArtifact, for request: UserStyleCompilationRequest) -> Bool {
        guard let backend = backend(for: request.preprocessor),
              artifact.schemaVersion == UserStyleCompiledArtifact.currentSchemaVersion,
              artifact.sourceDigest == request.sourceDigest,
              artifact.preprocessor == normalize(request.preprocessor),
              artifact.compilerRevision == backend.compilerRevision,
              artifact.optionsDigest == optionsDigest(request.options),
              artifact.compiledBodyDigest == digest(artifact.body),
              request.source.utf8.count <= backend.maximumSourceBytes,
              artifact.body.utf8.count <= backend.maximumOutputBytes
        else { return false }
        return true
    }

    public static func compile(_ request: UserStyleCompilationRequest) throws -> UserStyleCompiledArtifact {
        guard let backend = backend(for: request.preprocessor) else {
            throw UserStyleCompiler.CompilationError(message: "Unsupported userstyle preprocessor")
        }
        let body = try backend.compile(request)
        return UserStyleCompiledArtifact(request: request, compilerRevision: backend.compilerRevision, body: body)
    }
}

private struct LessUserStylePreprocessorBackend: UserStylePreprocessorBackend {
    let preprocessor = "less"
    let compilerRevision = UserStylePreprocessorService.lessRevision
    let maximumSourceBytes = UserStyleCompiler.maximumSourceBytes
    let maximumOutputBytes = UserStyleCompiler.maximumOutputBytes

    func compile(_ request: UserStyleCompilationRequest) throws -> String {
        try UserStyleCompiler.compile(request.source, variables: request.variables)
    }
}

enum UserStyleCompiler {
    struct CompilationError: Error, LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }
    }

    private static let renderLock = NSLock()
    static let maximumSourceBytes = 2 * 1024 * 1024
    static let maximumOutputBytes = 10 * 1024 * 1024

#if DEBUG
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
        context.exceptionHandler = { _, exception in _ = exception }
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
        if let exception = context.exception { throw CompilationError(message: exception.toString()) }

        var globals: [String: String] = [:]
        for variable in variables { globals[variable.name] = variable.value }
        let request: [String: Any] = ["source": source, "variables": globals]
        guard let requestData = try? JSONSerialization.data(withJSONObject: request),
              let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw CompilationError(message: String(localized: "Less compiler input could not be serialized.", comment: "Userstyle compiler input serialization error"))
        }

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
              let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw CompilationError(message: context.exception?.toString() ?? String(localized: "Less compilation failed.", comment: "Userstyle compiler failure"))
        }
        if let error = result["error"] as? String {
            let line = result["line"] as? Int
            let column = result["column"] as? Int
            let location: String
            if let line, let column {
                location = "\(String(localized: "line \(line)")), \(String(localized: "column \(column)"))"
            } else if let line {
                location = String(localized: "line \(line)")
            } else if let column {
                location = String(localized: "column \(column)")
            } else {
                location = ""
            }
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
        let bundleURL = Bundle(for: BundleMarker.self).url(forResource: "less.min", withExtension: "js", subdirectory: "UserStyleCompiler")
            ?? Bundle(for: BundleMarker.self).url(forResource: "less.min", withExtension: "js")
        guard let bundleURL else { return nil }
        return try? String(contentsOf: bundleURL, encoding: .utf8)
    }

    private final class BundleMarker: NSObject {}
}
