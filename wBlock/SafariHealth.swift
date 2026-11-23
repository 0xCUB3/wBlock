import Foundation
import SwiftUI
import wBlockCoreService

/// Whether this OS can query Safari's Web Extension enabled state.
/// Always `true` on macOS, and `#available(iOS 26.2, *)` on iOS.
/// Keyed strictly on OS capability, never on a transient `nil` read.
enum SafariExtensionCapability {
    static var isScriptsStateKnowable: Bool {
        #if os(macOS)
        return true
        #elseif os(iOS)
        if #available(iOS 26.2, *) {
            return true
        }
        return false
        #else
        return false
        #endif
    }
}

/// Anti-flicker hysteresis for the extension ring weld state.
///
/// Welds immediately when all knowable extensions read on. Once welded,
/// un-welds only after two consecutive off reads so a single transient
/// Safari XPC hiccup never flashes the degraded UI.
struct SafariExtensionHysteresis: Equatable, Sendable {
    private(set) var hasReadOnce = false
    private(set) var isWelded = false
    private(set) var consecutiveOffReads = 0
    private(set) var lastKnownBlockerStates: [Bool] = []
    private(set) var lastKnownScriptsEnabled: Bool?

    mutating func record(
        blockerStates: [Bool],
        rawScriptsEnabled: Bool?,
        isScriptsStateKnowable: Bool
    ) {
        hasReadOnce = true
        lastKnownBlockerStates = blockerStates
        if isScriptsStateKnowable {
            // Transient `nil` keeps the last known scripts state.
            if let rawScriptsEnabled {
                lastKnownScriptsEnabled = rawScriptsEnabled
            }
        } else {
            lastKnownScriptsEnabled = nil
        }

        let blockersAllOn = !blockerStates.isEmpty && blockerStates.allSatisfy { $0 }
        let scriptsSatisfied = !isScriptsStateKnowable || (lastKnownScriptsEnabled == true)
        let allKnowableOn = blockersAllOn && scriptsSatisfied

        if allKnowableOn {
            consecutiveOffReads = 0
            isWelded = true
        } else {
            consecutiveOffReads += 1
            if isWelded, consecutiveOffReads >= 2 {
                isWelded = false
            }
        }
    }

    var effectiveScriptsEnabled: Bool? {
        lastKnownScriptsEnabled
    }

    /// True after a single off read while still welded, awaiting a second read
    /// to confirm whether the extension is genuinely disabled.
    var isAwaitingOffConfirmation: Bool {
        hasReadOnce && isWelded && consecutiveOffReads == 1
    }
}

/// Pure input snapshot for `SafariHealthResolver`.
struct SafariHealthInput: Equatable, Sendable {
    var hasReadExtensions: Bool
    var blockerStates: [Bool]
    var scriptsEnabled: Bool?
    var isScriptsStateKnowable: Bool
    var isWelded: Bool
    var pausedComponents: BlockingPauseComponents
    var hasHitRuleLimit: Bool
    var isApplying: Bool
    var hasFailed: Bool
    var failedDuringUpdate: Bool
    var lastUpdatedDate: Date?
}

/// Priority-ordered protection health status shown by the Hero, compact
/// Advanced banner, Settings top row, and iOS bottom accessory.
enum SafariHealthStatus: Equatable, Sendable {
    case allBlockersOff
    case someBlockersOff
    case scriptsExtensionOff
    case paused(partial: Bool)
    case ruleLimitHit
    case applying
    case failed(isUpdate: Bool)
    case protected(lastUpdated: Date?)

    enum Action: Equatable, Sendable {
        case openSafariSettings
        case resume
        case reviewRuleLimit
        case tryAgain
    }

    enum Tone: Equatable, Sendable {
        case red
        case orange
        case gray
        case accent
        case green

        var color: Color {
            switch self {
            case .red: .red
            case .orange: .orange
            case .gray: .secondary
            case .accent: .accentColor
            case .green: Color(red: 0.16, green: 0.78, blue: 0.42)
            }
        }
    }

    var isProtected: Bool {
        if case .protected = self { return true }
        return false
    }

    var isExtensionDegraded: Bool {
        switch self {
        case .allBlockersOff, .someBlockersOff, .scriptsExtensionOff:
            return true
        default:
            return false
        }
    }

    var tone: Tone {
        switch self {
        case .allBlockersOff: .red
        case .someBlockersOff, .scriptsExtensionOff, .ruleLimitHit, .failed: .orange
        case .paused: .gray
        case .applying: .accent
        case .protected: .green
        }
    }

    var symbolName: String {
        switch self {
        case .allBlockersOff, .someBlockersOff, .scriptsExtensionOff, .ruleLimitHit, .failed:
            "exclamationmark.shield.fill"
        case .paused:
            "shield.slash.fill"
        case .applying:
            "shield.fill"
        case .protected:
            "checkmark.shield.fill"
        }
    }

    var title: String {
        switch self {
        case .allBlockersOff:
            NSLocalizedString("Turn on wBlock in Safari", comment: "Hero status title: all blockers off")
        case .someBlockersOff:
            NSLocalizedString("Finish turning on wBlock", comment: "Hero status title: some blockers off")
        case .scriptsExtensionOff:
            NSLocalizedString("Allow wBlock Scripts", comment: "Hero status title: scripts extension off")
        case .paused:
            NSLocalizedString("Protection paused", comment: "Hero status title: paused")
        case .ruleLimitHit:
            NSLocalizedString("Too many filters on", comment: "Hero status title: rule limit hit")
        case .applying:
            NSLocalizedString("Applying filters…", comment: "Hero status title: applying")
        case .failed(let isUpdate):
            isUpdate
                ? NSLocalizedString("Couldn't update filters", comment: "Hero status title: update failed")
                : NSLocalizedString("Couldn't apply your changes", comment: "Hero status title: apply failed")
        case .protected:
            NSLocalizedString("Protected", comment: "Hero status title: protected")
        }
    }

    func subtitle(now: Date = Date()) -> String {
        switch self {
        case .allBlockersOff:
            return NSLocalizedString("wBlock can't block anything until turned on in Safari's Extensions menu.", comment: "Hero status subtitle: all blockers off")
        case .someBlockersOff:
            return NSLocalizedString("One or more blockers are off; ads might get through.", comment: "Hero status subtitle: some blockers off")
        case .scriptsExtensionOff:
            return NSLocalizedString("Extras and some ad blocking need the wBlock Scripts extension enabled.", comment: "Hero status subtitle: scripts extension off")
        case .paused(let partial):
            return partial
                ? NSLocalizedString("Some blocking is paused right now; you can toggle it again to resume.", comment: "Hero status subtitle: partial pause")
                : NSLocalizedString("Blocking is paused right now; you can toggle it again to resume blocking.", comment: "Hero status subtitle: full pause")
        case .ruleLimitHit:
            return NSLocalizedString("Safari has reached its rule limit so some rules won't be loaded; try turning off a category.", comment: "Hero status subtitle: rule limit hit")
        case .applying:
            return NSLocalizedString("Applying your changes to Safari; this can take a few seconds.", comment: "Hero status subtitle: applying")
        case .failed:
            return NSLocalizedString("Something went wrong; try again to refresh Safari's blockers.", comment: "Hero status subtitle: failed")
        case .protected(let lastUpdated):
            guard let lastUpdated else {
                return NSLocalizedString("Blocking is on in Safari.", comment: "Hero status subtitle: protected without timestamp")
            }
            let relative: String
            if abs(now.timeIntervalSince(lastUpdated)) < 60 {
                relative = NSLocalizedString("just now", comment: "Hero relative update time")
            } else {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .full
                relative = formatter.localizedString(for: lastUpdated, relativeTo: now)
            }
            return String(
                format: NSLocalizedString("Lists updated %@", comment: "Hero status subtitle: protected with relative time"),
                relative
            )
        }
    }

    var ctaTitle: String? {
        switch action {
        case .openSafariSettings:
            NSLocalizedString("Open Safari Settings", comment: "Hero CTA")
        case .resume:
            NSLocalizedString("Resume", comment: "Hero CTA")
        case .reviewRuleLimit:
            NSLocalizedString("Review", comment: "Hero CTA")
        case .tryAgain:
            NSLocalizedString("Try Again", comment: "Hero CTA")
        case nil:
            nil
        }
    }

    var action: Action? {
        switch self {
        case .allBlockersOff, .someBlockersOff, .scriptsExtensionOff:
            .openSafariSettings
        case .paused:
            .resume
        case .ruleLimitHit:
            .reviewRuleLimit
        case .failed:
            .tryAgain
        case .applying, .protected:
            nil
        }
    }
}

/// Pure, priority-ordered resolver matching the 8-tier health hierarchy.
enum SafariHealthResolver {
    static func resolve(_ input: SafariHealthInput) -> SafariHealthStatus {
        if input.hasReadExtensions && !input.isWelded {
            if !input.blockerStates.isEmpty {
                if input.blockerStates.allSatisfy({ !$0 }) {
                    return .allBlockersOff
                }
                if input.blockerStates.contains(false) {
                    return .someBlockersOff
                }
            }
            if input.isScriptsStateKnowable && input.scriptsEnabled == false {
                return .scriptsExtensionOff
            }
        }
        if !input.pausedComponents.isEmpty {
            return .paused(partial: input.pausedComponents != .all)
        }
        if input.hasHitRuleLimit {
            return .ruleLimitHit
        }
        if input.isApplying {
            return .applying
        }
        if input.hasFailed {
            return .failed(isUpdate: input.failedDuringUpdate)
        }
        return .protected(lastUpdated: input.lastUpdatedDate)
    }
}

/// Single serialized Safari extension health monitor shared across the app.
/// Polls at 1 Hz ONLY while degraded and the window/scene is active; healthy
/// state refreshes once on `scenePhase == .active`.
@MainActor
final class SafariHealthMonitor: ObservableObject {
    @Published private(set) var blockerSlots: [SafariExtensionSetupSupport.ContentBlockerSlotState] = []
    @Published private(set) var scriptsExtensionEnabled: Bool?
    @Published private(set) var hysteresis = SafariExtensionHysteresis()
    @Published private(set) var weldCelebrationCount = 0

    let isScriptsStateKnowable: Bool
    private var isSceneActive = true
    private var isQuerying = false
    private var pollTask: Task<Void, Never>?

    init(isScriptsStateKnowable: Bool = SafariExtensionCapability.isScriptsStateKnowable) {
        self.isScriptsStateKnowable = isScriptsStateKnowable
    }

    deinit {
        pollTask?.cancel()
    }

    var arcStates: [Bool] {
        let slotBools: [Bool]
        if blockerSlots.isEmpty {
            slotBools = Array(repeating: hysteresis.isWelded, count: 5)
        } else {
            slotBools = blockerSlots.map(\.isEnabled)
        }
        if isScriptsStateKnowable {
            return slotBools + [scriptsExtensionEnabled == true]
        }
        return slotBools
    }

    var isDegraded: Bool {
        guard hysteresis.hasReadOnce else { return false }
        return !hysteresis.isWelded
    }

    private var needsActivePolling: Bool {
        guard hysteresis.hasReadOnce else { return false }
        return !hysteresis.isWelded || hysteresis.isAwaitingOffConfirmation
    }

    func setSceneActive(_ active: Bool) {
        let becameActive = active && !isSceneActive
        isSceneActive = active
        if active {
            if becameActive || !hysteresis.hasReadOnce {
                Task { [weak self] in
                    await self?.refreshNow()
                }
            } else if needsActivePolling {
                ensurePollingLoopIfNeeded()
            }
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    func startIfNeeded() {
        guard !hysteresis.hasReadOnce else {
            if isSceneActive && needsActivePolling { ensurePollingLoopIfNeeded() }
            return
        }
        Task { [weak self] in
            await self?.refreshNow()
        }
    }

    func refreshNow() async {
        guard !isQuerying else { return }
        isQuerying = true
        defer { isQuerying = false }

        let wasWelded = hysteresis.isWelded
        let hadRead = hysteresis.hasReadOnce

        let slots = await SafariExtensionSetupSupport.contentBlockerSlotStates()
        let rawScripts: Bool? = isScriptsStateKnowable
            ? await SafariExtensionSetupSupport.scriptsExtensionEnabledState()
            : nil

        blockerSlots = slots
        var next = hysteresis
        next.record(
            blockerStates: slots.map(\.isEnabled),
            rawScriptsEnabled: rawScripts,
            isScriptsStateKnowable: isScriptsStateKnowable
        )
        hysteresis = next
        scriptsExtensionEnabled = next.effectiveScriptsEnabled

        if hadRead && !wasWelded && next.isWelded {
            weldCelebrationCount += 1
        }

        if isSceneActive && (!next.isWelded || next.isAwaitingOffConfirmation) {
            ensurePollingLoopIfNeeded()
        } else if next.isWelded {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private func ensurePollingLoopIfNeeded() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            defer { self?.pollTask = nil }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { break }
                guard self.isSceneActive, self.needsActivePolling else { break }
                await self.refreshNow()
                if !self.needsActivePolling { break }
            }
        }
    }

    func status(
        pausedComponents: BlockingPauseComponents,
        hasHitRuleLimit: Bool,
        isApplying: Bool,
        hasFailed: Bool,
        failedDuringUpdate: Bool = false,
        lastUpdatedDate: Date?
    ) -> SafariHealthStatus {
        SafariHealthResolver.resolve(
            SafariHealthInput(
                hasReadExtensions: hysteresis.hasReadOnce,
                blockerStates: blockerSlots.map(\.isEnabled),
                scriptsEnabled: scriptsExtensionEnabled,
                isScriptsStateKnowable: isScriptsStateKnowable,
                isWelded: hysteresis.isWelded,
                pausedComponents: pausedComponents,
                hasHitRuleLimit: hasHitRuleLimit,
                isApplying: isApplying,
                hasFailed: hasFailed,
                failedDuringUpdate: failedDuringUpdate,
                lastUpdatedDate: lastUpdatedDate
            )
        )
    }
}
