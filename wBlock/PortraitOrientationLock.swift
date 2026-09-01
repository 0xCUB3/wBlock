import Foundation
#if os(iOS)
import UIKit
#endif

/// Device-local preference that can pin the iOS app to portrait.
///
/// See GitHub issue #558. Default is unlocked so iPhone landscape and iPad
/// rotation keep matching the supported interface orientations Info.plist keys.
enum PortraitOrientationLock {
    static let storageKey = "lockPortraitOrientation"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }

    #if os(iOS)
    static var mask: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .all
        }
        return isEnabled ? .portrait : .allButUpsideDown
    }

    @MainActor
    static func apply() {
        let orientations = mask
        if #available(iOS 16.0, *) {
            for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in }
            }
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
    #endif
}
