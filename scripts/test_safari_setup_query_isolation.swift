import Foundation
import ObjectiveC
import SafariServices
import wBlockCoreService

// Compile with SafariExtensionSetupSupport.swift and the built core framework.
// Replace Safari only in this test process; never contact the user's extensions.
private final class QueryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var offMainCalls = 0

    func record() {
        lock.lock()
        defer { lock.unlock() }
        calls += 1
        if !Thread.isMainThread { offMainCalls += 1 }
    }

    func verify(expected: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        print("Safari queries: \(calls), off-main: \(offMainCalls)")
        return calls == expected && offMainCalls == 0
    }
}

@main
struct SafariSetupQueryIsolationTests {
    static func main() {
        let probe = QueryProbe()
        let blockerSelector = #selector(SFContentBlockerManager.getStateOfContentBlocker(withIdentifier:completionHandler:))
        let scriptsSelector = #selector(SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier:completionHandler:))
        guard let blockerMethod = class_getClassMethod(SFContentBlockerManager.self, blockerSelector),
              let scriptsMethod = class_getClassMethod(SFSafariExtensionManager.self, scriptsSelector) else {
            fatalError("Safari query methods unavailable")
        }

        let blocker: @convention(block) (AnyObject, NSString, @escaping @convention(block) (SFContentBlockerState?, NSError?) -> Void) -> Void = { _, _, completion in
            probe.record()
            DispatchQueue.global().async {
                completion(nil, NSError(domain: "TestSafariUnavailable", code: 1))
            }
        }
        let scripts: @convention(block) (AnyObject, NSString, @escaping @convention(block) (SFSafariExtensionState?, NSError?) -> Void) -> Void = { _, _, completion in
            probe.record()
            DispatchQueue.global().async {
                completion(nil, NSError(domain: "TestSafariUnavailable", code: 1))
            }
        }
        let blockerIMP = imp_implementationWithBlock(blocker)
        let scriptsIMP = imp_implementationWithBlock(scripts)
        let originalBlocker = method_setImplementation(blockerMethod, blockerIMP)
        let originalScripts = method_setImplementation(scriptsMethod, scriptsIMP)
        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: .macOS)
        let rounds = 64

        Task.detached {
            let valid = await withTaskGroup(of: Bool.self) { group in
                for _ in 0..<rounds {
                    group.addTask {
                        let states = await SafariExtensionSetupSupport.contentBlockerSlotStates(forPlatform: .macOS)
                        let enabled = await SafariExtensionSetupSupport.allContentBlockersEnabled(forPlatform: .macOS)
                        let scriptsEnabled = await SafariExtensionSetupSupport.scriptsExtensionEnabledState()
                        return states.map(\.bundleIdentifier) == targets.map(\.bundleIdentifier)
                            && states.allSatisfy { !$0.isEnabled }
                            && !enabled && scriptsEnabled == nil
                    }
                }
                var valid = true
                for await result in group { valid = result && valid }
                return valid
            }
            let isolated = probe.verify(expected: rounds * (2 * targets.count + 1))
            method_setImplementation(blockerMethod, originalBlocker)
            method_setImplementation(scriptsMethod, originalScripts)
            imp_removeBlock(blockerIMP)
            imp_removeBlock(scriptsIMP)
            print(valid && isolated ? "PASS: concurrent Safari setup queries stay on main and preserve error results" : "FAIL: Safari setup query isolation or result handling")
            exit(valid && isolated ? 0 : 1)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            print("FAIL: Safari query test timed out")
            exit(1)
        }
        RunLoop.main.run()
    }
}
