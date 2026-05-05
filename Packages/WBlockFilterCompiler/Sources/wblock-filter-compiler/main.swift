import Foundation
import WBlockFilterCompiler

struct CLIOptions {
    var diagnosticsOnly = false
    var uboCompat = false
    var pretty = false
    var advancedRuntime = false
    var lookupURL: URL?
    var outputURL: URL?
    var advancedOutputURL: URL?
    var inputPaths: [String] = []
}

struct ScriptletPayload: Encodable {
    var name: String
    var args: [String]
}

struct LookupPayload: Encodable {
    var url: String
    var css: [String]
    var extendedCss: [String]
    var js: [String]
    var scriptlets: [ScriptletPayload]
    var engineTimestamp: Double
}

func parseOptions(_ arguments: [String]) -> CLIOptions {
    var options = CLIOptions()
    var iterator = arguments.dropFirst().makeIterator()

    while let argument = iterator.next() {
        switch argument {
        case "--diagnostics-only":
            options.diagnosticsOnly = true
        case "--ubo-compat":
            options.uboCompat = true
        case "--pretty":
            options.pretty = true
        case "--advanced-runtime":
            options.advancedRuntime = true
        case "--lookup":
            if let urlString = iterator.next() {
                options.lookupURL = URL(string: urlString)
                options.advancedRuntime = true
            }
        case "--advanced-output":
            if let path = iterator.next() {
                options.advancedOutputURL = URL(fileURLWithPath: path)
            }
        case "--output", "-o":
            if let path = iterator.next() {
                options.outputURL = URL(fileURLWithPath: path)
            }
        case "--help", "-h":
            printUsageAndExit(status: 0)
        default:
            options.inputPaths.append(argument)
        }
    }

    return options
}

func printUsageAndExit(status: Int32) -> Never {
    FileHandle.standardError.write(
        Data(
            """
            Usage: wblock-filter-compiler [options] [filter-list.txt ...]

            Options:
              --diagnostics-only   Classify and diagnose without emitting Safari JSON.
              --ubo-compat         Enable uBO preprocessor identity for !#if ext_ublock blocks.
              --pretty             Pretty-print the summary JSON.
              --advanced-runtime   Compile scriptlets/procedural cosmetics into a WebExtension runtime bundle.
              --lookup URL         Print the native advanced-runtime payload for URL.
              --advanced-output PATH
                                   Write the advanced runtime JSON bundle to PATH.
              --output, -o PATH    Write Safari content blocker JSON to PATH.
              --help, -h           Show this help.

            If no input files are provided, stdin is read as one filter source.
            Summary JSON is printed to stdout unless --output is omitted, in which case Safari JSON is not printed.
            """.utf8
        )
    )
    exit(status)
}

func loadSources(paths: [String]) throws -> [FilterSource] {
    if paths.isEmpty {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return [FilterSource(identifier: "stdin", displayName: "stdin", text: text)]
    }

    return try paths.map { path in
        let url = URL(fileURLWithPath: path)
        return FilterSource(
            identifier: url.path,
            displayName: url.lastPathComponent,
            url: url,
            text: try String(contentsOf: url, encoding: .utf8)
        )
    }
}

func makeSummary(result: FilterCompilationResult) -> [String: Any] {
    var classified: [String: Int] = [:]
    for (kind, count) in result.diagnostics.classifiedRules {
        classified[kind.rawValue] = count
    }

    var unsupported: [String: Int] = [:]
    for rule in result.unsupportedRules {
        unsupported[rule.reason.rawValue, default: 0] += 1
    }

    return [
        "compilerVersion": result.fingerprints.compilerVersion,
        "totalLines": result.diagnostics.totalLines,
        "safariRuleCount": result.safariRuleCount,
        "advancedRuleCount": result.advancedRules.ruleCount,
        "classifiedRules": classified,
        "unsupportedRules": unsupported,
    ]
}

let options = parseOptions(CommandLine.arguments)

do {
    let sources = try loadSources(paths: options.inputPaths)
    var configuration = FilterCompilerConfiguration()
    configuration.target = options.diagnosticsOnly ? .diagnosticsOnly : .safariContentBlocker
    configuration.platform = options.uboCompat ? .uBlockOriginCompatibility : .safariCompatible
    if options.advancedRuntime {
        configuration.enabledCapabilities.insert(.advancedScriptlets)
        configuration.enabledCapabilities.insert(.proceduralCosmetics)
        configuration.enabledCapabilities.insert(.redirects)
        configuration.enabledCapabilities.insert(.headerModification)
    }

    let result = try NativeFilterCompiler().compile(sources, configuration: configuration)

    if let outputURL = options.outputURL {
        try result.safariRulesJSON.write(to: outputURL, atomically: true, encoding: .utf8)
    }
    if let advancedOutputURL = options.advancedOutputURL {
        try result.advancedRules.jsonString(prettyPrinted: options.pretty)
            .write(to: advancedOutputURL, atomically: true, encoding: .utf8)
    }

    if let lookupURL = options.lookupURL {
        let lookup = AdvancedRuleRuntime(bundle: result.advancedRules).lookup(pageURL: lookupURL)
        let payload = LookupPayload(
            url: lookupURL.absoluteString,
            css: lookup.css,
            extendedCss: lookup.extendedCss,
            js: lookup.js,
            scriptlets: lookup.scriptlets.map { ScriptletPayload(name: $0.name, args: $0.args) },
            engineTimestamp: lookup.engineTimestamp
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = options.pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(0)
    }

    let summary = makeSummary(result: result)
    let summaryData = try JSONSerialization.data(
        withJSONObject: summary,
        options: options.pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    )
    FileHandle.standardOutput.write(summaryData)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("wblock-filter-compiler: \(error)\n".utf8))
    exit(1)
}
