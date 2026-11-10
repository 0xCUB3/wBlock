import Foundation

// The app's update check and apply must never overlap an in-process
// auto-update run. A run that started during a check closed the user's
// review sheet when it finished, and app work refused during a run was lost:
// an apply asked for as the foreground catch-up started never ran.
@main
struct ForegroundRunGateTests {
    static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    final class Flag: @unchecked Sendable { var count = 0 }

    static func main() {
        var gate = ForegroundRunGate()
        let resumed = Flag()
        let wait: @Sendable () -> Void = { resumed.count += 1 }
        expect(gate.beginForegroundWork(orWait: wait), "app work begins while no run is active")
        expect(!gate.startRun(), "a run cannot start during an update check")
        expect(gate.beginForegroundWork(orWait: wait), "an apply may start while a check holds the gate")
        gate.endForegroundWork()
        expect(!gate.startRun(), "a run waits until every piece of app work ends")
        gate.endForegroundWork()
        expect(gate.startRun(), "a run starts once app work ends")
        expect(!gate.beginForegroundWork(orWait: wait), "a check or apply waits during a run")
        expect(gate.foregroundWork == 0, "waiting app work holds nothing")
        expect(resumed.count == 0, "waiting app work is not resumed while the run goes on")
        gate.finishRun().forEach { $0() }
        expect(resumed.count == 1, "the run's end resumes the app work that waited")
        expect(gate.finishRun().isEmpty, "a second finish resumes nothing again")
        expect(gate.beginForegroundWork(orWait: wait), "the resumed app work claims the gate")
        expect(!gate.startRun(), "a new run waits for the resumed app work")
        gate.endForegroundWork()
        gate.endForegroundWork()
        expect(gate.foregroundWork == 0, "an extra release does not go negative")
        print("foreground run gate: ok")
    }
}
