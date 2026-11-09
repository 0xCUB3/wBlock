import Foundation

// The app's update check and apply must never overlap an in-process
// auto-update run. A run that started during a check closed the user's
// review sheet when it finished.
@main
struct ForegroundRunGateTests {
    static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        var gate = ForegroundRunGate()
        expect(gate.beginForegroundWork(), "app work begins while no run is active")
        expect(!gate.startRun(), "a run cannot start during an update check")
        expect(gate.beginForegroundWork(), "an apply may start while a check holds the gate")
        gate.endForegroundWork()
        expect(!gate.startRun(), "a run waits until every piece of app work ends")
        gate.endForegroundWork()
        expect(gate.startRun(), "a run starts once app work ends")
        expect(!gate.beginForegroundWork(), "a check or apply is refused during a run")
        expect(gate.foregroundWork == 0, "a refused claim holds nothing")
        gate.finishRun()
        expect(gate.beginForegroundWork(), "app work begins after the run finishes")
        gate.endForegroundWork()
        gate.endForegroundWork()
        expect(gate.foregroundWork == 0, "an extra release does not go negative")
        print("foreground run gate: ok")
    }
}
