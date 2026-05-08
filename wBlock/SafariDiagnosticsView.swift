import SafariServices
import SwiftUI
import wBlockCoreService

struct SafariDiagnosticsView: View {
    @State private var result = SafariDiagnosticsResult.empty
    @State private var isRunning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                actionButtons

                Text("Checks whether Safari sees wBlock extensions, whether generated rules exist, and whether the Scripts extension recently synced dynamic DNR rules.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(result.items) { item in
                        SafariDiagnosticRow(item: item)
                    }
                }

                if !result.recommendations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recommendations")
                            .font(.headline)
                        ForEach(result.recommendations, id: \.self) { recommendation in
                            Text(recommendation)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Safari Diagnostics")
        .task {
            if result.items.isEmpty {
                runChecks()
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        #if os(macOS)
        HStack(spacing: 10) {
            runChecksButton
                .frame(width: 220)
            openSafariSettingsButton
                .frame(width: 280)
            Spacer(minLength: 0)
        }
        #else
        VStack(spacing: 10) {
            runChecksButton
            openSafariSettingsButton
        }
        #endif
    }

    private var runChecksButton: some View {
        Button {
            runChecks()
        } label: {
            Label(isRunning ? "Running Checks…" : "Run Checks", systemImage: "stethoscope")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isRunning)
    }

    private var openSafariSettingsButton: some View {
        Button {
            SafariExtensionSetupSupport.openScriptsExtensionSettings()
        } label: {
            Label("Open Safari Extension Settings", systemImage: "gear")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func runChecks() {
        guard !isRunning else { return }
        isRunning = true
        Task {
            let fresh = await SafariDiagnosticsRunner.run()
            await MainActor.run {
                result = fresh
                isRunning = false
            }
        }
    }
}

private struct SafariDiagnosticsResult: Equatable {
    var items: [SafariDiagnosticItem]
    var recommendations: [String]

    static let empty = SafariDiagnosticsResult(items: [], recommendations: [])
}

private struct SafariDiagnosticItem: Identifiable, Equatable {
    enum Status: Equatable {
        case pass
        case warn
        case fail
        case unknown

        var systemImage: String {
            switch self {
            case .pass: return "checkmark.circle.fill"
            case .warn: return "exclamationmark.triangle.fill"
            case .fail: return "xmark.circle.fill"
            case .unknown: return "questionmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .pass: return .green
            case .warn: return .orange
            case .fail: return .red
            case .unknown: return .secondary
            }
        }
    }

    let id = UUID()
    var title: String
    var detail: String
    var status: Status

    static func == (lhs: SafariDiagnosticItem, rhs: SafariDiagnosticItem) -> Bool {
        lhs.title == rhs.title && lhs.detail == rhs.detail && lhs.status == rhs.status
    }
}

private struct SafariDiagnosticRow: View {
    let item: SafariDiagnosticItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.status.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(item.status.color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body)
                Text(item.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum SafariDiagnosticsRunner {
    static func run() async -> SafariDiagnosticsResult {
        var items: [SafariDiagnosticItem] = []
        var recommendations: [String] = []

        let scriptsEnabled = await SafariExtensionSetupSupport.scriptsExtensionEnabledState()
        switch scriptsEnabled {
        case true:
            items.append(.init(title: String(localized: "Scripts Extension"), detail: String(localized: "Safari reports the Scripts extension is enabled."), status: .pass))
        case false:
            items.append(.init(title: String(localized: "Scripts Extension"), detail: String(localized: "Safari reports the Scripts extension is disabled."), status: .fail))
            recommendations.append(String(localized: "Enable wBlock Scripts in Safari Extensions settings and allow it on all websites."))
        case nil:
            items.append(.init(title: String(localized: "Scripts Extension"), detail: String(localized: "Safari did not return Scripts extension state."), status: .unknown))
            recommendations.append(String(localized: "Open Safari Extensions settings and confirm wBlock Scripts is enabled."))
        }

        let contentBlockerItems = await contentBlockerStateItems()
        items.append(contentsOf: contentBlockerItems.items)
        recommendations.append(contentsOf: contentBlockerItems.recommendations)

        let fileItems = generatedRuleFileItems()
        items.append(contentsOf: fileItems.items)
        recommendations.append(contentsOf: fileItems.recommendations)

        let advanced = nativeAdvancedRuntimeItem()
        items.append(advanced.item)
        if let recommendation = advanced.recommendation {
            recommendations.append(recommendation)
        }

        let dnr = recentDNRSyncItem()
        items.append(dnr.item)
        if let recommendation = dnr.recommendation {
            recommendations.append(recommendation)
        }

        return SafariDiagnosticsResult(items: items, recommendations: Array(NSOrderedSet(array: recommendations)) as? [String] ?? recommendations)
    }

    private static func contentBlockerStateItems() async -> (items: [SafariDiagnosticItem], recommendations: [String]) {
        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
        var enabled = 0
        var disabledNames: [String] = []
        var unknownNames: [String] = []

        for target in targets {
            let state = await contentBlockerEnabledState(identifier: target.bundleIdentifier)
            switch state {
            case true: enabled += 1
            case false: disabledNames.append(target.displayName)
            case nil: unknownNames.append(target.displayName)
            }
        }

        let detail = String.localizedStringWithFormat(
            NSLocalizedString("%d of %d content blockers enabled", comment: "Safari diagnostics content blocker state"),
            enabled,
            targets.count
        )
        let status: SafariDiagnosticItem.Status = enabled == targets.count ? .pass : (enabled == 0 ? .fail : .warn)
        var item = SafariDiagnosticItem(title: String(localized: "Content Blockers"), detail: detail, status: status)
        if !disabledNames.isEmpty {
            item.detail += " · " + String.localizedStringWithFormat(NSLocalizedString("Disabled: %@", comment: "Safari diagnostics disabled content blockers"), disabledNames.joined(separator: ", "))
        }
        if !unknownNames.isEmpty {
            item.detail += " · " + String.localizedStringWithFormat(NSLocalizedString("Unknown: %@", comment: "Safari diagnostics unknown content blockers"), unknownNames.joined(separator: ", "))
        }

        let recommendations = enabled == targets.count ? [] : [String(localized: "Enable all wBlock content blockers in Safari Extensions settings.")]
        return ([item], recommendations)
    }

    private static func contentBlockerEnabledState(identifier: String) async -> Bool? {
        await ContentBlockerService.contentBlockerStateSnapshot(withIdentifier: identifier).isEnabled
    }

    private static func generatedRuleFileItems() -> (items: [SafariDiagnosticItem], recommendations: [String]) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) else {
            return ([.init(title: String(localized: "Generated Rule Files"), detail: String(localized: "Could not open the wBlock app group container."), status: .fail)], [])
        }

        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
        var present = 0
        var totalRules = 0
        var missing: [String] = []
        for target in targets {
            let url = containerURL.appendingPathComponent(target.rulesFilename)
            guard FileManager.default.fileExists(atPath: url.path),
                  let count = safariRuleCount(at: url) else {
                missing.append(target.displayName)
                continue
            }
            present += 1
            totalRules += count
        }

        let detail = String.localizedStringWithFormat(
            NSLocalizedString("%d of %d files present · %@ Safari rules", comment: "Safari diagnostics generated rule files"),
            present,
            targets.count,
            totalRules.formatted()
        )
        let status: SafariDiagnosticItem.Status = present == targets.count && totalRules > 0 ? .pass : .warn
        var recommendations: [String] = []
        if status != .pass {
            recommendations.append(String(localized: "Apply changes in wBlock to regenerate Safari content blocker files."))
        }
        if !missing.isEmpty {
            recommendations.append(String.localizedStringWithFormat(NSLocalizedString("Missing rule files for: %@", comment: "Safari diagnostics missing rule files"), missing.joined(separator: ", ")))
        }
        return ([.init(title: String(localized: "Generated Rule Files"), detail: detail, status: status)], recommendations)
    }

    private static func safariRuleCount(at url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        return array.count
    }

    private static func nativeAdvancedRuntimeItem() -> (item: SafariDiagnosticItem, recommendation: String?) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) else {
            return (.init(title: String(localized: "Advanced Runtime"), detail: String(localized: "Could not locate the advanced runtime file."), status: .unknown), nil)
        }
        let url = containerURL.appendingPathComponent("wblock_native_advanced_runtime.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (.init(title: String(localized: "Advanced Runtime"), detail: String(localized: "No native advanced runtime file found. This is expected unless native uBlock compatibility lists are enabled."), status: .warn), String(localized: "Enable native uBlock compatibility lists and apply changes to build advanced runtime rules."))
        }
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (.init(title: String(localized: "Advanced Runtime"), detail: String(localized: "The advanced runtime file could not be parsed."), status: .fail), String(localized: "Apply changes to rebuild the advanced runtime file."))
        }
        let jsCount = (object["js"] as? [Any])?.count ?? 0
        let scriptletCount = (object["scriptlets"] as? [Any])?.count ?? 0
        let dnrCount = (object["dnrRules"] as? [Any])?.count ?? 0
        let detail = String.localizedStringWithFormat(
            NSLocalizedString("%@ JS · %@ scriptlets · %@ dynamic DNR rules", comment: "Safari diagnostics advanced runtime counts"),
            jsCount.formatted(),
            scriptletCount.formatted(),
            dnrCount.formatted()
        )
        return (.init(title: String(localized: "Advanced Runtime"), detail: detail, status: .pass), nil)
    }

    private static func recentDNRSyncItem() -> (item: SafariDiagnosticItem, recommendation: String?) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) else {
            return (.init(title: String(localized: "Dynamic DNR Sync"), detail: String(localized: "Could not open the wBlock app group container."), status: .unknown), nil)
        }
        let logURL = containerURL.appendingPathComponent("web_extension.log")
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else {
            return (.init(title: String(localized: "Dynamic DNR Sync"), detail: String(localized: "No Scripts extension diagnostics have been recorded yet."), status: .warn), String(localized: "Open any website in Safari, then run these checks again."))
        }
        let lines = text.split(separator: "\n").suffix(200).map(String.init)
        if let latest = lines.last(where: { $0.contains("event=dnr_sync") }) {
            let status: SafariDiagnosticItem.Status = latest.contains("outcome=success") ? .pass : .fail
            return (.init(title: String(localized: "Dynamic DNR Sync"), detail: latest, status: status), status == .pass ? nil : String(localized: "Open Safari Extensions settings and confirm wBlock Scripts has website permissions."))
        }
        return (.init(title: String(localized: "Dynamic DNR Sync"), detail: String(localized: "No dynamic DNR sync event found in recent Scripts extension logs."), status: .warn), String(localized: "Open any website in Safari, then run these checks again."))
    }

    private static var currentPlatform: Platform {
        #if os(iOS)
        return .iOS
        #else
        return .macOS
        #endif
    }
}
