import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum Haptic: Equatable, Sendable {
    case success
    case warning
    case failure
    case paused
    case resumed
    case found
    case upToDate
    case toggle
    case tap
}

@MainActor
enum Haptics {
    #if os(iOS)
    private static var lastPlayedAt: CFTimeInterval = 0
    private static let minimumInterval: CFTimeInterval = 0.1
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    #endif

    static func play(_ haptic: Haptic) {
        #if os(iOS)
        guard UIApplication.shared.applicationState == .active else { return }
        let now = CACurrentMediaTime()
        guard now - lastPlayedAt >= minimumInterval else { return }
        lastPlayedAt = now

        if #available(iOS 17.0, *) {
            HapticCenter.shared.emit(haptic)
        } else {
            playUIKit(haptic)
        }
        #endif
    }

    static func alignment() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }

    #if os(iOS)
    private static func playUIKit(_ haptic: Haptic) {
        switch haptic {
        case .success, .resumed:
            notificationGenerator.notificationOccurred(.success)
        case .warning:
            notificationGenerator.notificationOccurred(.warning)
        case .failure:
            notificationGenerator.notificationOccurred(.error)
        case .paused:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
        case .found:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
        case .upToDate:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
        case .toggle:
            selectionGenerator.selectionChanged()
        case .tap:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.6)
        }
    }
    #endif
}

#if os(iOS)
@available(iOS 17.0, *)
@MainActor
final class HapticCenter: ObservableObject {
    struct Pulse: Equatable {
        let id: UInt64
        let haptic: Haptic
    }

    static let shared = HapticCenter()
    @Published private(set) var pulse: Pulse?

    private var nextID: UInt64 = 0
    private var lastClaimedID: UInt64 = 0

    func emit(_ haptic: Haptic) {
        nextID &+= 1
        pulse = Pulse(id: nextID, haptic: haptic)
    }

    /// Multi-window iPad scenes each mount a host; only the first claims each pulse.
    func claim(_ id: UInt64) -> Bool {
        guard id != lastClaimedID else { return false }
        lastClaimedID = id
        return true
    }
}

@available(iOS 17.0, *)
private extension Haptic {
    var sensoryFeedback: SensoryFeedback {
        switch self {
        case .success: .success
        case .warning: .warning
        case .failure: .error
        case .paused: .stop
        case .resumed: .start
        case .found: .impact(weight: .medium, intensity: 0.7)
        case .upToDate: .impact(flexibility: .soft, intensity: 0.5)
        case .toggle: .selection
        case .tap: .impact(flexibility: .solid, intensity: 0.6)
        }
    }
}
#endif

struct HapticHostModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            content.modifier(IOS17HapticHostModifier())
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if os(iOS)
@available(iOS 17.0, *)
private struct IOS17HapticHostModifier: ViewModifier {
    @ObservedObject private var center = HapticCenter.shared

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: center.pulse) { _, newPulse in
            guard let newPulse, center.claim(newPulse.id) else { return nil }
            return newPulse.haptic.sensoryFeedback
        }
    }
}
#endif
