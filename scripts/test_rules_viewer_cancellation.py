"""Run the viewer's initial task with an analyzer paused until the view closes."""
from pathlib import Path
import subprocess
import tempfile

source = Path("wBlock/FilterInfoView.swift").read_text()
start = source.index("        .task {", source.index("struct FilterRulesView")) + len("        .task {")
end = source.index("\n        }\n        .onChangeCompat(of: shownKinds)", start)
body = source[start:end]
core = Path("wBlockCoreService/FilterRuleAnalysis.swift").read_text()
def method_between(start, end):
    return core[core.index(start):core.index(end, core.index(start))]
rule_helpers = "\n".join([
    method_between("    public static func ruleSet", "    /// Fold only"),
    method_between("    public static func ruleIdentity", "    /// uBO"),
    method_between("    public static func isRuleLine", "    /// Classifies"),
])
harness = r'''import Foundation

final class Probe: @unchecked Sendable {
    let started = AsyncStream<Void>.makeStream()
    let release = DispatchSemaphore(value: 0)
    var observedCancellation = false
    var returnCompletedResult = false
}
var probe = Probe()

struct FilterRuleAnalysis: Sendable {
    let lines: [String]
RULE_HELPERS
    static func analyze(content: String, seenInEarlierLists: Set<String>, isCancelled: () -> Bool) -> Self {
        probe.started.continuation.yield(())
        probe.release.wait()
        probe.observedCancellation = isCancelled()
        return Self(lines: probe.observedCancellation && !probe.returnCompletedResult ? [] : [content])
    }
}
struct FilterListLoader {
    func readLocalFilterContent(_ filter: String) -> String? { "||ads.example^" }
}
@MainActor final class Editor {
    func replaceText(_ text: String, lineKinds: [Int: String], markClean: Bool) {}
}
@MainActor final class Harness {
    var rules = ""
    let filter = "sample"
    let editorController = Editor()
    var isLoading = true
    var analysis: FilterRuleAnalysis?
    var rebuildCount = 0
    func earlierListContents() -> [String] { ["||earlier.example^"] }
    func rebuildDisplayedText() { rebuildCount += 1 }
    func load() async {
BODY
    }
}
@main struct Test {
    @MainActor static func main() async {
        let rules = "! comment\n||EXAMPLE.com^\nexample.com##.Ad\n||last.example^"
        require(FilterRuleAnalysis.ruleSet(from: rules) == ["||example.com^", "example.com##.Ad", "||last.example^"], "default scan must preserve rule identities")
        var scanned = 0
        let interrupted = FilterRuleAnalysis.ruleSet(from: rules, isCancelled: {
            scanned += 1
            return scanned == 3
        })
        require(interrupted.isEmpty && scanned == 3, "cancelled earlier-list scan must stop without returning partial rules")
        for (cancel, completedResult) in [(true, false), (true, true), (false, false)] {
            probe = Probe()
            probe.returnCompletedResult = completedResult
            let view = Harness()
            let task = Task { await view.load() }
            var started = probe.started.stream.makeAsyncIterator()
            await started.next()
            if cancel { task.cancel() }
            probe.release.signal()
            await task.value
            if cancel {
                require(probe.observedCancellation, "closing the viewer must cancel its detached analyzer")
                require(view.analysis == nil && view.rebuildCount == 0, "closed viewer must not publish or rebuild")
            } else {
                require(!probe.observedCancellation, "active viewer must retain its worker")
                require(view.analysis?.lines == ["||ads.example^"] && view.rebuildCount == 1, "active viewer must publish and rebuild once")
            }
        }
        print("PASS rules viewer cancellation")
    }
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
}
'''.replace("BODY", body).replace("RULE_HELPERS", rule_helpers)
with tempfile.TemporaryDirectory(prefix="wblock-viewer-cancellation-") as temp:
    test = Path(temp) / "test.swift"
    test.write_text(harness)
    binary = str(Path(temp) / "test")
    subprocess.run(["swiftc", "-parse-as-library", str(test), "-o", binary], check=True)
    subprocess.run([binary], check=True, timeout=15)
