import Foundation

public enum WBlockFilterCompilerInfo {
    public static let version = "0.1.0-dev"
}

public protocol FilterCompiling: Sendable {
    func compile(
        _ sources: [FilterSource],
        configuration: FilterCompilerConfiguration
    ) throws -> FilterCompilationResult
}

public struct FilterCompilerConfiguration: Sendable, Equatable {
    public var dialects: Set<FilterDialect>
    public var target: CompilationTarget
    public var platform: FilterPlatform
    public var safariVersion: SafariCompatibilityVersion
    public var enabledCapabilities: Set<CompilerCapability>
    public var strictMode: Bool
    public var preprocessConditionals: Bool

    public init(
        dialects: Set<FilterDialect> = [.auto],
        target: CompilationTarget = .safariContentBlocker,
        platform: FilterPlatform = .safariCompatible,
        safariVersion: SafariCompatibilityVersion = .autodetect,
        enabledCapabilities: Set<CompilerCapability> = [.nativeCosmeticRules],
        strictMode: Bool = true,
        preprocessConditionals: Bool = true
    ) {
        self.dialects = dialects
        self.target = target
        self.platform = platform
        self.safariVersion = safariVersion
        self.enabledCapabilities = enabledCapabilities
        self.strictMode = strictMode
        self.preprocessConditionals = preprocessConditionals
    }
}

public enum FilterDialect: Sendable, Hashable {
    case abp
    case uBlockOrigin
    case adGuard
    case hosts
    case auto
}

public enum CompilationTarget: Sendable, Hashable {
    case safariContentBlocker
    case safariWebExtensionAdvanced
    case diagnosticsOnly
}

public enum FilterPlatform: Sendable, Hashable {
    /// Conservative Safari mode. Does not opt into uBO-only preprocessor sections.
    case safariCompatible

    /// Safari target with uBO compatibility enabled. Unsupported uBO-only rules must be diagnosed.
    case uBlockOriginCompatibility
}

public enum SafariCompatibilityVersion: Sendable, Hashable {
    case autodetect
    case safari(Int)
}

public enum CompilerCapability: Sendable, Hashable {
    case nativeCosmeticRules
    case advancedScriptlets
    case proceduralCosmetics
    case declarativeNetRequest
    case removeQueryParameters
    case redirects
    case headerModification
}

public struct FilterSource: Sendable, Equatable {
    public var identifier: String
    public var displayName: String
    public var url: URL?
    public var text: String

    public init(identifier: String, displayName: String, url: URL? = nil, text: String) {
        self.identifier = identifier
        self.displayName = displayName
        self.url = url
        self.text = text
    }
}

public struct FilterCompilationResult: Sendable, Equatable {
    public var safariRulesJSON: String
    public var safariRuleCount: Int
    public var advancedRules: AdvancedRuleBundle
    public var diagnostics: CompilationDiagnostics
    public var unsupportedRules: [UnsupportedRule]
    public var fingerprints: CompilationFingerprints

    public init(
        safariRulesJSON: String,
        safariRuleCount: Int,
        advancedRules: AdvancedRuleBundle,
        diagnostics: CompilationDiagnostics,
        unsupportedRules: [UnsupportedRule],
        fingerprints: CompilationFingerprints
    ) {
        self.safariRulesJSON = safariRulesJSON
        self.safariRuleCount = safariRuleCount
        self.advancedRules = advancedRules
        self.diagnostics = diagnostics
        self.unsupportedRules = unsupportedRules
        self.fingerprints = fingerprints
    }
}

public struct CompilationDiagnostics: Sendable, Equatable {
    public var totalLines: Int
    public var emittedSafariRules: Int
    public var classifiedRules: [RuleKind: Int]
    public var messages: [DiagnosticMessage]

    public init(
        totalLines: Int = 0,
        emittedSafariRules: Int = 0,
        classifiedRules: [RuleKind: Int] = [:],
        messages: [DiagnosticMessage] = []
    ) {
        self.totalLines = totalLines
        self.emittedSafariRules = emittedSafariRules
        self.classifiedRules = classifiedRules
        self.messages = messages
    }
}

public enum RuleKind: String, Sendable, Hashable, Comparable {
    case comment
    case preprocessor
    case network
    case networkException
    case cosmetic
    case cosmeticException
    case scriptlet
    case scriptletException
    case proceduralCosmetic
    case htmlFiltering
    case unsupported

    public static func < (lhs: RuleKind, rhs: RuleKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct DiagnosticMessage: Sendable, Equatable {
    public var sourceIdentifier: String
    public var line: Int
    public var severity: DiagnosticSeverity
    public var message: String

    public init(sourceIdentifier: String, line: Int, severity: DiagnosticSeverity, message: String) {
        self.sourceIdentifier = sourceIdentifier
        self.line = line
        self.severity = severity
        self.message = message
    }
}

public enum DiagnosticSeverity: Sendable, Hashable {
    case info
    case warning
    case error
}

public struct UnsupportedRule: Sendable, Equatable {
    public var sourceIdentifier: String
    public var line: Int
    public var text: String
    public var reason: UnsupportedReason

    public init(sourceIdentifier: String, line: Int, text: String, reason: UnsupportedReason) {
        self.sourceIdentifier = sourceIdentifier
        self.line = line
        self.text = text
        self.reason = reason
    }
}

public enum UnsupportedReason: String, Sendable, Hashable {
    case cosmeticExceptionNeedsPlanner
    case denyAllowNeedsPlanner
    case headerModificationNeedsAdvancedRuntime
    case htmlFiltering
    case mixedDomainOptionsNeedSplitting
    case noSafariEquivalent
    case proceduralCosmeticRequiresAdvancedRuntime
    case redirectsRequireAdvancedRuntime
    case removeParamRequiresAdvancedRuntime
    case responseBodyReplacement
    case responseHeaderFiltering
    case scriptletRequiresAdvancedRuntime
    case unknownModifier
    case unknownSyntax
}

public struct CompilationFingerprints: Sendable, Equatable {
    public var compilerVersion: String

    public init(compilerVersion: String = WBlockFilterCompilerInfo.version) {
        self.compilerVersion = compilerVersion
    }
}
