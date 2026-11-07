import Foundation
import wBlockCoreService

@main struct CloudSyncRemoteUserScriptTests {
  static func main() {
    // Tombstones and add generations are covered by scripts/proofs.
    let script = UserScript(name: "probe", url: URL(string: "https://example.com/probe.user.js"))
    for origin: UserScriptMutationOrigin in [.local, .remoteSync] {
      for isNew in [false, true] {
        let info = UserScriptManagerNotificationKey.userInfo(for: script, origin: origin, isNewAddition: isNew)
        precondition(UserScriptManagerNotificationKey.identifiesLocalAddition(info) == (origin == .local && isNew))
      }
    }
    precondition(!UserScriptManagerNotificationKey.identifiesLocalAddition(nil))
    precondition(
      !UserScriptManagerNotificationKey.identifiesLocalAddition([UserScriptManagerNotificationKey.isRemoteSync: false]))
    for url in [
      "https://cdn.jsdelivr.net/npm/@filteringdev/tinyshield@latest/dist/grouped/a/tinyShield-ar.user.js",
      "https://raw.githubusercontent.com/SysAdminDoc/YoutubeAdblock/main/YoutubeAdblock.user.js",
      "https://cdn.jsdelivr.net/gh/adamlui/youtube-classic/greasemonkey/youtube-classic.user.js",
      "https://cdn.jsdelivr.net/gh/adamlui/youtube-classic/dist/youtube-classic.user.js",
    ] {
      precondition(CloudSyncRemoteUserScriptReconciler.normalizedURL(" \(url) ").isEmpty)
      precondition(CloudSyncRemoteUserScriptReconciler.canonicalURL(url) == nil)
    }
    for url in [
      "https://codeberg.org/adamlui/youtube-classic/raw/branch/main/greasemonkey/youtube-classic.user.js",
      "https://scriptcat.org/scripts/code/6345/youtube-classic.user.js",
      "https://example.com/adamlui/youtube-classic/custom.user.js",
      "https://cdn.jsdelivr.net/npm/@filteringdev/tinyshield@latest/dist/tinyShield.user.js",
      "https://example.com/live.user.js",
    ] {
      precondition(CloudSyncRemoteUserScriptReconciler.normalizedURL(" \(url) ") == url)
      precondition(CloudSyncRemoteUserScriptReconciler.canonicalURL(url)?.absoluteString == url)
    }
    for name in ["tube-cleaner", "player-cleaner", "dark-reader"] {
      let old = "https://bundled.wblock.invalid/\(name).user.js"
      let canonical =
        "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/\(name)/dist/\(name).user.js"
      precondition(CloudSyncRemoteUserScriptReconciler.normalizedURL(" \(old) ") == canonical)
      precondition(CloudSyncRemoteUserScriptReconciler.canonicalURL(old)?.absoluteString == canonical)
      precondition(
        CloudSyncRemoteUserScriptReconciler.deletedURLsToMergeDuringRemoteApply(
          remoteDeletedURLs: [old], remoteRemoteScriptURLs: [canonical], localRemoteScriptURLs: []
        ).isEmpty)
    }
    print("PASS: userscript notifications and canonical URL migrations")
  }
}
