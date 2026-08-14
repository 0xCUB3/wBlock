import Foundation

@main
struct CompilerTimeoutTests {
    static func main() {
#if DEBUG
        UserStyleCompiler.debugDeadlineOverride = 0.25
        UserStyleCompiler.compilerSourceOverrides = ["less.min": "while (true) {}"]
        let timedOut = DispatchSemaphore(value: 0)
        var timeoutError: Error?
        DispatchQueue.global().async {
            do { _ = try UserStyleCompiler.compile("body { color: red; }", variables: []) }
            catch { timeoutError = error }
            timedOut.signal()
        }
        let timeoutDeadline = Date().addingTimeInterval(5)
        while timedOut.wait(timeout: .now()) == .timedOut && Date() < timeoutDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(Date() < timeoutDeadline, "timeout probe exceeded wall bound")
        precondition(timeoutError?.localizedDescription.contains("timed out") == true, "missing localized timeout error")

        UserStyleCompiler.compilerSourceOverrides = ["less.min":
            "if (typeof fetch !== 'undefined' || typeof XMLHttpRequest !== 'undefined' || " +
            "typeof WebSocket !== 'undefined' || typeof importScripts !== 'undefined' || " +
            "typeof navigator !== 'undefined' || typeof crypto !== 'undefined' || " +
            "typeof BroadcastChannel !== 'undefined' || typeof webkit !== 'undefined') " +
            "{ throw new Error('worker capability leak'); } " +
            "self.less={render:function(source, options, callback){callback(null,{css:source});}}"
        ]
        let recovered = DispatchSemaphore(value: 0)
        var recoveredCSS: String?
        DispatchQueue.global().async {
            recoveredCSS = try? UserStyleCompiler.compile("body { color: red; }", variables: [])
            recovered.signal()
        }
        let recoveryDeadline = Date().addingTimeInterval(5)
        while recovered.wait(timeout: .now()) == .timedOut && Date() < recoveryDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(Date() < recoveryDeadline, "recovery compile exceeded wall bound")
        precondition(recoveredCSS?.contains("color: red") == true, "compile did not recover after timeout")
        print("PASS: compiler timeout/recovery")
#endif
    }
}
