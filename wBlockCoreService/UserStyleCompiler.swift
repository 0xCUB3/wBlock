//
//  UserStyleCompiler.swift
//  wBlockCoreService
//
// Offline, compiler-neutral UserCSS preprocessing. Each compilation creates a
// fresh JavaScriptCore context and exposes only the selected vendored bridge.
//

import CryptoKit
import Foundation
import JavaScriptCore

public struct UserStyleCompilationRequest: Sendable, Hashable {
    public let source: String
    public let preprocessor: String
    public let variables: [UserStyleSupport.Variable]
    public let options: [String: String]
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
        schemaVersion = Self.currentSchemaVersion
        sourceDigest = request.sourceDigest
        preprocessor = UserStylePreprocessorService.normalize(request.preprocessor)
        self.compilerRevision = compilerRevision
        optionsDigest = UserStylePreprocessorService.optionsDigest(request.options)
        compiledBodyDigest = UserStylePreprocessorService.digest(body)
        self.body = body
    }
}

public protocol UserStylePreprocessorBackend: Sendable {
    var preprocessor: String { get }
    var compilerRevision: String { get }
    var maximumSourceBytes: Int { get }
    var maximumOutputBytes: Int { get }
    var consumesVariables: Bool { get }
    func compile(_ request: UserStyleCompilationRequest) throws -> String
}

public enum UserStylePreprocessorService {
    public static let lessRevision = "less-4.9.0-wblock-1"
    public static let sassRevision = "sass-scss-1.102.0-wblock-1"
    public static let stylusRevision = "stylus-0.64.0-wblock-1-bounded-offline"
    public static let postCSSRevision = "postcss-8.5.26-postcss-nested-8.0.1-wblock-1"
    public static let maximumSourceBytes = 2 * 1024 * 1024
    public static let maximumOutputBytes = 10 * 1024 * 1024

    public static func normalize(_ preprocessor: String) -> String {
        let value = preprocessor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty ? "default" : value
    }

    public static func optionsDigest(_ options: [String: String]) -> String {
        digest(options.keys.sorted().map { "\($0)=\(options[$0] ?? "")" }.joined(separator: "\n"))
    }

    public static func digest(_ source: String) -> String {
        SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func backend(for preprocessor: String) -> (any UserStylePreprocessorBackend)? {
        switch normalize(preprocessor) {
        case "less": return LessBackend()
        case "sass": return SassBackend(syntax: "sass")
        case "scss": return SassBackend(syntax: "scss")
        case "stylus": return StylusBackend()
        case "postcss": return PostCSSBackend()
        default: return nil
        }
    }

    public static func requiresCompilation(_ preprocessor: String) -> Bool { backend(for: preprocessor) != nil }
    public static func compilerRevision(for preprocessor: String) -> String? { backend(for: preprocessor)?.compilerRevision }
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
              UserStyleCompiler.serializedInputSize(request) <= backend.maximumSourceBytes,
              artifact.body.utf8.count <= backend.maximumOutputBytes else { return false }
        return true
    }

    public static func compile(_ request: UserStyleCompilationRequest) throws -> UserStyleCompiledArtifact {
        guard let backend = backend(for: request.preprocessor) else {
            throw UserStyleCompiler.CompilationError(message: String(localized: "Userstyle compiler failed.", comment: "Generic userstyle compiler failure"))
        }
        guard request.source.utf8.count <= backend.maximumSourceBytes,
              UserStyleCompiler.serializedInputSize(request) <= backend.maximumSourceBytes else {
            throw UserStyleCompiler.CompilationError(message: String(localized: "Userstyle source exceeds the 2 MiB limit.", comment: "Userstyle compiler source size error"))
        }
        return UserStyleCompiledArtifact(request: request, compilerRevision: backend.compilerRevision, body: try backend.compile(request))
    }
}

private struct LessBackend: UserStylePreprocessorBackend {
    let preprocessor = "less"
    let compilerRevision = UserStylePreprocessorService.lessRevision
    let maximumSourceBytes = UserStylePreprocessorService.maximumSourceBytes
    let maximumOutputBytes = UserStylePreprocessorService.maximumOutputBytes
    let consumesVariables = true
    func compile(_ request: UserStyleCompilationRequest) throws -> String {
        try UserStyleCompiler.compileLess(request.source, variables: request.variables)
    }
}

private struct SassBackend: UserStylePreprocessorBackend {
    let syntax: String
    var preprocessor: String { syntax }
    let compilerRevision = UserStylePreprocessorService.sassRevision
    let maximumSourceBytes = UserStylePreprocessorService.maximumSourceBytes
    let maximumOutputBytes = UserStylePreprocessorService.maximumOutputBytes
    let consumesVariables = true
    func compile(_ request: UserStyleCompilationRequest) throws -> String {
        var variables: [String: String] = [:]
        for variable in request.variables { variables[variable.name] = variable.value }
        let prepared = UserStyleCompiler.prepareSassSource(request.source, syntax: syntax)
        let css = try UserStyleCompiler.callJSONBridge(resource: "wblock-sass-1.102.0.min", extension: "js", function: "wblockSassCompile", request: ["source": prepared.source, "syntax": syntax, "variables": variables])
        return UserStyleCompiler.restoreSassDocumentRules(css, preludes: prepared.preludes)
    }
}

private struct StylusBackend: UserStylePreprocessorBackend {
    let preprocessor = "stylus"
    let compilerRevision = UserStylePreprocessorService.stylusRevision
    let maximumSourceBytes = UserStylePreprocessorService.maximumSourceBytes
    let maximumOutputBytes = UserStylePreprocessorService.maximumOutputBytes
    let consumesVariables = true
    func compile(_ request: UserStyleCompilationRequest) throws -> String {
        let variables = Dictionary(uniqueKeysWithValues: request.variables.map { ($0.name, $0.value) })
        return try UserStyleCompiler.callObjectBridge(resource: "stylus-jsc", extension: "js", function: "StylusCompile", request: ["source": request.source, "variables": variables])
    }
}

private struct PostCSSBackend: UserStylePreprocessorBackend {
    let preprocessor = "postcss"
    let compilerRevision = UserStylePreprocessorService.postCSSRevision
    let maximumSourceBytes = UserStylePreprocessorService.maximumSourceBytes
    let maximumOutputBytes = UserStylePreprocessorService.maximumOutputBytes
    let consumesVariables = false
    func compile(_ request: UserStyleCompilationRequest) throws -> String {
        // UserCSS variables are intentionally not PostCSS plugin options. The fixed
        // nested plugin has no arbitrary-plugin, preset-env, or autoprefixer surface.
        try UserStyleCompiler.callJSONBridge(resource: "wblock-postcss-nested", extension: "js", function: "wblockPostcssNested", request: ["source": request.source, "variables": request.options])
    }
}

enum UserStyleCompiler {
    struct CompilationError: Error, LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }
    }

    static let maximumSourceBytes = UserStylePreprocessorService.maximumSourceBytes
    static let maximumOutputBytes = UserStylePreprocessorService.maximumOutputBytes
    private static let renderLock = NSLock()
#if DEBUG
    /// Test-only resource-name overrides; production always loads packaged resources.
    static var compilerSourceOverrides: [String: String] = [:]
    static var compilerSourceOverride: String?
#endif

    static func serializedInputSize(_ request: UserStyleCompilationRequest) -> Int {
        serializedInputSize(source: request.source, metadata: [
            "preprocessor": request.preprocessor,
            "variables": request.variables.map { ["name": $0.name, "value": $0.value] },
            "options": request.options
        ])
    }

    private static func serializedInputSize(source: String, metadata: [String: Any]) -> Int {
        guard let data = try? JSONSerialization.data(withJSONObject: metadata) else { return Int.max }
        return source.utf8.count + data.count
    }

    private static func jsonLiteral(_ request: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    static func compile(_ source: String, variables: [UserStyleSupport.Variable]) throws -> String {
        try compileLess(source, variables: variables)
    }

    static func compileLess(_ source: String, variables: [UserStyleSupport.Variable]) throws -> String {
        let globals = Dictionary(uniqueKeysWithValues: variables.map { ($0.name, $0.value) })
        let request: [String: Any] = ["source": source, "variables": globals]
        guard serializedInputSize(source: source, metadata: ["variables": globals]) <= maximumSourceBytes else {
            throw CompilationError(message: String(localized: "Userstyle source exceeds the 2 MiB limit.", comment: "Userstyle compiler source size error"))
        }
        renderLock.lock(); defer { renderLock.unlock() }
#if DEBUG
        let bundle = compilerSourceOverrides["less.min"] ?? compilerSourceOverride ?? loadCompilerBundle("less.min", extension: "js")
#else
        let bundle = loadCompilerBundle("less.min", extension: "js")
#endif
        guard let bundle else { throw CompilationError(message: String(localized: "Userstyle compiler resource is missing.", comment: "Userstyle compiler resource error")) }
        let context = freshContext(needsLessBrowserShim: true)
        context.evaluateScript(bundle)
        guard context.exception == nil else {
            throw CompilationError(message: context.exception?.toString() ?? String(localized: "Userstyle compiler resource failed to load.", comment: "Userstyle compiler load error"))
        }
        guard let requestJSON = jsonLiteral(request) else { throw CompilationError(message: String(localized: "Userstyle compiler input could not be serialized.", comment: "Userstyle compiler serialization error")) }
        let script = """
        (function(request) {
            var result = null, failure = null;
            less.render(request.source, {filename:'file:///userstyle.less', javascriptEnabled: false, processImports: false, globalVars:request.variables}, function(error, output) {
                if (error) failure = {message: error.message || String(error), line: error.line, column: error.column};
                else result = output && output.css;
            });
            return JSON.stringify(failure ? {error: failure} : {css: result});
        })(\(requestJSON))
        """
        guard let value = context.evaluateScript(script)?.toString(),
              let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw CompilationError(message: String(localized: "Userstyle compiler returned an invalid response.", comment: "Userstyle compiler response error")) }
        if let error = object["error"] as? [String: Any] { throw formattedError(error, fallback: String(localized: "Userstyle compiler failed.", comment: "Generic userstyle compiler failure")) }
        guard let result = object["css"] as? String else { throw CompilationError(message: String(localized: "Userstyle compiler returned no CSS.", comment: "Userstyle compiler empty output error")) }
        guard result.utf8.count <= maximumOutputBytes else { throw CompilationError(message: String(localized: "Userstyle compiler output exceeds the 10 MiB limit.", comment: "Userstyle compiler output size error")) }
        return result
    }

    static func callJSONBridge(resource: String, extension: String, function: String, request: [String: Any]) throws -> String {
        let source = request["source"] as? String ?? ""
        var metadata = request
        metadata.removeValue(forKey: "source")
        guard serializedInputSize(source: source, metadata: metadata) <= maximumSourceBytes,
              let requestJSON = jsonLiteral(request) else { throw CompilationError(message: String(localized: "Userstyle compiler input could not be serialized.", comment: "Userstyle compiler serialization error")) }
        let context = try loadedContext(resource: resource, extension: `extension`)
        let script = "(function(){ var r = (typeof \(function) === 'function') ? \(function)(\(requestJSON)) : null; return typeof r === 'string' ? r : JSON.stringify(r); })()"
        guard let value = context.evaluateScript(script)?.toString(), let output = value.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: output) as? [String: Any] else { throw CompilationError(message: String(localized: "Userstyle compiler returned an invalid response.", comment: "Userstyle compiler response error")) }
        if let error = object["error"] as? String { throw CompilationError(message: format(error: error, line: object["line"], column: object["column"])) }
        if let error = object["error"] as? [String: Any] { throw formattedError(error, fallback: String(localized: "Userstyle compiler failed.", comment: "Generic userstyle compiler failure")) }
        guard let css = object["css"] as? String else { throw CompilationError(message: String(localized: "Userstyle compiler returned no CSS.", comment: "Userstyle compiler empty output error")) }
        guard css.utf8.count <= maximumOutputBytes else { throw CompilationError(message: String(localized: "Userstyle compiler output exceeds the 10 MiB limit.", comment: "Userstyle compiler output size error")) }
        return css
    }

    static func callObjectBridge(resource: String, extension: String, function: String, request: [String: Any]) throws -> String {
        try callJSONBridge(resource: resource, extension: `extension`, function: function, request: request)
    }

    private static func loadedContext(resource: String, extension: String) throws -> JSContext {
        renderLock.lock(); defer { renderLock.unlock() }
#if DEBUG
        let bundle = compilerSourceOverrides[resource] ?? loadCompilerBundle(resource, extension: `extension`)
#else
        let bundle = loadCompilerBundle(resource, extension: `extension`)
#endif
        guard let bundle else { throw CompilationError(message: String(localized: "Userstyle compiler resource is missing.", comment: "Userstyle compiler resource error")) }
        let context = freshContext(); context.evaluateScript(bundle)
        if let exception = context.exception { throw CompilationError(message: exception.toString() ?? String(localized: "Userstyle compiler resource failed to load.", comment: "Userstyle compiler load error")) }
        return context
    }

    private static func freshContext(needsLessBrowserShim: Bool = false) -> JSContext {
        let context = JSContext()!
        context.exceptionHandler = { _, _ in }
        if needsLessBrowserShim {
            // Inert JavaScript values required by Less's browser UMD bootstrap.
            // They expose no native object, DOM, network, filesystem, or timer.
            context.evaluateScript("var window = this; var globalThis = this; var location = { href: 'file:///userstyle.less', hash: '' }; var document = { currentScript: null, getElementsByTagName: function() { return []; } };")
        }
        return context
    }

    static func prepareSassSource(_ source: String, syntax: String) -> (source: String, preludes: [String]) {
        let lines = source.components(separatedBy: "\n")
        var output: [String] = []
        var preludes: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
            let trimmed = String(line.dropFirst(indentation.count))
            guard trimmed.hasPrefix("@-moz-document ") else {
                output.append(line); index += 1; continue
            }
            var captured = trimmed
            var end = index
            // SCSS conditions may span arbitrary lines; do not cut at the first
            // line until the opening brace has actually been seen.
            if syntax == "scss" {
                while !hasOpeningBrace(captured), end + 1 < lines.count {
                    end += 1
                    captured += "\n" + lines[end]
                }
            } else {
                while captured.trimmingCharacters(in: .whitespacesAndNewlines)
                        .hasSuffix(","),
                      end + 1 < lines.count
                {
                    end += 1
                    captured += "\n"
                        + lines[end].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            let marker = "__wblock_document_\(preludes.count)__"
            let prelude = captured.firstIndex(of: "{").map { String(captured[..<$0]).trimmingCharacters(in: .whitespacesAndNewlines) } ?? captured.trimmingCharacters(in: .whitespacesAndNewlines)
            preludes.append(prelude)
            let braceSuffix = captured.firstIndex(of: "{").map { String(captured[$0...]) } ?? (syntax == "scss" ? " {" : "")
            output.append(indentation + "@media \(marker)" + braceSuffix)
            index = end + 1
        }
        return (output.joined(separator: "\n"), preludes)
    }

    private static func hasOpeningBrace(_ text: String) -> Bool {
        var quote: Character?
        var escaped = false
        for character in text {
            if escaped { escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if quote != nil {
                if character == quote { quote = nil }
            } else if character == "\"" || character == "'" { quote = character
            } else if character == "{" { return true }
        }
        return false
    }

    static func restoreSassDocumentRules(_ css: String, preludes: [String]) -> String {
        var result = css
        for (index, prelude) in preludes.enumerated() {
            let marker = "@media __wblock_document_\(index)__"
            guard let markerRange = result.range(of: marker) else { continue }
            let lineEnd = result[markerRange.upperBound...].firstIndex(of: "\n")
                ?? result.endIndex
            guard let brace = result.range(
                of: "{",
                range: markerRange.upperBound..<lineEnd
            ) else { continue }
            result.replaceSubrange(
                markerRange.lowerBound..<brace.upperBound,
                with: prelude + " {"
            )
        }
        return result
    }

    private static func formattedError(_ error: [String: Any], fallback: String) -> CompilationError {
        let message = error["message"] as? String ?? fallback
        return CompilationError(message: format(error: message, line: error["line"], column: error["column"]))
    }

    private static func format(error: String, line: Any?, column: Any?) -> String {
        let lineNumber = (line as? NSNumber)?.intValue
        let columnNumber = (column as? NSNumber)?.intValue
        if let lineNumber, let columnNumber {
            return String(format: String(localized: "line %@, column %@: %@", comment: "Userstyle compiler diagnostic location"), "\(lineNumber)", "\(columnNumber)", error)
        }
        if let lineNumber {
            return String(format: String(localized: "line %@: %@", comment: "Userstyle compiler diagnostic location"), "\(lineNumber)", error)
        }
        if let columnNumber {
            return String(format: String(localized: "column %@: %@", comment: "Userstyle compiler diagnostic location"), "\(columnNumber)", error)
        }
        return error
    }

    private static func loadCompilerBundle(_ name: String, extension: String) -> String? {
        let bundle = Bundle(for: BundleMarker.self)
        guard let url = bundle.url(forResource: name, withExtension: `extension`, subdirectory: "UserStyleCompiler") ?? bundle.url(forResource: name, withExtension: `extension`) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private final class BundleMarker: NSObject {}
}
