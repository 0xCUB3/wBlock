import Foundation
import wBlockCoreService

/// The Apply sheet's Reload stat comes from one reload pass. A pass where
/// Safari already had every blocker's rules still spends time checking each
/// one, and must report that time instead of zero.
@main
struct ReloadPassTimingTests {
    static func result(skipped: Bool) -> ContentBlockerService.ReloadAttemptResult {
        .init(success: true, skipped: skipped, attempts: skipped ? 0 : 1, durationMs: 0)
    }

    static func main() async {
        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: .iOS)
        precondition(targets.count >= 2)

        let verified = await ContentBlockerReloadPolicy.reloadPass(targets, groupIdentifier: "test", reload: { _ in
            try? await Task.sleep(nanoseconds: 60_000_000)
            return result(skipped: true)
        })
        precondition(verified.results.count == targets.count)
        let minimum = targets.count * 50
        precondition(
            verified.durationMs >= minimum,
            "all-skipped pass reported \(verified.durationMs)ms, expected at least \(minimum)ms"
        )

        // Targets finish out of order; the pass still returns only after the
        // slowest one, so its time is known before anyone reads it.
        let slowest = targets.max { $0.slot < $1.slot }!
        var delivered: [String] = []
        let outOfOrder = await ContentBlockerReloadPolicy.reloadPass(
            targets, groupIdentifier: "test", maxConcurrent: targets.count,
            reload: { target in
                let delay = target.bundleIdentifier == slowest.bundleIdentifier ? 300 : 20
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
                return result(skipped: target.bundleIdentifier != slowest.bundleIdentifier)
            },
            onResult: { delivered.append($0.target.bundleIdentifier) }
        )
        precondition(delivered.last == slowest.bundleIdentifier && delivered.count == targets.count)
        precondition(outOfOrder.durationMs >= 250, "out-of-order pass reported \(outOfOrder.durationMs)ms")

        // A warm pass with nothing to check adds no fixed delay. Compared with the
        // sleeping pass above rather than a wall-clock limit, which shared CI
        // runners overshoot.
        let warm = await ContentBlockerReloadPolicy.reloadPass(targets, groupIdentifier: "test", reload: { _ in
            result(skipped: true)
        })
        precondition(warm.durationMs < minimum, "warm pass reported \(warm.durationMs)ms")
        print("reload pass timing: ok (verified \(verified.durationMs)ms, out of order \(outOfOrder.durationMs)ms, warm \(warm.durationMs)ms)")
    }
}
