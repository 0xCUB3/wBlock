import Foundation
import wBlockCoreService

#if os(macOS)
final class LifetimeState: @unchecked Sendable {
    let lock = NSLock()
    var events: [String] = []
    func record(_ event: String) { lock.lock(); events.append(event); lock.unlock() }
    func snapshot() -> [String] { lock.lock(); defer { lock.unlock() }; return events }
}

actor LifetimeGate {
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

@main struct FilterUpdateWorkLifetimeTests {
    static func main() async {
        let state = LifetimeState()
        let gate = LifetimeGate()
        FilterUpdateWorkLifetime.start(
            acknowledge: { state.record("acknowledged/disconnected") },
            begin: { state.record("begin") },
            end: { state.record("end") }
        ) {
            await gate.wait()
            state.record("published")
        }
        precondition(state.snapshot() == ["begin", "acknowledged/disconnected"])
        await gate.release()
        for _ in 0..<200 {
            if state.snapshot().last == "end" { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(state.snapshot() == ["begin", "acknowledged/disconnected", "published", "end"])
        // Exercise the actual SDK transaction pair as well as the ordering seam.
        await withCheckedContinuation { continuation in
            FilterUpdateWorkLifetime.start { continuation.resume() }
        }
        print("PASS: service owns work before acknowledgement through final publication")
    }
}
#endif
