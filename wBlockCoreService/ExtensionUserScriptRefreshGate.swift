import Foundation

/// Serializes opportunistic userscript refreshes started from the extension
/// so overlapping page loads do not run two update passes at once.
actor ExtensionUserScriptRefreshGate {
    private var isRunning = false

    func begin() -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        return true
    }

    func finish() {
        isRunning = false
    }
}
