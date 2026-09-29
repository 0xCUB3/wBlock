import Foundation
import wBlockCoreService

@main
struct ApplyBaselineAcknowledgementTests {
    static func main() {
        func filter(_ name: String) -> FilterList {
            FilterList(name: name, url: URL(string: "https://example.com/\(name)")!, category: .ads)
        }
        let x = filter("x"), a = filter("a"), b = filter("b")
        let baseline = [ApplyFilterConfiguration(x)]
        let current = [x, a, b].map(ApplyFilterConfiguration.init)

        // Bulk add A then B; B's download fails first.
        var applied = ApplyFilterConfiguration.acknowledging(b.id, in: current, baseline: baseline)
        applied = ApplyFilterConfiguration.acknowledging(a.id, in: current, baseline: applied)
        precondition(applied == current, "reversed acknowledgements must match the current order")

        // Repeating an acknowledgement is idempotent.
        precondition(ApplyFilterConfiguration.acknowledging(a.id, in: current, baseline: applied) == current)

        // Unrelated pending edits stay pending: a removed filter and a rename are not acknowledged.
        let gone = filter("gone")
        let renamed = FilterList(id: x.id, name: "renamed", url: x.url, category: .ads)
        let pendingCurrent = [renamed, a].map(ApplyFilterConfiguration.init)
        let pendingBaseline = [x, gone].map(ApplyFilterConfiguration.init)
        let result = ApplyFilterConfiguration.acknowledging(a.id, in: pendingCurrent, baseline: pendingBaseline)
        precondition(result.map(\.id) == [x.id, a.id, gone.id], "only the acknowledged filter joins the baseline")
        precondition(result[0].name == "x" && result != pendingCurrent)
        print("PASS")
    }
}
