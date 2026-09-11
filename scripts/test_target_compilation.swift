import Foundation
import wBlockCoreService

@main
struct TargetCompilationTests {
    static func main() async {
        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: .macOS)
        func requests(deadline: Date? = nil, cancelled: Bool) -> [SharedAutoUpdateManager.TargetCompilationRequest] {
            targets.map {
                SharedAutoUpdateManager.TargetCompilationRequest(
                    target: $0, filters: [], allTargets: targets, disabledSites: [],
                    affinitySnapshot: SafariContentBlockerAffinitySnapshot(contentsByFilterID: [:]),
                    orderedFilters: [], extraRulesText: nil, deadline: deadline,
                    minimumTime: 12, isCancelled: { cancelled }
                )
            }
        }

        var delivered: [ContentBlockerTargetInfo] = []
        let cancelled = await SharedAutoUpdateManager.compileTargets(requests(cancelled: true)) {
            delivered.append($0.target)
        }
        precondition(cancelled.count == targets.count)
        precondition(Set(delivered) == Set(targets) && delivered.count == targets.count)
        precondition(cancelled.allSatisfy {
            $0.outcome == nil && $0.failureDescription == nil && $0.budgetExpired == nil
        })

        let expired = await SharedAutoUpdateManager.compileTargets(
            requests(deadline: Date().addingTimeInterval(-1), cancelled: false)
        )
        precondition(expired.count == targets.count)
        precondition(expired.allSatisfy { $0.budgetExpired == 0 && $0.outcome == nil })

        let empty = await SharedAutoUpdateManager.compileTargets([]) { _ in
            preconditionFailure("empty work must not deliver a result")
        }
        precondition(empty.isEmpty)
        let work = requests(cancelled: false)
        let stopped = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await SharedAutoUpdateManager.compileTargets(work)
        }.value
        precondition(stopped.allSatisfy { $0.outcome == nil })
        print("PASS: target compilation cancellation, budget, and result delivery")
    }
}
